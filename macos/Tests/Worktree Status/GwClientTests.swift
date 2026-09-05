import Foundation
import Testing
@testable import Zashiki

/// Exercises `GwClient` against fake `gw` executables (shell scripts) so
/// these tests don't depend on `gw` actually being installed, and can
/// force failure/timeout paths that a real `gw` wouldn't reliably hit.
struct GwClientTests {
    private static let minimalListJSON = """
        {
          "schema_version": 2,
          "repository": { "path": "/tmp/example", "branch": "main" },
          "worktrees": []
        }
        """

    @Test func fetchWorktreesDecodesSuccessfulOutput() async throws {
        let script = try makeScript(exitCode: 0, stdout: Self.minimalListJSON)
        defer { try? FileManager.default.removeItem(at: script) }

        let client = GwClient(binaryPathOverride: script.path)
        let output = try await client.fetchWorktrees(directory: FileManager.default.temporaryDirectory)

        #expect(output.repository.branch == "main")
        #expect(output.worktrees.isEmpty)
    }

    @Test func fetchWorktreesThrowsBinaryNotFoundForMissingPath() async throws {
        let client = GwClient(binaryPathOverride: "/nonexistent/path/to/gw")

        await #expect(throws: GwClientError.self) {
            _ = try await client.fetchWorktrees(directory: FileManager.default.temporaryDirectory)
        }
    }

    @Test func fetchWorktreesThrowsProcessFailedOnNonZeroExit() async throws {
        let script = try makeScript(exitCode: 1, stderr: "not a git repository")
        defer { try? FileManager.default.removeItem(at: script) }

        let client = GwClient(binaryPathOverride: script.path)

        do {
            _ = try await client.fetchWorktrees(directory: FileManager.default.temporaryDirectory)
            Issue.record("expected processFailed to be thrown")
        } catch GwClientError.processFailed(let exitCode, let stderr) {
            #expect(exitCode == 1)
            #expect(stderr.contains("not a git repository"))
        }
    }

    @Test func fetchWorktreesThrowsDecodingFailedOnMalformedJSON() async throws {
        let script = try makeScript(exitCode: 0, stdout: "not json")
        defer { try? FileManager.default.removeItem(at: script) }

        let client = GwClient(binaryPathOverride: script.path)

        do {
            _ = try await client.fetchWorktrees(directory: FileManager.default.temporaryDirectory)
            Issue.record("expected decodingFailed to be thrown")
        } catch GwClientError.decodingFailed {
            // Expected.
        }
    }

    @Test func fetchWorktreesThrowsTimedOutWhenExceedingTimeout() async throws {
        let script = try makeScript(exitCode: 0, stdout: Self.minimalListJSON, sleepSeconds: 2)
        defer { try? FileManager.default.removeItem(at: script) }

        let client = GwClient(binaryPathOverride: script.path, timeout: 0.2)

        await #expect(throws: GwClientError.self) {
            _ = try await client.fetchWorktrees(directory: FileManager.default.temporaryDirectory)
        }
    }

    @Test func cleanDecodesRemovedList() async throws {
        let json = """
            {
              "schema_version": 2,
              "repository": { "path": "/tmp/example", "branch": "main" },
              "mode": "apply",
              "removed": ["/tmp/example-worktrees/done-feature"]
            }
            """
        let script = try makeScript(exitCode: 0, stdout: json)
        defer { try? FileManager.default.removeItem(at: script) }

        let client = GwClient(binaryPathOverride: script.path)
        let output = try await client.clean(directory: FileManager.default.temporaryDirectory)

        #expect(output.mode == "apply")
        #expect(output.removed == ["/tmp/example-worktrees/done-feature"])
    }

    // MARK: - Fake `gw` executable

    /// Writes a shell script standing in for `gw`: it prints `stdout` to
    /// stdout, `stderr` to stderr, optionally sleeps first, then exits
    /// with `exitCode`.
    private func makeScript(
        exitCode: Int32,
        stdout: String = "",
        stderr: String = "",
        sleepSeconds: Double = 0
    ) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("gw-fake-\(UUID().uuidString)")
        let script = """
            #!/bin/sh
            sleep \(sleepSeconds)
            printf '%s' \(shellQuote(stdout))
            printf '%s' \(shellQuote(stderr)) >&2
            exit \(exitCode)
            """
        try script.write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        return url
    }

    private func shellQuote(_ string: String) -> String {
        "'" + string.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
