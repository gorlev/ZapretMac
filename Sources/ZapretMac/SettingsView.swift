import SwiftUI
import ZapretMacKit

/// The Settings window (Command-Comma). One tab per topic, at most about
/// six. Each tab is a grouped Form that sizes to its content, so the
/// window grows to fit and shows no scroll bar it does not need.
struct SettingsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        TabView(selection: $model.settingsTab) {
            ForEach(SettingsTab.allCases) { tab in
                page(tab)
                    .tabItem { Label(tab.title, systemImage: tab.symbol) }
                    .tag(tab)
            }
        }
        .noInitialFocus()
    }

    @ViewBuilder
    private func page(_ tab: SettingsTab) -> some View {
        Form {
            switch tab {
            case .general: GeneralSettings()
            case .appearance: AppearanceSettings()
            case .about: AboutSettings()
            }
        }
        .formStyle(.grouped)
        .fitsContent()
        .frame(width: 520)
    }
}

/// The Settings tabs. Snapshot mode walks through every case.
enum SettingsTab: String, CaseIterable, Identifiable {
    case general, appearance, about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: "General"
        case .appearance: "Appearance"
        case .about: "About"
        }
    }

    var symbol: String {
        switch self {
        case .general: "gearshape"
        case .appearance: "paintpalette"
        case .about: "info.circle"
        }
    }
}

struct GeneralSettings: View {
    @Environment(AppModel.self) private var model
    @State private var portText = ""

    var body: some View {
        @Bindable var prefs = model.prefs
        Section("Startup") {
            Toggle("Open at login", isOn: Binding(get: { model.launchAtLogin },
                                                  set: { model.launchAtLogin = $0 }))
            Toggle("Turn the bypass on when ZapretMac opens", isOn: $prefs.startOnLaunch)
        }
        Section {
            LabeledContent("SOCKS port") {
                TextField("SOCKS port", text: $portText, prompt: Text(String(Prefs.defaultPort)))
                    .labelsHidden()
                    .multilineTextAlignment(.trailing)
                    .frame(width: 80)
                    .onSubmit(applyPort)
            }
            Toggle("Use as system proxy", isOn: Binding(get: { prefs.useSystemProxy },
                                                        set: { prefs.useSystemProxy = $0; model.systemProxyChanged() }))
        } header: {
            Text("Proxy")
        } footer: {
            Text(portFooter)
                .foregroundStyle(TPWSCommand.isValidPort(Int(portText) ?? 0) || portText.isEmpty ? AnyShapeStyle(.secondary) : AnyShapeStyle(.red))
        }
        Section("Log") {
            Toggle("Show every connection in the log", isOn: Binding(get: { prefs.verboseLog },
                                                                      set: { prefs.verboseLog = $0; model.restartIfRunning() }))
        }
        .onAppear { portText = String(prefs.port) }
    }

    private var portFooter: String {
        if let port = Int(portText), !TPWSCommand.isValidPort(port) { return "Use a port from 1024 to 65535." }
        return "tpws listens on 127.0.0.1 only. Press Return to apply. Browsers without the system proxy can use SOCKS5 127.0.0.1:\(model.prefs.port)."
    }

    private func applyPort() {
        guard let port = Int(portText), TPWSCommand.isValidPort(port), port != model.prefs.port else { return }
        model.prefs.port = port
        model.portChanged()
    }
}

struct AboutSettings: View {
    @State private var version = "…"

    var body: some View {
        Section {
            LabeledContent("ZapretMac", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev")
            LabeledContent("tpws", value: version)
            LabeledContent("zapret source", value: String(ZapretSource.commit.prefix(10)))
        } footer: {
            Text("ZapretMac is free and open source. The bypass engine is tpws from zapret by bol-van, MIT license.")
                .foregroundStyle(.secondary)
        }
        Section {
            Link("zapret on GitHub", destination: URL(string: "https://github.com/bol-van/zapret")!)
            Link("tpws options", destination: URL(string: "https://github.com/bol-van/zapret/blob/master/docs/readme.en.md#tpws")!)
        }
        .task { version = await Engine.version() }
    }
}

enum ZapretSource {
    /// Written by build.sh from Vendor/zapret/COMMIT.
    static var commit: String {
        Bundle.main.object(forInfoDictionaryKey: "ZapretCommit") as? String ?? "unknown"
    }
}
