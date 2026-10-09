import Foundation

/// Speaks one segment at a time. Callbacks are delivered on the main actor.
@MainActor
protocol SpeechEngine: AnyObject {
    /// Range in the spoken string about to be spoken (word granularity). Apple voices only.
    var onWord: ((NSRange) -> Void)? { get set }
    /// The segment finished playing naturally. Not called after `stop()` or a newer `speak`.
    var onFinish: (() -> Void)? { get set }

    /// Speaks `text`, replacing anything currently playing. `next` may be prepared in advance.
    func speak(_ text: String, prefetchNext next: String?, speed: Double, pitch: Double)
    func pause()
    func resume()
    func stop()
    /// Applies immediately where the engine supports it, otherwise from the next segment.
    func setPitch(_ pitch: Double)
}
