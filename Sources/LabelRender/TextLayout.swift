import CoreGraphics
import CoreText
import Foundation

/// Lays out text lines (no wrapping) with an auto-fitted system font size.
struct TextLayout {
    static let minSize: CGFloat = 4
    static let maxSize: CGFloat = 200
    static let lineSpacing: CGFloat = 1.1

    struct Line {
        let line: CTLine
        /// Horizontal start of the line's typographic origin, in reading points.
        let x: CGFloat
        /// Baseline, in reading points (y down).
        let baseline: CGFloat
    }

    let fontSize: CGFloat
    let overflow: Bool
    let lines: [Line]

    /// Returns `nil` for empty or whitespace-only text.
    init?(_ content: TextContent, in size: CGSize) {
        guard !content.text.allSatisfy(\.isWhitespace) else { return nil }
        let strings = content.text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)

        // Largest k with size 4 + 0.5·k fitting; fitting is monotone in size.
        let steps = Int((Self.maxSize - Self.minSize) * 2)
        func sizeFor(_ k: Int) -> CGFloat { Self.minSize + CGFloat(k) / 2 }
        func fits(_ k: Int) -> Bool {
            let m = Self.measure(strings, font: Self.font(size: sizeFor(k), bold: content.bold))
            return m.width <= size.width && m.height <= size.height
        }
        let chosen: Int
        if fits(0) {
            var lo = 0, hi = steps
            while lo < hi {
                let mid = (lo + hi + 1) / 2
                if fits(mid) { lo = mid } else { hi = mid - 1 }
            }
            chosen = lo
            overflow = false
        } else {
            chosen = 0
            overflow = true
        }
        fontSize = sizeFor(chosen)

        let font = Self.font(size: fontSize, bold: content.bold)
        let ascent = CTFontGetAscent(font), descent = CTFontGetDescent(font)
        let pitch = (ascent + descent) * Self.lineSpacing
        let blockHeight = ascent + descent + pitch * CGFloat(strings.count - 1)
        let top = (size.height - blockHeight) / 2
        lines = strings.enumerated().map { i, s in
            let line = Self.makeLine(s, font: font)
            let ink = Self.inkExtent(line)
            let x: CGFloat
            switch content.alignment {
            case .leading: x = -ink.minX
            case .center: x = size.width / 2 - (ink.minX + ink.maxX) / 2
            case .trailing: x = size.width - ink.maxX
            }
            return Line(line: line, x: x, baseline: top + ascent + pitch * CGFloat(i))
        }
    }

    static func font(size: CGFloat, bold: Bool) -> CTFont {
        CTFontCreateUIFontForLanguage(bold ? .emphasizedSystem : .system, size, nil)
            ?? CTFontCreateWithName("Helvetica" as CFString, size, nil)
    }

    static func makeLine(_ s: String, font: CTFont) -> CTLine {
        CTLineCreateWithAttributedString(NSAttributedString(string: s, attributes: [NSAttributedString.Key(kCTFontAttributeName as String): font]))
    }

    /// Horizontal extent used for alignment: the glyph ink, falling back to the
    /// typographic width for lines without ink (e.g. spaces only).
    static func inkExtent(_ line: CTLine) -> (minX: CGFloat, maxX: CGFloat) {
        let glyphs = CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)
        if !glyphs.isNull, glyphs.width > 0 { return (glyphs.minX, glyphs.maxX) }
        return (0, typographicWidth(line))
    }

    static func typographicWidth(_ line: CTLine) -> CGFloat {
        CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil) - CTLineGetTrailingWhitespaceWidth(line))
    }

    /// Size of the text block at the given font.
    static func measure(_ strings: [String], font: CTFont) -> CGSize {
        let ascent = CTFontGetAscent(font), descent = CTFontGetDescent(font)
        var width: CGFloat = 0
        for s in strings {
            let line = makeLine(s, font: font)
            let ink = inkExtent(line)
            width = max(width, typographicWidth(line), ink.maxX - ink.minX)
        }
        let height = ascent + descent + (ascent + descent) * lineSpacing * CGFloat(strings.count - 1)
        return CGSize(width: width, height: height)
    }
}
