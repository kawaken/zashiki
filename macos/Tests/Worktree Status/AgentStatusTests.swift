import Foundation
import Testing
@testable import Zashiki

struct AgentStatusTests {
    @Test @MainActor func togglesAgentsPaneVisibility() {
        let model = AgentStatusModel()
        #expect(!model.isVisible)

        model.open()
        #expect(model.isVisible)

        model.toggle()
        #expect(!model.isVisible)

        model.toggle()
        model.close()
        #expect(!model.isVisible)
    }

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

    @Test func detectsPromptBeforeAgentStatusBarAsIdle() {
        let result = AgentDetector.detect(.init(
            processName: "claude",
            screenContents: ">\n" +
                "gw [main] [So5] C:_ 5:_ 7:_\n" +
                "∥ plan mode on (shift+tab to cycle) · ←for agents",
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

    @Test func detectsConfirmationPromptWithCancelFooterAsWaiting() {
        let result = AgentDetector.detect(.init(
            processName: "codex",
            screenContents: "Do you want to make this edit to main.go?\nEsc to cancel",
            inputLine: ""))

        #expect(result == .init(provider: .codex, activity: .waiting))
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

    @Test func detectsThoughtForProgressAsWorking() {
        let result = AgentDetector.detect(.init(
            processName: "codex",
            screenContents: "Schlepping… (17s · thought for 3s)",
            inputLine: ""))

        #expect(result == .init(provider: .codex, activity: .working))
    }

    @Test func detectsShellCommandProgressOutsideRecentFooterAsWorking() {
        let output = (0..<9).map { "output line \($0)" }.joined(separator: "\n")
        let result = AgentDetector.detect(.init(
            processName: "codex",
            screenContents: "Running 1 shell command\n" + output,
            inputLine: ""))

        #expect(result == .init(provider: .codex, activity: .working))
    }

    @Test func idlePromptTakesPrecedenceOverStaleWorkingText() {
        let result = AgentDetector.detect(.init(
            processName: "codex",
            screenContents: "Running 1 shell command\n>\n" +
                "gw [main] [So5] C:_ 5:_ 7:_\n" +
                "∥ plan mode on (shift+tab to cycle) · ←for agents",
            inputLine: ""))

        #expect(result == .init(provider: .codex, activity: .idle))
    }

    @Test func ignoresNonAgentProcess() {
        let result = AgentDetector.detect(.init(
            processName: "zsh",
            screenContents: "❯",
            inputLine: ""))

        #expect(result == nil)
    }
    @Test func parsesClaudeConversationMarkersAndRows() {
        let entries = AgentConversationParser.parse(
            provider: .claude,
            screenContents: "Claude Code\n❯ inspect the build\n⏺ The build is clean\n❯",
            totalRows: 20)

        #expect(entries.map(\.kind) == [.user, .assistant])
        #expect(entries.map(\.preview) == ["inspect the build", "The build is clean"])
        #expect(entries.map(\.row) == [17, 18])
    }

    @Test func usesStableClaudeEntryIDsAcrossViewportRows() {
        let first = AgentConversationParser.parse(
            provider: .claude,
            screenContents: "❯ inspect the build\n⏺ The build is clean",
            totalRows: 2)
        let second = AgentConversationParser.parse(
            provider: .claude,
            screenContents: "\n\n❯ inspect the build\n⏺ The build is clean",
            totalRows: 4)

        #expect(first.map(\.id) == second.map(\.id))
    }

    @Test func parsesCodexMultiLineResponse() {
        let entries = AgentConversationParser.parse(
            provider: .codex,
            screenContents: "OpenAI Codex\n› fix the test\n• I found the failing assertion.\n  It is in the fixture.\n›",
            totalRows: 4)

        #expect(entries.count == 2)
        #expect(entries[0].kind == .user)
        #expect(entries[1].kind == .assistant)
        #expect(entries[1].preview == "I found the failing assertion. It is in the fixture.")
        #expect(entries[1].row == 2)
    }

    @Test func ignoresUnknownConversationMarkers() {
        let entries = AgentConversationParser.parse(
            provider: .codex,
            screenContents: "OpenAI Codex\nplain output\n❯ not a Codex marker",
            totalRows: 3)

        #expect(entries.isEmpty)
    }
}
