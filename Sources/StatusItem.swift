import AppKit
import Combine

/// Menu bar item that shows the countdown and offers quick controls.
@MainActor
final class StatusItemController: NSObject, NSMenuDelegate {
    private let model: TimerModel
    private let isPanelVisible: () -> Bool
    private let togglePanel: () -> Void
    private var item: NSStatusItem?
    private var cancellables = Set<AnyCancellable>()

    init(model: TimerModel, isPanelVisible: @escaping () -> Bool, togglePanel: @escaping () -> Void) {
        self.model = model
        self.isPanelVisible = isPanelVisible
        self.togglePanel = togglePanel
        super.init()

        model.settings.$showInMenuBar
            .sink { [weak self] show in self?.setVisible(show) }
            .store(in: &cancellables)
        model.$displaySeconds.combineLatest(model.$phase, model.$mode)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.refresh() }
            .store(in: &cancellables)
    }

    private func setVisible(_ show: Bool) {
        if show, item == nil {
            let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
            let menu = NSMenu()
            menu.delegate = self
            item.menu = menu
            self.item = item
            refresh()
        } else if !show, let item {
            NSStatusBar.system.removeStatusItem(item)
            self.item = nil
        }
    }

    private func refresh() {
        guard let button = item?.button else { return }
        let image = NSImage(systemSymbolName: model.mode.isBreak ? "cup.and.saucer.fill" : "timer",
                            accessibilityDescription: "Timer")
        image?.isTemplate = true
        button.image = image
        if model.phase == .idle {
            button.title = ""
            button.imagePosition = .imageOnly
        } else {
            button.attributedTitle = NSAttributedString(
                string: " " + model.timeString,
                attributes: [.font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium)])
            button.imagePosition = .imageLeading
        }
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        let status: String
        switch model.phase {
        case .idle: status = "\(model.mode.title) · \(model.timeString)"
        case .running: status = "\(model.mode.title) · \(model.timeString) left"
        case .paused: status = "Paused · \(model.timeString) left"
        case .finished: status = "\(model.mode.title) finished!"
        }
        menu.addItem(disabledItem(status))
        menu.addItem(.separator())
        menu.addItem(actionItem(model.primaryTitle, #selector(primary)))
        if model.phase != .idle { menu.addItem(actionItem("Reset", #selector(reset))) }
        menu.addItem(actionItem("Skip to \(model.nextMode == .focus ? "Focus" : "Break")", #selector(skip)))
        menu.addItem(.separator())

        let stats = model.stats
        menu.addItem(disabledItem("Today: \(FocusStats.format(seconds: stats.today.seconds)) · \(stats.today.sessions) sessions"))
        if stats.streak > 0 { menu.addItem(disabledItem("Streak: \(stats.streak) day\(stats.streak == 1 ? "" : "s") 🔥")) }
        menu.addItem(.separator())

        menu.addItem(actionItem(isPanelVisible() ? "Hide Timer Window" : "Show Timer Window", #selector(toggleWindow)))
        let quit = actionItem("Quit Timer", #selector(quit))
        quit.keyEquivalent = "q"
        menu.addItem(quit)
    }

    private func disabledItem(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    private func actionItem(_ title: String, _ action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    @objc private func primary() { model.primaryAction() }
    @objc private func reset() { model.reset() }
    @objc private func skip() { model.skip() }
    @objc private func toggleWindow() { togglePanel() }
    @objc private func quit() { NSApp.terminate(nil) }
}
