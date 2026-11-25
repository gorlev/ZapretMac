import Foundation
import Testing
@testable import ZapretMacKit

private let httpOptions = StrategyOptions(arguments: ["--hostcase", "--split-pos=method+2"])
private let httpsOptions = StrategyOptions(arguments: ["--tlsrec=sniext+1", "--split-pos=midsld", "--disorder"])

@Test func profilesJoinWithPortFilters() {
    let joined = StrategyProfiles(http: httpOptions, https: httpsOptions).arguments
    #expect(joined == ["--filter-tcp=80", "--split-pos=method+2", "--hostcase",
                       "--new",
                       "--filter-tcp=443", "--tlsrec=sniext+1", "--split-pos=midsld", "--disorder"])
}

@Test func profilesSplitBack() throws {
    let joined = StrategyProfiles(http: httpOptions, https: httpsOptions).arguments
    let parsed = try #require(StrategyProfiles(arguments: joined))
    #expect(parsed.http.splitPositions == "method+2" && parsed.http.hostCase && parsed.http.tcpPorts == "80")
    #expect(parsed.https.tlsRecord == "sniext+1" && parsed.https.disorder && parsed.https.tcpPorts == "443")
    #expect(parsed.arguments == joined)
    #expect(StrategyProfiles.split(joined).count == 2)
    #expect(StrategyProfiles.join(StrategyProfiles.split(joined)) == joined)
}

@Test func profilesRefuseOtherLists() {
    #expect(StrategyProfiles(arguments: ["--split-pos=1"]) == nil)
    #expect(StrategyProfiles(arguments: ["--split-pos=1", "--new", "--disorder"]) == nil)
    #expect(StrategyProfiles.split(["--split-pos=1"]) == [["--split-pos=1"]])
}

@Test func optionsKeepSecondProfileInExtra() {
    let joined = StrategyProfiles(http: httpOptions, https: httpsOptions).arguments
    let options = StrategyOptions(arguments: joined)
    #expect(options.tcpPorts == "80")
    #expect(options.hostCase && options.splitPositions == "method+2")
    // The HTTPS part is not read into the form: --disorder stays off.
    #expect(!options.disorder && options.tlsRecord.isEmpty)
    #expect(options.extra == ["--new", "--filter-tcp=443", "--tlsrec=sniext+1", "--split-pos=midsld", "--disorder"])
    #expect(options.hasSecondProfile)
    #expect(options.arguments == joined)
    // Through the editor's command line and back.
    #expect(StrategyOptions(commandLine: options.commandLine) == options)
    #expect(!StrategyOptions(arguments: ["--split-pos=1"]).hasSecondProfile)
}

@Test func commandPutsListsIntoEveryProfile() {
    let joined = StrategyProfiles(http: httpOptions, https: httpsOptions).arguments
    var c = TPWSCommand(port: 19880, strategy: joined, scope: .listOnly,
                        hostlistPath: "/h.txt", excludePath: nil, debug: false)
    #expect(c.arguments == ["--socks", "--bind-addr=127.0.0.1", "--port=19880",
                            "--hostlist=/h.txt", "--filter-tcp=80", "--split-pos=method+2", "--hostcase",
                            "--new",
                            "--hostlist=/h.txt", "--filter-tcp=443", "--tlsrec=sniext+1", "--split-pos=midsld", "--disorder"])
    c.excludePath = "/x.txt"
    #expect(c.arguments.filter { $0 == "--hostlist=/h.txt" }.count == 2)
    #expect(c.arguments.filter { $0 == "--hostlist-exclude=/x.txt" }.count == 2)
    c.scope = .allSites
    #expect(!c.arguments.contains("--hostlist=/h.txt"))
    #expect(c.arguments.filter { $0 == "--hostlist-exclude=/x.txt" }.count == 2)
}

@Test func singleProfileCommandIsUnchanged() {
    let c = TPWSCommand(port: 19880, strategy: ["--split-pos=1,midsld", "--disorder"], scope: .listOnly,
                        hostlistPath: "/h.txt", excludePath: "/x.txt", debug: true, pidFile: "/p.pid")
    #expect(c.arguments == ["--socks", "--bind-addr=127.0.0.1", "--port=19880", "--debug=1", "--pidfile=/p.pid",
                            "--hostlist=/h.txt", "--hostlist-exclude=/x.txt", "--split-pos=1,midsld", "--disorder"])
}
