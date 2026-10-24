enum EANUPC {
    private static let l = ["0001101", "0011001", "0010011", "0111101", "0100011",
                            "0110001", "0101111", "0111011", "0110111", "0001011"]
    private static let g = ["0100111", "0110011", "0011011", "0100001", "0011101",
                            "0111001", "0000101", "0010001", "0001001", "0010111"]
    private static let r = ["1110010", "1100110", "1101100", "1000010", "1011100",
                            "1001110", "1010000", "1000100", "1001000", "1110100"]
    private static let parity = ["LLLLLL", "LLGLGG", "LLGGLG", "LLGGGL", "LGLLGG",
                                 "LGGLLG", "LGGGLL", "LGLGLG", "LGLGGL", "LGGLGL"]

    /// GS1 mod-10 check digit over `body` (weights 3,1,3,... from the right).
    static func checkDigit(_ body: [Int]) -> Int {
        var sum = 0
        for (i, d) in body.reversed().enumerated() { sum += d * (i % 2 == 0 ? 3 : 1) }
        return (10 - sum % 10) % 10
    }

    /// Returns body + check digit. Accepts `bodyLength` digits (append) or `bodyLength + 1` (verify).
    static func digits(_ value: String, bodyLength: Int) throws -> [Int] {
        var d: [Int] = []
        for ch in value {
            guard let n = ch.wholeNumberValue, ch.isASCII else { throw BarcodeError.invalidCharacter(ch) }
            d.append(n)
        }
        if d.count == bodyLength { return d + [checkDigit(d)] }
        if d.count == bodyLength + 1 {
            guard checkDigit(Array(d.dropLast())) == d[bodyLength] else { throw BarcodeError.badCheckDigit }
            return d
        }
        throw BarcodeError.invalidLength(expected: [bodyLength, bodyLength + 1], got: d.count)
    }

    private static func bits(_ s: String) -> [Bool] { s.map { $0 == "1" } }

    static func ean13Modules(_ d: [Int]) -> [Bool] {
        var out = bits("101")
        for (i, p) in parity[d[0]].enumerated() {
            out += bits(p == "L" ? l[d[i + 1]] : g[d[i + 1]])
        }
        out += bits("01010")
        for i in 7...12 { out += bits(r[d[i]]) }
        return out + bits("101")
    }

    static func ean8Modules(_ d: [Int]) -> [Bool] {
        var out = bits("101")
        for i in 0..<4 { out += bits(l[d[i]]) }
        out += bits("01010")
        for i in 4..<8 { out += bits(r[d[i]]) }
        return out + bits("101")
    }
}
