import Carbon.HIToolbox
import Foundation
import ZapretMacKit

/// The system-wide shortcut, registered with Carbon's RegisterEventHotKey.
/// It needs no Accessibility permission, and the key never reaches the app
/// in front. One shortcut at a time: registering a new one replaces the old.
final class GlobalHotKey {
    static let shared = GlobalHotKey()

    /// Called on the main thread when the shortcut is pressed in any app.
    var onPress: (() -> Void)?
    private(set) var registered: GlobalShortcut?
    private var ref: EventHotKeyRef?
    private var handler: EventHandlerRef?

    private static let signature = OSType(0x5A4D4250) // 'ZMBP'
    static let bypassID: UInt32 = 1

    private init() {}

    /// Registers the shortcut, replacing the one before. Returns false when
    /// macOS refuses it, usually because another app already uses it.
    @discardableResult
    func register(_ shortcut: GlobalShortcut) -> Bool {
        unregister()
        guard shortcut.isValid else { return false }
        installHandler()
        var newRef: EventHotKeyRef?
        let id = EventHotKeyID(signature: Self.signature, id: Self.bypassID)
        let status = RegisterEventHotKey(UInt32(shortcut.keyCode), shortcut.carbonModifiers, id,
                                         GetApplicationEventTarget(), 0, &newRef)
        guard status == noErr, let newRef else { return false }
        ref = newRef
        registered = shortcut
        return true
    }

    func unregister() {
        if let ref { UnregisterEventHotKey(ref) }
        ref = nil
        registered = nil
    }

    /// What the Carbon callback calls. The self-test calls it too.
    func fire(_ id: UInt32) {
        guard id == Self.bypassID else { return }
        onPress?()
    }

    private func installHandler() {
        guard handler == nil else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), hotKeyCallback, 1, &spec, nil, &handler)
    }
}

/// Carbon delivers hot key events on the main thread.
private nonisolated func hotKeyCallback(_ next: EventHandlerCallRef?, _ event: EventRef?, _ data: UnsafeMutableRawPointer?) -> OSStatus {
    guard let event else { return OSStatus(eventNotHandledErr) }
    var hotKey = EventHotKeyID()
    let status = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                                   nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKey)
    guard status == noErr else { return status }
    let id = hotKey.id
    MainActor.assumeIsolated { GlobalHotKey.shared.fire(id) }
    return noErr
}
