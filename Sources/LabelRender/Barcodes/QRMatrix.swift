import CoreImage
import CoreGraphics
import Foundation

public enum QRMatrix {
    /// Square module matrix (`true` = dark), quiet zone removed.
    public static func modules(_ payload: String) throws -> [[Bool]] {
        guard !payload.isEmpty else { throw BarcodeError.empty }
        guard let filter = CIFilter(name: "CIQRCodeGenerator") else { return [] }
        filter.setValue(Data(payload.utf8), forKey: "inputMessage")
        filter.setValue("M", forKey: "inputCorrectionLevel")
        guard let image = filter.outputImage else { return [] }
        let extent = image.extent.integral
        let w = Int(extent.width), h = Int(extent.height)
        guard w > 0, h > 0 else { return [] }

        var pixels = [UInt8](repeating: 255, count: w * h)
        let context = CIContext(options: [.useSoftwareRenderer: true])
        let space = CGColorSpaceCreateDeviceGray()
        guard let cg = context.createCGImage(image, from: extent, format: .L8, colorSpace: space) else { return [] }
        let ok = pixels.withUnsafeMutableBytes { buf -> Bool in
            guard let ctx = CGContext(data: buf.baseAddress, width: w, height: h, bitsPerComponent: 8,
                                      bytesPerRow: w, space: space, bitmapInfo: CGImageAlphaInfo.none.rawValue)
            else { return false }
            ctx.interpolationQuality = .none
            ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        guard ok else { return [] }

        var grid = (0..<h).map { y in (0..<w).map { x in pixels[y * w + x] < 128 } }
        // Strip the white border.
        let rows = grid.indices.filter { grid[$0].contains(true) }
        let cols = (0..<w).filter { x in grid.contains { $0[x] } }
        guard let r0 = rows.first, let r1 = rows.last, let c0 = cols.first, let c1 = cols.last else { return [] }
        grid = grid[r0...r1].map { Array($0[c0...c1]) }
        return grid
    }
}
