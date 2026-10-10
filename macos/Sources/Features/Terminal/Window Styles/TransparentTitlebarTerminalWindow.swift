import AppKit

/// A terminal window style that provides a transparent titlebar effect. With this effect, the titlebar
/// matches the background color of the window.
class TransparentTitlebarTerminalWindow: TerminalWindow {
    /// Stores the last surface configuration to reapply appearance when needed.
    /// Becoming main can reset the titlebar appearance.
    private var lastSurfaceConfig: Zashiki.SurfaceView.DerivedConfig?

    // MARK: NSWindow

    override func becomeMain() {
        super.becomeMain()

        guard let lastSurfaceConfig else { return }
        syncAppearance(lastSurfaceConfig)

    }

    override func update() {
        super.update()

        // On macOS 13 to 15, we need to hide the NSVisualEffectView in order to allow our
        // titlebar to be truly transparent.
        if #unavailable(macOS 26) {
            if !effectViewIsHidden {
                hideEffectView()
            }
        }
    }

    // MARK: Appearance

    override func syncAppearance(_ surfaceConfig: Zashiki.SurfaceView.DerivedConfig) {
        super.syncAppearance(surfaceConfig)
        // override appearance based on the terminal's background color
        if let preferredBackgroundColor {
            appearance = (preferredBackgroundColor.isLightColor ? NSAppearance(named: .aqua) : NSAppearance(named: .darkAqua))
        }

        // Save our config in case we need to reapply
        lastSurfaceConfig = surfaceConfig

        if #available(macOS 26.0, *) {
            syncAppearanceTahoe(surfaceConfig)
        } else {
            syncAppearanceVentura(surfaceConfig)
        }
    }

    @available(macOS 26.0, *)
    private func syncAppearanceTahoe(_ surfaceConfig: Zashiki.SurfaceView.DerivedConfig) {
        // When we have transparency, we need to set the titlebar background to match the
        // window background but with opacity. The window background is set using the
        // "preferred background color" property.
        //
        // Even if we aren't transparent, we still set this because this becomes the
        // color of the titlebar in native fullscreen view.
        if let titlebarView = titlebarContainer?.firstDescendant(withClassName: "NSTitlebarView") {
            titlebarView.wantsLayer = true

            // Our content extends under the titlebar and draws the top row
            // itself (see `TerminalWindow.awakeFromNib`), so the titlebar must
            // not paint over it.
            titlebarView.layer?.backgroundColor = NSColor.clear.cgColor
        }

        // In all cases, we have to hide the background view since this has multiple subviews
        // that force a background color.
        titlebarBackgroundView?.isHidden = true
    }

    @available(macOS 13.0, *)
    private func syncAppearanceVentura(_ surfaceConfig: Zashiki.SurfaceView.DerivedConfig) {
        guard let titlebarContainer else { return }

        // Our content extends under the titlebar and draws the top row
        // itself, so the titlebar must not paint over it.
        titlebarContainer.wantsLayer = true
        titlebarContainer.layer?.backgroundColor = NSColor.clear.cgColor

        // See the docs for the function that sets this to true on why
        effectViewIsHidden = false

        // Necessary to not draw the border around the title
        titlebarAppearsTransparent = true
    }

    // MARK: View Finders

    private var titlebarBackgroundView: NSView? {
        titlebarContainer?.firstDescendant(withClassName: "NSTitlebarBackgroundView")
    }

    // MARK: macOS 13 to 15

    private var effectViewIsHidden = false

    private func hideEffectView() {
        guard !effectViewIsHidden else { return }

        // Keep the system titlebar backdrop from covering our content.
        if let effectView = titlebarContainer?.descendants(withClassName: "NSVisualEffectView").first {
            effectView.isHidden = true
        }

        effectViewIsHidden = true
    }
}
