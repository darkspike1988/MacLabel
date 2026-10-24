import LabelMedia
import SwiftUI

/// One rendered label drawn as white paper in reading orientation: the exact print raster,
/// the roll's corner radius, a subtle shadow, a red outline on overflow and the feed arrow.
/// White in dark mode too, because it stands for paper.
struct LabelPaper: View {
    let image: CGImage
    let roll: LabelRoll
    let feed: FeedDirection
    let overflow: Bool
    let spokenText: String

    @Environment(\.displayScale) private var displayScale

    var body: some View {
        let layout = feed.isVertical ? AnyLayout(HStackLayout(spacing: 12)) : AnyLayout(VStackLayout(spacing: 12))
        layout {
            ViewThatFits {
                paper
                ScrollView([.horizontal, .vertical]) { paper.padding(12) }
            }

            Image(systemName: feed.systemImage)
                .font(.title3)
                .foregroundStyle(.secondary)
                .help(L10n.string("Feed direction: this edge leaves the printer first."))
                .accessibilityLabel(L10n.string("Feed direction"))
                .accessibilityValue(feed.title)
        }
    }

    /// The raster at a whole number of device pixels per dot, see `PreviewSizing`.
    private var paper: some View {
        let shape = LabelShape(cornerFraction: cornerFraction)
        let size = PreviewSizing.size(
            pixels: CGSize(width: image.width, height: image.height), displayScale: displayScale, limit: Self.maxSize
        )
        return Image(decorative: image, scale: 1)
            .resizable()
            .interpolation(.none)
            .antialiased(false)
            .frame(width: size.width, height: size.height)
            .background(.white)
            .clipShape(shape)
            .overlay {
                if overflow {
                    shape.stroke(.red, lineWidth: 3)
                } else {
                    shape.stroke(.black.opacity(0.08), lineWidth: 1)
                }
            }
            .shadow(color: .black.opacity(0.18), radius: 8, y: 3)
            .accessibilityElement()
            .accessibilityLabel(spokenText)
            .accessibilityValue(overflow ? L10n.string("Doesn't fit on the label") : "")
            .accessibilityAddTraits(.isImage)
    }

    /// Large, but not so large that a small label turns into a poster.
    private static let maxSize = CGSize(width: 560, height: 380)

    /// The preview covers the whole label at 300 dpi, so the radius in pixels is relative to its width.
    private var cornerFraction: CGFloat {
        guard image.width > 0 else { return 0 }
        return CGFloat(roll.cornerRadiusMM / 25.4 * 300) / CGFloat(image.width)
    }
}
