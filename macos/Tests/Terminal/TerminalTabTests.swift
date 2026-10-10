import AppKit
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
