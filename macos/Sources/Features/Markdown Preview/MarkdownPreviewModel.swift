import Foundation

/// Owns the state for a single terminal window's Markdown preview pane.
/// One instance lives on each `BaseTerminalController` (see
/// `markdownPreview` there) and is shared with the SwiftUI view tree via
/// `TerminalViewModel`.
///
/// This currently only supports an explicit `reload()`. Live-reload on
/// file changes is added separately by `MarkdownPreviewFileWatcher`
/// (not yet wired in — see plan/markdown-preview.md Step 3).
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

    /// Opens `url` in the preview pane: reads its contents and shows the
    /// pane. Does not start watching `url` for changes.
    func open(url: URL) {
        fileURL = url
        reload()
        isVisible = true
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

    /// Hides the pane without discarding the currently open file, so
    /// reopening shows the same content.
    func close() {
        isVisible = false
    }
}
