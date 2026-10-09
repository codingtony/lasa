import AppKit
import SwiftUI

@main
struct LasaApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    private let controller = ReaderController.shared

    init() {
        Settings.registerDefaults()
    }

    var body: some Scene {
        Window("Läsa", id: "main") {
            ContentView(controller: controller)
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Open…") { controller.showOpenPanel() }
                    .keyboardShortcut("o")
            }
            CommandMenu("Playback") {
                Button(LocalizedStringKey(controller.isPlaying && !controller.isPaused ? "Pause" : "Play")) { controller.togglePlayPause() }
                    .keyboardShortcut(.space, modifiers: [])
                    .disabled(controller.document == nil)
                Button("Stop") { controller.stop() }
                    .keyboardShortcut(".")
                Divider()
                Button("Next Sentence") { controller.next() }
                    .keyboardShortcut(.rightArrow)
                Button("Previous Sentence") { controller.previous() }
                    .keyboardShortcut(.leftArrow)
            }
            CommandMenu("Go") {
                Button("Go to Page…") { controller.showGoToPage = true }
                    .keyboardShortcut("g", modifiers: [.command, .option])
                    .disabled(controller.document == nil)
            }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
        MainActor.assumeIsolated { ReaderController.shared.restoreLastDocument() }
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        guard let url = urls.first else { return }
        MainActor.assumeIsolated { ReaderController.shared.open(url) }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}
