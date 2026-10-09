import Foundation
import Testing
@testable import LasaCore

/// A multiple-choice page as returned by PDFKit: running header, section, question, options,
/// score and page number.
private let multipleChoicePage = """
20260924 Farmakologi A
2 Kinetik A
Hur förändras farmakokinetiken om fraktionen av läkemedlet som är bundet i plasma minskar?
Välj ett alternativ:
fa ökar, eftersom mer är tillgängligt för absorption.
Vd ökar, eftersom mer fördelas till vävnad.
CL R
minskar, eftersom mindre är tillgängligt för filtration.
Ingen parameter ändras, eftersom bara fraktionen obunden är viktig.
F minskar, eftersom första-passage effekten blir svagare.
Totalpoäng: 1
2/37
"""

private let unpunctuatedOptions = """
Vilket av följande läkemedel är en protonpumpshämmare som används vid magsår och reflux?
Välj ett alternativ:
Omeprazol
Ranitidin
Ibuprofen
Paracetamol
"""

@Test func joinsHyphenatedLineBreak() {
    let raw = "Läke-\nmedel är bra."
    let segs = segments(of: raw)
    #expect(segs.map(\.spoken) == ["Läkemedel är bra."])
    #expect(segs[0].rawRange == NSRange(location: 0, length: (raw as NSString).length))
}

@Test func joinsSoftWrappedProseEvenBeforeUppercase() {
    let raw = "Läkemedlet metaboliseras i levern av enzymet\nCYP3A4 och utsöndras via njurarna."
    #expect(segments(of: raw).map(\.spoken) == ["Läkemedlet metaboliseras i levern av enzymet CYP3A4 och utsöndras via njurarna."])
}

@Test func shortLinesBeforeCapitalizedLinesAreSeparateItems() {
    #expect(segments(of: unpunctuatedOptions).map(\.spoken) == [
        "Vilket av följande läkemedel är en protonpumpshämmare som används vid magsår och reflux?",
        "Välj ett alternativ:",
        "Omeprazol", "Ranitidin", "Ibuprofen", "Paracetamol",
    ])
}

@Test func lineBreaksMarkLongPausesButSentencesInAParagraphDoNot() {
    let raw = "Läkemedlet tas upp i tarmen. Det metaboliseras i levern av enzymet CYP3A4.\nVälj ett alternativ:\nOmeprazol\nRanitidin"
    let segs = segments(of: raw)
    #expect(segs.map(\.spoken) == [
        "Läkemedlet tas upp i tarmen.", "Det metaboliseras i levern av enzymet CYP3A4.",
        "Välj ett alternativ:", "Omeprazol", "Ranitidin",
    ])
    #expect(segs.map(\.endsBlock) == [false, true, true, true, true])
}

@Test func multipleChoicePageKeepsQuestionAndOptionsApart() {
    let spoken = segments(of: multipleChoicePage).map(\.spoken)
    #expect(spoken.contains("Hur förändras farmakokinetiken om fraktionen av läkemedlet som är bundet i plasma minskar?"))
    #expect(spoken.contains("Vd ökar, eftersom mer fördelas till vävnad."))
    #expect(spoken.contains("CL R minskar, eftersom mindre är tillgängligt för filtration."))
    #expect(spoken.contains("Ingen parameter ändras, eftersom bara fraktionen obunden är viktig."))
    #expect(spoken.contains("Totalpoäng: 1"))
    #expect(spoken.contains("Välj ett alternativ:"))
    #expect(spoken.contains("fa ökar, eftersom mer är tillgängligt för absorption."))
    #expect(segments(of: multipleChoicePage).map(\.endsBlock).allSatisfy { $0 })
}

@Test func startOffsetInsideWordStartsAtThatWord() {
    let offset = (multipleChoicePage as NSString).range(of: "farmakokinetiken").location + 4
    let segs = segments(of: multipleChoicePage, startingAt: offset)
    #expect(segs.first?.spoken.hasPrefix("farmakokinetiken om fraktionen") == true)
    #expect(segs.first?.rawRange.location == offset - 4)
}

@Test func rawRangesCoverFirstAndLastSpokenWords() {
    for raw in [multipleChoicePage, unpunctuatedOptions] {
        for seg in segments(of: raw) {
            let covered = (raw as NSString).substring(with: seg.rawRange)
            let words = seg.spoken.split(separator: " ")
            #expect(covered.hasPrefix(String(words.first!)), "\(covered)")
            #expect(covered.hasSuffix(String(words.last!)), "\(covered)")
            #expect(seg.spokenToRaw.count == seg.spoken.utf16.count)
        }
    }
}
