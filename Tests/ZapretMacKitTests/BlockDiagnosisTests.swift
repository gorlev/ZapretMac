import Foundation
import Testing
@testable import ZapretMacKit

// S-101: comparing the system resolver with DNS-over-HTTPS, and the verdict.

@Test func dnsAgreesWhenAnAddressIsShared() {
    let v = BlockDiagnosis.dnsVerdict(system: ["93.184.215.14", "2606:2800::1"],
                                      doh: [["93.184.215.14"], ["93.184.215.14", "93.184.215.15"], nil])
    #expect(v == .agrees)
}

@Test func dnsIsSpoofedWhenTheProviderAnswersDifferently() {
    let doh: [[String]?] = [["162.159.128.233", "162.159.130.233"], ["162.159.130.233"], ["162.159.128.233", "162.159.130.233"]]
    #expect(BlockDiagnosis.dnsVerdict(system: ["195.208.4.1"], doh: doh) == .spoofed)
    // No answer from the provider while the public resolvers agree.
    #expect(BlockDiagnosis.dnsVerdict(system: nil, doh: doh) == .spoofed)
    #expect(BlockDiagnosis.dnsVerdict(system: [], doh: doh) == .spoofed)
    // A stub address is a block page even when the public answers differ.
    #expect(BlockDiagnosis.dnsVerdict(system: ["127.0.0.1"], doh: [["1.2.3.4"], ["5.6.7.8"]]) == .spoofed)
}

@Test func dnsIsUnknownWithoutAgreeingPublicAnswers() {
    // No public answer at all.
    #expect(BlockDiagnosis.dnsVerdict(system: ["1.2.3.4"], doh: [nil, nil, []]) == .unknown)
    // Public resolvers disagree with each other (a CDN), so a different system answer proves nothing.
    #expect(BlockDiagnosis.dnsVerdict(system: ["9.9.9.9"], doh: [["1.1.1.1"], ["2.2.2.2"]]) == .unknown)
    // Only one resolver answered.
    #expect(BlockDiagnosis.dnsVerdict(system: ["9.9.9.9"], doh: [["1.1.1.1"], nil]) == .unknown)
    // An IPv6-only system answer cannot be compared with A records.
    #expect(BlockDiagnosis.dnsVerdict(system: ["2606:4700::1"], doh: [["1.1.1.1"], ["1.1.1.1"]]) == .unknown)
}

@Test func verdictMapsEachFindingToItsMessage() {
    #expect(BlockDiagnosis.kind(dns: .spoofed, opensDirectly: false, addressAnswers: nil, controlAnswers: nil) == .dns)
    #expect(BlockDiagnosis.kind(dns: .spoofed, opensDirectly: true, addressAnswers: nil, controlAnswers: nil) == .dns)
    #expect(BlockDiagnosis.kind(dns: .agrees, opensDirectly: true, addressAnswers: nil, controlAnswers: nil) == .none)
    #expect(BlockDiagnosis.kind(dns: .agrees, opensDirectly: false, addressAnswers: false, controlAnswers: true) == .ip)
    // The control site does not answer either: no internet, not an IP block.
    #expect(BlockDiagnosis.kind(dns: .agrees, opensDirectly: false, addressAnswers: false, controlAnswers: false) == .dpi)
    #expect(BlockDiagnosis.kind(dns: .unknown, opensDirectly: false, addressAnswers: true, controlAnswers: true) == .dpi)
    #expect(BlockKind.dns.message.contains("DNS over HTTPS"))
    #expect(BlockKind.ip.message.contains("cannot get around"))
    #expect(BlockKind.dpi.message.contains("A strategy can get around"))
    #expect(BlockKind.allCases.filter(\.strategyCanHelp) == [.dpi])
}

@Test func reservedAddresses() {
    #expect(BlockDiagnosis.isReserved("0.0.0.0"))
    #expect(BlockDiagnosis.isReserved("10.1.2.3"))
    #expect(BlockDiagnosis.isReserved("172.20.0.1"))
    #expect(!BlockDiagnosis.isReserved("172.32.0.1"))
    #expect(!BlockDiagnosis.isReserved("8.8.8.8"))
    #expect(!BlockDiagnosis.isIPv4("1.2.3"))
    #expect(!BlockDiagnosis.isIPv4("256.1.1.1"))
}

@Test func dnsQueryAndAnswerRoundTrip() throws {
    let q = try #require(DNSMessage.query(host: "Example.com"))
    let expected: [UInt8] = [0, 0, 1, 0, 0, 1, 0, 0, 0, 0, 0, 0, 7] + Array("example".utf8) + [3] + Array("com".utf8) + [0, 0, 1, 0, 1]
    #expect([UInt8](q) == expected)
    #expect(!DNSMessage.base64URL(q).contains("="))
    // The answer: the question, a CNAME, then an A record using a compression pointer.
    var answer = [UInt8](q)
    answer[2] = 0x81; answer[3] = 0x80; answer[7] = 2
    answer += [0xC0, 12, 0, 5, 0, 1, 0, 0, 0, 60, 0, 2, 0xC0, 12]
    answer += [0xC0, 12, 0, 1, 0, 1, 0, 0, 0, 60, 0, 4, 93, 184, 215, 14]
    #expect(DNSMessage.addresses(in: Data(answer)) == ["93.184.215.14"])
    var nx = [UInt8](q); nx[3] = 0x83
    #expect(DNSMessage.addresses(in: Data(nx)) == [])
    #expect(DNSMessage.addresses(in: Data([1, 2, 3])) == nil)
    #expect(DNSMessage.query(host: "") == nil)
}
