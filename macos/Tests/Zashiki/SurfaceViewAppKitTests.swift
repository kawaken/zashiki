@testable import Zashiki
import GhosttyKit
import Testing

struct SurfaceViewAppKitTests {
    @MainActor
    @Test(arguments: ["日本語", "dictated text", "😀", "first\nsecond"])
    func inputMethodCommitsUseUnmodifiedKeyEvents(text: String) {
        var calls = 0
        let handled = Zashiki.SurfaceView.sendCommittedText(GHOSTTY_ACTION_PRESS, text: text) { event in
            calls += 1
            #expect(String(cString: event.text!) == text)
            #expect(event.action == GHOSTTY_ACTION_PRESS)
            #expect(event.mods == GHOSTTY_MODS_NONE)
            #expect(event.consumed_mods == GHOSTTY_MODS_NONE)
            #expect(!event.composing)
            #expect(event.keycode == 0)
            return true
        }
        #expect(handled)
        #expect(calls == 1)
    }

    @MainActor
    @Test func emptyCommitDoesNotSendKey() {
        #expect(!Zashiki.SurfaceView.sendCommittedText(GHOSTTY_ACTION_PRESS, text: "") { _ in
            Issue.record("Unexpected key event")
            return true
        })
    }

    @Test(arguments: [
        ("\u{0008}", true),
        ("\u{001F}", true),
        ("\u{007F}", false),
        (" ", false),
        ("h", false),
        ("", false),
        ("\u{0009}x", false),
        ("\u{0009}\u{0009}", false),
    ])
    func suppressesOnlySingleC0ControlTextWhileComposing(
        text: String,
        expected: Bool
    ) {
        #expect(
            Zashiki.SurfaceView.shouldSuppressComposingControlInput(
                text,
                composing: true
            ) == expected
        )
    }

    @Test func doesNotSuppressControlTextWhenNotComposing() {
        #expect(
            Zashiki.SurfaceView.shouldSuppressComposingControlInput(
                "\u{0008}",
                composing: false
            ) == false
        )
    }

    @Test func doesNotSuppressMissingText() {
        #expect(
            Zashiki.SurfaceView.shouldSuppressComposingControlInput(
                nil,
                composing: true
            ) == false
        )
    }
}
