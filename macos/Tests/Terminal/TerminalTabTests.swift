import AppKit
import SwiftUI
import Testing
@testable import Zashiki

@MainActor
struct TerminalTabTests {
    /// No nib, windows, or processes are needed for these controller operations.
    private final class Controller: TerminalController {
        let testUndoManager = ExpiringUndoManager()
        override var windowNibName: NSNib.Name? { nil }
        override var undoManager: ExpiringUndoManager? { testUndoManager }
    }

    private func controller() throws -> Controller {
        let app = try #require((NSApp.delegate as? AppDelegate)?.ghostty)
        return Controller(app, withSurfaceTree: .init())
    }

    @Test func titlebarTabHitTestingDoesNotAdvertiseWindowDragging() throws {
        let tab = TerminalTab()
        let container = TerminalViewContainer {
            TerminalTabItem(
                tab: tab, isSelected: true, shortcut: "⌘1", showsBellInTitle: false,
                canCloseOthers: false, canCloseRight: false,
                onSelect: {}, onClose: {}, onAction: { _ in }, onMove: { _, _ in })
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        let window = TerminalWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 36),
                                    styleMask: [.titled], backing: .buffered, defer: false)
        window.awakeFromNib()
        window.contentView = container
        container.layoutSubtreeIfNeeded()
        #expect(!window.isMovable)
        let hosting = try #require(container.subviews.first)
        #expect(!container.mouseDownCanMoveWindow)
        #expect(!hosting.mouseDownCanMoveWindow)

        func findTab(in view: NSView) -> TerminalTabItemView? {
            if let tab = view as? TerminalTabItemView { return tab }
            return view.subviews.lazy.compactMap { findTab(in: $0) }.first
        }
        let tabView = try #require(findTab(in: hosting))
        #expect(tabView.bounds.width > 0)
        #expect(tabView.bounds.height > 0)
        // Title, shortcut, and empty padding must all reach the drag source,
        // including the top of the tab that overlaps the native titlebar.
        let bounds = tabView.bounds
        for point in [NSPoint(x: bounds.midX, y: 1), NSPoint(x: bounds.midX, y: bounds.midY),
                      NSPoint(x: bounds.maxX - 20, y: bounds.midY)] {
            let hit = tabView.hitTest(tabView.convert(point, to: tabView.superview))
            #expect(hit === tabView)
            #expect(hit?.mouseDownCanMoveWindow == false)
        }
    }

    @Test func dragBoundariesPreserveSelectionAndTabIdentity() throws {
        let controller = try controller()
        let tabs = [TerminalTab(), TerminalTab(), TerminalTab()]
        controller.replaceTabs(tabs, selected: tabs[1])
        tabs[2].titleOverride = "third"
        tabs[2].color = .green

        controller.tabBarDidMove(tabs[2].id, relativeTo: tabs[0], after: false)
        #expect(controller.tabs.map(\.id) == [tabs[2].id, tabs[0].id, tabs[1].id])
        #expect(controller.selectedTab === tabs[1])
        #expect(controller.tabs[0].title == "third")
        #expect(controller.tabs[0].color == .green)

        controller.tabBarDidMove(tabs[2].id, relativeTo: tabs[1], after: true)
        #expect(controller.tabs.map(\.id) == tabs.map(\.id))
        controller.tabBarDidMove(tabs[0].id, relativeTo: tabs[1], after: false)
        #expect(controller.tabs.map(\.id) == tabs.map(\.id))
        controller.tabBarDidMove(UUID(), relativeTo: tabs[0], after: true)
        #expect(controller.tabs.map(\.id) == tabs.map(\.id))
        controller.tabBarDidPerform(.rename, on: tabs[0])
        #expect(tabs[0].isEditingTitle)
        controller.selectTab(tabs[1])
        #expect(!tabs[0].isEditingTitle)
        controller.promptTabTitle()
        #expect(tabs[1].isEditingTitle)
    }

    @Test func backgroundContextMenuUsesClickedTabAndCanUndo() throws {
        let controller = try controller()
        let tabs = [TerminalTab(), TerminalTab(), TerminalTab(), TerminalTab()]
        controller.replaceTabs(tabs, selected: tabs[0])
        controller.tabBarDidPerform(.setTitle("background"), on: tabs[2])
        controller.tabBarDidPerform(.setColor(.blue), on: tabs[2])
        #expect(controller.selectedTab === tabs[0])
        #expect(tabs[2].titleOverride == "background")
        #expect(tabs[2].color == .blue)
        controller.tabBarDidPerform(.closeRight, on: tabs[1])
        #expect(controller.tabs.map(\.id) == Array(tabs.prefix(2)).map(\.id))
        #expect(controller.selectedTab === tabs[0])
        controller.testUndoManager.undo()
        #expect(controller.tabs.map(\.id) == tabs.map(\.id))
        #expect(controller.tabs[2] === tabs[2])
        controller.testUndoManager.redo()
        #expect(controller.tabs.map(\.id) == Array(tabs.prefix(2)).map(\.id))
    }

    @Test func closeOthersKeepsBackgroundTargetAndEmptyNameRestoresAutomaticTitle() throws {
        let controller = try controller()
        let tabs = [TerminalTab(), TerminalTab(), TerminalTab()]
        controller.replaceTabs(tabs, selected: tabs[0])
        controller.tabBarDidPerform(.setTitle("custom"), on: tabs[1])
        controller.tabBarDidPerform(.setTitle(""), on: tabs[1])
        #expect(tabs[1].titleOverride == nil)
        controller.tabBarDidPerform(.closeOthers, on: tabs[1])
        #expect(controller.tabs.count == 1)
        #expect(controller.selectedTab === tabs[1])
        controller.testUndoManager.undo()
        #expect(controller.tabs.map(\.id) == tabs.map(\.id))
    }
}
