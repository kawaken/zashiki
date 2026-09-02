import Foundation
import Testing
@testable import Zashiki

/// Fixtures are trimmed real output from `gw list --json` / `gw clean
/// --json` (see https://github.com/kawaken/gw), covering the shapes that
/// showed up in practice: a PR-less/detached/agent-less worktree, a locked
/// worktree with an active session, and a merged-PR worktree recommended
/// for cleanup.
struct GwSchemaTests {
    @Test func decodesFullListOutput() throws {
        let output = try decode(GwListOutput.self, json: Self.listFixture)

        #expect(output.schemaVersion == 1)
        #expect(output.repository.path == "/Users/kawaken/projects/example")
        #expect(output.repository.branch == "main")
        #expect(output.worktrees.count == 3)
        #expect(output.sources?.github == "gh")
        #expect(output.sources?.agent == "local-state")
    }

    @Test func decodesWorktreeWithNoPRAndNoAgentProvider() throws {
        let output = try decode(GwListOutput.self, json: Self.listFixture)
        let worktree = try #require(output.worktrees.first { $0.branch == "review-me" })

        #expect(worktree.github.pr == nil)
        #expect(worktree.agent.provider == nil)
        #expect(worktree.agent.lifecycle == "unknown")
        #expect(worktree.cleanup.recommendation == "review")
        #expect(worktree.locked == false)
        #expect(worktree.detached == false)
        #expect(worktree.displayName == "review-me")
    }

    @Test func decodesLockedWorktreeWithActiveAgent() throws {
        let output = try decode(GwListOutput.self, json: Self.listFixture)
        let worktree = try #require(output.worktrees.first { $0.branch == "wip-feature" })

        #expect(worktree.locked)
        #expect(worktree.agent.provider == "claude")
        #expect(worktree.agent.lifecycle == "active")
        #expect(worktree.cleanup.recommendation == "keep")
        #expect(worktree.cleanup.reasons == ["worktree_locked"])
    }

    @Test func decodesMergedPRRecommendedForCleanup() throws {
        let output = try decode(GwListOutput.self, json: Self.listFixture)
        let worktree = try #require(output.worktrees.first { $0.branch == "done-feature" })

        let pr = try #require(worktree.github.pr)
        #expect(pr.number == 84)
        #expect(pr.state == "MERGED")
        #expect(pr.url == "https://github.com/kawaken/example/pull/84")
        #expect(worktree.cleanup.recommendation == "recommended")
        #expect(worktree.cleanup.reasons == ["pull_request_merged", "worktree_clean"])
    }

    @Test func providesHumanReadableTooltips() throws {
        let output = try decode(GwListOutput.self, json: Self.listFixture)
        let worktree = try #require(output.worktrees.first { $0.branch == "done-feature" })

        #expect(worktree.displayNameHelp == "done-feature\nPath: /tmp/example-worktrees/done-feature")
        #expect(worktree.gitStatusHelp == "Git: Clean (no changes)")
        #expect(worktree.upstreamHelp == "Upstream: Up to date")
        #expect(worktree.agentHelp == "Agent: Codex\nLifecycle: Ended\nActivity: Unknown")
        #expect(worktree.pullRequestHelp == "Pull request #84: Ship the thing\nState: Merged\nGitHub: Available")
        #expect(worktree.lockHelp == "Locked: this worktree is protected from cleanup")
        #expect(worktree.cleanupHelp == "Cleanup: Recommended\nReason: Pull Request Merged, Worktree Clean")
    }

    @Test func tooltipsExplainUnknownAndErrorStates() throws {
        let json = """
        {
          "path": "/tmp/dirty-worktree",
          "branch": "dirty-worktree",
          "git": { "clean": false, "status_error": "permission denied", "ahead": 2, "behind": 1 },
          "github": { "pr": null, "status": "degraded" },
          "agent": { "lifecycle": "hibernating", "activity": "mystery" },
          "cleanup": { "recommendation": "quarantine", "reasons": ["needs_manual_review"] }
        }
        """
        let worktree = try decode(GwWorktree.self, json: json)

        #expect(worktree.gitStatusHelp == "Git: Unable to determine status\nError: permission denied")
        #expect(worktree.upstreamHelp == "Upstream: 2 ahead, 1 behind")
        #expect(worktree.agentHelp == "Agent: None detected\nLifecycle: Hibernating\nActivity: Mystery")
        #expect(worktree.pullRequestHelp == nil)
        #expect(worktree.cleanupHelp == "Cleanup: Quarantine\nReason: Needs Manual Review")
    }

    @Test func displayNameFallsBackToShortHeadWhenDetached() throws {
        let json = """
        {
          "path": "/tmp/detached-worktree",
          "detached": true,
          "head": "cef7975bb9a55ad0c4b6a730675e43c8b014104f",
          "git": { "clean": true },
          "github": { "pr": null, "status": "available" },
          "agent": { "lifecycle": "unknown", "activity": "unknown" },
          "cleanup": { "recommendation": "review" }
        }
        """
        let worktree = try decode(GwWorktree.self, json: json)

        #expect(worktree.branch == nil)
        #expect(worktree.detached)
        #expect(worktree.displayName == "cef7975")
    }

    @Test func decodesCleanDryRunOutput() throws {
        let json = """
        {
          "schema_version": 1,
          "repository": { "path": "/tmp/example", "branch": "main" },
          "mode": "dry-run",
          "candidates": [\(Self.doneFeatureWorktreeFixture)]
        }
        """
        let output = try decode(GwCleanOutput.self, json: json)

        #expect(output.mode == "dry-run")
        #expect(output.candidates?.count == 1)
        #expect(output.removed == nil)
    }

    @Test func decodesCleanApplyOutput() throws {
        let json = """
        {
          "schema_version": 1,
          "repository": { "path": "/tmp/example", "branch": "main" },
          "mode": "apply",
          "removed": ["/tmp/example-worktrees/done-feature"]
        }
        """
        let output = try decode(GwCleanOutput.self, json: json)

        #expect(output.mode == "apply")
        #expect(output.candidates == nil)
        #expect(output.removed == ["/tmp/example-worktrees/done-feature"])
    }

    @Test func unknownEnumLikeStringsDecodeWithoutThrowing() throws {
        // A future `gw` might introduce recommendation/lifecycle/state
        // values this app doesn't know about yet; these are decoded as
        // plain strings (see GwSchema.swift), so decoding must still
        // succeed and callers fall through their `switch`'s `default`.
        let json = """
        {
          "path": "/tmp/example",
          "git": { "clean": true },
          "github": { "pr": null, "status": "degraded" },
          "agent": { "provider": "some-future-agent", "lifecycle": "hibernating", "activity": "mystery" },
          "cleanup": { "recommendation": "quarantine" }
        }
        """
        let worktree = try decode(GwWorktree.self, json: json)

        #expect(worktree.github.status == "degraded")
        #expect(worktree.agent.lifecycle == "hibernating")
        #expect(worktree.cleanup.recommendation == "quarantine")
    }

    // MARK: - Fixtures

    private static let doneFeatureWorktreeFixture = """
        {
          "path": "/tmp/example-worktrees/done-feature",
          "branch": "done-feature",
          "head": "7e9176ed792133ee5bb3dad8ddfe782d67607e8d",
          "git": { "clean": true, "last_commit_at": "2026-08-29T15:54:33+09:00" },
          "github": {
            "pr": {
              "number": 84,
              "title": "Ship the thing",
              "state": "MERGED",
              "merged_at": "2026-08-29T12:34:22Z",
              "url": "https://github.com/kawaken/example/pull/84",
              "head_branch": "done-feature"
            },
            "status": "available"
          },
          "agent": {
            "provider": "codex",
            "session_id": "01a04c13-bce2-78b3-b437-1ce0c056925a",
            "lifecycle": "ended",
            "activity": "unknown",
            "observed_at": "2026-08-30T03:06:53.694733Z"
          },
          "cleanup": { "recommendation": "recommended", "reasons": ["pull_request_merged", "worktree_clean"] }
        }
        """

    private static let listFixture = """
        {
          "schema_version": 1,
          "repository": { "path": "/Users/kawaken/projects/example", "branch": "main" },
          "sources": { "github": "gh", "agent": "local-state" },
          "worktrees": [
            \(doneFeatureWorktreeFixture),
            {
              "path": "/tmp/example-worktrees/review-me",
              "branch": "review-me",
              "head": "cef7975bb9a55ad0c4b6a730675e43c8b014104f",
              "git": { "clean": true, "last_commit_at": "2026-08-27T01:28:34+09:00" },
              "github": { "pr": null, "status": "available" },
              "agent": { "lifecycle": "unknown", "activity": "unknown" },
              "cleanup": { "recommendation": "review", "reasons": ["no_pull_request"] }
            },
            {
              "path": "/tmp/example-worktrees/wip-feature",
              "branch": "wip-feature",
              "head": "53c6c1d6d8266bb24bce0eff2f0841947eb816fe",
              "locked": true,
              "git": { "clean": true, "ahead": 0, "behind": 0, "last_commit_at": "2026-08-31T00:04:39+09:00" },
              "github": { "pr": null, "status": "available" },
              "agent": {
                "provider": "claude",
                "session_id": "6828ae27-5186-5469-ac33-4990e550ac5e",
                "lifecycle": "active",
                "activity": "unknown",
                "observed_at": "2026-08-30T15:00:35.251073Z"
              },
              "cleanup": { "recommendation": "keep", "reasons": ["worktree_locked"] }
            }
          ]
        }
        """
}

private func decode<T: Decodable>(_ type: T.Type, json: String) throws -> T {
    try JSONDecoder().decode(T.self, from: Data(json.utf8))
}
