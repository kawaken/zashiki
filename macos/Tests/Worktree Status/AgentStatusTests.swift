import Foundation
import Testing
@testable import Zashiki

struct AgentStatusTests {
    @Test func detectsClaudeFromForegroundProcess() {
        let result = AgentDetector.detect(.init(
            processName: "claude",
            screenContents: "Claude Code\n❯",
            inputLine: ""))

        #expect(result == .init(provider: .claude, activity: .idle))
    }

    @Test func detectsCodexFromForegroundProcess() {
        let result = AgentDetector.detect(.init(
            processName: "/opt/homebrew/bin/codex",
            screenContents: "OpenAI Codex\n›",
            inputLine: ""))

        #expect(result == .init(provider: .codex, activity: .idle))
    }

    @Test func detectsClaudeBarePromptAsIdle() {
        let result = AgentDetector.detect(.init(
            processName: "claude",
            screenContents: "* Churned for 1m 17s · done 0:00\n>",
            inputLine: ""))

        #expect(result == .init(provider: .claude, activity: .idle))
    }

    @Test func detectsWrappedClaudeFromScreenBranding() {
        let result = AgentDetector.detect(.init(
            processName: "node",
            screenContents: "Claude Code\nWorking…",
            inputLine: ""))

        #expect(result == .init(provider: .claude, activity: .working))
    }

    @Test func detectsVersionedClaudeExecutable() {
        let result = AgentDetector.detect(.init(
            processName: "/Users/test/.local/share/claude/versions/2.1.259",
            screenContents: "Thinking…",
            inputLine: ""))

        #expect(result == .init(provider: .claude, activity: .working))
    }

    @Test func detectsPermissionPromptAsWaiting() {
        let result = AgentDetector.detect(.init(
            processName: "codex",
            screenContents: "Allow this command?\nPermission required: allow / deny",
            inputLine: ""))

        #expect(result == .init(provider: .codex, activity: .waiting))
    }

    @Test func detectsTypedInputAsWaiting() {
        let result = AgentDetector.detect(.init(
            processName: "claude",
            screenContents: "Claude Code\n❯ inspect this",
            inputLine: "inspect this"))

        #expect(result == .init(provider: .claude, activity: .waiting))
    }

    @Test func detectsClaudeSelectionPromptAsWaiting() {
        let result = AgentDetector.detect(.init(
            processName: "claude",
            screenContents: "選択式で質問してもらって良いですか？\n" +
                "次のアクション\n" +
                "1. そのままコミットする\n" +
                "2. コミットメッセージを提案してから確認\n" +
                "Enter to select · ↑/↓ to navigate · Esc to cancel",
            inputLine: ""))

        #expect(result == .init(provider: .claude, activity: .waiting))
    }

    @Test func returnsUnknownForUnrecognizedScreen() {
        let result = AgentDetector.detect(.init(
            processName: "claude",
            screenContents: "Claude Code\n新しい出力",
            inputLine: ""))

        #expect(result == .init(provider: .claude, activity: .unknown))
    }

    @Test func detectsKnownWorkingScreen() {
        let result = AgentDetector.detect(.init(
            processName: "codex",
            screenContents: "OpenAI Codex\nThinking…",
            inputLine: ""))

        #expect(result == .init(provider: .codex, activity: .working))
    }

    @Test func ignoresNonAgentProcess() {
        let result = AgentDetector.detect(.init(
            processName: "zsh",
            screenContents: "❯",
            inputLine: ""))

        #expect(result == nil)
    }
}
