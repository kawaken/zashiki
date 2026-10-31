import Foundation
import GhosttyKit
import Testing
@testable import Zashiki

@MainActor
struct ClipboardRequestCompletionTests {
    private let surface = UnsafeMutableRawPointer(bitPattern: 0x1234)!
    private let state = UnsafeMutableRawPointer(bitPattern: 0x5678)!

    @Test func overlappingRequestsCompleteAfterCallbackReturns() async {
        var callbackActive = true
        var responses = 0
        for _ in 0..<100 {
            let response = ClipboardRequestCompletion(surface: surface, currentSurface: { surface }, state: state, completeRequest: { actualSurface, data, actualState, confirmed in
                #expect(!callbackActive)
                #expect(actualSurface == surface)
                #expect(actualState == state)
                #expect(data.isEmpty)
                #expect(confirmed)
                responses += 1
            })
            response.denyDeferred()
        }
        #expect(responses == 0)
        callbackActive = false
        await nextMainTurn()
        #expect(responses == 100)
    }

    @Test func closedOrReplacedSurfaceSkipsDeferredCompletion() async {
        for replacement in [nil, UnsafeMutableRawPointer(bitPattern: 0x9999)] {
            var current: ghostty_surface_t? = surface
            var responses = 0
            let response = ClipboardRequestCompletion(surface: surface, currentSurface: { current }, state: state, completeRequest: { _, _, _, _ in responses += 1 })
            response.denyDeferred()
            current = replacement
            await nextMainTurn()
            #expect(responses == 0)
        }
    }

    @Test(arguments: ["日本語\ntext", ""])
    func approvalAndCancellationCompleteOnce(data: String) async {
        var responses: [String] = []
        let response = ClipboardRequestCompletion(surface: surface, currentSurface: { surface }, state: state, completeRequest: { _, text, _, confirmed in
            #expect(confirmed)
            responses.append(text)
        })
        response.complete(data: data)
        response.complete(data: "duplicate")
        response.denyDeferred()
        await nextMainTurn()
        #expect(responses == [data])
    }

    private func nextMainTurn() async {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async { continuation.resume() }
        }
    }
}
