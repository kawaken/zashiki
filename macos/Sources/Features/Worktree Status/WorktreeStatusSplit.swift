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

    @ViewBuilder let content: () -> Content

    /// The fractional width of the pane vs. the terminal content.
    @State private var split: CGFloat = 0.3

    /// The fractional height of Worktree Status vs. Agents when both are
    /// visible in the side panel.
    @State private var panelSplit: CGFloat = 0.5

    var body: some View {
        Group {
            if !model.isVisible && !agentStatus.isVisible {
                content()
            } else {
                SplitView(.horizontal, $split, dividerColor: ghostty.config.splitDividerColor, left: {
                    sidePanel
                        .padding(.top, Spike208.isInset ? Spike208.titleRowHeight : 0)
                        .ignoresSafeArea(.container, edges: Spike208.isInset ? .top : [])
                }, right: {
                    content()
                }, onEqualize: {
                    split = 0.5
                })
            }
        }
        .frame(maxWidth: .greatestFiniteMagnitude, maxHeight: .greatestFiniteMagnitude)
    }

    @ViewBuilder
    private var sidePanel: some View {
        if model.isVisible && agentStatus.isVisible {
            SplitView(.vertical, $panelSplit, dividerColor: ghostty.config.splitDividerColor, left: {
                WorktreeStatusPane(model: model, directory: directory)
            }, right: {
                AgentStatusPane(model: agentStatus, surfaces: surfaces)
            }, onEqualize: {
                panelSplit = 0.5
            })
        } else if model.isVisible {
            WorktreeStatusPane(model: model, directory: directory)
        } else {
            AgentStatusPane(model: agentStatus, surfaces: surfaces)
        }
    }
}
