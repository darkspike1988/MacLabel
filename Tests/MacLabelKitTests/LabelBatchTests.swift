import Testing
import LabelRender
@testable import MacLabelKit

private func texts(_ out: [LabelContent]) -> [String] {
    out.compactMap { if case .text(let t) = $0 { t.text } else { nil } }
}

@Test func counterPadding() throws {
    let out = try LabelBatch.expand(.text(.init(text: "Box {n}")), copies: 3, counter: .init(start: 8, step: 1, minimumDigits: 2), table: nil)
    #expect(texts(out) == ["Box 08", "Box 09", "Box 10"])
}
@Test func csvPlaceholdersCaseInsensitive() throws {
    let t = try CSVTable(parsing: "Name;Ort\nA;X\nB;Y\n")
    let out = try LabelBatch.expand(.text(.init(text: "{name} – {ORT}")), copies: 2, counter: nil, table: t)
    #expect(texts(out) == ["A – X", "A – X", "B – Y", "B – Y"])
}
@Test func unknownPlaceholder() {
    #expect(throws: BatchError.unknownPlaceholder("plz")) {
        try LabelBatch.expand(.text(.init(text: "{plz}")), copies: 1, counter: nil, table: try CSVTable(parsing: "Name\nA\n"))
    }
}
@Test func counterPlaceholderWithoutCounterIsUnknown() {
    #expect(throws: BatchError.unknownPlaceholder("n")) {
        try LabelBatch.expand(.text(.init(text: "{n}")), copies: 1, counter: nil, table: nil)
    }
}
@Test func columnNamedNUsedWithoutCounter() throws {
    let t = try CSVTable(parsing: "n\nA\n")
    #expect(texts(try LabelBatch.expand(.text(.init(text: "{n}")), copies: 1, counter: nil, table: t)) == ["A"])
    #expect(texts(try LabelBatch.expand(.text(.init(text: "{n}")), copies: 1, counter: .init(), table: t)) == ["1"])
}
@Test func zeroCopies() {
    #expect(throws: BatchError.invalidCopies) { try LabelBatch.expand(.text(.init(text: "x")), copies: 0, counter: nil, table: nil) }
}
@Test func literalBraces() throws {
    let out = try LabelBatch.expand(.text(.init(text: "{{x}} {n}")), copies: 1, counter: .init(), table: nil)
    #expect(texts(out) == ["{x} 1"])
}
@Test func counterRunsAcrossCsvRows() throws {
    let t = try CSVTable(parsing: "a\nX\nY\n")
    let out = try LabelBatch.expand(.text(.init(text: "{a}{n}")), copies: 2, counter: .init(), table: t)
    #expect(texts(out) == ["X1", "X2", "Y3", "Y4"])
}
@Test func replacesBarcodeAndQR() throws {
    let bc = try LabelBatch.expand(.barcode(.init(symbology: .code128, value: "A{n}")), copies: 1, counter: .init(), table: nil)
    if case .barcode(let b) = bc[0] { #expect(b.value == "A1") } else { Issue.record("not barcode") }
    let qr = try LabelBatch.expand(.qr(.init(payload: "u/{n}", caption: "c{n}")), copies: 1, counter: .init(start: 5), table: nil)
    if case .qr(let q) = qr[0] { #expect(q.payload == "u/5"); #expect(q.caption == "c5") } else { Issue.record("not qr") }
}

@Test func unknownPlaceholderNameIsTrimmed() {
    #expect(throws: BatchError.unknownPlaceholder("plz")) {
        try LabelBatch.expand(.text(.init(text: "{ plz }")), copies: 1, counter: nil, table: nil)
    }
}
