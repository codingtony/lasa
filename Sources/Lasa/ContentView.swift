import SwiftUI

struct ContentView: View {
    @Bindable var controller: ReaderController

    @AppStorage(SettingsKey.displayMode) private var displayMode = "continuous"
    @AppStorage(SettingsKey.fitMode) private var fitMode = "width"
    @AppStorage(SettingsKey.autoscrollSpeed) private var autoscrollSpeed = 40.0
    @AppStorage(SettingsKey.autoscrollOn) private var autoscrollOn = false
    @AppStorage(SettingsKey.followReading) private var followReading = true
    @AppStorage(SettingsKey.showInspector) private var showInspector = true
    @State private var pageInput = ""

    var body: some View {
        Group {
            if let document = controller.document {
                PDFKitView(
                    controller: controller,
                    document: document,
                    displayMode: displayMode,
                    fitMode: fitMode,
                    autoscrollSpeed: autoscrollSpeed,
                    followReading: followReading,
                    readingZone: controller.readingZone,
                    editingZone: controller.isEditingZone,
                    autoscrollOn: $autoscrollOn
                )
            } else {
                VStack(spacing: 12) {
                    Text("Open a PDF to start reading").foregroundStyle(.secondary)
                    Button("Open PDF…") { controller.showOpenPanel() }
                        .controlSize(.large)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(minWidth: 600, minHeight: 400)
        .dropDestination(for: URL.self) { urls, _ in
            guard let url = urls.first(where: { $0.pathExtension.lowercased() == "pdf" }) else { return false }
            controller.open(url)
            return true
        }
        .navigationTitle(controller.fileURL?.lastPathComponent ?? "Läsa")
        .toolbar { toolbar }
        .inspector(isPresented: $showInspector) {
            InspectorView(controller: controller)
                .inspectorColumnWidth(min: 260, ideal: 300, max: 400)
        }
        .alert(
            controller.alertMessage ?? "",
            isPresented: Binding(
                get: { controller.alertMessage != nil },
                set: { if !$0 { controller.alertMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        }
        .alert("Go to Page", isPresented: $controller.showGoToPage) {
            TextField("Page number", text: $pageInput)
            Button("Go") {
                if let number = Int(pageInput.trimmingCharacters(in: .whitespaces)) {
                    controller.goToPage(number - 1)
                }
                pageInput = ""
            }
            .keyboardShortcut(.defaultAction)
            Button("Cancel", role: .cancel) { pageInput = "" }
        } message: {
            Text("Enter a page number from 1 to \(controller.document?.pageCount ?? 0).")
        }
        .alert(
            "Resume where you left off?",
            isPresented: Binding(
                get: { controller.resumeOffer != nil },
                set: { if !$0 { controller.resumeOffer = nil } }
            ),
            presenting: controller.resumeOffer
        ) { page in
            Button("Resume at Page \(page + 1)") {
                // After the alert closes and the view has laid out the document.
                DispatchQueue.main.async { controller.goToPage(page) }
            }
            .keyboardShortcut(.defaultAction)
            Button("Start at Page 1", role: .cancel) {}
        } message: { page in
            Text("You were on page \(page + 1) of \(controller.document?.pageCount ?? 0) last time. You can change this question in the settings sidebar under Documents.")
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            Button { controller.showOpenPanel() } label: { Label("Open", systemImage: "folder") }
                .help("Open PDF (⌘O)")
        }
        ToolbarItem(placement: .navigation) {
            Button {
                controller.showGoToPage = true
            } label: {
                Group {
                    if let document = controller.document {
                        Text("Page \(controller.currentPageIndex + 1) of \(document.pageCount)")
                    } else {
                        Text("Page –")
                    }
                }
                .monospacedDigit()
            }
            .help("Go to page (⌥⌘G)")
            .disabled(controller.document == nil)
        }
        ToolbarItemGroup(placement: .principal) {
            Button { controller.previous() } label: { Label("Previous", systemImage: "backward.fill") }
                .help("Previous sentence (⌘←)")
                .disabled(!controller.isPlaying)
            Button { controller.togglePlayPause() } label: {
                Label(
                    LocalizedStringKey(controller.isPlaying && !controller.isPaused ? "Pause" : "Play"),
                    systemImage: controller.isPlaying && !controller.isPaused ? "pause.fill" : "play.fill"
                )
            }
            .help("Play / Pause (Space)")
            .disabled(controller.document == nil)
            Button { controller.stop() } label: { Label("Stop", systemImage: "stop.fill") }
                .help("Stop (⌘.)")
                .disabled(!controller.isPlaying)
            Button { controller.next() } label: { Label("Next", systemImage: "forward.fill") }
                .help("Next sentence (⌘→)")
                .disabled(!controller.isPlaying)
        }
        ToolbarItemGroup(placement: .primaryAction) {
            Toggle(isOn: $autoscrollOn) { Label("Auto-scroll", systemImage: "arrow.down.doc") }
                .help("Auto-scroll")
            Button { fitMode = "width" } label: { Label("Fit width", systemImage: "arrow.left.and.right") }
                .help("Fit width")
            Button { fitMode = "page" } label: { Label("Fit page", systemImage: "rectangle.portrait") }
                .help("Fit page")
            Button {
                fitMode = "manual"
                controller.pdfView?.zoomOut(nil)
            } label: { Label("Zoom out", systemImage: "minus.magnifyingglass") }
                .help("Zoom out")
            Button {
                fitMode = "manual"
                controller.pdfView?.zoomIn(nil)
            } label: { Label("Zoom in", systemImage: "plus.magnifyingglass") }
                .help("Zoom in")
            Button { showInspector.toggle() } label: { Label("Settings", systemImage: "sidebar.right") }
                .help("Show or hide reading settings")
        }
    }
}
