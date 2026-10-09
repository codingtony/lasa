import CoreGraphics
import Testing
@testable import LasaCore

// Synthetic line boxes on a ~600×800 page, y-up. Lines are 24 high, 20 apart, so consecutive
// lines overlap a little, like Vision's boxes.

private func line(x: CGFloat, top: CGFloat, w: CGFloat, h: CGFloat = 24) -> CGRect {
    CGRect(x: x, y: top - h, width: w, height: h)
}

private func column(x: CGFloat, top: CGFloat, count: Int = 5) -> [CGRect] {
    (0..<count).map { line(x: x, top: top - CGFloat($0) * 20, w: 230) }
}

/// Sorting by midY alone would interleave the columns: left 1, right 1, left 2, ...
@Test func staggeredColumnsAreReadColumnByColumnThenFooter() {
    let left = column(x: 50, top: 700)
    let right = column(x: 310, top: 690)
    let footer = line(x: 50, top: 60, w: 20, h: 20)
    #expect(ReadingOrder.order(left + right + [footer]) == Array(0..<11))
}

@Test func fullWidthTitleIsReadBeforeColumns() {
    let title = line(x: 50, top: 760, w: 490)
    let left = column(x: 50, top: 700)
    let right = column(x: 310, top: 700)
    // Shuffle the input so the order comes from geometry, not input order.
    let boxes = right + [title] + left
    let expected = [5] + Array(6..<11) + Array(0..<5)
    #expect(ReadingOrder.order(boxes) == expected)
}

@Test func figureLabelsCrossingTheGutterAreReadAfterColumns() {
    let left = column(x: 50, top: 700)
    let right = column(x: 310, top: 700)
    // 60 below the lowest column line; B spans the gutter.
    let a = line(x: 50, top: 536, w: 100, h: 20)
    let b = line(x: 250, top: 536, w: 150, h: 20)
    let boxes = [b, a] + right + left
    let expected = Array(7..<12) + Array(2..<7) + [1, 0]
    #expect(ReadingOrder.order(boxes) == expected)
}

@Test func shortLastLineDoesNotSplitSingleColumn() {
    var boxes = (0..<4).map { line(x: 50, top: 700 - CGFloat($0) * 20, w: 490) }
    boxes.append(line(x: 50, top: 620, w: 100))
    #expect(ReadingOrder.order(boxes.reversed()) == [4, 3, 2, 1, 0])
}

@Test func emptyInputHasEmptyOrder() {
    #expect(ReadingOrder.order([]) == [])
}
