import Foundation
import Testing
@testable import ZapretMacKit

@Test func scanPlanCounts() {
    #expect(ScanPlan.https.count == 39)
    // 6 header tricks + 5 paddings + 3 splits x 4 + 3 method tricks
    #expect(ScanPlan.http.count == 26)
}

@Test func scanPlanPicksSetByScheme() {
    #expect(ScanPlan.tries(for: URL(string: "http://example.com")!) == ScanPlan.http)
    #expect(ScanPlan.tries(for: URL(string: "https://example.com")!) == ScanPlan.https)
}

@Test func scanPlanFollowsMacOSRules() {
    for t in ScanPlan.https + ScanPlan.http {
        #expect(!(t.arguments.contains("--oob") && t.arguments.contains("--disorder")), "\(t.flags)")
        #expect(!t.arguments.contains { $0.hasPrefix("--mss") || $0.hasPrefix("--fix-seg") }, "\(t.flags)")
    }
}

@Test func scanPlanIDsAreUnique() {
    // Unique within each set; the same flags in both sets share one id.
    for set in [ScanPlan.https, ScanPlan.http] { #expect(Set(set.map(\.id)).count == set.count) }
    let all = ScanPlan.https + ScanPlan.http
    #expect(all.allSatisfy { $0.id.hasPrefix(ScanPlan.idPrefix) })
    #expect(Trial(id: all[0].id, name: all[0].name, arguments: all[0].arguments).isScan)
    #expect(!Trial(id: "preset:oob", name: "", arguments: []).isScan)
}

@Test func scanPlanParsesWithStrategyOptions() {
    // StrategyOptions may not know --hostpad and --hostspell yet.
    let allowed = ["--hostpad=", "--hostspell="]
    for t in ScanPlan.https + ScanPlan.http {
        let options = StrategyOptions(arguments: t.arguments)
        let unknown = options.extra.filter { arg in !allowed.contains { arg.hasPrefix($0) } }
        #expect(unknown.isEmpty, "\(t.flags)")
        #expect(Set(options.arguments) == Set(t.arguments), "\(t.flags)")
    }
}

@Test func scanPlanContainsBlockcheckTries() {
    let flags = Set(ScanPlan.https.map(\.flags))
    #expect(flags.contains("--split-pos=1,sniext+1,host+1,midsld,endhost-1 --oob"))
    #expect(flags.contains("--tlsrec=sniext+4 --split-pos=1,midsld --disorder"))
    #expect(flags.contains("--tlsrec=midsld"))
    let http = Set(ScanPlan.http.map(\.flags))
    #expect(http.contains("--hostspell=hoSt"))
    #expect(http.contains("--hostpad=16384"))
    #expect(http.contains("--split-pos=method+2,midsld --hostcase"))
    #expect(ScanPlan.http.last?.flags == "--methodeol")
}

@Test func scanTryNames() {
    #expect(ScanTry(arguments: ["--split-pos=sniext+1", "--oob"]).name == "Split at sniext+1 · OOB")
    #expect(ScanTry(arguments: ["--tlsrec=sniext+4", "--split-pos=1,midsld", "--disorder"]).name
        == "TLS records at sniext+4 · Split at 1,midsld · Disorder")
}
