import LabelMedia
import LabelProtocol

/// Physical parameters of the paper path, all in millimetres.
///
/// Paper coordinate: `s = 0` is the leading edge of the first label on the strip; `s` grows
/// against the feed direction (the leading edge passes the head first). The simulator tracks
/// `x`, the paper coordinate currently under the print line.
public struct MechanicalModel: Sendable, Equatable {
    /// Length of one label, leading edge to trailing edge. 11354: 375 dots at 300 dpi = 31.75 mm (catalog).
    public var labelLengthMM: Double
    /// Backing paper between two labels. Not published by DYMO; estimated from the roll geometry
    /// (1000 labels, 25 mm core, ≤ 85 mm roll, 0.13–0.15 mm material → pitch ≈ 35–39 mm → gap ≈ 3–6 mm).
    public var gapMM: Double
    /// Position of the top-of-form sense hole relative to the label's leading edge
    /// (positive = further into the label).
    public var senseHoleOffsetMM: Double
    /// Distance from the sense-hole sensor upstream to the print line. Together with
    /// `senseHoleOffsetMM` it gives where the first line lands at top of form:
    /// `senseHoleOffsetMM − headToSensorMM` below the leading edge.
    public var headToSensorMM: Double
    /// Distance from the print line to the tear bar (feed after `ESC E`, reversed before the next job).
    public var headToTearBarMM: Double
    /// Label width across the head (rendering only).
    public var labelWidthMM: Double
    /// Corner radius of the labels (rendering only).
    public var cornerRadiusMM: Double
    /// Dots across the head (672 at 300 dpi).
    public var headDots: Int

    public init(
        labelLengthMM: Double = 31.75,
        gapMM: Double = 4.5,
        senseHoleOffsetMM: Double = 0,
        headToSensorMM: Double = 0,
        headToTearBarMM: Double = 12,
        labelWidthMM: Double = 57.1,
        cornerRadiusMM: Double = 1.3,
        headDots: Int = 672
    ) {
        self.labelLengthMM = labelLengthMM
        self.gapMM = gapMM
        self.senseHoleOffsetMM = senseHoleOffsetMM
        self.headToSensorMM = headToSensorMM
        self.headToTearBarMM = headToTearBarMM
        self.labelWidthMM = labelWidthMM
        self.cornerRadiusMM = cornerRadiusMM
        self.headDots = headDots
    }

    /// Model for a die-cut catalog roll; the label length comes from `feedDots` (exact), not `feedMM` (rounded).
    public init(roll: LabelRoll, gapMM: Double = 4.5, headToTearBarMM: Double = 12) {
        self.init(
            labelLengthMM: Double(roll.feedDots ?? 375) * Self.step300MM,
            gapMM: gapMM,
            headToTearBarMM: headToTearBarMM,
            labelWidthMM: roll.acrossMM,
            cornerRadiusMM: roll.cornerRadiusMM
        )
    }

    /// One line at 300 lpi (`ESC h`).
    public static let step300MM = 25.4 / 300
    /// One line at 600 lpi (`ESC i`): half step.
    public static let step600MM = 25.4 / 600

    public func stepMM(_ quality: PrintQuality) -> Double {
        quality == .text ? Self.step300MM : Self.step600MM
    }

    /// Distance from one label's leading edge to the next.
    public var pitchMM: Double { labelLengthMM + gapMM }

    /// Where the print line sits relative to the leading edge at top of form.
    public var topOfFormOffsetMM: Double { senseHoleOffsetMM - headToSensorMM }

    public func leadingEdgeMM(label k: Int) -> Double { Double(k) * pitchMM }

    public func topOfFormMM(label k: Int) -> Double { leadingEdgeMM(label: k) + topOfFormOffsetMM }

    /// First top-of-form position strictly ahead of `x` (the sensor stops at the next hole).
    public func nextTopOfFormMM(after x: Double) -> Double {
        var k = Int(((x - topOfFormOffsetMM) / pitchMM).rounded(.down))
        while topOfFormMM(label: k) <= x + 1e-6 { k += 1 }
        return topOfFormMM(label: k)
    }

    public func isTopOfForm(_ x: Double) -> Bool {
        let k = ((x - topOfFormOffsetMM) / pitchMM).rounded()
        return abs(topOfFormMM(label: Int(k)) - x) < 1e-6
    }

    /// The label a page starting at `x` is meant for: the nearest top of form.
    public func labelIndex(forPageStart x: Double) -> Int {
        Int(((x - topOfFormOffsetMM) / pitchMM).rounded())
    }
}
