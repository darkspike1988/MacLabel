import CoreGraphics
import LabelProtocol

/// QR code: physically square modules, quiet zone of two modules, caption to the right.
enum QRLayout {
    static let quietModules = 2

    static func render(_ content: QRContent, geometry: LabelGeometry) throws -> (MonochromeBitmap, overflow: Bool) {
        let matrix: [[Bool]]
        do { matrix = try QRMatrix.modules(content.payload) } catch let error as BarcodeError { throw RenderError.barcode(error) }
        let grid = ReadingPixels(geometry)
        let total = matrix.count + 2 * quietModules
        // Module size in 300-dpi dots; on the feed axis it is that many dots' worth of lines.
        var module = min(grid.width / grid.xUnitsPerDot, grid.height / grid.yUnitsPerDot) / total
        var overflow = false
        if module < 1 { module = 1; overflow = true }
        let mx = module * grid.xUnitsPerDot, my = module * grid.yUnitsPerDot
        let side = (x: total * mx, y: total * my)

        var bitmap = MonochromeBitmap(width: geometry.headDots, height: geometry.lengthLines)
        var originX = (grid.width - side.x) / 2
        let caption = content.caption ?? ""
        if !caption.allSatisfy(\.isWhitespace) {
            originX = 0
            let box = grid.points(x: min(side.x, grid.width)..<grid.width, y: 0..<grid.height)
            if let text = BarcodeLayout.drawText(caption, in: box, geometry: geometry, alignment: .leading) {
                bitmap = text.bitmap
                overflow = overflow || text.overflow
            }
        }
        let originY = (grid.height - side.y) / 2

        for (row, cells) in matrix.enumerated() {
            let y = originY + (quietModules + row) * my
            for (col, dark) in cells.enumerated() where dark {
                let x = originX + (quietModules + col) * mx
                grid.fill(&bitmap, x: x..<x + mx, y: y..<y + my)
            }
        }
        return (bitmap, overflow)
    }
}
