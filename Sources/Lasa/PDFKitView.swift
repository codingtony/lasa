import LasaCore
import PDFKit
import SwiftUI

/// PDFView with click-to-jump, a "Read from here" context menu item, and reading-zone drawing.
final class ReaderPDFView: PDFView {
    weak var controller: ReaderController?
    private var mouseDownMonitor: Any?
    private var mouseUpMonitor: Any?
    private let zoneOverlay = ReadingZoneOverlay()
    private var zoneEditing = false
    /// Page and display-normalized start point of the zone being dragged.
    private var zoneDrag: (page: PDFPage, start: CGPoint)?
    private var zoneObservers: [NSObjectProtocol] = []

    // PDFKit's internal page views receive mouse events and run their own tracking loop for
    // text selection, so neither mouseDown overrides nor gesture recognizers see a plain click.
    // A local monitor always sees the initial mouse-down; the click is judged once the button is up.
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let mouseDownMonitor { NSEvent.removeMonitor(mouseDownMonitor) }
        mouseDownMonitor = nil
        guard window != nil else { return }
        mouseDownMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .leftMouseDragged, .leftMouseUp]) { [weak self] event in
            guard let self else { return event }
            if self.handleZoneEdit(event) { return nil }
            if event.type == .leftMouseDown { self.mouseDownSeen(event) }
            return event
        }
    }

    /// Shows the reading zone over every visible page while `editing`; drags then draw a new zone.
    func showZoneEditor(_ editing: Bool, zone: CGRect?) {
        if zoneDrag == nil { zoneOverlay.zone = zone }
        guard editing != zoneEditing else { return }
        zoneEditing = editing
        zoneDrag = nil
        zoneObservers.forEach(NotificationCenter.default.removeObserver)
        zoneObservers = []
        guard editing else {
            zoneOverlay.removeFromSuperview()
            return
        }
        zoneOverlay.pdfView = self
        zoneOverlay.frame = bounds
        zoneOverlay.autoresizingMask = [.width, .height]
        addSubview(zoneOverlay, positioned: .above, relativeTo: nil)
        // The overlay is not part of the scrolled content: redraw whenever the pages move.
        var sources: [(Notification.Name, AnyObject)] = [(.PDFViewScaleChanged, self), (.PDFViewDisplayModeChanged, self)]
        if let clip = documentView?.enclosingScrollView?.contentView {
            clip.postsBoundsChangedNotifications = true
            sources.append((NSView.boundsDidChangeNotification, clip))
        }
        zoneObservers = sources.map { name, object in
            NotificationCenter.default.addObserver(forName: name, object: object, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.zoneOverlay.needsDisplay = true }
            }
        }
    }

    /// While editing the zone, a drag on a page draws it. Returns true when the event was used.
    private func handleZoneEdit(_ event: NSEvent) -> Bool {
        guard zoneEditing, event.window === window else { return false }
        let point = convert(event.locationInWindow, from: nil)
        switch event.type {
        case .leftMouseDown:
            guard bounds.contains(point), let superview, !(hitTest(convert(point, to: superview)) is NSScroller),
                  let page = page(for: point, nearest: true)
            else { return false }
            zoneDrag = (page, displayPoint(point, on: page))
            return true
        case .leftMouseDragged, .leftMouseUp:
            guard let drag = zoneDrag else { return false }
            let end = displayPoint(point, on: drag.page)
            let rect = CGRect(
                x: min(drag.start.x, end.x), y: min(drag.start.y, end.y),
                width: abs(end.x - drag.start.x), height: abs(end.y - drag.start.y)
            )
            zoneOverlay.zone = rect
            if event.type == .leftMouseUp {
                zoneDrag = nil
                if rect.width > 0.02, rect.height > 0.02 {
                    MainActor.assumeIsolated { controller?.setReadingZone(rect) }
                } else {
                    // A plain click keeps the current zone.
                    zoneOverlay.zone = MainActor.assumeIsolated { controller?.readingZone }
                }
            }
            return true
        default:
            return false
        }
    }

    /// `point` (view space) as a display-normalized position on `page`, clamped to the page.
    private func displayPoint(_ point: CGPoint, on page: PDFPage) -> CGPoint {
        let p = ReadingZone.displayPoint(fromPage: convert(point, to: page), box: page.bounds(for: .cropBox), rotation: page.rotation)
        return CGPoint(x: min(max(p.x, 0), 1), y: min(max(p.y, 0), 1))
    }

    private func mouseDownSeen(_ event: NSEvent) {
        guard event.window === window, event.clickCount == 1 else { return }
        let point = convert(event.locationInWindow, from: nil)
        guard bounds.contains(point), let page = page(for: point, nearest: false) else { return }
        let pagePoint = convert(point, to: page)
        if let annotation = page.annotation(at: pagePoint), annotation.type == "Link" { return }
        let downOnScreen = NSEvent.mouseLocation
        // Runs after PDFKit has handled the press (and its drag loop, if any).
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if NSEvent.pressedMouseButtons & 1 == 0 {
                self.finishClick(page: page, pagePoint: pagePoint, downOnScreen: downOnScreen)
            } else {
                self.mouseUpMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseUp) { [weak self] up in
                    guard let self else { return up }
                    if let monitor = self.mouseUpMonitor { NSEvent.removeMonitor(monitor) }
                    self.mouseUpMonitor = nil
                    DispatchQueue.main.async {
                        self.finishClick(page: page, pagePoint: pagePoint, downOnScreen: downOnScreen)
                    }
                    return up
                }
            }
        }
    }

    /// A press that ended where it started without selecting text moves reading there.
    private func finishClick(page: PDFPage, pagePoint: CGPoint, downOnScreen: CGPoint) {
        let up = NSEvent.mouseLocation
        guard hypot(up.x - downOnScreen.x, up.y - downOnScreen.y) < 4 else { return }
        if let selection = currentSelection?.string, !selection.isEmpty { return }
        MainActor.assumeIsolated { controller?.wordClicked(page: page, point: pagePoint) }
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = super.menu(for: event) ?? NSMenu()
        let point = convert(event.locationInWindow, from: nil)
        guard let page = page(for: point, nearest: true) else { return menu }
        let pagePoint = convert(point, to: page)
        let item = NSMenuItem(title: String(localized: "Read from here"), action: #selector(readFromHere(_:)), keyEquivalent: "")
        item.target = self
        item.representedObject = ReadTarget(page: page, point: pagePoint)
        menu.insertItem(item, at: 0)
        menu.insertItem(.separator(), at: 1)
        return menu
    }

    @objc private func readFromHere(_ sender: NSMenuItem) {
        guard let target = sender.representedObject as? ReadTarget else { return }
        MainActor.assumeIsolated { controller?.readFrom(page: target.page, point: target.point) }
    }

    private final class ReadTarget: NSObject {
        let page: PDFPage
        let point: CGPoint
        init(page: PDFPage, point: CGPoint) {
            self.page = page
            self.point = point
        }
    }
}

/// Dims everything outside the reading zone on each visible page. Never takes mouse events.
private final class ReadingZoneOverlay: NSView {
    weak var pdfView: PDFView?
    var zone: CGRect? {
        didSet { needsDisplay = true }
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draw(_ dirtyRect: NSRect) {
        guard let pdfView, let zone else { return }
        for page in pdfView.visiblePages {
            let box = page.bounds(for: .cropBox)
            let pageRect = convert(pdfView.convert(box, from: page), from: pdfView)
            let zonePageRect = ReadingZone.pageRect(fromDisplay: zone, box: box, rotation: page.rotation)
            let zoneRect = convert(pdfView.convert(zonePageRect, from: page), from: pdfView)
            let shade = NSBezierPath(rect: pageRect)
            shade.append(NSBezierPath(rect: zoneRect))
            shade.windingRule = .evenOdd
            NSColor.black.withAlphaComponent(0.35).setFill()
            shade.fill()
            let border = NSBezierPath(rect: zoneRect)
            border.lineWidth = 2
            NSColor.controlAccentColor.setStroke()
            border.stroke()
        }
    }
}

struct PDFKitView: NSViewRepresentable {
    let controller: ReaderController
    let document: PDFDocument
    let displayMode: String
    let fitMode: String
    let autoscrollSpeed: Double
    let followReading: Bool
    let readingZone: CGRect?
    let editingZone: Bool
    @Binding var autoscrollOn: Bool

    func makeCoordinator() -> Coordinator { Coordinator(controller: controller) }

    func makeNSView(context: Context) -> ReaderPDFView {
        let view = ReaderPDFView()
        view.controller = controller
        view.displaysPageBreaks = true
        view.postsFrameChangedNotifications = true
        context.coordinator.attach(view)
        controller.pdfView = view
        return view
    }

    func updateNSView(_ view: ReaderPDFView, context: Context) {
        let coordinator = context.coordinator
        coordinator.parent = self
        if view.document !== document {
            view.document = document
            // The scroll view can keep the previous document's offset, so always pick the page.
            let index = controller.takePendingPage() ?? 0
            if let page = document.page(at: index) {
                // Wait for layout and fit scaling, otherwise the jump is lost.
                DispatchQueue.main.async { view.go(to: page) }
            }
        }
        let mode: PDFDisplayMode = switch displayMode {
        case "single": .singlePage
        case "twoUp": .twoUpContinuous
        default: .singlePageContinuous
        }
        if view.displayMode != mode { view.displayMode = mode }
        coordinator.applyFit()
        coordinator.setAutoscroll(on: autoscrollOn, speed: autoscrollSpeed)
        view.showZoneEditor(editingZone, zone: readingZone)
    }

    static func dismantleNSView(_ view: ReaderPDFView, coordinator: Coordinator) {
        coordinator.setAutoscroll(on: false, speed: 0)
    }

    @MainActor
    final class Coordinator: NSObject {
        let controller: ReaderController
        var parent: PDFKitView?
        private weak var view: PDFView?
        private var timer: Timer?
        private var speed: Double = 0

        init(controller: ReaderController) {
            self.controller = controller
        }

        func attach(_ view: PDFView) {
            self.view = view
            let center = NotificationCenter.default
            center.addObserver(self, selector: #selector(pageChanged), name: .PDFViewPageChanged, object: view)
            center.addObserver(self, selector: #selector(frameChanged), name: NSView.frameDidChangeNotification, object: view)
        }

        @objc private func pageChanged() {
            guard let view, let page = view.currentPage, let doc = view.document else { return }
            let index = doc.index(for: page)
            controller.currentPageIndex = index
            if let path = controller.fileURL?.path { Settings.setLastPage(index, for: path) }
        }

        @objc private func frameChanged() {
            applyFit()
        }

        func applyFit() {
            guard let view, let parent else { return }
            switch parent.fitMode {
            case "width":
                if !view.autoScales { view.autoScales = true }
            case "page":
                view.autoScales = false
                guard let page = view.currentPage ?? view.document?.page(at: 0) else { return }
                let pageBox = page.bounds(for: view.displayBox)
                let pageWidth = pageBox.width * (view.displayMode == .twoUpContinuous ? 2 : 1)
                guard pageWidth > 0, pageBox.height > 0, view.bounds.width > 0, view.bounds.height > 0 else { return }
                let scale = min(view.bounds.width / pageWidth, view.bounds.height / pageBox.height) * 0.97
                if abs(view.scaleFactor - scale) > 0.001 { view.scaleFactor = scale }
            default:
                if view.autoScales { view.autoScales = false }
            }
        }

        func setAutoscroll(on: Bool, speed: Double) {
            self.speed = speed
            if on, timer == nil {
                timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
                    MainActor.assumeIsolated { self?.tick() }
                }
            } else if !on {
                timer?.invalidate()
                timer = nil
            }
        }

        private func tick() {
            guard let view, let parent, let documentView = view.documentView,
                  let scrollView = documentView.enclosingScrollView
            else { return }
            // While reading with follow on, the reader moves the view instead.
            if controller.isPlaying, !controller.isPaused, parent.followReading { return }

            let clip = scrollView.contentView
            let delta = speed / 60.0 / max(scrollView.magnification, 0.01)
            var origin = clip.bounds.origin
            let atEnd: Bool
            if documentView.isFlipped {
                let maxY = documentView.frame.height - clip.bounds.height
                origin.y = min(origin.y + delta, maxY)
                atEnd = origin.y >= maxY - 0.5
            } else {
                origin.y = max(origin.y - delta, documentView.frame.minY)
                atEnd = origin.y <= documentView.frame.minY + 0.5
            }
            clip.scroll(to: origin)
            scrollView.reflectScrolledClipView(clip)
            if atEnd { parent.autoscrollOn = false }
        }
    }
}
