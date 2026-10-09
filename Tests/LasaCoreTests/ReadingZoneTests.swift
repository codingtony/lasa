import CoreGraphics
import Foundation
import Testing
@testable import LasaCore

private let box = CGRect(x: 10, y: 20, width: 600, height: 800)

/// The top tenth of the page as shown.
private let topBand = CGRect(x: 0, y: 0.9, width: 1, height: 0.1)

private func close(_ a: CGRect, _ b: CGRect) -> Bool {
    abs(a.minX - b.minX) < 1e-6 && abs(a.minY - b.minY) < 1e-6 && abs(a.width - b.width) < 1e-6 && abs(a.height - b.height) < 1e-6
}

@Test func topBandOnUnrotatedPageIsTopOfPageSpace() {
    #expect(close(ReadingZone.pageRect(fromDisplay: topBand, box: box, rotation: 0), CGRect(x: 10, y: 740, width: 600, height: 80)))
}

/// /Rotate is clockwise: what is shown at the top of a page rotated 90° is its left edge in page space.
@Test func topBandFollowsClockwiseRotation() {
    #expect(close(ReadingZone.pageRect(fromDisplay: topBand, box: box, rotation: 90), CGRect(x: 10, y: 20, width: 60, height: 800)))
    #expect(close(ReadingZone.pageRect(fromDisplay: topBand, box: box, rotation: 180), CGRect(x: 10, y: 20, width: 600, height: 80)))
    #expect(close(ReadingZone.pageRect(fromDisplay: topBand, box: box, rotation: 270), CGRect(x: 550, y: 20, width: 60, height: 800)))
    #expect(close(ReadingZone.pageRect(fromDisplay: topBand, box: box, rotation: -90), CGRect(x: 550, y: 20, width: 60, height: 800)))
}

@Test func displayPointInvertsPageRect() {
    let zone = CGRect(x: 0.1, y: 0.2, width: 0.5, height: 0.3)
    for rotation in [0, 90, 180, 270] {
        let rect = ReadingZone.pageRect(fromDisplay: zone, box: box, rotation: rotation)
        let a = ReadingZone.displayPoint(fromPage: CGPoint(x: rect.minX, y: rect.minY), box: box, rotation: rotation)
        let b = ReadingZone.displayPoint(fromPage: CGPoint(x: rect.maxX, y: rect.maxY), box: box, rotation: rotation)
        let back = CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(a.x - b.x), height: abs(a.y - b.y))
        #expect(close(back, zone), "rotation \(rotation)")
    }
}

@Test func maskedHeaderAndPageNumberAreNotSpokenAndRangesStayValid() {
    let raw = "Kapitel 3 Farmakologi\nLäkemedlet tas upp i tarmen.\n12"
    let ns = raw as NSString
    let body = ns.range(of: "Läkemedlet tas upp i tarmen.")
    let masked = ReadingZone.mask(raw) { NSLocationInRange($0, body) }
    #expect((masked as NSString).length == ns.length)
    let segs = segments(of: masked)
    #expect(segs.map(\.spoken) == ["Läkemedlet tas upp i tarmen."])
    #expect(segs.first?.rawRange == body)
}
