import Foundation

/// Owns the state for a single terminal window's Worktree Status pane.
/// One instance lives on each `BaseTerminalController` (see
/// `worktreeStatus` there) and is shared with the SwiftUI view tree via
/// `TerminalViewModel`.
///
/// Unlike `MarkdownPreviewModel`, there's no live-reload watcher: `gw list
/// --json` takes ~5s in practice (dominated by GitHub/agent lookups), so
/// refreshes only happen on explicit triggers — pane open, the manual
/// refresh button, and the focused surface's pwd changing (debounced; see
/// `TerminalView`).
class WorktreeStatusModel: ObservableObject {
    /// Whether the pane is currently shown.
    @Published var isVisible: Bool = false

    /// The worktrees from the most recent successful `gw list --json`.
    /// Preserved across a failed refresh so the pane doesn't blank out on
    /// a transient error (see `errorMessage`).
    @Published private(set) var worktrees: [GwWorktree] = []

    /// True while a `gw list` call is in flight.
    @Published private(set) var isLoading: Bool = false

    /// True while a `gw clean` call is in flight. Tracked separately from
    /// `isLoading` so the clean button's own spinner doesn't depend on
    /// unrelated background refreshes.
    @Published private(set) var isCleaning: Bool = false

    /// Set when the last `refresh()` or `clean()` failed. Cleared on the
    /// next successful `refresh()`. Stale `worktrees` are kept on screen
    /// even when this is set (same design as `MarkdownPreviewModel.errorMessage`).
    @Published private(set) var errorMessage: String?

    @Published private(set) var lastUpdatedAt: Date?

    /// Incremented on every refresh, successful or not, for views that
    /// need an explicit "state changed" signal instead of diffing arrays.
    @Published private(set) var revision: Int = 0

    private let client: GwClient
    private var currentDirectory: URL?
    private var inFlightTask: Task<Void, Never>?

    init(client: GwClient = GwClient()) {
        self.client = client
    }

    /// Worktrees `gw` recommends removing. Drives whether the "gw clean"
    /// button is enabled.
    var recommendedCleanupCount: Int {
        worktrees.filter { $0.cleanup.recommendation == "recommended" }.count
    }

    func open() {
        isVisible = true
    }

    func close() {
        isVisible = false
    }

    func toggle() {
        isVisible.toggle()
    }

    /// Re-runs `gw list --json` in `directory`. Cancels any in-flight
    /// refresh first — only the latest directory's result matters (e.g.
    /// focus moved to another surface before the previous call returned).
    func refresh(directory: URL) {
        currentDirectory = directory
        inFlightTask?.cancel()
        isLoading = true

        inFlightTask = Task { @MainActor [weak self, client] in
            guard let self else { return }
            do {
                let output = try await client.fetchWorktrees(directory: directory)
                guard !Task.isCancelled else { return }
                self.worktrees = output.worktrees
                self.errorMessage = nil
                self.lastUpdatedAt = Date()
            } catch {
                guard !Task.isCancelled else { return }
                self.errorMessage = Self.message(for: error)
            }
            guard !Task.isCancelled else { return }
            self.isLoading = false
            self.revision += 1
        }
    }

    /// Runs `gw clean --json` (a real, non-dry-run pass) in the
    /// last-known directory, then refreshes. Callers are expected to have
    /// already confirmed the candidate list with the user — this does not
    /// re-confirm.
    func clean() {
        guard let directory = currentDirectory else { return }
        isCleaning = true

        Task { @MainActor [weak self, client] in
            guard let self else { return }
            do {
                _ = try await client.clean(directory: directory)
                self.errorMessage = nil
            } catch {
                self.errorMessage = Self.message(for: error)
            }
            self.isCleaning = false
            self.refresh(directory: directory)
        }
    }

    private static func message(for error: Error) -> String {
        switch error {
        case GwClientError.binaryNotFound:
            return "\"gw\" was not found. Make sure it's installed and on PATH, or set ZASHIKI_GW."
        case GwClientError.timedOut:
            return "\"gw\" timed out."
        case GwClientError.processFailed(_, let stderr):
            let trimmed = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? "\"gw\" failed to run." : trimmed
        case GwClientError.decodingFailed:
            return "Couldn't parse \"gw\"'s output. It may be an unsupported version."
        default:
            return error.localizedDescription
        }
    }
}
