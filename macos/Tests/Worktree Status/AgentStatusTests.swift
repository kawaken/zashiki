import Foundation
import Testing
@testable import Zashiki

struct AgentStatusTests {
    @Test func detectsClaudeFromForegroundProcess() {
        let result = AgentDetector.detect(.init(
            processName: "claude",
            screenContents: "Claude Code\n❯",
            inputLine: "",
            previousScreenContents: nil))

        #expect(result == .init(provider: .claude, activity: .idle))
    }

    @Test func detectsCodexFromForegroundProcess() {
        let result = AgentDetector.detect(.init(
            processName: "/opt/homebrew/bin/codex",
            screenContents: "OpenAI Codex\n›",
            inputLine: "",
            previousScreenContents: nil))

        #expect(result == .init(provider: .codex, activity: .idle))
    }

    @Test func detectsWrappedClaudeFromScreenBranding() {
        let result = AgentDetector.detect(.init(
            processName: "node",
            screenContents: "Claude Code\nWorking…",
            inputLine: "",
            previousScreenContents: nil))

        #expect(result == .init(provider: .claude, activity: .working))
    }

    @Test func detectsVersionedClaudeExecutable() {
        let result = AgentDetector.detect(.init(
            processName: "/Users/test/.local/share/claude/versions/2.1.259",
            screenContents: "Thinking…",
            inputLine: "",
            previousScreenContents: nil))

        #expect(result == .init(provider: .claude, activity: .working))
    }

    @Test func detectsPermissionPromptAsWaiting() {
        let result = AgentDetector.detect(.init(
            processName: "codex",
            screenContents: "Allow this command?\nPermission required: allow / deny",
            inputLine: "",
            previousScreenContents: nil))

        #expect(result == .init(provider: .codex, activity: .waiting))
    }

    @Test func detectsTypedInputAsWaiting() {
        let result = AgentDetector.detect(.init(
            processName: "claude",
            screenContents: "Claude Code\n❯ inspect this",
            inputLine: "inspect this",
            previousScreenContents: nil))

        #expect(result == .init(provider: .claude, activity: .waiting))
    }

    @Test func detectsRecentScreenChangeAsWorking() {
        let result = AgentDetector.detect(.init(
            processName: "codex",
            screenContents: "OpenAI Codex\nApplying patch",
            inputLine: "",
            previousScreenContents: "OpenAI Codex\nReading files"))

        #expect(result == .init(provider: .codex, activity: .working))
    }

    @Test func returnsUnknownForUnrecognizedKnownAgentScreen() {
        let result = AgentDetector.detect(.init(
            processName: "claude",
            screenContents: "Claude Code\nA new UI we do not know yet",
            inputLine: "",
            previousScreenContents: nil))

        #expect(result == .init(provider: .claude, activity: .unknown))
    }

    @Test func ignoresNonAgentProcess() {
        let result = AgentDetector.detect(.init(
            processName: "zsh",
            screenContents: "❯",
            inputLine: "",
            previousScreenContents: nil))

        #expect(result == nil)
    }
}
