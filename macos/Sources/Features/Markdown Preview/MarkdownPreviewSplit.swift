import SwiftUI

/// Wraps arbitrary terminal content with an optional Markdown preview
/// pane. When the pane is hidden this is a pass-through (no `SplitView`
/// overhead); when visible it wraps `content` and the preview side-by-side
/// using the same `SplitView` the terminal splits use.
struct MarkdownPreviewSplit<Content: View>: View {
    let ghostty: Zashiki.App

    @ObservedObject var model: MarkdownPreviewModel

    /// Divider position, shared across the window's tabs.
    @ObservedObject var layout: PanelLayoutModel

    @ViewBuilder let content: () -> Content

    var body: some View {
        Group {
            if !model.isVisible {
                content()
            } else {
                SplitView(.horizontal, $layout.rightSplit, dividerColor: ghostty.config.splitDividerColor, left: {
                    content()
                }, right: {
                    MarkdownPreviewPane(model: model)
                }, onEqualize: {
                    layout.rightSplit = 0.5
                })
            }
        }
        .frame(maxWidth: .greatestFiniteMagnitude, maxHeight: .greatestFiniteMagnitude)
    }
}
