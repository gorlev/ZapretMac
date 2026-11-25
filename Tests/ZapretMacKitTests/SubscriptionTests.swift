import Foundation
import Testing
@testable import ZapretMacKit

/// The text of the list below, before gzip:
///   # community list / example.org / www.Example.net # mirror / (blank) / sub.example.com / example.org
private let listText = "# community list\nexample.org\nwww.Example.net # mirror\n\nsub.example.com\nexample.org\n"

/// `/usr/bin/gzip -c -9 list.txt` of `listText` (the header has a file name).
private let listGzip: [UInt8] = [
    0x1f, 0x8b, 0x08, 0x08, 0x30, 0x19, 0x07, 0x6b, 0x02, 0x03, 0x6c, 0x69,
    0x73, 0x74, 0x2e, 0x74, 0x78, 0x74, 0x00, 0x53, 0x56, 0x48, 0xce, 0xcf,
    0xcd, 0x2d, 0xcd, 0xcb, 0x2c, 0xa9, 0x54, 0xc8, 0xc9, 0x2c, 0x2e, 0xe1,
    0x4a, 0xad, 0x48, 0xcc, 0x2d, 0xc8, 0x49, 0xd5, 0xcb, 0x2f, 0x4a, 0xe7,
    0x2a, 0x2f, 0x2f, 0xd7, 0x73, 0x85, 0xf2, 0xf3, 0x52, 0x4b, 0x14, 0x94,
    0x15, 0x72, 0x33, 0x8b, 0x8a, 0xf2, 0x8b, 0xb8, 0xb8, 0x8a, 0x4b, 0x93,
    0xf4, 0x60, 0x2a, 0x81, 0x06, 0xa0, 0xe8, 0x02, 0x00, 0x6d, 0xd5, 0x84,
    0xa8, 0x53, 0x00, 0x00, 0x00,
]

@Test func gzipUnpacksToTheOriginalText() throws {
    let data = Data(listGzip)
    #expect(Gzip.isGzip(data))
    let out = try Gzip.decompress(data)
    #expect(String(data: out, encoding: .utf8) == listText)
}

@Test func gzipRefusesOtherData() {
    #expect(!Gzip.isGzip(Data(listText.utf8)))
    #expect(throws: Gzip.Failure.notGzip) { try Gzip.decompress(Data(listText.utf8)) }
    var broken = listGzip
    broken.removeLast(40)
    #expect(throws: Gzip.Failure.damaged) { try Gzip.decompress(Data(broken)) }
}

@Test func plainAndGzipListsParseTheSame() throws {
    let expected = ["example.org", "example.net", "sub.example.com"]
    #expect(try SiteListSubscription.domains(from: Data(listText.utf8)) == expected)
    #expect(try SiteListSubscription.domains(from: Data(listGzip)) == expected)
}

@Test func listsAreParsedLikePastedSites() throws {
    let text = "#only a comment\n*.YouTube.com\nhttps://discord.gg/x\n  roblox.com  ; x.com\nnot a domain\n"
    #expect(try SiteListSubscription.domains(from: Data(text.utf8)) == Domains.parseList(text))
    #expect(try SiteListSubscription.domains(from: Data(text.utf8)) == ["youtube.com", "discord.gg", "roblox.com", "x.com"])
}

@Test func listsWithNoSitesOrNoTextAreRefused() {
    #expect(throws: SiteListSubscription.Failure.empty) {
        try SiteListSubscription.domains(from: Data("# nothing here\n\n".utf8))
    }
    #expect(throws: SiteListSubscription.Failure.notText) {
        try SiteListSubscription.domains(from: Data("<!DOCTYPE html><html>example.com</html>".utf8))
    }
    #expect(throws: SiteListSubscription.Failure.notText) {
        try SiteListSubscription.domains(from: Data([0x89, 0x50, 0x4e, 0x47, 0x00, 0x01]))
    }
}

@Test func listAddressesAreChecked() {
    #expect(SiteListSubscription.url(from: " https://example.com/lists/russia-blacklist.txt ")?.host == "example.com")
    #expect(SiteListSubscription.url(from: "file:///tmp/list.txt")?.path == "/tmp/list.txt")
    #expect(SiteListSubscription.url(from: "http://localhost/list.txt") != nil)
    #expect(SiteListSubscription.url(from: "example.com/list.txt") == nil)
    #expect(SiteListSubscription.url(from: "ftp://example.com/list.txt") == nil)
    #expect(SiteListSubscription.url(from: "https://nohost/list") == nil)
    #expect(SiteListSubscription.url(from: "https://example.com/a list.txt") == nil)
}

@Test func listNamesComeFromTheAddress() throws {
    let url = try #require(URL(string: "https://example.com/zapret/list-general%20v2.txt.gz?raw=1"))
    #expect(SiteListSubscription.defaultName(for: url) == "list-general v2.txt.gz")
    #expect(SiteListSubscription.defaultName(for: try #require(URL(string: "https://lists.example.com"))) == "lists.example.com")
}

@Test func listsAreDueAfterADay() {
    let now = Date(timeIntervalSince1970: 1_000_000)
    #expect(SiteListSubscription.isDue(lastUpdated: nil, now: now))
    #expect(!SiteListSubscription.isDue(lastUpdated: now.addingTimeInterval(-3600), now: now))
    #expect(SiteListSubscription.isDue(lastUpdated: now.addingTimeInterval(-SiteListSubscription.refreshInterval), now: now))
}

@Test func ownSitesComeFirstAndEachDomainOnce() {
    let merged = SiteListSubscription.merge(["youtube.com", "discord.com"],
                                            [["discord.com", "x.com"], ["x.com", "roblox.com"]])
    #expect(merged == ["youtube.com", "discord.com", "x.com", "roblox.com"])
    #expect(SiteListSubscription.readFile(Domains.fileContents(merged)) == merged)
    #expect(SiteListSubscription.readFile("") == [])
}
