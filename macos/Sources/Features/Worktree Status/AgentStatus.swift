import Foundation

/// The coding-agent providers that Zashiki can identify inside a Surface.
enum AgentProvider: String, Equatable {
    case claude
    case codex

    var displayName: String {
        switch self {
        case .claude: return "Claude Code"
        case .codex: return "Codex"
        }
    }

    var processNames: [String] {
        switch self {
        case .claude: return ["claude", "claude-code"]
        case .codex: return ["codex", "codex-cli"]
        }
    }
}

/// The best-effort activity state inferred from a Surface's foreground agent.
enum AgentActivity: String, Equatable {
    case working
    case waiting
    case idle
    case unknown

    var displayName: String {
        rawValue.capitalized
    }
}

struct AgentDetection: Equatable {
    let provider: AgentProvider
    let activity: AgentActivity
}

/// Input to the provider/status detector. Keeping this value type independent
/// of AppKit makes the heuristics straightforward to test with fixtures.
struct AgentDetectionInput: Equatable {
    let processName: String?
    let screenContents: String
    let inputLine: String
}

enum AgentDetector {
    static func detect(_ input: AgentDetectionInput) -> AgentDetection? {
        guard let provider = provider(for: input) else { return nil }

        let bottom = bottomLines(of: input.screenContents)
        let lowerBottom = bottom.lowercased()
        let inputLine = input.inputLine.trimmingCharacters(in: .whitespacesAndNewlines)

        if isWaiting(lowerBottom: lowerBottom, inputLine: inputLine) {
            return .init(provider: provider, activity: .waiting)
        }

        if isIdle(lowerBottom: lowerBottom) {
            return .init(provider: provider, activity: .idle)
        }

        if isWorking(lowerBottom: lowerBottom) {
            return .init(provider: provider, activity: .working)
        }

        return .init(provider: provider, activity: .unknown)
    }

    private static func provider(for input: AgentDetectionInput) -> AgentProvider? {
        if let processName = input.processName?.lowercased(),
           let provider = AgentProvider.allCases.first(where: { provider in
               let executable = URL(fileURLWithPath: processName).lastPathComponent
               if provider.processNames.contains(executable) { return true }
               return provider == .claude && processName.contains("/claude/versions/")
           }) {
            return provider
        }

        // Some agent CLIs are launched through a runtime wrapper (for example
        // Node). Only use screen identification for those wrappers, never for
        // a Surface whose foreground process is unknown.
        guard input.processName != nil else { return nil }
        let lowerScreen = input.screenContents.lowercased()
        if lowerScreen.contains("claude code") { return .claude }
        if lowerScreen.contains("openai codex") || lowerScreen.contains("codex cli") { return .codex }
        return nil
    }

    private static func bottomLines(of text: String) -> String {
        text.split(whereSeparator: \.isNewline)
            .suffix(8)
            .joined(separator: "\n")
    }

    private static func isWaiting(lowerBottom: String, inputLine: String) -> Bool {
        if !inputLine.isEmpty { return true }

        // Claude Code's selection UI puts the question above the choices and
        // leaves this footer on the last line, so the question mark is not a
        // reliable indicator by itself.
        if lowerBottom.contains("enter to select") &&
            lowerBottom.contains("esc to cancel") {
            return true
        }

        let hasPermissionWord = lowerBottom.contains("permission") ||
            lowerBottom.contains("approve") ||
            lowerBottom.contains("approval")
        let hasDecisionWord = lowerBottom.contains("allow") ||
            lowerBottom.contains("deny") ||
            lowerBottom.contains("reject") ||
            lowerBottom.contains("yes/no") ||
            lowerBottom.contains("y/n")

        if hasPermissionWord && hasDecisionWord { return true }
        if lowerBottom.contains("press enter to continue") { return true }

        guard let lastLine = lowerBottom.split(whereSeparator: \.isNewline).last else { return false }
        let last = lastLine.trimmingCharacters(in: .whitespaces)
        return last.hasSuffix("?") || last.hasSuffix("？")
    }

    private static func isWorking(lowerBottom: String) -> Bool {
        [
            "thinking",
            "working",
            "generating",
            "running",
            "esc to interrupt",
            "ctrl+c to stop",
        ].contains { lowerBottom.contains($0) }
    }

    private static func isIdle(lowerBottom: String) -> Bool {
        guard let lastLine = lowerBottom.split(whereSeparator: \.isNewline).last else { return false }
        let last = lastLine.trimmingCharacters(in: .whitespaces)
        return last.contains("❯") || last.contains("›") || last == ">" || last.hasPrefix("> ")
    }
}

extension AgentProvider: CaseIterable {}
