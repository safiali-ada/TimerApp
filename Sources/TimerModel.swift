import AppKit

/// Countdown state. Time left is always derived from `endDate`, so throttling or sleep never causes drift.
@MainActor
final class TimerModel: ObservableObject {
    enum Phase { case idle, running, paused, finished }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var displaySeconds = 0
    @Published var minutesText = "05"
    @Published var secondsText = "00"
    @Published var soundOn: Bool {
        didSet { UserDefaults.standard.set(soundOn, forKey: Keys.sound) }
    }
    @Published var pinned: Bool {
        didSet {
            UserDefaults.standard.set(pinned, forKey: Keys.pinned)
            onPinChange?(pinned)
        }
    }

    var onPinChange: ((Bool) -> Void)?
    var onFinish: (() -> Void)?

    private enum Keys {
        static let sound = "soundOn"
        static let pinned = "pinned"
    }

    private var endDate: Date?
    private var pausedRemaining: TimeInterval = 0
    private var ticker: Timer?
    private let alarm = Alarm()

    init() {
        let defaults = UserDefaults.standard
        soundOn = defaults.object(forKey: Keys.sound) as? Bool ?? true
        pinned = defaults.object(forKey: Keys.pinned) as? Bool ?? true
    }

    var timeString: String {
        String(format: "%02d:%02d", displaySeconds / 60, displaySeconds % 60)
    }

    /// Duration currently typed into the fields, in seconds.
    var enteredSeconds: Int {
        min(Int(minutesText) ?? 0, 999) * 60 + min(Int(secondsText) ?? 0, 59)
    }

    var primaryTitle: String {
        switch phase {
        case .running: "Pause"
        case .finished: "Dismiss"
        case .idle, .paused: "Start"
        }
    }

    func primaryAction() {
        switch phase {
        case .idle: start(seconds: TimeInterval(enteredSeconds))
        case .paused: start(seconds: pausedRemaining)
        case .running: pause()
        case .finished: reset()
        }
    }

    func reset() {
        stopTicker()
        alarm.stop()
        endDate = nil
        phase = .idle
        displaySeconds = enteredSeconds
    }

    func applyPreset(minutes: Int) {
        minutesText = String(format: "%02d", minutes)
        secondsText = "00"
        reset()
    }

    private func start(seconds: TimeInterval) {
        guard seconds > 0 else { return }
        minutesText = String(format: "%02d", enteredSeconds / 60)
        secondsText = String(format: "%02d", enteredSeconds % 60)
        endDate = Date().addingTimeInterval(seconds)
        phase = .running
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
        phase = .paused
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
        phase = .finished
        if soundOn { alarm.play(times: 3) }
        onFinish?()
    }

    private func stopTicker() {
        ticker?.invalidate()
        ticker = nil
    }
}

/// Plays a system sound a fixed number of times back to back.
final class Alarm: NSObject, NSSoundDelegate {
    private let sound = NSSound(named: "Glass")
    private var playsLeft = 0

    func play(times: Int) {
        guard let sound else { return }
        sound.stop()
        sound.delegate = self
        playsLeft = times - 1
        sound.play()
    }

    func stop() {
        playsLeft = 0
        sound?.stop()
    }

    func sound(_ sound: NSSound, didFinishPlaying finished: Bool) {
        guard finished, playsLeft > 0 else { return }
        playsLeft -= 1
        sound.play()
    }
}
