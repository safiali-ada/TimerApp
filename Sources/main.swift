import AppKit
import SwiftUI

/// Borderless, non-activating panel that can still take keyboard input for the time fields.
final class FloatingPanel: NSPanel {
    init(size: NSSize) {
        super.init(contentRect: NSRect(origin: .zero, size: size),
                   styleMask: [.borderless, .nonactivatingPanel, .miniaturizable],
                   backing: .buffered, defer: false)
        isFloatingPanel = true
        hidesOnDeactivate = false
        isMovableByWindowBackground = true
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// Hosting view that reacts to the first click even when the panel isn't key.
final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let model = TimerModel()
    private var panel: FloatingPanel!

    func applicationDidFinishLaunching(_ notification: Notification) {
        let size = NSSize(width: 260, height: 190)
        let panel = FloatingPanel(size: size)
        self.panel = panel

        panel.contentView = FirstMouseHostingView(rootView: TimerView(
            model: model,
            onClose: { NSApp.terminate(nil) },
            onMinimize: { [weak panel] in panel?.miniaturize(nil) }
        ))

        // Restore the last position; on first launch start in the top-right corner.
        let hasSavedFrame = UserDefaults.standard.string(forKey: "NSWindow Frame TimerPanel") != nil
        panel.setFrameAutosaveName("TimerPanel")
        if !hasSavedFrame, let screen = NSScreen.main?.visibleFrame {
            panel.setFrameOrigin(NSPoint(x: screen.maxX - size.width - 24, y: screen.maxY - size.height - 24))
        }

        panel.level = model.pinned ? .floating : .normal
        model.onPinChange = { [weak panel] pinned in panel?.level = pinned ? .floating : .normal }
        model.onFinish = { [weak self] in self?.showPanel() }

        panel.orderFrontRegardless()
        panel.invalidateShadow()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showPanel()
        return true
    }

    /// Brings the panel forward without activating the app or stealing focus.
    private func showPanel() {
        if panel.isMiniaturized { panel.deminiaturize(nil) }
        panel.orderFrontRegardless()
    }
}

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    app.run()
}
