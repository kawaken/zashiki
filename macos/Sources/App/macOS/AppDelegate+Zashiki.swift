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

    /// Look up the terminal window controller that currently owns the
    /// surface with the given Zashiki Surface ID (the same u64 value
    /// exposed to child processes as ZASHIKI_SURFACE_ID). Returns nil if
    /// no window currently has a matching surface (e.g. it was closed
    /// since the ID was captured).
    ///
    /// This is a different identifier from `zashikiSurface(id: UUID)`
    /// above (`Zashiki.SurfaceView.id`, a Swift-side UUID used for drag &
    /// drop). This one round-trips through libghostty's `Surface.id`,
    /// which is what's visible to shell processes.
    func terminalController(forZashikiSurfaceID id: UInt64) -> BaseTerminalController? {
        for window in NSApp.windows {
            guard let controller = window.windowController as? BaseTerminalController else {
                continue
            }

            for surface in controller.surfaceTree where surface.zashikiSurfaceID == id {
                return controller
            }
        }

        return nil
    }
}
