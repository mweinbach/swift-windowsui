import SwiftWindowsUI
import XCTest

@testable import WinSwiftUI

@MainActor
private final class UndoSessionClient: TextInputUndoClient {
    var text: String
    var selection: TextInputUndoSelection
    var permitsUndoReplay = true
    var undoRuntime: RetainedViewRuntime?
    var session: TextInputUndoSession!
    var onRefresh: (() -> Void)?
    var onWrite: ((String, TextInputUndoSelection) -> Void)?
    var writes = 0
    var invalidations = 0

    init(text: String, manager: WinSwiftUI.UndoManager) {
        self.text = text
        selection = TextInputUndoSelection(caret: text.count)
        session = TextInputUndoSession(manager: manager, text: text)
        session.adopt(self, text: text)
    }

    var undoText: String? { text }
    var undoSelection: TextInputUndoSelection? { selection }

    func refreshUndoConfiguration() { onRefresh?() }
    func invalidateUndoDisplay() { invalidations += 1 }

    func applyUndoText(_ text: String, selection: TextInputUndoSelection) {
        writes += 1
        if let onWrite {
            onWrite(text, selection)
        } else {
            self.text = text
            self.selection = selection
            session.adopt(self, text: text)
        }
    }

    func edit(_ text: String, caret: Int? = nil) {
        let mutation = session.beginEdit(before: self.text, expected: text, selection: selection)
        self.text = text
        selection = TextInputUndoSelection(caret: caret ?? text.count)
        session.adopt(self, text: text)
        session.finishEdit(mutation, text: text, selection: selection)
    }
}

@MainActor
private final class UndoSessionCounter {
    var value = 0
}

@MainActor
private final class UndoSessionReleaseCallback {
    let callback: @MainActor () -> Void

    init(_ callback: @escaping @MainActor () -> Void) { self.callback = callback }

    deinit { MainActor.assumeIsolated { callback() } }
}

@MainActor
final class TextInputUndoSessionTests: XCTestCase {
    func testEditStoresOnlyChangedGraphemesIncludingCombiningSequences() async {
        let selection = TextInputUndoSelection(caret: 7)
        let edit = TextInputUndoSession.Edit(
            before: "prefix a suffix", after: "prefix a\u{301} suffix",
            beforeSelection: selection, afterSelection: selection)
        XCTAssertEqual(edit.offset, 7)
        XCTAssertEqual(edit.removed, "a")
        XCTAssertEqual(edit.inserted, "a\u{301}")
    }

    func testDeltaReplayRestoresUnicodeTextAndDirectionalSelectionRepeatedly() async {
        let manager = WinSwiftUI.UndoManager()
        let client = UndoSessionClient(text: "a👩🏽‍💻b", manager: manager)
        client.selection = TextInputUndoSelection(
            caret: 1, selection: RetainedTextSelection(indices: .range(1..<2), affinity: .upstream))
        client.edit("a漢b", caret: 2)

        for _ in 0..<3 {
            manager.undo()
            XCTAssertEqual(client.text, "a👩🏽‍💻b")
            XCTAssertEqual(client.selection.caret, 1)
            XCTAssertEqual(client.selection.selection?.indices, .range(1..<2))
            XCTAssertEqual(client.selection.selection?.affinity, .upstream)
            manager.redo()
            XCTAssertEqual(client.text, "a漢b")
            XCTAssertEqual(client.selection.caret, 2)
            XCTAssertNil(client.selection.selection)
        }
        XCTAssertEqual(client.writes, 6)
    }

    func testCombiningEditUndoDoesNotSplitTheMergedGrapheme() async {
        let manager = WinSwiftUI.UndoManager()
        let client = UndoSessionClient(text: "a", manager: manager)
        client.edit("a\u{301}")
        manager.undo()
        XCTAssertEqual(client.text, "a")
        manager.redo()
        XCTAssertEqual(client.text, "a\u{301}")
        XCTAssertEqual(client.selection.caret, 1)
    }

    func testBlockedPreflightKeepsTheTopActionUntilEligible() async {
        let manager = WinSwiftUI.UndoManager()
        let client = UndoSessionClient(text: "a", manager: manager)
        client.edit("ab")
        client.permitsUndoReplay = false
        manager.undo()
        XCTAssertEqual(client.text, "ab")
        XCTAssertEqual(client.writes, 0)
        XCTAssertTrue(manager.canUndo)
        XCTAssertFalse(manager.canRedo)
        client.permitsUndoReplay = true
        manager.undo()
        XCTAssertEqual(client.text, "a")
        XCTAssertTrue(manager.canRedo)
    }

    func testOriginFilterRejectsAnActionBeforeRefreshingItsOtherOwner() async {
        let manager = WinSwiftUI.UndoManager()
        let client = UndoSessionClient(text: "a", manager: manager)
        client.edit("ab")
        var refreshes = 0
        client.onRefresh = { refreshes += 1 }
        manager.undo(allowingTarget: { _ in false })
        XCTAssertEqual(refreshes, 0)
        XCTAssertEqual(client.text, "ab")
        XCTAssertTrue(manager.canUndo)
        manager.undo()
        XCTAssertEqual(refreshes, 1)
        manager.redo(allowingTarget: { _ in false })
        XCTAssertEqual(refreshes, 1)
        XCTAssertEqual(client.text, "a")
        XCTAssertTrue(manager.canRedo)
    }

    func testExternalWriteBeforeReconciliationClearsOnlyThatSession() async {
        let manager = WinSwiftUI.UndoManager()
        let other = UndoSessionClient(text: "other", manager: manager)
        let client = UndoSessionClient(text: "a", manager: manager)
        other.edit("other edit")
        client.edit("ab")
        client.text = "replacement"

        manager.undo()

        XCTAssertEqual(client.text, "replacement")
        XCTAssertEqual(client.writes, 0)
        XCTAssertTrue(manager.canUndo)
        manager.undo()
        XCTAssertEqual(other.text, "other")
        XCTAssertEqual(client.text, "replacement")
    }

    func testPreflightRebuildCannotPopAReplacementAction() async {
        let manager = WinSwiftUI.UndoManager()
        let client = UndoSessionClient(text: "a", manager: manager)
        let counter = UndoSessionCounter()
        client.edit("ab")
        client.onRefresh = {
            client.onRefresh = nil
            manager.removeAllActions()
            manager.registerUndo(withTarget: counter) { $0.value += 1 }
            manager.setActionName("Replacement")
            manager.undo()
            XCTAssertEqual(counter.value, 0)
        }

        manager.undo()

        XCTAssertEqual(counter.value, 0)
        XCTAssertEqual(client.text, "ab")
        XCTAssertEqual(manager.undoActionName, "Replacement")
        manager.undo()
        XCTAssertEqual(counter.value, 1)
    }

    func testRemovalDuringReplayCannotRegisterAnInverse() async {
        let manager = WinSwiftUI.UndoManager()
        let client = UndoSessionClient(text: "a", manager: manager)
        client.edit("ab")
        client.onWrite = { text, selection in
            client.text = text
            client.selection = selection
            client.session.invalidate()
        }

        manager.undo()

        XCTAssertEqual(client.text, "a")
        XCTAssertFalse(manager.canUndo)
        XCTAssertFalse(manager.canRedo)
        XCTAssertFalse(manager.isUndoing)
        client.onWrite = nil
    }

    func testRejectedReplayDoesNotRegisterAStaleRedo() async {
        let manager = WinSwiftUI.UndoManager()
        let client = UndoSessionClient(text: "a", manager: manager)
        client.edit("ab")
        client.onWrite = { _, _ in }

        manager.undo()

        XCTAssertEqual(client.text, "ab")
        XCTAssertFalse(manager.canUndo)
        XCTAssertFalse(manager.canRedo)
        XCTAssertEqual(client.invalidations, 1)
    }

    func testNormalizedReplayClearsHistoryRatherThanRestoringStaleProposals() async {
        let manager = WinSwiftUI.UndoManager()
        let client = UndoSessionClient(text: "a", manager: manager)
        client.edit("ab")
        client.onWrite = { text, selection in
            client.text = text.uppercased()
            client.selection = selection
            client.session.adopt(client, text: client.text)
        }

        manager.undo()

        XCTAssertEqual(client.text, "A")
        XCTAssertFalse(manager.canUndo)
        XCTAssertFalse(manager.canRedo)
        client.onWrite = nil
    }

    func testReentrantAcceptedEditCannotResurrectTheInterruptedOuterRecord() async {
        let manager = WinSwiftUI.UndoManager()
        let client = UndoSessionClient(text: "a", manager: manager)
        let outer = client.session.beginEdit(before: "a", expected: "ab", selection: client.selection)
        client.text = "ab"
        client.edit("abc")
        client.session.finishEdit(outer, text: client.text, selection: client.selection)

        manager.undo()

        XCTAssertEqual(client.text, "ab")
        XCTAssertFalse(manager.canUndo)
        manager.redo()
        XCTAssertEqual(client.text, "abc")
    }

    func testDisabledRegistrationAcceptedEditInvalidatesOldEditorHistoryOnly() async {
        let manager = WinSwiftUI.UndoManager()
        let client = UndoSessionClient(text: "a", manager: manager)
        let counter = UndoSessionCounter()
        manager.registerUndo(withTarget: counter) { $0.value += 1 }
        manager.setActionName("Application action")
        client.edit("ab")
        manager.disableUndoRegistration()
        client.edit("abc")

        XCTAssertFalse(manager.isUndoRegistrationEnabled)
        XCTAssertEqual(manager.undoActionName, "Application action")
        manager.enableUndoRegistration()
        manager.undo()
        XCTAssertEqual(counter.value, 1)
        XCTAssertEqual(client.text, "abc")
        XCTAssertFalse(manager.canUndo)
    }

    func testNewEditAfterUndoClearsRedoAndUsesCurrentCheckpoint() async {
        let manager = WinSwiftUI.UndoManager()
        let client = UndoSessionClient(text: "a", manager: manager)
        client.edit("ab")
        manager.undo()
        client.edit("ac")
        XCTAssertFalse(manager.canRedo)
        manager.undo()
        XCTAssertEqual(client.text, "a")
        manager.redo()
        XCTAssertEqual(client.text, "ac")
    }

    func testAllClosingSessionsAreInvalidBeforeAnyHistoryIsPurged() async {
        let manager = WinSwiftUI.UndoManager()
        let first = UndoSessionClient(text: "first", manager: manager)
        let second = UndoSessionClient(text: "second", manager: manager)
        first.edit("first edit")
        second.edit("second edit")

        first.session.markInvalid()
        second.session.markInvalid()
        first.session.purgeHistory()
        manager.undo()
        XCTAssertEqual(second.text, "second edit")
        second.session.purgeHistory()
        XCTAssertFalse(manager.canUndo)
        XCTAssertFalse(manager.canRedo)
    }

    func testRemovalDuringRegistrationPruningDoesNotLeaveAnActionOrRenameAnotherTarget() async {
        let manager = WinSwiftUI.UndoManager()
        let client = UndoSessionClient(text: "a", manager: manager)
        let other = UndoSessionCounter()
        client.edit("ab")
        do {
            let expired = UndoSessionCounter()
            let payload = UndoSessionReleaseCallback {
                client.session.invalidate()
                manager.registerUndo(withTarget: other) { $0.value += 1 }
                manager.setActionName("Application cleanup")
            }
            manager.registerUndo(withTarget: expired) { _ in withExtendedLifetime(payload) {} }
        }

        client.edit("abc")

        XCTAssertEqual(manager.undoActionName, "Application cleanup")
        manager.undo()
        XCTAssertEqual(other.value, 1)
        XCTAssertEqual(client.text, "abc")
        XCTAssertFalse(manager.canUndo)
        XCTAssertFalse(manager.canRedo)
    }

    func testRegistrationDisabledByPruningClearsEarlierEditorHistory() async {
        let manager = WinSwiftUI.UndoManager()
        let client = UndoSessionClient(text: "a", manager: manager)
        client.edit("ab")
        do {
            let expired = UndoSessionCounter()
            let payload = UndoSessionReleaseCallback { manager.disableUndoRegistration() }
            manager.registerUndo(withTarget: expired) { _ in withExtendedLifetime(payload) {} }
        }

        client.edit("abc")

        XCTAssertFalse(manager.isUndoRegistrationEnabled)
        XCTAssertFalse(manager.canUndo)
        XCTAssertFalse(manager.canRedo)
        XCTAssertEqual(client.text, "abc")
        manager.enableUndoRegistration()
        client.edit("abcd")
        manager.undo()
        XCTAssertEqual(client.text, "abc")
    }

    func testBeginningAnEditDoesNotCreateATicketAfterHistoryCleanupInvalidatesItsSession() async {
        let manager = WinSwiftUI.UndoManager()
        let client = UndoSessionClient(text: "a", manager: manager)
        client.edit("ab")
        do {
            let target = UndoSessionCounter()
            let payload = UndoSessionReleaseCallback { client.session.invalidate() }
            manager.registerUndo(withTarget: target) { _ in withExtendedLifetime(payload) {} }
        }
        client.text = "XY"

        let mutation = client.session.beginEdit(before: "XY", expected: "XYZ", selection: client.selection)

        XCTAssertNil(mutation)
        XCTAssertFalse(client.session.isValid)
        XCTAssertFalse(manager.canUndo)
        XCTAssertFalse(manager.canRedo)
        XCTAssertEqual(client.text, "XY")
    }

    func testCancellingAnUnwrittenMutationKeepsEarlierHistoryReplayable() async {
        let manager = WinSwiftUI.UndoManager()
        let client = UndoSessionClient(text: "a", manager: manager)
        client.edit("ab")
        let mutation = client.session.beginEdit(before: "ab", expected: "abc", selection: client.selection)
        XCTAssertNotNil(mutation)

        client.session.cancelEdit(mutation)
        manager.undo()

        XCTAssertEqual(client.text, "a")
        XCTAssertTrue(manager.canRedo)
        manager.redo()
        XCTAssertEqual(client.text, "ab")
    }
}
