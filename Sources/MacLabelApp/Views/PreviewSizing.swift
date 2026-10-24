import CoreGraphics

/// How large the preview raster is drawn.
///
/// The preview must show the exact 1-bit print raster, so it is drawn without interpolation and
/// every print dot covers a whole number of device pixels (never a fraction, never less than one).
/// Rule: enlarge by the largest whole factor that keeps the label within `limit`; if even 1:1 does
/// not fit, draw 1:1 anyway and let the caller scroll rather than drop dots.
enum PreviewSizing {
    /// Size in points for an image of `pixels` dots on a display with `displayScale` device pixels per point.
    static func size(pixels: CGSize, displayScale: CGFloat, limit: CGSize) -> CGSize {
        guard pixels.width > 0, pixels.height > 0 else { return .zero }
        let scale = max(displayScale, 1)
        let fit = min(limit.width * scale / pixels.width, limit.height * scale / pixels.height)
        let factor = max(fit.rounded(.down), 1)
        return CGSize(width: pixels.width * factor / scale, height: pixels.height * factor / scale)
    }
}
