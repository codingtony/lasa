import AVFoundation
import CSherpaOnnx

enum PiperError: Error {
    case loadFailed(String)
}

/// sherpa-onnx TTS handle. Generation only ever runs on the serial `synthQueue`.
private struct TTSHandle: @unchecked Sendable {
    let pointer: OpaquePointer
}

/// Bundled Piper (VITS) neural voices via the sherpa-onnx C API, played through AVAudioEngine.
@MainActor
final class PiperSpeechEngine: SpeechEngine {
    var onWord: ((NSRange) -> Void)?
    var onFinish: (() -> Void)?

    private let tts: TTSHandle
    private let format: AVAudioFormat
    private let synthQueue = DispatchQueue(label: "lasa.piper.synthesis")
    private let audioEngine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let timePitch = AVAudioUnitTimePitch()

    /// Bumped by every `speak`/`stop`; stale completions compare against it and bail out.
    private var generation = 0
    /// Audio is always synthesized at the model's natural speed (the model's own speed
    /// parameter scales sub-linearly: 2.0 only gives ~1.56×), so buffers depend on text alone
    /// and `timePitch.rate` applies the exact requested speed.
    private var cache: (text: String, buffer: AVAudioPCMBuffer)?
    private var prefetching: String?
    /// A `speak` that arrived while its text was still being prefetched.
    private var awaitingPrefetch: (generation: Int, next: String?)?

    init(voiceDir: URL) throws {
        let files = (try? FileManager.default.contentsOfDirectory(at: voiceDir, includingPropertiesForKeys: nil)) ?? []
        guard let model = files.first(where: { $0.pathExtension == "onnx" }) else {
            throw PiperError.loadFailed(voiceDir.lastPathComponent)
        }
        let modelPath = strdup(model.path)
        let tokensPath = strdup(voiceDir.appendingPathComponent("tokens.txt").path)
        let dataDir = strdup(voiceDir.appendingPathComponent("espeak-ng-data").path)
        let provider = strdup("cpu")
        defer { free(modelPath); free(tokensPath); free(dataDir); free(provider) }

        var config = SherpaOnnxOfflineTtsConfig()
        config.model.vits.model = UnsafePointer(modelPath)
        config.model.vits.tokens = UnsafePointer(tokensPath)
        config.model.vits.data_dir = UnsafePointer(dataDir)
        config.model.vits.noise_scale = 0.667
        config.model.vits.noise_scale_w = 0.8
        config.model.vits.length_scale = 1.0
        config.model.num_threads = 4
        config.model.provider = UnsafePointer(provider)
        config.max_num_sentences = 1
        config.silence_scale = 0.2

        guard let tts = SherpaOnnxCreateOfflineTts(&config) else {
            throw PiperError.loadFailed(voiceDir.lastPathComponent)
        }
        self.tts = TTSHandle(pointer: tts)
        let sampleRate = Double(SherpaOnnxOfflineTtsSampleRate(tts))
        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1) else {
            SherpaOnnxDestroyOfflineTts(tts)
            throw PiperError.loadFailed(voiceDir.lastPathComponent)
        }
        self.format = format

        audioEngine.attach(player)
        audioEngine.attach(timePitch)
        audioEngine.connect(player, to: timePitch, format: format)
        audioEngine.connect(timePitch, to: audioEngine.mainMixerNode, format: format)
    }

    deinit {
        SherpaOnnxDestroyOfflineTts(tts.pointer)
    }

    func speak(_ text: String, prefetchNext next: String?, speed: Double, pitch: Double) {
        generation += 1
        let gen = generation
        awaitingPrefetch = nil
        player.stop()
        timePitch.rate = Float(speed)
        setPitch(pitch)

        if let cached = cache, cached.text == text {
            cache = nil
            play(cached.buffer, generation: gen)
            prefetch(next)
            return
        }
        if prefetching == text {
            awaitingPrefetch = (gen, next)
            return
        }

        synthQueue.async { [tts, format] in
            let buffer = Self.synthesize(tts: tts, format: format, text: text)
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard self.generation == gen else { return }
                    guard let buffer else { self.onFinish?(); return }
                    self.play(buffer, generation: gen)
                    self.prefetch(next)
                }
            }
        }
    }

    func pause() { player.pause() }
    func resume() { player.play() }

    func stop() {
        generation += 1
        awaitingPrefetch = nil
        cache = nil
        player.stop()
    }

    func setPitch(_ pitch: Double) {
        timePitch.pitch = Float(1200 * log2(max(pitch, 0.01)))
    }

    private func play(_ buffer: AVAudioPCMBuffer, generation gen: Int) {
        if !audioEngine.isRunning {
            do {
                try audioEngine.start()
            } catch {
                onFinish?()
                return
            }
        }
        player.scheduleBuffer(buffer, completionCallbackType: .dataPlayedBack) { [weak self] _ in
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self, self.generation == gen else { return }
                    self.onFinish?()
                }
            }
        }
        player.play()
    }

    private func prefetch(_ text: String?) {
        guard let text, prefetching == nil else { return }
        prefetching = text
        synthQueue.async { [tts, format] in
            let buffer = Self.synthesize(tts: tts, format: format, text: text)
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    self.prefetching = nil
                    if let waiting = self.awaitingPrefetch, waiting.generation == self.generation {
                        self.awaitingPrefetch = nil
                        guard let buffer else { self.onFinish?(); return }
                        self.play(buffer, generation: waiting.generation)
                        self.prefetch(waiting.next)
                    } else if let buffer {
                        self.cache = (text, buffer)
                    }
                }
            }
        }
    }

    private nonisolated static func synthesize(tts: TTSHandle, format: AVAudioFormat, text: String) -> AVAudioPCMBuffer? {
        var cfg = SherpaOnnxGenerationConfig()
        cfg.speed = 1.0
        cfg.silence_scale = 0.2
        cfg.sid = 0
        guard let audio = SherpaOnnxOfflineTtsGenerateWithConfig(tts.pointer, text, &cfg, nil, nil) else { return nil }
        defer { SherpaOnnxDestroyOfflineTtsGeneratedAudio(audio) }
        let count = Int(audio.pointee.n)
        guard count > 0, let samples = audio.pointee.samples,
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(count)),
              let channel = buffer.floatChannelData?[0]
        else { return nil }
        channel.update(from: samples, count: count)
        buffer.frameLength = AVAudioFrameCount(count)
        return buffer
    }
}
