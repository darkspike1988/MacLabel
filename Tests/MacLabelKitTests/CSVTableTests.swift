import Testing
@testable import MacLabelKit

@Test func germanExcelCSV() throws {
    let t = try CSVTable(parsing: "\u{FEFF}Name;Ort\r\n\"Müller; Hans\";Köln\r\n\r\nSchmidt;\"Bad \"\"Neu\"\"\"\r\n")
    #expect(t.headers == ["Name", "Ort"])
    #expect(t.rows.count == 2)
    #expect(t.rows[0]["Name"] == "Müller; Hans")
    #expect(t.rows[1]["Ort"] == "Bad \"Neu\"")
}
@Test func commaCSV() throws { #expect(try CSVTable(parsing: "a,b\n1,2\n").rows[0]["b"] == "2") }
@Test func tabCSV() throws { #expect(try CSVTable(parsing: "a\tb\n1\t2").rows[0]["b"] == "2") }
@Test func unterminatedQuote() {
    #expect(throws: CSVError.unterminatedQuote(line: 2)) { try CSVTable(parsing: "a\n\"x\n") }
}
@Test func noHeader() {
    #expect(throws: CSVError.noHeader) { try CSVTable(parsing: "") }
    #expect(throws: CSVError.noHeader) { try CSVTable(parsing: "\r\n\n") }
}
@Test func shortAndLongRows() throws {
    let t = try CSVTable(parsing: " a ;b\n1\n1;2;3\n")
    #expect(t.headers == ["a", "b"])
    #expect(t.rows[0]["b"] == "")
    #expect(t.rows[1] == ["a": "1", "b": "2"])
}
@Test func duplicateHeaderLaterWins() throws {
    #expect(try CSVTable(parsing: "a;a\n1;2\n").rows[0]["a"] == "2")
}
@Test func quotedNewlineAndDelimiterInFirstLine() throws {
    let t = try CSVTable(parsing: "\"a;b\",c\n\"x\ny\",z\n")
    #expect(t.headers == ["a;b", "c"])
    #expect(t.rows[0]["a;b"] == "x\ny")
}
@Test func quotedEmptyRowKept() throws {
    #expect(try CSVTable(parsing: "a\n\"\"\n").rows.count == 1)
}
