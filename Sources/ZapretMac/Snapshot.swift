import AppKit
import IOKit.pwr_mgt
import SwiftUI
import ZapretMacKit

/// Screenshot mode for automated checks.
///   APP_STORE=/tmp/test.store APP_SNAPSHOT=/tmp/shots ~/Applications/ZapretMac.app/Contents/MacOS/ZapretMac
/// writes <page>-light.png and <page>-dark.png for every sidebar page, and
/// settings-<tab>-light.png and settings-<tab>-dark.png for every Settings tab, then quits.
/// Each PNG gets a <page>-<mode>-layout.json with the grid probes (tools/check-layout.swift).
/// APP_SNAPSHOT_PAGES=all,starred limits the pages. Add "settings" to include Settings.
/// Add APP_ACCENT=<id> to see the pages in another accent.
enum Snapshot {
    static func runIfRequested(model: AppModel, openSettings: OpenSettingsAction) {
        let env = ProcessInfo.processInfo.environment
        guard let dir = env["APP_SNAPSHOT"], !dir.isEmpty else { return }
        // Snapshots never run against the real database.
        guard Store.isOverridden else {
            print("SNAPSHOT refused: set APP_STORE to a file in /tmp")
            NSApp.terminate(nil)
            return
        }
        let only = env["APP_SNAPSHOT_PAGES"].map { Set($0.split(separator: ",").map(String.init)) }
        Task {
            // A sleeping display gives screencapture nothing. Declaring user
            // activity wakes it; the assertion keeps it on until the run quits.
            var activity: IOPMAssertionID = 0
            IOPMAssertionDeclareUserActivity("Snapshots" as CFString, kIOPMUserActiveLocal, &activity)
            var awake: IOPMAssertionID = 0
            IOPMAssertionCreateWithName(kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString,
                                        IOPMAssertionLevel(kIOPMAssertionLevelOn), "Snapshots" as CFString, &awake)
            try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
            try? await Task.sleep(for: .seconds(1.5))
            for mode in ["light", "dark"] {
                NSApp.appearance = NSAppearance(named: mode == "light" ? .aqua : .darkAqua)
                for page in SidebarItem.allCases where only?.contains(page.rawValue) ?? true {
                    model.sidebar = page
                    try? await Task.sleep(for: .seconds(0.8))
                    capture(to: "\(dir)/\(page.rawValue)-\(mode).png")
                }
            }
            // The global shortcut's HUD (S-073), on and off. "hud" takes only this.
            if only == nil || only?.contains("extras") == true || only?.contains("hud") == true {
                for mode in ["light", "dark"] {
                    NSApp.appearance = NSAppearance(named: mode == "light" ? .aqua : .darkAqua)
                    for state in [Engine.State.running, .stopped] {
                        BypassHUD.shared.show(state: state)
                        try? await Task.sleep(for: .seconds(0.5))
                        capture(to: "\(dir)/hud-\(state == .running ? "on" : "off")-\(mode).png", window: BypassHUD.shared.window)
                    }
                }
                BypassHUD.shared.hide()
            }
            // Extras. The Add Subscription sheet also runs alone with
            // APP_SNAPSHOT_PAGES=domains,subscription (the rest scans for minutes).
            if only == nil || only?.contains("extras") == true || only?.contains("subscription") == true {
                let main = NSApp.windows.first { $0.canBecomeMain && !$0.isSheet }
                for mode in ["light", "dark"] {
                    NSApp.appearance = NSAppearance(named: mode == "light" ? .aqua : .darkAqua)
                    model.requestAddSubscription(excluded: false)
                    try? await Task.sleep(for: .seconds(1))
                    capture(to: "\(dir)/subscription-\(mode).png", window: main?.attachedSheet)
                    model.showAddSubscription = false
                    try? await Task.sleep(for: .seconds(0.6))
                }
            }
            // The strategy editor sheet, then Overview with the bypass off.
            if only == nil || only?.contains("extras") == true {
                let main = NSApp.windows.first { $0.canBecomeMain && !$0.isSheet }
                for mode in ["light", "dark"] {
                    NSApp.appearance = NSAppearance(named: mode == "light" ? .aqua : .darkAqua)
                    model.sidebar = .strategies
                    model.newStrategy(from: StrategyOptions(commandLine: "--split-pos=1,midsld --oob --disorder"),
                                      name: "My Provider")
                    try? await Task.sleep(for: .seconds(1))
                    capture(to: "\(dir)/editor-\(mode).png", window: main?.attachedSheet)
                    model.draft = nil
                    try? await Task.sleep(for: .seconds(0.6))
                }
                // Find a Strategy with real results for two sites.
                model.prefs.finderSites = "example.com wikipedia.org"
                model.openFinder()
                model.startFinder(urls: SiteCheck.urls(from: model.prefs.finderSites))
                for _ in 0..<600 where model.finder.isRunning { try? await Task.sleep(for: .milliseconds(100)) }
                for mode in ["light", "dark"] {
                    NSApp.appearance = NSAppearance(named: mode == "light" ? .aqua : .darkAqua)
                    try? await Task.sleep(for: .seconds(0.8))
                    capture(to: "\(dir)/finder-\(mode).png", window: main?.attachedSheet)
                }
                // The same sheet after a thorough scan (blockcheck's matrix).
                if let url = URL(string: "https://example.com") {
                    model.prefs.finderSites = "https://example.com"
                    model.startFinder(url: url, depth: .thorough)
                    for _ in 0..<900 where model.finder.isRunning { try? await Task.sleep(for: .milliseconds(100)) }
                }
                for mode in ["light", "dark"] {
                    NSApp.appearance = NSAppearance(named: mode == "light" ? .aqua : .darkAqua)
                    try? await Task.sleep(for: .seconds(0.8))
                    capture(to: "\(dir)/finder-thorough-\(mode).png", window: main?.attachedSheet)
                }
                model.finderDepth = .quick
                model.showFinder = false
                try? await Task.sleep(for: .seconds(0.6))
                model.turnOff()
                model.check = nil
                for mode in ["light", "dark"] {
                    NSApp.appearance = NSAppearance(named: mode == "light" ? .aqua : .darkAqua)
                    model.sidebar = .overview
                    try? await Task.sleep(for: .seconds(0.8))
                    capture(to: "\(dir)/overview-off-\(mode).png")
                }
            }
            // S-072: the System proxy caption in PAC mode (My list). Only the
            // preference is shown on; nothing applies the system proxy here.
            if only == nil || only?.contains("overview") == true {
                let scope = model.prefs.scope
                model.prefs.scope = .listOnly
                model.prefs.useSystemProxy = true
                for mode in ["light", "dark"] {
                    NSApp.appearance = NSAppearance(named: mode == "light" ? .aqua : .darkAqua)
                    model.sidebar = .overview
                    try? await Task.sleep(for: .seconds(0.8))
                    capture(to: "\(dir)/overview-pac-\(mode).png")
                }
                model.prefs.useSystemProxy = false
                model.prefs.scope = scope
            }
            // S-100: Sites with a few automatically added sites, seeded into the
            // test store's automatic file. "autohostlist" runs this alone.
            if only == nil || only?.contains("domains") == true || only?.contains("autohostlist") == true {
                let scope = model.prefs.scope
                let autoText = (try? String(contentsOf: Store.autoHostlistURL, encoding: .utf8)) ?? ""
                try? "rutracker.org\nnnmclub.to\ninstagram.com\nlinkedin.com\n"
                    .write(to: Store.autoHostlistURL, atomically: true, encoding: .utf8)
                model.prefs.scope = .listOnly
                model.prefs.autoHostlist = true
                model.reloadAutoSites()
                for mode in ["light", "dark"] {
                    NSApp.appearance = NSAppearance(named: mode == "light" ? .aqua : .darkAqua)
                    model.sidebar = .domains
                    try? await Task.sleep(for: .seconds(0.8))
                    capture(to: "\(dir)/domains-auto-\(mode).png")
                }
                try? autoText.write(to: Store.autoHostlistURL, atomically: true, encoding: .utf8)
                model.prefs.autoHostlist = false
                model.prefs.scope = scope
                model.reloadAutoSites()
            }
            // S-081: a fake helper shows as ready (nothing is installed or run as
            // root); Overview in Transparent mode, and Settings > Advanced with it on.
            if only == nil || only?.contains("overview") == true || only?.contains("settings") == true {
                HelperClient.shared.useFake(FakeHelperClient(), state: .ready)
                model.setTransparentMode(true)
                if !model.engine.isOn { model.turnOn() }
                for _ in 0..<50 where model.engine.state != .running { try? await Task.sleep(for: .milliseconds(100)) }
            }
            if only == nil || only?.contains("overview") == true {
                for mode in ["light", "dark"] {
                    NSApp.appearance = NSAppearance(named: mode == "light" ? .aqua : .darkAqua)
                    model.sidebar = .overview
                    try? await Task.sleep(for: .seconds(0.8))
                    capture(to: "\(dir)/overview-transparent-\(mode).png")
                }
            }
            if only == nil || only?.contains("settings") == true {
                let main = NSApp.windows.first { $0.canBecomeMain && !$0.isSheet }
                // A sample shortcut in the test suite, shown but never registered.
                if model.prefs.globalShortcut == nil {
                    model.prefs.globalShortcut = GlobalShortcut(keyCode: 11, modifiers: [.control, .option])
                }
                openSettings()
                try? await Task.sleep(for: .seconds(1))
                for mode in ["light", "dark"] {
                    NSApp.appearance = NSAppearance(named: mode == "light" ? .aqua : .darkAqua)
                    for tab in SettingsTab.allCases {
                        model.settingsTab = tab
                        try? await Task.sleep(for: .seconds(0.8))
                        let settings = NSApp.windows.first { $0.isVisible && $0 !== main && !$0.isSheet && $0.frame.width > 300 }
                        capture(to: "\(dir)/settings-\(tab.rawValue)-\(mode).png", window: settings)
                    }
                }
            }
            print("SNAPSHOT done \(dir)")
            // An open sheet refuses terminate, and the run would wait forever.
            for window in NSApp.windows { if let sheet = window.attachedSheet { window.endSheet(sheet) } }
            NSApp.terminate(nil)
        }
    }

    /// Captures the real window with screencapture, so glass, sidebars, and
    /// materials look exactly as on screen. That needs Screen Recording
    /// permission for the app that started this one (for example, your terminal).
    /// Without it, falls back to drawing the view hierarchy, which leaves
    /// sidebars and glass blank.
    private static func capture(to path: String, window: NSWindow? = nil) {
        // Another app can hide this one while snapshots run (computer use hides
        // apps it does not control). Hidden windows cannot be captured.
        if NSApp.isHidden { NSApp.unhideWithoutActivation() }
        guard let window = window ?? NSApp.windows.first(where: { $0.canBecomeMain && !$0.isSheet }) else {
            print("SNAPSHOT no window")
            return
        }
        // Active, like a window someone is using: real accent colors and focus rings.
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
        let size = window.contentView?.bounds.size ?? .zero
        GridProbes.shared.write(to: path.replacingOccurrences(of: ".png", with: "-layout.json"), window: size)
        try? FileManager.default.removeItem(atPath: path)
        // The first capture of a run sometimes misses the window. Try three times.
        for _ in 1...3 {
            let shot = Process()
            shot.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
            shot.arguments = ["-x", "-o", "-l", String(window.windowNumber), path]
            try? shot.run()
            shot.waitUntilExit()
            if FileManager.default.fileExists(atPath: path) {
                print("SNAPSHOT \(path)")
                return
            }
            Thread.sleep(forTimeInterval: 0.5)
        }
        guard let view = window.contentView?.superview ?? window.contentView,
              let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        if let data = rep.representation(using: .png, properties: [:]) {
            try? data.write(to: URL(fileURLWithPath: path))
            print("SNAPSHOT \(path) (fallback: no Screen Recording permission, sidebars and glass are blank)")
        }
    }
}
