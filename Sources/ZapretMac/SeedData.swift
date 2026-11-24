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
        if let off = model.domains(excluded: false).first(where: { $0.domain == "wattpad.com" }) { off.isEnabled = false }
        context.insert(CustomStrategy(name: "My ISP", commandLine: "--tlsrec=sniext+1 --split-pos=2,midsld --oob"))
        try? context.save()
        model.prefs.useSystemProxy = false
        model.turnOn()
        // A little real traffic, so the log and the stats have something.
        Task {
            try? await Task.sleep(for: .seconds(0.8))
            for site in ["https://example.com", "https://www.wikipedia.org", "https://github.com"] {
                if let url = URL(string: site) { _ = await SiteCheck.fetch(url, socksPort: model.prefs.port) }
            }
            model.prefs.testURL = "https://example.com"
            model.runCheck()
        }
    }
}
