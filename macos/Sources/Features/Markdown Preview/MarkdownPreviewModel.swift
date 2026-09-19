import Foundation

/// Owns the state for a single terminal window's Markdown preview pane.
/// One instance lives on each `BaseTerminalController` (see
/// `markdownPreview` there) and is shared with the SwiftUI view tree via
/// `TerminalViewModel`.
///
/// Live-reload is driven by `MarkdownPreviewFileWatcher`: `open(url:)`
/// starts watching the file, and further writes (including atomic-save
/// editors that replace the file via `rename(2)`) trigger `reload()`
/// automatically. Watching continues even while the pane is hidden, so
/// showing it again reflects up-to-date content.
class MarkdownPreviewModel: ObservableObject {
    /// Whether the preview pane is currently shown.
    @Published var isVisible: Bool = false

    /// The file currently being previewed, if any.
    @Published private(set) var fileURL: URL?

    /// The raw Markdown content of `fileURL`, or empty if nothing is open.
    @Published private(set) var content: String = ""

    /// Incremented every time `content` is reloaded. Views that need an
    /// explicit "content changed" signal (e.g. for scroll preservation in
    /// a later step) can observe this instead of diffing strings.
    @Published private(set) var revision: Int = 0

    /// Set when `fileURL` could not be read. Cleared on the next
    /// successful read.
    @Published private(set) var errorMessage: String?

    /// Whether `goBack()` would move to a previous entry.
    @Published private(set) var canGoBack: Bool = false

    /// Whether `goForward()` would move to a later entry.
    @Published private(set) var canGoForward: Bool = false

    /// Files opened via `open(url:)`, in navigation order. `historyIndex`
    /// points at the entry currently shown in `fileURL`. `goBack()` /
    /// `goForward()` move within this list without altering it;
    /// `open(url:)` truncates any forward entries and appends the new one,
    /// like a browser's history after following a fresh link.
    private var history: [URL] = []
    private var historyIndex: Int = -1

    private var watcher: MarkdownPreviewFileWatcher?

    /// Opens `url` in the preview pane as a new history entry: reads its
    /// contents, shows the pane, and starts watching `url` for changes.
    /// Replaces any previously-watched file. Any forward history is
    /// discarded, matching browser back/forward semantics.
    func open(url: URL) {
        history.removeSubrange((historyIndex + 1)...)
        history.append(url)
        historyIndex = history.count - 1
        updateNavigationState()
        show(url: url)
    }

    /// Moves to the previous entry in history, if any.
    func goBack() {
        guard canGoBack else { return }
        historyIndex -= 1
        updateNavigationState()
        show(url: history[historyIndex])
    }

    /// Moves to the next entry in history, if any.
    func goForward() {
        guard canGoForward else { return }
        historyIndex += 1
        updateNavigationState()
        show(url: history[historyIndex])
    }

    private func show(url: URL) {
        fileURL = url
        reload()
        isVisible = true
        watcher = MarkdownPreviewFileWatcher(url: url) { [weak self] in
            self?.reload()
        }
    }

    private func updateNavigationState() {
        canGoBack = historyIndex > 0
        canGoForward = historyIndex < history.count - 1
    }

    /// Re-reads `fileURL` from disk and republishes `content`.
    func reload() {
        guard let fileURL else { return }
        do {
            content = try String(contentsOf: fileURL, encoding: .utf8)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
        revision += 1
    }

    /// Toggles pane visibility. If no file is open yet, this shows/hides
    /// an empty state with an "Open File..." affordance.
    func toggle() {
        isVisible.toggle()
    }

    /// Hides the pane without discarding the currently open file or
    /// stopping the watcher, so reopening shows up-to-date content.
    func close() {
        isVisible = false
    }
}
