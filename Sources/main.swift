import AppKit
import Combine
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
    private let settings = Settings()
    private let stats = FocusStats()
    private lazy var model = TimerModel(settings: settings, stats: stats)
    private var panel: FloatingPanel!
    private var statusItem: StatusItemController?
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        let size = TimerView.size(scale: settings.scale, companion: settings.showCompanion)
        let panel = FloatingPanel(size: size)
        self.panel = panel

        let hostingView = FirstMouseHostingView(rootView: TimerView(
            model: model,
            settings: settings,
            stats: stats,
            onClose: { [weak self] in self?.closePanel() },
            onMinimize: { [weak panel] in panel?.miniaturize(nil) }
        ))
        // The app sizes the panel itself, from the scale setting.
        hostingView.sizingOptions = []
        panel.contentView = hostingView

        // Restore the last position; on first launch start in the top-right corner.
        let hasSavedFrame = UserDefaults.standard.string(forKey: "NSWindow Frame TimerPanel") != nil
        panel.setFrameAutosaveName("TimerPanel")
        if !hasSavedFrame, let screen = NSScreen.main?.visibleFrame {
            panel.setFrameOrigin(NSPoint(x: screen.maxX - size.width - 24, y: screen.maxY - size.height - 24))
        }

        settings.$scale.combineLatest(settings.$showCompanion)
            .sink { [weak self] scale, companion in self?.resizePanel(scale: scale, companion: companion) }
            .store(in: &cancellables)
        settings.$pinned
            .sink { [weak panel] pinned in panel?.level = pinned ? .floating : .normal }
            .store(in: &cancellables)
        model.onFinish = { [weak self] in self?.showPanel() }

        statusItem = StatusItemController(
            model: model,
            isPanelVisible: { [weak panel] in panel?.isVisible ?? false },
            togglePanel: { [weak self] in
                guard let self else { return }
                if self.panel.isVisible { self.panel.orderOut(nil) } else { self.showPanel() }
            })

        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, event.window === self.panel else { return event }
            return self.handleKey(event) ? nil : event
        }

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

    /// With the menu bar item available the timer keeps running there; otherwise closing quits.
    private func closePanel() {
        if settings.showInMenuBar { panel.orderOut(nil) } else { NSApp.terminate(nil) }
    }

    /// Resizes around the top-left corner, keeping the panel on screen.
    private func resizePanel(scale: Double, companion: Bool) {
        let size = TimerView.size(scale: scale, companion: companion)
        var frame = panel.frame
        frame.origin.y = frame.maxY - size.height
        frame.size = size
        if let visible = (panel.screen ?? NSScreen.main)?.visibleFrame {
            frame.origin.x = min(max(frame.origin.x, visible.minX), visible.maxX - size.width)
            frame.origin.y = min(max(frame.origin.y, visible.minY), visible.maxY - size.height)
        }
        panel.setFrame(frame, display: true)
        panel.invalidateShadow()
    }

    private func handleKey(_ event: NSEvent) -> Bool {
        let key = event.charactersIgnoringModifiers?.lowercased() ?? ""
        if event.modifierFlags.contains(.command) {
            switch key {
            case "=", "+": settings.setScale(settings.scale + 0.1)
            case "-": settings.setScale(settings.scale - 0.1)
            case "0": settings.setScale(1)
            case "w": closePanel()
            case "q": NSApp.terminate(nil)
            default: return false
            }
            return true
        }

        // Escape leaves a text field; other shortcuts only apply when not typing.
        let editing = panel.firstResponder is NSText
        if event.keyCode == 53 {
            panel.makeFirstResponder(nil)
            return true
        }
        guard !editing else { return false }
        switch key {
        case " ": model.primaryAction()
        case "r": model.reset()
        case "s": model.skip()
        default: return false
        }
        return true
    }
}

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    app.run()
}
