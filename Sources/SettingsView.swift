import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @ObservedObject var model: TimerModel
    @ObservedObject var settings: Settings

    var body: some View {
        Form {
            Section("Sessions") {
                Stepper("Focus: \(settings.focusMinutes) min", value: $settings.focusMinutes, in: 1...180)
                Stepper("Short break: \(settings.shortBreakMinutes) min", value: $settings.shortBreakMinutes, in: 1...60)
                Stepper("Long break: \(settings.longBreakMinutes) min", value: $settings.longBreakMinutes, in: 1...90)
                Stepper("Long break after \(settings.longBreakEvery) sessions", value: $settings.longBreakEvery, in: 2...8)
                Toggle("Start breaks automatically", isOn: $settings.autoStartBreaks)
                Toggle("Start focus automatically", isOn: $settings.autoStartFocus)
            }

            Section("Alarm") {
                Toggle("Play alarm when time is up", isOn: $settings.soundOn)
                Picker("Tone", selection: $settings.tone) {
                    ForEach(AlarmTones.systemNames, id: \.self) { Text($0).tag($0) }
                    if AlarmTones.isCustomFile(settings.tone) {
                        Divider()
                        Text(AlarmTones.displayName(settings.tone)).tag(settings.tone)
                    }
                }
                .onChange(of: settings.tone) { _ in model.previewAlarm() }
                HStack {
                    Button { model.previewAlarm() } label: { Label("Preview", systemImage: "play.fill") }
                    Spacer()
                    Button("Choose Sound File…", action: chooseToneFile)
                }
                Stepper("Ring \(settings.alarmRepeats) \(settings.alarmRepeats == 1 ? "time" : "times")",
                        value: $settings.alarmRepeats, in: 1...10)
                volumeSlider("Volume", value: $settings.alarmVolume)
            }

            Section {
                Picker("Background sound", selection: $settings.ambient) {
                    ForEach(NoisePlayer.Kind.allCases) { Text($0.title).tag($0) }
                }
                if settings.ambient != .off {
                    volumeSlider("Volume", value: $settings.ambientVolume)
                }
            } header: {
                Text("Ambient")
            } footer: {
                Text("Plays only while a focus session is running.").font(.caption).foregroundStyle(.secondary)
            }

            Section("Window") {
                LabeledContent("Size") {
                    HStack {
                        Slider(value: Binding(get: { settings.scale }, set: { settings.setScale($0) }),
                               in: Settings.scaleRange)
                        Text("\(Int((settings.scale * 100).rounded()))%")
                            .monospacedDigit()
                            .frame(width: 42, alignment: .trailing)
                    }
                }
                Text("Tip: drag the bottom-right corner, or press ⌘+ / ⌘− / ⌘0.")
                    .font(.caption).foregroundStyle(.secondary)
                Toggle("Keep on top of other windows", isOn: $settings.pinned)
                Toggle("Show timer in menu bar", isOn: $settings.showInMenuBar)
            }

            Section("Companion") {
                Toggle("Show companion", isOn: $settings.showCompanion)
                if settings.showCompanion {
                    HStack(spacing: 10) {
                        ForEach(Buddy.allCases) { buddy in
                            buddyChoice(buddy)
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
            }

            Section {
                HStack {
                    Text("Space start/pause · R reset · S skip · Esc unfocus")
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("Quit Timer") { NSApp.terminate(nil) }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 360, height: 520)
    }

    private func volumeSlider(_ title: String, value: Binding<Double>) -> some View {
        LabeledContent(title) {
            HStack(spacing: 6) {
                Image(systemName: "speaker.fill").foregroundStyle(.secondary)
                Slider(value: value, in: 0...1)
                Image(systemName: "speaker.wave.3.fill").foregroundStyle(.secondary)
            }
        }
    }

    private func buddyChoice(_ buddy: Buddy) -> some View {
        let selected = settings.buddy == buddy
        return Button { settings.buddy = buddy } label: {
            VStack(spacing: 2) {
                CompanionCanvas(mood: selected ? .cheerful : .ready, buddy: buddy, time: 0.25)
                    .frame(width: 56, height: 56)
                Text(buddy.title).font(.caption.weight(selected ? .semibold : .regular))
            }
            .padding(6)
            .background(RoundedRectangle(cornerRadius: 10).fill(selected ? Color.accentColor.opacity(0.25) : Color.gray.opacity(0.12)))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(selected ? Color.accentColor : .clear, lineWidth: 1.5))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func chooseToneFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.audio]
        panel.allowsMultipleSelection = false
        panel.message = "Choose a sound to play when the timer ends"
        NSApp.activate(ignoringOtherApps: true)
        if panel.runModal() == .OK, let url = panel.url {
            settings.tone = url.path
        }
    }
}

struct StatsView: View {
    @ObservedObject var stats: FocusStats

    var body: some View {
        let week = stats.week
        let maxSeconds = max(week.map(\.day.seconds).max() ?? 0, 25 * 60)
        let weekTotal = week.reduce(0) { $0 + $1.day.seconds }

        VStack(alignment: .leading, spacing: 12) {
            Text("This week").font(.headline)
            HStack(alignment: .bottom, spacing: 8) {
                ForEach(week, id: \.date) { entry in
                    let isToday = Calendar.current.isDateInToday(entry.date)
                    VStack(spacing: 4) {
                        Text(entry.day.seconds > 0 ? FocusStats.format(seconds: entry.day.seconds) : " ")
                            .font(.system(size: 9)).foregroundStyle(.secondary)
                            .fixedSize()
                        RoundedRectangle(cornerRadius: 4)
                            .fill(isToday ? TimerModel.Mode.focus.accent : TimerModel.Mode.focus.accent.opacity(0.5))
                            .frame(width: 22, height: max(3, 80 * CGFloat(entry.day.seconds) / CGFloat(maxSeconds)))
                        Text(entry.date.formatted(.dateTime.weekday(.narrow)))
                            .font(.caption2.weight(isToday ? .bold : .regular))
                    }
                }
            }
            .frame(maxWidth: .infinity)
            Divider()
            statRow("Today", "\(FocusStats.format(seconds: stats.today.seconds)) · \(stats.today.sessions) sessions")
            statRow("This week", FocusStats.format(seconds: weekTotal))
            statRow("Streak", stats.streak == 1 ? "1 day" : "\(stats.streak) days")
        }
        .padding(16)
        .frame(width: 270)
    }

    private func statRow(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title).foregroundStyle(.secondary)
            Spacer()
            Text(value).monospacedDigit()
        }
        .font(.callout)
    }
}
