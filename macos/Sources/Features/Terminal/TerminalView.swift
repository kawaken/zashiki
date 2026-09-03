import SwiftUI
import GhosttyKit
import os

/// This delegate is notified of actions and property changes regarding the terminal view. This
/// delegate is optional and can be used by a TerminalView caller to react to changes such as
/// titles being set, cell sizes being changed, etc.
protocol TerminalViewDelegate: AnyObject {
    /// Called when the currently focused surface changed. This can be nil.
    func focusedSurfaceDidChange(to: Zashiki.SurfaceView?)

    /// The URL of the pwd should change.
    func pwdDidChange(to: URL?)

    /// The cell size changed.
    func cellSizeDidChange(to: NSSize)

    /// Perform an action. At the time of writing this is only triggered by the command palette.
    func performAction(_ action: String, on: Zashiki.SurfaceView)

    /// A split tree operation
    func performSplitAction(_ action: TerminalSplitOperation)
}

/// The view model is a required implementation for TerminalView callers. This contains
/// the main state between the TerminalView caller and SwiftUI. This abstraction is what
/// allows AppKit to own most of the data in SwiftUI.
protocol TerminalViewModel: ObservableObject {
    /// The tree of terminal surfaces (splits) within the view. This is mutated by TerminalView
    /// and children. This should be @Published.
    var surfaceTree: SplitTree<Zashiki.SurfaceView> { get set }

    /// The command palette state.
    var commandPaletteIsShowing: Bool { get set }

    /// The update overlay should be visible.
    var updateOverlayIsVisible: Bool { get }

    /// The state for this window's Markdown preview pane.
    var markdownPreview: MarkdownPreviewModel { get }

    /// The state for this window's Worktree Status pane.
    var worktreeStatus: WorktreeStatusModel { get }
}

/// The main terminal view. This terminal view supports splits.
struct TerminalView<ViewModel: TerminalViewModel>: View {
    @ObservedObject var ghostty: Zashiki.App

    // The required view model
    @ObservedObject var viewModel: ViewModel

    // An optional delegate to receive information about terminal changes.
    weak var delegate: (any TerminalViewDelegate)?

    /// The most recently focused surface, equal to `focusedSurface` when it is non-nil.
    @State private var lastFocusedSurface: Weak<Zashiki.SurfaceView>?

    /// Debounces Worktree Status refreshes triggered by `pwdURL` changing,
    /// so rapid focus changes across surfaces don't fire a `gw list` per
    /// hop.
    @State private var worktreeStatusRefreshTask: Task<Void, Never>?

    // This seems like a crutch after switching from SwiftUI to AppKit lifecycle.
    @FocusState private var focused: Bool

    // Various state values sent back up from the currently focused terminals.
    @FocusedValue(\.zashikiSurfaceView) private var focusedSurface
    @FocusedValue(\.zashikiSurfacePwd) private var surfacePwd
    @FocusedValue(\.zashikiSurfaceCellSize) private var cellSize

    // The pwd of the focused surface as a URL
    private var pwdURL: URL? {
        guard let surfacePwd, surfacePwd != "" else { return nil }
        return URL(fileURLWithPath: surfacePwd)
    }

    var body: some View {
        switch ghostty.readiness {
        case .loading:
            Text("Loading")
        case .error:
            ErrorView()
        case .ready:
            WorktreeStatusSplit(
                ghostty: ghostty,
                model: viewModel.worktreeStatus,
                directory: pwdURL,
                surfaces: Array(viewModel.surfaceTree)) {
                MarkdownPreviewSplit(ghostty: ghostty, model: viewModel.markdownPreview) {
                    ZStack {
                        VStack(spacing: 0) {
                            // If we're running in debug mode we show a warning so that users
                            // know that performance will be degraded.
                            if Zashiki.info.mode == GHOSTTY_BUILD_MODE_DEBUG || Zashiki.info.mode == GHOSTTY_BUILD_MODE_RELEASE_SAFE {
                                DebugBuildWarningView()
                            }

                            TerminalSplitTreeView(
                                tree: viewModel.surfaceTree,
                                action: { delegate?.performSplitAction($0) })
                                .environmentObject(ghostty)
                                .zashikiLastFocusedSurface(lastFocusedSurface)
                                .focused($focused)
                                .onAppear { self.focused = true }
                                .onChange(of: focusedSurface) { newValue in
                                    // We want to keep track of our last focused surface so even if
                                    // we lose focus we keep this set to the last non-nil value.
                                    if newValue != nil {
                                        lastFocusedSurface = .init(newValue)
                                        self.delegate?.focusedSurfaceDidChange(to: newValue)
                                    }
                                }
                                .onChange(of: pwdURL) { newValue in
                                    self.delegate?.pwdDidChange(to: newValue)

                                    worktreeStatusRefreshTask?.cancel()
                                    guard viewModel.worktreeStatus.isVisible, let newValue else { return }
                                    worktreeStatusRefreshTask = Task {
                                        try? await Task.sleep(nanoseconds: 400_000_000)
                                        guard !Task.isCancelled else { return }
                                        viewModel.worktreeStatus.refresh(directory: newValue)
                                    }
                                }
                                .onChange(of: cellSize) { newValue in
                                    guard let size = newValue else { return }
                                    self.delegate?.cellSizeDidChange(to: size)
                                }
                                .frame(idealWidth: lastFocusedSurface?.value?.initialSize?.width,
                                       idealHeight: lastFocusedSurface?.value?.initialSize?.height)
                        }
                        // Ignore safe area to extend up in to the titlebar region if we have the "hidden" titlebar style
                        .ignoresSafeArea(.container, edges: ghostty.config.macosTitlebarStyle == .hidden ? .top : [])

                        if let surfaceView = lastFocusedSurface?.value {
                            TerminalCommandPaletteView(
                                surfaceView: surfaceView,
                                isPresented: $viewModel.commandPaletteIsShowing,
                                zashikiConfig: ghostty.config,
                                updateViewModel: (NSApp.delegate as? AppDelegate)?.updateViewModel) { action in
                                self.delegate?.performAction(action, on: surfaceView)
                            }
                        }

                        // Show update information above all else.
                        if viewModel.updateOverlayIsVisible {
                            UpdateOverlay()
                        }
                    }
                }
            }
        }
    }
}

private struct UpdateOverlay: View {
    var body: some View {
        if let appDelegate = NSApp.delegate as? AppDelegate {
            VStack {
                Spacer()

                HStack {
                    Spacer()
                    UpdatePill(model: appDelegate.updateViewModel)
                        .padding(.bottom, 9)
                        .padding(.trailing, 9)
                }
            }
        }
    }
}

struct DebugBuildWarningView: View {
    @State private var isPopover = false

    var body: some View {
        HStack {
            Spacer()

            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.yellow)

            Text("You're running a debug build of Zashiki! Performance will be degraded.")
                .padding(.all, 8)
                .popover(isPresented: $isPopover, arrowEdge: .bottom) {
                    Text("""
                    Debug builds of Zashiki are very slow and you may experience
                    performance problems. Debug builds are only recommended during
                    development.
                    """)
                    .padding(.all)
                }

            Spacer()
        }
        .background(Color(.windowBackgroundColor))
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Debug build warning")
        .accessibilityValue("Debug builds of Zashiki are very slow and you may experience performance problems. Debug builds are only recommended during development.")
        .accessibilityAddTraits(.isStaticText)
        .onTapGesture {
            isPopover = true
        }
    }
}
