import Foundation
import Security
import ZapretMacKit
import os

/// Accepts XPC connections only from the ZapretMac app signed by the
/// helper's own team.
final class ListenerDelegate: NSObject, NSXPCListenerDelegate {
    private let requirement: String? = Signing.teamID().flatMap { ClientRequirement.string(teamID: $0) }

    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        guard let requirement else {
            log.error("refused a connection: the helper has no signing team")
            return false
        }
        // The system checks every message against this requirement and
        // invalidates the connection when the client does not meet it.
        connection.setCodeSigningRequirement(requirement)
        let home = Self.home(of: connection.effectiveUserIdentifier)
        let service = HelperService(connectionID: ObjectIdentifier(connection), home: home)
        connection.exportedInterface = NSXPCInterface(with: ZapretHelperProtocol.self)
        connection.exportedObject = service
        let id = ObjectIdentifier(connection)
        connection.invalidationHandler = {
            // S-082: the app quit or crashed while Transparent mode was on.
            Transparent.shared.ownerGone(id)
        }
        connection.interruptionHandler = {
            Transparent.shared.ownerGone(id)
        }
        connection.resume()
        log.info("accepted a connection from uid \(connection.effectiveUserIdentifier)")
        return true
    }

    private static func home(of uid: uid_t) -> String {
        guard let entry = getpwuid(uid), let dir = entry.pointee.pw_dir else { return "/var/empty" }
        return String(cString: dir)
    }
}

/// One per connection; the shared state lives in `Transparent`.
final class HelperService: NSObject, ZapretHelperProtocol, Sendable {
    let connectionID: ObjectIdentifier
    let home: String

    init(connectionID: ObjectIdentifier, home: String) {
        self.connectionID = connectionID
        self.home = home
    }

    func version(reply: @escaping @Sendable (Int) -> Void) {
        reply(HelperInfo.protocolVersion)
    }

    func status(reply: @escaping @Sendable (Bool, Int, Bool, Int32) -> Void) {
        let status = Transparent.shared.status()
        reply(status.running, status.port, status.pfTokenPresent, status.tpwsPID)
    }

    func startTransparent(port: Int, arguments: [String], reply: @escaping @Sendable (String?) -> Void) {
        reply(Transparent.shared.start(port: port, arguments: arguments, home: home, owner: connectionID))
    }

    func stopTransparent(reply: @escaping @Sendable (String?) -> Void) {
        reply(Transparent.shared.cleanUp(reason: "stop"))
    }

    func cleanUp(reply: @escaping @Sendable (String?) -> Void) {
        reply(Transparent.shared.cleanUp(reason: "clean up"))
    }
}

enum Signing {
    /// The team identifier the running helper is signed with, nil when ad hoc.
    static func teamID() -> String? {
        var code: SecCode?
        guard SecCodeCopySelf([], &code) == errSecSuccess, let code else { return nil }
        var staticCode: SecStaticCode?
        guard SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode else { return nil }
        var info: CFDictionary?
        guard SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess,
              let dict = info as? [String: Any] else { return nil }
        return dict[kSecCodeInfoTeamIdentifier as String] as? String
    }

    /// True when the file is signed by `team` and meets `identifier`.
    static func isSigned(_ url: URL, identifier: String, team: String) -> Bool {
        var staticCode: SecStaticCode?
        guard SecStaticCodeCreateWithPath(url as CFURL, [], &staticCode) == errSecSuccess, let staticCode else { return false }
        let text = "identifier \"\(identifier)\" and anchor apple generic and certificate leaf[subject.OU] = \"\(team)\""
        var requirement: SecRequirement?
        guard SecRequirementCreateWithString(text as CFString, [], &requirement) == errSecSuccess, let requirement else { return false }
        return SecStaticCodeCheckValidity(staticCode, SecCSFlags(rawValue: kSecCSCheckAllArchitectures), requirement) == errSecSuccess
    }
}

enum Paths {
    /// tpws in the same app bundle: Contents/MacOS/ZapretMacHelper -> Contents/Helpers/tpws.
    /// Never a path the client sends.
    static var tpws: URL {
        let executable = (Bundle.main.executableURL ?? URL(fileURLWithPath: CommandLine.arguments[0])).resolvingSymlinksInPath()
        return executable.deletingLastPathComponent().deletingLastPathComponent().appending(path: "Helpers/tpws")
    }

    /// Survives a helper crash, not a reboot (pf forgets its tokens on reboot too).
    static let state = URL(fileURLWithPath: "/var/run/com.gorlev.zapretmac.helper.state")
}
