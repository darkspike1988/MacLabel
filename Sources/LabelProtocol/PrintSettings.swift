public enum PrintQuality: Sendable {
    case text
    case graphics

    /// Lines per inch in feed direction.
    public var linesPerInch: Int {
        switch self {
        case .text: 300
        case .graphics: 600
        }
    }
}

public enum PrintDensity: Sendable, CaseIterable {
    case light, medium, normal, dark
}

public enum TwinRoll: Sendable {
    case auto, left, right
}
