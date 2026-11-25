import AppKit
import Foundation
import ServiceManagement
import SwiftData
import ZapretMacKit

/// A site in one of the two lists.
@Model
final class DomainEntry {
    var domain: String
    /// false: "Sites to unblock". true: "Never touch".
    var isExcluded: Bool = false
    var isEnabled: Bool = true
    var createdAt: Date = Date.now
    var uuid: UUID = UUID()

    init(domain: String, isExcluded: Bool = false) {
        self.domain = domain
        self.isExcluded = isExcluded
    }
}

/// A strategy a person made, stored as tpws flags.
@Model
final class CustomStrategy {
    var name: String
    var commandLine: String
    var createdAt: Date = Date.now
    var uuid: UUID = UUID()

    init(name: String, commandLine: String) {
        self.name = name
        self.commandLine = commandLine
    }

    var options: StrategyOptions { StrategyOptions(commandLine: commandLine) }
    var selectionID: String { "custom:\(uuid.uuidString)" }
}

/// The sidebar pages. Snapshot mode walks through every case.
enum SidebarItem: String, CaseIterable, Identifiable {
    case overview, strategies, domains, log

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview: String(localized: "Overview")
        case .strategies: String(localized: "Strategies")
        case .domains: String(localized: "Sites")
        case .log: String(localized: "Log")
        }
    }

    var symbol: String {
        switch self {
        case .overview: "shield.lefthalf.filled"
        case .strategies: "slider.horizontal.3"
        case .domains: "globe"
        case .log: "text.alignleft"
        }
    }

    var shortcut: Character {
        switch self {
        case .overview: "1"
        case .strategies: "2"
        case .domains: "3"
        case .log: "4"
        }
    }
}

/// What the strategy editor sheet is working on.
struct StrategyDraft: Identifiable {
    var id = UUID()
    /// The custom strategy being edited, or nil for a new one.
    var editing: UUID?
    var name: String
    var options: StrategyOptions
}

/// App-wide state that menus, toolbars, and views share.
@Observable
final class AppModel {
    let container: ModelContainer
    let engine = Engine()
    let prefs = Prefs.shared
    let proxy: SystemProxy
    /// Serves the PAC file while the system proxy is in PAC mode (S-072).
    let pacServer = PACServer()
    let finder = StrategyFinder()
    var showFinder = false
    /// Quick tries the strategies; Thorough runs blockcheck's tpws matrix.
    var finderDepth: ScanDepth = .quick
    /// The page reopens where it was left. Test and snapshot runs start on Overview.
    var sidebar: SidebarItem? = Store.isOverridden ? .overview
        : SidebarItem(rawValue: UserDefaults.standard.string(forKey: "sidebar.page") ?? "") ?? .overview {
        didSet { if !Store.isOverridden, let sidebar { UserDefaults.standard.set(sidebar.rawValue, forKey: "sidebar.page") } }
    }
    var draft: StrategyDraft?
    /// Bumped by the Add Sites command; the Sites page focuses its field.
    var addSitesRequest = 0
    var check: SiteCheck.Result?
    var isChecking = false
    /// The Add Subscription sheet, and which list a new subscription feeds.
    var showAddSubscription = false
    var addSubscriptionExcluded = false
    /// Subscriptions downloading now, by uuid: their rows show progress.
    var updatingSubscriptions = Set<UUID>()
    /// Checks once an hour whether a subscription is a day old.
    @ObservationIgnored var subscriptionTimer: Timer?
    /// Settings reopens on the last tab. Test and snapshot runs leave it alone.
    var settingsTab: SettingsTab = SettingsTab(rawValue: UserDefaults.standard.string(forKey: "settings.tab") ?? "") ?? .general {
        didSet { if !Store.isOverridden { UserDefaults.standard.set(settingsTab.rawValue, forKey: "settings.tab") } }
    }

    init(container: ModelContainer) {
        self.container = container
        proxy = SystemProxy(defaults: Prefs.shared.defaults)
        engine.onFailure = { [weak self] reason in
            guard let self else { return }
            // Nothing listens on the port now: give apps their old proxy back.
            if proxy.isApplied || pacServer.isRunning { Task { await self.releaseProxy() } }
            if !Store.isOverridden { Notifier.post(title: String(localized: "ZapretMac stopped"), body: reason) }
        }
    }

    private var context: ModelContext { container.mainContext }

    // MARK: - Undo

    /// Ties SwiftData to the window's undo manager, so Edit > Undo brings
    /// back deleted sites and strategies, and rewrites the hostlist files.
    func attachUndo(_ undoManager: UndoManager?) {
        guard let undoManager, context.undoManager !== undoManager else { return }
        context.undoManager = undoManager
        for name in [NSNotification.Name.NSUndoManagerDidUndoChange, .NSUndoManagerDidRedoChange] {
            NotificationCenter.default.addObserver(forName: name, object: undoManager, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.listsChanged() }
            }
        }
    }

    private func undoName(_ name: String) {
        context.undoManager?.setActionName(name)
    }

    func requestAddSites() {
        sidebar = .domains
        addSitesRequest += 1
    }

    // MARK: - Strategies

    func customStrategies() -> [CustomStrategy] {
        (try? context.fetch(FetchDescriptor<CustomStrategy>(sortBy: [SortDescriptor(\.createdAt)]))) ?? []
    }

    /// The chosen strategy's name and flags. Falls back to the default preset
    /// when the chosen custom one was deleted.
    var activeStrategy: (name: String, arguments: [String]) {
        let id = prefs.strategyID
        if id.hasPrefix("custom:"), let custom = customStrategies().first(where: { $0.selectionID == id }) {
            return (custom.name, custom.options.arguments)
        }
        let preset = Preset.with(id: String(id.dropFirst("preset:".count))) ?? Preset.with(id: Preset.defaultID)!
        return (preset.name, preset.options.arguments)
    }

    func choose(strategy id: String) {
        guard prefs.strategyID != id else { return }
        prefs.strategyID = id
        restartIfRunning()
    }

    func newStrategy(from options: StrategyOptions = StrategyOptions(commandLine: "--split-pos=1,midsld"), name: String = "") {
        draft = StrategyDraft(editing: nil, name: name, options: options)
    }

    /// tpws flags on the clipboard, or nil when it holds something else.
    var clipboardFlags: StrategyOptions? {
        guard let text = NSPasteboard.general.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines),
              text.hasPrefix("--"), text.count < 2000 else { return nil }
        return StrategyOptions(commandLine: text)
    }

    func newStrategyFromClipboard() {
        guard let options = clipboardFlags else { NSSound.beep(); return }
        newStrategy(from: options, name: "")
    }

    func copyFlags(_ commandLine: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(commandLine, forType: .string)
    }

    func edit(_ strategy: CustomStrategy) {
        draft = StrategyDraft(editing: strategy.uuid, name: strategy.name, options: strategy.options)
    }

    @discardableResult
    func save(_ draft: StrategyDraft) -> CustomStrategy {
        let name = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let strategy: CustomStrategy
        if let id = draft.editing, let existing = customStrategies().first(where: { $0.uuid == id }) {
            existing.name = name
            existing.commandLine = draft.options.commandLine
            strategy = existing
        } else {
            strategy = CustomStrategy(name: name, commandLine: draft.options.commandLine)
            context.insert(strategy)
        }
        try? context.save()
        if prefs.strategyID == strategy.selectionID { restartIfRunning() } else { choose(strategy: strategy.selectionID) }
        return strategy
    }

    func delete(_ strategy: CustomStrategy) {
        let wasActive = prefs.strategyID == strategy.selectionID
        context.delete(strategy)
        try? context.save()
        undoName("Delete Strategy")
        if wasActive { choose(strategy: "preset:\(Preset.defaultID)") }
    }

    // MARK: - Sites

    func domains(excluded: Bool) -> [DomainEntry] {
        let all = (try? context.fetch(FetchDescriptor<DomainEntry>(sortBy: [SortDescriptor(\.domain)]))) ?? []
        return all.filter { $0.isExcluded == excluded }
    }

    /// Adds every domain in pasted text. Returns how many were new.
    @discardableResult
    func addDomains(from text: String, excluded: Bool) -> Int {
        let existing = Set(domains(excluded: excluded).map(\.domain))
        var added = 0
        for domain in Domains.parseList(text) where !existing.contains(domain) {
            context.insert(DomainEntry(domain: domain, isExcluded: excluded))
            added += 1
        }
        try? context.save()
        if added > 0 {
            undoName(String(localized: "Add \(added) Sites"))
            listsChanged()
        }
        return added
    }

    func remove(_ entries: [DomainEntry]) {
        for entry in entries { context.delete(entry) }
        try? context.save()
        undoName(String(localized: "Delete \(entries.count) Sites"))
        listsChanged()
    }

    /// The lists feed tpws only through files: rewrite them and restart.
    func listsChanged() {
        try? context.save()
        writeLists()
        restartIfRunning()
    }

    /// My list plus the turned-on subscriptions: what tpws and the PAC file use.
    func mergedDomains(excluded: Bool) -> [String] {
        let own = domains(excluded: excluded).filter(\.isEnabled).map(\.domain)
        let lists = subscriptions(excluded: excluded).filter(\.isEnabled).map(subscriptionDomains)
        return SiteListSubscription.merge(own, lists)
    }

    /// Writes My list and the turned-on subscriptions into the two files tpws
    /// reads. Returns true when either file's domains changed.
    @discardableResult
    func writeLists() -> Bool {
        var changed = false
        for excluded in [false, true] {
            let text = Domains.fileContents(mergedDomains(excluded: excluded))
            let url = excluded ? Store.excludeURL : Store.hostlistURL
            if (try? String(contentsOf: url, encoding: .utf8)) != text {
                changed = true
                try? text.write(to: url, atomically: true, encoding: .utf8)
            }
        }
        return changed
    }

    var includeCount: Int { domains(excluded: false).filter(\.isEnabled).count }

    // MARK: - On and off

    var command: TPWSCommand {
        let exclude = domains(excluded: true).contains(where: \.isEnabled)
            || subscriptions(excluded: true).contains { $0.isEnabled && $0.domainCount > 0 }
        return TPWSCommand(port: prefs.port, strategy: activeStrategy.arguments, scope: prefs.scope,
                           hostlistPath: Store.hostlistURL.path,
                           excludePath: exclude ? Store.excludeURL.path : nil,
                           debug: prefs.verboseLog, pidFile: Store.pidURL.path)
    }

    func toggle() {
        if engine.isOn { turnOff() } else { turnOn() }
    }

    // MARK: - Global shortcut (S-073)

    /// True when macOS refused the shortcut, usually because another app uses it.
    var globalShortcutFailed = false

    /// Saves a newly recorded shortcut (nil removes it) and registers it system-wide.
    func setGlobalShortcut(_ shortcut: GlobalShortcut?) {
        prefs.globalShortcut = shortcut
        registerGlobalShortcut()
    }

    /// Registers the saved shortcut, or removes the registration when there is none.
    func registerGlobalShortcut() {
        GlobalHotKey.shared.onPress = { [weak self] in self?.globalShortcutPressed() }
        if let shortcut = prefs.globalShortcut {
            globalShortcutFailed = !GlobalHotKey.shared.register(shortcut)
        } else {
            GlobalHotKey.shared.unregister()
            globalShortcutFailed = false
        }
    }

    /// The global shortcut: the same switch as Command-B, plus a HUD that says which way it went.
    func globalShortcutPressed() {
        let wasOn = engine.isOn
        toggle()
        BypassHUD.shared.show(state: wasOn ? .stopped : .running)
    }

    func turnOn() {
        writeLists()
        engine.start(command)
        if prefs.useSystemProxy, !proxy.isApplied {
            Task { await applyProxy() }
        }
    }

    func turnOff() {
        engine.stop()
        if proxy.isApplied || pacServer.isRunning { Task { await releaseProxy() } }
    }

    func restartIfRunning() {
        guard engine.isOn else { return }
        writeLists()
        engine.start(command)
        proxyInputsChanged()
    }

    func systemProxyChanged() {
        guard engine.isOn else { return }
        Task {
            if prefs.useSystemProxy { await applyProxy() } else { await releaseProxy() }
        }
    }

    func portChanged() {
        guard engine.isOn else { return }
        restartIfRunning()
        if proxy.isApplied {
            Task {
                await proxy.restore()
                await applyProxy()
            }
        }
    }

    // MARK: - System proxy mode (S-072)

    /// My list sends only the listed sites through the system proxy, with a
    /// PAC file; All sites sends everything to the SOCKS proxy.
    var proxyMode: ProxyMode { prefs.scope == .listOnly ? .pac : .socks }

    /// The PAC script for the enabled lists and the current port.
    func pacScript() -> String {
        PACFile.script(include: mergedDomains(excluded: false),
                       exclude: mergedDomains(excluded: true),
                       port: prefs.port)
    }

    /// Starts the PAC server (or gives it the current lists) and returns
    /// the PAC file's address.
    func servePAC() async -> URL? {
        await pacServer.start(preferredPort: prefs.port + 1, script: pacScript())
    }

    /// Applies the system proxy in the mode the Sites choice asks for.
    private func applyProxy() async {
        switch proxyMode {
        case .socks:
            await proxy.apply(port: prefs.port)
            if proxy.mode == .socks { pacServer.stop() }
        case .pac:
            // No port for the PAC file: every site goes to SOCKS rather than none.
            guard let url = await servePAC() else { await proxy.apply(port: prefs.port); return }
            await proxy.apply(port: prefs.port, pacURL: url)
        }
    }

    /// Puts the old proxy settings back, then stops serving the PAC file.
    private func releaseProxy() async {
        await proxy.restore()
        if !proxy.isApplied { pacServer.stop() }
    }

    /// The lists, the port, or the Sites choice changed while on: serve the
    /// new PAC file, and switch between SOCKS and PAC mode when needed.
    private func proxyInputsChanged() {
        if pacServer.isRunning { pacServer.update(pacScript()) }
        guard proxy.isApplied, proxy.mode != proxyMode else { return }
        Task { await applyProxy() }
    }

    /// At launch: put back a proxy left pointing at a dead tpws by a crash.
    func recoverFromCrash() {
        if proxy.isApplied, !engine.isOn { proxy.restoreNow() }
    }

    func runCheck() {
        guard let url = SiteCheck.url(from: prefs.testURL) else { return }
        isChecking = true
        check = nil
        let port = engine.state == .running ? prefs.port : nil
        Task {
            let result = await SiteCheck.run(url, port: port)
            check = result
            isChecking = false
        }
    }

    // MARK: - Find a strategy

    func openFinder() {
        if SiteCheck.urls(from: prefs.finderSites).isEmpty {
            prefs.finderSites = SiteCheck.url(from: prefs.testURL) == nil ? "https://discord.com" : prefs.testURL
        }
        showFinder = true
    }

    /// Quick: every built-in strategy, then the user's own. Thorough:
    /// blockcheck's tpws matrix for the address, with a shorter wait per try.
    func startFinder(url: URL, depth: ScanDepth? = nil) {
        startFinder(urls: [url], depth: depth)
    }

    /// Every strategy is tried on every site. A thorough scan picks the HTTP
    /// or HTTPS set by the first address.
    func startFinder(urls: [URL], depth: ScanDepth? = nil) {
        guard let first = urls.first else { return }
        rememberScan(before: first)
        let depth = depth ?? finderDepth
        finderDepth = depth
        switch depth {
        case .quick:
            var list = Preset.all.map { (id: "preset:\($0.id)", name: $0.name, arguments: $0.options.arguments) }
            list += customStrategies().map { (id: $0.selectionID, name: $0.name, arguments: $0.options.arguments) }
            finder.start(urls: urls, strategies: list, depth: .quick)
        case .thorough:
            let list = ScanPlan.tries(for: first).map { (id: $0.id, name: $0.name, arguments: $0.arguments) }
            finder.start(urls: urls, strategies: list, depth: .thorough, timeout: 6)
        }
    }

    // MARK: - Save what a scan found (S-091, S-093)

    /// The strategy editor shown on top of Find a Strategy.
    var finderDraft: StrategyDraft?
    /// The address the finder last ran on.
    private(set) var finderURL: URL?
    /// The fastest working row of earlier thorough scans of `keptHost`,
    /// for HTTP (true) and HTTPS (false), kept when the next scan starts.
    private var keptScanBest: [Bool: Trial] = [:]
    private var keptHost = ""

    private static func isHTTP(_ url: URL) -> Bool { url.scheme?.lowercased() == "http" }

    private static func fastest(_ trials: [Trial]) -> Trial? {
        trials.compactMap { t -> (Trial, Int)? in
            if case .works(let ms) = t.status { (t, ms) } else { nil }
        }
        .min { $0.1 < $1.1 }?.0
    }

    /// Keeps the best row of the scan that is about to be replaced, so an
    /// HTTP scan after an HTTPS one (or the other way) can join both.
    private func rememberScan(before next: URL) {
        if let last = finderURL, finder.depth == .thorough, let best = Self.fastest(finder.trials.filter(\.isScan)) {
            keptScanBest[Self.isHTTP(last)] = best
        }
        let host = next.host?.lowercased() ?? ""
        if host != keptHost { keptScanBest = [:]; keptHost = host }
        keptScanBest[Self.isHTTP(next)] = nil
        finderURL = next
    }

    /// The fastest working scan row for HTTP or HTTPS: from the scan on
    /// screen, or from the scan before it on the same site.
    func bestScanRow(http: Bool) -> Trial? {
        if finder.depth == .thorough, let url = finderURL, Self.isHTTP(url) == http,
           let live = Self.fastest(finder.trials.filter(\.isScan)) {
            return live
        }
        return keptScanBest[http]
    }

    /// Opens the strategy editor on top of the finder with a scan row's flags.
    func saveScanRow(_ trial: Trial) {
        let name = trial.name.isEmpty ? String(localized: "\(finder.site) strategy") : trial.name
        finderDraft = StrategyDraft(editing: nil, name: name, options: StrategyOptions(arguments: trial.arguments))
    }

    /// After a thorough scan of an https:// address with no HTTP result yet.
    var canAlsoScanHTTP: Bool {
        guard let url = finderURL, !finder.isRunning, finder.depth == .thorough, !finder.trials.isEmpty else { return false }
        return !Self.isHTTP(url) && keptScanBest[true] == nil
    }

    /// Runs blockcheck's HTTP set on http:// and the same host.
    func alsoScanHTTP() {
        guard let url = finderURL, var parts = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return }
        parts.scheme = "http"
        parts.port = nil
        guard let http = parts.url else { return }
        startFinder(url: http, depth: .thorough)
    }

    /// The best HTTP and HTTPS rows joined into one two-profile strategy.
    var joinedScanStrategy: StrategyOptions? {
        guard finder.depth == .thorough, let http = bestScanRow(http: true), let https = bestScanRow(http: false) else { return nil }
        let profiles = StrategyProfiles(http: StrategyOptions(arguments: http.arguments),
                                        https: StrategyOptions(arguments: https.arguments))
        return StrategyOptions(arguments: profiles.arguments)
    }

    func saveJoinedScan() {
        guard let options = joinedScanStrategy else { return }
        finderDraft = StrategyDraft(editing: nil, name: String(localized: "\(finder.site) strategy"), options: options)
    }

    // MARK: - Login item

    var launchAtLogin: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            do {
                if newValue { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            } catch {
                NSSound.beep()
            }
        }
    }
}
