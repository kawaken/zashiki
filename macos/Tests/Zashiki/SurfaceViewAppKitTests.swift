@testable import Zashiki
import GhosttyKit
import Foundation
import Testing

struct SurfaceViewAppKitTests {
    private func unit(_ value: unichar) -> NSString {
        var value = value
        return NSString(characters: &value, length: 1)
    }

    @Test func decodesSplitSurrogatePairBeforeBridging() {
        var decoder = CommittedTextDecoder()
        #expect(decoder.decode(unit(0xD83D)) == "")
        #expect(decoder.decode(unit(0xDE00)) == "😀")
        #expect(decoder.decode(unit(0xDE00)) == "")
        #expect(decoder.decode("日本語😀") == "日本語😀")
    }

    @Test func rejectsUnpairedAndInterruptedSurrogates() {
        var decoder = CommittedTextDecoder()
        #expect(decoder.decode(unit(0xDE00)) == "")
        #expect(decoder.decode(unit(0xD83D)) == "")
        #expect(decoder.decode("a") == "a")
        #expect(decoder.decode(unit(0xDE00)) == "")
        #expect(decoder.decode(unit(0xD83D)) == "")
        #expect(decoder.decode(NSAttributedString(string: "日本")) == "日本")
        #expect(decoder.decode(unit(0xDE00)) == "")
        #expect(decoder.decode(unit(0xD83D)) == "")
        #expect(decoder.decode(42) == nil)
        #expect(decoder.decode(unit(0xDE00)) == "")
        #expect(decoder.decode(unit(0xD83D)) == "")
        decoder.reset()
        #expect(decoder.decode(unit(0xDE00)) == "")
    }

    @Test func latestLeadWinsAndCompletePairsClearPendingState() {
        var decoder = CommittedTextDecoder()
        #expect(decoder.decode(unit(0xD800)) == "")
        #expect(decoder.decode(unit(0xD83D)) == "")
        #expect(decoder.decode(unit(0xDE00)) == "😀")
        #expect(decoder.decode(unit(0xD800)) == "")
        #expect(decoder.decode("😀") == "😀")
        #expect(decoder.decode(unit(0xDC00)) == "")
    }

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
