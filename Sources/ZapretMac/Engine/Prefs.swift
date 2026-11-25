import Foundation
import Observation
import ZapretMacKit

/// The app's choices, saved in UserDefaults. Test, seed, and snapshot runs
/// (APP_STORE set) use their own suite, so they never change the real ones.
@Observable
final class Prefs {
    static let shared = Prefs()

    let defaults: UserDefaults

    var port: Int { didSet { defaults.set(port, forKey: "port") } }
    /// "preset:<id>" or "custom:<uuid>".
    var strategyID: String { didSet { defaults.set(strategyID, forKey: "strategy") } }
    var scope: Scope { didSet { defaults.set(scope.rawValue, forKey: "scope") } }
    var useSystemProxy: Bool { didSet { defaults.set(useSystemProxy, forKey: "systemProxy") } }
    var startOnLaunch: Bool { didSet { defaults.set(startOnLaunch, forKey: "startOnLaunch") } }
    var verboseLog: Bool { didSet { defaults.set(verboseLog, forKey: "verboseLog") } }
    var testURL: String { didSet { defaults.set(testURL, forKey: "testURL") } }
    /// The sites Find a Strategy tries, one per line or separated by spaces or commas.
    var finderSites: String { didSet { defaults.set(finderSites, forKey: "finderSites") } }
    /// The shortcut that turns the bypass on and off in any app. None until the person records one.
    var globalShortcut: GlobalShortcut? {
        didSet { defaults.set(globalShortcut.flatMap { try? JSONEncoder().encode($0) }, forKey: "globalShortcut") }
    }

    static let defaultPort = 1088

    /// ZM_SLOT=<n>: a parallel worker's test runs get their own defaults and port.
    static var slotNumber: Int { Int(ProcessInfo.processInfo.environment["ZM_SLOT"] ?? "") ?? 0 }
    static var slotSuffix: String { slotNumber == 0 ? "" : ".slot\(slotNumber)" }

    private init() {
        if Store.isOverridden {
            let suite = "com.gorlev.zapretmac.test" + Self.slotSuffix
            UserDefaults().removePersistentDomain(forName: suite)
            defaults = UserDefaults(suiteName: suite)!
        } else {
            defaults = .standard
        }
        let d = defaults
        port = (d.object(forKey: "port") as? Int) ?? (Store.isOverridden ? 19881 + Self.slotNumber * 10 : Self.defaultPort)
        strategyID = d.string(forKey: "strategy") ?? "preset:\(Preset.defaultID)"
        scope = Scope(rawValue: d.string(forKey: "scope") ?? "") ?? .allSites
        useSystemProxy = (d.object(forKey: "systemProxy") as? Bool) ?? !Store.isOverridden
        startOnLaunch = d.bool(forKey: "startOnLaunch")
        verboseLog = (d.object(forKey: "verboseLog") as? Bool) ?? true
        let testURL = d.string(forKey: "testURL") ?? "https://discord.com"
        self.testURL = testURL
        finderSites = d.string(forKey: "finderSites") ?? testURL
        globalShortcut = Self.savedShortcut(in: d)
    }

    /// The shortcut as saved, read straight from the defaults.
    static func savedShortcut(in defaults: UserDefaults) -> GlobalShortcut? {
        defaults.data(forKey: "globalShortcut").flatMap { try? JSONDecoder().decode(GlobalShortcut.self, from: $0) }
    }
}
