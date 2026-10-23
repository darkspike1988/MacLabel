import CoreGraphics
import CoreText
import Foundation

/// Lays out text lines (no wrapping) with an auto-fitted system font size.
struct TextLayout {
    static let minSize: CGFloat = 4
    static let maxSize: CGFloat = 200
    static let lineSpacing: CGFloat = 1.1
    /// Kept free on every side so antialiased edge pixels never touch the clip.
    static let safetyMargin: CGFloat = 0.5

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
        // `\.isNewline` covers "\n", "\r\n" (one Character), "\r", U+2028 etc.
        let strings = content.text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline).map(String.init)
        let box = CGRect(origin: .zero, size: size).insetBy(dx: Self.safetyMargin, dy: Self.safetyMargin)

        // Largest k with size 4 + 0.5·k fitting; fitting is monotone in size.
        let steps = Int((Self.maxSize - Self.minSize) * 2)
        func sizeFor(_ k: Int) -> CGFloat { Self.minSize + CGFloat(k) / 2 }
        func fits(_ k: Int) -> Bool {
            let block = Block(strings, font: Self.font(size: sizeFor(k), bold: content.bold))
            return block.width <= box.width && block.height <= box.height
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

        let block = Block(strings, font: Self.font(size: fontSize, bold: content.bold))
        // Centre the real vertical extent (ink and typographic, all runs) in the box.
        let shift = box.midY - (block.top + block.bottom) / 2
        lines = block.lines.map { m in
            let x: CGFloat
            switch content.alignment {
            case .leading: x = box.minX - m.inkMinX
            case .center: x = box.midX - (m.inkMinX + m.inkMaxX) / 2
            case .trailing: x = box.maxX - m.inkMaxX
            }
            return Line(line: m.line, x: x, baseline: m.baseline + shift)
        }
    }

    /// Per-line metrics of a text block at one font size. Baselines start at 0 (y down).
    struct Block {
        struct Metrics {
            let line: CTLine
            let baseline: CGFloat
            let inkMinX: CGFloat, inkMaxX: CGFloat
        }

        let lines: [Metrics]
        let width: CGFloat
        /// Topmost and bottommost extent relative to the first baseline (y down).
        let top: CGFloat, bottom: CGFloat
        var height: CGFloat { bottom - top }

        init(_ strings: [String], font: CTFont) {
            let fontAscent = CTFontGetAscent(font), fontDescent = CTFontGetDescent(font)
            let pitch = (fontAscent + fontDescent) * TextLayout.lineSpacing
            var lines: [Metrics] = []
            var width: CGFloat = 0, top = CGFloat.infinity, bottom = -CGFloat.infinity
            for (i, s) in strings.enumerated() {
                let line = CTLineCreateWithAttributedString(
                    NSAttributedString(string: s, attributes: [NSAttributedString.Key(kCTFontAttributeName as String): font]))
                // Typographic bounds take the max over all runs, including fallback fonts.
                var ascent: CGFloat = 0, descent: CGFloat = 0
                let typoWidth = CGFloat(CTLineGetTypographicBounds(line, &ascent, &descent, nil))
                    - CGFloat(CTLineGetTrailingWhitespaceWidth(line))
                var above = max(ascent, fontAscent), below = max(descent, fontDescent)
                var inkMinX: CGFloat = 0, inkMaxX = typoWidth
                let glyphs = CTLineGetBoundsWithOptions(line, .useGlyphPathBounds) // y up
                if !glyphs.isNull, glyphs.width > 0 || glyphs.height > 0 {
                    above = max(above, glyphs.maxY)
                    below = max(below, -glyphs.minY)
                    if glyphs.width > 0 { inkMinX = glyphs.minX; inkMaxX = glyphs.maxX }
                }
                let baseline = pitch * CGFloat(i)
                top = min(top, baseline - above)
                bottom = max(bottom, baseline + below)
                width = max(width, typoWidth, inkMaxX - inkMinX)
                lines.append(Metrics(line: line, baseline: baseline, inkMinX: inkMinX, inkMaxX: inkMaxX))
            }
            self.lines = lines
            self.width = width
            self.top = top
            self.bottom = bottom
        }
    }

    static func font(size: CGFloat, bold: Bool) -> CTFont {
        CTFontCreateUIFontForLanguage(bold ? .emphasizedSystem : .system, size, nil)
            ?? CTFontCreateWithName("Helvetica" as CFString, size, nil)
    }
}
