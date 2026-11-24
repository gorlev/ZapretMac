import SwiftData
import SwiftUI
import ZapretMacKit

/// The menu bar item's menu: the switch, the strategy, and the window.
struct MenuBarContent: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings
    @Query(sort: \CustomStrategy.createdAt) private var custom: [CustomStrategy]

    var body: some View {
        Text(model.engine.state.title)
        Button(model.engine.isOn ? "Turn Off" : "Turn On") { model.toggle() }
            .keyboardShortcut("b")
        Divider()
        Picker("Strategy", selection: Binding(get: { model.prefs.strategyID },
                                              set: { model.choose(strategy: $0) })) {
            ForEach(Preset.all) { Text($0.name).tag("preset:\($0.id)") }
            if !custom.isEmpty {
                Divider()
                ForEach(custom) { Text($0.name).tag($0.selectionID) }
            }
        }
        Picker("Sites", selection: Binding(get: { model.prefs.scope },
                                           set: { model.prefs.scope = $0; model.restartIfRunning() })) {
            Text("All Sites").tag(Scope.allSites)
            Text("My List").tag(Scope.listOnly)
        }
        Toggle("Use as System Proxy", isOn: Binding(get: { model.prefs.useSystemProxy },
                                                    set: { model.prefs.useSystemProxy = $0; model.systemProxyChanged() }))
        Divider()
        Button("Open ZapretMac") {
            openWindow(id: "main")
            NSApp.activate()
        }
        Button("Settings…") {
            openSettings()
            NSApp.activate()
        }
        .keyboardShortcut(",")
        Divider()
        Button("Quit ZapretMac") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}
