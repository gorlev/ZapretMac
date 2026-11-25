import Foundation
import Testing
@testable import ZapretMacKit

// S-102: TLS 1.2 and 1.3 tried separately, and repeats.

private func opens(_ ms: Int, _ site: String = "a.com") -> SiteAttempt { SiteAttempt(site: site, result: .opens(milliseconds: ms)) }
private func fails(_ why: String, _ site: String = "a.com") -> SiteAttempt { SiteAttempt(site: site, result: .fails(why)) }

@Test func aTryWorksOnlyIfEveryRepeatWorks() {
    #expect(SiteAttempt.combine(repeats: [opens(100), opens(300), opens(200)]) == opens(300))
    #expect(SiteAttempt.combine(repeats: [opens(100), fails("Connection reset"), opens(200)]) == fails("Connection reset"))
    #expect(SiteAttempt.combine(repeats: []) == nil)
    // Two sites, three repeats: b.com fails once.
    let folded = Trial.combine(repeats: [[opens(100), opens(50, "b.com")],
                                         [opens(120), fails("Timed out", "b.com")],
                                         [opens(110), opens(60, "b.com")]])
    #expect(folded == [opens(120), fails("Timed out", "b.com")])
    // An early stop after the first failure still folds.
    #expect(Trial.combine(repeats: [[opens(100)], [fails("Timed out")]]) == [fails("Timed out")])
}

@Test func versionsAreRecordedAndBothMustWork() {
    var t = Trial(id: "scan:--split-pos=2", name: "Split at 2", arguments: ["--split-pos=2"])
    t.finish(versions: [VersionResult(version: .tls13, repeats: [[opens(80)]]),
                        VersionResult(version: .tls12, repeats: [[opens(120)]])])
    #expect(t.status == .works(milliseconds: 120))
    #expect(t.works(with: .tls13) == true && t.works(with: .tls12) == true)
    #expect(t.versions.map(\.version) == [.tls13, .tls12])

    t.finish(versions: [VersionResult(version: .tls13, repeats: [[opens(80)], [opens(90)], [opens(85)]]),
                        VersionResult(version: .tls12, repeats: [[opens(120)], [fails("Connection reset")]])])
    #expect(t.works(with: .tls13) == true)
    #expect(t.works(with: .tls12) == false)
    #expect(t.status == .fails("TLS 1.2: Connection reset"))
    #expect(!t.works)
    #expect(t.sites == [fails("TLS 1.2: Connection reset")])

    // A quick find records no versions.
    t.finish(with: [opens(50)])
    #expect(t.versions.isEmpty && t.works(with: .tls13) == nil)
    #expect(TLSVersion.tls13.name == "TLS 1.3")
}
