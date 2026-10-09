import AppKit
import LasaCore
import PDFKit
import Vision

struct OCRLine: Sendable {
    /// UTF-16 range of this line in `PageText.raw`.
    let range: NSRange
    /// Line bounds in page space.
    let rect: CGRect
}

struct PageText: Sendable {
    let pageIndex: Int
    let raw: String
    let isOCR: Bool
    /// Empty for text pages.
    let ocrLines: [OCRLine]
}

/// Supplies each page's text: the PDF text layer when present, otherwise Vision OCR.
/// With a reading zone set, text outside it is blanked (see `ReadingZone.mask`).
@MainActor
final class PageTextProvider {
    private let document: PDFDocument
    private var cache: [Int: PageText] = [:]
    private var inflight: [Int: Task<PageText, Never>] = [:]
    /// Pages restricted to `zone`; cleared whenever the zone changes.
    private var zoned: [Int: PageText] = [:]

    /// Display-normalized reading zone relative to each page's crop box; nil reads whole pages.
    var zone: CGRect? {
        didSet { zoned.removeAll() }
    }

    init(document: PDFDocument) {
        self.document = document
    }

    func text(forPageAt index: Int) async -> PageText? {
        guard let full = await fullText(forPageAt: index) else { return nil }
        guard let zone, let page = document.page(at: index) else { return full }
        if let cached = zoned[index] { return cached }
        let rect = ReadingZone.pageRect(fromDisplay: zone, box: page.bounds(for: .cropBox), rotation: page.rotation)
        let restricted = full.restricted(to: rect, on: page)
        zoned[index] = restricted
        return restricted
    }

    private func fullText(forPageAt index: Int) async -> PageText? {
        if let cached = cache[index] { return cached }
        if let running = inflight[index] { return await running.value }
        guard let page = document.page(at: index) else { return nil }

        if let string = page.string, string.trimmingCharacters(in: .whitespacesAndNewlines).count >= 20 {
            let text = PageText(pageIndex: index, raw: string, isOCR: false, ocrLines: [])
            cache[index] = text
            return text
        }

        let mediaBox = page.bounds(for: .mediaBox)
        let rotation = page.rotation
        let scale: CGFloat = 2.5
        let image = page.thumbnail(of: NSSize(width: mediaBox.width * scale, height: mediaBox.height * scale), for: .mediaBox)
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            let empty = PageText(pageIndex: index, raw: "", isOCR: true, ocrLines: [])
            cache[index] = empty
            return empty
        }

        let task = Task.detached(priority: .userInitiated) {
            recognize(cgImage, pageIndex: index, mediaBox: mediaBox, rotation: rotation)
        }
        inflight[index] = task
        let result = await task.value
        inflight[index] = nil
        cache[index] = result
        return result
    }

    /// Starts loading a page in the background so it is ready when reading reaches it.
    func prefetch(_ index: Int) {
        guard index >= 0, index < document.pageCount, cache[index] == nil, inflight[index] == nil else { return }
        Task { _ = await self.fullText(forPageAt: index) }
    }
}

extension PageText {
    /// This page with every line whose center lies outside `rect` (page space) blanked out.
    @MainActor
    func restricted(to rect: CGRect, on page: PDFPage) -> PageText {
        func inside(_ r: CGRect) -> Bool { rect.contains(CGPoint(x: r.midX, y: r.midY)) }
        if isOCR {
            let kept = ocrLines.filter { inside($0.rect) }
            var keep = IndexSet()
            for line in kept { keep.insert(integersIn: line.range.location..<NSMaxRange(line.range)) }
            return PageText(pageIndex: pageIndex, raw: ReadingZone.mask(raw) { keep.contains($0) }, isOCR: true, ocrLines: kept)
        }
        // Line selections, like the highlighting, agree with `page.string` indices;
        // `characterBounds(at:)` drifts from them around line breaks.
        var drop = IndexSet()
        let lines = page.selection(for: NSRange(location: 0, length: (raw as NSString).length))?.selectionsByLine() ?? []
        for line in lines where !inside(line.bounds(for: page)) {
            for i in 0..<line.numberOfTextRanges(on: page) {
                let range = line.range(at: i, on: page)
                if range.location != NSNotFound { drop.insert(integersIn: range.location..<NSMaxRange(range)) }
            }
        }
        return PageText(pageIndex: pageIndex, raw: ReadingZone.mask(raw) { !drop.contains($0) }, isOCR: false, ocrLines: [])
    }
}

/// `rotation` is the page's clockwise /Rotate: the thumbnail, and so Vision's boxes, are in the
/// rotated orientation, which `ReadingZone.pageRect` maps back to page space.
private func recognize(_ image: CGImage, pageIndex: Int, mediaBox: CGRect, rotation: Int) -> PageText {
    let request = VNRecognizeTextRequest()
    request.recognitionLevel = .accurate
    request.usesLanguageCorrection = true
    if (try? request.supportedRecognitionLanguages())?.contains("sv-SE") == true {
        request.recognitionLanguages = ["sv-SE"]
    } else {
        request.automaticallyDetectsLanguage = true
    }

    do {
        try VNImageRequestHandler(cgImage: image).perform([request])
    } catch {
        return PageText(pageIndex: pageIndex, raw: "", isOCR: true, ocrLines: [])
    }

    let observations = (request.results ?? []).sorted { $0.boundingBox.midY > $1.boundingBox.midY }
    var raw = ""
    var lines: [OCRLine] = []
    for observation in observations {
        guard let candidate = observation.topCandidates(1).first?.string, !candidate.isEmpty else { continue }
        if !raw.isEmpty { raw += "\n" }
        let start = (raw as NSString).length
        raw += candidate
        let rect = ReadingZone.pageRect(fromDisplay: observation.boundingBox, box: mediaBox, rotation: rotation)
        lines.append(OCRLine(range: NSRange(location: start, length: (candidate as NSString).length), rect: rect))
    }
    return PageText(pageIndex: pageIndex, raw: raw, isOCR: true, ocrLines: lines)
}
