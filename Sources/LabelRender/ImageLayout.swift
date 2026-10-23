import CoreGraphics
import LabelProtocol

/// Raster image: aspect-fit and centred in the printable area, gray, then 1 bit.
enum ImageLayout {
    static func render(_ content: ImageContent, geometry: LabelGeometry) -> MonochromeBitmap {
        let box = geometry.readingSizePoints
        let image = content.image
        let scale = min(box.width / CGFloat(image.width), box.height / CGFloat(image.height))
        let size = CGSize(width: CGFloat(image.width) * scale, height: CGFloat(image.height) * scale)
        let origin = CGPoint(x: (box.width - size.width) / 2, y: (box.height - size.height) / 2)
        return LabelRenderer.rasterize(geometry, dither: content.dither) { ctx in
            ctx.interpolationQuality = .high
            // Reading space is y-down; CGImage draws y-up. Transparency composites onto white.
            ctx.translateBy(x: origin.x, y: origin.y + size.height)
            ctx.scaleBy(x: 1, y: -1)
            ctx.draw(image, in: CGRect(origin: .zero, size: size))
        }
    }
}
