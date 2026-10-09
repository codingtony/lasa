import PDFKit

/// In-memory reading highlight: fills its bounds with a translucent color.
final class HighlightAnnotation: PDFAnnotation {
    private let fill: NSColor

    init(bounds: CGRect, fill: NSColor) {
        self.fill = fill
        super.init(bounds: bounds, forType: .square, withProperties: nil)
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func draw(with box: PDFDisplayBox, in context: CGContext) {
        context.saveGState()
        context.setBlendMode(.multiply)
        context.setFillColor(fill.cgColor)
        context.fill(bounds)
        context.restoreGState()
    }
}
