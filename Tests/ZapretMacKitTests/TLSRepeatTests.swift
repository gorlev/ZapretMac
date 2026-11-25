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

@Test func versionsAreRecordedAndTLS13IsEnough() {
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
    // TLS 1.3 alone is enough to work, in TLS 1.3's time, with a caveat.
    #expect(t.status == .works(milliseconds: 90))
    #expect(t.worksOnlyWithTLS13)
    #expect(t.sites == [opens(90)])

    // TLS 1.2 alone is not: browsers use TLS 1.3.
    t.finish(versions: [VersionResult(version: .tls13, repeats: [[fails("Connection reset")]]),
                        VersionResult(version: .tls12, repeats: [[opens(120)]])])
    #expect(t.status == .fails("TLS 1.3: Connection reset"))
    #expect(!t.works && !t.worksOnlyWithTLS13)
    #expect(t.works(with: .tls12) == true)

    // Both fail: the TLS 1.3 reason is shown.
    t.finish(versions: [VersionResult(version: .tls13, repeats: [[fails("Timed out")]]),
                        VersionResult(version: .tls12, repeats: [[fails("Connection reset")]])])
    #expect(t.status == .fails("TLS 1.3: Timed out"))

    // A quick find records no versions.
    t.finish(with: [opens(50)])
    #expect(t.versions.isEmpty && t.works(with: .tls13) == nil)
    #expect(TLSVersion.tls13.name == "TLS 1.3")
}

@Test func strategiesThatWorkWithBothVersionsRankFirst() {
    func trial(_ id: String, tls13: SiteAttempt, tls12: SiteAttempt) -> Trial {
        var t = Trial(id: id, name: id, arguments: [])
        t.finish(versions: [VersionResult(version: .tls13, sites: [tls13]),
                            VersionResult(version: .tls12, sites: [tls12])])
        return t
    }
    let fastOnly13 = trial("only13", tls13: opens(50), tls12: fails("Connection reset"))
    let slowBoth = trial("both", tls13: opens(300), tls12: opens(400))
    let only12 = trial("only12", tls13: fails("Timed out"), tls12: opens(60))
    let quick = Trial(id: "quick", name: "quick", arguments: [], status: .works(milliseconds: 500))
    #expect(Trial.ranked([only12, fastOnly13, quick, slowBoth]).map(\.id) == ["both", "quick", "only13", "only12"])
    #expect(!quick.worksOnlyWithTLS13 && !slowBoth.worksOnlyWithTLS13 && fastOnly13.worksOnlyWithTLS13)
}

@Test func severalSitesWorkOnlyWithTLS13IfOneNeedsIt() {
    var t = Trial(id: "x", name: "x", arguments: [])
    t.finish(versions: [VersionResult(version: .tls13, sites: [opens(100), opens(200, "b.com")]),
                        VersionResult(version: .tls12, sites: [opens(150), fails("Connection reset", "b.com")])])
    #expect(t.status == .works(milliseconds: 200))
    #expect(t.worksOnlyWithTLS13)
}
