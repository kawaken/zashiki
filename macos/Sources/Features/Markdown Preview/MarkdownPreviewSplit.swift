import SwiftUI

/// Wraps arbitrary terminal content with an optional Markdown preview
/// pane. When the pane is hidden this is a pass-through (no `SplitView`
/// overhead); when visible it wraps `content` and the preview side-by-side
/// using the same `SplitView` the terminal splits use.
struct MarkdownPreviewSplit<Content: View>: View {
    let ghostty: Ghostty.App

    @ObservedObject var model: MarkdownPreviewModel

    @ViewBuilder let content: () -> Content

    /// The fractional width of the terminal vs. the preview pane.
    @State private var split: CGFloat = 0.7

    var body: some View {
        Group {
            if !model.isVisible {
                content()
            } else {
                SplitView(.horizontal, $split, dividerColor: ghostty.config.splitDividerColor, left: {
                    content()
                }, right: {
                    MarkdownPreviewPane(model: model)
                }, onEqualize: {
                    split = 0.5
                })
            }
        }
        .frame(maxWidth: .greatestFiniteMagnitude, maxHeight: .greatestFiniteMagnitude)
    }
}
