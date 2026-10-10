import SwiftUI

/// The top row of a terminal window. There is no title row: the tab bar and
/// the side panels' headers sit side by side at the top of the window.
enum WindowTopRow {
    static let height: CGFloat = 36
}

private struct WindowButtonsInsetKey: EnvironmentKey {
    static let defaultValue: CGFloat = 0
}

extension EnvironmentValues {
    /// Space to leave at the leading edge for the window buttons (the traffic
    /// lights). Only the view in the top-left corner of the window gets a
    /// non-zero value.
    var windowButtonsInset: CGFloat {
        get { self[WindowButtonsInsetKey.self] }
        set { self[WindowButtonsInsetKey.self] = newValue }
    }
}
