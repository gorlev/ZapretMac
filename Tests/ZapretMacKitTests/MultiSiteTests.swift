import Foundation
import Testing
@testable import ZapretMacKit

private func trial(_ attempts: [SiteAttempt]) -> Trial {
    var t = Trial(id: "preset:x", name: "X", arguments: [])
    t.finish(with: attempts)
    return t
}

@Test func worksOnlyWhenEverySiteOpens() {
    let both = trial([SiteAttempt(site: "a.com", result: .opens(milliseconds: 120)),
                      SiteAttempt(site: "b.com", result: .opens(milliseconds: 340))])
    #expect(both.status == .works(milliseconds: 340))
    #expect(both.works)
    #expect(both.openCount == 2)
    #expect(both.failedSites.isEmpty)
    #expect(!both.isPartial)

    let oneFails = trial([SiteAttempt(site: "a.com", result: .opens(milliseconds: 120)),
                          SiteAttempt(site: "b.com", result: .fails("Timed out"))])
    #expect(oneFails.status == .fails("Timed out"))
    #expect(!oneFails.works)
}

@Test func timeIsTheSlowestSite() {
    let t = trial([SiteAttempt(site: "a.com", result: .opens(milliseconds: 900)),
                   SiteAttempt(site: "b.com", result: .opens(milliseconds: 40)),
                   SiteAttempt(site: "c.com", result: .opens(milliseconds: 300))])
    #expect(t.status == .works(milliseconds: 900))
}

@Test func partialResultCounts() {
    let t = trial([SiteAttempt(site: "a.com", result: .opens(milliseconds: 100)),
                   SiteAttempt(site: "b.com", result: .fails("Connection reset")),
                   SiteAttempt(site: "c.com", result: .opens(milliseconds: 200))])
    #expect(t.openCount == 2)
    #expect(t.sites.count == 3)
    #expect(t.isPartial)
    #expect(t.failedSites.map(\.site) == ["b.com"])
    #expect(t.status == .fails("Connection reset"))

    let none = trial([SiteAttempt(site: "a.com", result: .fails("Timed out")),
                      SiteAttempt(site: "b.com", result: .fails("Site not found"))])
    #expect(none.openCount == 0)
    #expect(!none.isPartial)
    #expect(none.status == .fails("Timed out"))
}

@Test func oneSiteBehavesAsBefore() {
    #expect(Trial.combine([SiteAttempt(site: "a.com", result: .opens(milliseconds: 77))]) == .works(milliseconds: 77))
    #expect(Trial.combine([SiteAttempt(site: "a.com", result: .fails("No internet"))]) == .fails("No internet"))
    #expect(Trial.combine([]) == .waiting)
    #expect(!trial([SiteAttempt(site: "a.com", result: .fails("x"))]).isPartial)
}

@Test func failuresThatOpenedMoreSitesRankFirst() {
    let none = trial([SiteAttempt(site: "a.com", result: .fails("x")), SiteAttempt(site: "b.com", result: .fails("x"))])
    let half = trial([SiteAttempt(site: "a.com", result: .opens(milliseconds: 1)), SiteAttempt(site: "b.com", result: .fails("x"))])
    let ranked = Trial.ranked([none, half])
    #expect(ranked.map(\.openCount) == [1, 0])
}

@Test func siteListSplitsLikeTheDomainList() {
    #expect(Domains.pieces("discord.com youtube.com") == ["discord.com", "youtube.com"])
    #expect(Domains.pieces("a.com,b.com;\nhttp://c.com/x  # note") == ["a.com", "b.com", "http://c.com/x"])
    #expect(Domains.parseList("https://www.YouTube.com/watch, discord.com") == ["youtube.com", "discord.com"])
}
