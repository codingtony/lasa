import AVFoundation
import SwiftUI

struct InspectorView: View {
    let controller: ReaderController

    @AppStorage(SettingsKey.voiceID) private var voiceID = ""
    @AppStorage(SettingsKey.speed) private var speed = 1.0
    @AppStorage(SettingsKey.pitch) private var pitch = 1.0
    @AppStorage(SettingsKey.linePause) private var linePause = 0.8
    @AppStorage(SettingsKey.followReading) private var followReading = true
    @AppStorage(SettingsKey.autoscrollSpeed) private var autoscrollSpeed = 40.0
    @AppStorage(SettingsKey.displayMode) private var displayMode = "continuous"
    @AppStorage(SettingsKey.resumeMode) private var resumeMode = ResumeMode.ask
    @State private var language = Settings.languageOverride

    @State private var piperVoices: [VoiceOption] = []
    @State private var appleVoices: [VoiceOption] = []

    var body: some View {
        Form {
            Section("Voice") {
                Picker("Voice", selection: $voiceID) {
                    if !piperVoices.isEmpty {
                        Section("Piper (neural)") {
                            ForEach(piperVoices) { Text($0.label).tag($0.id.string) }
                        }
                    }
                    if !appleVoices.isEmpty {
                        Section("Apple") {
                            ForEach(appleVoices) { Text($0.label).tag($0.id.string) }
                        }
                    }
                    if let missing = missingSavedVoice {
                        Text(missing.label).tag(missing.id.string)
                    }
                }
                Button("Test voice") { controller.testVoice() }
                Button("Get more Apple voices…") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.universalaccess?SpokenContent") {
                        NSWorkspace.shared.open(url)
                    }
                }
                Text("In System Settings, click ⓘ next to System Voice, select Swedish, then click the download button next to an Enhanced or Premium voice.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Speech") {
                LabeledContent("Speed") {
                    HStack {
                        Slider(value: $speed, in: Settings.speedRange, step: 0.05)
                        Text(String(format: "%.2f×", speed)).monospacedDigit().frame(width: 48, alignment: .trailing)
                    }
                }
                LabeledContent("Pitch") {
                    HStack {
                        Slider(value: $pitch, in: Settings.pitchRange, step: 0.05)
                        Text(String(format: "%.2f×", pitch)).monospacedDigit().frame(width: 48, alignment: .trailing)
                    }
                }
                LabeledContent("Pause between lines") {
                    HStack {
                        Slider(value: $linePause, in: Settings.linePauseRange, step: 0.1)
                        Text(String(format: "%.1f s", linePause)).monospacedDigit().frame(width: 48, alignment: .trailing)
                    }
                }
                Toggle("Follow reading", isOn: $followReading)
            }

            Section("Reading zone") {
                if controller.isEditingZone {
                    Text("Drag a rectangle around the text to read on any page. Text outside it (headers, footers, page numbers) is skipped on every page of this PDF.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button("Done") { controller.isEditingZone = false }
                } else {
                    Button(LocalizedStringKey(controller.readingZone == nil ? "Set reading zone…" : "Change reading zone…")) {
                        controller.isEditingZone = true
                    }
                    .disabled(controller.document == nil)
                }
                if controller.readingZone != nil {
                    Button("Read whole pages") { controller.setReadingZone(nil) }
                }
            }

            Section("View") {
                Picker("Pages", selection: $displayMode) {
                    Text("Continuous").tag("continuous")
                    Text("Single page").tag("single")
                    Text("Two pages").tag("twoUp")
                }
                LabeledContent("Auto-scroll speed") {
                    HStack {
                        Slider(value: $autoscrollSpeed, in: Settings.autoscrollRange)
                        Text("\(Int(autoscrollSpeed))").monospacedDigit().frame(width: 48, alignment: .trailing)
                    }
                }
            }

            Section("Documents") {
                Picker("When reopening a PDF", selection: $resumeMode) {
                    Text("Ask to resume").tag(ResumeMode.ask)
                    Text("Resume at last page").tag(ResumeMode.always)
                    Text("Start at page 1").tag(ResumeMode.never)
                }
            }

            Section("Language") {
                Picker("Interface language", selection: $language) {
                    Text("Automatic (system)").tag("")
                    Text(verbatim: "English").tag("en")
                    Text(verbatim: "Svenska").tag("sv")
                }
                if language != Settings.languageAtLaunch {
                    Text("Läsa must restart to change language.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if Bundle.main.bundleURL.pathExtension == "app" {
                        Button("Restart Now", action: relaunch)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .onAppear(perform: reloadVoices)
        .onReceive(NotificationCenter.default.publisher(for: AVSpeechSynthesizer.availableVoicesDidChangeNotification)) { _ in
            reloadVoices()
        }
        .onChange(of: voiceID) { oldVoice, newVoice in
            // Speed/pitch on screen belong to the previous voice; store them, then load the new voice's.
            Settings.saveVoiceSettings(speed: speed, pitch: pitch, for: oldVoice)
            let stored = Settings.voiceSettings(for: newVoice)
            speed = stored.speed
            pitch = stored.pitch
            controller.voiceChanged()
        }
        .onChange(of: pitch) { controller.pitchChanged() }
        .onChange(of: language) { Settings.languageOverride = language }
    }

    /// Starts a fresh copy of the app (which picks up the new language), then quits this one.
    private func relaunch() {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration) { _, error in
            guard error == nil else { return }
            DispatchQueue.main.async { NSApp.terminate(nil) }
        }
    }

    private func reloadVoices() {
        piperVoices = VoiceCatalog.piperVoices()
        appleVoices = VoiceCatalog.appleVoices()
        // Only pick a default when nothing was ever chosen. A saved voice that is missing from the
        // list right now (e.g. system voices still loading at launch) must not be overwritten.
        if voiceID.isEmpty, let resolved = VoiceCatalog.resolve(voiceID)?.string {
            voiceID = resolved
        }
    }

    /// Keeps the picker showing the saved voice even if it is not (yet) in the installed lists.
    private var missingSavedVoice: VoiceOption? {
        guard let id = VoiceID(string: voiceID),
              !(piperVoices + appleVoices).contains(where: { $0.id == id })
        else { return nil }
        return VoiceOption(id: id, label: String(localized: "\(VoiceCatalog.label(for: id)) (unavailable)"))
    }
}
