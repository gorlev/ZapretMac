import Foundation
import JavaScriptCore
import Testing
@testable import ZapretMacKit

/// Runs the PAC script in JavaScriptCore and asks it about a host.
private func route(_ script: String, _ host: String) -> String? {
    let context = JSContext()!
    context.evaluateScript(script)
    return context.objectForKeyedSubscript("FindProxyForURL")?
        .call(withArguments: ["https://\(host)/", host])?.toString()
}

private let socks = "SOCKS5 127.0.0.1:1088; SOCKS 127.0.0.1:1088; DIRECT"

@Test func pacSendsListedSitesAndSubdomainsToSocks() {
    let script = PACFile.script(include: ["discord.com", "youtube.com"], exclude: [], port: 1088)
    #expect(route(script, "discord.com") == socks)
    #expect(route(script, "cdn.discord.com") == socks)
    #expect(route(script, "a.b.youtube.com") == socks)
    #expect(route(script, "WWW.YouTube.COM") == socks)
    #expect(route(script, "discord.com.") == socks)
}

@Test func pacSendsOtherSitesDirect() {
    let script = PACFile.script(include: ["discord.com"], exclude: [], port: 1088)
    #expect(route(script, "example.com") == "DIRECT")
    #expect(route(script, "notdiscord.com") == "DIRECT")
    #expect(route(script, "discord.com.evil.net") == "DIRECT")
    #expect(route(script, "com") == "DIRECT")
    #expect(route(script, "localhost") == "DIRECT")
    #expect(route(script, "hasOwnProperty") == "DIRECT")
}

@Test func pacExcludedSitesWin() {
    let script = PACFile.script(include: ["google.com", "maps.google.com"], exclude: ["mail.google.com", "apple.com"], port: 1088)
    #expect(route(script, "mail.google.com") == "DIRECT")
    #expect(route(script, "x.mail.google.com") == "DIRECT")
    #expect(route(script, "apple.com") == "DIRECT")
    #expect(route(script, "www.google.com") == socks)
    #expect(route(script, "maps.google.com") == socks)
}

@Test func pacEmptyListIsAllDirect() {
    let script = PACFile.script(include: [], exclude: [], port: 1088)
    #expect(script.contains("var include = {};"))
    #expect(route(script, "discord.com") == "DIRECT")
}

@Test func pacUsesThePortAndEscapes() {
    let script = PACFile.script(include: ["  .Site.Example. ", "a\"b"], exclude: [], port: 19901)
    #expect(script.contains("\"SOCKS5 127.0.0.1:19901; SOCKS 127.0.0.1:19901; DIRECT\""))
    #expect(script.contains("\"site.example\": 1"))
    #expect(script.contains("\"a\\\"b\": 1"))
    #expect(route(script, "site.example") == "SOCKS5 127.0.0.1:19901; SOCKS 127.0.0.1:19901; DIRECT")
}

@Test func pacHandlesALargeList() {
    let domains = (0..<20_000).map { "site\($0).example" }
    let script = PACFile.script(include: domains, exclude: [], port: 1088)
    #expect(!script.contains("if (host"))
    #expect(route(script, "www.site19999.example") == socks)
    #expect(route(script, "site20000.example") == "DIRECT")
}
