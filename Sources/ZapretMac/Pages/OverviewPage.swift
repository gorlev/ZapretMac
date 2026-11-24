import SwiftData
import SwiftUI
import ZapretMacKit

/// The home page: one big switch, what it is doing, and a site check.
struct OverviewPage: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ScrollView {
            VStack(spacing: Space.xxl) {
                Hero()
                StatsRow()
                SetupCard()
                CheckCard()
                if !model.engine.recentHosts.isEmpty { RecentSitesCard() }
            }
            .frame(maxWidth: 640)
            .gridArea("overview", inset: 0)
            .padding(.horizontal, Space.margin)
            .padding(.vertical, Space.section)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle("Overview")
        .toolbar {
            ToolbarItem {
                Button(model.engine.isOn ? "Turn Off" : "Turn On",
                       systemImage: model.engine.isOn ? "stop.fill" : "play.fill") { model.toggle() }
                    .help(model.engine.isOn ? "Turn the bypass off (Command-B)" : "Turn the bypass on (Command-B)")
            }
        }
    }
}

// MARK: - Hero

private struct Hero: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: Space.lg) {
            PowerButton(state: model.engine.state) { model.toggle() }
            VStack(spacing: Space.xs) {
                Text(headline)
                    .font(.title.weight(.semibold))
                Text(subline)
                    .font(.callout)
                    .foregroundStyle(failed ? AnyShapeStyle(.red) : AnyShapeStyle(.secondary))
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                    .textSelection(.enabled)
            }
            if let error = model.proxy.lastError {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.callout)
                    .foregroundStyle(.orange)
            }
        }
        .frame(maxWidth: .infinity)
        .gridProbe("hero", area: "overview", edge: nil)
    }

    private var failed: Bool { if case .failed = model.engine.state { true } else { false } }

    private var headline: String {
        switch model.engine.state {
        case .stopped: "Bypass is off"
        case .starting: "Starting…"
        case .running: "Bypass is on"
        case .failed: "tpws stopped"
        }
    }

    private var subline: String {
        switch model.engine.state {
        case .stopped:
            "Click the switch to open blocked sites with \(model.activeStrategy.name)."
        case .starting:
            "Starting tpws on port \(String(model.prefs.port))."
        case .running:
            model.prefs.useSystemProxy && model.proxy.isApplied
                ? "Every app that uses the system proxy now goes through \(model.activeStrategy.name)."
                : "SOCKS5 proxy ready at 127.0.0.1:\(String(model.prefs.port)). Point your browser at it."
        case .failed(let message):
            message
        }
    }
}

/// The large round on/off switch.
struct PowerButton: View {
    let state: Engine.State
    let action: () -> Void
    @State private var hovering = false

    private let size: CGFloat = 148

    var body: some View {
        Button(action: action) {
            ZStack {
                // Soft halo while on.
                Circle()
                    .fill(Palette.accent.opacity(isOn ? 0.18 : 0))
                    .frame(width: size + 48, height: size + 48)
                    .blur(radius: 12)
                Circle()
                    .strokeBorder(isOn ? AnyShapeStyle(Palette.accent.opacity(0.35)) : AnyShapeStyle(.quaternary),
                                  lineWidth: 8)
                    .frame(width: size + 24, height: size + 24)
                Circle()
                    .fill(fill)
                    .frame(width: size, height: size)
                    .shadow(color: isOn ? Palette.accent.opacity(0.45) : .black.opacity(0.12),
                            radius: isOn ? 20 : 8, y: isOn ? 8 : 4)
                    .overlay(Circle().strokeBorder(.white.opacity(isOn ? 0.25 : 0.08), lineWidth: 1))
                if state == .starting {
                    ProgressView()
                        .controlSize(.large)
                        .tint(Palette.onAccent)
                } else {
                    Image(systemName: "power")
                        .font(.system(size: 52, weight: .semibold))
                        .foregroundStyle(isOn ? AnyShapeStyle(Palette.onAccent) : AnyShapeStyle(.secondary))
                        .contentTransition(.symbolEffect(.replace))
                }
            }
            .scaleEffect(hovering ? 1.03 : 1)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.spring(duration: 0.35), value: state)
        .animation(.easeOut(duration: 0.15), value: hovering)
        .help(isOn ? "Turn the bypass off (Command-B)" : "Turn the bypass on (Command-B)")
        .accessibilityLabel(isOn ? "Turn bypass off" : "Turn bypass on")
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }

    private var isOn: Bool { state == .running || state == .starting }

    private var fill: AnyShapeStyle {
        if isOn {
            AnyShapeStyle(LinearGradient(colors: [Palette.accent.opacity(0.85), Palette.accent],
                                         startPoint: .top, endPoint: .bottom))
        } else {
            AnyShapeStyle(.background.secondary)
        }
    }
}

// MARK: - Stats

private struct StatsRow: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: Space.md) {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                StatTile(title: "Running for", symbol: "clock",
                         value: model.engine.startedAt.map { Uptime.format(context.date.timeIntervalSince($0)) } ?? "—")
            }
            StatTile(title: "Connections", symbol: "arrow.left.arrow.right",
                     value: model.engine.isOn ? model.engine.connections.formatted() : "—")
            StatTile(title: "Sites seen", symbol: "globe",
                     value: model.engine.isOn ? model.engine.hostsSeen.count.formatted() : "—")
        }
        .gridProbe("stats", area: "overview")
    }
}

private struct StatTile: View {
    let title: String
    let symbol: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            Label(title, systemImage: symbol)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title2.weight(.semibold))
                .monospacedDigit()
                .contentTransition(.numericText())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Space.lg)
        .card()
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Setup

private struct SetupCard: View {
    @Environment(AppModel.self) private var model
    @Query private var domains: [DomainEntry]

    private var includeCount: Int { domains.filter { !$0.isExcluded && $0.isEnabled }.count }

    var body: some View {
        @Bindable var prefs = model.prefs
        VStack(alignment: .leading, spacing: 0) {
            CardRow(title: "Strategy", symbol: "slider.horizontal.3",
                    caption: "How tpws changes your traffic so the filter cannot read it.") {
                StrategyMenu()
            }
            Divider().padding(.leading, 48)
            CardRow(title: "Sites", symbol: "globe",
                    caption: prefs.scope == .listOnly && includeCount == 0
                        ? "Your list is empty. Add sites on the Sites page, or choose All sites."
                        : (prefs.scope == .allSites ? "Every site goes through the bypass."
                                                    : "Only the \(includeCount) sites in your list.")) {
                Picker("Sites", selection: Binding(get: { prefs.scope },
                                                  set: { prefs.scope = $0; model.restartIfRunning() })) {
                    Text("All sites").tag(Scope.allSites)
                    Text("My list").tag(Scope.listOnly)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
            }
            Divider().padding(.leading, 48)
            CardRow(title: "System proxy", symbol: "point.3.connected.trianglepath.dotted",
                    caption: "Sends Safari, Chrome, and other apps through ZapretMac. Turned back when it stops.") {
                Toggle("System proxy", isOn: Binding(get: { prefs.useSystemProxy },
                                                    set: { prefs.useSystemProxy = $0; model.systemProxyChanged() }))
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .disabled(model.proxy.isBusy)
            }
        }
        .card()
        .gridProbe("setup", area: "overview")
    }
}

/// A menu of every strategy, built-in and custom.
struct StrategyMenu: View {
    @Environment(AppModel.self) private var model
    @Query(sort: \CustomStrategy.createdAt) private var custom: [CustomStrategy]

    var body: some View {
        Menu {
            Section("Built-in") {
                ForEach(Preset.all) { preset in
                    Toggle(isOn: Binding(get: { model.prefs.strategyID == "preset:\(preset.id)" },
                                         set: { _ in model.choose(strategy: "preset:\(preset.id)") })) {
                        Label(preset.name, systemImage: preset.symbol)
                    }
                }
            }
            if !custom.isEmpty {
                Section("Yours") {
                    ForEach(custom) { strategy in
                        Toggle(strategy.name, isOn: Binding(get: { model.prefs.strategyID == strategy.selectionID },
                                                            set: { _ in model.choose(strategy: strategy.selectionID) }))
                    }
                }
            }
            Divider()
            Button("New Strategy…") { model.newStrategy() }
        } label: {
            Text(activeName)
        }
        .fixedSize()
    }

    private var activeName: String {
        custom.first { $0.selectionID == model.prefs.strategyID }?.name ?? model.activeStrategy.name
    }
}

private struct CardRow<Control: View>: View {
    let title: String
    let symbol: String
    let caption: String
    @ViewBuilder var control: Control

    var body: some View {
        HStack(spacing: Space.md) {
            Image(systemName: symbol)
                .font(.body.weight(.medium))
                .foregroundStyle(Palette.accentText)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.body.weight(.medium))
                Text(caption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: Space.lg)
            control
        }
        .padding(.horizontal, Space.lg)
        .padding(.vertical, Space.md)
    }
}

// MARK: - Site check

private struct CheckCard: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var prefs = model.prefs
        VStack(alignment: .leading, spacing: Space.md) {
            HStack {
                Label("Check a site", systemImage: "checkmark.seal")
                    .font(.headline)
                Spacer()
            }
            HStack(spacing: Space.sm) {
                TextField("Address", text: $prefs.testURL, prompt: Text("discord.com"))
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { model.runCheck() }
                Button {
                    model.runCheck()
                } label: {
                    if model.isChecking {
                        ProgressView().controlSize(.small).frame(width: 48)
                    } else {
                        Text("Check").frame(width: 48)
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(model.isChecking || SiteCheck.url(from: prefs.testURL) == nil)
                .help("Open the site with and without ZapretMac (Command-T)")
            }
            if let result = model.check {
                VStack(spacing: Space.sm) {
                    CheckRow(title: "Without ZapretMac", outcome: result.direct)
                    if let via = result.throughZapret {
                        CheckRow(title: "With ZapretMac", outcome: via)
                    } else {
                        HStack {
                            Text("With ZapretMac").foregroundStyle(.secondary)
                            Spacer()
                            Text("Turn the bypass on to compare").font(.callout).foregroundStyle(.tertiary)
                        }
                    }
                }
                .padding(.top, Space.xs)
                Text(verdict(result))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                Text("Opens the address once directly and once through tpws, so you can see whether the strategy helps.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(Space.lg)
        .card()
        .gridProbe("check", area: "overview")
    }

    private func verdict(_ r: SiteCheck.Result) -> String {
        guard let via = r.throughZapret else {
            return r.direct.isOK ? "The site opens without help." : "The site does not open directly."
        }
        switch (r.direct.isOK, via.isOK) {
        case (false, true): return "ZapretMac opens this site. The strategy works."
        case (true, true): return "The site opens either way."
        case (false, false): return "Still blocked. Try another strategy."
        case (true, false): return "The strategy breaks this site. Add it to Never touch, or pick another strategy."
        }
    }
}

private struct CheckRow: View {
    let title: String
    let outcome: SiteCheck.Outcome

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            switch outcome {
            case .ok(let status, let ms):
                Label("\(status) · \(ms) ms", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .monospacedDigit()
            case .failed(let reason):
                Label(reason, systemImage: "xmark.circle.fill")
                    .foregroundStyle(.red)
            }
        }
        .font(.callout)
    }
}

// MARK: - Recent sites

private struct RecentSitesCard: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: Space.md) {
            Label("Recent sites", systemImage: "clock.arrow.circlepath")
                .font(.headline)
            FlowLayout(spacing: Space.sm) {
                ForEach(model.engine.recentHosts, id: \.self) { host in
                    Text(host)
                        .font(.callout)
                        .padding(.horizontal, Space.sm)
                        .padding(.vertical, Space.xs)
                        .background(.quaternary.opacity(0.6), in: Capsule())
                        .contextMenu {
                            Button("Add to Sites to Unblock") { model.addDomains(from: host, excluded: false) }
                            Button("Add to Never Touch") { model.addDomains(from: host, excluded: true) }
                        }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Space.lg)
        .card()
        .gridProbe("recent", area: "overview")
    }
}

// MARK: - Shared

extension View {
    /// A rounded content card on the window background.
    func card() -> some View {
        background(.background.secondary, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(.separator.opacity(0.5), lineWidth: 1))
    }
}

/// Lays children out left to right and wraps to new lines.
struct FlowLayout: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, row: CGFloat = 0, widest: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width { x = 0; y += row + spacing; row = 0 }
            x += size.width + spacing
            widest = max(widest, x - spacing)
            row = max(row, size.height)
        }
        return CGSize(width: min(widest, width), height: y + row)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, row: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX { x = bounds.minX; y += row + spacing; row = 0 }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            row = max(row, size.height)
        }
    }
}
