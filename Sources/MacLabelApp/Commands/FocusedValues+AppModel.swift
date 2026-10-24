import SwiftUI

extension FocusedValues {
    /// The `AppModel` of the focused main window; menu commands act on it and are disabled without it.
    @Entry public var mainWindowModel: AppModel?
}
