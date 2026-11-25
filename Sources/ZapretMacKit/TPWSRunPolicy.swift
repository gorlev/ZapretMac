import Foundation

/// How a tpws is stopped: SIGTERM, wait up to `grace` checking every
/// `interval`, then SIGKILL. Never an unbounded wait.
public struct TPWSStopPolicy: Equatable, Sendable {
    public var grace: TimeInterval
    public var interval: TimeInterval

    public init(grace: TimeInterval, interval: TimeInterval) {
        self.grace = grace
        self.interval = interval
    }

    /// A tpws this app started: it quits at once on SIGTERM, so the port is
    /// free for a restart well within the grace time.
    public static let standard = TPWSStopPolicy(grace: 1.5, interval: 0.02)
    /// A tpws left behind by an earlier, force-quit run (found by its pid file).
    public static let leftover = TPWSStopPolicy(grace: 1.0, interval: 0.02)

    /// How many checks fit in the grace time.
    public var checks: Int { max(1, Int((grace / interval).rounded(.up))) }
    public var intervalMicroseconds: UInt32 { UInt32((interval * 1_000_000).rounded()) }
}

/// How long to wait for a started tpws to accept connections on its port.
/// "Ready" means the port answers, never that time passed or a line appeared.
public struct TPWSReadinessPlan: Equatable, Sendable {
    public var attempts: Int
    public var interval: Duration

    public init(attempts: Int, interval: Duration) {
        self.attempts = attempts
        self.interval = interval
    }

    /// The bypass: up to 3 s.
    public static let engine = TPWSReadinessPlan(attempts: 60, interval: .milliseconds(50))
    /// A strategy try: up to 1 s.
    public static let trial = TPWSReadinessPlan(attempts: 20, interval: .milliseconds(50))

    /// The longest the plan waits.
    public var limit: Duration { interval * attempts }
}

/// tpws quitting by itself is restarted once; a second exit within `window`
/// is a real failure.
public struct TPWSRestartPolicy: Sendable {
    public var window: TimeInterval
    public private(set) var recentCrashes: [Date] = []

    public init(window: TimeInterval = 60) {
        self.window = window
    }

    /// Records a crash at `now` and says whether to restart.
    public mutating func shouldRestart(at now: Date = .now) -> Bool {
        recentCrashes = recentCrashes.filter { $0 > now.addingTimeInterval(-window) }
        guard recentCrashes.isEmpty else { return false }
        recentCrashes.append(now)
        return true
    }
}
