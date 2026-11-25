import Foundation
import ZapretMacKit

// ZapretMacHelper, the root helper for Transparent mode. launchd starts it
// from Contents/Library/LaunchDaemons/com.gorlev.zapretmac.helper.plist
// once the person approves it in System Settings > Login Items.
//
//   ZapretMacHelper                     run as the XPC daemon (launchd only)
//   ZapretMacHelper --print-rules <port> print the pf anchor and tpws command it would use, then exit
//   ZapretMacHelper --validate <args…>   check tpws arguments like the daemon does; exit 0 if allowed
//   ZapretMacHelper --requirement        print the code requirement it puts on clients

let args = Array(CommandLine.arguments.dropFirst())

switch args.first {
case "--print-rules":
    guard args.count == 2, let port = Int(args[1]), (1024...65535).contains(port) else {
        print("usage: ZapretMacHelper --print-rules <port 1024-65535>")
        exit(2)
    }
    print("anchor: \(HelperInfo.anchor)")
    print(PFRules.anchorText(port: port), terminator: "")
    print("tpws: \(Paths.tpws.path) \(Transparent.fixedArguments(port: port).joined(separator: " "))")
    exit(0)
case "--validate":
    let folders = HelperArguments.allowedFolders(home: NSHomeDirectory())
    if let problem = HelperArguments.problem(in: Array(args.dropFirst()), allowedFolders: folders) {
        print("refused: \(problem)")
        exit(1)
    }
    print("allowed")
    exit(0)
case "--requirement":
    if let team = Signing.teamID(), let requirement = ClientRequirement.string(teamID: team) {
        print(requirement)
        exit(0)
    }
    print("no team: the helper is not signed with a team certificate")
    exit(1)
case .some(let other):
    print("unknown option \(other)")
    exit(2)
case nil:
    break
}

guard getuid() == 0 else {
    print("ZapretMacHelper runs as a launchd daemon. Use --print-rules or --validate to test it.")
    exit(1)
}

// A crash or reboot can leave our anchor behind: flush it first, always.
Transparent.shared.recoverAtLaunch()

let delegate = ListenerDelegate()
let listener = NSXPCListener(machServiceName: HelperInfo.machServiceName)
listener.delegate = delegate
listener.resume()
log.info("helper ready, protocol \(HelperInfo.protocolVersion)")
dispatchMain()
