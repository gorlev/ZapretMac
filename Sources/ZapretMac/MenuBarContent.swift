import SwiftData
import SwiftUI
import ZapretMacKit

/// The menu bar item's panel: the round switch, what it is doing, the
/// strategy and sites, and the way to the window.
struct MenuBarContent: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings
    @Query(sort: \CustomStrategy.createdAt) private var custom: [CustomStrategy]

    var body: some View {
        VStack(spacing: 0) {
            header
            PowerButton(state: model.engine.state, size: 96) { model.toggle() }
                .keyboardShortcut("b", modifiers: .command)
                .padding(.vertical, Space.xs)
            status
                .padding(.top, Space.xs)
                .padding(.bottom, Space.md)
            settingsCard
                .padding(.horizontal, Space.md)
            footer
        }
        .frame(width: 320)
        .themed()
        .gridArea("menubar", inset: Space.md)
    }

    // MARK: - Parts

    private var header: some View {
        HStack {
            Text(verbatim: "ZapretMac").font(.headline)
            Spacer()
            HStack(spacing: Space.xs) {
                Circle().fill(dotColor).frame(width: 8, height: 8)
                Text(model.engine.isOn ? String(localized: "On") : String(localized: "Off"))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
        }
        .padding(.horizontal, Space.lg)
        .padding(.top, Space.md)
        .padding(.bottom, Space.xs)
    }

    private var status: some View {
        VStack(spacing: 2) {
            Text(headline).font(.title3.weight(.semibold))
            TimelineView(.periodic(from: .now, by: 1)) { context in
                Text(subline(at: context.date))
                    .font(.callout)
                    .foregroundStyle(failed ? AnyShapeStyle(.red) : AnyShapeStyle(.secondary))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .monospacedDigit()
            }
        }
        .padding(.horizontal, Space.lg)
    }

    private var settingsCard: some View {
        VStack(spacing: 0) {
            row("slider.horizontal.3", String(localized: "Strategy")) {
                Picker("Strategy", selection: Binding(get: { model.prefs.strategyID },
                                                      set: { model.choose(strategy: $0) })) {
                    ForEach(Preset.all) { Text($0.name).tag("preset:\($0.id)") }
                    if !custom.isEmpty {
                        Divider()
                        ForEach(custom) { Text($0.name).tag($0.selectionID) }
                    }
                }
                .labelsHidden()
                .tint(Palette.accentText)
                .frame(maxWidth: 176, alignment: .trailing)
            }
            Divider().padding(.leading, Space.section + Space.sm)
            row("globe", String(localized: "Sites"), dropsTitle: true) {
                Picker("Sites", selection: Binding(get: { model.prefs.scope },
                                                   set: { model.prefs.scope = $0; model.restartIfRunning() })) {
                    Text("All Sites").tag(Scope.allSites)
                    Text("My List").tag(Scope.listOnly)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
            }
            if !model.prefs.transparentMode {
                Divider().padding(.leading, Space.section + Space.sm)
                row("point.3.connected.trianglepath.dotted", String(localized: "System proxy")) {
                    Toggle("Use as System Proxy", isOn: Binding(get: { model.prefs.useSystemProxy },
                                                                set: { model.prefs.useSystemProxy = $0; model.systemProxyChanged() }))
                        .toggleStyle(.switch)
                        .labelsHidden()
                        .controlSize(.small)
                }
            }
        }
        .background(.quinary, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var footer: some View {
        HStack(spacing: Space.sm) {
            Button {
                openWindow(id: "main")
                NSApp.activate()
            } label: {
                Label("Open ZapretMac", systemImage: "macwindow")
            }
            .buttonStyle(.bordered)
            Spacer()
            Button {
                openSettings()
                NSApp.activate()
            } label: {
                Label("Settings…", systemImage: "gearshape").labelStyle(.iconOnly)
            }
            .keyboardShortcut(",")
            .help("Settings…")
            Button {
                NSApp.terminate(nil)
            } label: {
                Label("Quit ZapretMac", systemImage: "rectangle.portrait.and.arrow.right").labelStyle(.iconOnly)
            }
            .keyboardShortcut("q")
            .help("Quit ZapretMac")
        }
        .buttonStyle(.borderless)
        // Accent text: the deep shade in light mode, the light one in dark, so both read.
        .tint(Palette.accentText)
        .padding(.horizontal, Space.lg)
        .padding(.vertical, Space.md)
    }

    /// One row of the card. `dropsTitle`: when the control is too wide (the
    /// Sites choice in German), the icon alone names the row.
    private func row<Control: View>(_ symbol: String, _ title: String, dropsTitle: Bool = false,
                                    @ViewBuilder control: () -> Control) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: Space.md) {
                rowIcon(symbol)
                Text(title).fixedSize()
                Spacer(minLength: Space.sm)
                control()
            }
            if dropsTitle {
                HStack(spacing: Space.md) {
                    rowIcon(symbol).help(title)
                    Spacer(minLength: 0)
                    control()
                }
            }
        }
        .padding(.horizontal, Space.md)
        .frame(minHeight: 40)
    }

    private func rowIcon(_ symbol: String) -> some View {
        Image(systemName: symbol)
            .foregroundStyle(Palette.accentText)
            .frame(width: Space.xl)
    }

    // MARK: - Words

    private var failed: Bool { if case .failed = model.engine.state { true } else { false } }

    private var dotColor: Color {
        switch model.engine.state {
        case .running: .green
        case .starting: .orange
        case .failed: .red
        case .stopped: .secondary
        }
    }

    private var headline: String {
        switch model.engine.state {
        case .stopped: String(localized: "Bypass is off")
        case .starting: String(localized: "Starting…")
        case .running: String(localized: "Bypass is on")
        case .failed: String(localized: "tpws stopped")
        }
    }

    private func subline(at date: Date) -> String {
        switch model.engine.state {
        case .stopped:
            return model.activeStrategy.name
        case .starting:
            return String(localized: "Starting tpws on port \(String(model.prefs.port)).")
        case .running:
            let uptime = model.engine.startedAt.map { Uptime.format(date.timeIntervalSince($0)) } ?? ""
            return model.prefs.transparentMode
                ? String(localized: "Transparent mode · \(uptime)")
                : String(localized: "SOCKS5 127.0.0.1:\(String(model.prefs.port)) · \(uptime)")
        case .failed(let message):
            return message
        }
    }
}
