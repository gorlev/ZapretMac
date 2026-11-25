import Testing
@testable import ZapretMacKit

/// S-104: sharing the SOCKS proxy with devices on the local network.
struct NetworkShareTests {
    @Test func sharingAddsALANBindAndKeepsLoopback() {
        let command = TPWSCommand(port: 1088, strategy: ["--split-pos=2"], scope: .allSites, debug: false,
                                  shareAddress: "192.168.1.20")
        #expect(Array(command.arguments.prefix(4)) == ["--socks", "--bind-addr=127.0.0.1", "--bind-addr=192.168.1.20", "--port=1088"])
        #expect(command.arguments.filter { $0.hasPrefix("--bind-addr") }.count == 2)
    }

    @Test func notSharingBindsLoopbackOnly() {
        let command = TPWSCommand(port: 1088, strategy: ["--split-pos=2"], scope: .allSites, debug: false)
        #expect(command.arguments.filter { $0.hasPrefix("--bind-addr") } == ["--bind-addr=127.0.0.1"])
        #expect(Array(command.arguments.prefix(3)) == ["--socks", "--bind-addr=127.0.0.1", "--port=1088"])
    }

    @Test func unusableAddressesAddNoBind() {
        for ip in ["127.0.0.1", "169.254.3.4", "0.0.0.0", "fe80::1", "not an address", ""] {
            let command = TPWSCommand(port: 1088, strategy: [], scope: .allSites, shareAddress: ip)
            #expect(command.arguments.filter { $0.hasPrefix("--bind-addr") } == ["--bind-addr=127.0.0.1"], "\(ip)")
        }
    }

    @Test func transparentModeIgnoresSharing() {
        let shared = TPWSCommand(port: 1088, strategy: ["--split-pos=2"], scope: .allSites,
                                 mode: .transparent, shareAddress: "192.168.1.20")
        let plain = TPWSCommand(port: 1088, strategy: ["--split-pos=2"], scope: .allSites, mode: .transparent)
        #expect(shared.arguments == plain.arguments)
        #expect(!shared.arguments.contains { $0.hasPrefix("--bind") || $0.hasPrefix("--socks") })
        #expect(HelperArguments.problem(in: shared.arguments, allowedFolders: HelperArguments.allowedFolders(home: "/Users/me")) == nil)
    }

    @Test func qrPayloadIsASOCKS5URL() {
        #expect(NetworkShare.payload(ip: "192.168.1.20", port: 1088) == "socks5://192.168.1.20:1088")
    }

    @Test func choosesTheRoutedInterfaceThenWiFiOrEthernet() {
        let addresses = [
            NetworkShare.Address(interface: "utun4", ip: "10.8.0.2"),
            NetworkShare.Address(interface: "en7", ip: "169.254.10.1"),
            NetworkShare.Address(interface: "bridge100", ip: "192.168.2.1"),
            NetworkShare.Address(interface: "en0", ip: "192.168.1.20"),
            NetworkShare.Address(interface: "en5", ip: "10.0.0.7"),
        ]
        #expect(NetworkShare.choose(from: addresses, preferred: "en5")?.ip == "10.0.0.7")
        #expect(NetworkShare.choose(from: addresses, preferred: "utun4")?.ip == "192.168.1.20")
        #expect(NetworkShare.choose(from: addresses, preferred: nil)?.ip == "192.168.1.20")
        #expect(NetworkShare.choose(from: [NetworkShare.Address(interface: "utun0", ip: "10.8.0.2")], preferred: nil) == nil)
        #expect(NetworkShare.choose(from: [], preferred: "en0") == nil)
    }
}
