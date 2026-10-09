import AVFoundation

enum VoiceID: Hashable {
    case apple(String)
    case piper(String)

    init?(string: String) {
        if string.hasPrefix("apple:") {
            self = .apple(String(string.dropFirst("apple:".count)))
        } else if string.hasPrefix("piper:") {
            self = .piper(String(string.dropFirst("piper:".count)))
        } else {
            return nil
        }
    }

    var string: String {
        switch self {
        case .apple(let id): "apple:\(id)"
        case .piper(let folder): "piper:\(folder)"
        }
    }
}

struct VoiceOption: Identifiable, Hashable {
    let id: VoiceID
    let label: String
}

/// Swedish voices: bundled Piper models plus installed Apple system voices.
enum VoiceCatalog {
    /// Used when no voice was ever chosen: Lisa, the female Piper voice.
    static let defaultPiperFolder = "vits-piper-sv_SE-lisa-medium"

    /// `LASA_PIPER_DIR` (dev runs) or `<App>.app/Contents/Resources/piper`.
    static var piperRoot: URL? {
        if let override = ProcessInfo.processInfo.environment["LASA_PIPER_DIR"], !override.isEmpty {
            return URL(fileURLWithPath: override, isDirectory: true)
        }
        return Bundle.main.resourceURL?.appendingPathComponent("piper", isDirectory: true)
    }

    static func piperDirectory(for folder: String) -> URL? {
        piperRoot?.appendingPathComponent(folder, isDirectory: true)
    }

    static func piperVoices() -> [VoiceOption] {
        guard let root = piperRoot,
              let dirs = try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
        else { return [] }
        let fm = FileManager.default
        return dirs
            .filter { dir in
                let files = (try? fm.contentsOfDirectory(atPath: dir.path)) ?? []
                return files.contains { $0.hasSuffix(".onnx") }
                    && files.contains("tokens.txt")
                    && files.contains("espeak-ng-data")
            }
            .map(\.lastPathComponent)
            .sorted()
            .map { VoiceOption(id: .piper($0), label: piperLabel(for: $0)) }
    }

    static func appleVoices() -> [VoiceOption] {
        AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language.hasPrefix("sv") }
            .sorted { ($0.name, $0.quality.rawValue) < ($1.name, $1.quality.rawValue) }
            .map { VoiceOption(id: .apple($0.identifier), label: "\($0.name) (\(qualityLabel($0.quality)))") }
    }

    static func label(for id: VoiceID) -> String {
        switch id {
        case .piper(let folder): return piperLabel(for: folder)
        case .apple(let identifier): return AVSpeechSynthesisVoice(identifier: identifier)?.name ?? identifier
        }
    }

    /// The saved voice if still available, else the default Piper voice, any Piper voice, then any Apple voice.
    static func resolve(_ saved: String) -> VoiceID? {
        let piper = piperVoices().map(\.id)
        let apple = appleVoices().map(\.id)
        if let id = VoiceID(string: saved), piper.contains(id) || apple.contains(id) { return id }
        if piper.contains(.piper(defaultPiperFolder)) { return .piper(defaultPiperFolder) }
        return piper.first ?? apple.first
    }

    /// `vits-piper-sv_SE-alma-medium` → `Alma (Piper)`.
    private static func piperLabel(for folder: String) -> String {
        let parts = folder.split(separator: "-")
        let name = parts.count > 3 ? String(parts[3]) : folder
        let display = name.count <= 3 ? name.uppercased() : name.prefix(1).uppercased() + name.dropFirst()
        return "\(display) (Piper)"
    }

    private static func qualityLabel(_ quality: AVSpeechSynthesisVoiceQuality) -> String {
        switch quality {
        case .premium: String(localized: "Premium")
        case .enhanced: String(localized: "Enhanced")
        default: String(localized: "Standard")
        }
    }
}
