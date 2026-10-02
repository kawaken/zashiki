import Foundation

/// Divider positions for the side panes, shared across every tab in the
/// same tabGroup (see `BaseTerminalController.init`) so switching tabs
/// keeps the panel widths instead of resetting them per tab.
final class PanelLayoutModel: ObservableObject {
    /// The fractional width of the left side panel vs. the terminal content.
    @Published var leftSplit: CGFloat = 0.3

    /// The fractional height of Worktree Status vs. Agents when both are
    /// visible in the left side panel.
    @Published var leftPanelSplit: CGFloat = 0.5

    /// The fractional width of the terminal vs. the Markdown preview pane.
    @Published var rightSplit: CGFloat = 0.7
}
