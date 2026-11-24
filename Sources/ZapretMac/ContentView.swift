import SwiftData
import SwiftUI

struct ContentView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openSettings) private var openSettings
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
        .sheet(item: $model.draft) { draft in
            StrategyEditor(draft: draft)
                .environment(model)
                .themed()
        }
        .noInitialFocus()
        .task {
            SeedData.insertIfRequested(into: model)
            SelfTest.runIfRequested(model: model)
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

    var body: some View {
        HStack(spacing: Space.sm) {
            StatusDot(state: model.engine.state)
            VStack(alignment: .leading, spacing: 0) {
                Text(model.engine.state.title)
                    .font(.callout.weight(.medium))
                Text(model.engine.isOn ? "127.0.0.1:\(String(model.prefs.port))" : "Not running")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            Spacer(minLength: 0)
        }
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

extension Engine.State {
    var title: String {
        switch self {
        case .stopped: "Off"
        case .starting: "Starting…"
        case .running: "Bypass On"
        case .failed: "Stopped with an Error"
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
