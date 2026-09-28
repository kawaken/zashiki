import Combine
import Darwin
import Foundation

enum AgentConversationEntryKind: String, Equatable {
    case user
    case assistant

    var displayName: String {
        switch self {
        case .user: return "User"
        case .assistant: return "Agent"
        }
    }
}

struct AgentConversationEntry: Identifiable, Equatable {
    let id: String
    let provider: AgentProvider
    let kind: AgentConversationEntryKind
    let preview: String
    let row: Int
}

/// Parses the small set of stable turn markers exposed by the Claude Code and
/// Codex TUIs. Unknown output is deliberately ignored: a false history marker
/// is more disruptive than an omitted one.
enum AgentConversationParser {
    static func parse(
        provider: AgentProvider,
        screenContents: String,
        totalRows: Int
    ) -> [AgentConversationEntry] {
        let lines = screenContents.split(separator: "\n", omittingEmptySubsequences: false)
        guard !lines.isEmpty else { return [] }

        let firstRow = max(0, totalRows - lines.count)
        var result: [AgentConversationEntry] = []
        var current: (kind: AgentConversationEntryKind, row: Int, text: String)?

        for (index, rawLine) in lines.enumerated() {
            let line = String(rawLine)
            if let marker = marker(for: provider, line: line) {
                append(
                    current,
                    provider: provider,
                    into: &result)
                current = marker.text.isEmpty
                    ? (marker.kind, firstRow + index, "")
                    : (marker.kind, firstRow + index, marker.text)
                continue
            }

            guard let existing = current, !existing.text.isEmpty else { continue }
            let content = normalized(line)
            guard !content.isEmpty else { continue }
            if existing.text.count < 240 {
                var updated = existing
                updated.text += " " + content
                updated.text = String(updated.text.prefix(240))
                current = updated
            }
        }

        append(current, provider: provider, into: &result)
        return result
    }

    private static func append(
        _ candidate: (kind: AgentConversationEntryKind, row: Int, text: String)?,
        provider: AgentProvider,
        into result: inout [AgentConversationEntry]
    ) {
        guard let candidate else { return }
        let preview = normalized(candidate.text)
        guard !preview.isEmpty else { return }

        // The row is relative to the currently rendered alternate-screen view and
        // changes every time the TUI scrolls. Keep it as navigation metadata, but
        // do not use it as the identity used to merge viewport snapshots.
        let id = "\(provider.rawValue):\(candidate.kind.rawValue):\(preview)"
        result.append(.init(
            id: id,
            provider: provider,
            kind: candidate.kind,
            preview: String(preview.prefix(120)),
            row: candidate.row))
    }

    private static func marker(
        for provider: AgentProvider,
        line: String
    ) -> (kind: AgentConversationEntryKind, text: String)? {
        let line = line.trimmingCharacters(in: .whitespaces)

        switch provider {
        case .claude:
            if let text = line.removingPrefix("❯") {
                return (.user, normalized(text))
            }
            if let text = line.removingPrefix(">") {
                return (.user, normalized(text))
            }
            if let text = line.removingPrefix("⏺") {
                return (.assistant, normalized(text))
            }
            if let text = line.removingPrefix("●") {
                return (.assistant, normalized(text))
            }

        case .codex:
            if let text = line.removingPrefix("›") {
                return (.user, normalized(text))
            }
            if let text = line.removingPrefix("•") {
                return (.assistant, normalized(text))
            }
            if let text = line.removingPrefix("◦") {
                return (.assistant, normalized(text))
            }
        }

        return nil
    }

    private static func normalized(_ value: String) -> String {
        value
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

@MainActor
final class AgentConversationHistory: ObservableObject {
    @Published private(set) var detection: AgentDetection?
    @Published private(set) var entries: [AgentConversationEntry] = []

    private var lastScreenContents: String?
    private var lastTotalRows: Int?
    private var lastDetection: AgentDetection?
    private var captureTask: Task<Void, Never>?
    private var settingsObserver: NSObjectProtocol?
    private var lastCapturedSourceScreen: String?

    init() {
        settingsObserver = NotificationCenter.default.addObserver(
            forName: .zashikiClaudeHistoryAutoScrollDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.cancelCapture()
        }
    }

    deinit {
        if let settingsObserver {
            NotificationCenter.default.removeObserver(settingsObserver)
        }
    }

    func refresh(surface: Zashiki.SurfaceView) {
        guard let foregroundPID = surface.surfaceModel?.foregroundPID,
              let processName = ProcessNameResolver.name(for: foregroundPID)
        else {
            clear()
            return
        }

        let screenContents = surface.cachedScreenContents.get()
        let inputLine = surface.cachedInputLineBeforeCursor.get()
        let detection = AgentDetector.detect(.init(
            processName: processName,
            screenContents: screenContents,
            inputLine: inputLine))

        guard let detection else {
            clear()
            return
        }

        self.detection = detection
        guard detection.provider == .claude else {
            cancelCapture()
            entries = []
            lastScreenContents = nil
            lastTotalRows = nil
            lastDetection = detection
            return
        }

        guard UserDefaults.zashiki.claudeCodeHistoryAutoScrollEnabled else {
            cancelCapture()
            updateEntries(screenContents: screenContents, totalRows: scrollbarTotalRows(surface))
            return
        }

        guard let scrollbar = surface.scrollbar else {
            entries = []
            lastScreenContents = nil
            lastTotalRows = nil
            return
        }
        let totalRows = Int(scrollbar.total)
        guard detection != lastDetection ||
                screenContents != lastScreenContents ||
                totalRows != lastTotalRows else {
            return
        }

        lastDetection = detection
        lastScreenContents = screenContents
        lastTotalRows = totalRows
        if entries.isEmpty {
            entries = AgentConversationParser.parse(
                provider: detection.provider,
                screenContents: screenContents,
                totalRows: totalRows)
        }

        if detection.activity == .idle,
           captureTask == nil,
           lastCapturedSourceScreen != screenContents {
            captureTask = Task { @MainActor [weak self, weak surface] in
                guard let self, let surface else { return }
                await self.captureHistory(on: surface)
            }
        }
    }

    func clear() {
        cancelCapture()
        detection = nil
        entries = []
        lastScreenContents = nil
        lastTotalRows = nil
        lastDetection = nil
        lastCapturedSourceScreen = nil
    }

    func focusAndScroll(to entry: AgentConversationEntry, on surface: Zashiki.SurfaceView) {
        guard UserDefaults.zashiki.claudeCodeHistoryAutoScrollEnabled,
              detection?.provider == .claude,
              detection?.activity == .idle,
              surface.surfaceModel?.mouseCaptured == true,
              captureTask == nil else { return }

        captureTask = Task { @MainActor [weak self, weak surface] in
            guard let self, let surface else { return }
            await self.navigate(to: entry, on: surface)
        }
    }

    private func updateEntries(screenContents: String, totalRows: Int) {
        let parsed = AgentConversationParser.parse(
            provider: .claude,
            screenContents: screenContents,
            totalRows: totalRows)
        entries = parsed
        lastScreenContents = screenContents
        lastTotalRows = totalRows
        lastDetection = detection
    }

    private func scrollbarTotalRows(_ surface: Zashiki.SurfaceView) -> Int {
        Int(surface.scrollbar?.total ?? 0)
    }

    private func cancelCapture() {
        captureTask?.cancel()
        captureTask = nil
        lastCapturedSourceScreen = nil
    }

    private func captureHistory(on surface: Zashiki.SurfaceView) async {
        guard UserDefaults.zashiki.claudeCodeHistoryAutoScrollEnabled,
              detection?.provider == .claude,
              detection?.activity == .idle,
              surface.surfaceModel?.mouseCaptured == true else {
            captureTask = nil
            return
        }

        let original = surface.cachedScreenContents.get()
        lastCapturedSourceScreen = original
        var previous = original
        var unchangedCount = 0

        defer {
            Task { @MainActor [weak self, weak surface] in
                guard let self, let surface else { return }
                await self.restore(originalScreen: original, on: surface)
                self.captureTask = nil
            }
        }

        for _ in 0..<32 {
            guard !Task.isCancelled,
                  UserDefaults.zashiki.claudeCodeHistoryAutoScrollEnabled,
                  detection?.provider == .claude,
                  detection?.activity == .idle else { return }

            surface.surfaceModel?.sendMouseScroll(.init(x: 0, y: 3))
            guard await waitForScreenUpdate() else { return }

            let screen = surface.cachedScreenContents.get()
            let totalRows = scrollbarTotalRows(surface)
            mergeEntries(from: screen, totalRows: totalRows, prepend: true)

            if screen == previous {
                unchangedCount += 1
                if unchangedCount >= 2 { return }
            } else {
                unchangedCount = 0
            }
            previous = screen
        }
    }

    private func navigate(to entry: AgentConversationEntry, on surface: Zashiki.SurfaceView) async {
        defer { captureTask = nil }

        var previous = surface.cachedScreenContents.get()
        for _ in 0..<32 {
            guard !Task.isCancelled,
                  UserDefaults.zashiki.claudeCodeHistoryAutoScrollEnabled,
                  detection?.provider == .claude,
                  detection?.activity == .idle else { return }

            let current = surface.cachedScreenContents.get()
            if AgentConversationParser.parse(
                provider: .claude,
                screenContents: current,
                totalRows: scrollbarTotalRows(surface)
            ).contains(where: { $0.id == entry.id }) {
                return
            }

            guard surface.surfaceModel?.mouseCaptured == true else { return }
            surface.surfaceModel?.sendMouseScroll(.init(x: 0, y: 3))
            guard await waitForScreenUpdate() else { return }

            let next = surface.cachedScreenContents.get()
            mergeEntries(from: next, totalRows: scrollbarTotalRows(surface), prepend: true)
            if next == previous { return }
            previous = next
        }
    }

    private func restore(originalScreen: String, on surface: Zashiki.SurfaceView) async {
        guard surface.surfaceModel?.mouseCaptured == true else { return }

        var previous: String?
        for _ in 0..<48 {
            guard !Task.isCancelled else { return }
            let current = surface.cachedScreenContents.get()
            if current == originalScreen { return }
            if let previous, current == previous { return }

            surface.surfaceModel?.sendMouseScroll(.init(x: 0, y: -3))
            guard await waitForScreenUpdate() else { return }
            previous = current
        }
    }

    private func mergeEntries(from screenContents: String, totalRows: Int, prepend: Bool = false) {
        let parsed = AgentConversationParser.parse(
            provider: .claude,
            screenContents: screenContents,
            totalRows: totalRows)
        guard !parsed.isEmpty else { return }

        var knownIDs = Set(entries.map(\.id))
        let newEntries = parsed.filter { knownIDs.insert($0.id).inserted }
        if prepend {
            entries.insert(contentsOf: newEntries, at: 0)
        } else {
            entries.append(contentsOf: newEntries)
        }
        lastScreenContents = screenContents
        lastTotalRows = totalRows
        lastDetection = detection
    }

    private func waitForScreenUpdate() async -> Bool {
        do {
            try await Task.sleep(nanoseconds: 700_000_000)
            return true
        } catch {
            return false
        }
    }
}

enum ProcessNameResolver {
    static func name(for pid: Int) -> String? {
        var buffer = [CChar](repeating: 0, count: 4096)
        let length = proc_pidpath(Int32(pid), &buffer, UInt32(buffer.count))
        guard length > 0 else { return nil }
        return String(cString: buffer)
    }
}

private extension String {
    func removingPrefix(_ prefix: String) -> String? {
        guard hasPrefix(prefix) else { return nil }
        return String(dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
    }
}
