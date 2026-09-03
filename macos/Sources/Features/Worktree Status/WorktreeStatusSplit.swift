import SwiftUI

/// Wraps arbitrary terminal content with an optional Worktree Status pane.
/// When the pane is hidden this is a pass-through (no `SplitView`
/// overhead); when visible it wraps the pane and `content` side-by-side,
/// pane on the left, using the same `SplitView` the terminal splits use.
///
/// This is the left-side counterpart to `MarkdownPreviewSplit` (right
/// side); `TerminalView` nests the two so both can be shown at once.
struct WorktreeStatusSplit<Content: View>: View {
    let ghostty: Zashiki.App

    @ObservedObject var model: WorktreeStatusModel

    /// The directory to refresh against; forwarded to `WorktreeStatusPane`.
    let directory: URL?

    let surfaces: [Zashiki.SurfaceView]

    @ViewBuilder let content: () -> Content

    /// The fractional width of the pane vs. the terminal content.
    @State private var split: CGFloat = 0.3

    var body: some View {
        Group {
            if !model.isVisible {
                content()
            } else {
                SplitView(.horizontal, $split, dividerColor: ghostty.config.splitDividerColor, left: {
                    WorktreeStatusPane(model: model, directory: directory, surfaces: surfaces)
                }, right: {
                    content()
                }, onEqualize: {
                    split = 0.5
                })
            }
        }
        .frame(maxWidth: .greatestFiniteMagnitude, maxHeight: .greatestFiniteMagnitude)
    }
}
