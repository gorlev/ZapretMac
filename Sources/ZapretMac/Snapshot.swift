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
            // The menu bar panel, on and off, in a window like the panel's.
            // "menubar" takes only this.
            if only == nil || only?.contains("extras") == true || only?.contains("menubar") == true {
                let panel = NSWindow(contentRect: NSRect(x: 200, y: 200, width: 320, height: 480),
                                     styleMask: [.titled, .fullSizeContentView], backing: .buffered, defer: false)
                panel.titlebarAppearsTransparent = true
                panel.titleVisibility = .hidden
                for button in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
                    panel.standardWindowButton(button)?.isHidden = true
                }
                let blur = NSVisualEffectView()
                blur.material = .popover
                blur.state = .active
                let host = NSHostingView(rootView: MenuBarContent().environment(model).modelContainer(model.container).ignoresSafeArea())
                host.translatesAutoresizingMaskIntoConstraints = false
                blur.addSubview(host)
                NSLayoutConstraint.activate([host.topAnchor.constraint(equalTo: blur.topAnchor),
                                             host.bottomAnchor.constraint(equalTo: blur.bottomAnchor),
                                             host.leadingAnchor.constraint(equalTo: blur.leadingAnchor),
                                             host.trailingAnchor.constraint(equalTo: blur.trailingAnchor)])
                panel.contentView = blur
                panel.setContentSize(host.fittingSize)
                let wasOn = model.engine.isOn
                for state in ["on", "off"] {
                    if state == "off" { model.turnOff() } else if !model.engine.isOn { model.turnOn() }
                    for _ in 0..<50 where model.engine.isOn != (state == "on") || model.engine.state == .starting {
                        try? await Task.sleep(for: .milliseconds(100))
                    }
                    for mode in ["light", "dark"] {
                        NSApp.appearance = NSAppearance(named: mode == "light" ? .aqua : .darkAqua)
                        try? await Task.sleep(for: .seconds(0.6))
                        host.layoutSubtreeIfNeeded()
                        panel.setContentSize(NSSize(width: 320, height: host.intrinsicContentSize.height > 0 ? host.intrinsicContentSize.height : host.fittingSize.height))
                        capture(to: "\(dir)/menubar-\(state)-\(mode).png", window: panel)
                    }
                }
                panel.orderOut(nil)
                if wasOn {
                    model.turnOn()
                    for _ in 0..<50 where model.engine.state != .running { try? await Task.sleep(for: .milliseconds(100)) }
                }
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
            // S-103 S-106: the Add Subscription sheet with an IP list suggestion
            // chosen (the plain sheet above shows the suggestions). Sites with its
            // IP Addresses section is domains-<mode>.png (the seed has ranges).
            // Runs alone with APP_SNAPSHOT_PAGES=domains,suggestions.
            if only == nil || only?.contains("extras") == true || only?.contains("suggestions") == true {
                let main = NSApp.windows.first { $0.canBecomeMain && !$0.isSheet }
                for mode in ["light", "dark"] {
                    NSApp.appearance = NSAppearance(named: mode == "light" ? .aqua : .darkAqua)
                    model.addSubscriptionSuggestion = SuggestedLists.list(kind: .addresses).first
                    model.requestAddSubscription(excluded: false)
                    try? await Task.sleep(for: .seconds(1))
                    capture(to: "\(dir)/subscription-suggested-\(mode).png", window: main?.attachedSheet)
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
            // S-107: the strategy editor's Advanced section with the remaining
            // tpws options set. "editor-advanced" takes only this.
            if only == nil || only?.contains("extras") == true || only?.contains("editor-advanced") == true {
                let main = NSApp.windows.first { $0.canBecomeMain && !$0.isSheet }
                for mode in ["light", "dark"] {
                    NSApp.appearance = NSAppearance(named: mode == "light" ? .aqua : .darkAqua)
                    model.sidebar = .strategies
                    model.newStrategy(from: StrategyOptions(commandLine: "--split-pos=1,midsld --disorder=tls --oob=http"
                                                            + " --oob-data=0x01 --filter-l7=http,tls --tamper-start=n1 --tamper-cutoff=n3"),
                                      name: "My Provider")
                    try? await Task.sleep(for: .seconds(1))
                    if let sheet = main?.attachedSheet { scrollToEnd(sheet.contentView) }
                    try? await Task.sleep(for: .seconds(0.5))
                    capture(to: "\(dir)/editor-advanced-\(mode).png", window: main?.attachedSheet)
                    model.draft = nil
                    try? await Task.sleep(for: .seconds(0.6))
                }
            }
            // S-101 S-102: Find a Strategy with a verdict line (a fake system
            // resolver gives the DNS verdict) and a thorough scan's TLS columns,
            // stopped after a few rows. Runs alone with APP_SNAPSHOT_PAGES=verdict.
            if only == nil || only?.contains("verdict") == true, let url = URL(string: "https://example.com") {
                let main = NSApp.windows.first { $0.canBecomeMain && !$0.isSheet }
                model.prefs.finderSites = "https://example.com"
                model.finder.resolver = { _ in ["195.208.4.1"] }
                model.openFinder()
                model.finderDepth = .thorough
                model.startFinder(url: url, depth: .thorough)
                for _ in 0..<900 where model.finder.finishedCount < 6 && model.finder.isRunning {
                    try? await Task.sleep(for: .milliseconds(100))
                }
                model.finder.stop()
                // One row that works only with TLS 1.3, to show its note.
                if let i = model.finder.trials.firstIndex(where: \.works) {
                    model.finder.pretendTLS12FailedForSnapshot(at: i)
                }
                for mode in ["light", "dark"] {
                    NSApp.appearance = NSAppearance(named: mode == "light" ? .aqua : .darkAqua)
                    try? await Task.sleep(for: .seconds(0.8))
                    capture(to: "\(dir)/finder-verdict-\(mode).png", window: main?.attachedSheet)
                }
                model.finder.resolver = BlockCheck.systemResolver
                model.finderDepth = .quick
                model.showFinder = false
                try? await Task.sleep(for: .seconds(0.6))
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
            // S-104: Settings > General with sharing on (address and QR code).
            // Only the preference is set; tpws is not started. "share" runs it alone.
            if only == nil || only?.contains("share") == true {
                let main = NSApp.windows.first { $0.canBecomeMain && !$0.isSheet }
                let sharing = model.prefs.shareOnNetwork
                model.prefs.shareOnNetwork = true
                model.shareMonitor.refresh()
                model.settingsTab = .general
                openSettings()
                try? await Task.sleep(for: .seconds(1))
                for mode in ["light", "dark"] {
                    NSApp.appearance = NSAppearance(named: mode == "light" ? .aqua : .darkAqua)
                    try? await Task.sleep(for: .seconds(0.8))
                    let settings = NSApp.windows.first { $0.isVisible && $0 !== main && !$0.isSheet && $0.frame.width > 300 }
                    capture(to: "\(dir)/settings-share-\(mode).png", window: settings)
                }
                model.prefs.shareOnNetwork = sharing
                NSApp.windows.first { $0.isVisible && $0 !== main && !$0.isSheet && $0.frame.width > 300 }?.close()
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

    /// Scrolls the first vertical scroll view under `view` to its end, to show
    /// the last sections of a long sheet.
    private static func scrollToEnd(_ view: NSView?) {
        guard let view else { return }
        if let scroll = view as? NSScrollView, let document = scroll.documentView,
           document.frame.height > scroll.contentView.bounds.height {
            let y = document.isFlipped ? document.frame.height - scroll.contentView.bounds.height : 0
            scroll.contentView.scroll(to: NSPoint(x: 0, y: y))
            scroll.reflectScrolledClipView(scroll.contentView)
            return
        }
        for sub in view.subviews { scrollToEnd(sub) }
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
