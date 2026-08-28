import SwiftWindowsCore
import SwiftWindowsGraphics
@preconcurrency import XCTest

@testable import SwiftWindowsPlatform
@testable import SwiftWindowsUI
@testable import WinSwiftUI

@MainActor
final class RetainedAlertHostTests: XCTestCase {
    func testBackgroundEditorStateSelectionAndUndoSurviveAcceptedAlertRemoval() async throws {
        try withTextLayout {
            let model = RetainedAlertModel(kind: .custom, presented: false)
            let fixture = RetainedAlertHost(model: model)
            defer { fixture.close() }
            let background = try fixture.node("alert.background")
            let shell = try XCTUnwrap(background.parent)
            let editor = try fixture.editor()
            let text = try XCTUnwrap(fixture.background.text)
            let selection = try XCTUnwrap(fixture.background.selection)
            let count = try XCTUnwrap(fixture.background.count)
            let manager = try XCTUnwrap(fixture.background.manager)
            XCTAssertNotNil(editor.textInputController)
            fixture.runtime.requestFocus(editor)
            XCTAssertTrue(fixture.runtime.focusedNode === editor)
            fixture.type("🧑‍🚀")
            XCTAssertEqual(text.wrappedValue, "A🧑‍🚀Z")
            XCTAssertTrue(manager.canUndo)
            selection.wrappedValue = retainedAlertSelection(0..<1, in: text.wrappedValue)
            count.wrappedValue = 12
            fixture.flush()

            model.presented = true
            fixture.rebuild()

            XCTAssertTrue(try fixture.node("alert.background") === background)
            XCTAssertTrue(background.parent === shell)
            XCTAssertTrue(try fixture.editor() === editor)
            XCTAssertNotNil(editor.textInputController)
            XCTAssertEqual(text.wrappedValue, "A🧑‍🚀Z")
            XCTAssertEqual(count.wrappedValue, 12)
            XCTAssertEqual(editor.textInputSelection?.indices, .range(0..<1))
            XCTAssertEqual(editor.textInputCaretOffset, 1)
            XCTAssertEqual(retainedAlertSelectionOffsets(selection.wrappedValue, in: text.wrappedValue), 0..<1)
            try fixture.focusButton("alert.choose")
            manager.undo()
            fixture.flush()
            XCTAssertEqual(text.wrappedValue, "A🧑‍🚀Z", "The alert must block background undo without removing it")
            XCTAssertTrue(manager.canUndo)
            XCTAssertFalse(manager.canRedo)

            try fixture.activate("alert.choose")

            XCTAssertFalse(model.presented)
            XCTAssertFalse(fixture.containsAlert)
            XCTAssertTrue(try fixture.node("alert.background") === background)
            XCTAssertTrue(background.parent === shell)
            XCTAssertTrue(try fixture.editor() === editor)
            XCTAssertNotNil(editor.textInputController)
            XCTAssertTrue(
                fixture.runtime.focusedNode === editor, "Restore the actual surviving editor after accepted absence")
            XCTAssertEqual(count.wrappedValue, 12)
            XCTAssertEqual(editor.textInputSelection?.indices, .range(0..<1))
            XCTAssertTrue(manager.canUndo)
            fixture.key(0x5A, modifiers: [.control])
            XCTAssertEqual(text.wrappedValue, RetainedAlertBackground.seed)
            XCTAssertEqual(editor.textInputSelection?.indices, .range(1..<3))
            XCTAssertEqual(retainedAlertSelectionOffsets(selection.wrappedValue, in: text.wrappedValue), 1..<3)
            XCTAssertTrue(manager.canRedo)
            fixture.key(0x59, modifiers: [.control])
            XCTAssertEqual(text.wrappedValue, "A🧑‍🚀Z")
            XCTAssertEqual(editor.textInputCaretOffset, 2)
            XCTAssertTrue(manager.canUndo)
            XCTAssertFalse(manager.canRedo)
        }
    }

    func testCustomActionRebuildsMountedStateBeforeExactlyOneCapturedReset() async throws {
        try withTextLayout {
            let model = RetainedAlertModel(kind: .custom)
            let fixture = RetainedAlertHost(model: model)
            defer {
                model.onAction = nil
                model.onReset = nil
                fixture.close()
            }
            let count = try XCTUnwrap(fixture.background.count)
            let background = try fixture.node("alert.background")
            let button = try fixture.button("alert.choose")
            let copiedAction = try XCTUnwrap(button.onActivate)
            var countsAtReset: [Int] = []
            var renderedCountsAtReset: [String?] = []
            model.onAction = { [weak model] _, _ in
                model?.version = 1
                count.wrappedValue += 1
            }
            model.onReset = { [weak fixture] in
                countsAtReset.append(count.wrappedValue)
                renderedCountsAtReset.append(
                    fixture?.nodes.first { $0.accessibilityIdentifier == "alert.background.count" }?.text)
            }
            model.clearAccesses()

            try fixture.activate("alert.choose")

            XCTAssertEqual(model.events, [.action("choose", 0), .reset(0)])
            XCTAssertEqual(model.actionPresentationStates, [true])
            XCTAssertEqual(
                model.resetVersions, [0], "The admitted action keeps its captured reset through a same-session rebuild")
            XCTAssertEqual(countsAtReset, [8])
            XCTAssertEqual(
                renderedCountsAtReset, ["Count: 8"], "The State write actually adopted a new tree before reset")
            XCTAssertEqual(count.wrappedValue, 8)
            XCTAssertTrue(try fixture.node("alert.background") === background)
            XCTAssertFalse(model.presented)
            XCTAssertFalse(fixture.containsAlert)
            assertInert(copiedAction, model: model, fixture: fixture)
        }
    }

    func testLegacyAndGeneratedOKActionsResetExactlyOnce() async throws {
        try withTextLayout {
            for kind in [RetainedAlertKind.legacy, .legacyFallback, .builderFallback] {
                let model = RetainedAlertModel(kind: kind)
                let fixture = RetainedAlertHost(model: model)
                defer { fixture.close() }
                let label = kind == .legacy ? "Legacy choose" : "OK"
                let button = try fixture.button(label: label)
                let action = try XCTUnwrap(button.onActivate)
                XCTAssertEqual(
                    fixture.alertButtons.count, 1, "An empty actions builder supplies OK, not an extra Cancel")
                model.clearAccesses()

                try fixture.activate(label: label)

                let expected: [RetainedAlertEvent] =
                    kind == .legacy ? [.action("legacy", 0), .reset(0)] : [.reset(0)]
                XCTAssertEqual(model.events, expected)
                XCTAssertEqual(model.resetVersions, [0])
                XCTAssertFalse(model.presented)
                XCTAssertFalse(fixture.containsAlert)
                assertInert(action, model: model, fixture: fixture)
            }
        }
    }

    func testAcceptedItemReplacementNeverRevivesAnOldButtonAction() async throws {
        try withTextLayout {
            let model = RetainedAlertModel(kind: .item)
            let fixture = RetainedAlertHost(model: model)
            defer { fixture.close() }
            let firstID = try XCTUnwrap(model.item).id
            let firstAction = try XCTUnwrap(try fixture.button(label: "Choose First").onActivate)
            model.item = RetainedAlertItem(id: RetainedAlertID(value: 2), title: "Second")
            fixture.rebuild()
            let secondAction = try XCTUnwrap(try fixture.button(label: "Choose Second").onActivate)
            assertInert(firstAction, model: model, fixture: fixture)

            model.item = RetainedAlertItem(id: firstID, title: "First again")
            fixture.rebuild()

            assertInert(firstAction, model: model, fixture: fixture)
            assertInert(secondAction, model: model, fixture: fixture)
            XCTAssertEqual(model.item?.id, firstID)
            model.clearAccesses()
            try fixture.activate(label: "Choose First again")
            XCTAssertEqual(model.events, [.action("item:1", 0), .reset(0)])
            XCTAssertNil(model.item)
            XCTAssertFalse(fixture.containsAlert)
        }
    }

    func testRemovingAndReplacingButtonsRetiresCopiedActivateAndRepeatActions() async throws {
        try withTextLayout {
            let model = RetainedAlertModel(kind: .custom)
            let fixture = RetainedAlertHost(model: model)
            defer { fixture.close() }
            let original = try fixture.button("alert.choose")
            let originalAction = try XCTUnwrap(original.onActivate)
            let originalRepeat = try XCTUnwrap(original.onRepeatActivate)
            model.showsPrimary = false
            fixture.rebuild()
            XCTAssertFalse(fixture.contains("alert.choose"))
            XCTAssertTrue(fixture.containsAlert)
            assertInert(originalAction, model: model, fixture: fixture)
            assertInert(originalRepeat, model: model, fixture: fixture)

            model.showsPrimary = true
            model.buttonIdentity = "second"
            model.version = 1
            fixture.rebuild()
            let second = try fixture.button("alert.choose")
            let secondAction = try XCTUnwrap(second.onActivate)
            let secondRepeat = try XCTUnwrap(second.onRepeatActivate)
            XCTAssertFalse(second === original)
            model.buttonIdentity = "third"
            model.version = 2
            fixture.rebuild()

            assertInert(originalAction, model: model, fixture: fixture)
            assertInert(originalRepeat, model: model, fixture: fixture)
            assertInert(secondAction, model: model, fixture: fixture)
            assertInert(secondRepeat, model: model, fixture: fixture)
            XCTAssertTrue(model.presented)
            model.clearAccesses()
            let current = try fixture.focusButton("alert.choose")
            try XCTUnwrap(current.onRepeatActivate)()
            fixture.flush()
            XCTAssertEqual(model.events, [.action("choose", 2), .reset(2)])
            XCTAssertFalse(model.presented)
            XCTAssertFalse(fixture.containsAlert)
        }
    }

    func testActionInstallingPlainItemReplacementSkipsOldResetButRendersTheReplacement() async throws {
        try withTextLayout {
            let model = RetainedAlertModel(kind: .item)
            let fixture = RetainedAlertHost(model: model)
            defer {
                model.onAction = nil
                fixture.close()
            }
            let oldAction = try XCTUnwrap(try fixture.button(label: "Choose First").onActivate)
            model.onAction = { [weak model] _, _ in
                // No State write, observation, or explicit host reload occurs
                // here. The alert operation still owes its control invalidation.
                model?.version = 1
                model?.item = RetainedAlertItem(id: RetainedAlertID(value: 2), title: "Second")
            }
            model.clearAccesses()

            try fixture.activate(label: "Choose First")

            XCTAssertEqual(model.events, [.action("item:1", 0)])
            XCTAssertTrue(model.resetVersions.isEmpty)
            XCTAssertEqual(model.item?.id, RetainedAlertID(value: 2))
            XCTAssertNotNil(try fixture.button(label: "Choose Second"))
            XCTAssertTrue(try fixture.overlay().accessibilityTraits.contains(.isModal))
            assertInert(oldAction, model: model, fixture: fixture)
            model.onAction = nil
            model.clearAccesses()
            try fixture.activate(label: "Choose Second")
            XCTAssertEqual(model.events, [.action("item:2", 1), .reset(1)])
            XCTAssertNil(model.item)
        }
    }

    func testActionClosingTheHostDoesNotResetOrRestoreFocusAfterClose() async throws {
        try withTextLayout {
            let model = RetainedAlertModel(kind: .custom, presented: false)
            let fixture = RetainedAlertHost(model: model)
            defer {
                model.onAction = nil
                fixture.close()
            }
            let editor = try fixture.editor()
            fixture.runtime.requestFocus(editor)
            model.presented = true
            fixture.rebuild()
            var closeCalls = 0
            fixture.host.onWindowClosed = { _ in closeCalls += 1 }
            model.onAction = { [weak fixture] _, _ in fixture?.close() }
            let oldAction = try XCTUnwrap(try fixture.button("alert.choose").onActivate)
            model.clearAccesses()

            try fixture.activate("alert.choose")

            XCTAssertEqual(closeCalls, 1)
            XCTAssertEqual(model.events, [.action("choose", 0)])
            XCTAssertTrue(model.resetVersions.isEmpty)
            XCTAssertTrue(model.presented)
            XCTAssertNil(fixture.runtime.focusedNode)
            _ = fixture.runtime.renderScene(at: fixture.clock.now + 1)
            XCTAssertNil(fixture.runtime.focusedNode, "A delayed restoration cannot refocus a closed host")
            assertInert(oldAction, model: model, fixture: fixture)
        }
    }

    func testRejectedResetKeepsModalFocusAndAllowsAnotherSeparateAttempt() async throws {
        try withTextLayout {
            let model = RetainedAlertModel(kind: .custom, presented: false)
            let fixture = RetainedAlertHost(model: model)
            defer {
                model.onReset = nil
                fixture.close()
            }
            let editor = try fixture.editor()
            fixture.runtime.requestFocus(editor)
            model.presented = true
            fixture.rebuild()
            let button = try fixture.focusButton("alert.choose")
            let overlay = try fixture.overlay()
            var focusAtReset: [Bool] = []
            var modalAtReset: [Bool] = []
            model.onReset = { [weak fixture, weak button, weak overlay] in
                focusAtReset.append(fixture?.runtime.focusedNode === button)
                modalAtReset.append(overlay?.accessibilityTraits.contains(.isModal) == true)
            }
            model.acceptsReset = false
            model.clearAccesses()

            try fixture.activate("alert.choose")

            XCTAssertEqual(model.events, [.action("choose", 0), .reset(0)])
            XCTAssertTrue(model.presented)
            XCTAssertTrue(try fixture.overlay() === overlay)
            XCTAssertTrue(overlay.accessibilityTraits.contains(.isModal))
            XCTAssertTrue(fixture.runtime.focusedNode === button)
            XCTAssertEqual(focusAtReset, [true])
            XCTAssertEqual(modalAtReset, [true])
            model.acceptsReset = true

            try fixture.activate("alert.choose")

            XCTAssertEqual(model.events, [.action("choose", 0), .reset(0), .action("choose", 0), .reset(0)])
            XCTAssertEqual(model.resetVersions, [0, 0])
            XCTAssertEqual(focusAtReset, [true, true])
            XCTAssertEqual(modalAtReset, [true, true])
            XCTAssertFalse(model.presented)
            XCTAssertFalse(fixture.containsAlert)
            XCTAssertTrue(fixture.runtime.focusedNode === editor)
        }
    }

    func testRawSnapshotAlertAndCustomActionWorkWithoutAStateCoordinator() async throws {
        try withTextLayout {
            let model = RetainedAlertModel(kind: .custom)
            let view = RetainedAlertOwner(base: Color.white, model: model)
            let snapshot = WinSwiftUIRendererSnapshotter.snapshot(
                of: view, size: IntSize(width: 640, height: 480), timestamp: 5_000)
            defer {
                snapshot.runtime.stopRenderLifecycleCallbacks()
                snapshot.runtime.cancelRenderLifecycleTasks()
            }
            let overlay = try XCTUnwrap(
                retainedAlertNodes(in: snapshot.runtime.root).first { $0.nodeTag == "alert-overlay" })
            let button = try XCTUnwrap(
                retainedAlertNodes(in: overlay).first { $0.accessibilityIdentifier == "alert.choose" })
            XCTAssertTrue(overlay.accessibilityTraits.contains(.isModal))
            XCTAssertFalse(snapshot.scene.layers.isEmpty)
            XCTAssertFalse(snapshot.frame.commands.isEmpty)
            snapshot.runtime.requestFocus(button)
            XCTAssertTrue(snapshot.runtime.focusedNode === button)
            model.clearAccesses()

            try XCTUnwrap(button.onActivate)()

            XCTAssertEqual(model.events, [.action("choose", 0), .reset(0)])
            XCTAssertFalse(model.presented)
            // A snapshot's invalidation handler is intentionally empty. A new
            // snapshot observes the accepted model value without a live host.
            let dismissed = WinSwiftUIRendererSnapshotter.snapshot(
                of: view, size: IntSize(width: 640, height: 480), timestamp: 5_001)
            defer {
                dismissed.runtime.stopRenderLifecycleCallbacks()
                dismissed.runtime.cancelRenderLifecycleTasks()
            }
            XCTAssertFalse(retainedAlertNodes(in: dismissed.runtime.root).contains { $0.nodeTag == "alert-overlay" })
        }
    }

    func testPresentingDataUsesItsFirstAcceptedSnapshotUntilTheNextPresentation() async throws {
        try withTextLayout {
            let model = RetainedAlertModel(kind: .data)
            let fixture = RetainedAlertHost(model: model)
            defer { fixture.close() }
            XCTAssertEqual(try fixture.node("alert.data.message").text, "Payload: Alpha")
            model.data = RetainedAlertData(value: "Beta")
            model.version = 1
            fixture.rebuild()

            XCTAssertEqual(try fixture.node("alert.data.message").text, "Payload: Alpha")
            model.clearAccesses()
            try fixture.activate("alert.data.choose")
            XCTAssertEqual(model.events, [.action("data:Alpha", 1), .reset(1)])
            XCTAssertFalse(model.presented)
            model.presented = true
            fixture.rebuild()
            XCTAssertEqual(try fixture.node("alert.data.message").text, "Payload: Beta")
            model.clearAccesses()
            try fixture.activate("alert.data.choose")
            XCTAssertEqual(model.events, [.action("data:Beta", 1), .reset(1)])
            XCTAssertFalse(model.presented)
        }
    }

    func testClosingOneHostDoesNotRetireAnotherHostsAcceptedActions() async throws {
        try withTextLayout {
            let firstModel = RetainedAlertModel(kind: .custom)
            let secondModel = RetainedAlertModel(kind: .custom)
            let first = RetainedAlertHost(model: firstModel)
            let second = RetainedAlertHost(model: secondModel)
            defer {
                first.close()
                second.close()
            }
            let firstAction = try XCTUnwrap(try first.button("alert.choose").onActivate)
            let secondButton = try second.focusButton("alert.choose")
            let secondAction = try XCTUnwrap(secondButton.onActivate)
            first.close()

            assertInert(firstAction, model: firstModel, fixture: first)
            XCTAssertTrue(firstModel.presented)
            XCTAssertTrue(secondModel.presented)
            XCTAssertTrue(second.runtime.focusedNode === secondButton)
            secondModel.clearAccesses()
            secondAction()
            second.flush()

            XCTAssertEqual(secondModel.events, [.action("choose", 0), .reset(0)])
            XCTAssertFalse(secondModel.presented)
            XCTAssertFalse(second.containsAlert)
            XCTAssertTrue(firstModel.events.isEmpty)
        }
    }

    func testRawAlertActionRequiresAttachmentEvenWhileItsRuntimeIsAlive() async throws {
        try withTextLayout {
            let model = RetainedAlertModel(kind: .custom)
            let runtime = makeRawRuntime()
            defer {
                runtime.stopRenderLifecycleCallbacks()
                runtime.cancelRenderLifecycleTasks()
            }
            var invalidations = 0
            let node = makeRawComponent(model: model) { invalidations += 1 }.makeNode(runtime: runtime)
            node.frame = Rect(x: 0, y: 0, width: 640, height: 480)
            let button = try XCTUnwrap(
                retainedAlertNodes(in: node).first { $0.accessibilityIdentifier == "alert.choose" })
            let action = try XCTUnwrap(button.onActivate)
            let repeatAction = try XCTUnwrap(button.onRepeatActivate)
            XCTAssertNil(node.parent)
            XCTAssertTrue(runtime.root.children.isEmpty)
            model.clearAccesses()

            // Construction alone does not admit raw actions. Keep the runtime
            // alive so this refusal specifically exercises the detached tree.
            withExtendedLifetime(runtime) {
                action()
                repeatAction()
                XCTAssertTrue(model.getterVersions.isEmpty)
                XCTAssertTrue(model.events.isEmpty)
                XCTAssertTrue(model.resetVersions.isEmpty)
                XCTAssertTrue(model.presented)
                XCTAssertEqual(invalidations, 0)
                XCTAssertNil(runtime.focusedNode)
            }
            withExtendedLifetime(node) {}
        }
    }

    func testRawAlertNodeAndCopiedActionsDoNotOwnOrOutliveTheirRuntimeAuthority() async throws {
        try withTextLayout {
            let model = RetainedAlertModel(kind: .custom)
            var invalidations = 0
            weak var releasedRuntime: RetainedViewRuntime?
            var retainedNode: ViewNode?
            var retainedAction: (() -> Void)?
            var retainedRepeat: (() -> Void)?
            do {
                let runtime = makeRawRuntime()
                let node = makeRawComponent(model: model) { invalidations += 1 }.makeNode(runtime: runtime)
                node.frame = Rect(x: 0, y: 0, width: 640, height: 480)
                runtime.root.addChild(node)
                _ = runtime.renderScene(at: 5_000)
                let button = try XCTUnwrap(
                    retainedAlertNodes(in: node).first { $0.accessibilityIdentifier == "alert.choose" })
                XCTAssertTrue(node.parent === runtime.root)
                releasedRuntime = runtime
                retainedNode = node
                retainedAction = try XCTUnwrap(button.onActivate)
                retainedRepeat = try XCTUnwrap(button.onRepeatActivate)
                withExtendedLifetime(runtime) {}
            }

            // Retaining a previously attached raw tree and its action copies
            // must not keep the runtime alive or preserve input authority.
            XCTAssertNil(releasedRuntime)
            let node = try XCTUnwrap(retainedNode)
            let action = try XCTUnwrap(retainedAction)
            let repeatAction = try XCTUnwrap(retainedRepeat)
            model.clearAccesses()
            action()
            repeatAction()
            XCTAssertTrue(model.getterVersions.isEmpty)
            XCTAssertTrue(model.events.isEmpty)
            XCTAssertTrue(model.resetVersions.isEmpty)
            XCTAssertTrue(model.presented)
            XCTAssertEqual(invalidations, 0)
            withExtendedLifetime(node) {}
        }
    }

    func testCurrentEscapeDismissesAfterAnUnrelatedMountedStateRebuild() async throws {
        try withTextLayout {
            let model = RetainedAlertModel(kind: .builderFallback)
            let fixture = RetainedAlertHost(model: model)
            defer { fixture.close() }
            let originalButton = try fixture.button(label: "OK")
            fixture.runtime.requestFocus(originalButton)
            let count = try XCTUnwrap(fixture.background.count)
            model.version = 1
            count.wrappedValue += 1
            fixture.flush()
            let currentButton = try fixture.button(label: "OK")
            XCTAssertTrue(currentButton === originalButton)
            XCTAssertEqual(try fixture.node("alert.background.count").text, "Count: 8")
            fixture.runtime.requestFocus(currentButton)
            XCTAssertTrue(fixture.runtime.focusedNode === currentButton)
            model.clearAccesses()

            fixture.runtime.keyDown(KeyboardEvent(keyCode: KeyboardKey.escape.rawValue))
            fixture.flush()

            XCTAssertFalse(model.presented)
            XCTAssertFalse(fixture.containsAlert)
            XCTAssertEqual(model.events, [.reset(1)])
            XCTAssertEqual(model.resetVersions, [1])
            XCTAssertEqual(count.wrappedValue, 8)
        }
    }

    func testOneRawComponentCanMaterializeInTwoRuntimesAndRematerializeInOne() async throws {
        try withTextLayout {
            let model = RetainedAlertModel(kind: .custom)
            var invalidations = 0
            let component = makeRawComponent(model: model) { invalidations += 1 }
            let firstRuntime = makeRawRuntime()
            let secondRuntime = makeRawRuntime()
            let firstHost = ComponentHost(runtime: firstRuntime)
            let secondHost = ComponentHost(runtime: secondRuntime)
            defer {
                firstRuntime.stopRenderLifecycleCallbacks()
                firstRuntime.cancelRenderLifecycleTasks()
                secondRuntime.stopRenderLifecycleCallbacks()
                secondRuntime.cancelRenderLifecycleTasks()
            }
            firstHost.setContent(component)
            secondHost.setContent(component)
            _ = firstRuntime.renderFrame(at: 5_000)
            _ = secondRuntime.renderFrame(at: 5_000)
            let firstButton = try XCTUnwrap(
                retainedAlertNodes(in: firstRuntime.root).first { $0.accessibilityIdentifier == "alert.choose" })
            let secondButton = try XCTUnwrap(
                retainedAlertNodes(in: secondRuntime.root).first { $0.accessibilityIdentifier == "alert.choose" })
            let firstAction = try XCTUnwrap(firstButton.onActivate)
            let firstRepeat = try XCTUnwrap(firstButton.onRepeatActivate)
            let secondAction = try XCTUnwrap(secondButton.onActivate)
            model.clearAccesses()

            firstAction()

            XCTAssertEqual(model.events, [.action("choose", 0), .reset(0)])
            XCTAssertFalse(model.presented)

            // Raw clients own model updates and materialization. Reuse the
            // same Component, whose authored binding/action captured version 0.
            model.presented = true
            model.version = 7
            firstHost.setContent(component)
            _ = firstRuntime.renderFrame(at: 5_001)
            let displacedButton = try XCTUnwrap(
                retainedAlertNodes(in: firstRuntime.root).first { $0.accessibilityIdentifier == "alert.choose" })
            let displacedAction = try XCTUnwrap(displacedButton.onActivate)
            let displacedRepeat = try XCTUnwrap(displacedButton.onRepeatActivate)
            // This receipt has never fired. Its refusal must be caused by
            // replacement, not by a prior successful dismissal of its own.
            firstHost.setContent(component)
            _ = firstRuntime.renderFrame(at: 5_002)
            let invalidationsBeforeStaleCopies = invalidations
            model.clearAccesses()
            firstAction()
            firstRepeat()
            displacedAction()
            displacedRepeat()
            XCTAssertTrue(model.getterVersions.isEmpty)
            XCTAssertTrue(model.events.isEmpty)
            XCTAssertTrue(model.resetVersions.isEmpty)
            XCTAssertTrue(model.presented)
            XCTAssertEqual(invalidations, invalidationsBeforeStaleCopies)
            let currentButton = try XCTUnwrap(
                retainedAlertNodes(in: firstRuntime.root).first { $0.accessibilityIdentifier == "alert.choose" })
            try XCTUnwrap(currentButton.onActivate)()
            XCTAssertEqual(model.events, [.action("choose", 0), .reset(0)])
            XCTAssertFalse(model.presented)

            // Rematerializing the first tree cannot retire the still-current
            // action installed from that same Component in the second tree.
            model.presented = true
            model.clearAccesses()
            secondAction()
            XCTAssertEqual(model.events, [.action("choose", 0), .reset(0)])
            XCTAssertFalse(model.presented)
            XCTAssertEqual(invalidations, 3)
            withExtendedLifetime((firstHost, secondHost, firstRuntime, secondRuntime)) {}
        }
    }

    func testActionAcceptedAbsenceDefersFocusUntilReturnAndReplacementCancelsIt() async throws {
        try withTextLayout {
            for reopensBeforeReturning in [false, true] {
                let model = RetainedAlertModel(kind: .custom, presented: false)
                let fixture = RetainedAlertHost(model: model, addsEarlierControl: true)
                defer {
                    model.onAction = nil
                    fixture.close()
                }
                let editor = try fixture.editor()
                let earlier = try fixture.node("alert.background.earlier")
                XCTAssertTrue(fixture.nodes.first { $0.isFocusable } === earlier)
                fixture.runtime.requestFocus(editor)
                XCTAssertTrue(fixture.runtime.focusedNode === editor)
                model.presented = true
                fixture.rebuild()
                var acceptedAbsenceInsideAction = false
                var backgroundFocusInsideAction: [Bool] = []
                model.onAction = { [weak model, weak fixture, weak editor] _, _ in
                    guard let model, let fixture, let editor else { return }
                    model.presented = false
                    fixture.rebuild()
                    acceptedAbsenceInsideAction = !fixture.containsAlert
                    backgroundFocusInsideAction.append(fixture.runtime.focusedNode === editor)
                    if reopensBeforeReturning {
                        model.presented = true
                        model.version = 1
                        fixture.rebuild()
                        backgroundFocusInsideAction.append(fixture.runtime.focusedNode === editor)
                    }
                }
                model.clearAccesses()

                try fixture.activate("alert.choose")

                XCTAssertTrue(acceptedAbsenceInsideAction)
                XCTAssertEqual(backgroundFocusInsideAction, reopensBeforeReturning ? [false, false] : [false])
                XCTAssertEqual(model.events, [.action("choose", 0)])
                XCTAssertTrue(
                    model.resetVersions.isEmpty, "The authored action already removed its accepted presentation")
                XCTAssertEqual(model.presented, reopensBeforeReturning)
                XCTAssertEqual(fixture.containsAlert, reopensBeforeReturning)
                XCTAssertFalse(fixture.runtime.focusedNode === earlier)
                if reopensBeforeReturning {
                    XCTAssertTrue(try fixture.overlay().accessibilityTraits.contains(.isModal))
                    XCTAssertFalse(
                        fixture.runtime.focusedNode === editor, "A replacement cancels the old restoration ticket")
                } else {
                    XCTAssertTrue(fixture.runtime.focusedNode === editor)
                }
            }
        }
    }

    func testItemReplacementPreservesTheOriginalNonfirstBackgroundFocusTarget() async throws {
        try withTextLayout {
            let model = RetainedAlertModel(kind: .item)
            model.item = nil
            let fixture = RetainedAlertHost(model: model, addsEarlierControl: true)
            defer { fixture.close() }
            let editor = try fixture.editor()
            let earlier = try fixture.node("alert.background.earlier")
            XCTAssertTrue(fixture.nodes.first { $0.isFocusable } === earlier)
            fixture.runtime.requestFocus(editor)
            XCTAssertTrue(fixture.runtime.focusedNode === editor)
            model.item = RetainedAlertItem(id: RetainedAlertID(value: 1), title: "First")
            fixture.rebuild()
            let firstButton = try fixture.button(label: "Choose First")
            fixture.runtime.requestFocus(firstButton)
            XCTAssertTrue(fixture.runtime.focusedNode === firstButton)

            model.item = RetainedAlertItem(id: RetainedAlertID(value: 2), title: "Second")
            model.version = 1
            fixture.rebuild()
            model.clearAccesses()
            try fixture.activate(label: "Choose Second")

            XCTAssertEqual(model.events, [.action("item:2", 1), .reset(1)])
            XCTAssertNil(model.item)
            XCTAssertFalse(fixture.containsAlert)
            XCTAssertTrue(try fixture.editor() === editor)
            XCTAssertTrue(fixture.runtime.focusedNode === editor)
            XCTAssertFalse(fixture.runtime.focusedNode === earlier)
            XCTAssertFalse(fixture.runtime.focusedNode === firstButton)
        }
    }

    private func makeRawRuntime() -> RetainedViewRuntime {
        let runtime = RetainedViewRuntime(root: ViewNode())
        runtime.setRootSize(IntSize(width: 640, height: 480))
        return runtime
    }

    private func makeRawComponent(model: RetainedAlertModel, onInvalidate: @escaping () -> Void) -> Component {
        let context = ViewBuildContext(
            canvasSizeProvider: { Size(width: 640, height: 480) }, invalidateHandler: onInvalidate)
        return RetainedAlertOwner(base: Color.white, model: model).makeComponent(context: context)
    }

    private func assertInert(
        _ action: () -> Void, model: RetainedAlertModel, fixture: RetainedAlertHost,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        let reads = model.getterVersions
        let events = model.events
        let resets = model.resetVersions
        let reloads = fixture.host.executedReloadCount
        let focus = fixture.runtime.focusedNode
        action()
        fixture.flush()
        XCTAssertEqual(
            model.getterVersions, reads, "A retired action must refuse before reading a binding", file: file, line: line
        )
        XCTAssertEqual(model.events, events, file: file, line: line)
        XCTAssertEqual(model.resetVersions, resets, file: file, line: line)
        XCTAssertEqual(fixture.host.executedReloadCount, reloads, file: file, line: line)
        XCTAssertTrue(fixture.runtime.focusedNode === focus, file: file, line: line)
    }

    private func withTextLayout(_ body: () throws -> Void) throws {
        let previous = NativeTextRenderer.testingOverrides
        NativeTextRenderer.testingOverrides.layout = { text, style, _, _ in
            let glyphs = Array(text).enumerated().map { index, character in
                NativeTextGlyphLayout(
                    character: character, origin: Point(x: Double(index) * 9, y: 0), advance: 9,
                    glyphID: UInt32(index + 1), fontFamily: style.fontFamily, weight: style.weight,
                    fontSize: style.nativeFontPixelSize, sourceIndex: index)
            }
            let size = Size(width: Double(max(text.count, 1)) * 9, height: max(style.nativeFontPixelSize, 1))
            return NativeTextLayoutResult(
                lines: [NativeTextLineLayout(text: text, width: size.width, height: size.height, glyphs: glyphs)],
                contentSize: size, measuredSize: size)
        }
        defer { NativeTextRenderer.testingOverrides = previous }
        try body()
    }
}

private enum RetainedAlertKind: Equatable {
    case custom
    case legacy
    case legacyFallback
    case builderFallback
    case item
    case data
}

private enum RetainedAlertEvent: Equatable {
    case action(String, Int)
    case reset(Int)
}

private struct RetainedAlertID: Hashable, CustomStringConvertible {
    let value: Int
    var description: String { "shared alert ID description" }
}

private struct RetainedAlertItem: Identifiable {
    let id: RetainedAlertID
    let title: String
}

private struct RetainedAlertData {
    let value: String
}

@MainActor
private final class RetainedAlertModel {
    let kind: RetainedAlertKind
    var presented: Bool
    var item: RetainedAlertItem? = RetainedAlertItem(id: RetainedAlertID(value: 1), title: "First")
    var data: RetainedAlertData? = RetainedAlertData(value: "Alpha")
    var version = 0
    var showsPrimary = true
    var buttonIdentity = "first"
    var acceptsReset = true
    var getterVersions: [Int] = []
    var resetVersions: [Int] = []
    var events: [RetainedAlertEvent] = []
    var actionPresentationStates: [Bool] = []
    var onAction: (@MainActor (String, Int) -> Void)?
    var onReset: (@MainActor () -> Void)?

    init(kind: RetainedAlertKind, presented: Bool = true) {
        self.kind = kind
        self.presented = presented
    }

    var hasPresentation: Bool { kind == .item ? item != nil : presented }

    func clearAccesses() {
        getterVersions.removeAll()
        resetVersions.removeAll()
        events.removeAll()
        actionPresentationStates.removeAll()
    }

    func booleanBinding(version: Int) -> Binding<Bool> {
        Binding(
            get: {
                self.getterVersions.append(version)
                return self.presented
            },
            set: {
                self.recordReset(version)
                if self.acceptsReset { self.presented = $0 }
            })
    }

    func itemBinding(version: Int) -> Binding<RetainedAlertItem?> {
        Binding(
            get: {
                self.getterVersions.append(version)
                return self.item
            },
            set: {
                self.recordReset(version)
                if self.acceptsReset { self.item = $0 }
            })
    }

    func perform(_ key: String, version: Int) {
        events.append(.action(key, version))
        actionPresentationStates.append(hasPresentation)
        onAction?(key, version)
    }

    private func recordReset(_ version: Int) {
        resetVersions.append(version)
        events.append(.reset(version))
        onReset?()
    }
}

@MainActor
private struct RetainedAlertOwner<Base: View>: View {
    let base: Base
    let model: RetainedAlertModel

    var body: some View {
        let version = model.version
        let binding = model.booleanBinding(version: version)
        switch model.kind {
        case .custom:
            return AnyView(
                base.alert("Retained alert", isPresented: binding) {
                    RetainedAlertActions(model: model, version: version)
                } message: {
                    Text("Message \(version)")
                })
        case .legacy:
            return AnyView(
                base.alert(isPresented: binding) {
                    Alert(
                        title: Text("Legacy alert"),
                        dismissButton: .default(Text("Legacy choose")) { model.perform("legacy", version: version) })
                })
        case .legacyFallback:
            return AnyView(base.alert(isPresented: binding) { Alert(title: Text("Legacy fallback")) })
        case .builderFallback:
            return AnyView(base.alert(Text("Builder fallback"), isPresented: binding) {})
        case .item:
            return AnyView(
                base.alert(item: model.itemBinding(version: version)) { item in
                    Alert(
                        title: Text(item.title),
                        dismissButton: .default(Text("Choose \(item.title)")) {
                            model.perform("item:\(item.id.value)", version: version)
                        })
                })
        case .data:
            return AnyView(
                base.alert("Data alert", isPresented: binding, presenting: model.data) { data in
                    Button("Use data") { model.perform("data:\(data.value)", version: version) }
                        .accessibilityIdentifier("alert.data.choose")
                } message: { data in
                    Text("Payload: \(data.value)").accessibilityIdentifier("alert.data.message")
                })
        }
    }
}

@MainActor
private struct RetainedAlertActions: View {
    let model: RetainedAlertModel
    let version: Int

    var body: some View {
        HStack {
            if model.showsPrimary {
                Button("Choose") { model.perform("choose", version: version) }
                    .accessibilityIdentifier("alert.choose")
                    .id(model.buttonIdentity)
            }
            Button("Cancel", role: .cancel) { model.perform("cancel", version: version) }
                .accessibilityIdentifier("alert.cancel")
        }
    }
}

@MainActor
private final class RetainedAlertBackgroundRecord {
    var showsEarlierControl = false
    var text: Binding<String>?
    var selection: Binding<TextSelection?>?
    var count: Binding<Int>?
    weak var manager: WinSwiftUI.UndoManager?
}

@MainActor
private struct RetainedAlertBackground: View {
    static let seed = "A👩🏽‍💻e\u{301}Z"
    @Environment(\.undoManager) private var manager
    @State private var text: String
    @State private var selection: TextSelection?
    @State private var count = 7
    let record: RetainedAlertBackgroundRecord

    init(record: RetainedAlertBackgroundRecord) {
        self.record = record
        _text = State(initialValue: Self.seed)
        _selection = State(initialValue: retainedAlertSelection(1..<3, in: Self.seed))
    }

    var body: some View {
        record.text = $text
        record.selection = $selection
        record.count = $count
        record.manager = manager
        return VStack(alignment: .leading, spacing: 8) {
            if record.showsEarlierControl {
                Button("Earlier control") {}.accessibilityIdentifier("alert.background.earlier")
            }
            TextEditor(text: $text, selection: $selection)
                .accessibilityIdentifier("alert.background.editor")
                .frame(width: 320, height: 120)
            Text("Count: \(count)").accessibilityIdentifier("alert.background.count")
            Button("Other control") {}.accessibilityIdentifier("alert.background.other")
        }
        .accessibilityIdentifier("alert.background")
    }
}

@MainActor
private final class RetainedAlertRootControl {
    var revision: Binding<Int>?
}

@MainActor
private struct RetainedAlertRoot: View {
    @State private var revision = 0
    let control: RetainedAlertRootControl
    let model: RetainedAlertModel
    let background: RetainedAlertBackgroundRecord

    var body: some View {
        control.revision = $revision
        let _ = revision
        return RetainedAlertOwner(base: RetainedAlertBackground(record: background), model: model)
    }
}

@MainActor
private final class RetainedAlertHost {
    let host: WinSwiftUIWindowHost
    let window: Win32Window
    let clock: RuntimeTestClock
    let background: RetainedAlertBackgroundRecord
    private let control: RetainedAlertRootControl

    var runtime: RetainedViewRuntime { host.hostedRuntime }
    var nodes: [ViewNode] { retainedAlertNodes(in: runtime.root) }
    var containsAlert: Bool { nodes.contains { $0.nodeTag == "alert-overlay" } }
    var alertButtons: [ViewNode] {
        guard let overlay = nodes.first(where: { $0.nodeTag == "alert-overlay" }) else { return [] }
        return retainedAlertNodes(in: overlay).filter { $0.isFocusable && $0.onActivate != nil }
    }

    init(model: RetainedAlertModel, addsEarlierControl: Bool = false) {
        let clock = RuntimeTestClock()
        clock.now = 5_000
        let control = RetainedAlertRootControl()
        let background = RetainedAlertBackgroundRecord()
        background.showsEarlierControl = addsEarlierControl
        let size = IntSize(width: 640, height: 480)
        let surface = SurfaceDescriptor(offscreenPixelSize: size, scaleFactor: 1)
        let window = Win32Window(title: "Retained alert host", clientSize: size)
        window.testScaleFactorOverride = 1
        window.testMonitorRefreshRateOverride = 60
        let host = WinSwiftUIWindowHost(
            configuration: WindowGroupConfiguration(
                title: "Retained alert host", size: size, clearColor: .black,
                content: [AnyView(RetainedAlertRoot(control: control, model: model, background: background))]),
            platformWindow: window, renderer: FakeRenderBackend(), batchRenderer: FakeBatchRenderBackend(),
            surfaceDescriptorProvider: { _ in surface }, startupProbeConfiguration: nil)
        self.clock = clock
        self.control = control
        self.background = background
        self.window = window
        self.host = host
        host.frameClock = { clock.now }
        host.hostedRuntime.clock = { clock.now }
        host.windowDidCreate(window)
        flush()
        host.resetObservabilityCounters()
    }

    func close() { host.windowWillClose(window) }

    func flush() {
        for _ in 0..<3 {
            clock.now += 0.02
            host.windowNeedsDisplay(window)
        }
    }

    func rebuild() {
        guard let revision = control.revision else { return XCTFail("Missing mounted root revision") }
        revision.wrappedValue += 1
        flush()
    }

    func contains(_ identifier: String) -> Bool { nodes.contains { $0.accessibilityIdentifier == identifier } }

    func node(_ identifier: String) throws -> ViewNode {
        let matches = nodes.filter { $0.accessibilityIdentifier == identifier }
        XCTAssertEqual(matches.count, 1, "Expected one \(identifier)")
        return try XCTUnwrap(matches.first)
    }

    func editor() throws -> ViewNode {
        let editor = try node("alert.background.editor")
        XCTAssertTrue(editor.accessibilityTraits.contains(.isTextInput))
        return editor
    }

    func overlay() throws -> ViewNode {
        let matches = nodes.filter { $0.nodeTag == "alert-overlay" }
        XCTAssertEqual(matches.count, 1)
        return try XCTUnwrap(matches.first)
    }

    func button(_ identifier: String) throws -> ViewNode {
        let identified = try node(identifier)
        return try XCTUnwrap(retainedAlertNodes(in: identified).first { $0.isFocusable && $0.onActivate != nil })
    }

    func button(label: String) throws -> ViewNode {
        let matches = alertButtons.filter { retainedAlertNodes(in: $0).contains { $0.text == label } }
        XCTAssertEqual(matches.count, 1, "Expected one button labeled \(label)")
        return try XCTUnwrap(matches.first)
    }

    @discardableResult
    func focusButton(_ identifier: String) throws -> ViewNode {
        let button = try button(identifier)
        runtime.requestFocus(button)
        XCTAssertTrue(runtime.focusedNode === button)
        return button
    }

    func activate(_ identifier: String) throws {
        try focusButton(identifier)
        key(KeyboardKey.enter.rawValue)
    }

    func activate(label: String) throws {
        let button = try button(label: label)
        runtime.requestFocus(button)
        XCTAssertTrue(runtime.focusedNode === button)
        key(KeyboardKey.enter.rawValue)
    }

    func key(_ code: UInt32, modifiers: KeyboardModifiers = []) {
        host.window(
            window, keyDown: KeyboardEvent(keyCode: code, modifiers: modifiers, textInputDelivery: .systemCharacter))
        flush()
    }

    func type(_ text: String) {
        host.window(window, didInputText: text)
        flush()
    }
}

@MainActor
private func retainedAlertNodes(in root: ViewNode) -> [ViewNode] {
    var result: [ViewNode] = []
    var pending = [root]
    while let node = pending.popLast() {
        result.append(node)
        pending.append(contentsOf: node.children.reversed())
    }
    return result
}

@MainActor
private func retainedAlertSelection(_ range: Range<Int>, in text: String) -> TextSelection {
    let lower = text.index(text.startIndex, offsetBy: range.lowerBound)
    let upper = text.index(text.startIndex, offsetBy: range.upperBound)
    return TextSelection(range: lower..<upper)
}

@MainActor
private func retainedAlertSelectionOffsets(_ selection: TextSelection?, in text: String) -> Range<Int>? {
    guard let selection, case .selection(let range) = selection.indices else { return nil }
    let lower = text.distance(from: text.startIndex, to: range.lowerBound)
    let upper = text.distance(from: text.startIndex, to: range.upperBound)
    return lower..<upper
}
