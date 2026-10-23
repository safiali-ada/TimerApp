import SwiftUI

struct TimerView: View {
    @ObservedObject var model: TimerModel
    let onClose: () -> Void
    let onMinimize: () -> Void

    private static let presets = [1, 5, 10, 25]
    private let digitFont = Font.system(size: 42, weight: .semibold, design: .rounded).monospacedDigit()

    var body: some View {
        ZStack {
            WindowDragArea()
            card.allowsHitTesting(false)
            VStack(spacing: 10) {
                header
                timeDisplay.frame(height: 52)
                presetRow
                controls
            }
            .padding(.horizontal, 14)
            .padding(.top, 10)
            .padding(.bottom, 14)
        }
        .frame(width: 260, height: 190)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .foregroundColor(.white)
    }

    // MARK: Card

    @ViewBuilder private var card: some View {
        let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)
        if model.phase == .finished {
            TimelineView(.animation) { context in
                let t = context.date.timeIntervalSinceReferenceDate
                let pulse = (sin(t * .pi * 2) + 1) / 2
                shape.fill(Color(red: 0.62 + 0.28 * pulse, green: 0.10 + 0.06 * pulse, blue: 0.12))
            }
        } else {
            shape.fill(Color(white: 0.11))
                .overlay(shape.strokeBorder(Color.white.opacity(0.08)))
        }
    }

    // MARK: Sections

    private var header: some View {
        HStack(spacing: 6) {
            WindowDots(onClose: onClose, onMinimize: onMinimize)
            Spacer()
            IconToggle(symbol: model.soundOn ? "bell.fill" : "bell.slash", isOn: model.soundOn,
                       help: "Sound") { model.soundOn.toggle() }
            IconToggle(symbol: model.pinned ? "pin.fill" : "pin.slash", isOn: model.pinned,
                       help: "Keep on top") { model.pinned.toggle() }
        }
    }

    @ViewBuilder private var timeDisplay: some View {
        if model.phase == .idle {
            HStack(spacing: 2) {
                digitField($model.minutesText, maxLength: 3, alignment: .trailing).frame(width: 82)
                Text(":").font(digitFont).opacity(0.6)
                digitField($model.secondsText, maxLength: 2, alignment: .leading).frame(width: 60)
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
            .padding(.horizontal, 4)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.06)))
            .onSubmit { model.primaryAction() }
            .onChange(of: text.wrappedValue) { value in
                let digits = String(value.filter(\.isASCII).filter(\.isNumber).prefix(maxLength))
                if digits != value { text.wrappedValue = digits }
            }
    }

    private var presetRow: some View {
        HStack(spacing: 6) {
            ForEach(Self.presets, id: \.self) { minutes in
                let selected = model.phase == .idle && model.enteredSeconds == minutes * 60
                Button("\(minutes)m") { model.applyPreset(minutes: minutes) }
                    .buttonStyle(FillButtonStyle(fill: .white.opacity(selected ? 0.22 : 0.08), height: 22, fontSize: 11))
            }
        }
        .disabled(model.phase == .running)
        .opacity(model.phase == .running ? 0.4 : 1)
    }

    private var controls: some View {
        HStack(spacing: 8) {
            Button(model.primaryTitle, action: model.primaryAction)
                .buttonStyle(FillButtonStyle(fill: primaryFill))
            Button("Reset", action: model.reset)
                .buttonStyle(FillButtonStyle(fill: .white.opacity(0.1)))
        }
    }

    private var primaryFill: Color {
        switch model.phase {
        case .running: Color(red: 0.85, green: 0.55, blue: 0.15)
        case .finished: .white.opacity(0.25)
        case .idle, .paused: Color(red: 0.2, green: 0.62, blue: 0.35)
        }
    }
}

// MARK: - Components

private struct WindowDots: View {
    let onClose: () -> Void
    let onMinimize: () -> Void
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 6) {
            dot(Color(red: 1, green: 0.37, blue: 0.34), symbol: "xmark", action: onClose)
            dot(Color(red: 1, green: 0.74, blue: 0.18), symbol: "minus", action: onMinimize)
        }
        .onHover { hovering = $0 }
    }

    private func dot(_ color: Color, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Circle().fill(color)
                .frame(width: 12, height: 12)
                .overlay(
                    Image(systemName: symbol)
                        .font(.system(size: 7, weight: .bold))
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
    let help: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .medium))
                .frame(width: 24, height: 20)
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
