import Foundation

/// The result of trying one strategy against one site.
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

    public init(id: String, name: String, arguments: [String], status: Status = .waiting) {
        self.id = id
        self.name = name
        self.arguments = arguments
        self.status = status
    }

    public var works: Bool { if case .works = status { true } else { false } }

    /// Working strategies first, fastest first; then still running; failures last.
    /// Equal ranks keep their original order.
    public static func ranked(_ trials: [Trial]) -> [Trial] {
        func key(_ t: Trial) -> (Int, Int) {
            switch t.status {
            case .works(let ms): (0, ms)
            case .testing: (1, 0)
            case .waiting: (2, 0)
            case .fails: (3, 0)
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
