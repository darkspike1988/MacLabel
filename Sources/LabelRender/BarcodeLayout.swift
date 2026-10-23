import CoreGraphics
import LabelProtocol

/// 1D barcode: bars perpendicular to reading x, written as whole head pixels.
enum BarcodeLayout {
    static let quietModules = 10
    /// Smallest module (X-dimension) in 300-dpi dots.
    static let minModuleDots = 2
    /// Share of the reading height used by the human-readable text.
    static let textBand = 0.2

    static func render(_ content: BarcodeContent, geometry: LabelGeometry) throws -> (MonochromeBitmap, overflow: Bool) {
        let modules: [Bool], text: String
        do {
            modules = try Barcode.modules(content.symbology, content.value)
            text = try Barcode.humanReadable(content.symbology, content.value)
        } catch let error as BarcodeError {
            throw RenderError.barcode(error)
        }
        let grid = ReadingPixels(geometry)
        let total = modules.count + 2 * quietModules
        // Ruling 30: a module is at least `minModuleDots` dots (≈0.17 mm) wide physically, i.e. 4 lines
        // when reading x lies on the 600-lpi feed axis. Narrower codes do not scan reliably: render at the
        // minimum and report overflow instead.
        let minModule = minModuleDots * grid.xUnitsPerDot
        var module = grid.width / total
        var overflow = false
        if module < minModule { module = minModule; overflow = true }

        var barHeight = grid.height
        var bitmap = MonochromeBitmap(width: geometry.headDots, height: geometry.lengthLines)
        if content.showText {
            barHeight = Int(Double(grid.height) * (1 - textBand))
            let band = grid.points(x: 0..<grid.width, y: barHeight..<grid.height)
            if let caption = drawText(text, in: band, geometry: geometry) {
                bitmap = caption.bitmap
                overflow = overflow || caption.overflow
            }
        }

        // Centred; when overflowing, the start is negative and the fill clips.
        var x = (grid.width - total * module) / 2 + quietModules * module
        var i = 0
        while i < modules.count {
            var end = i
            while end < modules.count, modules[end] == modules[i] { end += 1 }
            let length = (end - i) * module
            if modules[i] { grid.fill(&bitmap, x: x..<x + length, y: 0..<barHeight) }
            x += length
            i = end
        }
        return (bitmap, overflow)
    }

    /// Auto-fits `text` into `box` (reading points) and rasterizes it; `nil` for blank text.
    static func drawText(_ text: String, in box: CGRect, geometry: LabelGeometry,
                         alignment: TextContent.TextAlignment = .center) -> (bitmap: MonochromeBitmap, overflow: Bool)? {
        guard box.width > 2 * TextLayout.safetyMargin, box.height > 2 * TextLayout.safetyMargin else {
            return text.allSatisfy(\.isWhitespace) ? nil
                : (MonochromeBitmap(width: geometry.headDots, height: geometry.lengthLines), true)
        }
        guard let layout = TextLayout(TextContent(text: text, alignment: alignment), in: box.size) else { return nil }
        let bitmap = LabelRenderer.rasterize(geometry) { ctx in
            ctx.translateBy(x: box.minX, y: box.minY)
            layout.draw(in: ctx)
        }
        return (bitmap, layout.overflow)
    }
}
