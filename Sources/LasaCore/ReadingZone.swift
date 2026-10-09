import CoreGraphics
import Foundation

/// The part of every page that is read aloud.
///
/// A zone is a rect in display-normalized coordinates: 0...1 on both axes relative to a page box,
/// origin at the bottom-left of the page as shown, i.e. after the page's clockwise rotation.
/// That way the same zone covers the same visible area on rotated and unrotated pages.
public enum ReadingZone {
    /// Page-space rect covered by the display-normalized `rect` on a page with `box` and `rotation`.
    public static func pageRect(fromDisplay rect: CGRect, box: CGRect, rotation: Int) -> CGRect {
        let a = pageNormalized(fromDisplay: CGPoint(x: rect.minX, y: rect.minY), rotation: rotation)
        let b = pageNormalized(fromDisplay: CGPoint(x: rect.maxX, y: rect.maxY), rotation: rotation)
        return CGRect(
            x: box.minX + min(a.x, b.x) * box.width,
            y: box.minY + min(a.y, b.y) * box.height,
            width: abs(a.x - b.x) * box.width,
            height: abs(a.y - b.y) * box.height
        )
    }

    /// Display-normalized position of the page-space `point` on a page with `box` and `rotation`.
    public static func displayPoint(fromPage point: CGPoint, box: CGRect, rotation: Int) -> CGPoint {
        let x = (point.x - box.minX) / max(box.width, 1)
        let y = (point.y - box.minY) / max(box.height, 1)
        switch normalized(rotation) {
        case 90: return CGPoint(x: y, y: 1 - x)
        case 180: return CGPoint(x: 1 - x, y: 1 - y)
        case 270: return CGPoint(x: 1 - y, y: x)
        default: return CGPoint(x: x, y: y)
        }
    }

    /// `raw` with every non-whitespace UTF-16 unit at an index where `keep` is false replaced by a
    /// space. Indices are unchanged, so ranges into the original page text stay valid.
    public static func mask(_ raw: String, keep: (Int) -> Bool) -> String {
        var units = Array(raw.utf16)
        var changed = false
        for i in units.indices where !isWhitespace(units[i]) && !keep(i) {
            units[i] = 0x20
            changed = true
        }
        return changed ? String(decoding: units, as: UTF16.self) : raw
    }

    private static func pageNormalized(fromDisplay p: CGPoint, rotation: Int) -> CGPoint {
        switch normalized(rotation) {
        case 90: return CGPoint(x: 1 - p.y, y: p.x)
        case 180: return CGPoint(x: 1 - p.x, y: 1 - p.y)
        case 270: return CGPoint(x: p.y, y: 1 - p.x)
        default: return p
        }
    }

    private static func normalized(_ rotation: Int) -> Int { (rotation % 360 + 360) % 360 }
}
