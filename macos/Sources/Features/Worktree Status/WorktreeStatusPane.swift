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

    /// Every Surface in the terminal window. Agent detection is Surface-based,
    /// unlike the worktree list which is repository-based.
    let surfaces: [Zashiki.SurfaceView]

    @StateObject private var agentStatus = AgentStatusModel()

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
        }
        .background(Color(nsColor: .textBackgroundColor))
        .task(id: surfaces.map(\.id)) {
            await monitorAgents()
        }
        .onDisappear {
            agentStatus.clear()
        }
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
            .help(cleanupButtonHelp)
            .accessibilityValue(cleanupButtonHelp)

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
            VStack(spacing: 0) {
                agentSection
                statusMessage(systemImage: "exclamationmark.triangle", message: errorMessage)
            }
        } else if model.isLoading && model.worktrees.isEmpty {
            VStack(spacing: 0) {
                agentSection
                statusMessage(systemImage: nil, message: "Loading…", isProgress: true)
            }
        } else if model.worktrees.isEmpty {
            VStack(spacing: 0) {
                agentSection
                statusMessage(
                    systemImage: directory == nil ? "questionmark.folder" : "square.stack.3d.up.slash",
                    message: directory == nil
                        ? "No focused surface's directory is known yet."
                        : "No worktrees found.")
            }
        } else {
            VStack(spacing: 0) {
                if let errorMessage = model.errorMessage {
                    warningBanner(errorMessage)
                }
                agentSection
                worktreeList
            }
        }
    }

    @ViewBuilder
    private var agentSection: some View {
        if !agentStatus.agents.isEmpty {
            agentsSection
            Divider()
        }
    }

    private var agentsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "person.2.fill")
                    .foregroundStyle(.secondary)
                Text("Agents")
                    .font(.subheadline.weight(.semibold))
                Text("\(agentStatus.agents.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(agentStatus.agents) { agent in
                        AgentStatusRowView(agent: agent) {
                            focus(agent.surface)
                        }
                        .padding(.horizontal, 8)
                        Divider()
                    }
                }
            }
            .frame(maxHeight: 190)
        }
    }

    private func monitorAgents() async {
        while !Task.isCancelled {
            agentStatus.refresh(surfaces: surfaces)
            do {
                try await Task.sleep(nanoseconds: 750_000_000)
            } catch {
                return
            }
        }
    }

    private func focus(_ surface: Zashiki.SurfaceView) {
        surface.window?.makeKeyAndOrderFront(nil)
        if !NSApp.isActive {
            NSApp.activate(ignoringOtherApps: true)
        }
        Zashiki.moveFocus(to: surface)
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

    private var cleanupButtonHelp: String {
        if model.isCleaning {
            return "Removing recommended worktrees…"
        }
        if directory == nil {
            return "No focused worktree repository is available"
        }
        if model.isLoading && model.worktrees.isEmpty {
            return "Loading worktrees…"
        }

        let recommended = model.recommendedCleanupCount
        if recommended > 0 {
            let noun = recommended == 1 ? "worktree" : "worktrees"
            return "Run \"gw clean\" to remove \(recommended) recommended \(noun)"
        }

        let review = model.reviewCleanupCount
        if review > 0 {
            let noun = review == 1 ? "worktree needs" : "worktrees need"
            return "No worktrees are recommended for removal. \(review) \(noun) review, but none are eligible for automatic cleanup"
        }
        return "No worktrees are recommended for removal"
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
