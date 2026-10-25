import AppKit
import AVFoundation

/// Alarm tones available on this Mac: the built-in system sounds plus any the user has installed.
enum AlarmTones {
    static let systemNames: [String] = {
        let dirs = ["/System/Library/Sounds", "/Library/Sounds", NSHomeDirectory() + "/Library/Sounds"]
        let extensions: Set<String> = ["aiff", "aif", "caf", "wav", "mp3", "m4a"]
        var names = Set<String>()
        for dir in dirs {
            let files = (try? FileManager.default.contentsOfDirectory(atPath: dir)) ?? []
            for file in files where extensions.contains((file as NSString).pathExtension.lowercased()) {
                names.insert((file as NSString).deletingPathExtension)
            }
        }
        return names.sorted()
    }()

    static func isCustomFile(_ tone: String) -> Bool { tone.hasPrefix("/") }

    /// Copies a user-picked file into Application Support. The sandbox only grants access to it
    /// while the open panel's selection is live, so keeping our own copy lets it play after relaunch.
    static func importFile(_ url: URL) -> URL? {
        let fm = FileManager.default
        guard let support = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
        let dir = support.appendingPathComponent("Tones", isDirectory: true)
        let dest = dir.appendingPathComponent(url.lastPathComponent)
        if url.standardizedFileURL == dest.standardizedFileURL { return dest }
        do {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
            if fm.fileExists(atPath: dest.path) { try fm.removeItem(at: dest) }
            try fm.copyItem(at: url, to: dest)
            return dest
        } catch {
            return nil
        }
    }

    static func displayName(_ tone: String) -> String {
        isCustomFile(tone) ? ((tone as NSString).lastPathComponent as NSString).deletingPathExtension : tone
    }

    static func sound(for tone: String) -> NSSound? {
        if isCustomFile(tone) { return NSSound(contentsOfFile: tone, byReference: true) }
        return NSSound(named: tone)
    }
}

/// Plays the chosen alarm tone a number of times back to back.
final class Alarm: NSObject, NSSoundDelegate {
    private var sound: NSSound?
    private var playsLeft = 0

    func play(tone: String, times: Int, volume: Double) {
        stop()
        guard let sound = AlarmTones.sound(for: tone) ?? NSSound(named: "Glass") else { return }
        sound.delegate = self
        sound.volume = Float(volume)
        self.sound = sound
        playsLeft = max(times, 1) - 1
        sound.play()
    }

    func stop() {
        playsLeft = 0
        sound?.stop()
    }

    func sound(_ sound: NSSound, didFinishPlaying finished: Bool) {
        guard finished, playsLeft > 0, sound === self.sound else { return }
        playsLeft -= 1
        sound.play()
    }
}

/// Generates soft background noise while the user focuses.
final class NoisePlayer {
    enum Kind: String, CaseIterable, Identifiable {
        case off, white, pink, brown
        var id: String { rawValue }
        var title: String {
            switch self {
            case .off: "Off"
            case .white: "White noise"
            case .pink: "Pink noise (rain)"
            case .brown: "Brown noise (deep)"
            }
        }
    }

    private let engine = AVAudioEngine()
    private var source: AVAudioSourceNode?
    private var playing: Kind = .off

    /// Starts, switches or stops the noise; calling it repeatedly with the same values is cheap.
    func update(kind: Kind, volume: Double) {
        engine.mainMixerNode.outputVolume = Float(volume)
        guard kind != playing else { return }
        stop()
        guard kind != .off else { return }

        let sampleRate = engine.outputNode.outputFormat(forBus: 0).sampleRate
        guard sampleRate > 0, let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1) else { return }
        let node = AVAudioSourceNode(format: format, renderBlock: Self.renderBlock(for: kind))
        engine.attach(node)
        engine.connect(node, to: engine.mainMixerNode, format: format)
        do {
            try engine.start()
            source = node
            playing = kind
        } catch {
            engine.detach(node)
        }
    }

    func stop() {
        engine.stop()
        if let source { engine.detach(source) }
        source = nil
        playing = .off
    }

    private static func renderBlock(for kind: Kind) -> AVAudioSourceNodeRenderBlock {
        // Filter memory lives in plain stored properties so the audio thread never allocates.
        final class State { var brown: Float = 0, b0: Float = 0, b1: Float = 0, b2: Float = 0, b3: Float = 0, b4: Float = 0, b5: Float = 0, b6: Float = 0 }
        let state = State()
        return { _, _, frameCount, bufferList in
            for buffer in UnsafeMutableAudioBufferListPointer(bufferList) {
                guard let out = buffer.mData?.assumingMemoryBound(to: Float.self) else { continue }
                for i in 0..<Int(frameCount) {
                    let white = Float.random(in: -1...1)
                    switch kind {
                    case .off:
                        out[i] = 0
                    case .white:
                        out[i] = white * 0.25
                    case .pink:
                        // Paul Kellet's refined pink noise filter.
                        let s = state
                        s.b0 = 0.99886 * s.b0 + white * 0.0555179
                        s.b1 = 0.99332 * s.b1 + white * 0.0750759
                        s.b2 = 0.96900 * s.b2 + white * 0.1538520
                        s.b3 = 0.86650 * s.b3 + white * 0.3104856
                        s.b4 = 0.55000 * s.b4 + white * 0.5329522
                        s.b5 = -0.7616 * s.b5 - white * 0.0168980
                        let sum = s.b0 + s.b1 + s.b2 + s.b3 + s.b4 + s.b5 + s.b6 + white * 0.5362
                        s.b6 = white * 0.115926
                        out[i] = sum * 0.06
                    case .brown:
                        state.brown = (state.brown + 0.02 * white) / 1.02
                        out[i] = state.brown * 2.5
                    }
                }
            }
            return noErr
        }
    }
}
