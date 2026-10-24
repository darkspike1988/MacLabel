import SwiftUI

/// The outline of a label: a rounded rectangle whose corner radius scales with the drawn width,
/// so it keeps the roll's real radius at any preview size.
struct LabelShape: Shape {
    /// Corner radius divided by the label's width.
    let cornerFraction: CGFloat

    func path(in rect: CGRect) -> Path {
        let radius = min(rect.width * cornerFraction, min(rect.width, rect.height) / 2)
        return Path(roundedRect: rect, cornerRadius: radius)
    }
}
