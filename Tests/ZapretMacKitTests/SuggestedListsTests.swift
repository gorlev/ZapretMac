import Foundation
import Testing
@testable import ZapretMacKit

/// S-106: the suggested lists in Add Subscription.
@Suite("Suggested lists (S-106)")
struct SuggestedListsTests {
    @Test func everyEntryIsComplete() {
        #expect(!SuggestedLists.all.isEmpty)
        for list in SuggestedLists.all {
            #expect(!list.name.isEmpty, "\(list.id)")
            #expect(!list.summary.isEmpty && !list.summary.contains("\n"), "\(list.id)")
            #expect(list.url.scheme == "https", "\(list.id)")
            #expect(SiteListSubscription.url(from: list.url.absoluteString) == list.url, "\(list.id)")
            #expect(list.source.scheme == "https", "\(list.id)")
            #expect(list.id.hasPrefix("get_") && list.id.hasSuffix(".sh"), "\(list.id)")
            if let country = list.country { #expect(country.count == 2 && country == country.uppercased(), "\(list.id)") }
        }
    }

    @Test func idsAndAddressesAreUnique() {
        #expect(Set(SuggestedLists.all.map(\.id)).count == SuggestedLists.all.count)
        #expect(Set(SuggestedLists.all.map(\.url)).count == SuggestedLists.all.count)
    }

    @Test func bothKindsAreOffered() {
        #expect(!SuggestedLists.list(kind: .domains).isEmpty)
        #expect(!SuggestedLists.list(kind: .addresses).isEmpty)
        #expect(SuggestedLists.list(kind: .addresses).allSatisfy { $0.kind == .addresses })
    }

    /// zapret's lists are about Russia's blocks; each one says so.
    @Test func countrySpecificListsSayWhichCountry() {
        #expect(SuggestedLists.all.allSatisfy { $0.country == "RU" })
        #expect(SuggestedLists.all.first?.countryName?.isEmpty == false)
    }

    @Test func aSuggestionIsFoundByItsAddress() {
        let first = SuggestedLists.all[0]
        #expect(SuggestedLists.matching(first.url) == first)
        #expect(SuggestedLists.matching(URL(string: "https://example.com/list.txt")) == nil)
        #expect(SuggestedLists.matching(nil) == nil)
    }
}
