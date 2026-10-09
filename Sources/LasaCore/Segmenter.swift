import Foundation
import NaturalLanguage

/// One unit of speech: a sentence (or list item) from a page's text.
public struct Segment: Equatable, Sendable {
    /// UTF-16 range in the page's raw string covered by this segment.
    public let rawRange: NSRange
    /// Text sent to the speech engine (hyphenation joined, line breaks removed).
    public let spoken: String
    /// For each UTF-16 index in `spoken`, the UTF-16 index in the raw page string.
    public let spokenToRaw: [Int]
    /// True when a line/paragraph break follows this segment (list item, option, heading,
    /// paragraph end, page end) — a natural place for a longer pause.
    public let endsBlock: Bool

    public init(rawRange: NSRange, spoken: String, spokenToRaw: [Int], endsBlock: Bool) {
        self.rawRange = rawRange
        self.spoken = spoken
        self.spokenToRaw = spokenToRaw
        self.endsBlock = endsBlock
    }

    /// Maps a UTF-16 range in `spoken` to the covering raw range.
    public func rawRange(forSpoken range: NSRange) -> NSRange? {
        guard range.length > 0, range.location >= 0, NSMaxRange(range) <= spokenToRaw.count else { return nil }
        let start = spokenToRaw[range.location]
        let end = spokenToRaw[NSMaxRange(range) - 1] + 1
        return NSRange(location: start, length: max(0, end - start))
    }
}

/// Splits a page's raw text into speakable segments, starting at `startOffset` (UTF-16 index in `raw`).
public func segments(of raw: String, startingAt startOffset: Int = 0) -> [Segment] {
    let text = raw as NSString
    let lines = trimmedLines(of: text)
    guard !lines.isEmpty else { return [] }
    let maxLen = lines.map(\.length).max() ?? 0
    let lineLastChars = Set(lines.filter { $0.length > 0 }.map { NSMaxRange($0) - 1 })

    var result: [Segment] = []
    let tokenizer = NLTokenizer(unit: .sentence)
    tokenizer.setLanguage(.swedish)

    for block in blocks(of: lines, in: text, maxLen: maxLen) {
        let (units, map) = joinBlock(block, in: text)
        guard !units.isEmpty else { continue }
        let spoken = String(utf16CodeUnits: units, count: units.count)
        var sentences: [(range: NSRange, spoken: String, map: [Int])] = []
        tokenizer.string = spoken
        tokenizer.enumerateTokens(in: spoken.startIndex..<spoken.endIndex) { range, _ in
            var r = NSRange(range, in: spoken)
            while r.length > 0, isWhitespace(units[r.location]) { r.location += 1; r.length -= 1 }
            while r.length > 0, isWhitespace(units[NSMaxRange(r) - 1]) { r.length -= 1 }
            guard r.length > 0 else { return true }
            let slice = Array(units[r.location..<NSMaxRange(r)])
            let sliceMap = Array(map[r.location..<NSMaxRange(r)])
            let sentence = String(utf16CodeUnits: slice, count: slice.count)
            guard sentence.unicodeScalars.contains(where: { CharacterSet.alphanumerics.contains($0) }) else { return true }
            let start = sliceMap[0]
            let end = sliceMap[sliceMap.count - 1] + 1
            sentences.append((NSRange(location: start, length: end - start), sentence, sliceMap))
            return true
        }
        for (i, s) in sentences.enumerated() {
            let endsLine = lineLastChars.contains(s.map[s.map.count - 1])
            result.append(Segment(rawRange: s.range, spoken: s.spoken, spokenToRaw: s.map, endsBlock: endsLine || i == sentences.count - 1))
        }
    }

    guard startOffset > 0 else { return result }
    result.removeAll { NSMaxRange($0.rawRange) <= startOffset }
    guard let first = result.first else { return result }
    let units = Array(first.spoken.utf16)
    guard var idx = first.spokenToRaw.firstIndex(where: { $0 >= startOffset }), idx > 0 else { return result }
    while idx > 0, !isWhitespace(units[idx - 1]) { idx -= 1 }
    guard idx > 0 else { return result }
    let tail = Array(units[idx...])
    let tailMap = Array(first.spokenToRaw[idx...])
    let start = tailMap[0]
    let end = NSMaxRange(first.rawRange)
    result[0] = Segment(
        rawRange: NSRange(location: start, length: end - start),
        spoken: String(utf16CodeUnits: tail, count: tail.count),
        spokenToRaw: tailMap,
        endsBlock: first.endsBlock
    )
    return result
}

// MARK: - Internals

private let bulletChars: Set<unichar> = Set("•▪●–-*".utf16)

func isWhitespace(_ c: unichar) -> Bool {
    c == 0x20 || c == 0x09 || c == 0x0A || c == 0x0D || c == 0xA0 || c == 0x2028 || c == 0x2029
}

private func isNewline(_ c: unichar) -> Bool { c == 0x0A || c == 0x0D || c == 0x2028 || c == 0x2029 }

private func scalar(_ c: unichar) -> Unicode.Scalar? { Unicode.Scalar(c) }

private func isLowercaseLetter(_ c: unichar) -> Bool {
    guard let s = scalar(c) else { return false }
    return CharacterSet.lowercaseLetters.contains(s)
}

private func startsItem(_ c: unichar) -> Bool {
    if bulletChars.contains(c) { return true }
    guard let s = scalar(c) else { return false }
    return CharacterSet.uppercaseLetters.contains(s) || CharacterSet.decimalDigits.contains(s)
}

/// Each line's content range with surrounding whitespace removed (length 0 for blank lines).
private func trimmedLines(of text: NSString) -> [NSRange] {
    var lines: [NSRange] = []
    let n = text.length
    var lineStart = 0
    var i = 0
    func push(_ start: Int, _ end: Int) {
        var s = start, e = end
        while s < e, isWhitespace(text.character(at: s)) { s += 1 }
        while e > s, isWhitespace(text.character(at: e - 1)) { e -= 1 }
        lines.append(NSRange(location: s, length: e - s))
    }
    while i < n {
        let c = text.character(at: i)
        if isNewline(c) {
            push(lineStart, i)
            if c == 0x0D, i + 1 < n, text.character(at: i + 1) == 0x0A { i += 1 }
            lineStart = i + 1
        }
        i += 1
    }
    if lineStart < n { push(lineStart, n) }
    return lines
}

/// Groups consecutive non-blank lines into blocks, breaking at blank lines and hard line breaks.
private func blocks(of lines: [NSRange], in text: NSString, maxLen: Int) -> [[NSRange]] {
    var result: [[NSRange]] = []
    var current: [NSRange] = []
    for (i, line) in lines.enumerated() {
        guard line.length > 0 else {
            if !current.isEmpty { result.append(current); current = [] }
            continue
        }
        current.append(line)
        guard i + 1 < lines.count else { continue }
        let next = lines[i + 1]
        guard next.length > 0 else { continue }
        let lastChar = text.character(at: NSMaxRange(line) - 1)
        let endsWithHyphen = lastChar == 0x2D
        let endsWithColon = lastChar == 0x3A  // "Välj ett alternativ:" introduces a list
        let isShort = Double(line.length) < 0.6 * Double(maxLen)
        if endsWithColon || (!endsWithHyphen && isShort && startsItem(text.character(at: next.location))) {
            result.append(current)
            current = []
        }
    }
    if !current.isEmpty { result.append(current) }
    return result
}

/// Joins a block's lines into spoken UTF-16 units plus a spoken→raw index map.
private func joinBlock(_ block: [NSRange], in text: NSString) -> ([unichar], [Int]) {
    var units: [unichar] = []
    var map: [Int] = []
    func append(_ c: unichar, _ rawIndex: Int) {
        let ws = isWhitespace(c)
        if ws, units.last.map(isWhitespace) ?? true { return }
        units.append(ws ? 0x20 : c)
        map.append(rawIndex)
    }
    for (j, line) in block.enumerated() {
        for k in line.location..<NSMaxRange(line) { append(text.character(at: k), k) }
        guard j + 1 < block.count else { continue }
        let next = block[j + 1]
        let last = text.character(at: NSMaxRange(line) - 1)
        if last == 0x2D, isLowercaseLetter(text.character(at: next.location)), units.last == 0x2D {
            units.removeLast()
            map.removeLast()
        } else {
            append(0x20, NSMaxRange(line))
        }
    }
    return (units, map)
}
