import SwiftUI

/// A single row in the Worktree Status pane, summarizing one `gw list`
/// entry. Only the branch/HEAD label is plain text — everything else is an
/// SF Symbol (with a tooltip for detail) so a row stays scannable in a
/// narrow side panel.
struct WorktreeStatusRowView: View {
    let worktree: GwWorktree

    var body: some View {
        HStack(spacing: 6) {
            gitStateIcon

            Text(worktree.displayName)
                .font(.system(.body, design: .monospaced))
                .lineLimit(1)
                .truncationMode(.middle)

            if worktree.locked {
                Image(systemName: "lock.fill")
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 4)

            aheadBehindLabel
            agentIcon
            pullRequestLabel
            cleanupIcon
        }
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .help(worktree.rowHelp)
        .appKitTooltip(worktree.rowHelp)
    }

    @ViewBuilder
    private var gitStateIcon: some View {
        if let statusError = worktree.git.statusError,
           !statusError.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
        } else if worktree.git.clean {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
        } else {
            Image(systemName: "circle.fill")
                .foregroundStyle(.orange)
        }
    }

    @ViewBuilder
    private var aheadBehindLabel: some View {
        let ahead = worktree.git.ahead ?? 0
        let behind = worktree.git.behind ?? 0
        if ahead > 0 || behind > 0 {
            HStack(spacing: 4) {
                if ahead > 0 {
                    Label("\(ahead)", systemImage: "arrow.up")
                }
                if behind > 0 {
                    Label("\(behind)", systemImage: "arrow.down")
                }
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var agentIcon: some View {
        Image(systemName: Self.agentSymbolName(for: worktree.agent.provider))
            .foregroundStyle(Self.agentColor(for: worktree.agent.lifecycle))
    }

    @ViewBuilder
    private var pullRequestLabel: some View {
        if let pr = worktree.github.pr, let url = URL(string: pr.url) {
            Link(destination: url) {
                Text("#\(pr.number)")
                    .font(.caption)
                    .foregroundStyle(Self.pullRequestColor(for: pr.state))
            }
        } else {
            Image(systemName: Self.pullRequestStatusSymbolName(for: worktree.github.status))
                .foregroundStyle(Self.pullRequestStatusColor(for: worktree.github.status))
        }
    }

    @ViewBuilder
    private var cleanupIcon: some View {
        Group {
            switch worktree.cleanup.recommendation {
            case "recommended":
                Image(systemName: "trash.circle.fill")
                    .foregroundStyle(.red)
            case "review":
                Image(systemName: "exclamationmark.circle.fill")
                    .foregroundStyle(.yellow)
            case "keep":
                Image(systemName: "checkmark.circle")
                    .foregroundStyle(.secondary)
            default:
                Image(systemName: "questionmark.circle")
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// `provider` is a raw string from `gw` (see `GwSchema.swift`); unknown
    /// values fall back to a generic icon rather than failing to render.
    private static func agentSymbolName(for provider: String?) -> String {
        guard let provider else { return "person.crop.circle" }
        switch provider {
        case "claude": return "sparkles"
        case "codex": return "cpu"
        default: return "questionmark.circle"
        }
    }

    private static func agentColor(for lifecycle: String) -> Color {
        switch lifecycle {
        case "active": return .green
        case "ended": return .secondary
        default: return .secondary.opacity(0.5)
        }
    }

    private static func pullRequestColor(for state: String) -> Color {
        switch state {
        case "OPEN": return .green
        case "MERGED": return .purple
        case "CLOSED": return .red
        default: return .secondary
        }
    }

    private static func pullRequestStatusSymbolName(for status: String) -> String {
        switch status {
        case "found": return "checkmark.circle.fill"
        case "not_found": return "minus.circle"
        case "unknown": return "questionmark.circle.fill"
        case "unavailable": return "exclamationmark.triangle.fill"
        default: return "questionmark.circle"
        }
    }

    private static func pullRequestStatusColor(for status: String) -> Color {
        switch status {
        case "found": return .green
        case "not_found": return .secondary
        case "unknown": return .orange
        case "unavailable": return .red
        default: return .secondary
        }
    }
}
