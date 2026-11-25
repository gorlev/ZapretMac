import Foundation
import Testing
@testable import ZapretMacKit

/// S-103: IP addresses and ranges, and how they reach tpws.
@Suite("IP address lists (S-103)")
struct IPListTests {
    static let data = "/Users/me/Library/Application Support/ZapretMac"
    static let testData = "/tmp/ZapretMac-self-3.store-files"

    @Test func addressesAndRangesAreNormalized() {
        #expect(IPRanges.normalize("1.2.3.4") == "1.2.3.4")
        #expect(IPRanges.normalize(" 10.1.2.3/8 ") == "10.0.0.0/8")
        #expect(IPRanges.normalize("203.0.113.9/24") == "203.0.113.0/24")
        #expect(IPRanges.normalize("1.2.3.4/32") == "1.2.3.4")
        #expect(IPRanges.normalize("0.0.0.0/0") == "0.0.0.0/0")
        #expect(IPRanges.normalize("2001:DB8::1") == "2001:db8::1")
        #expect(IPRanges.normalize("2001:0db8:0000:0000:0000:0000:0000:0001/128") == "2001:db8::1")
        #expect(IPRanges.normalize("2001:db8:abcd:12::1/48") == "2001:db8:abcd::/48")
        #expect(IPRanges.normalize("[2001:db8::5]") == "2001:db8::5")
        #expect(IPRanges.normalize("192.0.2.1 # a comment") == "192.0.2.1")
    }

    @Test func junkIsNotAnAddress() {
        for junk in ["", "# comment", "example.com", "1.2.3", "1.2.3.256", "1.2.3.4/33", "2001:db8::/129",
                     "1.2.3.4/", "1.2.3.4/x", "1.2.3.4/-1", "::g", "fe80::1%en0", "01.2.3.4.5", "1.2.3.4/24/8"] {
            #expect(IPRanges.normalize(junk) == nil, "\(junk)")
        }
    }

    @Test func listsSkipCommentsAndJunkAndDropDuplicates() {
        let text = "# antifilter\n1.2.3.0/24\n\n1.2.3.7/24 # same range\nnot-an-address\n2001:db8::/32, 198.51.100.1;1.2.3.0/24\n"
        #expect(IPRanges.parseList(text) == ["1.2.3.0/24", "2001:db8::/32", "198.51.100.1"])
    }

    @Test func pastedTextIsSortedIntoSitesAndAddresses() {
        let routed = IPRanges.route("youtube.com 1.2.3.4 https://www.Discord.com/app 203.0.113.0/24 youtube.com 2001:db8::1 junk")
        #expect(routed.domains == ["youtube.com", "discord.com"])
        #expect(routed.addresses == ["1.2.3.4", "203.0.113.0/24", "2001:db8::1"])
    }

    @Test func subscribedListsAreReadByKind() throws {
        let ips = Data("# ipsum\n1.2.3.0/24\n2001:db8::/32\nexample.com\n".utf8)
        #expect(try SiteListSubscription.entries(from: ips, kind: .addresses) == ["1.2.3.0/24", "2001:db8::/32"])
        #expect(try SiteListSubscription.entries(from: ips, kind: .domains) == ["example.com"])
        #expect(throws: SiteListSubscription.Failure.onlyAddresses) {
            try SiteListSubscription.entries(from: Data("1.2.3.0/24\n".utf8), kind: .domains)
        }
        #expect(throws: SiteListSubscription.Failure.onlyDomains) {
            try SiteListSubscription.entries(from: Data("example.com\n".utf8), kind: .addresses)
        }
        #expect(throws: SiteListSubscription.Failure.empty) {
            try SiteListSubscription.entries(from: Data("# nothing\n".utf8), kind: .addresses)
        }
    }

    // MARK: - tpws arguments

    func command(scope: Scope, hostlist: Bool = true, exclude: Bool = true, ipset: Bool = true, ipsetExclude: Bool = true,
                 folder: String = data, mode: TPWSCommand.Mode = .socks) -> TPWSCommand {
        let joined = StrategyProfiles(http: StrategyOptions(arguments: ["--hostcase"]),
                                      https: StrategyOptions(arguments: ["--split-pos=2"])).arguments
        return TPWSCommand(port: 1088, strategy: joined, scope: scope,
                           hostlistPath: hostlist ? "\(folder)/hostlist.txt" : nil,
                           excludePath: exclude ? "\(folder)/hostlist-exclude.txt" : nil,
                           ipsetPath: ipset ? "\(folder)/ipset.txt" : nil,
                           ipsetExcludePath: ipsetExclude ? "\(folder)/ipset-exclude.txt" : nil,
                           debug: false, pidFile: "\(folder)/tpws.pid", mode: mode)
    }

    /// In tpws a profile with a hostlist and an ipset needs both to match, so
    /// My list writes each strategy profile once per include list.
    @Test func myListMatchesASiteOrAnAddress() {
        let profiles = StrategyProfiles.split(command(scope: .listOnly, mode: .transparent).arguments)
        #expect(profiles.count == 4)
        let hostlist = "--hostlist=\(Self.data)/hostlist.txt"
        let ipset = "--ipset=\(Self.data)/ipset.txt"
        for profile in profiles {
            #expect(profile.contains(hostlist) != profile.contains(ipset), "\(profile)")
            #expect(profile.contains("--hostlist-exclude=\(Self.data)/hostlist-exclude.txt"))
            #expect(profile.contains("--ipset-exclude=\(Self.data)/ipset-exclude.txt"))
        }
        #expect(profiles.filter { $0.contains(ipset) }.count == 2)
        #expect(profiles.filter { $0.contains("--filter-tcp=443") && $0.contains(ipset) }.count == 1)
    }

    @Test func allSitesUsesOnlyTheExcludeLists() {
        let arguments = command(scope: .allSites).arguments
        #expect(!arguments.contains { $0.hasPrefix("--ipset=") || $0.hasPrefix("--hostlist=") })
        let profiles = StrategyProfiles.split(arguments.filter { !$0.hasPrefix("--socks") })
        #expect(profiles.count == 2)
        #expect(arguments.filter { $0 == "--ipset-exclude=\(Self.data)/ipset-exclude.txt" }.count == 2)
    }

    @Test func onlyAddressesMeansOneProfileEach() {
        let arguments = command(scope: .listOnly, hostlist: false, exclude: false, ipsetExclude: false).arguments
        #expect(arguments.filter { $0 == "--ipset=\(Self.data)/ipset.txt" }.count == 2)
        #expect(!arguments.contains { $0.hasPrefix("--hostlist") || $0.hasPrefix("--ipset-exclude") })
    }

    @Test func noIPListsLeavesTheCommandAsBefore() {
        let arguments = command(scope: .listOnly, ipset: false, ipsetExclude: false, mode: .transparent).arguments
        #expect(arguments == ["--hostlist=\(Self.data)/hostlist.txt", "--hostlist-exclude=\(Self.data)/hostlist-exclude.txt",
                              "--filter-tcp=80", "--hostcase", "--new",
                              "--hostlist=\(Self.data)/hostlist.txt", "--hostlist-exclude=\(Self.data)/hostlist-exclude.txt",
                              "--filter-tcp=443", "--split-pos=2"])
    }

    @Test func transparentArgumentsWithIPListsPassTheHelper() {
        let folders = HelperArguments.allowedFolders(home: "/Users/me")
        for folder in [Self.data, Self.testData] {
            for scope in Scope.allCases {
                for (hostlist, ipset) in [(true, true), (false, true), (true, false)] {
                    for excludes in [true, false] {
                        let arguments = command(scope: scope, hostlist: hostlist, exclude: excludes, ipset: ipset,
                                                ipsetExclude: excludes, folder: folder, mode: .transparent).arguments
                        #expect(HelperArguments.problem(in: arguments, allowedFolders: folders) == nil, "\(arguments)")
                    }
                }
            }
        }
        for preset in Preset.all {
            var c = command(scope: .listOnly, mode: .transparent)
            c.strategy = preset.options.arguments
            #expect(HelperArguments.problem(in: c.arguments, allowedFolders: folders) == nil, "\(preset.id)")
        }
    }

    @Test func anIPListOutsideTheDataFolderIsRefused() {
        let c = TPWSCommand(port: 1088, strategy: [], scope: .listOnly, ipsetPath: "/etc/ipset.txt", mode: .transparent)
        #expect(HelperArguments.problem(in: c.arguments, allowedFolders: HelperArguments.allowedFolders(home: "/Users/me")) != nil)
    }
}
