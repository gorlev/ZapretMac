import SwiftData
import SwiftUI

struct ContentView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openSettings) private var openSettings
    @Environment(\.undoManager) private var undoManager
    @Query private var domains: [DomainEntry]

    var body: some View {
        @Bindable var model = model
        NavigationSplitView {
            sidebar
        } detail: {
            switch model.sidebar ?? .overview {
            case .overview: OverviewPage()
            case .strategies: StrategiesPage()
            case .domains: DomainsPage()
            case .log: LogPage()
            }
        }
        .sheet(isPresented: $model.showFinder) {
            FinderSheet()
                .environment(model)
                .themed()
        }
        .sheet(isPresented: $model.showAddSubscription) {
            AddSubscriptionSheet()
                .environment(model)
                .themed()
        }
        .sheet(item: $model.draft) { draft in
            StrategyEditor(draft: draft)
                .environment(model)
                .themed()
        }
        .noInitialFocus()
        .onAppear { model.attachUndo(undoManager) }
        .onChange(of: undoManager) { model.attachUndo(undoManager) }
        .task {
            SeedData.insertIfRequested(into: model)
            Snapshot.runIfRequested(model: model, openSettings: openSettings)
        }
    }

    private var sidebar: some View {
        @Bindable var model = model
        return List(selection: $model.sidebar) {
            ForEach(SidebarItem.allCases) { page in
                Label(page.title, systemImage: page.symbol)
                    .badge(badge(for: page))
                    .tag(page)
            }
        }
        .safeAreaInset(edge: .bottom) { SidebarStatus() }
        .navigationSplitViewColumnWidth(min: 190, ideal: 212)
    }

    private func badge(for page: SidebarItem) -> Int {
        switch page {
        case .domains: domains.filter { !$0.isExcluded && $0.isEnabled }.count
        default: 0
        }
    }
}

/// A small status line at the foot of the sidebar: is the bypass on?
private struct SidebarStatus: View {
    @Environment(AppModel.self) private var model
    @Environment(\.appearsActive) private var appearsActive

    var body: some View {
        HStack(spacing: Space.sm) {
            StatusDot(state: model.engine.state)
            VStack(alignment: .leading, spacing: 0) {
                Text(model.engine.state.title)
                    .font(.callout.weight(.medium))
                Text(!model.engine.isOn ? String(localized: "Not running")
                     : model.prefs.transparentMode ? String(localized: "Transparent mode") : "127.0.0.1:\(String(model.prefs.port))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            Spacer(minLength: 0)
        }
        // Dims with the window, like the system sidebar.
        .opacity(appearsActive ? 1 : 0.6)
        .padding(.horizontal, Space.lg)
        .padding(.vertical, Space.md)
        .accessibilityElement(children: .combine)
    }
}

struct StatusDot: View {
    let state: Engine.State

    var body: some View {
        Circle()
            .fill(state.color)
            .frame(width: 8, height: 8)
            .shadow(color: state.color.opacity(state == .running ? 0.6 : 0), radius: 4)
    }
}

extension Engine {
    /// The menu bar shield: on, off, or a warning after a failure.
    var menuBarSymbol: String { state.symbol }
}

extension Engine.State {
    /// The shield for this state, in the menu bar and the global shortcut's HUD.
    var symbol: String {
        switch self {
        case .running, .starting: "shield.lefthalf.filled"
        case .stopped: "shield.slash"
        case .failed: "exclamationmark.shield"
        }
    }

    var title: String {
        switch self {
        case .stopped: String(localized: "Off")
        case .starting: String(localized: "Starting…")
        case .running: String(localized: "Bypass On")
        case .failed: String(localized: "Stopped with an Error")
        }
    }

    var color: Color {
        switch self {
        case .stopped: Color.secondary.opacity(0.5)
        case .starting: .orange
        case .running: .green
        case .failed: .red
        }
    }
}
