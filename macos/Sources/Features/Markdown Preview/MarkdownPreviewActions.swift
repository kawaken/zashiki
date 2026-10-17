import AppKit
import SwiftUI

/// Both the header button and the context menu build their actions here.
struct MarkdownPreviewActions {
    let model: MarkdownPreviewModel
    let configuration: MarkdownExternalAppConfiguration
    let openApp: (MarkdownExternalApp) -> Void
    let showFontSize: () -> Void

    func makeMenu() -> NSMenu {
        let menu = NSMenu()
        let markdown = model.markdownForCopy
        let fileURL = model.fileURL
        let relativePath = model.relativePath

        menu.addItem(MarkdownPreviewMenuItem(title: "Copy Markdown Source", available: markdown != nil) {
            Self.copy(markdown)
        })
        menu.addItem(MarkdownPreviewMenuItem(title: "Copy Absolute Path", available: fileURL != nil) {
            Self.copy(fileURL?.path)
        })
        let relativePathItem = MarkdownPreviewMenuItem(title: "Copy Relative Path", available: relativePath != nil) {
            Self.copy(relativePath)
        }
        relativePathItem.toolTip = model.baseDirectoryURL.map {
            "Relative to the working directory when opened: \($0.path)"
        } ?? "The working directory when opened is unavailable"
        menu.addItem(relativePathItem)
        menu.addItem(.separator())

        let openWith = MarkdownPreviewMenuItem(
            title: "Open With", available: fileURL != nil && !configuration.apps.isEmpty
        ) {}
        let appsMenu = NSMenu()
        for app in configuration.apps {
            let item = MarkdownPreviewMenuItem(title: app.name, available: fileURL != nil) { openApp(app) }
            item.state = app.id == configuration.defaultID ? .on : .off
            appsMenu.addItem(item)
        }
        openWith.submenu = appsMenu
        menu.addItem(openWith)
        menu.addItem(MarkdownPreviewMenuItem(title: "Reveal File in Finder", available: fileURL != nil) {
            guard let fileURL else { return }
            NSWorkspace.shared.activateFileViewerSelecting([fileURL])
        })
        menu.addItem(.separator())
        menu.addItem(MarkdownPreviewMenuItem(title: "Font Size…", action: showFontSize))
        return menu
    }

    private static func copy(_ string: String?) {
        guard let string else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(string, forType: .string)
    }
}

/// Keeps closure targets alive and participates in the original menu's validation.
final class MarkdownPreviewMenuItem: NSMenuItem, NSMenuItemValidation {
    private let available: Bool
    private let perform: () -> Void

    init(title: String, available: Bool = true, action: @escaping () -> Void) {
        self.available = available
        self.perform = action
        super.init(title: title, action: #selector(invoke), keyEquivalent: "")
        target = self
        isEnabled = available
    }

    required init(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool { available }

    @objc private func invoke() {
        guard available else { return }
        perform()
    }
}

struct MarkdownPreviewActionsButton: NSViewRepresentable {
    let makeMenu: () -> NSMenu

    func makeNSView(context: Context) -> MenuButton { MenuButton(makeMenu: makeMenu) }

    func updateNSView(_ button: MenuButton, context: Context) { button.makeMenu = makeMenu }

    final class MenuButton: NSButton {
        var makeMenu: () -> NSMenu

        init(makeMenu: @escaping () -> NSMenu) {
            self.makeMenu = makeMenu
            super.init(frame: .zero)
            image = NSImage(systemSymbolName: "ellipsis", accessibilityDescription: "Markdown Preview Actions")
            imagePosition = .imageOnly
            isBordered = false
            target = self
            action = #selector(showMenu)
            setAccessibilityLabel("Markdown Preview Actions")
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

        @objc private func showMenu() {
            makeMenu().popUp(positioning: nil, at: NSPoint(x: bounds.minX, y: bounds.minY), in: self)
        }
    }
}

/// Textual handles rightMouseDown itself. Preserve its native selection menu
/// through menu(for:), rather than covering it with a SwiftUI contextMenu.
struct MarkdownPreviewContextMenu: NSViewRepresentable {
    let makeMenu: () -> NSMenu

    func makeNSView(context: Context) -> MonitorView { MonitorView(makeMenu: makeMenu) }

    func updateNSView(_ view: MonitorView, context: Context) { view.makeMenu = makeMenu }

    static func dismantleNSView(_ view: MonitorView, coordinator: ()) { view.stopMonitoring() }

    static func appending(_ actions: NSMenu, to existing: NSMenu?) -> NSMenu {
        guard let existing, !existing.items.isEmpty else { return actions }
        existing.addItem(.separator())
        for item in actions.items {
            actions.removeItem(item)
            existing.addItem(item)
        }
        return existing
    }

    final class MonitorView: NSView {
        var makeMenu: () -> NSMenu
        private var eventMonitor: Any?

        init(makeMenu: @escaping () -> NSMenu) {
            self.makeMenu = makeMenu
            super.init(frame: .zero)
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

        // This background only measures the pane; normal input goes to its content.
        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            stopMonitoring()
            guard window != nil else { return }
            eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.rightMouseDown, .leftMouseDown]) { [weak self] event in
                guard let self, let view = self.targetView(for: event) else { return event }
                let menu = MarkdownPreviewContextMenu.appending(self.makeMenu(), to: view.menu(for: event))
                NSMenu.popUpContextMenu(menu, with: event, for: view)
                return nil
            }
        }

        func targetView(for event: NSEvent) -> NSView? {
            guard event.type == .rightMouseDown
                    || (event.type == .leftMouseDown && event.modifierFlags.contains(.control)),
                  let window, window === event.window,
                  !isHiddenOrHasHiddenAncestor,
                  bounds.contains(convert(event.locationInWindow, from: nil)),
                  visibleRect.contains(convert(event.locationInWindow, from: nil)),
                  let contentView = window.contentView else { return nil }
            let point = contentView.superview?.convert(event.locationInWindow, from: nil) ?? event.locationInWindow
            return contentView.hitTest(point)
        }

        func stopMonitoring() {
            if let eventMonitor {
                NSEvent.removeMonitor(eventMonitor)
                self.eventMonitor = nil
            }
        }

        deinit {
            if let eventMonitor { NSEvent.removeMonitor(eventMonitor) }
        }
    }
}
