import Foundation
import WinSwiftUI
import XCTest

@MainActor
private final class UndoManagerValue {
    let manager: WinSwiftUI.UndoManager
    var value = 0

    init(manager: WinSwiftUI.UndoManager) {
        self.manager = manager
    }

    func set(_ newValue: Int, name: String) {
        let previousValue = value
        manager.registerUndo(withTarget: self) { target in
            target.set(previousValue, name: name)
        }
        manager.setActionName(name)
        value = newValue
    }
}

private final class UndoManagerPayload {}

@MainActor
private final class UndoManagerReleaseCallback {
    private let onRelease: @MainActor () -> Void

    init(onRelease: @escaping @MainActor () -> Void) {
        self.onRelease = onRelease
    }

    deinit {
        MainActor.assumeIsolated {
            onRelease()
        }
    }
}

private final class EqualUndoManagerTarget: NSObject {
    var value = 0

    override func isEqual(_ object: Any?) -> Bool {
        object is EqualUndoManagerTarget
    }

    override var hash: Int { 0 }
}

@MainActor
final class UndoManagerTests: XCTestCase {
    func testRegistrationDoesNotRetainUndoTarget() async {
        let manager = WinSwiftUI.UndoManager()
        var target: UndoManagerValue? = UndoManagerValue(manager: manager)
        let observedTarget = { [weak target] in target }
        target?.set(1, name: "Edit")

        target = nil

        XCTAssertNil(observedTarget())
        XCTAssertFalse(manager.canUndo)
        XCTAssertEqual(manager.undoActionName, "")
        manager.undo()
        XCTAssertFalse(manager.canRedo)
    }

    func testDeadUndoTargetPrunesNameAndCapturedPayload() async {
        let manager = WinSwiftUI.UndoManager()
        weak var observedPayload: UndoManagerPayload?
        do {
            let target = UndoManagerValue(manager: manager)
            let payload = UndoManagerPayload()
            observedPayload = payload
            manager.registerUndo(withTarget: target) { target in
                target.value = 1
                withExtendedLifetime(payload) {}
            }
            manager.setActionName("Expired")
        }

        XCTAssertNotNil(observedPayload)
        XCTAssertEqual(manager.undoActionName, "")
        XCTAssertNil(observedPayload)
        XCTAssertFalse(manager.canUndo)
    }

    func testUndoSkipsDeadTopActionWithoutPriorAvailabilityQuery() async {
        let manager = WinSwiftUI.UndoManager()
        let live = UndoManagerValue(manager: manager)
        live.set(1, name: "Live")
        do {
            let expired = UndoManagerValue(manager: manager)
            expired.set(9, name: "Expired")
        }

        manager.undo()

        XCTAssertEqual(live.value, 0)
        XCTAssertFalse(manager.canUndo)
        XCTAssertEqual(manager.redoActionName, "Live")
        manager.redo()
        XCTAssertEqual(live.value, 1)
    }

    func testRedoSkipsDeadTopActionWithoutPriorAvailabilityQuery() async {
        let manager = WinSwiftUI.UndoManager()
        let live = UndoManagerValue(manager: manager)
        do {
            let expired = UndoManagerValue(manager: manager)
            expired.set(9, name: "Expired")
            live.set(1, name: "Live")
            manager.undo()
            manager.undo()
            XCTAssertEqual(expired.value, 0)
        }

        manager.redo()

        XCTAssertEqual(live.value, 1)
        XCTAssertFalse(manager.canRedo)
        XCTAssertEqual(manager.undoActionName, "Live")
    }

    func testDeadRedoTargetPrunesNameAndCapturedPayload() async {
        let manager = WinSwiftUI.UndoManager()
        weak var observedPayload: UndoManagerPayload?
        do {
            let target = UndoManagerValue(manager: manager)
            let payload = UndoManagerPayload()
            observedPayload = payload
            manager.registerUndo(withTarget: target) { target in
                target.manager.registerUndo(withTarget: target) { target in
                    target.value = 1
                    withExtendedLifetime(payload) {}
                }
                target.manager.setActionName("Expired redo")
            }
            manager.undo()
            XCTAssertEqual(manager.redoActionName, "Expired redo")
            withExtendedLifetime(target) {}
        }

        XCTAssertNotNil(observedPayload)
        XCTAssertEqual(manager.redoActionName, "")
        XCTAssertNil(observedPayload)
        XCTAssertFalse(manager.canRedo)
    }

    func testSelectiveRemovalClearsBothStacksAndPreservesOtherTargets() async {
        let manager = WinSwiftUI.UndoManager()
        let first = UndoManagerValue(manager: manager)
        let second = UndoManagerValue(manager: manager)
        first.set(1, name: "First one")
        second.set(1, name: "Second one")
        first.set(2, name: "First two")
        second.set(2, name: "Second two")
        manager.undo()
        manager.undo()

        manager.removeAllActions(withTarget: first)

        XCTAssertEqual(manager.undoActionName, "Second one")
        XCTAssertEqual(manager.redoActionName, "Second two")
        manager.redo()
        XCTAssertEqual(second.value, 2)
        manager.undo()
        manager.undo()
        XCTAssertEqual(second.value, 0)
        XCTAssertEqual(first.value, 1)
        XCTAssertFalse(manager.canUndo)
        manager.redo()
        manager.redo()
        XCTAssertEqual(second.value, 2)
        XCTAssertFalse(manager.canRedo)
    }

    func testSelectiveRemovalUsesObjectIdentityInsteadOfEquality() async {
        let manager = WinSwiftUI.UndoManager()
        let first = EqualUndoManagerTarget()
        let second = EqualUndoManagerTarget()
        XCTAssertEqual(first, second)
        XCTAssertFalse(first === second)
        manager.registerUndo(withTarget: first) { $0.value = 1 }
        manager.setActionName("First")
        manager.registerUndo(withTarget: second) { $0.value = 2 }
        manager.setActionName("Second")

        manager.removeAllActions(withTarget: first)
        manager.removeAllActions(withTarget: 42)
        manager.undo()

        XCTAssertEqual(first.value, 0)
        XCTAssertEqual(second.value, 2)
        XCTAssertFalse(manager.canUndo)
    }

    func testRepeatedUndoRedoPreservesReciprocalRegistrationAndNames() async {
        let manager = WinSwiftUI.UndoManager()
        let target = UndoManagerValue(manager: manager)
        target.set(7, name: "Change value")

        for _ in 0..<4 {
            XCTAssertTrue(manager.canUndo)
            XCTAssertFalse(manager.canRedo)
            XCTAssertEqual(manager.undoActionName, "Change value")
            manager.undo()
            XCTAssertEqual(target.value, 0)
            XCTAssertFalse(manager.canUndo)
            XCTAssertTrue(manager.canRedo)
            XCTAssertEqual(manager.redoActionName, "Change value")
            XCTAssertFalse(manager.isUndoing)
            XCTAssertFalse(manager.isRedoing)
            manager.redo()
            XCTAssertEqual(target.value, 7)
            XCTAssertFalse(manager.isUndoing)
            XCTAssertFalse(manager.isRedoing)
        }
    }

    func testNewRegistrationInvalidatesExistingRedo() async {
        let manager = WinSwiftUI.UndoManager()
        let target = UndoManagerValue(manager: manager)
        target.set(1, name: "Original")
        manager.undo()
        XCTAssertTrue(manager.canRedo)

        target.set(2, name: "Replacement")

        XCTAssertFalse(manager.canRedo)
        XCTAssertEqual(manager.redoActionName, "")
        manager.redo()
        XCTAssertEqual(target.value, 2)
        manager.undo()
        XCTAssertEqual(target.value, 0)
        XCTAssertEqual(manager.redoActionName, "Replacement")
    }

    func testNestedUndoAndRedoInsideUndoKeepOuterPhaseAndHistory() async {
        let manager = WinSwiftUI.UndoManager()
        let older = UndoManagerValue(manager: manager)
        let target = UndoManagerValue(manager: manager)
        older.set(3, name: "Older")
        manager.registerUndo(withTarget: target) { target in
            let manager = target.manager
            XCTAssertTrue(manager.isUndoing)
            XCTAssertFalse(manager.isRedoing)
            target.set(5, name: "Inverse")
            manager.undo()
            XCTAssertEqual(manager.undoActionName, "Older")
            XCTAssertEqual(manager.redoActionName, "Inverse")
            XCTAssertTrue(manager.isUndoing)
            manager.redo()
            XCTAssertTrue(manager.isUndoing)
            XCTAssertFalse(manager.isRedoing)
            XCTAssertEqual(target.value, 5)
            XCTAssertEqual(manager.redoActionName, "Inverse")
        }
        manager.setActionName("Outer")

        manager.undo()

        XCTAssertEqual(older.value, 3)
        XCTAssertEqual(target.value, 5)
        XCTAssertEqual(manager.undoActionName, "Older")
        XCTAssertEqual(manager.redoActionName, "Inverse")
        XCTAssertFalse(manager.isUndoing)
        manager.redo()
        XCTAssertEqual(target.value, 0)
        manager.undo()
        XCTAssertEqual(target.value, 5)
    }

    func testNestedUndoAndRedoInsideRedoKeepOuterPhaseAndHistory() async {
        let manager = WinSwiftUI.UndoManager()
        let older = UndoManagerValue(manager: manager)
        let target = UndoManagerValue(manager: manager)
        older.set(3, name: "Older")
        manager.registerUndo(withTarget: target) { target in
            target.manager.registerUndo(withTarget: target) { target in
                let manager = target.manager
                XCTAssertFalse(manager.isUndoing)
                XCTAssertTrue(manager.isRedoing)
                target.set(5, name: "Inverse")
                manager.undo()
                XCTAssertEqual(target.value, 5)
                XCTAssertEqual(manager.undoActionName, "Inverse")
                XCTAssertTrue(manager.isRedoing)
                manager.redo()
                XCTAssertFalse(manager.isUndoing)
                XCTAssertTrue(manager.isRedoing)
                XCTAssertEqual(target.value, 5)
            }
            target.manager.setActionName("Outer redo")
        }
        manager.undo()

        manager.redo()

        XCTAssertEqual(older.value, 3)
        XCTAssertEqual(target.value, 5)
        XCTAssertEqual(manager.undoActionName, "Inverse")
        XCTAssertFalse(manager.canRedo)
        XCTAssertFalse(manager.isRedoing)
        manager.undo()
        XCTAssertEqual(target.value, 0)
        manager.undo()
        XCTAssertEqual(older.value, 0)
    }

    func testSelectiveCleanupAfterInverseRegistrationKeepsOtherHistoryAndReplayPhase() async {
        let manager = WinSwiftUI.UndoManager()
        let older = UndoManagerValue(manager: manager)
        let target = UndoManagerValue(manager: manager)
        older.set(3, name: "Older")
        manager.registerUndo(withTarget: target) { target in
            let manager = target.manager
            target.set(5, name: "Inverse")
            manager.removeAllActions(withTarget: target)
            manager.setActionName("Discarded inverse")
            manager.undo()
            manager.redo()
            XCTAssertTrue(manager.isUndoing)
            XCTAssertFalse(manager.isRedoing)
            XCTAssertFalse(manager.canRedo)
        }

        manager.undo()

        XCTAssertEqual(older.value, 3)
        XCTAssertEqual(target.value, 5)
        XCTAssertEqual(manager.undoActionName, "Older")
        XCTAssertFalse(manager.canRedo)
        manager.registerUndo(withTarget: target) { $0.value = 0 }
        XCTAssertEqual(manager.undoActionName, "")
        manager.undo()
        XCTAssertEqual(target.value, 0)
        manager.undo()
        XCTAssertEqual(older.value, 0)
    }

    func testGlobalCleanupAfterInverseRegistrationKeepsReplayPhaseUntilReturn() async {
        let manager = WinSwiftUI.UndoManager()
        let older = UndoManagerValue(manager: manager)
        let target = UndoManagerValue(manager: manager)
        older.set(3, name: "Older")
        manager.registerUndo(withTarget: target) { target in
            let manager = target.manager
            target.set(5, name: "Inverse")
            manager.removeAllActions()
            manager.undo()
            manager.redo()
            XCTAssertTrue(manager.isUndoing)
            XCTAssertFalse(manager.isRedoing)
            XCTAssertFalse(manager.canUndo)
            XCTAssertFalse(manager.canRedo)
        }

        manager.undo()

        XCTAssertEqual(older.value, 3)
        XCTAssertEqual(target.value, 5)
        XCTAssertFalse(manager.isUndoing)
        XCTAssertFalse(manager.isRedoing)
        XCTAssertFalse(manager.canUndo)
        XCTAssertFalse(manager.canRedo)
    }

    func testCleanupBeforeExplicitInverseRegistrationAllowsNewReciprocalAction() async {
        for removesEverything in [false, true] {
            let manager = WinSwiftUI.UndoManager()
            let target = UndoManagerValue(manager: manager)
            manager.registerUndo(withTarget: target) { target in
                let manager = target.manager
                if removesEverything {
                    manager.removeAllActions()
                } else {
                    manager.removeAllActions(withTarget: target)
                }
                target.set(5, name: "After cleanup")
                manager.undo()
                manager.redo()
                XCTAssertTrue(manager.isUndoing)
                XCTAssertFalse(manager.isRedoing)
                XCTAssertEqual(target.value, 5)
            }

            manager.undo()

            XCTAssertFalse(manager.canUndo)
            XCTAssertTrue(manager.canRedo)
            XCTAssertEqual(manager.redoActionName, "After cleanup")
            manager.redo()
            XCTAssertEqual(target.value, 0)
            XCTAssertTrue(manager.canUndo)
        }
    }

    func testCleanupDuringRedoKeepsLaterRegistrationOnUndoStack() async {
        for removesEverything in [false, true] {
            let manager = WinSwiftUI.UndoManager()
            let target = UndoManagerValue(manager: manager)
            manager.registerUndo(withTarget: target) { target in
                target.manager.registerUndo(withTarget: target) { target in
                    let manager = target.manager
                    if removesEverything {
                        manager.removeAllActions()
                    } else {
                        manager.removeAllActions(withTarget: target)
                    }
                    target.set(5, name: "After redo cleanup")
                    manager.undo()
                    manager.redo()
                    XCTAssertFalse(manager.isUndoing)
                    XCTAssertTrue(manager.isRedoing)
                }
            }
            manager.undo()

            manager.redo()

            XCTAssertEqual(target.value, 5)
            XCTAssertFalse(manager.canRedo)
            XCTAssertEqual(manager.undoActionName, "After redo cleanup")
            manager.undo()
            XCTAssertEqual(target.value, 0)
        }
    }

    func testTargetReleasedDuringReplayDoesNotLeaveLiveRedo() async {
        let manager = WinSwiftUI.UndoManager()
        var target: UndoManagerValue? = UndoManagerValue(manager: manager)
        let observedTarget = { [weak target] in target }
        manager.registerUndo(withTarget: target!) { liveTarget in
            target = nil
            XCTAssertNotNil(observedTarget())
            liveTarget.set(5, name: "Inverse")
        }

        manager.undo()

        XCTAssertNil(observedTarget())
        XCTAssertFalse(manager.canUndo)
        XCTAssertFalse(manager.canRedo)
        XCTAssertEqual(manager.redoActionName, "")
    }

    func testReplayWithoutInverseDoesNotRenameOtherActionsOrLeakPendingName() async {
        let manager = WinSwiftUI.UndoManager()
        let older = UndoManagerValue(manager: manager)
        let target = UndoManagerValue(manager: manager)
        older.set(3, name: "Older")
        manager.registerUndo(withTarget: target) { target in
            target.manager.setActionName("No inverse")
        }

        manager.undo()

        XCTAssertEqual(manager.undoActionName, "Older")
        XCTAssertFalse(manager.canRedo)
        manager.registerUndo(withTarget: target) { $0.value = 1 }
        XCTAssertEqual(manager.undoActionName, "")
        XCTAssertEqual(older.value, 3)
    }

    func testReplayNameBeforeInverseDoesNotRenameAnOlderRedo() async {
        let manager = WinSwiftUI.UndoManager()
        let target = UndoManagerValue(manager: manager)
        manager.registerUndo(withTarget: target) { target in
            target.manager.setActionName("New inverse")
            target.manager.registerUndo(withTarget: target) { $0.value = 4 }
        }
        target.set(2, name: "Existing redo")
        manager.undo()

        manager.undo()

        XCTAssertEqual(manager.redoActionName, "New inverse")
        manager.redo()
        XCTAssertEqual(target.value, 4)
        XCTAssertEqual(manager.redoActionName, "Existing redo")
    }

    func testRegistrationCanBeDisabledAndEnabledWithBalancedNesting() async {
        let manager = WinSwiftUI.UndoManager()
        let target = UndoManagerValue(manager: manager)
        XCTAssertTrue(manager.isUndoRegistrationEnabled)
        manager.disableUndoRegistration()
        manager.disableUndoRegistration()
        manager.registerUndo(withTarget: target) { $0.value = 1 }
        XCTAssertFalse(manager.isUndoRegistrationEnabled)
        XCTAssertFalse(manager.canUndo)

        manager.enableUndoRegistration()
        manager.registerUndo(withTarget: target) { $0.value = 2 }
        XCTAssertFalse(manager.isUndoRegistrationEnabled)
        XCTAssertFalse(manager.canUndo)
        manager.enableUndoRegistration()
        manager.registerUndo(withTarget: target) { $0.value = 3 }

        XCTAssertTrue(manager.isUndoRegistrationEnabled)
        XCTAssertTrue(manager.canUndo)
        manager.undo()
        XCTAssertEqual(target.value, 3)
    }

    func testDisabledRegistrationPreservesRedoAndPendingActionName() async {
        let manager = WinSwiftUI.UndoManager()
        let target = UndoManagerValue(manager: manager)
        target.set(1, name: "Original")
        manager.undo()
        manager.setActionName("Pending")
        manager.disableUndoRegistration()

        manager.registerUndo(withTarget: target) { $0.value = 2 }

        XCTAssertFalse(manager.canUndo)
        XCTAssertTrue(manager.canRedo)
        XCTAssertEqual(manager.redoActionName, "Original")
        manager.enableUndoRegistration()
        manager.registerUndo(withTarget: target) { $0.value = 3 }
        XCTAssertEqual(manager.undoActionName, "Pending")
        XCTAssertFalse(manager.canRedo)
        manager.undo()
        XCTAssertEqual(target.value, 3)
    }

    func testSelectiveCleanupPreservesNestedRegistrationDisableCount() async {
        let manager = WinSwiftUI.UndoManager()
        let removed = UndoManagerValue(manager: manager)
        let other = UndoManagerValue(manager: manager)
        removed.set(1, name: "Removed")
        other.set(2, name: "Other")
        manager.disableUndoRegistration()
        manager.disableUndoRegistration()

        manager.removeAllActions(withTarget: removed)

        XCTAssertFalse(manager.isUndoRegistrationEnabled)
        XCTAssertEqual(manager.undoActionName, "Other")
        manager.enableUndoRegistration()
        XCTAssertFalse(manager.isUndoRegistrationEnabled)
        manager.enableUndoRegistration()
        XCTAssertTrue(manager.isUndoRegistrationEnabled)
        manager.undo()
        XCTAssertEqual(other.value, 0)
        XCTAssertEqual(removed.value, 1)
        XCTAssertFalse(manager.canUndo)
    }

    func testGlobalCleanupEnablesRegistrationAndClearsPendingNames() async {
        let manager = WinSwiftUI.UndoManager()
        let target = UndoManagerValue(manager: manager)
        target.set(1, name: "Original")
        manager.undo()
        manager.setActionName("Pending")
        manager.disableUndoRegistration()
        manager.disableUndoRegistration()

        manager.removeAllActions()

        XCTAssertTrue(manager.isUndoRegistrationEnabled)
        XCTAssertFalse(manager.canUndo)
        XCTAssertFalse(manager.canRedo)
        XCTAssertEqual(manager.undoActionName, "")
        XCTAssertEqual(manager.redoActionName, "")
        manager.disableUndoRegistration()
        manager.enableUndoRegistration()
        manager.registerUndo(withTarget: target) { $0.value = 2 }
        XCTAssertEqual(manager.undoActionName, "")
        manager.undo()
        XCTAssertEqual(target.value, 2)
    }

    func testDisabledRegistrationStillAllowsExistingUndoAndRedoToExecute() async {
        for performsRedo in [false, true] {
            let manager = WinSwiftUI.UndoManager()
            let target = UndoManagerValue(manager: manager)
            target.set(1, name: "Change")
            if performsRedo { manager.undo() }
            manager.disableUndoRegistration()

            if performsRedo {
                manager.redo()
            } else {
                manager.undo()
            }

            XCTAssertEqual(target.value, performsRedo ? 1 : 0)
            XCTAssertFalse(manager.isUndoRegistrationEnabled)
            XCTAssertFalse(manager.canUndo)
            XCTAssertFalse(manager.canRedo)
            XCTAssertFalse(manager.isUndoing)
            XCTAssertFalse(manager.isRedoing)
            manager.enableUndoRegistration()
        }
    }

    func testGlobalCleanupDuringReplayCanReenableAndRegisterAnInverse() async {
        let manager = WinSwiftUI.UndoManager()
        let target = UndoManagerValue(manager: manager)
        manager.registerUndo(withTarget: target) { target in
            let manager = target.manager
            XCTAssertFalse(manager.isUndoRegistrationEnabled)
            manager.removeAllActions()
            XCTAssertTrue(manager.isUndoRegistrationEnabled)
            XCTAssertTrue(manager.isUndoing)
            target.set(5, name: "After reset")
        }
        manager.disableUndoRegistration()
        manager.disableUndoRegistration()

        manager.undo()

        XCTAssertTrue(manager.isUndoRegistrationEnabled)
        XCTAssertEqual(manager.redoActionName, "After reset")
        XCTAssertFalse(manager.isUndoing)
        manager.redo()
        XCTAssertEqual(target.value, 0)
    }

    func testEmptyUndoAndRedoLeaveReplayFlagsIdle() async {
        let manager = WinSwiftUI.UndoManager()

        manager.undo()
        manager.redo()

        XCTAssertFalse(manager.canUndo)
        XCTAssertFalse(manager.canRedo)
        XCTAssertFalse(manager.isUndoing)
        XCTAssertFalse(manager.isRedoing)
        XCTAssertTrue(manager.isUndoRegistrationEnabled)
    }

    func testRedoInvalidationReleasesCapturedPayloadAfterStackMutation() async {
        let manager = WinSwiftUI.UndoManager()
        let target = UndoManagerValue(manager: manager)
        var didReleasePayload = false
        do {
            let payload = UndoManagerReleaseCallback {
                didReleasePayload = true
                XCTAssertFalse(manager.canRedo)
                manager.registerUndo(withTarget: target) { $0.value = 2 }
                manager.setActionName("Release callback")
            }
            manager.registerUndo(withTarget: target) { target in
                target.manager.registerUndo(withTarget: target) { _ in
                    withExtendedLifetime(payload) {}
                }
            }
            manager.undo()
        }
        XCTAssertFalse(didReleasePayload)

        manager.registerUndo(withTarget: target) { $0.value = 1 }

        XCTAssertTrue(didReleasePayload)
        XCTAssertFalse(manager.canRedo)
        XCTAssertEqual(manager.undoActionName, "Release callback")
        manager.undo()
        XCTAssertEqual(target.value, 2)
        manager.undo()
        XCTAssertEqual(target.value, 1)
        XCTAssertFalse(manager.canUndo)
    }

    func testRegistrationRechecksEnablementAfterPruningPayloads() async {
        let manager = WinSwiftUI.UndoManager()
        let live = UndoManagerValue(manager: manager)
        do {
            let expired = UndoManagerValue(manager: manager)
            let payload = UndoManagerReleaseCallback {
                manager.disableUndoRegistration()
            }
            manager.registerUndo(withTarget: expired) { _ in
                withExtendedLifetime(payload) {}
            }
        }

        manager.registerUndo(withTarget: live) { $0.value = 1 }

        XCTAssertFalse(manager.isUndoRegistrationEnabled)
        XCTAssertFalse(manager.canUndo)
        manager.enableUndoRegistration()
        manager.registerUndo(withTarget: live) { $0.value = 2 }
        manager.undo()
        XCTAssertEqual(live.value, 2)
    }

    func testPruningDuringUndoCannotStartNestedOrOppositeReplay() async {
        let manager = WinSwiftUI.UndoManager()
        let first = UndoManagerValue(manager: manager)
        let second = UndoManagerValue(manager: manager)
        first.set(1, name: "First")
        second.set(2, name: "Second")
        var didReleasePayload = false
        do {
            let expired = UndoManagerValue(manager: manager)
            let payload = UndoManagerReleaseCallback {
                didReleasePayload = true
                XCTAssertFalse(manager.isUndoing)
                XCTAssertFalse(manager.isRedoing)
                manager.undo()
                XCTAssertEqual(second.value, 2)
                XCTAssertEqual(first.value, 1)
                manager.redo()
                XCTAssertEqual(second.value, 2)
            }
            manager.registerUndo(withTarget: expired) { _ in
                withExtendedLifetime(payload) {}
            }
        }

        manager.undo()

        XCTAssertTrue(didReleasePayload)
        XCTAssertEqual(first.value, 1)
        XCTAssertEqual(second.value, 0)
        XCTAssertEqual(manager.undoActionName, "First")
        XCTAssertEqual(manager.redoActionName, "Second")
        manager.removeAllActions()
    }

    func testPruningDuringRedoCannotStartNestedOrOppositeReplay() async {
        let manager = WinSwiftUI.UndoManager()
        let first = UndoManagerValue(manager: manager)
        let second = UndoManagerValue(manager: manager)
        var didReleasePayload = false
        do {
            let expired = UndoManagerValue(manager: manager)
            let payload = UndoManagerReleaseCallback {
                didReleasePayload = true
                XCTAssertFalse(manager.isUndoing)
                XCTAssertFalse(manager.isRedoing)
                manager.redo()
                XCTAssertEqual(first.value, 0)
                XCTAssertEqual(second.value, 0)
                manager.undo()
                XCTAssertEqual(first.value, 0)
            }
            manager.registerUndo(withTarget: expired) { target in
                target.manager.registerUndo(withTarget: target) { _ in
                    withExtendedLifetime(payload) {}
                }
            }
            first.set(1, name: "First")
            second.set(2, name: "Second")
            manager.undo()
            manager.undo()
            manager.undo()
            withExtendedLifetime(expired) {}
        }

        manager.redo()

        XCTAssertTrue(didReleasePayload)
        XCTAssertEqual(first.value, 1)
        XCTAssertEqual(second.value, 0)
        XCTAssertEqual(manager.undoActionName, "First")
        XCTAssertEqual(manager.redoActionName, "Second")
        manager.removeAllActions()
    }

    func testExecutedActionPayloadCannotStartAnotherReplayWhenReleased() async {
        for performsRedo in [false, true] {
            let manager = WinSwiftUI.UndoManager()
            let older = UndoManagerValue(manager: manager)
            let target = UndoManagerValue(manager: manager)
            older.set(1, name: "Older")
            var didReleasePayload = false
            do {
                let payload = UndoManagerReleaseCallback {
                    didReleasePayload = true
                    manager.undo()
                    XCTAssertEqual(older.value, 1)
                    XCTAssertEqual(target.value, 5)
                    manager.redo()
                    XCTAssertEqual(older.value, 1)
                    XCTAssertEqual(target.value, 5)
                }
                if performsRedo {
                    manager.registerUndo(withTarget: target) { target in
                        target.manager.registerUndo(withTarget: target) { target in
                            target.set(5, name: "Executed")
                            withExtendedLifetime(payload) {}
                        }
                    }
                    manager.undo()
                } else {
                    manager.registerUndo(withTarget: target) { target in
                        target.set(5, name: "Executed")
                        withExtendedLifetime(payload) {}
                    }
                }
            }

            if performsRedo {
                manager.redo()
            } else {
                manager.undo()
            }

            XCTAssertTrue(didReleasePayload)
            XCTAssertEqual(older.value, 1)
            XCTAssertEqual(target.value, 5)
            XCTAssertFalse(manager.isUndoing)
            XCTAssertFalse(manager.isRedoing)
            manager.removeAllActions()
        }
    }
}
