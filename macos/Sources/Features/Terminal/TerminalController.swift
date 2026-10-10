import Foundation
import Cocoa
import SwiftUI
import Combine
import GhosttyKit

/// A classic, tabbed terminal experience.
class TerminalController: BaseTerminalController {
    override var windowNibName: NSNib.Name? {
        return "TerminalTransparentTitlebar"
    }

    /// The initial window presentation is deferred by one runloop turn in a few places so
    /// AppKit can settle tab/window state first. Close actions must cancel it to avoid
    /// re-showing a tab that was already closed.
    private var pendingInitialPresentation: DispatchWorkItem?

    /// This is set to false by init if the window managed by this controller should not be restorable.
    /// For example, terminals executing custom scripts are not restorable.
    private var restorable: Bool = true

    /// The configuration derived from the Zashiki config so we don't need to rely on references.
    private(set) var derivedConfig: DerivedConfig

    /// The notification cancellable for focused surface property changes.
    private var surfaceAppearanceCancellables: Set<AnyCancellable> = []

    init(_ ghostty: Zashiki.App,
         withBaseConfig base: Zashiki.SurfaceConfiguration? = nil,
         withSurfaceTree tree: SplitTree<Zashiki.SurfaceView>? = nil,
         withTabs restoredTabs: [TerminalTab]? = nil,
         selectedTabIndex: Int = 0,
         parent: NSWindow? = nil
    ) {
        // The window we manage is not restorable if we've specified a command
        // to execute. We do this because the restored window is meaningless at the
        // time of writing this: it'd just restore to a shell in the same directory
        // as the script. We may want to revisit this behavior when we have scrollback
        // restoration.
        self.restorable = (base?.command ?? "") == ""

        // Setup our initial derived config based on the current app config
        self.derivedConfig = DerivedConfig(ghostty.config)

        // When we're given existing tabs, start from the first one's tree so
        // the base controller doesn't spawn a throwaway surface.
        super.init(ghostty, baseConfig: base, surfaceTree: tree ?? restoredTabs?.first?.surfaceTree)

        if let restoredTabs, !restoredTabs.isEmpty {
            let index = max(0, min(selectedTabIndex, restoredTabs.count - 1))
            replaceTabs(restoredTabs, selected: restoredTabs[index])
        }

        // Setup our notifications for behaviors
        let center = NotificationCenter.default
        center.addObserver(
            self,
            selector: #selector(onToggleFullscreen),
            name: Zashiki.Notification.zashikiToggleFullscreen,
            object: nil)
        center.addObserver(
            self,
            selector: #selector(onMoveTab),
            name: .zashikiMoveTab,
            object: nil)
        center.addObserver(
            self,
            selector: #selector(onGotoTab),
            name: Zashiki.Notification.zashikiGotoTab,
            object: nil)
        center.addObserver(
            self,
            selector: #selector(onCloseTab),
            name: .zashikiCloseTab,
            object: nil)
        center.addObserver(
            self,
            selector: #selector(onCloseOtherTabs),
            name: .zashikiCloseOtherTabs,
            object: nil)
        center.addObserver(
            self,
            selector: #selector(onCloseTabsOnTheRight),
            name: .zashikiCloseTabsOnTheRight,
            object: nil)
        center.addObserver(
            self,
            selector: #selector(onResetWindowSize),
            name: .zashikiResetWindowSize,
            object: nil
        )
        center.addObserver(
            self,
            selector: #selector(zashikiConfigDidChange(_:)),
            name: .zashikiConfigDidChange,
            object: nil
        )
        center.addObserver(
            self,
            selector: #selector(onCloseWindow),
            name: .zashikiCloseWindow,
            object: nil
        )
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported for this view")
    }

    deinit {
        // Remove all of our notificationcenter subscriptions
        let center = NotificationCenter.default
        center.removeObserver(self)
    }

    private func cancelPendingInitialPresentation() {
        pendingInitialPresentation?.cancel()
        pendingInitialPresentation = nil
    }

    private func scheduleInitialPresentation(_ block: @escaping () -> Void) {
        cancelPendingInitialPresentation()

        var scheduledWorkItem: DispatchWorkItem?
        scheduledWorkItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            defer { self.pendingInitialPresentation = nil }
            guard pendingInitialPresentation?.isCancelled == false else { return }
            block()
        }

        let workItem = scheduledWorkItem!
        pendingInitialPresentation = workItem
        DispatchQueue.main.async(execute: workItem)
    }

    // MARK: Base Controller Overrides

    override func surfaceTreeDidChange(from: SplitTree<Zashiki.SurfaceView>, to: SplitTree<Zashiki.SurfaceView>) {
        super.surfaceTreeDidChange(from: from, to: to)

        // Whenever our surface tree changes in any way (new split, close split, etc.)
        // we want to invalidate our state.
        invalidateRestorableState()

        // If the selected tab has no surfaces left then the tab goes away. If
        // it was the only tab we close our window.
        if to.isEmpty {
            if tabs.count > 1 {
                removeTab(selectedTab)
            } else {
                self.window?.close()
            }
        }
    }

    /// The tab bar is always shown: with no title row, it is where the title
    /// is shown and where the window can be dragged.
    override var showsTabBar: Bool { true }

    override func selectedTabDidChange(from oldTab: TerminalTab) {
        super.selectedTabDidChange(from: oldTab)
        invalidateRestorableState()

        syncAppearance()
    }

    override func tabsDidChange() {
        super.tabsDidChange()
        invalidateRestorableState()
    }

    override func tabBarDidClose(_ tab: TerminalTab) {
        closeTab(tab)
    }

    override func tabBarDidPerform(_ action: TerminalTabAction, on tab: TerminalTab) {
        guard tabs.contains(where: { $0 === tab }) else { return }
        switch action {
        case .closeOthers:
            performCloseOtherTabs(keeping: tab)
        case .closeRight:
            performCloseTabsOnTheRight(of: tab)
        default:
            super.tabBarDidPerform(action, on: tab)
        }
    }

    override func tabBarDidRequestNewTab() {
        newTab(nil)
    }

    override func replaceSurfaceTree(
        _ newTree: SplitTree<Zashiki.SurfaceView>,
        moveFocusTo newView: Zashiki.SurfaceView? = nil,
        moveFocusFrom oldView: Zashiki.SurfaceView? = nil,
        undoAction: String? = nil
    ) {
        // We have a special case if our tree is empty to close our tab immediately.
        // This makes it so that undo is handled properly.
        if newTree.isEmpty {
            closeTabImmediately()
            return
        }

        super.replaceSurfaceTree(
            newTree,
            moveFocusTo: newView,
            moveFocusFrom: oldView,
            undoAction: undoAction)
    }

    // MARK: Terminal Creation

    /// Returns all the available terminal controllers present in the app currently.
    static var all: [TerminalController] {
        return NSApplication.shared.windows.compactMap {
            $0.windowController as? TerminalController
        }
    }

    // Keep track of the last point that our window was launched at so that new
    // windows "cascade" over each other and don't just launch directly on top
    // of each other.
    private static var lastCascadePoint = NSPoint(x: 0, y: 0)

    private static func applyCascade(to window: NSWindow, hasFixedPos: Bool) {
        if hasFixedPos { return }

        if all.count > 1 {
            lastCascadePoint = window.cascadeTopLeft(from: lastCascadePoint)
        } else {
            // We assume the window frame is already correct at this point,
            // so we pass .zero to let cascade use the current frame position.
            lastCascadePoint = window.cascadeTopLeft(from: .zero)
        }
    }

    // The preferred parent terminal controller.
    static var preferredParent: TerminalController? {
        all.first {
            $0.window?.isMainWindow ?? false
        } ?? lastMain ?? all.last
    }

    // The last controller to be main. We use this when paired with "preferredParent"
    // to find the preferred window to attach new tabs, perform actions, etc. We
    // always prefer the main window but if there isn't any (because we're triggered
    // by something like an App Intent) then we prefer the most previous main.
    static private(set) weak var lastMain: TerminalController?

    /// The "new window" action.
    static func newWindow(
        _ ghostty: Zashiki.App,
        withBaseConfig baseConfig: Zashiki.SurfaceConfiguration? = nil,
        withParent explicitParent: NSWindow? = nil
    ) -> TerminalController {
        let c = TerminalController.init(ghostty, withBaseConfig: baseConfig)

        // Get our parent. Our parent is the one explicitly given to us,
        // otherwise the focused terminal, otherwise an arbitrary one.
        let parent: NSWindow? = explicitParent ?? preferredParent?.window
        if let parentController = parent?.windowController as? TerminalController {
            c.isBackgroundOpaque = parentController.isBackgroundOpaque
        }

        if let parent, parent.styleMask.contains(.fullScreen) {
            // If our previous window was fullscreen then we want our new window to
            // be fullscreen. This behavior actually doesn't match the native tabbing
            // behavior of macOS apps where new windows create tabs when in native
            // fullscreen but this is how we've always done it. This matches iTerm2
            // behavior.
            c.toggleFullscreen(mode: .native)
        } else if ghostty.config.windowFullscreen != nil {
            // Native has to be done immediately so that our stylemask contains
            // fullscreen for the logic later in this method.
            c.toggleFullscreen(mode: .native)
        }

        // We're dispatching this async because otherwise the lastCascadePoint doesn't
        // take effect. Our best theory is there is some next-event-loop-tick logic
        // that Cocoa is doing that we need to be after.
        c.scheduleInitialPresentation {
            c.showWindow(self)

            // Only cascade if we aren't fullscreen.
            if let window = c.window {
                if !window.styleMask.contains(.fullScreen) {
                    let hasFixedPos = c.derivedConfig.windowPositionX != nil && c.derivedConfig.windowPositionY != nil
                    Self.applyCascade(to: window, hasFixedPos: hasFixedPos)
                }
            }

            // All new_window actions force our app to be active, so that the new
            // window is focused and visible.
            NSApp.activate(ignoringOtherApps: true)
        }

        // Setup our undo
        if let undoManager = c.undoManager {
            undoManager.setActionName("New Window")
            undoManager.registerUndo(
                withTarget: c,
                expiresAfter: c.undoExpiration
            ) { target in
                // Close the window when undoing
                undoManager.disableUndoRegistration {
                    target.closeWindow(nil)
                }

                // Register redo action
                undoManager.registerUndo(
                    withTarget: ghostty,
                    expiresAfter: target.undoExpiration
                ) { ghostty in
                    _ = TerminalController.newWindow(
                        ghostty,
                        withBaseConfig: baseConfig,
                        withParent: explicitParent)
                }
            }
        }

        return c
    }

    /// Create a new window with an existing split tree.
    /// The window will be sized to match the tree's current view bounds if available.
    /// - Parameters:
    ///   - ghostty: The Zashiki app instance.
    ///   - tree: The split tree to use for the new window.
    ///   - position: Optional screen position (top-left corner) for the new window.
    ///               If nil, the window will cascade from the last cascade point.
    static func newWindow(
        _ ghostty: Zashiki.App,
        tree: SplitTree<Zashiki.SurfaceView>,
        position: NSPoint? = nil,
        confirmUndo: Bool = true,
        inheritBackgroundOpacity: Bool? = nil
    ) -> TerminalController {
        let c = TerminalController.init(ghostty, withSurfaceTree: tree)
        if let inheritBackgroundOpacity {
            c.isBackgroundOpaque = inheritBackgroundOpacity
        }

        // Calculate the target frame based on the tree's view bounds
        let treeSize: CGSize? = tree.root?.viewBounds()

        c.scheduleInitialPresentation {
            c.showWindow(self)
            if let window = c.window {
                // If we have a tree size, resize the window's content to match
                if let treeSize, treeSize.width > 0, treeSize.height > 0 {
                    window.setContentSize(treeSize)
                    window.constrainToScreen()
                }

                if !window.styleMask.contains(.fullScreen) {
                    if let position {
                        window.setFrameTopLeftPoint(position)
                        window.constrainToScreen()
                    } else {
                        let hasFixedPos = c.derivedConfig.windowPositionX != nil && c.derivedConfig.windowPositionY != nil
                        Self.applyCascade(to: window, hasFixedPos: hasFixedPos)
                    }
                }
            }
        }

        // Setup our undo
        if let undoManager = c.undoManager {
            undoManager.setActionName("New Window")
            undoManager.registerUndo(
                withTarget: c,
                expiresAfter: c.undoExpiration
            ) { target in
                undoManager.disableUndoRegistration {
                    if confirmUndo {
                        target.closeWindow(nil)
                    } else {
                        target.closeWindowImmediately()
                    }
                }

                undoManager.registerUndo(
                    withTarget: ghostty,
                    expiresAfter: target.undoExpiration
                ) { ghostty in
                    _ = TerminalController.newWindow(
                        ghostty,
                        tree: tree,
                        inheritBackgroundOpacity: inheritBackgroundOpacity
                    )
                }
            }
        }

        return c
    }

    static func newTab(
        _ ghostty: Zashiki.App,
        from parent: NSWindow? = nil,
        withBaseConfig baseConfig: Zashiki.SurfaceConfiguration? = nil
    ) -> TerminalController? {
        // Making sure that we're dealing with a TerminalController. If not,
        // then we just create a new window.
        guard let parent,
              let controller = parent.windowController as? TerminalController else {
            return newWindow(ghostty, withBaseConfig: baseConfig, withParent: parent)
        }

        guard let ghostty_app = ghostty.app else { return nil }

        // If the parent is miniaturized, bring it back out so the new tab is visible.
        if parent.isMiniaturized { parent.deminiaturize(self) }

        let view = Zashiki.SurfaceView(ghostty_app, baseConfig: baseConfig)
        controller.addTab(TerminalTab(surfaceTree: .init(view: view)), baseConfig: baseConfig)

        parent.makeKeyAndOrderFront(self)

        // We also activate our app so that it becomes front. This may be
        // necessary for the dock menu.
        NSApp.activate(ignoringOtherApps: true)

        return controller
    }

    /// Adds a tab at the position set by `window-new-tab-position` and selects it.
    private func addTab(_ tab: TerminalTab, baseConfig: Zashiki.SurfaceConfiguration?) {
        let index: Int
        switch ghostty.config.windowNewTabPosition {
        case "end":
            index = tabs.count

        case "current": fallthrough
        default:
            index = (tabs.firstIndex(where: { $0 === selectedTab }) ?? tabs.count - 1) + 1
        }

        insertTab(tab, at: index)
        selectTab(tab)

        // Setup our undo
        guard let undoManager else { return }
        undoManager.setActionName("New Tab")
        undoManager.registerUndo(
            withTarget: self,
            expiresAfter: undoExpiration
        ) { [weak tab] target in
            // Close the tab when undoing
            undoManager.disableUndoRegistration {
                if let tab { target.closeTabImmediately(tab) }
            }

            // Register redo action
            undoManager.registerUndo(
                withTarget: target,
                expiresAfter: target.undoExpiration
            ) { target in
                _ = TerminalController.newTab(
                    target.ghostty,
                    from: target.window,
                    withBaseConfig: baseConfig)
            }
        }
    }

    // MARK: - Methods

    @objc private func zashikiConfigDidChange(_ notification: Notification) {
        // Get our managed configuration object out
        guard let config = notification.userInfo?[
            Notification.Name.ZashikiConfigChangeKey
        ] as? Zashiki.Config else { return }

        // If this is an app-level config update then we update some things.
        if notification.object == nil {
            // Update our derived config
            self.derivedConfig = DerivedConfig(config)

            // If we have no surfaces in our window (is that possible?) then we update
            // our window appearance based on the root config. If we have surfaces, we
            // don't call this because focused surface changes will trigger appearance updates.
            if surfaceTree.isEmpty {
                syncAppearance(.init(config))
            }

            return
        }
        /// Surface-level config will be updated in
        /// ``Zashiki/Zashiki/SurfaceView/derivedConfig`` then
        /// ``TerminalController/focusedSurfaceDidChange(to:)``
    }

    /// Update window appearance from the selected tab.
    override func syncAppearance() {
        // When our focus changes, we update our window appearance based on the
        // currently focused surface.
        guard let focusedSurface else { return }
        syncAppearance(focusedSurface.derivedConfig)
    }

    private func syncAppearance(_ surfaceConfig: Zashiki.SurfaceView.DerivedConfig) {
        // Let our window handle its own appearance
        guard let window = window as? TerminalWindow else { return }

        window.syncAppearance(surfaceConfig)
        terminalViewContainer?.zashikiConfigDidChange(ghostty.config, preferredBackgroundColor: window.preferredBackgroundColor)
    }

    /// Adjusts the given frame for the configured window position.
    func adjustForWindowPosition(frame: NSRect, on screen: NSScreen) -> NSRect {
        guard let x = derivedConfig.windowPositionX else { return frame }
        guard let y = derivedConfig.windowPositionY else { return frame }

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

        // Return our new origin
        var result = frame
        result.origin = safeOrigin
        return result
    }

    /// This is called anytime a node in the surface tree is being removed.
    override func closeSurface(
        _ node: SplitTree<Zashiki.SurfaceView>.Node,
        withConfirmation: Bool = true
    ) {
        // If this isn't the root then we're dealing with a split closure.
        if surfaceTree.root != node {
            super.closeSurface(node, withConfirmation: withConfirmation)
            return
        }

        // More than 1 tab means we're closing a tab
        if tabs.count > 1 {
            closeTab(nil)
            return
        }

        // 1 tab, closing the window
        closeWindow(nil)
    }

    /// Closes a tab (the selected one by default) immediately and without
    /// confirmation. This will setup proper undo state so the action can be undone.
    func closeTabImmediately(_ tab: TerminalTab? = nil, registerRedo: Bool = true) {
        let tab = tab ?? selectedTab

        // The tab may already be gone, e.g. an undo that refers to a tab
        // that was closed some other way.
        guard let index = tabs.firstIndex(where: { $0 === tab }) else { return }

        // Closing the only tab closes the window.
        guard tabs.count > 1 else {
            closeWindowImmediately()
            return
        }

        removeTab(tab)

        // Undo. The closure keeps the tab (and its surfaces) alive until the
        // undo expires so it can be put back.
        guard let undoManager else { return }
        undoManager.setActionName("Close Tab")
        undoManager.registerUndo(
            withTarget: self,
            expiresAfter: undoExpiration
        ) { target in
            target.insertTab(tab, at: index)
            target.selectTab(tab)

            if registerRedo {
                undoManager.registerUndo(
                    withTarget: target,
                    expiresAfter: target.undoExpiration
                ) { target in
                    target.closeTabImmediately(tab)
                }
            }
        }
    }

    /// Closes the given tabs as one undoable action and keeps the selected tab.
    private func closeTabsImmediately(_ tabsToClose: [TerminalTab], actionName: String) {
        guard !tabsToClose.isEmpty else { return }
        let keep = selectedTab

        undoManager?.beginUndoGrouping()
        defer { undoManager?.endUndoGrouping() }

        for tab in tabsToClose {
            // We must not register a redo, because it messes with our own redo
            // that we register later.
            closeTabImmediately(tab, registerRedo: false)
        }

        guard let undoManager else { return }
        undoManager.setActionName(actionName)

        // We need to register an undo that reselects the kept tab. Otherwise, the
        // undo operation above for each tab will steal the selection. This undo
        // runs before the ones that put the tabs back, so reselect afterwards.
        undoManager.registerUndo(
            withTarget: self,
            expiresAfter: undoExpiration
        ) { target in
            DispatchQueue.main.async {
                target.selectTab(keep)
            }

            // Register redo action
            undoManager.registerUndo(
                withTarget: target,
                expiresAfter: target.undoExpiration
            ) { target in
                target.closeTabsImmediately(
                    tabsToClose.filter { tab in target.tabs.contains(where: { $0 === tab }) },
                    actionName: actionName)
            }
        }
    }

    private var otherTabs: [TerminalTab] {
        tabs.filter { $0 !== selectedTab }
    }

    private var tabsOnTheRight: [TerminalTab] {
        guard let index = tabs.firstIndex(where: { $0 === selectedTab }) else { return [] }
        return Array(tabs[(index + 1)...])
    }

    /// Closes the current window (including every tab) immediately and without
    /// confirmation. This will setup proper undo state so the action can be undone.
    func closeWindowImmediately() {
        guard let window = window else { return }

        cancelPendingInitialPresentation()

        registerUndoForCloseWindow()

        window.close()
    }

    /// Registers undo for closing the window with all of its tabs.
    private func registerUndoForCloseWindow() {
        guard let undoManager, undoManager.isUndoRegistrationEnabled else { return }
        guard let undoState else { return }

        // Register undo action to restore the window
        undoManager.setActionName("Close Window")
        undoManager.registerUndo(
            withTarget: ghostty,
            expiresAfter: undoExpiration) { ghostty in
                // Restore the undo state
                let newController = TerminalController(ghostty, with: undoState)

                // Register redo action
                undoManager.registerUndo(
                    withTarget: newController,
                    expiresAfter: newController.undoExpiration) { target in
                        target.closeWindowImmediately()
                    }
            }
    }

    /// Close all windows, asking for confirmation if necessary.
    static func closeAllWindows() {
        // The window we use for confirmations. Try to find the first window that
        // needs quit confirmation. This lets us attach the confirmation to something
        // that is running.
        guard let confirmWindow = all
            .first(where: { $0.surfaceTree.contains(where: { $0.needsConfirmQuit }) })?
            .surfaceTree.first(where: { $0.needsConfirmQuit })?
            .window
        else {
            closeAllWindowsImmediately()
            return
        }

        let alert = NSAlert()
        alert.messageText = "Close All Windows?"
        alert.informativeText = "All terminal sessions will be terminated."
        alert.addButton(withTitle: "Close All Windows")
        alert.addButton(withTitle: "Cancel")
        alert.alertStyle = .warning
        alert.beginSheetModal(for: confirmWindow, completionHandler: { response in
            if response == .alertFirstButtonReturn {
                // This is important so that we avoid losing focus when Stage
                // Manager is used (#8336)
                alert.window.orderOut(nil)
                closeAllWindowsImmediately()
            }
        })
    }

    static private func closeAllWindowsImmediately() {
        let undoManager = (NSApp.delegate as? AppDelegate)?.undoManager
        undoManager?.beginUndoGrouping()
        all.forEach { $0.closeWindowImmediately() }
        undoManager?.setActionName("Close All Windows")
        undoManager?.endUndoGrouping()
    }

    // MARK: Undo/Redo

    /// The state that we require to recreate a TerminalController from an undo.
    struct UndoState {
        let frame: NSRect
        let tabs: [TerminalTab]
        let selectedTabIndex: Int
    }

    convenience init(_ ghostty: Zashiki.App, with undoState: UndoState) {
        self.init(
            ghostty,
            withTabs: undoState.tabs,
            selectedTabIndex: undoState.selectedTabIndex)

        // Show the window and restore its frame
        showWindow(nil)
        if let window {
            window.setFrame(undoState.frame, display: true)

            // Restore focus to the previously focused surface, or the first
            // one if there was none.
            if let focusTarget = selectedTab.focusedSurface ?? surfaceTree.first {
                self.focusedSurface = focusTarget
                DispatchQueue.main.async {
                    Zashiki.moveFocus(to: focusTarget, from: nil)
                }
            }
        }
    }

    /// The current undo state for this controller
    var undoState: UndoState? {
        guard let window else { return nil }
        guard !allSurfaces.isEmpty else { return nil }
        return .init(
            frame: window.frame,
            tabs: tabs,
            selectedTabIndex: tabs.firstIndex(where: { $0 === selectedTab }) ?? 0)
    }

    // MARK: - NSWindowController

    override func windowWillLoad() {
        // We do NOT want to cascade because we handle this manually from the manager.
        shouldCascadeWindows = false
    }

    override func windowDidLoad() {
        super.windowDidLoad()
        guard let window else { return }

        // I copy this because we may change the source in the future but also because
        // I regularly audit our codebase for "ghostty.config" access because generally
        // you shouldn't use it. Its safe in this case because for a new window we should
        // use whatever the latest app-level config is.
        let config = ghostty.config

        // Setting all three of these is required for restoration to work.
        window.isRestorable = restorable
        if restorable {
            window.restorationClass = TerminalWindowRestoration.self
            window.identifier = .init(String(describing: TerminalWindowRestoration.self))
        }

        // If we have only a single surface (no splits) and there is a default size then
        // we should resize to that default size.
        if case let .leaf(view) = surfaceTree.root {
            // If this is our first surface then our focused surface will be nil
            // so we force the focused surface to the leaf.
            focusedSurface = view
        }

        // Initialize our content view to the SwiftUI root
        let container = TerminalViewContainer {
            TerminalView(ghostty: ghostty, viewModel: self, delegate: self)
        }

        // Set the initial content size on the container so that
        // intrinsicContentSize returns the correct value immediately,
        // without waiting for @FocusedValue to propagate through the
        // SwiftUI focus chain.
        container.initialContentSize = focusedSurface?.initialSize

        window.contentView = container

        // If we have a default size, we want to apply it.
        if let defaultSize {
            defaultSize.apply(to: window)

            if case .contentIntrinsicSize = defaultSize {
                if let screen = window.screen ?? NSScreen.main {
                    let frame = self.adjustForWindowPosition(frame: window.frame, on: screen)
                    window.setFrameOrigin(frame.origin)
                }
            }
        }

        // Zashiki draws its own tab bar inside the window, so we never want
        // macOS to put our windows into native tabs.
        window.tabbingMode = .disallowed

        // Apply any additional appearance-related properties to the new window. We
        // apply this based on the root config but change it later based on surface
        // config (see focused surface change callback).
        syncAppearance(.init(config))
    }

    /// Setup correct window frame before showing the window
    override func showWindow(_ sender: Any?) {
        guard let terminalWindow = window as? TerminalWindow else { return }

        // Set the initial window position. This must happen after the window
        // is fully set up (content view, toolbar, default size) so that
        // decorations added by subclass awakeFromNib (e.g. toolbar for tabs
        // style) don't change the frame after the position is restored.
        let originChanged = terminalWindow.setInitialWindowPosition(
            x: derivedConfig.windowPositionX,
            y: derivedConfig.windowPositionY,
        )
        let restored = LastWindowPosition.shared.restore(
            terminalWindow,
            origin: !originChanged,
            size: defaultSize == nil,
        )

        // If nothing is changed for the frame,
        // we should center the window
        if !originChanged, !restored {
            // This doesn't work in `windowDidLoad` somehow
            terminalWindow.center()
        }

        super.showWindow(sender)
    }

    // MARK: NSWindowDelegate

    override func windowShouldClose(_ sender: NSWindow) -> Bool {
        // We will always explicitly close the window, after confirming if needed.
        closeWindow(nil)
        return false
    }

    override func windowWillClose(_ notification: Notification) {
        super.windowWillClose(notification)
        cancelPendingInitialPresentation()

        // If we remove a window, we reset the cascade point to the key window so that
        // the next window cascade's from that one.
        if let focusedWindow = NSApplication.shared.keyWindow {
            // If we are NOT the focused window, then we are a tabbed window. If we
            // are closing a tabbed window, we want to set the cascade point to be
            // the next cascade point from this window.
            if focusedWindow != window {
                // The cascadeTopLeft call below should NOT move the window. Starting with
                // macOS 15, we found that specifically when used with the new window snapping
                // features of macOS 15, this WOULD move the frame. So we keep track of the
                // old frame and restore it if necessary. Issue:
                // https://github.com/ghostty-org/ghostty/issues/2565
                let oldFrame = focusedWindow.frame

                Self.lastCascadePoint = focusedWindow.cascadeTopLeft(from: .zero)

                if focusedWindow.frame != oldFrame {
                    focusedWindow.setFrame(oldFrame, display: true)
                }

                return
            }

            // If we are the focused window, then we set the last cascade point to
            // our own frame so that it shows up in the same spot.
            let frame = focusedWindow.frame
            Self.lastCascadePoint = NSPoint(x: frame.minX, y: frame.maxY)
        }
    }

    override func windowDidBecomeKey(_ notification: Notification) {
        super.windowDidBecomeKey(notification)
        terminalViewContainer?.updateGlassTintOverlay(isKeyWindow: true)
    }

    override func windowDidResignKey(_ notification: Notification) {
        super.windowDidResignKey(notification)
        terminalViewContainer?.updateGlassTintOverlay(isKeyWindow: false)
    }

    override func windowDidMove(_ notification: Notification) {
        super.windowDidMove(notification)

        // Whenever we move save our last position for the next start.
        LastWindowPosition.shared.save(window)
    }

    override func windowDidResize(_ notification: Notification) {
        super.windowDidResize(notification)

        // Whenever we resize save our last position and size for the next start.
        LastWindowPosition.shared.save(window)
    }

    func windowDidBecomeMain(_ notification: Notification) {
        // Whenever we get focused, use that as our last window position for
        // restart. This differs from Terminal.app but matches iTerm2 behavior
        // and I think its sensible.
        LastWindowPosition.shared.save(window)

        // Remember our last main
        Self.lastMain = self
    }

    // Called when the window will be encoded. We handle the data encoding here in the
    // window controller.
    func window(_ window: NSWindow, willEncodeRestorableState state: NSCoder) {
        let data = TerminalRestorableState(from: self)
        data.encode(with: state)
    }

    // MARK: First Responder

    @IBAction func newWindow(_ sender: Any?) {
        guard let surface = focusedSurface?.surface else { return }
        ghostty.newWindow(surface: surface)
    }

    @IBAction func newTab(_ sender: Any?) {
        guard let surface = focusedSurface?.surface else { return }
        ghostty.newTab(surface: surface)
    }

    @IBAction func closeTab(_ sender: Any?) {
        closeTab(selectedTab)
    }

    /// Closes a tab, asking for confirmation if it has a running process.
    func closeTab(_ tab: TerminalTab) {
        guard tabs.count > 1 else {
            closeWindow(nil)
            return
        }

        guard tab.needsConfirmQuit else {
            closeTabImmediately(tab)
            return
        }

        // Show the tab we're asking about.
        selectTab(tab)
        confirmClose(
            messageText: "Close Tab?",
            informativeText: "The terminal still has a running process. If you close the tab the process will be killed."
        ) {
            self.closeTabImmediately(tab)
        }
    }

    @IBAction func closeOtherTabs(_ sender: Any?) {
        performCloseOtherTabs(keeping: selectedTab)
    }

    private func performCloseOtherTabs(keeping tab: TerminalTab) {
        let tabsToClose = tabs.filter { $0 !== tab }

        // If we only have one tab then we have no other tabs to close
        guard !tabsToClose.isEmpty else { return }

        // Check if we have to confirm close.
        guard tabsToClose.contains(where: { $0.needsConfirmQuit }) else {
            closeTabsImmediately(tabsToClose, actionName: "Close Other Tabs")
            return
        }

        confirmClose(
            messageText: "Close Other Tabs?",
            informativeText: "At least one other tab still has a running process. If you close the tab the process will be killed."
        ) {
            self.closeTabsImmediately(tabsToClose, actionName: "Close Other Tabs")
        }
    }

    @IBAction func closeTabsOnTheRight(_ sender: Any?) {
        performCloseTabsOnTheRight(of: selectedTab)
    }

    private func performCloseTabsOnTheRight(of tab: TerminalTab) {
        guard let index = tabs.firstIndex(where: { $0 === tab }) else { return }
        let tabsToClose = Array(tabs.dropFirst(index + 1))
        guard !tabsToClose.isEmpty else { return }

        guard tabsToClose.contains(where: { $0.needsConfirmQuit }) else {
            closeTabsImmediately(tabsToClose, actionName: "Close Tabs to the Right")
            return
        }

        confirmClose(
            messageText: "Close Tabs on the Right?",
            informativeText: "At least one tab to the right still has a running process. If you close the tab the process will be killed."
        ) {
            self.closeTabsImmediately(tabsToClose, actionName: "Close Tabs to the Right")
        }
    }

    @IBAction func returnToDefaultSize(_ sender: Any?) {
        guard let window, let defaultSize else { return }
        defaultSize.apply(to: window)
    }

    @IBAction override func closeWindow(_ sender: Any?) {
        // We need to check every tab for confirmation if we're closing the window.
        guard let confirmTab = tabs.first(where: { $0.needsConfirmQuit }) else {
            closeWindowImmediately()
            return
        }

        // Show a tab that needs confirmation so the alert has context.
        selectTab(confirmTab)
        confirmClose(
            messageText: "Close Window?",
            informativeText: "All terminal sessions in this window will be terminated.",
        ) {
            self.closeWindowImmediately()
        }
    }

    @IBAction func toggleZashikiFullScreen(_ sender: Any?) {
        guard let surface = focusedSurface?.surface else { return }
        ghostty.toggleFullscreen(surface: surface)
    }

    // MARK: - TerminalViewDelegate

    override func focusedSurfaceDidChange(to: Zashiki.SurfaceView?) {
        super.focusedSurfaceDidChange(to: to)

        // We always cancel our event listener
        surfaceAppearanceCancellables.removeAll()

        // When our focus changes, we update our window appearance based on the
        // currently focused surface.
        guard let focusedSurface else { return }
        syncAppearance(focusedSurface.derivedConfig)

        // We also want to get notified of certain changes to update our appearance.
        focusedSurface.$derivedConfig
            .dropFirst()
            .sink { [weak self, weak focusedSurface] _ in self?.syncAppearanceOnPropertyChange(focusedSurface) }
            .store(in: &surfaceAppearanceCancellables)
        focusedSurface.$backgroundColor
            .dropFirst()
            .sink { [weak self, weak focusedSurface] _ in self?.syncAppearanceOnPropertyChange(focusedSurface) }
            .store(in: &surfaceAppearanceCancellables)
    }

    private func syncAppearanceOnPropertyChange(_ surface: Zashiki.SurfaceView?) {
        guard let surface else { return }
        DispatchQueue.main.async { [weak self, weak surface] in
            guard let surface else { return }
            guard let self else { return }
            guard self.focusedSurface == surface else { return }
            self.syncAppearance(surface.derivedConfig)
        }
    }

    // MARK: - Notifications

    @objc private func onMoveTab(notification: SwiftUI.Notification) {
        guard let target = notification.object as? Zashiki.SurfaceView else { return }
        guard target == self.focusedSurface else { return }

        // Get the move action
        guard let action = notification.userInfo?[Notification.Name.ZashikiMoveTabKey] as? Zashiki.Action.MoveTab else { return }
        guard action.amount != 0 else { return }

        // Move the selected tab, stopping at either end.
        guard let selectedIndex = tabs.firstIndex(where: { $0 === selectedTab }) else { return }
        moveTab(selectedTab, to: selectedIndex + action.amount)
    }

    @objc private func onGotoTab(notification: SwiftUI.Notification) {
        guard let target = notification.object as? Zashiki.SurfaceView else { return }
        guard target == self.focusedSurface else { return }

        // Get the tab index from the notification
        guard let tabEnumAny = notification.userInfo?[Zashiki.Notification.GotoTabKey] else { return }
        guard let tabEnum = tabEnumAny as? ghostty_action_goto_tab_e else { return }
        let tabIndex: Int32 = tabEnum.rawValue

        // This will be the index we want to actual go to
        let finalIndex: Int

        // An index that is invalid is used to signal some special values.
        if tabIndex <= 0 {
            guard let selectedIndex = tabs.firstIndex(where: { $0 === selectedTab }) else { return }

            if tabIndex == GHOSTTY_GOTO_TAB_PREVIOUS.rawValue {
                finalIndex = selectedIndex == 0 ? tabs.count - 1 : selectedIndex - 1
            } else if tabIndex == GHOSTTY_GOTO_TAB_NEXT.rawValue {
                finalIndex = selectedIndex == tabs.count - 1 ? 0 : selectedIndex + 1
            } else if tabIndex == GHOSTTY_GOTO_TAB_LAST.rawValue {
                finalIndex = tabs.count - 1
            } else {
                return
            }
        } else {
            // The configured value is 1-indexed. If our index is outside our
            // boundary then we use the max.
            finalIndex = min(Int(tabIndex - 1), tabs.count - 1)
        }

        guard tabs.indices.contains(finalIndex) else { return }
        selectTab(tabs[finalIndex])
    }

    @objc private func onCloseTab(notification: SwiftUI.Notification) {
        guard let target = notification.object as? Zashiki.SurfaceView else { return }
        guard surfaceTree.contains(target) else { return }
        closeTab(self)
    }

    @objc private func onCloseOtherTabs(notification: SwiftUI.Notification) {
        guard let target = notification.object as? Zashiki.SurfaceView else { return }
        guard surfaceTree.contains(target) else { return }
        closeOtherTabs(self)
    }

    @objc private func onCloseTabsOnTheRight(notification: SwiftUI.Notification) {
        guard let target = notification.object as? Zashiki.SurfaceView else { return }
        guard surfaceTree.contains(target) else { return }
        closeTabsOnTheRight(self)
    }

    @objc private func onCloseWindow(notification: SwiftUI.Notification) {
        guard let target = notification.object as? Zashiki.SurfaceView else { return }
        guard surfaceTree.contains(target) else { return }
        closeWindow(self)
    }

    @objc private func onResetWindowSize(notification: SwiftUI.Notification) {
        guard let target = notification.object as? Zashiki.SurfaceView else { return }
        guard surfaceTree.contains(target) else { return }
        returnToDefaultSize(nil)
    }

    @objc private func onToggleFullscreen(notification: SwiftUI.Notification) {
        guard let target = notification.object as? Zashiki.SurfaceView else { return }
        guard target == self.focusedSurface else { return }

        // Get the fullscreen mode we want to toggle
        let fullscreenMode: FullscreenMode
        if let any = notification.userInfo?[Zashiki.Notification.FullscreenModeKey],
           let mode = any as? FullscreenMode {
            fullscreenMode = mode
        } else {
            Zashiki.logger.warning("no fullscreen mode specified or invalid mode, doing nothing")
            return
        }

        toggleFullscreen(mode: fullscreenMode)
    }

    struct DerivedConfig {
        let backgroundColor: Color
        let maximize: Bool
        let windowPositionX: Int16?
        let windowPositionY: Int16?

        init() {
            self.backgroundColor = Color(NSColor.windowBackgroundColor)
            self.maximize = false
            self.windowPositionX = nil
            self.windowPositionY = nil
        }

        init(_ config: Zashiki.Config) {
            self.backgroundColor = config.backgroundColor
            self.maximize = config.maximize
            self.windowPositionX = config.windowPositionX
            self.windowPositionY = config.windowPositionY
        }
    }
}

// MARK: NSMenuItemValidation

extension TerminalController {
    override func validateMenuItem(_ item: NSMenuItem) -> Bool {
        switch item.action {
        case #selector(closeTabsOnTheRight):
            return !tabsOnTheRight.isEmpty

        case #selector(returnToDefaultSize):
            guard let window else { return false }

            // Native fullscreen windows can't revert to default size.
            if window.styleMask.contains(.fullScreen) {
                return false
            }

            // If we're fullscreen at all then we can't change size
            if fullscreenStyle?.isFullscreen ?? false {
                return false
            }

            // If our window is already the default size or we don't have a
            // default size, then disable.
            return defaultSize?.isChanged(for: window) ?? false

        default:
            return super.validateMenuItem(item)
        }
    }
}

// MARK: Default Size

extension TerminalController {
    /// The possible default sizes for a terminal. The size can't purely be known as a
    /// window frame because if we set `window-width/height` then it is based
    /// on content size.
    enum DefaultSize {
        /// A frame, set with `window.setFrame`
        case frame(NSRect)

        /// A content size, set with `window.setContentSize`
        case contentIntrinsicSize

        func isChanged(for window: NSWindow) -> Bool {
            switch self {
            case .frame(let rect):
                return window.frame != rect
            case .contentIntrinsicSize:
                guard let view = window.contentView else {
                    return false
                }

                return view.frame.size != view.intrinsicContentSize
            }
        }

        func apply(to window: NSWindow) {
            switch self {
            case .frame(let rect):
                window.setFrame(rect, display: true)
            case .contentIntrinsicSize:
                guard let size = window.contentView?.intrinsicContentSize else {
                    return
                }

                window.setContentSize(size)
                window.constrainToScreen()
            }
        }
    }

    private var defaultSize: DefaultSize? {
        if derivedConfig.maximize, let screen = window?.screen ?? NSScreen.main {
            // Maximize takes priority, we take up the full screen we're on.
            return .frame(screen.visibleFrame)
        } else if focusedSurface?.initialSize != nil {
            // Initial size as requested by the configuration (e.g. `window-width`)
            // takes next priority.
            return .contentIntrinsicSize
        } else {
            return nil
        }
    }
}
