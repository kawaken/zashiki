import AppKit
import GhosttyKit

/// The base class for all standalone, "normal" terminal windows. This sets the basic
/// style and configuration of the window based on the app configuration.
class TerminalWindow: NSWindow {
    /// Posted when a terminal window awakes from nib.
    static let terminalDidAwake = Notification.Name("TerminalWindowDidAwake")

    /// Posted when a terminal window will close
    static let terminalWillCloseNotification = Notification.Name("TerminalWindowWillClose")

    /// This is the key in UserDefaults to use for the default `level` value. This is
    /// used by the manual float on top menu item feature.
    static let defaultLevelKey: String = "TerminalDefaultLevel"

    /// The configuration derived from the Zashiki config so we don't need to rely on references.
    private(set) var derivedConfig: DerivedConfig = .init()

    /// Whether this window supports the update accessory. If this is false, then views within this
    /// window should determine how to show update notifications.
    var supportsUpdateAccessory: Bool {
        // There is no title row to show it in, so the terminal view shows the
        // update overlay instead.
        false
    }

    /// Glass effect view for liquid glass background when transparency is enabled
    private var glassEffectView: NSView?

    /// Gets the terminal controller from the window controller.
    var terminalController: TerminalController? {
        windowController as? TerminalController
    }

    // MARK: NSWindow Overrides

    override func awakeFromNib() {
        // Notify that this terminal window has loaded
        NotificationCenter.default.post(name: Self.terminalDidAwake, object: self)

        tabbingMode = .disallowed

        // Our tab bar occupies the native titlebar. Disable Window Server's
        // automatic titlebar dragging: it can move the window before AppKit's
        // tab drag source receives the mouse events. WindowDragHandle requests
        // window movement explicitly with performDrag(with:).
        isMovable = false

        // All new windows are based on the app config at the time of creation.
        guard let appDelegate = NSApp.delegate as? AppDelegate else { return }
        let config = appDelegate.ghostty.config

        // Setup our initial config
        derivedConfig = .init(config)

        // If there is a hardcoded title in the configuration, we set that
        // immediately. Future `set_title` apprt actions will override this
        // if necessary but this ensures our window loads with the proper
        // title immediately rather than on another event loop tick (see #5934)
        if let title = derivedConfig.title {
            self.title = title
        }

        // NOTE: setInitialWindowPosition is NOT called here because subclass
        // awakeFromNib may add decorations (e.g. toolbar for tabs style) that
        // change the frame. It is called from TerminalController.windowDidLoad
        // after the window is fully set up.

        // There is no title row: our content extends to the top of the window
        // and the tab bar and the side panels' headers take its place.
        if styleMask.contains(.titled) {
            styleMask.insert(.fullSizeContentView)
            titlebarAppearsTransparent = true
            titleVisibility = .hidden
        }

        // Get our saved level
        level = UserDefaults.zashiki.value(forKey: Self.defaultLevelKey) as? NSWindow.Level ?? .normal
    }

    // Both of these must be true for windows without decorations to be able to
    // still become key/main and receive events.
    override var canBecomeKey: Bool { return true }
    override var canBecomeMain: Bool { return true }

    override func close() {
        NotificationCenter.default.post(name: Self.terminalWillCloseNotification, object: self)
        super.close()
    }

    var titlebarContainer: NSView? {
        // If we aren't fullscreen then the titlebar container is part of our window.
        if !styleMask.contains(.fullScreen) {
            return contentView?.firstViewFromRoot(withClassName: "NSTitlebarContainerView")
        }

        // If we are fullscreen, the titlebar container view is part of a separate
        // "fullscreen window", we need to find the window and then get the view.
        for window in NSApplication.shared.windows {
            // This is the private window class that contains the toolbar
            guard window.className == "NSToolbarFullScreenWindow" else { continue }

            // The parent will match our window. This is used to filter the correct
            // fullscreen window if we have multiple.
            guard window.parent == self else { continue }

            return window.contentView?.firstViewFromRoot(withClassName: "NSTitlebarContainerView")
        }

        return nil
    }

    // MARK: Positioning And Styling

    /// This is called by the controller when there is a need to reset the window appearance.
    func syncAppearance(_ surfaceConfig: Zashiki.SurfaceView.DerivedConfig) {
        // If our window is not visible, then we do nothing. Some things such as blurring
        // have no effect if the window is not visible. Ultimately, we'll have this called
        // at some point when a surface becomes focused.
        guard isVisible else { return }
        defer { updateColorSchemeForSurfaceTree() }

        // Basic properties
        appearance = surfaceConfig.windowAppearance
        hasShadow = surfaceConfig.macosWindowShadow

        // Window transparency only takes effect if our window is not native fullscreen.
        // In native fullscreen we disable transparency/opacity because the background
        // becomes gray and widgets show through.
        //
        // Also check if the user has overridden transparency to be fully opaque.
        let forceOpaque = terminalController?.isBackgroundOpaque ?? false
        if !styleMask.contains(.fullScreen) &&
            !forceOpaque &&
            (surfaceConfig.backgroundOpacity < 1 || surfaceConfig.backgroundBlur.isGlassStyle) {
            isOpaque = false

            // This is weird, but we don't use ".clear" because this creates a look that
            // matches Terminal.app much more closer. This lets users transition from
            // Terminal.app more easily.
            backgroundColor = .white.withAlphaComponent(0.001)

            // We don't need to set blur when using glass
            if !surfaceConfig.backgroundBlur.isGlassStyle, let appDelegate = NSApp.delegate as? AppDelegate {
                ghostty_set_window_background_blur(
                    appDelegate.ghostty.app,
                    Unmanaged.passUnretained(self).toOpaque())
            }
        } else {
            isOpaque = true

            let backgroundColor = preferredBackgroundColor ?? NSColor(surfaceConfig.backgroundColor)
            self.backgroundColor = backgroundColor.withAlphaComponent(1)
        }
    }

    /// The preferred window background color. The current window background color may not be set
    /// to this, since this is dynamic based on the state of the surface tree.
    ///
    /// This background color will include alpha transparency if set. If the caller doesn't want that,
    /// change the alpha channel again manually.
    var preferredBackgroundColor: NSColor? {
        if let terminalController, !terminalController.surfaceTree.isEmpty {
            let surface: Zashiki.SurfaceView?

            // If our focused surface borders the top then we prefer its background color
            if let focusedSurface = terminalController.focusedSurface,
               let treeRoot = terminalController.surfaceTree.root,
               let focusedNode = treeRoot.node(view: focusedSurface),
               treeRoot.spatial().doesBorder(side: .up, from: focusedNode) {
                surface = focusedSurface
            } else {
                // If it doesn't border the top, we use the top-left leaf
                surface = terminalController.surfaceTree.root?.leftmostLeaf()
            }

            if let surface {
                let backgroundColor = surface.backgroundColor ?? surface.derivedConfig.backgroundColor
                let alpha = surface.derivedConfig.backgroundOpacity.clamped(to: 0.001...1)
                return NSColor(backgroundColor).withAlphaComponent(alpha)
            }
        }

        let alpha = derivedConfig.backgroundOpacity.clamped(to: 0.001...1)
        return derivedConfig.backgroundColor.withAlphaComponent(alpha)
    }

    func updateColorSchemeForSurfaceTree() {
        terminalController?.updateColorSchemeForSurfaceTree()
    }

    func setInitialWindowPosition(x: Int16?, y: Int16?) -> Bool {
        // If we don't have an X/Y then we try to use the previously saved window pos.
        guard let x = x, let y = y else {
            return false
        }

        // Prefer the screen our window is being placed on otherwise our primary screen.
        guard let screen = screen ?? NSScreen.screens.first else {
            return false
        }

        // Convert top-left coordinates to bottom-left origin using our utility extension
        let origin = screen.origin(
            fromTopLeftOffsetX: CGFloat(x),
            offsetY: CGFloat(y),
            windowSize: frame.size)

        // Clamp the origin to ensure the window stays fully visible on screen
        var safeOrigin = origin
        let vf = screen.visibleFrame
        safeOrigin.x = min(max(safeOrigin.x, vf.minX), vf.maxX - frame.width)
        safeOrigin.y = min(max(safeOrigin.y, vf.minY), vf.maxY - frame.height)

        setFrameOrigin(safeOrigin)
        return true
    }

    // MARK: Config

    struct DerivedConfig {
        let title: String?
        let backgroundBlur: Zashiki.Config.BackgroundBlur
        let backgroundColor: NSColor
        let backgroundOpacity: Double
        let windowCornerRadius: CGFloat

        init() {
            self.title = nil
            self.backgroundColor = NSColor.windowBackgroundColor
            self.backgroundOpacity = 1
            self.backgroundBlur = .disabled
            self.windowCornerRadius = 16
        }

        init(_ config: Zashiki.Config) {
            self.title = config.title
            self.backgroundColor = NSColor(config.backgroundColor)
            self.backgroundOpacity = config.backgroundOpacity
            self.backgroundBlur = config.backgroundBlur
            self.windowCornerRadius = 16
        }
    }
}
