import AVFoundation

/// macOS system voices via AVSpeechSynthesizer. Supports word-level progress.
@MainActor
final class AppleSpeechEngine: NSObject, SpeechEngine, AVSpeechSynthesizerDelegate {
    var onWord: ((NSRange) -> Void)?
    var onFinish: (() -> Void)?

    private let synthesizer = AVSpeechSynthesizer()
    private let voice: AVSpeechSynthesisVoice?
    private var current: AVSpeechUtterance?

    init(identifier: String) {
        voice = AVSpeechSynthesisVoice(identifier: identifier)
        super.init()
        synthesizer.delegate = self
    }

    /// Maps a 0.5–2.0 speed multiplier onto AVSpeechUtterance's 0–1 rate scale (1.0 = default rate).
    static func rate(for speed: Double) -> Float {
        let normal = Double(AVSpeechUtteranceDefaultSpeechRate)
        let maximum = Double(AVSpeechUtteranceMaximumSpeechRate)
        let rate = speed <= 1 ? normal * speed : normal + (speed - 1) * (maximum - normal)
        return Float(min(max(rate, Double(AVSpeechUtteranceMinimumSpeechRate)), maximum))
    }

    func speak(_ text: String, prefetchNext next: String?, speed: Double, pitch: Double) {
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = voice
        utterance.rate = Self.rate(for: speed)
        utterance.pitchMultiplier = Float(pitch)
        utterance.preUtteranceDelay = 0
        utterance.postUtteranceDelay = 0
        current = utterance
        if synthesizer.isSpeaking || synthesizer.isPaused {
            synthesizer.stopSpeaking(at: .immediate)
        }
        synthesizer.speak(utterance)
    }

    func pause() { synthesizer.pauseSpeaking(at: .word) }
    func resume() { synthesizer.continueSpeaking() }

    func stop() {
        current = nil
        synthesizer.stopSpeaking(at: .immediate)
    }

    func setPitch(_ pitch: Double) {}

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, willSpeakRangeOfSpeechString characterRange: NSRange, utterance: AVSpeechUtterance) {
        let id = ObjectIdentifier(utterance)
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                guard self.isCurrent(id) else { return }
                self.onWord?(characterRange)
            }
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        let id = ObjectIdentifier(utterance)
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                guard self.isCurrent(id) else { return }
                self.current = nil
                self.onFinish?()
            }
        }
    }

    private func isCurrent(_ id: ObjectIdentifier) -> Bool {
        current.map(ObjectIdentifier.init) == id
    }
}
