import Foundation
import Testing
@testable import ZapretMacKit

@Test func optionsRoundTrip() {
    var o = StrategyOptions()
    o.splitPositions = "1, midsld"
    o.disorder = true
    o.tlsRecord = "sniext+1"
    o.hostCase = true
    o.extra = ["--mss=88"]
    #expect(o.arguments == ["--tlsrec=sniext+1", "--split-pos=1,midsld", "--disorder", "--hostcase", "--mss=88"])
    let back = StrategyOptions(arguments: o.arguments)
    #expect(back.splitPositions == "1,midsld")
    #expect(back.disorder && back.hostCase)
    #expect(back.extra == ["--mss=88"])
}

@Test func parsesCommandLineWithQuotes() {
    #expect(CommandLineWords.split("--a=1  --b='x y' \"--c\"") == ["--a=1", "--b=x y", "--c"])
    #expect(CommandLineWords.split("   ") == [])
}

@Test func summaryReadsWell() {
    #expect(StrategyOptions(commandLine: "--split-pos=1,midsld --disorder").summary == "Split at 1,midsld · Disorder")
    #expect(StrategyOptions().summary == "No changes to traffic")
}

@Test func presetsAreUnique() {
    #expect(Set(Preset.all.map(\.id)).count == Preset.all.count)
    #expect(Preset.with(id: Preset.defaultID) != nil)
    for p in Preset.all { #expect(p.options.extra.isEmpty, "\(p.id) has unknown flags") }
}

@Test func commandUsesHostlistOnlyForListScope() {
    var c = TPWSCommand(port: 988, strategy: ["--disorder"], scope: .allSites,
                        hostlistPath: "/h.txt", excludePath: nil, debug: false)
    #expect(c.arguments == ["--socks", "--bind-addr=127.0.0.1", "--port=988", "--disorder"])
    c.scope = .listOnly
    c.excludePath = "/x.txt"
    #expect(c.arguments.contains("--hostlist=/h.txt"))
    #expect(c.arguments.contains("--hostlist-exclude=/x.txt"))
    #expect(TPWSCommand.isValidPort(988) == false)
    #expect(TPWSCommand.isValidPort(19880))
}

@Test("Normalize domains", arguments: [
    ("https://www.YouTube.com/watch?v=1", "youtube.com"),
    ("discord.com", "discord.com"),
    ("*.twitter.com", "twitter.com"),
    ("example.org:443", "example.org"),
    ("  rutracker.org.  ", "rutracker.org"),
])
func normalizes(_ input: String, expected: String) {
    #expect(Domains.normalize(input) == expected)
}

@Test func rejectsNonDomains() {
    for bad in ["", "# comment", "localhost", "a..b", "hello world", "ünicode.com"] {
        #expect(Domains.normalize(bad) == nil, "\(bad)")
    }
}

@Test func parsesPastedLists() {
    let text = "youtube.com, discord.com\nwww.youtube.com # dup\n# note\ninstagram.com;x.com"
    #expect(Domains.parseList(text) == ["youtube.com", "discord.com", "instagram.com", "x.com"])
    #expect(Domains.fileContents(["a.com", "b.com"]) == "a.com\nb.com\n")
}

@Test func classifiesLogLines() {
    #expect(LogLine(id: 1, text: "desync profile search for tcp target=1.2.3.4:443 l7proto=tls hostname='discord.com'").host == "discord.com")
    #expect(LogLine(id: 2, text: "Socket fd=8 (local) connected from 127.0.0.1:5").kind == .connection)
    #expect(LogLine(id: 3, text: "bind: Address already in use").kind == .error)
    #expect(LogLine(id: 4, text: "socks mode").kind == .info)
}

@Test func formatsUptime() {
    #expect(Uptime.format(42) == "42 s")
    #expect(Uptime.format(600) == "10 min")
    #expect(Uptime.format(3900) == "1 h 05 min")
}

@Test func readsNetworksetup() {
    let out = "Enabled: Yes\nServer: 127.0.0.1\nPort: 19880\nAuthenticated Proxy Enabled: 0\n"
    let s = ProxyState(networksetupOutput: out)
    #expect(s == ProxyState(enabled: true, server: "127.0.0.1", port: 19880))
    #expect(s?.points(to: 19880) == true)
    let list = "An asterisk (*) denotes that a network service is disabled.\nWi-Fi\n*Thunderbolt Bridge\nUSB LAN\n"
    #expect(ProxyState.services(fromList: list) == ["Wi-Fi", "USB LAN"])
}
