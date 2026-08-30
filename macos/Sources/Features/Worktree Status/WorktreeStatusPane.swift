import SwiftUI

/// The left-hand pane shown when a terminal window's Worktree Status is
/// visible. Shows a header (title, refresh button, "gw clean" button,
/// close button) plus the worktree list, or an empty/loading/error state.
struct WorktreeStatusPane: View {
    @ObservedObject var model: WorktreeStatusModel

    /// The directory to refresh against, derived from the focused
    /// surface's pwd. `nil` when no surface is focused yet / its pwd
    /// isn't known.
    let directory: URL?

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
        }
        .background(Color(nsColor: .textBackgroundColor))
    }

    private var header: some View {
        HStack(spacing: 10) {
            Text("Worktree Status")
                .font(.headline)
                .lineLimit(1)

            Spacer()

            if model.isLoading {
                ProgressView()
                    .controlSize(.small)
            }

            Button {
                guard let directory else { return }
                model.refresh(directory: directory)
            } label: {
                Image(systemName: "arrow.clockwise")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .disabled(directory == nil || model.isLoading)
            .help("Refresh")

            Button {
                confirmAndClean()
            } label: {
                if model.isCleaning {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: "trash")
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)
            .disabled(model.recommendedCleanupCount == 0 || model.isCleaning)
            .help("Run \"gw clean\" (\(model.recommendedCleanupCount) recommended)")

            Button {
                model.close()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Close Worktree Status")
        }
        .padding(8)
    }

    @ViewBuilder
    private var content: some View {
        if let errorMessage = model.errorMessage, model.worktrees.isEmpty {
            statusMessage(systemImage: "exclamationmark.triangle", message: errorMessage)
        } else if model.isLoading && model.worktrees.isEmpty {
            statusMessage(systemImage: nil, message: "Loading…", isProgress: true)
        } else if model.worktrees.isEmpty {
            statusMessage(
                systemImage: directory == nil ? "questionmark.folder" : "square.stack.3d.up.slash",
                message: directory == nil
                    ? "No focused surface's directory is known yet."
                    : "No worktrees found.")
        } else {
            VStack(spacing: 0) {
                if let errorMessage = model.errorMessage {
                    warningBanner(errorMessage)
                }
                worktreeList
            }
        }
    }

    private var worktreeList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(model.worktrees) { worktree in
                    WorktreeStatusRowView(worktree: worktree)
                        .padding(.horizontal, 8)
                    Divider()
                }
            }
        }
    }

    private func warningBanner(_ message: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle")
            Text(message)
                .lineLimit(2)
        }
        .font(.caption)
        .foregroundStyle(.orange)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(Color.orange.opacity(0.1))
    }

    private func statusMessage(systemImage: String?, message: String, isProgress: Bool = false) -> some View {
        VStack(spacing: 12) {
            if isProgress {
                ProgressView()
            } else if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 32))
                    .foregroundStyle(.secondary)
            }
            Text(message)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Shows a confirmation listing the recommended worktrees before
    /// running `gw clean` — an app-modal alert, same pattern as
    /// `MarkdownPreviewPane`'s `NSOpenPanel` (no window handle is threaded
    /// through this SwiftUI view, so a sheet isn't practical here).
    private func confirmAndClean() {
        let targets = model.worktrees.filter { $0.cleanup.recommendation == "recommended" }
        guard !targets.isEmpty else { return }

        let alert = NSAlert()
        alert.messageText = "Remove \(targets.count) worktree\(targets.count == 1 ? "" : "s")?"
        let lines = targets.map { worktree -> String in
            if let pr = worktree.github.pr {
                return "• \(worktree.displayName) (#\(pr.number))"
            }
            return "• \(worktree.displayName)"
        }
        alert.informativeText = lines.joined(separator: "\n")
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Remove")
        alert.addButton(withTitle: "Cancel")

        guard alert.runModal() == .alertFirstButtonReturn else { return }
        model.clean()
    }
}
