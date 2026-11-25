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
        status = Self.combine(attempts)
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
