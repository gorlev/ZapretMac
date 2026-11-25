import Foundation

/// What happened when one site was opened through one strategy.
public struct SiteAttempt: Equatable, Sendable {
    public enum Result: Equatable, Sendable {
        case opens(milliseconds: Int)
        case fails(String)
    }

    /// The site's host, as shown to the user.
    public let site: String
    public let result: Result

    public init(site: String, result: Result) {
        self.site = site
        self.result = result
    }

    public var opens: Bool { if case .opens = result { true } else { false } }

    /// One site tried several times: it opens only if every try opened, in
    /// the slowest try's time; otherwise it fails with the first failure's reason.
    public static func combine(repeats: [SiteAttempt]) -> SiteAttempt? {
        guard let first = repeats.first else { return nil }
        var slowest = 0
        for attempt in repeats {
            switch attempt.result {
            case .opens(let ms): slowest = max(slowest, ms)
            case .fails: return attempt
            }
        }
        return SiteAttempt(site: first.site, result: .opens(milliseconds: slowest))
    }
}

/// A TLS version a thorough scan tries separately, like blockcheck's
/// `--tlsv1.3` and `--tlsv1.2 --tls-max 1.2`.
public enum TLSVersion: String, CaseIterable, Sendable, Hashable {
    case tls13 = "1.3", tls12 = "1.2"

    /// "TLS 1.3".
    public var name: String { "TLS \(rawValue)" }
}

/// Every site's result with one TLS version, after every repeat.
public struct VersionResult: Equatable, Sendable {
    public let version: TLSVersion
    public let sites: [SiteAttempt]

    public init(version: TLSVersion, sites: [SiteAttempt]) {
        self.version = version
        self.sites = sites
    }

    /// Repeats of the same sites (each inner list is one repeat, sites in
    /// order) folded into one result per site.
    public init(version: TLSVersion, repeats: [[SiteAttempt]]) {
        self.init(version: version, sites: Trial.combine(repeats: repeats))
    }

    /// Every site opened with this version.
    public var opens: Bool { !sites.isEmpty && sites.allSatisfy(\.opens) }
}

/// The result of trying one strategy against one or more sites.
public struct Trial: Identifiable, Equatable, Sendable {
    public enum Status: Equatable, Sendable {
        case waiting, testing
        case works(milliseconds: Int)
        case fails(String)
    }

    /// The strategy's selection id ("preset:..." or "custom:...").
    public let id: String
    public let name: String
    public let arguments: [String]
    public var status: Status = .waiting
    /// One entry per site, in the order the sites were given. Empty until the try finishes.
    public var sites: [SiteAttempt] = []
    /// Thorough scans of https:// sites: the result with each TLS version.
    /// Empty for quick finds and http:// scans.
    public var versions: [VersionResult] = []

    public init(id: String, name: String, arguments: [String], status: Status = .waiting) {
        self.id = id
        self.name = name
        self.arguments = arguments
        self.status = status
    }

    public var works: Bool { if case .works = status { true } else { false } }

    /// How many of the sites opened.
    public var openCount: Int { sites.filter(\.opens).count }
    /// The sites that did not open, in order.
    public var failedSites: [SiteAttempt] { sites.filter { !$0.opens } }
    /// Some sites opened and some did not.
    public var isPartial: Bool { sites.count > 1 && openCount > 0 && openCount < sites.count }

    /// Records every site's result and the status they add up to.
    public mutating func finish(with attempts: [SiteAttempt]) {
        sites = attempts
        versions = []
        status = Self.combine(attempts)
    }

    /// Records each TLS version's results. A site opens only if it opened with
    /// every version; a failure names the version it failed with.
    public mutating func finish(versions results: [VersionResult]) {
        guard let first = results.first else { return finish(with: []) }
        let joined = first.sites.indices.map { i -> SiteAttempt in
            let site = first.sites[i].site
            var slowest = 0
            for result in results where i < result.sites.count {
                switch result.sites[i].result {
                case .opens(let ms): slowest = max(slowest, ms)
                case .fails(let reason):
                    return SiteAttempt(site: site, result: .fails("\(result.version.name): \(reason)"))
                }
            }
            return SiteAttempt(site: site, result: .opens(milliseconds: slowest))
        }
        sites = joined
        versions = results
        status = Self.combine(joined)
    }

    /// Whether the try worked with a version; nil if that version was not tried.
    public func works(with version: TLSVersion) -> Bool? {
        versions.first { $0.version == version }?.opens
    }

    /// Several repeats over the same sites (each inner list is one repeat,
    /// sites in order) folded per site: a site opens only if every repeat opened.
    public static func combine(repeats: [[SiteAttempt]]) -> [SiteAttempt] {
        guard let first = repeats.first else { return [] }
        return first.indices.compactMap { i in
            SiteAttempt.combine(repeats: repeats.compactMap { i < $0.count ? $0[i] : nil })
        }
    }

    /// A strategy works only if every site opens; its time is the slowest
    /// site's. Otherwise it fails with the first failing site's reason.
    public static func combine(_ attempts: [SiteAttempt]) -> Status {
        var slowest = 0
        for attempt in attempts {
            switch attempt.result {
            case .opens(let ms): slowest = max(slowest, ms)
            case .fails(let reason): return .fails(reason)
            }
        }
        return attempts.isEmpty ? .waiting : .works(milliseconds: slowest)
    }

    /// Working strategies first, fastest first; then still running; failures
    /// last, those that opened more sites first. Equal ranks keep their order.
    public static func ranked(_ trials: [Trial]) -> [Trial] {
        func key(_ t: Trial) -> (Int, Int) {
            switch t.status {
            case .works(let ms): (0, ms)
            case .testing: (1, 0)
            case .waiting: (2, 0)
            case .fails: (3, -t.openCount)
            }
        }
        return trials.enumerated()
            .sorted { a, b in
                let ka = key(a.element), kb = key(b.element)
                return ka != kb ? ka < kb : a.offset < b.offset
            }
            .map(\.element)
    }
}
