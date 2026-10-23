enum ITF14 {
    // n = narrow, w = wide (3 modules); 5 elements per digit.
    private static let patterns = ["nnwwn", "wnnnw", "nwnnw", "wwnnn", "nnwnw",
                                   "wnwnn", "nwwnn", "nnnww", "wnnwn", "nwnwn"]

    /// `d` holds 14 digits including the check digit.
    static func modules(_ d: [Int]) -> [Bool] {
        var widths = [1, 1, 1, 1] // start: narrow bar/space x2
        var i = 0
        while i < d.count {
            let bars = Array(patterns[d[i]]), spaces = Array(patterns[d[i + 1]])
            for k in 0..<5 {
                widths.append(bars[k] == "w" ? 3 : 1)
                widths.append(spaces[k] == "w" ? 3 : 1)
            }
            i += 2
        }
        widths += [3, 1, 1] // stop: wide bar, narrow space, narrow bar
        return Barcode.runs(widths)
    }
}
