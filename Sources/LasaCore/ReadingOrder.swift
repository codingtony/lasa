import CoreGraphics

/// Reading order of OCR line boxes on a page that may have several columns.
///
/// Recursive XY-cut: each region is split at its widest empty gap, vertical (columns, read left
/// then right) or horizontal (bands, read top then bottom). A gutter is usually wider than the
/// space between lines, so columns are split before accidental full-width row gaps; a wider gap
/// above a footer or around a full-width figure is split first. Columns win ties. A region with no
/// gap of at least half the median line height is read top to bottom.
public enum ReadingOrder {
    /// Indices of `boxes` in reading order. Boxes are line rects in a y-up space
    /// (origin bottom-left) with the same unit on both axes.
    public static func order(_ boxes: [CGRect]) -> [Int] {
        guard !boxes.isEmpty else { return [] }
        let minGap = 0.5 * boxes.map(\.height).sorted()[boxes.count / 2]

        func cut(_ idx: [Int]) -> [Int] {
            guard idx.count > 1 else { return idx }
            let v = widestGap(idx, boxes, low: \.minX, high: \.maxX)
            let h = widestGap(idx, boxes, low: \.minY, high: \.maxY)
            if v.size >= minGap && v.size >= h.size {
                return cut(idx.filter { boxes[$0].minX < v.at }) + cut(idx.filter { boxes[$0].minX >= v.at })
            }
            if h.size >= minGap {
                return cut(idx.filter { boxes[$0].minY >= h.at }) + cut(idx.filter { boxes[$0].minY < h.at })
            }
            return idx.sorted {
                let a = boxes[$0], b = boxes[$1]
                return a.midY != b.midY ? a.midY > b.midY : a.minX < b.minX
            }
        }
        return cut(Array(boxes.indices))
    }

    /// Widest empty gap along one axis among `idx`: its size and the low edge of the box after it.
    /// Both are 0 when no gap is positive.
    private static func widestGap(
        _ idx: [Int], _ boxes: [CGRect], low: (CGRect) -> CGFloat, high: (CGRect) -> CGFloat
    ) -> (size: CGFloat, at: CGFloat) {
        let sorted = idx.sorted { low(boxes[$0]) < low(boxes[$1]) }
        var best: (size: CGFloat, at: CGFloat) = (0, 0)
        var reach = high(boxes[sorted[0]])
        for i in sorted.dropFirst() {
            let gap = low(boxes[i]) - reach
            if gap > best.size { best = (gap, low(boxes[i])) }
            reach = max(reach, high(boxes[i]))
        }
        return best
    }
}
