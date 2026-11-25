import AppKit
import SwiftUI

/// The small panel the global shortcut shows for a second at the bottom
/// middle of the main screen: the shield and "Bypass On" or "Off".
/// It floats over every app and Space, never takes focus, and ignores the mouse.
final class BypassHUD {
    static let shared = BypassHUD()

    /// How long the panel stays, and how long it fades in and out.
    static let visible: Duration = .seconds(1)
    static let fade: TimeInterval = 0.2
    /// The panel's distance from the bottom of the screen's visible area.
    static let bottomInset: CGFloat = 120
    static let cornerRadius: CGFloat = 24

    private var panel: NSPanel?
    private var hideTask: Task<Void, Never>?
    private var shownCount = 0

    private init() {}

    /// The panel on screen now, for snapshots.
    var window: NSWindow? { panel }

    func show(state: Engine.State) {
        shownCount += 1
        let panel = panel ?? makePanel()
        self.panel = panel
        let host = NSHostingView(rootView: BypassHUDView(state: state).themed())
        panel.contentView = host
        panel.setContentSize(host.fittingSize)
        if let screen = NSScreen.main {
            let area = screen.visibleFrame
            panel.setFrameOrigin(NSPoint(x: area.midX - panel.frame.width / 2, y: area.minY + Self.bottomInset))
        }
        let animate = !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        if !panel.isVisible { panel.alphaValue = animate ? 0 : 1 }
        panel.orderFrontRegardless()
        if animate {
            NSAnimationContext.runAnimationGroup { $0.duration = Self.fade; panel.animator().alphaValue = 1 }
        } else {
            panel.alphaValue = 1
        }
        hideTask?.cancel()
        hideTask = Task { [weak self] in
            try? await Task.sleep(for: Self.visible)
            guard !Task.isCancelled else { return }
            self?.hide(animated: animate)
        }
    }

    func hide(animated: Bool = false) {
        hideTask?.cancel()
        guard let panel else { return }
        guard animated else { panel.orderOut(nil); return }
        shownCount += 1
        let shown = shownCount
        NSAnimationContext.runAnimationGroup({ $0.duration = Self.fade; panel.animator().alphaValue = 0 },
                                             completionHandler: {
            // A press during the fade shows the panel again: leave it then.
            MainActor.assumeIsolated { if self.shownCount == shown { panel.orderOut(nil) } }
        })
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false // the glass draws its own
        panel.isReleasedWhenClosed = false
        return panel
    }
}

private struct BypassHUDView: View {
    let state: Engine.State

    var body: some View {
        VStack(spacing: Space.sm) {
            Image(systemName: state.symbol)
                .font(.system(size: 44, weight: .regular)) // grid: ok symbol point size, not spacing
                .foregroundStyle(state == .running ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                .symbolRenderingMode(.hierarchical)
            Text(state.title)
                .font(.headline)
                .foregroundStyle(.primary)
        }
        .frame(width: 160, height: 120)
        .glassEffect(.regular, in: .rect(cornerRadius: BypassHUD.cornerRadius, style: .continuous))
        .padding(Space.sm)
        .accessibilityElement(children: .combine)
    }
}
