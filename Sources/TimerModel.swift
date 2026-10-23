import AppKit
import Combine

/// Countdown state. Time left is always derived from `endDate`, so throttling or sleep never causes drift.
@MainActor
final class TimerModel: ObservableObject {
    enum Phase { case idle, running, paused, finished }

    enum Mode: String, CaseIterable, Identifiable {
        case focus, shortBreak, longBreak
        var id: String { rawValue }
        var title: String {
            switch self {
            case .focus: "Focus"
            case .shortBreak: "Break"
            case .longBreak: "Long"
            }
        }
        var isBreak: Bool { self != .focus }
        var presets: [Int] { self == .focus ? [15, 25, 45, 60] : [3, 5, 10, 15] }
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var mode: Mode = .focus
    @Published private(set) var displaySeconds = 0
    /// Focus sessions finished since the last long break.
    @Published private(set) var completedInCycle = 0
    /// When the timer last became idle; the companion dozes off after a while.
    @Published private(set) var idleSince = Date()
    @Published var minutesText = "25"
    @Published var secondsText = "00"
    @Published var intention = ""

    let settings: Settings
    let stats: FocusStats
    var onFinish: (() -> Void)?

    private var endDate: Date?
    private var pausedRemaining: TimeInterval = 0
    private(set) var sessionLength: TimeInterval = 0
    private var ticker: Timer?
    private var autoStartWork: DispatchWorkItem?
    private let alarm = Alarm()
    private let noise = NoisePlayer()
    private var cancellables = Set<AnyCancellable>()

    init(settings: Settings, stats: FocusStats) {
        self.settings = settings
        self.stats = stats
        loadDuration(for: .focus)
        displaySeconds = enteredSeconds

        // Keep ambient noise in sync with the settings while a session runs.
        settings.$ambient.combineLatest(settings.$ambientVolume)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.updateAmbient() }
            .store(in: &cancellables)

        // Show edited session lengths right away when nothing is running.
        settings.$focusMinutes.combineLatest(settings.$shortBreakMinutes, settings.$longBreakMinutes)
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self, self.phase == .idle else { return }
                self.loadDuration(for: self.mode)
                self.displaySeconds = self.enteredSeconds
            }
            .store(in: &cancellables)
    }

    var timeString: String { Self.format(displaySeconds) }

    static func format(_ seconds: Int) -> String {
        String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }

    /// Duration currently typed into the fields, in seconds.
    var enteredSeconds: Int {
        min(Int(minutesText) ?? 0, 999) * 60 + min(Int(secondsText) ?? 0, 59)
    }

    /// Fraction of the current session still to go, from 1 down to 0.
    var remainingFraction: Double {
        guard phase != .idle, sessionLength > 0 else { return 1 }
        return min(1, Double(displaySeconds) / sessionLength)
    }

    /// The mode that follows the current one in the Pomodoro cycle.
    var nextMode: Mode {
        switch mode {
        case .focus:
            completedInCycle >= settings.longBreakEvery ? .longBreak : .shortBreak
        case .shortBreak, .longBreak:
            .focus
        }
    }

    var primaryTitle: String {
        switch phase {
        case .running: "Pause"
        case .paused: "Resume"
        case .finished: nextMode == .focus ? "Focus" : "Break"
        case .idle: "Start"
        }
    }

    func primaryAction() {
        switch phase {
        case .idle: start(seconds: TimeInterval(enteredSeconds))
        case .paused: start(seconds: pausedRemaining)
        case .running: pause()
        case .finished: advance(autoStart: true)
        }
    }

    func reset() {
        stopTicker()
        alarm.stop()
        cancelAutoStart()
        endDate = nil
        setPhase(.idle)
        displaySeconds = enteredSeconds
    }

    /// Ends the current session early and moves to the next mode without counting it.
    func skip() {
        if phase == .finished { advance(autoStart: false); return }
        if mode == .longBreak { completedInCycle = 0 }
        switchTo(nextMode)
    }

    func select(mode newMode: Mode) {
        guard phase != .running else { return }
        switchTo(newMode)
    }

    func applyPreset(minutes: Int) {
        minutesText = String(format: "%02d", minutes)
        secondsText = "00"
        reset()
    }

    func previewAlarm() {
        alarm.play(tone: settings.tone, times: 1, volume: settings.alarmVolume)
    }

    // MARK: Private

    private func loadDuration(for mode: Mode) {
        minutesText = String(format: "%02d", settings.minutes(for: mode))
        secondsText = "00"
    }

    private func start(seconds: TimeInterval) {
        guard seconds > 0 else { return }
        cancelAutoStart()
        alarm.stop()
        if phase == .idle { sessionLength = seconds }
        minutesText = String(format: "%02d", enteredSeconds / 60)
        secondsText = String(format: "%02d", enteredSeconds % 60)
        endDate = Date().addingTimeInterval(seconds)
        setPhase(.running)
        tick()
        let timer = Timer(timeInterval: 0.2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        timer.tolerance = 0.05
        RunLoop.main.add(timer, forMode: .common)
        ticker = timer
    }

    private func pause() {
        guard let endDate else { return }
        pausedRemaining = max(0, endDate.timeIntervalSinceNow)
        stopTicker()
        setPhase(.paused)
    }

    private func tick() {
        guard let endDate else { return }
        let remaining = endDate.timeIntervalSinceNow
        let seconds = max(0, Int(remaining.rounded(.up)))
        if seconds != displaySeconds { displaySeconds = seconds }
        if remaining <= 0 { finish() }
    }

    private func finish() {
        stopTicker()
        endDate = nil
        displaySeconds = 0
        if mode == .focus {
            stats.record(seconds: Int(sessionLength))
            completedInCycle += 1
        } else if mode == .longBreak {
            completedInCycle = 0
        }
        setPhase(.finished)
        if settings.soundOn {
            alarm.play(tone: settings.tone, times: settings.alarmRepeats, volume: settings.alarmVolume)
        }
        onFinish?()

        // Give the companion a few seconds to celebrate before rolling into the next session.
        let autoStart = nextMode == .focus ? settings.autoStartFocus : settings.autoStartBreaks
        if autoStart {
            let work = DispatchWorkItem { [weak self] in
                guard let self, self.phase == .finished else { return }
                self.advance(autoStart: true)
            }
            autoStartWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 4, execute: work)
        }
    }

    private func advance(autoStart: Bool) {
        switchTo(nextMode)
        if autoStart { start(seconds: TimeInterval(enteredSeconds)) }
    }

    private func switchTo(_ newMode: Mode) {
        mode = newMode
        loadDuration(for: newMode)
        reset()
    }

    private func setPhase(_ newPhase: Phase) {
        if newPhase == .idle && phase != .idle { idleSince = Date() }
        phase = newPhase
        updateAmbient()
    }

    private func updateAmbient() {
        let active = phase == .running && mode == .focus
        noise.update(kind: active ? settings.ambient : .off, volume: settings.ambientVolume)
    }

    private func cancelAutoStart() {
        autoStartWork?.cancel()
        autoStartWork = nil
    }

    private func stopTicker() {
        ticker?.invalidate()
        ticker = nil
    }
}
