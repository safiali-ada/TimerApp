import SwiftUI

/// The little character that keeps the user company. Its mood follows the timer.
enum Buddy: String, CaseIterable, Identifiable {
    case mochi, neko, tomo
    var id: String { rawValue }
    var title: String {
        switch self {
        case .mochi: "Mochi"
        case .neko: "Neko"
        case .tomo: "Tomo"
        }
    }
    fileprivate var body: (top: Color, bottom: Color) {
        switch self {
        case .mochi: (Color(red: 1.0, green: 0.97, blue: 0.97), Color(red: 1.0, green: 0.82, blue: 0.87))
        case .neko: (Color(red: 1.0, green: 0.84, blue: 0.60), Color(red: 0.97, green: 0.64, blue: 0.36))
        case .tomo: (Color(red: 1.0, green: 0.52, blue: 0.45), Color(red: 0.88, green: 0.25, blue: 0.24))
        }
    }
}

enum Mood {
    case ready, sleepy, cheerful, focused, pumped, finalStretch, worried, celebrating, relaxing
}

struct CompanionState {
    let mood: Mood
    let message: String
}

extension TimerModel {
    /// What the companion feels and says right now. `date` drives the slow message rotation.
    func companionState(at date: Date) -> CompanionState {
        let left = displaySeconds
        let fraction = remainingFraction
        let mood: Mood
        var lines: [String]

        switch phase {
        case .idle:
            if date.timeIntervalSince(idleSince) > 180 {
                mood = .sleepy
                lines = ["Zzz… poke me when we start", "*yawn* … study time?", "Dreaming of finished to-do lists…"]
            } else {
                mood = .ready
                lines = mode.isBreak
                    ? ["Time for a little break?", "Rest is part of the work 🌿", "Recharge, then we go again!"]
                    : ["Ready when you are!", "Pick a time and let's go ✨", "One session at a time.", "What are we working on today?"]
            }
        case .paused:
            mood = .worried
            lines = ["I'll wait right here…", "Come back soon? 🥺", "Paused. Ready when you are."]
        case .finished:
            if mode == .focus {
                mood = .celebrating
                let today = stats.today.sessions
                lines = ["You did it! 🎉", "Amazing work!", today > 1 ? "That's \(today) sessions today!" : "First one done today!"]
            } else {
                mood = .ready
                lines = ["Break's over. Ready to focus?", "Recharged? Let's go!"]
            }
        case .running where mode.isBreak:
            mood = .relaxing
            lines = ["Stretch those arms 🙆", "Sip some water 💧", "Look away from the screen 👀", "Breathe in… breathe out…"]
        case .running:
            if left <= 60 || fraction < 0.1 {
                mood = .finalStretch
                lines = ["Final stretch! 🏁", "Almost there!!", "Just a little more!"]
            } else if fraction < 0.34 {
                mood = .pumped
                let minutes = Int((Double(left) / 60).rounded(.up))
                lines = ["Only \(minutes) min to go!", "Look how far you've come!", "Don't stop now 💪"]
            } else if fraction < 0.67 {
                mood = .focused
                lines = ["You're in the zone 🔥", "Steady and strong.", "Shh… we're concentrating", "Keep that momentum!"]
            } else {
                mood = .cheerful
                lines = ["Let's do this! 💪", "Phone away, focus on!", "Deep breath. Here we go.", "Fresh start. You've got this!"]
            }
        }

        if !intention.isEmpty, mode == .focus, phase == .running, mood == .cheerful || mood == .focused {
            lines.append("We've got this: \(intention)")
        }
        let index = Int(date.timeIntervalSinceReferenceDate / 20) % lines.count
        return CompanionState(mood: mood, message: lines[index])
    }
}

/// Animated companion. Tap it for a little bounce.
struct CompanionView: View {
    let mood: Mood
    let buddy: Buddy
    @State private var pokedAt: Date?

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            let pokeAge = pokedAt.map { context.date.timeIntervalSince($0) } ?? .infinity
            CompanionCanvas(mood: mood, buddy: buddy, time: t, pokeAge: pokeAge)
        }
        .contentShape(Rectangle())
        .onTapGesture { pokedAt = Date() }
        .help("Poke \(buddy.title)")
    }
}

/// Draws one frame of the companion. Kept separate from the timeline so it can be rendered at any time value.
struct CompanionCanvas: View {
    let mood: Mood
    let buddy: Buddy
    let time: TimeInterval
    var pokeAge: TimeInterval = .infinity

    var body: some View {
        Canvas { gc, size in
            CompanionRenderer(mood: mood, buddy: buddy, t: time, pokeAge: pokeAge, size: size).draw(&gc)
        }
    }
}

private struct CompanionRenderer {
    let mood: Mood
    let buddy: Buddy
    let t: Double
    let pokeAge: Double
    let size: CGSize

    private var u: CGFloat { min(size.width, size.height) / 100 }
    private var poked: Bool { pokeAge < 0.9 }

    private enum Eyes { case open, happy, closed, sleepy }
    private enum Mouth { case smile, grin, open, flat, wavy, tiny }
    private enum Brows { case none, determined, worried }
    private enum Arms { case rest, wave, up, pump }

    private struct Pose {
        var hop: Double = 0, hopRate: Double = 1, bob: Double = 1, bobRate: Double = 0.5, sway: Double = 0
        var eyes: Eyes = .open, mouth: Mouth = .smile, brows: Brows = .none, arms: Arms = .rest
        var lookUp: Double = 0
    }

    private var pose: Pose {
        var p = Pose()
        switch mood {
        case .ready: p.bob = 1.5; p.sway = 3; p.arms = .wave
        case .sleepy: p.bob = 1.2; p.bobRate = 0.25; p.eyes = .sleepy; p.mouth = .tiny
        case .cheerful: p.hop = 3; p.hopRate = 0.9; p.bob = 0
        case .focused: p.bob = 0.8; p.bobRate = 0.6; p.brows = .determined; p.mouth = .flat
        case .pumped: p.hop = 4; p.hopRate = 1.3; p.bob = 0; p.brows = .determined; p.mouth = .grin; p.arms = .pump
        case .finalStretch: p.hop = 7; p.hopRate = 1.9; p.bob = 0; p.mouth = .open; p.arms = .up
        case .worried: p.bob = 0.6; p.bobRate = 0.4; p.sway = 2; p.brows = .worried; p.mouth = .wavy; p.lookUp = 1
        case .celebrating: p.hop = 12; p.hopRate = 1.5; p.bob = 0; p.eyes = .happy; p.mouth = .open; p.arms = .up
        case .relaxing: p.bob = 1.2; p.bobRate = 0.3; p.sway = 4; p.eyes = .closed; p.mouth = .smile
        }
        if poked { p.eyes = .happy; p.mouth = .open }
        return p
    }

    func draw(_ gc: inout GraphicsContext) {
        let p = pose
        let ground = 94 * u
        let cx = size.width / 2
        let bw = 58 * u, bh = 46 * u

        // Vertical motion: hops (with squash on landing), gentle breathing, and a poke bounce.
        let hopPhase = abs(sin(t * .pi * p.hopRate))
        var lift = CGFloat(p.hop * hopPhase) * u + CGFloat(p.bob * (sin(t * 2 * .pi * p.bobRate) + 1) / 2) * u
        if poked { lift += CGFloat(10 * sin(.pi * pokeAge / 0.9)) * u }
        let squash = p.hop > 0 ? CGFloat(0.07 * pow(1 - hopPhase, 6)) : CGFloat(0.015 * sin(t * 2 * .pi * p.bobRate))
        let sway = Angle.degrees(p.sway * sin(t * 2 * .pi * 0.35))

        // Ground shadow shrinks as the body rises.
        let shadowW = bw * (0.85 - min(lift / (40 * u), 0.4))
        gc.fill(Path(ellipseIn: CGRect(x: cx - shadowW / 2, y: ground - 2.5 * u, width: shadowW, height: 5 * u)),
                with: .color(.black.opacity(0.28)))

        var body = gc
        body.translateBy(x: cx, y: ground - lift)
        body.rotate(by: sway)
        body.scaleBy(x: 1 + squash, y: 1 - squash)
        drawBody(&body, bw: bw, bh: bh, pose: p)

        drawEffects(&gc, center: CGPoint(x: cx, y: ground - lift - bh / 2), bw: bw, bh: bh)
    }

    // MARK: Body

    private func drawBody(_ gc: inout GraphicsContext, bw: CGFloat, bh: CGFloat, pose p: Pose) {
        let colors = buddy.body
        let fill = GraphicsContext.Shading.linearGradient(
            Gradient(colors: [colors.top, colors.bottom]),
            startPoint: CGPoint(x: 0, y: -bh), endPoint: CGPoint(x: 0, y: 0))
        let outline = Color.black.opacity(0.22)

        if buddy == .neko {
            for side in [-1.0, 1.0] {
                let s = CGFloat(side)
                var ear = Path()
                ear.move(to: CGPoint(x: s * bw * 0.44, y: -bh * 0.62))
                ear.addLine(to: CGPoint(x: s * bw * 0.34, y: -bh * 1.13))
                ear.addLine(to: CGPoint(x: s * bw * 0.06, y: -bh * 0.92))
                ear.closeSubpath()
                gc.fill(ear, with: .color(colors.bottom))
                gc.stroke(ear, with: .color(outline), lineWidth: 1.2 * u)
                var inner = Path()
                inner.move(to: CGPoint(x: s * bw * 0.36, y: -bh * 0.78))
                inner.addLine(to: CGPoint(x: s * bw * 0.32, y: -bh * 1.02))
                inner.addLine(to: CGPoint(x: s * bw * 0.17, y: -bh * 0.9))
                inner.closeSubpath()
                gc.fill(inner, with: .color(Color(red: 1, green: 0.62, blue: 0.66)))
            }
        }

        drawArms(&gc, bw: bw, bh: bh, arms: p.arms, fill: colors.bottom, outline: outline)

        // A soft dome with a flat-ish bottom, like a mochi sitting on a table.
        var shape = Path()
        shape.move(to: CGPoint(x: -bw / 2, y: -bh * 0.38))
        shape.addQuadCurve(to: CGPoint(x: 0, y: -bh), control: CGPoint(x: -bw / 2, y: -bh))
        shape.addQuadCurve(to: CGPoint(x: bw / 2, y: -bh * 0.38), control: CGPoint(x: bw / 2, y: -bh))
        shape.addQuadCurve(to: CGPoint(x: bw * 0.32, y: 0), control: CGPoint(x: bw / 2, y: 0))
        shape.addLine(to: CGPoint(x: -bw * 0.32, y: 0))
        shape.addQuadCurve(to: CGPoint(x: -bw / 2, y: -bh * 0.38), control: CGPoint(x: -bw / 2, y: 0))
        shape.closeSubpath()
        gc.fill(shape, with: fill)
        gc.stroke(shape, with: .color(outline), lineWidth: 1.2 * u)

        // Glossy highlight.
        gc.fill(Path(ellipseIn: CGRect(x: -bw * 0.30, y: -bh * 0.90, width: bw * 0.18, height: bh * 0.12)),
                with: .color(.white.opacity(0.55)))

        if buddy == .tomo { drawLeaves(&gc, bh: bh) }
        drawFace(&gc, bw: bw, bh: bh, pose: p)
    }

    private func drawArms(_ gc: inout GraphicsContext, bw: CGFloat, bh: CGFloat, arms: Arms, fill: Color, outline: Color) {
        for side in [-1.0, 1.0] {
            let s = CGFloat(side)
            var center = CGPoint(x: s * (bw / 2 - 1 * u), y: -bh * 0.28)
            var angle = Angle.degrees(side * 20)
            switch arms {
            case .rest:
                break
            case .wave where side > 0:
                center = CGPoint(x: bw / 2 + 2 * u, y: -bh * 0.58)
                angle = .degrees(-50 + 25 * sin(t * 2 * .pi * 1.4))
            case .wave:
                break
            case .up:
                let flap = 12 * sin(t * 2 * .pi * 2 + side)
                center = CGPoint(x: s * (bw / 2 + 2 * u), y: -bh * 0.72)
                angle = .degrees(side * (-55 + flap))
            case .pump:
                let pump = abs(sin(t * .pi * 1.3))
                center = CGPoint(x: s * (bw / 2 + 1 * u), y: -bh * (0.35 + 0.25 * pump))
                angle = .degrees(side * -30)
            }
            var arm = gc
            arm.translateBy(x: center.x, y: center.y)
            arm.rotate(by: angle)
            let rect = CGRect(x: -6 * u, y: -4.5 * u, width: 12 * u, height: 9 * u)
            arm.fill(Path(ellipseIn: rect), with: .color(fill))
            arm.stroke(Path(ellipseIn: rect), with: .color(outline), lineWidth: 1.2 * u)
        }
    }

    private func drawLeaves(_ gc: inout GraphicsContext, bh: CGFloat) {
        let green = Color(red: 0.35, green: 0.72, blue: 0.35)
        for i in 0..<5 {
            var leaf = gc
            leaf.translateBy(x: 0, y: -bh + 1 * u)
            leaf.rotate(by: .degrees(Double(i) * 72 - 90 + 8 * sin(t * 1.5)))
            leaf.fill(Path(ellipseIn: CGRect(x: 0, y: -2.2 * u, width: 9 * u, height: 4.4 * u)), with: .color(green))
        }
        gc.fill(Path(roundedRect: CGRect(x: -1.3 * u, y: -bh - 5 * u, width: 2.6 * u, height: 6 * u), cornerRadius: 1.3 * u),
                with: .color(Color(red: 0.25, green: 0.55, blue: 0.25)))
    }

    private func drawFace(_ gc: inout GraphicsContext, bw: CGFloat, bh: CGFloat, pose p: Pose) {
        let ink = Color(red: 0.22, green: 0.14, blue: 0.20)
        let eyeY = -bh * 0.52
        let line = StrokeStyle(lineWidth: 2.2 * u, lineCap: .round, lineJoin: .round)

        // Blink for a moment every few seconds.
        let blinkCycle = (t + 0.7).truncatingRemainder(dividingBy: 3.8)
        let blink: CGFloat = blinkCycle < 0.13 ? 0.15 : 1

        for side in [-1.0, 1.0] {
            let s = CGFloat(side)
            let x = s * bw * 0.18
            switch p.eyes {
            case .open:
                let h = 9.5 * u * blink, w = 7 * u
                let y = eyeY - CGFloat(p.lookUp) * 1.5 * u
                gc.fill(Path(ellipseIn: CGRect(x: x - w / 2, y: y - h / 2, width: w, height: h)), with: .color(ink))
                if blink == 1 {
                    gc.fill(Path(ellipseIn: CGRect(x: x - 2.6 * u, y: y - 3.6 * u, width: 2.8 * u, height: 2.8 * u)),
                            with: .color(.white))
                }
            case .happy:
                var arc = Path()
                arc.move(to: CGPoint(x: x - 4 * u, y: eyeY + 1.5 * u))
                arc.addQuadCurve(to: CGPoint(x: x + 4 * u, y: eyeY + 1.5 * u), control: CGPoint(x: x, y: eyeY - 5 * u))
                gc.stroke(arc, with: .color(ink), style: line)
            case .closed:
                var arc = Path()
                arc.move(to: CGPoint(x: x - 4 * u, y: eyeY - 1 * u))
                arc.addQuadCurve(to: CGPoint(x: x + 4 * u, y: eyeY - 1 * u), control: CGPoint(x: x, y: eyeY + 4 * u))
                gc.stroke(arc, with: .color(ink), style: line)
            case .sleepy:
                var lid = Path()
                lid.move(to: CGPoint(x: x - 4 * u, y: eyeY + 0.5 * u))
                lid.addQuadCurve(to: CGPoint(x: x + 4 * u, y: eyeY + 0.5 * u), control: CGPoint(x: x, y: eyeY + 2.5 * u))
                gc.stroke(lid, with: .color(ink), style: line)
            }

            if p.brows != .none && !poked {
                // Inner end low = determined, inner end high = worried.
                let innerDrop: CGFloat = p.brows == .determined ? 2.5 * u : -2 * u
                var brow = Path()
                brow.move(to: CGPoint(x: x + s * 4 * u, y: eyeY - 8.5 * u))
                brow.addLine(to: CGPoint(x: x - s * 4 * u, y: eyeY - 8.5 * u + innerDrop))
                gc.stroke(brow, with: .color(ink), style: StrokeStyle(lineWidth: 1.8 * u, lineCap: .round))
            }

            // Rosy cheeks.
            gc.fill(Path(ellipseIn: CGRect(x: s * bw * 0.32 - 4.5 * u, y: -bh * 0.38 - 2.5 * u, width: 9 * u, height: 5 * u)),
                    with: .color(Color(red: 1, green: 0.45, blue: 0.55).opacity(buddy == .tomo ? 0.45 : 0.5)))

            if buddy == .neko {
                for k in [-1.0, 1.0] {
                    var whisker = Path()
                    whisker.move(to: CGPoint(x: s * bw * 0.40, y: -bh * 0.30 + CGFloat(k) * 1.5 * u))
                    whisker.addLine(to: CGPoint(x: s * bw * 0.58, y: -bh * 0.30 + CGFloat(k) * 3 * u))
                    gc.stroke(whisker, with: .color(ink.opacity(0.55)), lineWidth: 0.9 * u)
                }
            }
        }

        drawMouth(&gc, at: CGPoint(x: 0, y: -bh * 0.34), mouth: p.mouth, ink: ink, line: line)
    }

    private func drawMouth(_ gc: inout GraphicsContext, at m: CGPoint, mouth: Mouth, ink: Color, line: StrokeStyle) {
        var path = Path()
        switch mouth {
        case .smile where buddy == .neko:
            // A cat's "ω" smile.
            path.move(to: CGPoint(x: m.x - 4.5 * u, y: m.y))
            path.addQuadCurve(to: CGPoint(x: m.x, y: m.y), control: CGPoint(x: m.x - 2.25 * u, y: m.y + 3.5 * u))
            path.addQuadCurve(to: CGPoint(x: m.x + 4.5 * u, y: m.y), control: CGPoint(x: m.x + 2.25 * u, y: m.y + 3.5 * u))
            gc.stroke(path, with: .color(ink), style: line)
        case .smile:
            path.move(to: CGPoint(x: m.x - 4 * u, y: m.y))
            path.addQuadCurve(to: CGPoint(x: m.x + 4 * u, y: m.y), control: CGPoint(x: m.x, y: m.y + 4.5 * u))
            gc.stroke(path, with: .color(ink), style: line)
        case .grin, .open:
            let w: CGFloat = mouth == .open ? 6 : 5, h: CGFloat = mouth == .open ? 10 : 6
            path.move(to: CGPoint(x: m.x - w * u, y: m.y - 1 * u))
            path.addLine(to: CGPoint(x: m.x + w * u, y: m.y - 1 * u))
            path.addQuadCurve(to: CGPoint(x: m.x - w * u, y: m.y - 1 * u), control: CGPoint(x: m.x, y: m.y + h * u))
            path.closeSubpath()
            gc.fill(path, with: .color(ink))
            var tongue = gc
            tongue.clip(to: path)
            tongue.fill(Path(ellipseIn: CGRect(x: m.x - 3.5 * u, y: m.y + (h / 2 - 2.5) * u, width: 7 * u, height: 5 * u)),
                        with: .color(Color(red: 1, green: 0.45, blue: 0.5)))
        case .flat:
            path.move(to: CGPoint(x: m.x - 3 * u, y: m.y + 0.5 * u))
            path.addQuadCurve(to: CGPoint(x: m.x + 3 * u, y: m.y + 0.5 * u), control: CGPoint(x: m.x, y: m.y + 1.5 * u))
            gc.stroke(path, with: .color(ink), style: line)
        case .wavy:
            path.move(to: CGPoint(x: m.x - 5 * u, y: m.y + 1 * u))
            path.addQuadCurve(to: CGPoint(x: m.x, y: m.y + 1 * u), control: CGPoint(x: m.x - 2.5 * u, y: m.y - 1.5 * u))
            path.addQuadCurve(to: CGPoint(x: m.x + 5 * u, y: m.y + 1 * u), control: CGPoint(x: m.x + 2.5 * u, y: m.y + 3.5 * u))
            gc.stroke(path, with: .color(ink), style: StrokeStyle(lineWidth: 1.8 * u, lineCap: .round))
        case .tiny:
            gc.fill(Path(ellipseIn: CGRect(x: m.x - 1.8 * u, y: m.y - 0.5 * u, width: 3.6 * u, height: 3.6 * u)), with: .color(ink))
        }
    }

    // MARK: Effects

    private func drawEffects(_ gc: inout GraphicsContext, center c: CGPoint, bw: CGFloat, bh: CGFloat) {
        switch mood {
        case .sleepy:
            floating(&gc, symbol: "z", count: 3, from: CGPoint(x: c.x + bw * 0.35, y: c.y - bh * 0.4), drift: 14, color: .white)
        case .relaxing:
            floating(&gc, symbol: "♪", count: 2, from: CGPoint(x: c.x + bw * 0.4, y: c.y - bh * 0.3), drift: 10,
                     color: Color(red: 0.55, green: 0.95, blue: 0.85))
        case .worried:
            let slide = CGFloat((t * 0.6).truncatingRemainder(dividingBy: 1)) * 5 * u
            let x = c.x + bw * 0.42, y = c.y - bh * 0.45 + slide
            var drop = Path()
            drop.move(to: CGPoint(x: x, y: y - 4 * u))
            drop.addQuadCurve(to: CGPoint(x: x, y: y + 3 * u), control: CGPoint(x: x + 5 * u, y: y + 3 * u))
            drop.addQuadCurve(to: CGPoint(x: x, y: y - 4 * u), control: CGPoint(x: x - 5 * u, y: y + 3 * u))
            gc.fill(drop, with: .color(Color(red: 0.55, green: 0.8, blue: 1).opacity(0.9)))
        case .finalStretch, .pumped:
            let count = mood == .finalStretch ? 4 : 2
            for i in 0..<count {
                let angle = Double(i) / Double(count) * 2 * .pi + t * 0.8
                let r = bw * 0.72
                let p = CGPoint(x: c.x + CGFloat(cos(angle)) * r, y: c.y + CGFloat(sin(angle)) * r * 0.6)
                sparkle(&gc, at: p, size: CGFloat(2.5 + 2 * abs(sin(t * 3 + Double(i)))) * u)
            }
        case .celebrating:
            confetti(&gc)
        case .ready, .cheerful, .focused:
            break
        }

        if poked {
            for i in 0..<3 {
                let age = pokeAge - Double(i) * 0.12
                guard age > 0 else { continue }
                let x = c.x + CGFloat(i - 1) * 14 * u
                let y = c.y - bh * 0.7 - CGFloat(age) * 26 * u
                gc.opacity = max(0, 1 - age / 0.9)
                gc.draw(Text("♥").font(.system(size: 10 * u, weight: .bold)).foregroundColor(Color(red: 1, green: 0.45, blue: 0.6)),
                        at: CGPoint(x: x, y: y))
            }
            gc.opacity = 1
        }
    }

    private func floating(_ gc: inout GraphicsContext, symbol: String, count: Int, from origin: CGPoint, drift: Double, color: Color) {
        for i in 0..<count {
            let phase = (t * 0.35 + Double(i) / Double(count)).truncatingRemainder(dividingBy: 1)
            let p = CGPoint(x: origin.x + CGFloat(phase * drift) * u, y: origin.y - CGFloat(phase * 30) * u)
            var layer = gc
            layer.opacity = sin(phase * .pi)
            layer.draw(Text(symbol).font(.system(size: CGFloat(7 + phase * 6) * u, weight: .heavy, design: .rounded))
                .foregroundColor(color), at: p)
        }
    }

    private func sparkle(_ gc: inout GraphicsContext, at p: CGPoint, size s: CGFloat) {
        var star = Path()
        star.move(to: CGPoint(x: p.x, y: p.y - s))
        star.addQuadCurve(to: CGPoint(x: p.x + s, y: p.y), control: p)
        star.addQuadCurve(to: CGPoint(x: p.x, y: p.y + s), control: p)
        star.addQuadCurve(to: CGPoint(x: p.x - s, y: p.y), control: p)
        star.addQuadCurve(to: CGPoint(x: p.x, y: p.y - s), control: p)
        gc.fill(star, with: .color(Color(red: 1, green: 0.88, blue: 0.4)))
    }

    private func confetti(_ gc: inout GraphicsContext) {
        let colors: [Color] = [.pink, .yellow, .mint, .orange, .cyan, .purple]
        for i in 0..<16 {
            let speed = 0.35 + 0.3 * hash(i, 1)
            let fall = (t * speed + hash(i, 2)).truncatingRemainder(dividingBy: 1)
            let x = CGFloat(hash(i, 3)) * size.width + CGFloat(sin(t * 2 + Double(i))) * 3 * u
            let y = CGFloat(fall) * size.height * 1.1 - 6 * u
            var piece = gc
            piece.translateBy(x: x, y: y)
            piece.rotate(by: .radians(t * 4 * (hash(i, 4) - 0.5) * 2 + Double(i)))
            piece.fill(Path(CGRect(x: -1.5 * u, y: -2.5 * u, width: 3 * u, height: 5 * u)), with: .color(colors[i % colors.count]))
        }
    }

    /// Stable pseudo-random value in 0..<1 for a given piece and channel.
    private func hash(_ i: Int, _ k: Int) -> Double {
        let x = sin(Double(i * 127 + k * 311) * 12.9898) * 43758.5453
        return x - x.rounded(.down)
    }
}
