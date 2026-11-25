import Foundation
import Testing
@testable import ZapretMacKit

@Test func readsAutoProxyOutput() {
    let on = ProxyState.autoProxy(fromOutput: "URL: http://127.0.0.1:1089/proxy.pac\nEnabled: Yes\n")
    #expect(on?.url == "http://127.0.0.1:1089/proxy.pac" && on?.enabled == true)
    let none = ProxyState.autoProxy(fromOutput: "URL: (null)\nEnabled: No\n")
    #expect(none?.url == "" && none?.enabled == false)
    #expect(ProxyState.autoProxy(fromOutput: "** Error: unknown service") == nil)

    var state = ProxyState(networksetupOutput: "Enabled: No\nServer: \nPort: 0\nAuthenticated Proxy Enabled: 0\n")!
    #expect(state.autoProxyURL == nil && state.autoProxyEnabled == nil)
    state.readAutoProxy("URL: https://corp.example/wpad.dat\nEnabled: Yes\n")
    #expect(state == ProxyState(enabled: false, server: "", port: 0, autoProxyURL: "https://corp.example/wpad.dat", autoProxyEnabled: true))
}

@Test func oldSavedStatesStillDecode() throws {
    let old = Data(#"{"Wi-Fi":{"enabled":true,"server":"10.0.0.1","port":1080}}"#.utf8)
    let decoded = try JSONDecoder().decode([String: ProxyState].self, from: old)
    #expect(decoded["Wi-Fi"] == ProxyState(enabled: true, server: "10.0.0.1", port: 1080))
    let new = ProxyState(enabled: false, server: "", port: 0, autoProxyURL: "", autoProxyEnabled: false)
    let roundTrip = try JSONDecoder().decode(ProxyState.self, from: JSONEncoder().encode(new))
    #expect(roundTrip == new)
}

@Test func applySocksMode() {
    let commands = ProxyCommands.apply(services: ["Wi-Fi", "USB LAN"], mode: .socks, port: 1088, pacURL: nil)
    #expect(commands == [
        ["-setsocksfirewallproxy", "Wi-Fi", "127.0.0.1", "1088"],
        ["-setsocksfirewallproxystate", "Wi-Fi", "on"],
        ["-setautoproxystate", "Wi-Fi", "off"],
        ["-setsocksfirewallproxy", "USB LAN", "127.0.0.1", "1088"],
        ["-setsocksfirewallproxystate", "USB LAN", "on"],
        ["-setautoproxystate", "USB LAN", "off"],
    ])
}

@Test func applyPACMode() {
    let url = "http://127.0.0.1:1089/proxy.pac"
    let commands = ProxyCommands.apply(services: ["Wi-Fi"], mode: .pac, port: 1088, pacURL: url)
    #expect(commands == [
        ["-setautoproxyurl", "Wi-Fi", url],
        ["-setautoproxystate", "Wi-Fi", "on"],
        ["-setsocksfirewallproxystate", "Wi-Fi", "off"],
    ])
}

@Test func restoreBothSettings() {
    let previous: [String: ProxyState] = [
        // Its own SOCKS proxy and its own PAC file, both on.
        "Wi-Fi": ProxyState(enabled: true, server: "10.0.0.1", port: 1080,
                            autoProxyURL: "https://corp.example/wpad.dat", autoProxyEnabled: true),
        // A PAC URL that was set but off.
        "Ethernet": ProxyState(enabled: false, server: "", port: 0,
                               autoProxyURL: "http://old.example/p.pac", autoProxyEnabled: false),
        // Nothing set.
        "USB LAN": ProxyState(enabled: false, server: "", port: 0, autoProxyURL: "", autoProxyEnabled: false),
        // Saved before S-072: auto proxy never read, left alone.
        "Thunderbolt": ProxyState(enabled: false, server: "", port: 0),
    ]
    #expect(ProxyCommands.restore(previous) == [
        ["-setsocksfirewallproxystate", "Ethernet", "off"],
        ["-setautoproxyurl", "Ethernet", "http://old.example/p.pac"],
        ["-setautoproxystate", "Ethernet", "off"],
        ["-setsocksfirewallproxystate", "Thunderbolt", "off"],
        ["-setsocksfirewallproxystate", "USB LAN", "off"],
        ["-setautoproxystate", "USB LAN", "off"],
        ["-setsocksfirewallproxy", "Wi-Fi", "10.0.0.1", "1080"],
        ["-setsocksfirewallproxystate", "Wi-Fi", "on"],
        ["-setautoproxyurl", "Wi-Fi", "https://corp.example/wpad.dat"],
        ["-setautoproxystate", "Wi-Fi", "on"],
    ])
}
