/// What the menu bar panel's main button does for the typed text.
public enum PanelAction: Equatable, Sendable {
    case print
    /// The text does not fit: open the main window with it instead of printing.
    case openWindow
    /// Nothing can be printed; the text says why.
    case disabled(String)
}
