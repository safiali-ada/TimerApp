import Foundation

/// User preferences, persisted in UserDefaults as soon as they change.
@MainActor
final class Settings: ObservableObject {
    static let scaleRange: ClosedRange<Double> = 0.75...2.0

    // Timer
    @Published var focusMinutes: Int { didSet { save(focusMinutes, Keys.focus) } }
    @Published var shortBreakMinutes: Int { didSet { save(shortBreakMinutes, Keys.shortBreak) } }
    @Published var longBreakMinutes: Int { didSet { save(longBreakMinutes, Keys.longBreak) } }
    @Published var longBreakEvery: Int { didSet { save(longBreakEvery, Keys.longBreakEvery) } }
    @Published var autoStartBreaks: Bool { didSet { save(autoStartBreaks, Keys.autoBreaks) } }
    @Published var autoStartFocus: Bool { didSet { save(autoStartFocus, Keys.autoFocus) } }

    // Sound
    @Published var soundOn: Bool { didSet { save(soundOn, Keys.sound) } }
    /// A system sound name (e.g. "Glass") or an absolute path to an audio file.
    @Published var tone: String { didSet { save(tone, Keys.tone) } }
    @Published var alarmRepeats: Int { didSet { save(alarmRepeats, Keys.repeats) } }
    @Published var alarmVolume: Double { didSet { save(alarmVolume, Keys.alarmVolume) } }
    @Published var ambient: NoisePlayer.Kind { didSet { save(ambient.rawValue, Keys.ambient) } }
    @Published var ambientVolume: Double { didSet { save(ambientVolume, Keys.ambientVolume) } }

    // Window & companion
    @Published var pinned: Bool { didSet { save(pinned, Keys.pinned) } }
    @Published var scale: Double { didSet { save(scale, Keys.scale) } }
    @Published var showCompanion: Bool { didSet { save(showCompanion, Keys.companion) } }
    @Published var buddy: Buddy { didSet { save(buddy.rawValue, Keys.character) } }
    @Published var showInMenuBar: Bool { didSet { save(showInMenuBar, Keys.menuBar) } }

    private enum Keys {
        static let focus = "focusMinutes"
        static let shortBreak = "shortBreakMinutes"
        static let longBreak = "longBreakMinutes"
        static let longBreakEvery = "longBreakEvery"
        static let autoBreaks = "autoStartBreaks"
        static let autoFocus = "autoStartFocus"
        static let sound = "soundOn"
        static let tone = "alarmTone"
        static let repeats = "alarmRepeats"
        static let alarmVolume = "alarmVolume"
        static let ambient = "ambientNoise"
        static let ambientVolume = "ambientVolume"
        static let pinned = "pinned"
        static let scale = "windowScale"
        static let companion = "showCompanion"
        static let character = "companionCharacter"
        static let menuBar = "showInMenuBar"
    }

    init() {
        let d = UserDefaults.standard
        func value<T>(_ key: String, _ fallback: T) -> T { d.object(forKey: key) as? T ?? fallback }

        focusMinutes = value(Keys.focus, 25)
        shortBreakMinutes = value(Keys.shortBreak, 5)
        longBreakMinutes = value(Keys.longBreak, 15)
        longBreakEvery = value(Keys.longBreakEvery, 4)
        autoStartBreaks = value(Keys.autoBreaks, false)
        autoStartFocus = value(Keys.autoFocus, false)
        soundOn = value(Keys.sound, true)
        tone = value(Keys.tone, "Glass")
        alarmRepeats = value(Keys.repeats, 3)
        alarmVolume = value(Keys.alarmVolume, 1.0)
        ambient = NoisePlayer.Kind(rawValue: value(Keys.ambient, "")) ?? .off
        ambientVolume = value(Keys.ambientVolume, 0.35)
        pinned = value(Keys.pinned, true)
        scale = min(max(value(Keys.scale, 1.0), Self.scaleRange.lowerBound), Self.scaleRange.upperBound)
        showCompanion = value(Keys.companion, true)
        buddy = Buddy(rawValue: value(Keys.character, "")) ?? .mochi
        showInMenuBar = value(Keys.menuBar, true)
    }

    func minutes(for mode: TimerModel.Mode) -> Int {
        switch mode {
        case .focus: focusMinutes
        case .shortBreak: shortBreakMinutes
        case .longBreak: longBreakMinutes
        }
    }

    func setScale(_ newValue: Double) {
        let clamped = min(max(newValue, Self.scaleRange.lowerBound), Self.scaleRange.upperBound)
        let rounded = (clamped * 100).rounded() / 100
        if rounded != scale { scale = rounded }
    }

    private func save(_ value: Any, _ key: String) {
        UserDefaults.standard.set(value, forKey: key)
    }
}
