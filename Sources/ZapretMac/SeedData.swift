import Foundation
import SwiftData

/// Sample data for snapshots: APP_SEED=1 with APP_STORE in /tmp fills an empty
/// store with sites and one custom strategy, then turns the bypass on (tpws
/// on a test port, no system proxy), so the pages show real output.
@MainActor
enum SeedData {
    static func insertIfRequested(into model: AppModel) {
        guard ProcessInfo.processInfo.environment["APP_SEED"] == "1" else { return }
        guard Store.isOverridden else {
            print("APP_SEED ignored: APP_STORE must be a file in /tmp")
            return
        }
        let context = model.container.mainContext
        guard ((try? context.fetchCount(FetchDescriptor<DomainEntry>())) ?? 0) == 0 else { return }
        model.addDomains(from: "youtube.com googlevideo.com discord.com discord.gg discordapp.com roblox.com wattpad.com x.com",
                         excluded: false)
        model.addDomains(from: "apple.com icloud.com", excluded: true)
        // S-103: IP ranges (documentation ranges), shown in their own section.
        model.addDomains(from: "203.0.113.0/24 198.51.100.7 2001:db8:4e8::/48", excluded: false)
        if let off = model.domains(excluded: false).first(where: { $0.domain == "wattpad.com" }) { off.isEnabled = false }
        context.insert(CustomStrategy(name: "My ISP", commandLine: "--tlsrec=sniext+1 --split-pos=2,midsld --oob"))
        // Two subscriptions with no network: a list in the store folder, and
        // one whose last download failed.
        let failed = ListSubscription(url: "https://lists.example.org/ru/blocked.txt.gz")
        failed.domainCount = 18421
        failed.lastUpdated = Date.now.addingTimeInterval(-2 * 24 * 60 * 60)
        failed.lastError = String(localized: "The server answered with error \(404).")
        context.insert(failed)
        try? context.save()
        let community = Store.directory.appending(path: "community-hosts.txt")
        try? "# Community list\nrutracker.org\nrutor.info\nnnmclub.to\nlinkedin.com\nmedium.com\nsoundcloud.com\nproton.me\nsignal.org\n"
            .write(to: community, atomically: true, encoding: .utf8)
        Task { _ = await model.addSubscription(url: community, name: "Community", excluded: false) }
        model.prefs.useSystemProxy = false
        model.turnOn()
        // A little real traffic, so the log and the stats have something.
        Task {
            try? await Task.sleep(for: .seconds(0.8))
            for site in ["https://example.com", "https://www.wikipedia.org", "https://github.com"] {
                if let url = URL(string: site) { _ = await SiteCheck.fetch(url, socksPort: model.prefs.port) }
            }
            model.prefs.testURL = "https://example.com"
            model.prefs.finderSites = "https://example.com"
            model.runCheck()
        }
    }
}
