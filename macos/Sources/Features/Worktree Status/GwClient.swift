import Foundation

/// Errors surfaced by `GwClient`. Each case maps to a distinct message in
/// `WorktreeStatusPane`.
enum GwClientError: Error {
    /// `gw` could not be found on `PATH`, in any known install location,
    /// or via `ZASHIKI_GW`.
    case binaryNotFound
    /// `gw` exited non-zero.
    case processFailed(exitCode: Int32, stderr: String)
    /// `gw` did not exit within `GwClient.timeout`.
    case timedOut
    /// `gw` exited zero but its stdout wasn't the JSON shape we expect.
    case decodingFailed(Error)
}

/// Runs `gw` as a subprocess and decodes its `--json` output.
///
/// Zashiki isn't sandboxed (see `Zashiki*.entitlements`), so spawning an
/// arbitrary `Process` is unrestricted; this is the first place in the app
/// that does so.
final class GwClient {
    /// How long to wait for `gw` before giving up. `gw list --json` is
    /// dominated by GitHub/agent lookups and takes ~5s in practice; the
    /// default leaves generous headroom for a cold `gh` auth check or a
    /// slow network. Overridable so tests don't have to wait 20s to see a
    /// timeout.
    private let timeout: TimeInterval

    /// Explicit binary path, set by tests. When `nil`, the path is
    /// resolved via `resolveBinaryPath()` on every call (so a `gw`
    /// installed after launch, or a `PATH` change, is picked up without
    /// relaunching Zashiki).
    private let binaryPathOverride: String?

    init(binaryPathOverride: String? = nil, timeout: TimeInterval = 20) {
        self.binaryPathOverride = binaryPathOverride
        self.timeout = timeout
    }

    /// Runs `gw list --json` in `directory`.
    func fetchWorktrees(directory: URL) async throws -> GwListOutput {
        let data = try await run(arguments: ["list", "--json"], directory: directory)
        do {
            return try JSONDecoder().decode(GwListOutput.self, from: data)
        } catch {
            throw GwClientError.decodingFailed(error)
        }
    }

    /// Runs `gw clean --json` (a real run, not `--dry-run`) in `directory`.
    /// Callers are expected to have already confirmed the candidate list
    /// with the user (e.g. via a prior `fetchWorktrees` + confirmation
    /// dialog) — this does not re-confirm.
    func clean(directory: URL) async throws -> GwCleanOutput {
        let data = try await run(arguments: ["clean", "--json"], directory: directory)
        do {
            return try JSONDecoder().decode(GwCleanOutput.self, from: data)
        } catch {
            throw GwClientError.decodingFailed(error)
        }
    }

    /// Spawns `gw <arguments>` in `directory` and returns its stdout,
    /// throwing if it fails to launch, exits non-zero, or exceeds
    /// `Self.timeout`.
    private func run(arguments: [String], directory: URL) async throws -> Data {
        guard let binaryPath = binaryPathOverride ?? Self.resolveBinaryPath() else {
            throw GwClientError.binaryNotFound
        }

        return try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: binaryPath)
            process.arguments = arguments
            process.currentDirectoryURL = directory

            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()
            process.standardOutput = stdoutPipe
            process.standardError = stderrPipe

            // `terminationHandler` and the timeout's `DispatchWorkItem` can
            // both race to resume `continuation`; only the first should
            // win.
            let resumeState = ResumeOnce(continuation: continuation)

            let timeoutItem = DispatchWorkItem {
                if process.isRunning {
                    process.terminate()
                }
                resumeState.resume(.failure(GwClientError.timedOut))
            }
            DispatchQueue.global(qos: .userInitiated).asyncAfter(
                deadline: .now() + timeout, execute: timeoutItem)

            process.terminationHandler = { process in
                timeoutItem.cancel()
                let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                guard process.terminationStatus == 0 else {
                    let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
                    let stderrText = String(data: stderrData, encoding: .utf8) ?? ""
                    resumeState.resume(.failure(
                        GwClientError.processFailed(
                            exitCode: process.terminationStatus, stderr: stderrText)))
                    return
                }
                resumeState.resume(.success(stdoutData))
            }

            do {
                try process.run()
            } catch {
                timeoutItem.cancel()
                resumeState.resume(.failure(GwClientError.binaryNotFound))
            }
        }
    }

    /// Resolves the `gw` binary, checked in order: `ZASHIKI_GW` (explicit
    /// override), `PATH`, then a handful of common install locations that
    /// a GUI app's `PATH` often lacks (`go install`'s default `GOBIN`, plus
    /// the usual Homebrew/local-bin spots).
    static func resolveBinaryPath() -> String? {
        let fm = FileManager.default

        if let explicit = ProcessInfo.processInfo.environment["ZASHIKI_GW"],
            fm.isExecutableFile(atPath: explicit) {
            return explicit
        }

        if let pathEnv = ProcessInfo.processInfo.environment["PATH"] {
            for dir in pathEnv.split(separator: ":") {
                let candidate = "\(dir)/gw"
                if fm.isExecutableFile(atPath: candidate) {
                    return candidate
                }
            }
        }

        let home = NSHomeDirectory()
        let knownDirs = [
            "/opt/homebrew/bin",
            "/usr/local/bin",
            "\(home)/go/bin",
            "\(home)/.local/bin",
        ]
        for dir in knownDirs {
            let candidate = "\(dir)/gw"
            if fm.isExecutableFile(atPath: candidate) {
                return candidate
            }
        }

        return nil
    }
}

/// Guards a `CheckedContinuation` against being resumed twice, which would
/// otherwise crash. `Process.terminationHandler` and a timeout timer both
/// hold a reference to the same continuation and race to resume it.
private final class ResumeOnce<T> {
    private let continuation: CheckedContinuation<T, Error>
    private let lock = NSLock()
    private var didResume = false

    init(continuation: CheckedContinuation<T, Error>) {
        self.continuation = continuation
    }

    func resume(_ result: Result<T, Error>) {
        lock.lock()
        defer { lock.unlock() }
        guard !didResume else { return }
        didResume = true
        continuation.resume(with: result)
    }
}
