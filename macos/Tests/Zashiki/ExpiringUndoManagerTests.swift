import AppKit
import Testing
@testable import Zashiki

@MainActor
@Suite
struct ExpiringUndoManagerTests {
    private final class Target {
        var didUndo = false
    }

    @Test func removeAllActionsSafelyClearsExpiringActions() {
        let undoManager = ExpiringUndoManager()
        let target = Target()
        undoManager.groupsByEvent = false
        undoManager.registerUndo(withTarget: target, expiresAfter: .seconds(60)) {
            $0.didUndo = true
        }

        #expect(undoManager.canUndo)
        undoManager.removeAllActions()

        #expect(!undoManager.canUndo)
        #expect(!undoManager.canRedo)
    }

    @Test func removeAllActionsWithTargetPreservesOtherExpiringActions() {
        let undoManager = ExpiringUndoManager()
        let removedTarget = Target()
        let remainingTarget = Target()
        undoManager.groupsByEvent = false
        undoManager.registerUndo(withTarget: removedTarget, expiresAfter: .seconds(60)) {
            $0.didUndo = true
        }
        undoManager.registerUndo(withTarget: remainingTarget, expiresAfter: .seconds(60)) {
            $0.didUndo = true
        }

        undoManager.removeAllActions(withTarget: removedTarget)

        #expect(undoManager.canUndo)
        undoManager.undo()
        #expect(remainingTarget.didUndo)
        #expect(!removedTarget.didUndo)
        #expect(!undoManager.canUndo)
    }
}
