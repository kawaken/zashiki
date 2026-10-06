import AppKit
import Foundation

struct MarkdownPreviewDocumentSection: Identifiable, Equatable {
    let id: String
    let anchor: String?
    let markdown: String
}

enum MarkdownPreviewDocument {
    /// Splits a Markdown document at headings so page-internal links can use
    /// `ScrollViewReader` without changing the rendered block styles.
    static func sections(for body: String) -> [MarkdownPreviewDocumentSection] {
        let lines = body.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var sections: [(anchor: String?, lines: [String])] = []
        var currentLines: [String] = []
        var currentAnchor: String?
        var usedAnchors = Set<String>()
        var fence: Character?

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if let activeFence = fence {
                currentLines.append(line)
                if trimmed.first == activeFence,
                   trimmed.prefix(while: { $0 == activeFence }).count >= 3 {
                    fence = nil
                }
                continue
            }

            if let openingFence = openingFence(in: trimmed) {
                fence = openingFence
                currentLines.append(line)
                continue
            }

            guard let heading = heading(in: line) else {
                currentLines.append(line)
                continue
            }

            if !currentLines.isEmpty || !sections.isEmpty {
                sections.append((currentAnchor, currentLines))
            }
            currentLines = [heading.renderedLine]
            currentAnchor = uniqueAnchor(
                heading.explicitAnchor ?? slug(for: heading.text),
                usedAnchors: &usedAnchors
            )
        }

        if !currentLines.isEmpty || sections.isEmpty {
            sections.append((currentAnchor, currentLines))
        }

        return sections.enumerated().map { index, section in
            MarkdownPreviewDocumentSection(
                id: section.anchor ?? "markdown-preview-section-\(index)",
                anchor: section.anchor,
                markdown: section.lines.joined(separator: "\n")
            )
        }
    }

    private static func openingFence(in line: String) -> Character? {
        guard let first = line.first, first == "`" || first == "~" else { return nil }
        guard line.prefix(while: { $0 == first }).count >= 3 else { return nil }
        return first
    }

    private struct Heading {
        let text: String
        let renderedLine: String
        let explicitAnchor: String?
    }

    private static func heading(in line: String) -> Heading? {
        let indentation = line.prefix { $0 == " " }
        guard indentation.count <= 3 else { return nil }

        let content = line.dropFirst(indentation.count)
        let hashes = content.prefix { $0 == "#" }
        guard (1...6).contains(hashes.count) else { return nil }

        let remainder = content.dropFirst(hashes.count)
        guard remainder.isEmpty || remainder.first?.isWhitespace == true else { return nil }

        var text = String(remainder).trimmingCharacters(in: .whitespaces)
        while text.hasSuffix("#") {
            text.removeLast()
            text = text.trimmingCharacters(in: .whitespaces)
        }

        var explicitAnchor: String?
        if let start = text.range(of: "{#", options: .backwards), text.hasSuffix("}") {
            let candidate = text[text.index(start.lowerBound, offsetBy: 2)..<text.index(before: text.endIndex)]
            if !candidate.isEmpty {
                explicitAnchor = String(candidate)
                text = String(text[..<start.lowerBound]).trimmingCharacters(in: .whitespaces)
            }
        }

        let renderedLine = String(repeating: "#", count: hashes.count)
            + (text.isEmpty ? "" : " \(text)")
        return Heading(text: text, renderedLine: renderedLine, explicitAnchor: explicitAnchor)
    }

    private static func slug(for text: String) -> String {
        let folded = text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        var slug = ""
        var pendingSeparator = false

        for scalar in folded.unicodeScalars {
            if CharacterSet.alphanumerics.contains(scalar) || scalar == "_" || scalar == "-" {
                if pendingSeparator, !slug.isEmpty { slug.append("-") }
                slug.unicodeScalars.append(scalar)
                pendingSeparator = false
            } else if CharacterSet.whitespacesAndNewlines.contains(scalar) {
                pendingSeparator = true
            }
        }

        return slug
    }

    private static func uniqueAnchor(_ anchor: String, usedAnchors: inout Set<String>) -> String? {
        guard !anchor.isEmpty else { return nil }

        var candidate = anchor
        var suffix = 1
        while usedAnchors.contains(candidate) {
            candidate = "\(anchor)-\(suffix)"
            suffix += 1
        }
        usedAnchors.insert(candidate)
        return candidate
    }
}

struct MarkdownPreviewHistoryEntry: Identifiable, Equatable {
    let id: Int
    let url: URL
}

enum MarkdownPreviewFontSizePolicy {
    static let minimumSize: CGFloat = 10
    static let maximumSize: CGFloat = 32
    static let terminalScale: CGFloat = 0.8

    static func resolve(
        override: CGFloat,
        terminalCellHeight: CGFloat?,
        fallbackSize: CGFloat
    ) -> CGFloat {
        guard override > 0 else {
            guard let terminalCellHeight, terminalCellHeight > 0 else { return fallbackSize }
            return max(NSFont.smallSystemFontSize, terminalCellHeight * terminalScale)
        }
        return min(maximumSize, max(minimumSize, override))
    }
}

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

    /// All files in the current in-memory navigation history, in open order.
    /// The entry ID is its position in the history array, so repeated opens
    /// of the same URL remain distinct entries.
    @Published private(set) var historyEntries: [MarkdownPreviewHistoryEntry] = []

    /// The index of the file currently shown in `historyEntries`.
    @Published private(set) var currentHistoryIndex: Int?

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
        if historyIndex + 1 < history.count {
            history.removeSubrange((historyIndex + 1)...)
        }
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

    /// Moves directly to an existing history entry without adding a new one.
    func go(toHistoryEntryAt index: Int) {
        guard history.indices.contains(index), index != historyIndex else { return }
        historyIndex = index
        updateNavigationState()
        show(url: history[index])
    }

    private func show(url: URL) {
        fileURL = url
        isVisible = true
        watcher = MarkdownPreviewFileWatcher(url: url) { [weak self] in
            self?.reload()
        }
    }

    private func updateNavigationState() {
        historyEntries = history.enumerated().map { index, url in
            MarkdownPreviewHistoryEntry(id: index, url: url)
        }
        currentHistoryIndex = history.indices.contains(historyIndex) ? historyIndex : nil
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
