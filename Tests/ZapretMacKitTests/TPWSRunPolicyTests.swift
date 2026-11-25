import Foundation
import Testing
@testable import ZapretMacKit

@Test func stopPolicyIsBounded() {
    #expect(TPWSStopPolicy.standard.grace == 1.5)
    #expect(TPWSStopPolicy.standard.checks == 75)
    #expect(TPWSStopPolicy.standard.intervalMicroseconds == 20_000)
    #expect(TPWSStopPolicy.leftover.checks == 50)
    #expect(TPWSStopPolicy(grace: 0, interval: 0.02).checks == 1)
}

@Test func readinessPlansWaitAShortTime() {
    #expect(TPWSReadinessPlan.engine.limit == .seconds(3))
    #expect(TPWSReadinessPlan.trial.limit == .seconds(1))
}

@Test func restartsOnceThenFails() {
    var policy = TPWSRestartPolicy()
    let start = Date(timeIntervalSinceReferenceDate: 1000)
    let first = policy.shouldRestart(at: start)
    let second = policy.shouldRestart(at: start.addingTimeInterval(30))
    // A minute after the first crash, a crash is restarted again.
    let later = policy.shouldRestart(at: start.addingTimeInterval(61))
    #expect(first)
    #expect(!second)
    #expect(later)
    #expect(policy.recentCrashes.count == 1)
}
