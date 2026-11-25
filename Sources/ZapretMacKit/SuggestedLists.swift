import Foundation

/// A community site list offered in Add Subscription (S-106), with the
/// address zapret's own `ipset/` scripts download.
public struct SuggestedList: Identifiable, Equatable, Sendable {
    /// The zapret script that downloads this list, like "get_refilter_domains.sh".
    public let id: String
    public let name: String
    /// One line on what the list holds.
    public let summary: String
    public let url: URL
    public let kind: ListKind
    /// ISO 3166 code of the country the list is for, or nil for any country.
    public let country: String?
    /// The page that explains the list.
    public let source: URL

    /// The country's name in the person's language, or nil for any country.
    public var countryName: String? {
        country.map { Locale.current.localizedString(forRegionCode: $0) ?? $0 }
    }
}

/// The lists zapret's `ipset/get_*.sh` scripts download. Only addresses
/// those scripts use; every one of them is for Russia.
public enum SuggestedLists {
    public static let all: [SuggestedList] = [
        SuggestedList(
            id: "get_refilter_domains.sh", name: "Re:filter domains",
            summary: String(localized: "Domains blocked in Russia: the registry, cleaned up, plus sites blocked without it.", bundle: .main),
            url: URL(string: "https://github.com/1andrevich/Re-filter-lists/releases/latest/download/domains_all.lst")!,
            kind: .domains, country: "RU",
            source: URL(string: "https://github.com/1andrevich/Re-filter-lists")!),
        SuggestedList(
            id: "get_antizapret_domains.sh", name: "AntiZapret domains",
            summary: String(localized: "Domains blocked in Russia, as the AntiZapret project collects them. A large list.", bundle: .main),
            url: URL(string: "https://antizapret.prostovpn.org:8443/domains-export.txt")!,
            kind: .domains, country: "RU",
            source: URL(string: "https://antizapret.prostovpn.org")!),
        SuggestedList(
            id: "get_reestr_resolvable_domains.sh", name: "Registry domains (rulist)",
            summary: String(localized: "Domains from Russia's block registry that still resolve.", bundle: .main),
            url: URL(string: "https://raw.githubusercontent.com/bol-van/rulist/main/reestr_hostname_resolvable.txt")!,
            kind: .domains, country: "RU",
            source: URL(string: "https://github.com/bol-van/rulist")!),
        SuggestedList(
            id: "get_refilter_ipsum.sh", name: "Re:filter IP ranges",
            summary: String(localized: "IP ranges blocked in Russia, summarized into subnets.", bundle: .main),
            url: URL(string: "https://github.com/1andrevich/Re-filter-lists/releases/latest/download/ipsum.lst")!,
            kind: .addresses, country: "RU",
            source: URL(string: "https://github.com/1andrevich/Re-filter-lists")!),
        SuggestedList(
            id: "get_antifilter_allyouneed.sh", name: "Antifilter allyouneed",
            summary: String(localized: "IP ranges blocked in Russia: blocked addresses and subnets in one list.", bundle: .main),
            url: URL(string: "https://antifilter.download/list/allyouneed.lst")!,
            kind: .addresses, country: "RU",
            source: URL(string: "https://antifilter.download")!),
        SuggestedList(
            id: "get_antifilter_ipsum.sh", name: "Antifilter ipsum",
            summary: String(localized: "IP addresses blocked in Russia, joined into /24 ranges.", bundle: .main),
            url: URL(string: "https://antifilter.download/list/ipsum.lst")!,
            kind: .addresses, country: "RU",
            source: URL(string: "https://antifilter.download")!),
        SuggestedList(
            id: "get_antifilter_ipsmart.sh", name: "Antifilter ipsmart",
            summary: String(localized: "IP addresses blocked in Russia, joined into ranges from /32 to /22.", bundle: .main),
            url: URL(string: "https://antifilter.network/download/ipsmart.lst")!,
            kind: .addresses, country: "RU",
            source: URL(string: "https://antifilter.network")!),
    ]

    public static func list(kind: ListKind) -> [SuggestedList] { all.filter { $0.kind == kind } }

    /// The suggestion with this address, if it is one.
    public static func matching(_ url: URL?) -> SuggestedList? {
        guard let url else { return nil }
        return all.first { $0.url == url }
    }
}
