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
        case .overview: "Overview"
        case .strategies: "Strategies"
        case .domains: "Sites"
        case .log: "Log"
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
    var sidebar: SidebarItem? = .overview
    var draft: StrategyDraft?
    var check: SiteCheck.Result?
    var isChecking = false
    /// Settings reopens on the last tab. Test and snapshot runs leave it alone.
    var settingsTab: SettingsTab = SettingsTab(rawValue: UserDefaults.standard.string(forKey: "settings.tab") ?? "") ?? .general {
        didSet { if !Store.isOverridden { UserDefaults.standard.set(settingsTab.rawValue, forKey: "settings.tab") } }
    }

    init(container: ModelContainer) {
        self.container = container
        proxy = SystemProxy(defaults: Prefs.shared.defaults)
    }

    private var context: ModelContext { container.mainContext }

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
        if added > 0 { listsChanged() }
        return added
    }

    func remove(_ entries: [DomainEntry]) {
        for entry in entries { context.delete(entry) }
        try? context.save()
        listsChanged()
    }

    /// The lists feed tpws only through files: rewrite them and restart.
    func listsChanged() {
        try? context.save()
        writeLists()
        restartIfRunning()
    }

    private func writeLists() {
        let include = domains(excluded: false).filter(\.isEnabled).map(\.domain)
        let exclude = domains(excluded: true).filter(\.isEnabled).map(\.domain)
        try? Domains.fileContents(include).write(to: Store.hostlistURL, atomically: true, encoding: .utf8)
        try? Domains.fileContents(exclude).write(to: Store.excludeURL, atomically: true, encoding: .utf8)
    }

    var includeCount: Int { domains(excluded: false).filter(\.isEnabled).count }

    // MARK: - On and off

    var command: TPWSCommand {
        let exclude = domains(excluded: true).contains(where: \.isEnabled)
        return TPWSCommand(port: prefs.port, strategy: activeStrategy.arguments, scope: prefs.scope,
                           hostlistPath: Store.hostlistURL.path,
                           excludePath: exclude ? Store.excludeURL.path : nil,
                           debug: prefs.verboseLog)
    }

    /// A list scope with an empty list would change nothing.
    var scopeProblem: String? {
        prefs.scope == .listOnly && includeCount == 0 ? "Your site list is empty. Add sites or choose All sites." : nil
    }

    func toggle() {
        if engine.isOn { turnOff() } else { turnOn() }
    }

    func turnOn() {
        writeLists()
        engine.start(command)
        if prefs.useSystemProxy, !proxy.isApplied {
            Task { await proxy.apply(port: prefs.port) }
        }
    }

    func turnOff() {
        engine.stop()
        if proxy.isApplied { Task { await proxy.restore() } }
    }

    func restartIfRunning() {
        guard engine.isOn else { return }
        writeLists()
        engine.start(command)
    }

    func systemProxyChanged() {
        guard engine.isOn else { return }
        Task {
            if prefs.useSystemProxy { await proxy.apply(port: prefs.port) } else { await proxy.restore() }
        }
    }

    func portChanged() {
        guard engine.isOn else { return }
        restartIfRunning()
        if proxy.isApplied {
            Task {
                await proxy.restore()
                await proxy.apply(port: prefs.port)
            }
        }
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
