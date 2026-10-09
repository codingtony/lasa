import Foundation

/// UserDefaults keys shared by `@AppStorage` views and the controller.
enum SettingsKey {
    static let voiceID = "voiceID"
    static let speed = "speed"
    static let pitch = "pitch"
    static let linePause = "linePause"
    static let autoscrollSpeed = "autoscrollSpeed"
    static let autoscrollOn = "autoscrollOn"
    static let followReading = "followReading"
    static let displayMode = "displayMode"
    static let fitMode = "fitMode"
    static let showInspector = "showInspector"
    static let lastFilePath = "lastFilePath"
    static let lastPages = "lastPages"
    static let voiceSettings = "voiceSettings"
    static let resumeMode = "resumeMode"
    static let readingZones = "readingZones"
}

/// What to do when a PDF with a saved page is opened again.
enum ResumeMode {
    static let ask = "ask"
    static let always = "always"
    static let never = "never"
}

enum Settings {
    static let speedRange: ClosedRange<Double> = 0.5...2.0
    static let pitchRange: ClosedRange<Double> = 0.5...2.0
    static let autoscrollRange: ClosedRange<Double> = 5...300
    static let linePauseRange: ClosedRange<Double> = 0...3
    /// Pause between sentences inside a paragraph, as a fraction of the line pause.
    static let sentencePauseFraction = 0.35

    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            SettingsKey.voiceID: "",
            SettingsKey.speed: 1.0,
            SettingsKey.pitch: 1.0,
            SettingsKey.linePause: 0.8,
            SettingsKey.autoscrollSpeed: 40.0,
            SettingsKey.autoscrollOn: false,
            SettingsKey.followReading: true,
            SettingsKey.displayMode: "continuous",
            SettingsKey.fitMode: "width",
            SettingsKey.showInspector: true,
            SettingsKey.lastFilePath: "",
            SettingsKey.resumeMode: ResumeMode.ask,
        ])
        // Capture the language the UI was loaded in before the settings can change it.
        _ = languageAtLaunch
    }

    /// Interface language chosen in the app: "" follows the system (Swedish on a Swedish Mac),
    /// otherwise "en" or "sv". Stored as `AppleLanguages` in the app's own defaults domain, the
    /// standard per-app override that macOS reads at launch, so a change applies after a restart.
    static var languageOverride: String {
        get {
            let domain = defaults.persistentDomain(forName: Bundle.main.bundleIdentifier ?? ProcessInfo.processInfo.processName)
            guard let first = (domain?["AppleLanguages"] as? [String])?.first else { return "" }
            return first.hasPrefix("sv") ? "sv" : "en"
        }
        set {
            if newValue.isEmpty {
                defaults.removeObject(forKey: "AppleLanguages")
            } else {
                defaults.set([newValue], forKey: "AppleLanguages")
            }
        }
    }

    /// `languageOverride` when the app started, i.e. the language the UI is showing.
    static let languageAtLaunch = languageOverride

    private static var defaults: UserDefaults { .standard }

    static var voiceID: String {
        get { defaults.string(forKey: SettingsKey.voiceID) ?? "" }
        set { defaults.set(newValue, forKey: SettingsKey.voiceID) }
    }
    static var speed: Double { defaults.double(forKey: SettingsKey.speed) }
    static var pitch: Double { defaults.double(forKey: SettingsKey.pitch) }
    static var linePause: Double { defaults.double(forKey: SettingsKey.linePause) }
    static var followReading: Bool { defaults.bool(forKey: SettingsKey.followReading) }
    static var resumeMode: String { defaults.string(forKey: SettingsKey.resumeMode) ?? ResumeMode.ask }

    static var lastFilePath: String {
        get { defaults.string(forKey: SettingsKey.lastFilePath) ?? "" }
        set { defaults.set(newValue, forKey: SettingsKey.lastFilePath) }
    }

    static func lastPage(for path: String) -> Int? {
        (defaults.dictionary(forKey: SettingsKey.lastPages) as? [String: Int])?[path]
    }

    static func setLastPage(_ page: Int, for path: String) {
        var pages = (defaults.dictionary(forKey: SettingsKey.lastPages) as? [String: Int]) ?? [:]
        pages[path] = page
        defaults.set(pages, forKey: SettingsKey.lastPages)
    }

    /// Display-normalized reading zone (`ReadingZone`) remembered for each PDF path.
    static func readingZone(for path: String) -> CGRect? {
        guard let v = (defaults.dictionary(forKey: SettingsKey.readingZones) as? [String: [Double]])?[path], v.count == 4 else { return nil }
        return CGRect(x: v[0], y: v[1], width: v[2], height: v[3])
    }

    static func setReadingZone(_ zone: CGRect?, for path: String) {
        var zones = (defaults.dictionary(forKey: SettingsKey.readingZones) as? [String: [Double]]) ?? [:]
        zones[path] = zone.map { [$0.minX, $0.minY, $0.width, $0.height] }
        defaults.set(zones, forKey: SettingsKey.readingZones)
    }

    /// Speed and pitch remembered for each voice (`VoiceID.string`), so every voice keeps its own.
    static func voiceSettings(for voiceID: String) -> (speed: Double, pitch: Double) {
        let all = defaults.dictionary(forKey: SettingsKey.voiceSettings) as? [String: [String: Double]]
        let stored = all?[voiceID]
        return (stored?["speed"] ?? 1.0, stored?["pitch"] ?? 1.0)
    }

    static func saveVoiceSettings(speed: Double, pitch: Double, for voiceID: String) {
        guard !voiceID.isEmpty else { return }
        var all = (defaults.dictionary(forKey: SettingsKey.voiceSettings) as? [String: [String: Double]]) ?? [:]
        all[voiceID] = ["speed": speed, "pitch": pitch]
        defaults.set(all, forKey: SettingsKey.voiceSettings)
    }
}
