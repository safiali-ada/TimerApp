import SwiftUI

struct TimerView: View {
    @ObservedObject var model: TimerModel
    @ObservedObject var settings: Settings
    @ObservedObject var stats: FocusStats
    let onClose: () -> Void
    let onMinimize: () -> Void

    @State private var showSettings = false
    @State private var showStats = false

    /// Window size at 100%; every dimension in the layout is multiplied by `settings.scale`.
    static func size(scale: Double, companion: Bool) -> CGSize {
        CGSize(width: 280 * scale, height: (companion ? 310 : 228) * scale)
    }

    private func s(_ value: CGFloat) -> CGFloat { value * settings.scale }
    private var digitFont: Font { .system(size: s(44), weight: .semibold, design: .rounded).monospacedDigit() }
    private var accent: Color { model.mode.accent }

    var body: some View {
        let size = Self.size(scale: settings.scale, companion: settings.showCompanion)
        ZStack(alignment: .bottomTrailing) {
            WindowDragArea()
            card.allowsHitTesting(false)
            VStack(spacing: 0) {
                header.frame(height: s(22))
                if settings.showCompanion {
                    companion.frame(height: s(78)).padding(.top, s(6))
                }
                timeDisplay.frame(height: s(50)).padding(.top, s(4))
                progressBar.frame(height: s(4)).padding(.top, s(4))
                intentionRow.frame(height: s(22)).padding(.top, s(8))
                presetRow.frame(height: s(22)).padding(.top, s(8))
                controls.frame(height: s(30)).padding(.top, s(8))
                footer.frame(height: s(14)).padding(.top, s(8))
                Spacer(minLength: 0)
            }
            .padding(.horizontal, s(12))
            .padding(.top, s(10))
            ResizeGrip(settings: settings, size: s(14)).padding(s(3))
        }
        .frame(width: size.width, height: size.height)
        .clipShape(RoundedRectangle(cornerRadius: s(18), style: .continuous))
        .foregroundColor(.white)
    }

    // MARK: Card

    @ViewBuilder private var card: some View {
        let shape = RoundedRectangle(cornerRadius: s(18), style: .continuous)
        if model.phase == .finished {
            TimelineView(.animation) { context in
                let t = context.date.timeIntervalSinceReferenceDate
                let pulse = (sin(t * .pi * 2) + 1) / 2
                shape.fill(Color(white: 0.11)).overlay(shape.fill(accent.opacity(0.35 + 0.45 * pulse)))
            }
        } else {
            shape.fill(Color(white: 0.11))
                .overlay(shape.fill(LinearGradient(colors: [accent.opacity(0.16), .clear], startPoint: .top, endPoint: .center)))
                .overlay(shape.strokeBorder(Color.white.opacity(0.08)))
        }
    }

    // MARK: Sections

    private var header: some View {
        HStack(spacing: s(4)) {
            WindowDots(size: s(12), onClose: onClose, onMinimize: onMinimize)
            Spacer(minLength: s(4))
            modeTabs
            Spacer(minLength: s(4))
            IconToggle(symbol: "gearshape.fill", isOn: true, size: s(12), help: "Settings") {
                NSApp.activate(ignoringOtherApps: true)
                showSettings.toggle()
            }
            .popover(isPresented: $showSettings, arrowEdge: .bottom) {
                SettingsView(model: model, settings: settings)
            }
            IconToggle(symbol: settings.soundOn ? "bell.fill" : "bell.slash", isOn: settings.soundOn,
                       size: s(12), help: "Alarm sound") { settings.soundOn.toggle() }
            IconToggle(symbol: settings.pinned ? "pin.fill" : "pin.slash", isOn: settings.pinned,
                       size: s(12), help: "Keep on top") { settings.pinned.toggle() }
        }
    }

    private var modeTabs: some View {
        HStack(spacing: s(2)) {
            ForEach(TimerModel.Mode.allCases) { mode in
                let selected = model.mode == mode
                Button { model.select(mode: mode) } label: {
                    Text(mode.title)
                        .font(.system(size: s(10.5), weight: .semibold))
                        .frame(width: s(42), height: s(18))
                        .background(Capsule().fill(selected ? mode.accent.opacity(0.9) : .clear))
                        .opacity(selected ? 1 : 0.6)
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(s(2))
        .background(Capsule().fill(Color.white.opacity(0.07)))
        .disabled(model.phase == .running)
    }

    private var companion: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let state = model.companionState(at: context.date)
            HStack(spacing: s(4)) {
                CompanionView(mood: state.mood, buddy: settings.buddy)
                    .frame(width: s(78), height: s(78))
                SpeechBubble(text: state.message, fontSize: s(11.5), tail: s(7))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .animation(.easeInOut(duration: 0.3), value: state.message)
            }
        }
    }

    @ViewBuilder private var timeDisplay: some View {
        if model.phase == .idle {
            HStack(spacing: s(2)) {
                digitField($model.minutesText, maxLength: 3, alignment: .trailing).frame(width: s(86))
                Text(":").font(digitFont).opacity(0.6)
                digitField($model.secondsText, maxLength: 2, alignment: .leading).frame(width: s(62))
            }
        } else {
            Text(model.timeString)
                .font(digitFont)
                .opacity(model.phase == .paused ? 0.55 : 1)
                .allowsHitTesting(false)
        }
    }

    private func digitField(_ text: Binding<String>, maxLength: Int, alignment: TextAlignment) -> some View {
        TextField("00", text: text)
            .textFieldStyle(.plain)
            .font(digitFont)
            .multilineTextAlignment(alignment)
            .padding(.horizontal, s(4))
            .background(RoundedRectangle(cornerRadius: s(8)).fill(Color.white.opacity(0.06)))
            .onSubmit { model.primaryAction() }
            .onChange(of: text.wrappedValue) { value in
                let digits = String(value.filter(\.isASCII).filter(\.isNumber).prefix(maxLength))
                if digits != value { text.wrappedValue = digits }
            }
    }

    private var progressBar: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.08))
                Capsule().fill(accent)
                    .frame(width: geo.size.width * (1 - model.remainingFraction))
                    .animation(.linear(duration: 0.25), value: model.displaySeconds)
            }
        }
        .padding(.horizontal, s(8))
        .allowsHitTesting(false)
    }

    @ViewBuilder private var intentionRow: some View {
        let font = Font.system(size: s(12), weight: .medium, design: .rounded)
        if model.mode.isBreak {
            Text("Step away · stretch · hydrate")
                .font(font).opacity(0.55).allowsHitTesting(false)
        } else if model.phase == .running {
            Text(model.intention.isEmpty ? "Stay with it 🎯" : "🎯 \(model.intention)")
                .font(font).lineLimit(1).opacity(0.8).allowsHitTesting(false)
        } else {
            TextField("What are you focusing on?", text: $model.intention)
                .textFieldStyle(.plain)
                .font(font)
                .multilineTextAlignment(.center)
                .padding(.horizontal, s(8))
                .frame(maxHeight: .infinity)
                .background(RoundedRectangle(cornerRadius: s(7)).fill(Color.white.opacity(0.06)))
                .onSubmit { model.primaryAction() }
        }
    }

    private var presetRow: some View {
        HStack(spacing: s(6)) {
            ForEach(model.mode.presets, id: \.self) { minutes in
                let selected = model.phase == .idle && model.enteredSeconds == minutes * 60
                Button("\(minutes)m") { model.applyPreset(minutes: minutes) }
                    .buttonStyle(FillButtonStyle(fill: .white.opacity(selected ? 0.22 : 0.08), height: s(22), fontSize: s(11)))
            }
        }
        .disabled(model.phase == .running)
        .opacity(model.phase == .running ? 0.4 : 1)
    }

    private var controls: some View {
        HStack(spacing: s(8)) {
            Button(model.primaryTitle, action: model.primaryAction)
                .buttonStyle(FillButtonStyle(fill: primaryFill, height: s(30), fontSize: s(13)))
                .help("Space")
            Button("Reset", action: model.reset)
                .buttonStyle(FillButtonStyle(fill: .white.opacity(0.1), height: s(30), fontSize: s(13)))
                .help("R")
            Button(action: model.skip) {
                Image(systemName: "forward.end.fill")
            }
            .buttonStyle(FillButtonStyle(fill: .white.opacity(0.1), height: s(30), fontSize: s(12)))
            .frame(width: s(38))
            .help("Skip to \(model.nextMode == .focus ? "focus" : "break") (S)")
        }
    }

    private var primaryFill: Color {
        switch model.phase {
        case .running: Color(red: 0.85, green: 0.55, blue: 0.15)
        case .finished: .white.opacity(0.25)
        case .idle, .paused: accent
        }
    }

    private var footer: some View {
        HStack(spacing: s(4)) {
            ForEach(0..<settings.longBreakEvery, id: \.self) { index in
                Circle()
                    .fill(index < model.completedInCycle ? TimerModel.Mode.focus.accent : Color.white.opacity(0.18))
                    .frame(width: s(6), height: s(6))
            }
            Spacer()
            Button { showStats.toggle() } label: {
                Text(statsSummary)
                    .font(.system(size: s(10.5), weight: .medium, design: .rounded))
                    .opacity(0.6)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Focus history")
            .popover(isPresented: $showStats, arrowEdge: .bottom) { StatsView(stats: stats) }
        }
        .padding(.leading, s(4))
        .padding(.trailing, s(12))
    }

    private var statsSummary: String {
        let today = stats.today
        var text = "Today \(FocusStats.format(seconds: today.seconds)) · \(today.sessions) 🍅"
        if stats.streak > 1 { text += " · 🔥\(stats.streak)" }
        return text
    }
}

extension TimerModel.Mode {
    var accent: Color {
        switch self {
        case .focus: Color(red: 0.93, green: 0.40, blue: 0.36)
        case .shortBreak: Color(red: 0.22, green: 0.68, blue: 0.56)
        case .longBreak: Color(red: 0.36, green: 0.52, blue: 0.92)
        }
    }
}

// MARK: - Components

private struct SpeechBubble: View {
    let text: String
    let fontSize: CGFloat
    let tail: CGFloat

    var body: some View {
        Text(text)
            .font(.system(size: fontSize, weight: .medium, design: .rounded))
            .lineLimit(3)
            .minimumScaleFactor(0.8)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.vertical, fontSize * 0.6)
            .padding(.horizontal, fontSize * 0.8)
            .background(BubbleShape(tail: tail).fill(Color.white.opacity(0.12)))
            .padding(.leading, tail)
            .id(text)
            .transition(.opacity)
            .allowsHitTesting(false)
    }
}

/// Rounded rectangle with a little tail pointing left, toward the companion.
private struct BubbleShape: Shape {
    let tail: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path(roundedRect: rect, cornerRadius: min(rect.height / 2, tail * 1.8), style: .continuous)
        let y = rect.midY + rect.height * 0.15
        path.move(to: CGPoint(x: rect.minX + 1, y: y - tail * 0.7))
        path.addLine(to: CGPoint(x: rect.minX - tail, y: y + tail * 0.4))
        path.addLine(to: CGPoint(x: rect.minX + 1, y: y + tail * 0.5))
        path.closeSubpath()
        return path
    }
}

private struct WindowDots: View {
    let size: CGFloat
    let onClose: () -> Void
    let onMinimize: () -> Void
    @State private var hovering = false

    var body: some View {
        HStack(spacing: size / 2) {
            dot(Color(red: 1, green: 0.37, blue: 0.34), symbol: "xmark", action: onClose)
            dot(Color(red: 1, green: 0.74, blue: 0.18), symbol: "minus", action: onMinimize)
        }
        .onHover { hovering = $0 }
    }

    private func dot(_ color: Color, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Circle().fill(color)
                .frame(width: size, height: size)
                .overlay(
                    Image(systemName: symbol)
                        .font(.system(size: size * 0.58, weight: .bold))
                        .foregroundColor(.black.opacity(0.6))
                        .opacity(hovering ? 1 : 0)
                )
        }
        .buttonStyle(.plain)
    }
}

private struct IconToggle: View {
    let symbol: String
    let isOn: Bool
    let size: CGFloat
    let help: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .medium))
                .frame(width: size * 1.8, height: size * 1.65)
                .opacity(isOn ? 0.95 : 0.45)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

private struct FillButtonStyle: ButtonStyle {
    var fill: Color
    var height: CGFloat = 30
    var fontSize: CGFloat = 13

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: fontSize, weight: .semibold))
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .background(RoundedRectangle(cornerRadius: height / 3, style: .continuous).fill(fill))
            .opacity(configuration.isPressed ? 0.7 : 1)
            .contentShape(Rectangle())
    }
}

/// Lets the user drag the borderless panel from any empty area of the card.
private struct WindowDragArea: NSViewRepresentable {
    final class DragView: NSView {
        override var mouseDownCanMoveWindow: Bool { true }
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
        override func mouseDown(with event: NSEvent) { window?.performDrag(with: event) }
    }

    func makeNSView(context: Context) -> NSView { DragView() }
    func updateNSView(_ nsView: NSView, context: Context) {}
}

/// Bottom-right corner handle that scales the whole window while dragging.
private struct ResizeGrip: View {
    @ObservedObject var settings: Settings
    let size: CGFloat
    @State private var hovering = false

    var body: some View {
        ZStack {
            GripTracker(settings: settings)
            Path { path in
                for inset in [0.35, 0.65] {
                    path.move(to: CGPoint(x: size * inset, y: size * 0.92))
                    path.addLine(to: CGPoint(x: size * 0.92, y: size * inset))
                }
            }
            .stroke(Color.white.opacity(hovering ? 0.6 : 0.22), style: StrokeStyle(lineWidth: 1.3, lineCap: .round))
            .allowsHitTesting(false)
        }
        .frame(width: size, height: size)
        .onHover { hovering = $0 }
        .help("Drag to resize (⌘+ / ⌘−)")
    }

    private struct GripTracker: NSViewRepresentable {
        let settings: Settings

        final class TrackerView: NSView {
            var settings: Settings?
            private var startMouse: NSPoint = .zero
            private var startScale = 1.0

            override var mouseDownCanMoveWindow: Bool { false }
            override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

            override func mouseDown(with event: NSEvent) {
                startMouse = NSEvent.mouseLocation
                startScale = settings?.scale ?? 1
            }

            override func mouseDragged(with event: NSEvent) {
                guard let settings else { return }
                // The window grows from its top-left corner, so right and down both enlarge it.
                let mouse = NSEvent.mouseLocation
                let base = TimerView.size(scale: 1, companion: settings.showCompanion)
                let delta = ((mouse.x - startMouse.x) / base.width + (startMouse.y - mouse.y) / base.height) / 2
                settings.setScale(startScale + delta)
            }
        }

        func makeNSView(context: Context) -> TrackerView {
            let view = TrackerView()
            view.settings = settings
            return view
        }

        func updateNSView(_ nsView: TrackerView, context: Context) { nsView.settings = settings }
    }
}
