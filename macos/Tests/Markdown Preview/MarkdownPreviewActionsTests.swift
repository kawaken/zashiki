import AppKit
import Testing
@testable import Zashiki

@MainActor
struct MarkdownPreviewActionsTests {
    private func makeMenu(
        model: MarkdownPreviewModel,
        configuration: MarkdownExternalAppConfiguration = .initial
    ) -> NSMenu {
        MarkdownPreviewActions(model: model, configuration: configuration, openApp: { _ in }, showFontSize: {}).makeMenu()
    }

    private func openFile(in model: MarkdownPreviewModel, baseDirectory: Bool = true) throws {
        let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".md")
        try "# Preview".write(to: fileURL, atomically: true, encoding: .utf8)
        model.open(url: fileURL, baseDirectoryURL: baseDirectory ? fileURL.deletingLastPathComponent() : nil)
    }

    @Test func unavailableActionsStayDisabledDuringNativeMenuValidation() {
        _ = NSApplication.shared
        let menu = makeMenu(model: MarkdownPreviewModel())
        menu.update()
        let items = menu.items.filter { !$0.isSeparatorItem }
        #expect(items.dropLast().allSatisfy { !$0.isEnabled })
        #expect(items.last?.title == "Font Size…")
        #expect(items.last?.isEnabled == true)
        #expect(items.first { $0.submenu != nil }?.submenu?.items.allSatisfy { !$0.isEnabled } == true)

        var invoked = false
        let disabled = MarkdownPreviewMenuItem(title: "Unavailable", available: false) { invoked = true }
        let testMenu = NSMenu()
        testMenu.addItem(disabled)
        testMenu.performActionForItem(at: 0)
        #expect(!invoked)
    }

    @Test func readErrorDisablesSourceButKeepsFileActions() throws {
        _ = NSApplication.shared
        let model = MarkdownPreviewModel()
        try openFile(in: model)
        var menu = makeMenu(model: model)
        menu.update()
        #expect(menu.items.filter { !$0.isSeparatorItem }.allSatisfy { $0.isEnabled })

        let missing = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".md")
        model.open(url: missing, baseDirectoryURL: missing.deletingLastPathComponent())
        menu = makeMenu(model: model)
        menu.update()
        #expect(menu.items[0].isEnabled == false)
        #expect(menu.items[1].isEnabled)
        #expect(menu.items[2].isEnabled)
        #expect(menu.items[4].isEnabled)
        #expect(menu.items[5].isEnabled)
    }

    @Test func missingBaseAndExternalAppsDisableOnlyTheirActions() throws {
        _ = NSApplication.shared
        let model = MarkdownPreviewModel()
        try openFile(in: model, baseDirectory: false)
        let menu = makeMenu(model: model, configuration: .init(apps: [], defaultID: nil))
        menu.update()
        #expect(menu.items[0].isEnabled)
        #expect(menu.items[1].isEnabled)
        #expect(!menu.items[2].isEnabled)
        #expect(!menu.items[4].isEnabled)
        #expect(menu.items[5].isEnabled)
        #expect(menu.items.last?.isEnabled == true)
    }

    @Test func defaultAppAndActionsSurviveMovingIntoSelectionMenu() throws {
        _ = NSApplication.shared
        let model = MarkdownPreviewModel()
        try openFile(in: model)
        let configuration = MarkdownExternalAppConfiguration.initial
        var openedApp: MarkdownExternalApp?
        var fontSizeShown = false
        let actions = MarkdownPreviewActions(
            model: model, configuration: configuration,
            openApp: { openedApp = $0 }, showFontSize: { fontSizeShown = true }
        ).makeMenu()
        let existing = NSMenu()
        let copy = NSMenuItem(title: "Copy Selection", action: #selector(NSText.copy(_:)), keyEquivalent: "")
        existing.addItem(copy)
        let merged = MarkdownPreviewContextMenu.appending(actions, to: existing)

        #expect(merged === existing)
        #expect(merged.autoenablesItems)
        #expect(merged.items[0] === copy)
        #expect(copy.action == #selector(NSText.copy(_:)))
        #expect(copy.target == nil)
        #expect(merged.items[1].isSeparatorItem)
        let apps = try #require(merged.items.first { $0.submenu != nil }?.submenu)
        #expect(apps.items.map(\.state) == [.on, .off])
        apps.performActionForItem(at: 1)
        #expect(openedApp == configuration.apps[1])
        merged.performActionForItem(at: merged.items.count - 1)
        #expect(fontSizeShown)
    }

    @Test func emptySelectionMenuDoesNotAddLeadingSeparator() {
        let actions = makeMenu(model: MarkdownPreviewModel())
        let merged = MarkdownPreviewContextMenu.appending(actions, to: NSMenu())
        #expect(merged === actions)
        #expect(merged.items.first?.isSeparatorItem == false)
    }

    @Test func contextMenuOnlyHandlesContextClicksInsideItsVisiblePane() throws {
        _ = NSApplication.shared
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 200),
            styleMask: .borderless, backing: .buffered, defer: false
        )
        let content = try #require(window.contentView)
        let target = NSView(frame: NSRect(x: 200, y: 0, width: 200, height: 200))
        let monitor = MarkdownPreviewContextMenu.MonitorView(makeMenu: { NSMenu() })
        monitor.frame = target.frame
        content.addSubview(target)
        content.addSubview(monitor)
        window.orderFront(nil)
        defer {
            monitor.removeFromSuperview()
            window.orderOut(nil)
        }

        func event(_ type: NSEvent.EventType, x: CGFloat = 250, flags: NSEvent.ModifierFlags = []) throws -> NSEvent {
            try #require(NSEvent.mouseEvent(
                with: type, location: NSPoint(x: x, y: 100), modifierFlags: flags,
                timestamp: 0, windowNumber: window.windowNumber, context: nil,
                eventNumber: 0, clickCount: 1, pressure: 1
            ))
        }

        #expect(monitor.targetView(for: try event(.rightMouseDown)) === target)
        #expect(monitor.targetView(for: try event(.leftMouseDown, flags: .control)) === target)
        #expect(monitor.targetView(for: try event(.leftMouseDown)) == nil)
        #expect(monitor.targetView(for: try event(.rightMouseDown, x: 50)) == nil)
        #expect(monitor.targetView(for: try event(.rightMouseUp)) == nil)
        target.isHidden = true
        monitor.isHidden = true
        #expect(monitor.targetView(for: try event(.rightMouseDown)) == nil)
    }
}
