import Testing
@testable import ZapretMacKit

/// S-100 and S-103 together: the automatic list joins My list's hostlist
/// profile; the IP profile stays an IP profile; exclusions reach both.
@Test func autoHostlistJoinsTheHostlistProfileNotTheIPProfile() {
    let command = TPWSCommand(port: 1088, strategy: ["--split-pos=1"], scope: .listOnly,
                              hostlistPath: "/d/hostlist.txt", excludePath: "/d/exclude.txt",
                              ipsetPath: "/d/ipset.txt", ipsetExcludePath: nil, debug: false,
                              autoHostlist: .init(path: "/d/hostlist-auto.txt"))
    let profiles = command.profiles
    #expect(profiles.count == 2)
    let sites = profiles.first { $0.contains("--hostlist=/d/hostlist.txt") }
    let ips = profiles.first { $0.contains("--ipset=/d/ipset.txt") }
    #expect(sites?.contains("--hostlist-auto=/d/hostlist-auto.txt") == true)
    #expect(ips?.contains { $0.hasPrefix("--hostlist-auto") } == false)
    #expect(profiles.allSatisfy { $0.contains("--hostlist-exclude=/d/exclude.txt") })
}

@Test func autoHostlistAloneGetsItsOwnProfileWhenMyListHasOnlyAddresses() {
    let command = TPWSCommand(port: 1088, strategy: ["--split-pos=1"], scope: .listOnly,
                              hostlistPath: nil, ipsetPath: "/d/ipset.txt", debug: false,
                              autoHostlist: .init(path: "/d/hostlist-auto.txt"))
    #expect(command.profiles.contains { $0.contains("--hostlist-auto=/d/hostlist-auto.txt") && !$0.contains("--ipset=/d/ipset.txt") })
}
