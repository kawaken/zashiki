import SwiftUI

/// Wraps arbitrary terminal content with the optional Worktree Status and
/// Agents panes. When both are visible, the side panel is split vertically
/// so each pane can be resized independently.
///
/// This is the left-side counterpart to `MarkdownPreviewSplit` (right
/// side); `TerminalView` nests the two so both can be shown at once.
struct WorktreeStatusSplit<Content: View>: View {
    let ghostty: Zashiki.App

    @ObservedObject var model: WorktreeStatusModel

    /// The directory to refresh against; forwarded to `WorktreeStatusPane`.
    let directory: URL?

    let surfaces: [Zashiki.SurfaceView]

    @ObservedObject var agentStatus: AgentStatusModel

    /// Divider positions, shared across the window's tabs.
    @ObservedObject var layout: PanelLayoutModel

    @ViewBuilder let content: () -> Content

    var body: some View {
        Group {
            if !model.isVisible && !agentStatus.isVisible {
                content()
            } else {
                SplitView(.horizontal, $layout.leftSplit, dividerColor: ghostty.config.splitDividerColor, left: {
                    sidePanel
                }, right: {
                    content()
                }, onEqualize: {
                    layout.leftSplit = 0.5
                })
            }
        }
        .frame(maxWidth: .greatestFiniteMagnitude, maxHeight: .greatestFiniteMagnitude)
    }

    @ViewBuilder
    private var sidePanel: some View {
        if model.isVisible && agentStatus.isVisible {
            SplitView(.vertical, $layout.leftPanelSplit, dividerColor: ghostty.config.splitDividerColor, left: {
                WorktreeStatusPane(model: model, directory: directory)
            }, right: {
                AgentStatusPane(model: agentStatus, surfaces: surfaces)
            }, onEqualize: {
                layout.leftPanelSplit = 0.5
            })
        } else if model.isVisible {
            WorktreeStatusPane(model: model, directory: directory)
        } else {
            AgentStatusPane(model: agentStatus, surfaces: surfaces)
        }
    }
}
