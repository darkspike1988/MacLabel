import LabelRender

/// The direction the label leaves the printer, as seen in the upright preview.
/// Head line 0 is printed and ejected first; `LabelGeometry.headTransform()` places it at the
/// top (0°), left (90°), bottom (180°) or right (270°) edge of the reading view.
enum FeedDirection: Equatable {
    case up, left, down, right

    init(rotation: ReadingRotation) {
        switch rotation {
        case .upright: self = .up
        case .clockwise90: self = .left
        case .upsideDown: self = .down
        case .counterClockwise90: self = .right
        }
    }

    var systemImage: String {
        switch self {
        case .up: "arrow.up"
        case .left: "arrow.left"
        case .down: "arrow.down"
        case .right: "arrow.right"
        }
    }

    /// Up/down feed is drawn beside the label, left/right feed below it.
    var isVertical: Bool { self == .up || self == .down }
}

extension FeedDirection {
    /// The edge the label leaves the printer by, for VoiceOver.
    var title: String {
        switch self {
        case .up: L10n.string("Top edge")
        case .left: L10n.string("Left edge")
        case .down: L10n.string("Bottom edge")
        case .right: L10n.string("Right edge")
        }
    }
}
