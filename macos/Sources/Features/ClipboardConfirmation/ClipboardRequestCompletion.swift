import Foundation
import GhosttyKit

/// A single response to the originating surface. All access is on the main thread.
@MainActor
final class ClipboardRequestCompletion {
    private let originalSurface: ghostty_surface_t
    private let currentSurface: () -> ghostty_surface_t?
    private let state: UnsafeMutableRawPointer?
    private let completeRequest: (ghostty_surface_t, String, UnsafeMutableRawPointer?, Bool) -> Void
    private var completed = false

    init(
        surface: ghostty_surface_t,
        currentSurface: @escaping () -> ghostty_surface_t?,
        state: UnsafeMutableRawPointer?,
        completeRequest: @escaping (ghostty_surface_t, String, UnsafeMutableRawPointer?, Bool) -> Void = {
            Zashiki.App.completeClipboardRequest($0, data: $1, state: $2, confirmed: $3)
        }
    ) {
        self.originalSurface = surface
        self.currentSurface = currentSurface
        self.state = state
        self.completeRequest = completeRequest
    }

    func complete(data: String) {
        guard !completed else { return }
        completed = true
        guard let surface = currentSurface(), surface == originalSurface else { return }
        completeRequest(surface, data, state, true)
    }

    func denyDeferred() {
        // The confirmation callback still owns the request on this stack.
        DispatchQueue.main.async { self.complete(data: "") }
    }
}
