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

            for surface in controller.allSurfaces where surface.id == id {
                return surface
            }
        }

        return nil
    }

    /// Look up the terminal window controller that currently owns the
    /// terminal identified by the given ID. Returns nil if no window
    /// currently has a matching terminal (e.g. it was closed after the ID
    /// was returned by the CLI).
    ///
    /// This is a different identifier from `zashikiSurface(id: UUID)`
    /// above (`Zashiki.SurfaceView.id`, a Swift-side UUID used for drag &
    /// drop). The ID is returned to CLI callers as the terminal ID.
    func terminalController(forTerminalID terminalID: UInt64) -> BaseTerminalController? {
        terminalTab(forTerminalID: terminalID)?.controller
    }

    /// Like `terminalController(forTerminalID:)`, but also returns the
    /// tab within that window that owns the surface.
    func terminalTab(
        forTerminalID terminalID: UInt64
    ) -> (controller: BaseTerminalController, tab: TerminalTab)? {
        for window in NSApp.windows {
            guard let controller = window.windowController as? BaseTerminalController else {
                continue
            }

            for tab in controller.tabs where tab.surfaceTree.contains(where: { $0.terminalID == terminalID }) {
                return (controller, tab)
            }
        }

        return nil
    }

    /// Resolve a caller's controlling terminal ID to the tab that owns its
    /// PTY. The TTY name is queried at CLI invocation time, so a
    /// long-lived process does not need to retain a terminal ID in its
    /// environment.
    func terminalTab(
        forTTYName ttyName: String
    ) -> (controller: BaseTerminalController, tab: TerminalTab, terminalID: UInt64)? {
        for window in NSApp.windows {
            guard let controller = window.windowController as? BaseTerminalController else {
                continue
            }

            for tab in controller.tabs {
                guard let surface = tab.surfaceTree.first(where: { $0.ttyName == ttyName }),
                      let terminalID = surface.terminalID else {
                    continue
                }
                return (controller, tab, terminalID)
            }
        }

        return nil
    }
}
