import AVFoundation
import UIKit

/// Haptics and synthesised sound effects. No audio assets: tones are generated at start-up.
@MainActor
final class Feedback {
    static let shared = Feedback()
    weak var settings: AppSettings?

    enum Sound: CaseIterable { case tap, place, capture, roll, win, lose, error }

    private let engine = AVAudioEngine()
    private let players: [Sound: AVAudioPlayerNode]
    private let buffers: [Sound: AVAudioPCMBuffer]
    private var started = false
    private let impactLight = UIImpactFeedbackGenerator(style: .light)
    private let impactMedium = UIImpactFeedbackGenerator(style: .medium)
    private let notify = UINotificationFeedbackGenerator()

    private init() {
        let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 1)!
        var players: [Sound: AVAudioPlayerNode] = [:]
        var buffers: [Sound: AVAudioPCMBuffer] = [:]
        for sound in Sound.allCases {
            let node = AVAudioPlayerNode()
            engine.attach(node)
            engine.connect(node, to: engine.mainMixerNode, format: format)
            players[sound] = node
            buffers[sound] = Self.render(sound, format: format)
        }
        self.players = players
        self.buffers = buffers
    }

    /// Sequence of (frequency Hz, seconds) notes with a soft envelope.
    private static func notes(for sound: Sound) -> [(Double, Double)] {
        switch sound {
        case .tap: [(880, 0.04)]
        case .place: [(330, 0.05), (440, 0.05)]
        case .capture: [(520, 0.05), (260, 0.09)]
        case .roll: [(300, 0.03), (360, 0.03), (420, 0.03), (500, 0.04)]
        case .win: [(523, 0.1), (659, 0.1), (784, 0.1), (1046, 0.22)]
        case .lose: [(392, 0.14), (330, 0.14), (262, 0.26)]
        case .error: [(200, 0.09), (160, 0.12)]
        }
    }

    private static func render(_ sound: Sound, format: AVAudioFormat) -> AVAudioPCMBuffer {
        let rate = format.sampleRate
        let notes = notes(for: sound)
        let total = Int(notes.reduce(0) { $0 + $1.1 } * rate)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(total))!
        buffer.frameLength = AVAudioFrameCount(total)
        let data = buffer.floatChannelData![0]
        var cursor = 0
        for (freq, seconds) in notes {
            let n = Int(seconds * rate)
            for i in 0 ..< n where cursor + i < total {
                let t = Double(i) / rate
                let env = min(1, Double(i) / (0.004 * rate)) * min(1, Double(n - i) / (0.02 * rate))
                data[cursor + i] = Float(sin(2 * .pi * freq * t) * 0.28 * env)
            }
            cursor += n
        }
        return buffer
    }

    private func startIfNeeded() {
        guard !started else { return }
        try? AVAudioSession.sharedInstance().setCategory(.ambient, mode: .default, options: [.mixWithOthers])
        try? AVAudioSession.sharedInstance().setActive(true)
        engine.prepare()
        do { try engine.start(); started = true } catch { started = false }
    }

    func play(_ sound: Sound) {
        guard settings?.sound ?? true, let node = players[sound], let buffer = buffers[sound] else { return }
        startIfNeeded()
        guard started else { return }
        node.stop()
        node.scheduleBuffer(buffer, at: nil, options: .interrupts)
        node.play()
    }

    func tap() { if settings?.haptics ?? true { impactLight.impactOccurred() }; play(.tap) }
    func thud() { if settings?.haptics ?? true { impactMedium.impactOccurred() } }
    func success() { if settings?.haptics ?? true { notify.notificationOccurred(.success) }; play(.win) }
    func failure() { if settings?.haptics ?? true { notify.notificationOccurred(.error) }; play(.error) }
}
