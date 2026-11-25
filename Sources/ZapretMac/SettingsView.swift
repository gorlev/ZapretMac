import AppKit
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
            case .advanced: AdvancedSettings()
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
    case general, appearance, advanced, about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: String(localized: "General")
        case .appearance: String(localized: "Appearance")
        case .advanced: String(localized: "Advanced")
        case .about: String(localized: "About")
        }
    }

    var symbol: String {
        switch self {
        case .general: "gearshape"
        case .appearance: "paintpalette"
        case .advanced: "gearshape.2"
        case .about: "info.circle"
        }
    }
}

struct GeneralSettings: View {
    @Environment(AppModel.self) private var model
    @State private var portText = ""
    @State private var needsModifier = false

    var body: some View {
        @Bindable var prefs = model.prefs
        Section("Startup") {
            Toggle("Open at login", isOn: Binding(get: { model.launchAtLogin },
                                                  set: { model.launchAtLogin = $0 }))
            Toggle("Turn the bypass on when ZapretMac opens", isOn: $prefs.startOnLaunch)
        }
        Section {
            LabeledContent("Global shortcut") {
                ShortcutRecorder(needsModifier: $needsModifier)
            }
        } header: {
            Text("Shortcut")
        } footer: {
            if model.globalShortcutFailed {
                Text("Another app uses this shortcut. Choose another one.")
                    .foregroundStyle(.red)
            } else if needsModifier {
                Text("Use Command, Option, or Control with the key. Press Escape to cancel.")
                    .foregroundStyle(.secondary)
            } else {
                Text("Works in any app: press it to turn the bypass on or off.")
                    .foregroundStyle(.secondary)
            }
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
                .disabled(prefs.transparentMode)
        } header: {
            Text("Proxy")
        } footer: {
            Text(portFooter)
                .foregroundStyle(TPWSCommand.isValidPort(Int(portText) ?? 0) || portText.isEmpty ? AnyShapeStyle(.secondary) : AnyShapeStyle(.red))
        }
        ShareSettings()
        Section {
            LabeledContent("Language") {
                Text(Locale.current.localizedString(forLanguageCode: Bundle.main.preferredLocalizations.first ?? "en")?.localizedCapitalized ?? "English")
            }
            Button("Change in System Settings…") {
                if let url = URL(string: "x-apple.systempreferences:com.apple.Localization-Settings.extension") {
                    NSWorkspace.shared.open(url)
                }
            }
        } header: {
            Text("Language")
        } footer: {
            Text("ZapretMac follows your Mac's language. To use another language for ZapretMac only, add it under Applications in Language & Region.")
                .foregroundStyle(.secondary)
        }
        Section("Log") {
            Toggle("Show every connection in the log", isOn: Binding(get: { prefs.verboseLog },
                                                                      set: { prefs.verboseLog = $0; model.restartIfRunning() }))
        }
        .onAppear { portText = String(prefs.port) }
    }

    private var portFooter: String {
        if let port = Int(portText), !TPWSCommand.isValidPort(port) { return String(localized: "Use a port from 1024 to 65535.") }
        if model.sharedAddress != nil {
            return String(localized: "tpws listens on 127.0.0.1 and on your network address. Press Return to apply. Browsers without the system proxy can use SOCKS5 127.0.0.1:\(String(model.prefs.port)).")
        }
        return String(localized: "tpws listens on 127.0.0.1 only. Press Return to apply. Browsers without the system proxy can use SOCKS5 127.0.0.1:\(String(model.prefs.port)).")
    }

    private func applyPort() {
        guard let port = Int(portText), TPWSCommand.isValidPort(port), port != model.prefs.port else { return }
        model.prefs.port = port
        model.portChanged()
    }
}

/// S-104: share the SOCKS proxy with phones, tablets, and TVs on this network.
struct ShareSettings: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let prefs = model.prefs
        Section {
            Toggle("Share with devices on this network", isOn: Binding(get: { prefs.shareOnNetwork && !prefs.transparentMode },
                                                                       set: { model.setShareOnNetwork($0) }))
                .disabled(prefs.transparentMode)
            if prefs.shareOnNetwork, !prefs.transparentMode {
                if let address = model.sharedAddress, let text = model.sharedProxyText {
                    LabeledContent("SOCKS5 address") {
                        HStack(spacing: Space.sm) {
                            Text(text)
                                .monospacedDigit()
                                .textSelection(.enabled)
                            Button("Copy") {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(text, forType: .string)
                            }
                            .help(String(localized: "Copy the address"))
                        }
                    }
                    LabeledContent {
                        QRCode(text: NetworkShare.payload(ip: address.ip, port: prefs.port))
                    } label: {
                        Text("QR code")
                        Text("Scan it in a proxy app on your phone.")
                    }
                } else {
                    Label("No network address. Connect this Mac to Wi-Fi or Ethernet to share.", systemImage: "wifi.slash")
                        .foregroundStyle(.secondary)
                }
            }
        } header: {
            Text("Sharing")
        } footer: {
            VStack(alignment: .leading, spacing: Space.xs) {
                if prefs.transparentMode {
                    Text("Sharing works with the SOCKS proxy. Turn off Transparent mode in Advanced to share.")
                        .foregroundStyle(.secondary)
                } else if prefs.shareOnNetwork {
                    Text("While sharing is on, anyone on this network can use your Mac's bypass. The first time, macOS may ask whether tpws can accept incoming connections: click Allow, or other devices cannot connect.")
                        .foregroundStyle(.secondary)
                    Text("The Wi-Fi proxy setting on iPhone and Android takes HTTP proxies only, so use an app that supports SOCKS5 proxies and enter this address there.")
                        .foregroundStyle(.secondary)
                    if !model.engine.isOn {
                        Text("Turn the bypass on to start sharing.")
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Text("Lets your phone, tablet, or TV use this Mac as a SOCKS5 proxy. Off by default.")
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

/// Transparent mode's helper (S-080): what it does, its state, and the
/// buttons that install, approve, and remove it, and the mode switch (S-081).
struct AdvancedSettings: View {
    @Environment(AppModel.self) private var model
    @State private var helper = HelperClient.shared
    @State private var confirmRemove = false

    var body: some View {
        Section {
            Toggle("Use Transparent mode", isOn: Binding(get: { model.prefs.transparentMode },
                                                         set: { model.setTransparentMode($0) }))
                // Turning it off always works; turning it on needs the helper.
                .disabled(helper.state != .ready && !model.prefs.transparentMode)
            LabeledContent("Helper") {
                Label(helper.stateTitle, systemImage: symbol)
                    .foregroundStyle(helper.state == .ready ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
            }
            HStack {
                if !helper.isRegistered {
                    Button("Install Helper…") { helper.register() }
                }
                Button("Open Login Items…") { helper.openSystemSettingsLoginItems() }
                if helper.isRegistered {
                    Button("Remove Helper") { confirmRemove = true }
                }
            }
        } header: {
            HStack(spacing: Space.xs) {
                Text("Transparent mode")
                InfoButton.transparentMode
            }
        } footer: {
            VStack(alignment: .leading, spacing: Space.xs) {
                Text("Sends every app's web traffic through tpws with no proxy setting. It needs a helper that runs as administrator.")
                    .foregroundStyle(.secondary)
                if helper.state != .ready, !helper.isRegistered {
                    Text("Install the helper to use Transparent mode.")
                        .foregroundStyle(.secondary)
                }
                if helper.state == .needsApproval {
                    Text("Turn on ZapretMac in System Settings, under General, Login Items & Extensions.")
                        .foregroundStyle(.secondary)
                }
                if let message = helper.message {
                    Text(message).foregroundStyle(.red)
                }
            }
        }
        .confirmationDialog("Remove the helper?", isPresented: $confirmRemove) {
            Button("Remove Helper", role: .destructive) { Task { await helper.unregister() } }
        } message: {
            Text("Transparent mode stops working until you install it again.")
        }
        .task {
            // Approval happens in System Settings, which never calls back: look again every 2 seconds.
            while !Task.isCancelled {
                helper.refresh()
                model.checkHelper()
                if helper.state == .ready, helper.helperVersion == nil, !Store.isOverridden { await helper.checkVersion() }
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    private var symbol: String {
        switch helper.state {
        case .ready: "checkmark.circle.fill"
        case .needsApproval: "exclamationmark.circle"
        case .notInstalled: "circle.dashed"
        case .notFound: "questionmark.circle"
        }
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
