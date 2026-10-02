import Foundation

/// The state of a single tab in a terminal window: its split tree and
/// everything else that belongs to the tab rather than to the window.
///
/// `BaseTerminalController` owns the tabs and exposes the selected one
/// through its own `surfaceTree`, `focusedSurface`, etc.
final class TerminalTab: ObservableObject, Identifiable {
    let id = UUID()

    /// The tree of splits within this tab.
    @Published var surfaceTree: SplitTree<Zashiki.SurfaceView>

    /// The focused surface within this tab.
    var focusedSurface: Zashiki.SurfaceView?

    /// An override title for the tab set by the user via prompt_tab_title.
    /// When set, this takes precedence over the computed title from the terminal.
    var titleOverride: String?

    /// The state for this tab's Markdown preview.
    let markdownPreview = MarkdownPreviewModel()

    init(surfaceTree: SplitTree<Zashiki.SurfaceView> = .init()) {
        self.surfaceTree = surfaceTree
    }
}
