import AppKit
import SwiftData
import SwiftUI

// ZapretMac
//   ZapretMac                      the app
//   APP_STORE=<file> ZapretMac     use another database (tests, experiments)
//   APP_SNAPSHOT=<dir> ZapretMac   save a PNG of every sidebar page and Settings tab in light and dark mode, then quit
//   APP_SEED=1 ZapretMac           fill an empty /tmp store with sample data and turn bypass on (tools/snap.sh)
//   ZapretMac --selftest           run the self-test on a /tmp store and quit with 0 or 1 (tools/selftest.sh)
//   APP_ACCENT=<id> ZapretMac      run with another accent from Theme.all (UI/Theme.swift)
//   APP_GRID=1 ZapretMac           draw the 8 pt grid and the layout probes over the window
//   TPWS_PATH=<file> ZapretMac     use another tpws binary

@main
struct ZapretMacApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var model: AppModel

    init() {
        let model = AppModel(container: Store.makeContainer())
        _model = State(initialValue: model)
        AppDelegate.model = model
    }

    var body: some Scene {
        Window("ZapretMac", id: "main") {
            ContentView()
                .environment(model)
                .themed()
                .overlay { if GridOverlay.enabled { GridOverlay() } }
                .frame(minWidth: 780, minHeight: 560)
        }
        .modelContainer(model.container)
        .defaultSize(width: 1040, height: 720)
        .windowToolbarStyle(.unified)
        .commands {
            SidebarCommands()
            ToolbarCommands()
            CommandGroup(replacing: .newItem) {
                Button("New Strategy…") { model.newStrategy() }
                    .keyboardShortcut("n")
                Button("New Strategy from Clipboard") { model.newStrategyFromClipboard() }
                    .keyboardShortcut("v", modifiers: [.command, .option])
                Button("Add Sites…") { model.requestAddSites() }
                    .keyboardShortcut("n", modifiers: [.command, .shift])
            }
            CommandMenu("Bypass") {
                Button(model.engine.isOn ? String(localized: "Turn Off") : String(localized: "Turn On")) { model.toggle() }
                    .keyboardShortcut("b")
                Button("Check Site") { model.runCheck() }
                    .keyboardShortcut("t")
                Button("Find a Strategy…") { model.openFinder() }
                    .keyboardShortcut("t", modifiers: [.command, .shift])
                Divider()
                Toggle("Use as System Proxy", isOn: Binding(
                    get: { model.prefs.useSystemProxy },
                    set: { model.prefs.useSystemProxy = $0; model.systemProxyChanged() }))
                Divider()
                Button("Copy tpws Command") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(model.command.commandLine(binary: Engine.binaryURL.path), forType: .string)
                }
            }
            CommandGroup(after: .sidebar) {
                ForEach(SidebarItem.allCases) { page in
                    Button(page.title) { model.sidebar = page }
                        .keyboardShortcut(KeyEquivalent(page.shortcut))
                }
                Divider()
            }
        }

        MenuBarExtra {
            MenuBarContent()
                .environment(model)
        } label: {
            Image(systemName: model.engine.menuBarSymbol)
                .accessibilityLabel(model.engine.state.title)
        }
        .menuBarExtraStyle(.menu)

        Settings {
            SettingsView()
                .environment(model)
                .themed()
        }
        .windowResizability(.contentSize)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    static var model: AppModel?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Started from a terminal, the process is not a foreground app yet.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
        guard let model = Self.model else { return }
        // The self-test needs no window, so it runs even when macOS does not
        // open one (a locked screen, restored state with no windows).
        SelfTest.runIfRequested(model: model)
        model.recoverFromCrash()
        // Test runs never register the person's shortcut (their prefs are a test suite anyway).
        if !Store.isOverridden { model.registerGlobalShortcut() }
        if model.prefs.startOnLaunch, !Store.isOverridden { model.turnOn() }
    }

    /// The menu bar item keeps the app, and the bypass, running.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationWillTerminate(_ notification: Notification) {
        GlobalHotKey.shared.unregister()
        Self.model?.engine.stop()
        Self.model?.proxy.restoreNow()
        // The self-test's result becomes the exit code, after a normal quit.
        if SelfTest.requested { exit(SelfTest.exitCode) }
    }
}

/// Where the data lives: ~/Library/Application Support/ZapretMac/
enum Store {
    /// True when APP_STORE points somewhere else (tests, snapshots, seed data).
    static var isOverridden: Bool {
        !(ProcessInfo.processInfo.environment["APP_STORE"] ?? "").isEmpty
    }

    static var url: URL {
        if let path = ProcessInfo.processInfo.environment["APP_STORE"], !path.isEmpty {
            return URL(fileURLWithPath: path)
        }
        return directory.appending(path: "ZapretMac.store")
    }

    /// The folder for the store and the hostlist files tpws reads.
    static var directory: URL {
        if let path = ProcessInfo.processInfo.environment["APP_STORE"], !path.isEmpty {
            let dir = URL(fileURLWithPath: path + "-files", isDirectory: true)
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            return dir
        }
        let dir = URL.applicationSupportDirectory.appending(path: "ZapretMac", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static var hostlistURL: URL { directory.appending(path: "hostlist.txt") }
    static var excludeURL: URL { directory.appending(path: "hostlist-exclude.txt") }
    static var pidURL: URL { directory.appending(path: "tpws.pid") }

    static func makeContainer() -> ModelContainer {
        do {
            return try ModelContainer(for: DomainEntry.self, CustomStrategy.self,
                                      configurations: ModelConfiguration(url: url))
        } catch {
            fatalError("Could not open the database at \(url.path): \(error)")
        }
    }
}
