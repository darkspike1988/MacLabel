/// Modulo-103 checksum over start code value + weighted symbol values.
/// `values[0]` is the start code (weight 1), `values[i]` has weight i.
public func code128Checksum(_ values: [Int]) -> Int {
    guard let first = values.first else { return 0 }
    var sum = first
    for (i, v) in values.enumerated().dropFirst() { sum += v * i }
    return sum % 103
}

enum Code128 {
    private static let startB = 104, startC = 105, codeB = 100, codeC = 99, stop = 106

    // Bar/space widths per symbol value 0...106 (ISO/IEC 15417).
    private static let patterns: [String] = [
        "212222", "222122", "222221", "121223", "121322", "131222", "122213", "122312", "132212", "221213",
        "221312", "231212", "112232", "122132", "122231", "113222", "123122", "123221", "223211", "221132",
        "221231", "213212", "223112", "312131", "311222", "321122", "321221", "312212", "322112", "322211",
        "212123", "212321", "232121", "111323", "131123", "131321", "112313", "132113", "132311", "211313",
        "231113", "231311", "112133", "112331", "132131", "113123", "113321", "133121", "313121", "211331",
        "231131", "213113", "213311", "213131", "311123", "311321", "331121", "312113", "312311", "332111",
        "314111", "221411", "431111", "111224", "111422", "121124", "121421", "141122", "141221", "112214",
        "112412", "122114", "122411", "142112", "142211", "241211", "221114", "413111", "241112", "134111",
        "111242", "121142", "121241", "114212", "124112", "124211", "411212", "421112", "421211", "212141",
        "214121", "412121", "111143", "111341", "131141", "114113", "114311", "411113", "411311", "113141",
        "114131", "311141", "411131", "211412", "211214", "211232", "2331112",
    ]

    private static func isDigit(_ c: Character) -> Bool { c.isASCII && c.isNumber }

    static func symbolValues(_ value: String) throws -> [Int] {
        let chars = Array(value)
        for c in chars {
            guard let a = c.asciiValue, a >= 32, a <= 126 else { throw BarcodeError.invalidCharacter(c) }
        }
        // Length of the digit run starting at i.
        func run(_ i: Int) -> Int {
            var n = 0
            while i + n < chars.count, isDigit(chars[i + n]) { n += 1 }
            return n
        }
        var out: [Int] = []
        var i = 0
        var inC = false
        let r0 = run(0)
        if r0 >= 4, r0 % 2 == 0 {
            out.append(startC); inC = true
        } else {
            out.append(startB)
        }
        while i < chars.count {
            if inC {
                let r = run(i)
                if r >= 2 {
                    out.append(Int(String(chars[i...i + 1]))!)
                    i += 2
                } else {
                    out.append(codeB); inC = false
                }
            } else {
                let r = run(i)
                if r >= 4 {
                    // Odd run: emit the first digit in B so the rest pairs up in C.
                    if r % 2 == 1 {
                        out.append(Int(chars[i].asciiValue!) - 32); i += 1
                    }
                    out.append(codeC); inC = true
                } else {
                    out.append(Int(chars[i].asciiValue!) - 32); i += 1
                }
            }
        }
        return out
    }

    static func modules(_ value: String) throws -> [Bool] {
        var values = try symbolValues(value)
        values.append(code128Checksum(values))
        values.append(stop)
        var out: [Bool] = []
        for v in values { out += Barcode.runs(patterns[v].map { Int(String($0))! }) }
        return out
    }
}
