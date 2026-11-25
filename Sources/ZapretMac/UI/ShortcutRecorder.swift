import AppKit
import SwiftUI
import ZapretMacKit

/// Records the global shortcut: click, then press a combination with
/// Command, Option, or Control. Escape cancels; the x button removes it.
/// While recording, the old shortcut is off, so pressing it records it again
/// instead of turning the bypass on or off.
struct ShortcutRecorder: View {
    @Environment(AppModel.self) private var model
    /// Set when a key came without Command, Option, or Control; the footer explains.
    @Binding var needsModifier: Bool
    @State private var recording = false
    @State private var monitor: Any?

    var body: some View {
        HStack(spacing: Space.xs) {
            if recording {
                recordButton.buttonStyle(.borderedProminent)
            } else {
                recordButton.buttonStyle(.bordered)
            }
            if model.prefs.globalShortcut != nil, !recording {
                Button {
                    model.setGlobalShortcut(nil)
                } label: {
                    Label("Remove Shortcut", systemImage: "xmark.circle.fill")
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .help("Remove the shortcut")
            }
        }
        .onDisappear(perform: stop)
    }

    private var recordButton: some View {
        Button(action: { recording ? stop() : start() }) {
            Text(title)
                .monospacedDigit()
                .frame(minWidth: 96)
        }
        .help(recording ? String(localized: "Press a key combination, or Escape to cancel") : String(localized: "Click, then press a key combination"))
    }

    private var title: String {
        if recording { return String(localized: "Type Shortcut") }
        return model.prefs.globalShortcut?.displayString ?? String(localized: "Record Shortcut")
    }

    private func start() {
        needsModifier = false
        recording = true
        GlobalHotKey.shared.unregister()
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            record(event)
            return nil
        }
    }

    private func record(_ event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        var modifiers: GlobalShortcut.Modifiers = []
        if flags.contains(.command) { modifiers.insert(.command) }
        if flags.contains(.option) { modifiers.insert(.option) }
        if flags.contains(.control) { modifiers.insert(.control) }
        if flags.contains(.shift) { modifiers.insert(.shift) }
        if event.keyCode == GlobalShortcut.escapeKeyCode, modifiers.isEmpty {
            stop()
            return
        }
        let shortcut = GlobalShortcut(keyCode: event.keyCode, modifiers: modifiers)
        guard shortcut.isValid else {
            needsModifier = true
            NSSound.beep()
            return
        }
        needsModifier = false
        model.prefs.globalShortcut = shortcut
        stop()
    }

    /// Ends recording and registers whatever shortcut is saved now.
    private func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        guard recording else { return }
        recording = false
        model.registerGlobalShortcut()
    }
}
