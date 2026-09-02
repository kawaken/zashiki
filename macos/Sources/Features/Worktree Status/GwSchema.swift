import Foundation

/// Codable mirror of `gw list --json` / `gw clean --dry-run --json` / `gw
/// clean --json` (see https://github.com/kawaken/gw, `cmd/gw/main.go`).
///
/// Enum-like string fields (`cleanup.recommendation`, `agent.lifecycle`,
/// `agent.activity`, `agent.provider`, `github.status`, `github.pr.state`)
/// are decoded as plain `String`, not Swift `enum`s, so a minor `gw` update
/// that introduces a new value doesn't fail decoding for the whole
/// response. Call sites should `switch` on the raw string with a `default`
/// case.

/// Top-level output of `gw list --json`.
struct GwListOutput: Decodable {
    let schemaVersion: Int
    let repository: GwRepository
    let worktrees: [GwWorktree]
    let sources: GwSources?
    let errors: [GwResultError]?

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case repository
        case worktrees
        case sources
        case errors
    }
}

/// Top-level output of `gw clean --dry-run --json` / `gw clean --json`.
struct GwCleanOutput: Decodable {
    let schemaVersion: Int
    let repository: GwRepository
    /// `"dry-run"` or `"apply"` (raw string, see file header).
    let mode: String
    /// Populated for `--dry-run`: the worktrees that would be removed.
    let candidates: [GwWorktree]?
    /// Populated for a real run: paths of worktrees that were removed.
    let removed: [String]?
    let errors: [GwResultError]?

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case repository
        case mode
        case candidates
        case removed
        case errors
    }
}

struct GwRepository: Decodable {
    let path: String
    let branch: String?
}

struct GwWorktree: Decodable, Identifiable {
    let path: String
    let branch: String?
    let head: String?
    let detached: Bool
    let locked: Bool
    let git: GwGitState
    let github: GwGitHubState
    let agent: GwAgentState
    let cleanup: GwCleanupState

    var id: String { path }

    /// The label to show for this worktree: the branch name, or a
    /// shortened commit hash when detached (`branch` is absent/empty).
    var displayName: String {
        if let branch, !branch.isEmpty { return branch }
        if let head, head.count >= 7 { return String(head.prefix(7)) }
        return (path as NSString).lastPathComponent
    }

    /// Human-readable details for the branch/HEAD label. The full path is
    /// useful when multiple worktrees have similar branch names.
    var displayNameHelp: String {
        let location = "Path: \(path)"
        if detached || branch == nil || branch?.isEmpty == true {
            return "\(displayName)\nDetached HEAD\n\(location)"
        }
        return "\(displayName)\n\(location)"
    }

    var gitStatusHelp: String {
        if let statusError = git.statusError?.trimmingCharacters(in: .whitespacesAndNewlines),
           !statusError.isEmpty {
            return "Git: Unable to determine status\nError: \(statusError)"
        }
        return git.clean ? "Git: Clean (no changes)" : "Git: Dirty (uncommitted changes)"
    }

    var upstreamHelp: String {
        let ahead = git.ahead ?? 0
        let behind = git.behind ?? 0
        guard ahead > 0 || behind > 0 else { return "Upstream: Up to date" }

        var changes: [String] = []
        if ahead > 0 { changes.append("\(ahead) ahead") }
        if behind > 0 { changes.append("\(behind) behind") }
        return "Upstream: \(changes.joined(separator: ", "))"
    }

    var agentHelp: String {
        let provider = agent.provider.map(Self.humanized) ?? "None detected"
        return "Agent: \(provider)\nLifecycle: \(Self.humanized(agent.lifecycle))\nActivity: \(Self.humanized(agent.activity))"
    }

    var pullRequestHelp: String? {
        guard let pr = github.pr else { return nil }
        let title = pr.title.isEmpty ? "Untitled" : pr.title
        return "Pull request #\(pr.number): \(title)\nState: \(Self.humanized(pr.state))\nGitHub: \(Self.humanized(github.status))"
    }

    var lockHelp: String {
        "Locked: this worktree is protected from cleanup"
    }

    var cleanupHelp: String {
        let recommendation = Self.humanized(cleanup.recommendation)
        let reasons = cleanup.reasons?.compactMap { reason -> String? in
            let trimmed = reason.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : Self.humanized(trimmed)
        } ?? []
        let reasonText = reasons.isEmpty ? "None provided" : reasons.joined(separator: ", ")
        return "Cleanup: \(recommendation)\nReason: \(reasonText)"
    }

    /// Converts enum-like values from gw without assuming a fixed set of
    /// values. This keeps tooltips useful when gw adds a new value.
    static func humanized(_ value: String) -> String {
        value
            .split { $0 == "_" || $0 == "-" || $0 == " " }
            .map { $0.lowercased().capitalized }
            .joined(separator: " ")
    }

    enum CodingKeys: String, CodingKey {
        case path, branch, head, detached, locked, git, github, agent, cleanup
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        path = try c.decode(String.self, forKey: .path)
        branch = try c.decodeIfPresent(String.self, forKey: .branch)
        head = try c.decodeIfPresent(String.self, forKey: .head)
        detached = try c.decodeIfPresent(Bool.self, forKey: .detached) ?? false
        locked = try c.decodeIfPresent(Bool.self, forKey: .locked) ?? false
        git = try c.decode(GwGitState.self, forKey: .git)
        github = try c.decode(GwGitHubState.self, forKey: .github)
        agent = try c.decode(GwAgentState.self, forKey: .agent)
        cleanup = try c.decode(GwCleanupState.self, forKey: .cleanup)
    }
}

struct GwGitState: Decodable {
    let clean: Bool
    let statusError: String?
    let ahead: Int?
    let behind: Int?
    let lastCommitAt: String?

    enum CodingKeys: String, CodingKey {
        case clean
        case statusError = "status_error"
        case ahead
        case behind
        case lastCommitAt = "last_commit_at"
    }
}

struct GwGitHubState: Decodable {
    let pr: GwPullRequest?
    /// Raw string, e.g. `"available"`. See file header.
    let status: String
}

struct GwPullRequest: Decodable {
    let number: Int
    let title: String
    /// Raw string, e.g. `"OPEN"` / `"MERGED"` / `"CLOSED"`. See file header.
    let state: String
    let mergedAt: String?
    let url: String
    let headBranch: String

    enum CodingKeys: String, CodingKey {
        case number, title, state
        case mergedAt = "merged_at"
        case url
        case headBranch = "head_branch"
    }
}

struct GwAgentState: Decodable {
    /// Raw string, e.g. `"claude"` / `"codex"`. Absent when no session was
    /// ever observed for this worktree.
    let provider: String?
    let sessionID: String?
    /// Raw string, e.g. `"active"` / `"ended"` / `"unknown"`. See file header.
    let lifecycle: String
    /// Raw string. See file header.
    let activity: String
    let observedAt: String?

    enum CodingKeys: String, CodingKey {
        case provider
        case sessionID = "session_id"
        case lifecycle, activity
        case observedAt = "observed_at"
    }
}

struct GwCleanupState: Decodable {
    /// Raw string, e.g. `"recommended"` / `"review"` / `"keep"`. See file header.
    let recommendation: String
    let reasons: [String]?
}

struct GwSources: Decodable {
    let github: String?
    let agent: String?
}

struct GwResultError: Decodable {
    let source: String
    let code: String
    let message: String
}
