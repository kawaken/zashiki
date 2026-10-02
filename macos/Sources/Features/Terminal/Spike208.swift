import AppKit

// SPIKE for #208 (throwaway): checks whether the native tab bar can be inset
// between the side panels. Enabled only when ZASHIKI_SPIKE_DIR is set.
@MainActor
enum Spike208 {
    static let outDir = ProcessInfo.processInfo.environment["ZASHIKI_SPIKE_DIR"]
    static let stage = ProcessInfo.processInfo.environment["ZASHIKI_SPIKE_STAGE"] ?? "baseline"
    static var started = false

    /// Height of the title row (the titlebar without the tab bar).
    static let titleRowHeight: CGFloat = 32
    static var isInset: Bool { outDir != nil && stage == "inset" }
    static var applyCount = 0
    static var observed: Set<ObjectIdentifier> = []

    static func start(_ controller: TerminalController, ghostty: Zashiki.App) {
        guard outDir != nil, !started else { return }
        started = true
        after(1.5) {
            controller.worktreeStatus.open()
            if let md = ProcessInfo.processInfo.environment["ZASHIKI_SPIKE_MD"] {
                controller.markdownPreview.open(url: URL(fileURLWithPath: md))
            }
            _ = TerminalController.newTab(ghostty, from: controller.window)
            after(1.0) {
                _ = TerminalController.newTab(ghostty, from: controller.window)
                after(2.0) {
                    if isInset {
                        for window in controller.window?.tabGroup?.windows ?? [] {
                            window.styleMask.insert(.fullSizeContentView)
                        }
                    }
                    after(0.5) {
                        let selected = controller.window?.tabGroup?.selectedWindow ?? controller.window
                        applyInset(selected)
                        after(1.0) {
                            if let selected { dump(selected, name: "\(stage)-1-third-tab") }
                            // Switch back to the first tab (the one with the preview).
                            controller.window?.makeKeyAndOrderFront(nil)
                            after(0.5) {
                                applyInset(controller.window)
                                after(1.0) {
                                    if let window = controller.window { dump(window, name: "\(stage)-2-first-tab") }
                                    // Add a tab without re-applying, to see whether the inset survives.
                                    _ = TerminalController.newTab(ghostty, from: controller.window)
                                    after(2.0) {
                                        let selected = controller.window?.tabGroup?.selectedWindow
                                        if let selected { dump(selected, name: "\(stage)-3-new-tab-no-reapply") }
                                        after(0.5) { exit(0) }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    /// Moves the tab bar's clip view so it only spans the area between the side panels.
    static func applyInset(_ window: NSWindow?) {
        guard isInset, let window,
              let controller = window.windowController as? TerminalController,
              let tabBar = window.tabBarView,
              let clip = tabBar.firstSuperview(withClassName: "NSTitlebarAccessoryClipView"),
              let wrapper = clip.superview else { return }
        clearTitlebarBackground(window)
        let width = wrapper.bounds.width
        let hasLeft = controller.worktreeStatus.isVisible || controller.agentStatus.isVisible
        let left = hasLeft ? (width * 0.3).rounded() : 0
        let right = controller.markdownPreview.isVisible ? ((width - left) * 0.3).rounded() : 0
        let target = NSRect(x: left, y: clip.frame.minY, width: width - left - right, height: clip.frame.height)
        if clip.frame != target {
            clip.frame = target
            applyCount += 1
        }
        if observed.insert(ObjectIdentifier(clip)).inserted {
            clip.postsFrameChangedNotifications = true
            NotificationCenter.default.addObserver(
                forName: NSView.frameDidChangeNotification, object: clip, queue: .main
            ) { [weak clip] _ in
                MainActor.assumeIsolated { applyInset(clip?.window) }
            }
        }
    }

    /// Lets the content view show through the titlebar so the panels are
    /// visible in the tab bar row.
    static func clearTitlebarBackground(_ window: NSWindow) {
        guard isInset, let titlebarView = window.titlebarView else { return }
        titlebarView.layer?.backgroundColor = NSColor.clear.cgColor
        for view in window.contentView?.superview?.subviews ?? []
        where view.className.contains("BackdropView") {
            view.isHidden = true
        }
    }

    static func after(_ seconds: Double, _ block: @escaping () -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: block)
    }

    static func dump(_ window: NSWindow, name: String) {
        guard let outDir, let root = window.contentView?.superview else { return }
        clearTitlebarBackground(window)
        var lines: [String] = []
        func walk(_ view: NSView, _ depth: Int, _ inTitlebar: Bool) {
            let frame = view.convert(view.bounds, to: nil)
            let desc = "\(view.className) x=\(Int(frame.minX)) y=\(Int(frame.minY)) "
                + "w=\(Int(frame.width)) h=\(Int(frame.height)) hidden=\(view.isHidden) "
                + "tamic=\(view.translatesAutoresizingMaskIntoConstraints)"
            lines.append(String(repeating: "  ", count: depth) + desc)
            let titlebar = inTitlebar || view.className.contains("Titlebar")
            guard titlebar ? depth < 9 : depth < 3 else { return }
            for sub in view.subviews { walk(sub, depth + 1, titlebar) }
        }
        walk(root, 0, false)
        lines.append("windowFrame=\(window.frame)")
        lines.append("contentLayoutRect=\(window.contentLayoutRect)")
        lines.append("safeArea=\(String(describing: window.contentView?.safeAreaInsets))")
        lines.append("fullSizeContentView=\(window.styleMask.contains(.fullSizeContentView))")
        lines.append("tabs=\(window.tabGroup?.windows.count ?? 0)")
        lines.append("applyCount=\(applyCount)")
        try? lines.joined(separator: "\n").write(
            toFile: "\(outDir)/\(name).txt", atomically: true, encoding: .utf8)
        if let rep = root.bitmapImageRepForCachingDisplay(in: root.bounds) {
            root.cacheDisplay(in: root.bounds, to: rep)
            try? rep.representation(using: .png, properties: [:])?
                .write(to: URL(fileURLWithPath: "\(outDir)/\(name).png"))
        }
    }
}
