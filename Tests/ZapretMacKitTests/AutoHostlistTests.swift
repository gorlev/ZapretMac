import Foundation
import Testing
@testable import ZapretMacKit

/// S-100: tpws builds the site list by itself with `--hostlist-auto`.
@Suite("Automatic site list (S-100)")
struct AutoHostlistTests {
    static let data = "/Users/me/Library/Application Support/ZapretMac"
    static let auto = TPWSCommand.AutoHostlist(path: "\(data)/hostlist-auto.txt")
    static let autoFlags = ["--hostlist-auto=\(data)/hostlist-auto.txt",
                            "--hostlist-auto-fail-threshold=3", "--hostlist-auto-fail-time=60"]

    static let joined = StrategyProfiles(http: StrategyOptions(arguments: ["--hostcase"]),
                                         https: StrategyOptions(arguments: ["--split-pos=2"])).arguments

    func command(_ strategy: [String], scope: Scope = .listOnly, mode: TPWSCommand.Mode = .socks,
                 auto: TPWSCommand.AutoHostlist? = Self.auto) -> TPWSCommand {
        TPWSCommand(port: 1088, strategy: strategy, scope: scope, hostlistPath: "\(Self.data)/hostlist.txt",
                    excludePath: "\(Self.data)/hostlist-exclude.txt", pidFile: "\(Self.data)/tpws.pid",
                    mode: mode, autoHostlist: auto)
    }

    func count(_ flag: String, in arguments: [String]) -> Int { arguments.filter { $0 == flag }.count }

    @Test func onPutsTheThreeFlagsInOneProfile() {
        let arguments = command(["--split-pos=2"]).arguments
        for flag in Self.autoFlags { #expect(count(flag, in: arguments) == 1, "\(flag) in \(arguments)") }
        #expect(arguments.contains("--hostlist=\(Self.data)/hostlist.txt"))
    }

    @Test func onPutsTheFlagsInEveryProfile() {
        let arguments = command(Self.joined).arguments
        #expect(count("--new", in: arguments) == 1)
        for flag in Self.autoFlags { #expect(count(flag, in: arguments) == 2, "\(flag) in \(arguments)") }
        // Each profile starts with the lists, then its own strategy flags.
        let profileStart = arguments.firstIndex(of: "--hostlist=\(Self.data)/hostlist.txt") ?? 0
        let profiles = StrategyProfiles.split(Array(arguments[profileStart...]))
        #expect(profiles.count == 2)
        for profile in profiles { #expect(profile.contains(Self.autoFlags[0]), "\(profile)") }
    }

    @Test func everyPresetGetsTheFlagsInEveryProfile() {
        for preset in Preset.all {
            let strategy = preset.options.arguments
            let profiles = StrategyProfiles.split(strategy).count
            let arguments = command(strategy).arguments
            #expect(count(Self.autoFlags[0], in: arguments) == profiles, "\(preset.id)")
        }
    }

    @Test func offHasNoAutoFlags() {
        for strategy in [["--split-pos=2"], Self.joined] {
            let arguments = command(strategy, auto: nil).arguments
            #expect(!arguments.contains { $0.hasPrefix("--hostlist-auto") }, "\(arguments)")
        }
    }

    @Test func allSitesHasNoAutoFlags() {
        // In tpws the auto file is an include list: with All sites it would
        // narrow the bypass to the learned sites, so it is left out.
        let all = command(Self.joined, scope: .allSites)
        #expect(!all.usesAutoHostlist)
        #expect(!all.arguments.contains { $0.hasPrefix("--hostlist=") || $0.hasPrefix("--hostlist-auto") }, "\(all.arguments)")
    }

    @Test func otherThresholdAndTime() {
        let auto = TPWSCommand.AutoHostlist(path: "/x/auto.txt", failThreshold: 5, failTime: 120)
        let arguments = command(["--split-pos=2"], auto: auto).arguments
        #expect(arguments.contains("--hostlist-auto-fail-threshold=5"))
        #expect(arguments.contains("--hostlist-auto-fail-time=120"))
    }

    @Test func transparentModeNeverHasAutoFlagsAndPassesTheHelper() {
        let folders = HelperArguments.allowedFolders(home: "/Users/me")
        var strategies = Preset.all.map(\.options.arguments)
        strategies.append(Self.joined)
        for strategy in strategies {
            for scope in Scope.allCases {
                for debug in [true, false] {
                    var transparent = command(strategy, scope: scope, mode: .transparent)
                    transparent.debug = debug
                    let arguments = transparent.arguments
                    #expect(!transparent.usesAutoHostlist)
                    #expect(!arguments.contains { $0.hasPrefix("--hostlist-auto") }, "\(arguments)")
                    #expect(HelperArguments.problem(in: arguments, allowedFolders: folders) == nil, "\(arguments)")
                }
            }
        }
    }

    @Test func theHelperStillRefusesAutoFlags() {
        let folders = HelperArguments.allowedFolders(home: "/Users/me")
        #expect(HelperArguments.problem(in: [Self.autoFlags[0]], allowedFolders: folders) != nil)
    }

    @Test func readsTheFileTpwsWrites() {
        let text = "Blocked.example\n\nsecond.example\n# note\n  third.example  \nblocked.example\n"
        #expect(AutoHostlistFile.sites(in: text) == ["blocked.example", "second.example", "third.example"])
        #expect(AutoHostlistFile.sites(in: "") == [])
    }

    @Test func removesSitesFromTheFile() {
        let text = "a.example\nb.example\nc.example\n"
        #expect(AutoHostlistFile.contents(of: text, removing: ["b.example"]) == "a.example\nc.example\n")
        #expect(AutoHostlistFile.contents(of: text, removing: ["a.example", "b.example", "c.example"]) == "")
    }
}
