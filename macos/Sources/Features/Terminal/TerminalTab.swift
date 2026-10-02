import Combine
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
    var focusedSurface: Zashiki.SurfaceView? {
        didSet {
            guard focusedSurface !== oldValue else { return }
            observeFocusedSurface(previous: oldValue)
        }
    }

    /// An override title for the tab set by the user via prompt_tab_title.
    /// When set, this takes precedence over the computed title from the terminal.
    @Published var titleOverride: String?

    /// The title reported by the focused surface (without the override).
    @Published private(set) var surfaceTitle: String = TerminalTab.placeholderTitle

    /// True when the focused surface has an active bell.
    @Published private(set) var focusedSurfaceBell: Bool = false

    /// True when any surface in this tab has an active bell.
    @Published private(set) var bell: Bool = false

    /// The color assigned to this tab.
    @Published var color: TerminalTabColor = .none

    /// The state for this tab's Markdown preview.
    let markdownPreview = MarkdownPreviewModel()

    /// The title to show for this tab.
    var title: String { titleOverride ?? surfaceTitle }

    /// True if closing this tab should ask for confirmation.
    var needsConfirmQuit: Bool {
        surfaceTree.contains(where: { $0.needsConfirmQuit })
    }

    static let placeholderTitle = "👻"

    private var focusedSurfaceCancellables: Set<AnyCancellable> = []
    private var bellCancellable: AnyCancellable?

    init(surfaceTree: SplitTree<Zashiki.SurfaceView> = .init()) {
        self.surfaceTree = surfaceTree

        // `surfaceTree` can be replaced entirely when splits are added/removed/closed.
        // For each tree snapshot we build a fresh publisher that watches all surfaces
        // in that snapshot.
        bellCancellable = $surfaceTree
            .map { tree in
                tree.valuesPublisher(valueKeyPath: \.bell, publisherKeyPath: \.$bell)
            }
            // Keep only the latest tree publisher active. This automatically cancels
            // subscriptions for old/removed surfaces when the tree changes.
            .switchToLatest()
            .map { $0.values.contains(true) }
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.bell = $0 }
    }

    /// Follows the title and bell of the focused surface. If there is no focused
    /// surface we keep following the previous one, as long as it is still in the
    /// tree, so we don't listen to titles of closed surfaces.
    private func observeFocusedSurface(previous: Zashiki.SurfaceView?) {
        // Important to cancel any prior subscriptions
        focusedSurfaceCancellables = []

        guard let surface = focusedSurface ?? previous, surfaceTree.contains(surface) else {
            surfaceTitle = Self.placeholderTitle
            focusedSurfaceBell = false
            return
        }

        surface.$title
            .sink { [weak self] in self?.surfaceTitle = $0 }
            .store(in: &focusedSurfaceCancellables)
        surface.$bell
            .sink { [weak self] in self?.focusedSurfaceBell = $0 }
            .store(in: &focusedSurfaceCancellables)
    }
}
