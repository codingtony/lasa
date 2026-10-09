import AppKit
import LasaCore
import Observation
import PDFKit
import UniformTypeIdentifiers

/// Owns the open document and drives reading: page text → segments → speech engine → highlights.
@MainActor
@Observable
final class ReaderController {
    static let shared = ReaderController()

    private(set) var document: PDFDocument?
    private(set) var fileURL: URL?
    /// True from Play until Stop or end of document, including while paused.
    private(set) var isPlaying = false
    private(set) var isPaused = false
    var alertMessage: String?
    /// Page shown in the view (0-based), for the toolbar page indicator.
    var currentPageIndex = 0
    var showGoToPage = false
    /// Saved page (0-based) offered when reopening a document in "ask" resume mode.
    var resumeOffer: Int?
    /// Part of every page that is read (display-normalized, see `ReadingZone`); nil reads whole pages.
    private(set) var readingZone: CGRect?
    /// True while the reading zone is being drawn on the page.
    var isEditingZone = false
    /// Page to show as soon as the view has loaded the document ("always" resume mode).
    @ObservationIgnored private var pendingPageIndex: Int?

    @ObservationIgnored weak var pdfView: PDFView?
    @ObservationIgnored private var provider: PageTextProvider?
    @ObservationIgnored private var engine: (any SpeechEngine)?
    @ObservationIgnored private var engineVoice: VoiceID?
    @ObservationIgnored private var cursor: Cursor?
    @ObservationIgnored private var sentenceHighlights: [(PDFPage, PDFAnnotation)] = []
    @ObservationIgnored private var wordHighlight: (PDFPage, PDFAnnotation)?
    /// Bumped whenever reading restarts or stops so in-flight page loads can tell they are stale.
    @ObservationIgnored private var runID = 0
    /// The pause after a finished segment; cancelled by any navigation.
    @ObservationIgnored private var pendingAdvance: DispatchWorkItem?
    /// The pause ended while the user had paused; continue on resume.
    @ObservationIgnored private var advanceOnResume = false
    /// Where the user last clicked while not reading; used by the next Play.
    @ObservationIgnored private var clickedStart: (pageIndex: Int, offset: Int)?

    private struct Cursor {
        let pageIndex: Int
        let pageText: PageText
        let segments: [Segment]
        var position: Int
    }

    // MARK: - Documents

    func showOpenPanel() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.pdf]
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url { open(url) }
    }

    func open(_ url: URL) {
        guard let doc = PDFDocument(url: url) else {
            alertMessage = String(localized: "Could not open \(url.lastPathComponent)")
            return
        }
        if doc.isLocked {
            alertMessage = String(localized: "This PDF is password-protected.")
            return
        }
        stop()
        // Read the saved page before the view loads the document: loading reports page 1,
        // which overwrites the saved value.
        let saved = Settings.lastPage(for: url.path).flatMap { $0 > 0 && $0 < doc.pageCount ? $0 : nil }
        provider = PageTextProvider(document: doc)
        readingZone = Settings.readingZone(for: url.path)
        provider?.zone = readingZone
        isEditingZone = false
        clickedStart = nil
        currentPageIndex = 0
        pendingPageIndex = nil
        resumeOffer = nil
        switch Settings.resumeMode {
        case ResumeMode.always: pendingPageIndex = saved
        case ResumeMode.ask: resumeOffer = saved
        default: break
        }
        fileURL = url
        document = doc
        Settings.lastFilePath = url.path
    }

    /// Shows page `index` (0-based, clamped to the document).
    func goToPage(_ index: Int) {
        guard let doc = document, doc.pageCount > 0, let pdfView else { return }
        guard let page = doc.page(at: min(max(index, 0), doc.pageCount - 1)) else { return }
        pdfView.go(to: page)
    }

    /// Called by the view once it has loaded the document.
    func takePendingPage() -> Int? {
        defer { pendingPageIndex = nil }
        return pendingPageIndex
    }

    /// Reopens the last document at launch, unless a file was already opened from Finder.
    func restoreLastDocument() {
        guard document == nil else { return }
        let path = Settings.lastFilePath
        guard !path.isEmpty else { return }
        if FileManager.default.fileExists(atPath: path) {
            open(URL(fileURLWithPath: path))
        } else {
            Settings.lastFilePath = ""
        }
    }

    /// Sets (or with nil, removes) the reading zone of the open document and remembers it.
    func setReadingZone(_ zone: CGRect?) {
        readingZone = zone
        provider?.zone = zone
        if let path = fileURL?.path { Settings.setReadingZone(zone, for: path) }
    }

    // MARK: - Playback

    func togglePlayPause() {
        if !isPlaying {
            play()
        } else if isPaused {
            isPaused = false
            if advanceOnResume {
                advanceOnResume = false
                advance()
            } else {
                engine?.resume()
            }
        } else {
            engine?.pause()
            isPaused = true
        }
    }

    /// Starts at the selection, else at the last clicked word, else at the top of the visible page.
    func play() {
        guard let doc = document, let pdfView else { return }
        let clicked = clickedStart
        clickedStart = nil
        if let selection = pdfView.currentSelection, let page = selection.pages.first {
            let range = selection.range(at: 0, on: page)
            start(pageIndex: doc.index(for: page), offset: range.location == NSNotFound ? 0 : range.location)
        } else if let clicked {
            start(pageIndex: clicked.pageIndex, offset: clicked.offset)
        } else if let page = pdfView.currentPage {
            start(pageIndex: doc.index(for: page), offset: 0)
        }
    }

    /// Context menu "Read from here": `point` is in page space.
    func readFrom(page: PDFPage, point: CGPoint) {
        guard let doc = document else { return }
        let index = doc.index(for: page)
        Task {
            guard let offset = await textOffset(on: page, at: index, point: point, requireHit: false) else { return }
            start(pageIndex: index, offset: offset)
        }
    }

    /// A single click on text: jump there while reading, otherwise start there on the next Play.
    func wordClicked(page: PDFPage, point: CGPoint) {
        guard let doc = document else { return }
        let index = doc.index(for: page)
        Task {
            guard let offset = await textOffset(on: page, at: index, point: point, requireHit: true) else { return }
            if isPlaying {
                start(pageIndex: index, offset: offset)
            } else {
                clickedStart = (index, offset)
            }
        }
    }

    /// UTF-16 offset in the page text at `point` (page space). With `requireHit`, clicks
    /// outside any text return nil; otherwise they fall back to the nearest following line.
    private func textOffset(on page: PDFPage, at index: Int, point: CGPoint, requireHit: Bool) async -> Int? {
        guard let provider, let text = await provider.text(forPageAt: index) else { return nil }
        if !text.isOCR {
            // characterIndex(at:) snaps to a nearby character (often the previous word or line),
            // so take the word under the point and require that the point is actually on it.
            if let word = page.selectionForWord(at: point),
               word.bounds(for: page).insetBy(dx: -2, dy: -2).contains(point) {
                let range = word.range(at: 0, on: page)
                if range.location != NSNotFound {
                    // A word starts with a space only when the reading zone blanked it out.
                    let raw = text.raw as NSString
                    let blanked = range.location < raw.length && raw.character(at: range.location) == 0x20
                    return blanked && requireHit ? nil : range.location
                }
            }
            return requireHit ? nil : max(page.characterIndex(at: point), 0)
        }
        if let line = text.ocrLines.first(where: { $0.rect.insetBy(dx: -2, dy: -2).contains(point) }) {
            // OCR gives line boxes only: estimate the character from the horizontal position.
            let fraction = min(max((point.x - line.rect.minX) / max(line.rect.width, 1), 0), 1)
            return line.range.location + min(Int(fraction * CGFloat(line.range.length)), max(line.range.length - 1, 0))
        }
        if requireHit { return nil }
        return text.ocrLines.first(where: { $0.rect.midY <= point.y })?.range.location ?? 0
    }

    func stop() {
        runID += 1
        cancelPendingAdvance()
        engine?.stop()
        cursor = nil
        isPlaying = false
        isPaused = false
        clearHighlights()
    }

    func next() {
        guard isPlaying, cursor != nil else { return }
        advance()
    }

    func previous() {
        guard isPlaying, var current = cursor else { return }
        current.position = max(0, current.position - 1)
        cursor = current
        isPaused = false
        speakCurrent()
    }

    /// Restarts the current sentence with the newly selected voice.
    func voiceChanged() {
        guard isPlaying, !isPaused, cursor != nil else { return }
        speakCurrent()
    }

    func pitchChanged() {
        engine?.setPitch(Settings.pitch)
    }

    func testVoice() {
        stop()
        ensureEngine()?.speak(
            "Hej! Det här är en testmening om läkemedel och farmakokinetik.",
            prefetchNext: nil, speed: Settings.speed, pitch: Settings.pitch
        )
    }

    // MARK: - Reading loop

    private func start(pageIndex: Int, offset: Int) {
        runID += 1
        cancelPendingAdvance()
        let run = runID
        engine?.stop()
        clearHighlights()
        cursor = nil
        isPlaying = true
        isPaused = false
        Task { await self.load(pageIndex: pageIndex, offset: offset, run: run) }
    }

    private func load(pageIndex: Int, offset: Int, run: Int) async {
        var index = pageIndex
        var startOffset = offset
        while let doc = document, let provider, index < doc.pageCount {
            guard let text = await provider.text(forPageAt: index), run == runID else { return }
            provider.prefetch(index + 1)
            let segments = LasaCore.segments(of: text.raw, startingAt: startOffset)
            if !segments.isEmpty {
                cursor = Cursor(pageIndex: index, pageText: text, segments: segments, position: 0)
                speakCurrent()
                return
            }
            index += 1
            startOffset = 0
        }
        if run == runID { stop() }
    }

    /// Waits the configured pause (longer at line/paragraph breaks), then moves on.
    private func segmentFinished() {
        guard let current = cursor else { return }
        let segment = current.segments[current.position]
        let fraction = segment.endsBlock ? 1 : Settings.sentencePauseFraction
        let delay = Settings.linePause * fraction / max(Settings.speed, 0.1)
        let run = runID
        let item = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.runID == run else { return }
                self.pendingAdvance = nil
                if self.isPaused {
                    self.advanceOnResume = true
                } else {
                    self.advance()
                }
            }
        }
        pendingAdvance = item
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
    }

    private func cancelPendingAdvance() {
        pendingAdvance?.cancel()
        pendingAdvance = nil
        advanceOnResume = false
    }

    private func advance() {
        guard var current = cursor else { return }
        if current.position + 1 < current.segments.count {
            current.position += 1
            cursor = current
            isPaused = false
            speakCurrent()
        } else {
            start(pageIndex: current.pageIndex + 1, offset: 0)
        }
    }

    private func speakCurrent() {
        guard let current = cursor else { return }
        cancelPendingAdvance()
        let segment = current.segments[current.position]
        let next = current.position + 1 < current.segments.count ? current.segments[current.position + 1].spoken : nil
        highlight(segment, in: current)
        guard let engine = ensureEngine() else {
            stop()
            return
        }
        engine.speak(segment.spoken, prefetchNext: next, speed: Settings.speed, pitch: Settings.pitch)
    }

    /// Returns the engine for the selected voice, creating it (and retiring the old one) on change.
    private func ensureEngine() -> (any SpeechEngine)? {
        guard let voice = VoiceCatalog.resolve(Settings.voiceID) else {
            alertMessage = String(localized: "No Swedish voice is available.")
            return nil
        }
        if voice == engineVoice, let engine { return engine }
        engine?.stop()
        engine = nil
        engineVoice = nil

        let created: any SpeechEngine
        switch voice {
        case .apple(let identifier):
            created = AppleSpeechEngine(identifier: identifier)
        case .piper(let folder):
            if let dir = VoiceCatalog.piperDirectory(for: folder), let piper = try? PiperSpeechEngine(voiceDir: dir) {
                created = piper
            } else {
                alertMessage = String(localized: "Could not load voice \(VoiceCatalog.label(for: voice))")
                guard let fallback = VoiceCatalog.appleVoices().first?.id, case .apple(let identifier) = fallback else { return nil }
                Settings.voiceID = fallback.string
                created = AppleSpeechEngine(identifier: identifier)
                engineVoice = fallback
                return install(created)
            }
        }
        engineVoice = voice
        return install(created)
    }

    private func install(_ created: any SpeechEngine) -> any SpeechEngine {
        created.onFinish = { [weak self] in self?.segmentFinished() }
        created.onWord = { [weak self] range in self?.highlightWord(range) }
        engine = created
        return created
    }

    // MARK: - Highlighting

    private func highlight(_ segment: Segment, in current: Cursor) {
        clearHighlights()
        guard let page = document?.page(at: current.pageIndex) else { return }
        let rects: [CGRect]
        if current.pageText.isOCR {
            rects = current.pageText.ocrLines
                .filter { NSIntersectionRange($0.range, segment.rawRange).length > 0 }
                .map(\.rect)
        } else {
            rects = page.selection(for: segment.rawRange)?.selectionsByLine().map { $0.bounds(for: page) } ?? []
        }
        for rect in rects where !rect.isEmpty {
            let annotation = HighlightAnnotation(bounds: rect.insetBy(dx: -1, dy: -1), fill: NSColor.systemYellow.withAlphaComponent(0.35))
            page.addAnnotation(annotation)
            sentenceHighlights.append((page, annotation))
        }
        follow(rects.first, on: page)
    }

    private func highlightWord(_ spokenRange: NSRange) {
        removeWordHighlight()
        guard let current = cursor, !current.pageText.isOCR,
              let page = document?.page(at: current.pageIndex),
              let rawRange = current.segments[current.position].rawRange(forSpoken: spokenRange),
              let selection = page.selection(for: rawRange)
        else { return }
        let rect = selection.bounds(for: page)
        guard !rect.isEmpty else { return }
        let annotation = HighlightAnnotation(bounds: rect.insetBy(dx: -1, dy: -1), fill: NSColor.systemOrange.withAlphaComponent(0.45))
        page.addAnnotation(annotation)
        wordHighlight = (page, annotation)
    }

    private func follow(_ rect: CGRect?, on page: PDFPage) {
        guard Settings.followReading, let rect, let pdfView else { return }
        let visible = pdfView.convert(pdfView.bounds, to: page)
        // Scroll when the line is outside the middle 70% of the view, and keep context around it.
        guard !visible.insetBy(dx: 0, dy: visible.height * 0.15).contains(rect) else { return }
        pdfView.go(to: rect.insetBy(dx: 0, dy: -visible.height * 0.3), on: page)
    }

    private func removeWordHighlight() {
        if let (page, annotation) = wordHighlight { page.removeAnnotation(annotation) }
        wordHighlight = nil
    }

    private func clearHighlights() {
        removeWordHighlight()
        for (page, annotation) in sentenceHighlights { page.removeAnnotation(annotation) }
        sentenceHighlights = []
    }
}
