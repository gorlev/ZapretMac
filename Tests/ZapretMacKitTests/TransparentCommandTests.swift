import Foundation
import Testing
@testable import ZapretMacKit

/// S-081: the app must never send the helper something it refuses. Every
/// strategy the app can run, in Transparent mode, passes the helper's check.
@Suite("Transparent mode command (S-081)")
struct TransparentCommandTests {
    static let home = "/Users/me"
    static let data = "/Users/me/Library/Application Support/ZapretMac"
    static let testData = "/tmp/ZapretMac-self-3.store-files"
    let folders = HelperArguments.allowedFolders(home: home)

    /// The forms each strategy takes in the app: both scopes, with and
    /// without Never Touch, verbose log on and off, real and test folders.
    func commands(for strategy: [String]) -> [TPWSCommand] {
        var out: [TPWSCommand] = []
        for folder in [Self.data, Self.testData] {
            for scope in Scope.allCases {
                for exclude in [nil, "\(folder)/hostlist-exclude.txt"] {
                    for debug in [true, false] {
                        out.append(TPWSCommand(port: 1088, strategy: strategy, scope: scope,
                                               hostlistPath: "\(folder)/hostlist.txt", excludePath: exclude,
                                               debug: debug, pidFile: "\(folder)/tpws.pid", mode: .transparent))
                    }
                }
            }
        }
        return out
    }

    func expectAccepted(_ strategy: [String], _ label: String) {
        for command in commands(for: strategy) {
            let arguments = command.arguments
            #expect(HelperArguments.problem(in: arguments, allowedFolders: folders) == nil, "\(label): \(arguments)")
            for forbidden in ["--socks", "--port", "--bind-addr", "--pidfile", "--user", "--daemon", "--uid"] {
                #expect(!arguments.contains { $0 == forbidden || $0.hasPrefix(forbidden + "=") }, "\(label) has \(forbidden)")
            }
        }
    }

    @Test func everyPresetPasses() {
        for preset in Preset.all { expectAccepted(preset.options.arguments, preset.id) }
    }

    @Test func everyScanTryPasses() {
        for url in ["https://example.com", "http://example.com"] {
            for scan in ScanPlan.tries(for: URL(string: url)!) { expectAccepted(scan.arguments, scan.id) }
        }
    }

    @Test func joinedHTTPAndHTTPSStrategiesPass() {
        let http = ScanPlan.http.map(\.arguments)
        let https = ScanPlan.https.map(\.arguments)
        for (h, s) in zip(http, https) {
            let joined = StrategyProfiles(http: StrategyOptions(arguments: h), https: StrategyOptions(arguments: s))
            expectAccepted(joined.arguments, "joined \(h) + \(s)")
        }
    }

    @Test func listsGoToEveryProfile() {
        let joined = StrategyProfiles(http: StrategyOptions(arguments: ["--hostcase"]),
                                      https: StrategyOptions(arguments: ["--split-pos=2"])).arguments
        let command = TPWSCommand(port: 1088, strategy: joined, scope: .listOnly,
                                  hostlistPath: "\(Self.data)/hostlist.txt", excludePath: "\(Self.data)/hostlist-exclude.txt",
                                  debug: true, pidFile: "\(Self.data)/tpws.pid", mode: .transparent)
        #expect(command.arguments.filter { $0 == "--hostlist=\(Self.data)/hostlist.txt" }.count == 2)
        #expect(command.arguments.filter { $0 == "--hostlist-exclude=\(Self.data)/hostlist-exclude.txt" }.count == 2)
        #expect(command.arguments.first == "--debug=1")
    }

    @Test func socksModeIsUnchanged() {
        let command = TPWSCommand(port: 1088, strategy: ["--split-pos=2"], scope: .allSites, pidFile: "/x/tpws.pid")
        #expect(command.arguments == ["--socks", "--bind-addr=127.0.0.1", "--port=1088", "--debug=1",
                                      "--pidfile=/x/tpws.pid", "--split-pos=2"])
    }

    @Test func commandLineShowsWhatTheHelperAdds() {
        let command = TPWSCommand(port: 1088, strategy: ["--split-pos=2"], scope: .allSites, debug: false, mode: .transparent)
        #expect(command.arguments == ["--split-pos=2"])
        #expect(command.commandLine(binary: "/A/tpws") == "/A/tpws --user=root --port=1088 --bind-addr=127.0.0.1 --split-pos=2")
    }

    @Test func aListOutsideTheDataFolderIsRefused() {
        let command = TPWSCommand(port: 1088, strategy: [], scope: .listOnly, hostlistPath: "/etc/hosts", mode: .transparent)
        #expect(HelperArguments.problem(in: command.arguments, allowedFolders: folders) != nil)
    }
}
