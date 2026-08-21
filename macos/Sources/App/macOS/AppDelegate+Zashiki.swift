import AppKit

// MARK: Zashiki Delegate

/// This implements the Zashiki app delegate protocol which is used by the Zashiki
/// APIs for app-global information.
extension AppDelegate: Zashiki.Delegate {
    func zashikiSurface(id: UUID) -> Zashiki.SurfaceView? {
        for window in NSApp.windows {
            guard let controller = window.windowController as? BaseTerminalController else {
                continue
            }

            for surface in controller.surfaceTree where surface.id == id {
                return surface
            }
        }

        return nil
    }
}
