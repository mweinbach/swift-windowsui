import SwiftWindowsCore
import XCTest

@testable import SwiftWindowsUI

/// Source fixtures for the dormant adapter's physical retirement boundary.
/// They use raw retained nodes and a concrete build admission, not public List
/// construction. Native editor, focus, and UIA integration remain separate.
@MainActor
final class RetainedLazyListRetirementTests: XCTestCase {
    func testNestedStructuralTransitionRejectsBeforeAdoptingAnyMatchedProperty() async throws {
        let retained = row("old row", tag: "row")
        let departing = row("old descendant", tag: "departing")
        let editor = RetirementTestTextController()
        departing.textInputController = editor
        retained.addChild(departing)
        retained.opacity = 0.8
        let incoming = row("new row", tag: "row")
        incoming.opacity = 0.3
        let fixture = try RetirementFixture(previous: [retained], incoming: [incoming], appeared: true)
        defer { fixture.finish() }
        departing.transition = .init(kind: .opacity)
        let attachment = departing.captureLazyListAttachmentProof()
        let dialog = departing.beginFileDialogPresentation(kind: .importer)
        var updates = 0
        var dismantles = 0
        var disappearances = 0
        incoming.onUpdatePlatformView = { _ in updates += 1 }
        departing.onDismantlePlatformView = { _ in dismantles += 1 }
        departing.onDisappear = { disappearances += 1 }

        let result = ComponentHost.reconcileChildren(
            of: fixture.container, oldChildren: fixture.container.children,
            newNodes: fixture.candidate.children, admission: fixture.admission)

        XCTAssertFalse(result.completed)
        XCTAssertFalse(result.didMutate)
        XCTAssertEqual(retained.text, "old row")
        XCTAssertEqual(retained.opacity, 0.8)
        XCTAssertTrue(retained.children.first === departing)
        XCTAssertTrue(result.children.first === retained)
        XCTAssertEqual(updates, 0)
        XCTAssertEqual(dismantles, 0)
        XCTAssertEqual(disappearances, 0)
        XCTAssertEqual(editor.revokeCalls, 0)
        XCTAssertEqual(editor.willDetachCalls, 0)
        XCTAssertEqual(editor.detachCalls, 0)
        XCTAssertTrue(editor.isAuthorized(for: departing))
        XCTAssertTrue(dialog.isValid)
        XCTAssertTrue(attachment.isCurrent)
        XCTAssertTrue(departing.hasAppeared)
        XCTAssertTrue(fixture.runtime.transitionOverlays.isEmpty)
    }

    func testViewportEvictionRevokesEveryDepartureBeforeTheFirstCleanupAndCreatesNoOverlay() async throws {
        let first = row("first", tag: "first")
        let descendant = row("editor", tag: "descendant")
        first.addChild(descendant)
        let second = row("second", tag: "second", y: 20)
        let oldNodes = [first, descendant, second]
        let editors = oldNodes.map { node in
            let editor = RetirementTestTextController()
            node.textInputController = editor
            return editor
        }
        let incoming = row("next viewport", tag: "incoming")
        let incomingEditor = RetirementTestTextController()
        incoming.textInputController = incomingEditor
        let fixture = try RetirementFixture(
            previous: [first, second], incoming: [incoming], appeared: true, viewportEviction: true)
        defer { fixture.finish() }
        first.transition = .init(kind: .opacity)
        second.transition = .init(kind: .opacity)
        let proofs = oldNodes.map { $0.captureLazyListAttachmentProof() }
        let dialogs = oldNodes.map { $0.beginFileDialogPresentation(kind: .importer) }
        var firstCleanupSnapshots: [[Bool]] = []
        var dismantles = [Int](repeating: 0, count: oldNodes.count)
        var disappearances = [Int](repeating: 0, count: oldNodes.count)
        for (index, node) in oldNodes.enumerated() {
            node.onDismantlePlatformView = { _ in dismantles[index] += 1 }
            node.onDisappear = { disappearances[index] += 1 }
        }
        editors[0].onWillDetach = {
            firstCleanupSnapshots.append([
                zip(editors, oldNodes).allSatisfy { !$0.0.isAuthorized(for: $0.1) },
                dialogs.allSatisfy { !$0.isValid },
                proofs.allSatisfy { !$0.isCurrent },
                first.parent == nil && second.parent == nil,
                oldNodes.allSatisfy { !$0.isFileDialogPresenter(in: fixture.runtime) },
                oldNodes.allSatisfy { !$0.hasAppeared },
                fixture.container.children.isEmpty,
            ])
        }
        XCTAssertEqual(
            fixture.candidate.virtualizedDepartureRoots,
            Set([ObjectIdentifier(first), ObjectIdentifier(second)]))

        let result = fixture.replace(removalReason: .virtualization)

        XCTAssertTrue(result.completed)
        XCTAssertTrue(result.didMutate)
        XCTAssertEqual(firstCleanupSnapshots, [[true, true, true, true, true, true, true]])
        XCTAssertEqual(dismantles, [1, 1, 1])
        XCTAssertEqual(disappearances, [1, 1, 1])
        XCTAssertEqual(editors.map(\.revokeCalls), [1, 1, 1])
        XCTAssertEqual(editors.map(\.willDetachCalls), [1, 1, 1])
        XCTAssertEqual(editors.map(\.detachCalls), [1, 1, 1])
        XCTAssertTrue(fixture.runtime.transitionOverlays.isEmpty)
        XCTAssertFalse(first.isRemovalOverlay)
        XCTAssertFalse(second.isRemovalOverlay)
        XCTAssertEqual(result.children.count, 1)
        XCTAssertTrue(result.children.first === incoming)
        XCTAssertTrue(incoming.parent === fixture.container)
        XCTAssertEqual(incomingEditor.attachCalls, 1)
    }

    func testProviderCloseInFirstCleanupStillDrainsEveryOldObligationWithoutAttachingIncoming() async throws {
        let first = row("first", tag: "first")
        let second = row("second", tag: "second", y: 20)
        let firstEditor = RetirementTestTextController()
        let secondEditor = RetirementTestTextController()
        first.textInputController = firstEditor
        second.textInputController = secondEditor
        let incoming = row("incoming", tag: "incoming")
        let incomingEditor = RetirementTestTextController()
        incoming.textInputController = incomingEditor
        let fixture = try RetirementFixture(previous: [first, second], incoming: [incoming], appeared: true)
        defer { fixture.finish() }
        var cleanup: [String] = []
        firstEditor.onWillDetach = {
            cleanup.append("first willDetach")
            fixture.provider.close()
        }
        secondEditor.onWillDetach = { cleanup.append("second willDetach") }
        first.onDismantlePlatformView = { _ in cleanup.append("first dismantle") }
        second.onDismantlePlatformView = { _ in cleanup.append("second dismantle") }
        first.onDisappear = { cleanup.append("first disappear") }
        second.onDisappear = { cleanup.append("second disappear") }
        firstEditor.onDetach = { cleanup.append("first detach") }
        secondEditor.onDetach = { cleanup.append("second detach") }

        let result = fixture.replace()

        XCTAssertFalse(result.completed)
        XCTAssertTrue(result.didMutate)
        XCTAssertFalse(fixture.admission.isCurrent)
        XCTAssertEqual(
            cleanup,
            [
                "first willDetach", "second willDetach",
                "first dismantle", "first disappear", "second dismantle", "second disappear",
                "first detach", "second detach",
            ])
        XCTAssertTrue(result.children.isEmpty)
        XCTAssertTrue(fixture.container.children.isEmpty)
        XCTAssertNil(first.parent)
        XCTAssertNil(second.parent)
        XCTAssertNil(incoming.parent)
        XCTAssertEqual(incomingEditor.attachCalls, 0)
        XCTAssertEqual(firstEditor.detachCalls, 1)
        XCTAssertEqual(secondEditor.detachCalls, 1)
    }

    func testCleanupAddedUnrelatedChildSurvivesTheObsoletePlannedChildArray() async throws {
        let departing = row("departing", tag: "departing")
        let incoming = row("incoming", tag: "incoming")
        let authored = row("callback child", tag: "authored")
        let incomingEditor = RetirementTestTextController()
        incoming.textInputController = incomingEditor
        let fixture = try RetirementFixture(previous: [departing], incoming: [incoming], appeared: true)
        defer { fixture.finish() }
        var disappearances = 0
        departing.onDisappear = {
            disappearances += 1
            fixture.container.addChild(authored)
        }

        let result = fixture.replace()

        XCTAssertFalse(result.completed)
        XCTAssertTrue(result.didMutate)
        XCTAssertEqual(disappearances, 1)
        XCTAssertEqual(result.children.count, 1)
        XCTAssertTrue(result.children.first === authored)
        XCTAssertTrue(fixture.container.children.first === authored)
        XCTAssertTrue(authored.parent === fixture.container)
        XCTAssertNil(incoming.parent)
        XCTAssertEqual(incomingEditor.attachCalls, 0)
    }

    func testRetirementGateBlocksReattachmentAcrossParentsUntilOldCleanupDrains() async throws {
        let departing = row("departing", tag: "departing")
        departing.isFocusable = true
        let editor = RetirementTestTextController()
        departing.textInputController = editor
        let fixture = try RetirementFixture(previous: [departing], incoming: [], appeared: true)
        defer { fixture.finish() }
        let detachedParent = row("detached", tag: "detached")
        let deniedChild = row("denied", tag: "denied")
        let otherRuntime = RetainedViewRuntime(root: row("other runtime", tag: "other"))
        otherRuntime.clock = { 0 }
        let oldProof = departing.captureLazyListAttachmentProof()
        var rejectedAttempts: [Bool] = []
        var nestedCompleted: Bool?
        departing.onDisappear = {
            fixture.container.addChild(departing)
            rejectedAttempts.append(departing.parent == nil && fixture.container.children.isEmpty)
            detachedParent.addChild(departing)
            rejectedAttempts.append(departing.parent == nil && detachedParent.children.isEmpty)
            otherRuntime.root.addChild(departing)
            rejectedAttempts.append(departing.parent == nil && otherRuntime.root.children.isEmpty)
            nestedCompleted = departing.setChildren([deniedChild]).completed
            otherRuntime.requestFocus(departing)
            rejectedAttempts.append(otherRuntime.focusedNode == nil)
        }

        let result = fixture.replace()

        XCTAssertTrue(result.completed)
        XCTAssertTrue(result.didMutate)
        XCTAssertEqual(rejectedAttempts, [true, true, true, true])
        XCTAssertEqual(nestedCompleted, false)
        XCTAssertFalse(oldProof.isCurrent)
        XCTAssertEqual(editor.attachCalls, 1)
        XCTAssertEqual(editor.detachCalls, 1)
        XCTAssertTrue(departing.children.isEmpty)
        departing.onDisappear = nil
        otherRuntime.root.addChild(departing)
        XCTAssertTrue(departing.parent === otherRuntime.root)
        XCTAssertTrue(otherRuntime.root.children.first === departing)
        XCTAssertTrue(departing.captureLazyListAttachmentProof().isCurrent)
        XCTAssertFalse(oldProof.isCurrent)
        XCTAssertEqual(editor.attachCalls, 2)
        XCTAssertTrue(editor.isAuthorized(for: departing))
    }

    func testLaterControllerAttachmentCannotReviveAnEarlierSubtreeByRemovingAndReaddingIt() async throws {
        let first = row("first insertion", tag: "first")
        let second = row("second insertion", tag: "second")
        let descendant = row("second descendant", tag: "descendant")
        second.addChild(descendant)
        let third = row("third insertion", tag: "third")
        let firstEditor = RetirementTestTextController()
        let secondEditor = RetirementTestTextController()
        let descendantEditor = RetirementTestTextController()
        let thirdEditor = RetirementTestTextController()
        first.textInputController = firstEditor
        second.textInputController = secondEditor
        descendant.textInputController = descendantEditor
        third.textInputController = thirdEditor
        let fixture = try RetirementFixture(previous: [], incoming: [first, second, third])
        defer { fixture.finish() }
        var firstPublishedProof: RetainedLazyListAttachmentProof?
        var firstMembershipAtAttach = false
        var secondMembershipAtAttach = false
        var descendantRegistrationAtSecondAttach = false
        var didReenterSecondAttachment = false
        var authoredReordersCompleted: [Bool] = []
        var descendantCallsAtCallbackExit: Int?
        firstEditor.onAttach = {
            if firstPublishedProof == nil {
                firstPublishedProof = first.captureLazyListAttachmentProof()
                firstMembershipAtAttach =
                    first.parent === fixture.container
                    && fixture.container.children.contains { $0 === first }
            }
        }
        secondEditor.onAttach = {
            guard !didReenterSecondAttachment else { return }
            didReenterSecondAttachment = true
            secondMembershipAtAttach =
                second.parent === fixture.container
                && fixture.container.children.contains { $0 === second }
            descendantRegistrationAtSecondAttach = descendant.isFileDialogPresenter(in: fixture.runtime)
            // These ordinary child-list operations preserve the container's
            // local layout stamp. Restore equal pointers AND equal order, so
            // the checked path must notice the obsolete attachment proof.
            authoredReordersCompleted.append(fixture.container.setChildren([second]).completed)
            fixture.container.addChild(first)
            authoredReordersCompleted.append(fixture.container.setChildren([first, second]).completed)
            descendantCallsAtCallbackExit = descendantEditor.attachCalls
        }

        let result = fixture.replace()

        XCTAssertFalse(result.completed)
        XCTAssertTrue(result.didMutate)
        XCTAssertTrue(firstMembershipAtAttach)
        XCTAssertTrue(secondMembershipAtAttach)
        XCTAssertTrue(descendantRegistrationAtSecondAttach)
        XCTAssertEqual(authoredReordersCompleted, [true, true])
        XCTAssertEqual(firstPublishedProof?.isCurrent, false)
        XCTAssertTrue(fixture.candidate.isCurrent)
        XCTAssertTrue(fixture.admission.isCurrent)
        XCTAssertTrue(first.parent === fixture.container)
        XCTAssertTrue(second.parent === fixture.container)
        XCTAssertEqual(result.children.count, 2)
        XCTAssertTrue(result.children[0] === first)
        XCTAssertTrue(result.children[1] === second)
        XCTAssertEqual(firstEditor.attachCalls, 3)
        XCTAssertEqual(secondEditor.attachCalls, 3)
        XCTAssertEqual(descendantCallsAtCallbackExit, 2)
        XCTAssertEqual(descendantEditor.attachCalls, descendantCallsAtCallbackExit)
        XCTAssertEqual(thirdEditor.attachCalls, 0)
        XCTAssertNil(third.parent)
    }

    func testFocusExitPreservesANewerOutsideFocusWithoutAStaleNilAccessibilityEvent() async throws {
        let departing = row("departing focus", tag: "departing")
        departing.isFocusable = true
        let outside = row("outside focus", tag: "outside", y: 60)
        outside.isFocusable = true
        let fixture = try RetirementFixture(
            previous: [departing], incoming: [], appeared: true, outside: [outside],
            beforeAdmission: { runtime, _ in runtime.requestFocus(departing) })
        defer { fixture.finish() }
        XCTAssertTrue(fixture.runtime.focusedNode === departing)
        var focusEvents: [String] = []
        var exits = 0
        fixture.runtime.onAccessibilityFocusChanged = { focusEvents.append($0?.nodeTag ?? "nil") }
        departing.onFocusExit = {
            exits += 1
            fixture.runtime.requestFocus(outside)
        }

        let result = fixture.replace()

        XCTAssertTrue(result.completed)
        XCTAssertEqual(exits, 1)
        XCTAssertTrue(fixture.runtime.focusedNode === outside)
        XCTAssertTrue(outside.isFocused)
        XCTAssertFalse(departing.isFocused)
        XCTAssertEqual(focusEvents, ["outside"])
        XCTAssertTrue(outside.parent === fixture.runtime.root)
    }

    func testHostCloseInCleanupStillFinishesOldDetachButPreventsLaterAttachment() async throws {
        let first = row("first", tag: "first")
        let second = row("second", tag: "second", y: 20)
        let firstEditor = RetirementTestTextController()
        let secondEditor = RetirementTestTextController()
        first.textInputController = firstEditor
        second.textInputController = secondEditor
        let incoming = row("incoming", tag: "incoming")
        let incomingEditor = RetirementTestTextController()
        incoming.textInputController = incomingEditor
        let fixture = try RetirementFixture(previous: [first, second], incoming: [incoming], appeared: true)
        defer { fixture.finish() }
        var disappearances = 0
        first.onDisappear = { disappearances += 1 }
        second.onDisappear = { disappearances += 1 }
        firstEditor.onWillDetach = { fixture.runtime.stopRenderLifecycleCallbacks() }

        let result = fixture.replace()

        XCTAssertFalse(result.completed)
        XCTAssertTrue(result.didMutate)
        XCTAssertFalse(fixture.runtime.permitsRetainedActionInvocation)
        XCTAssertFalse(fixture.admission.isCurrent)
        XCTAssertEqual(disappearances, 2)
        XCTAssertEqual(firstEditor.willDetachCalls, 1)
        XCTAssertEqual(secondEditor.willDetachCalls, 1)
        XCTAssertEqual(firstEditor.detachCalls, 1)
        XCTAssertEqual(secondEditor.detachCalls, 1)
        XCTAssertEqual(incomingEditor.attachCalls, 0)
        XCTAssertNil(incoming.parent)
        XCTAssertTrue(result.children.isEmpty)
    }

    func testQueuedLongPressCleanupInvalidatesAdoptedChildrenBeforeTheWrapperReturns() async throws {
        let departing = row("held row", tag: "departing")
        let incoming = row("incoming", tag: "incoming")
        let authored = row("cleanup child", tag: "authored")
        let incomingEditor = RetirementTestTextController()
        incoming.textInputController = incomingEditor
        let hook = RetirementCleanupHook()
        var pressing: [Bool] = []
        var recognitions = 0
        var cleanups = 0
        departing.longPressGesture = RetainedLongPressGesture(
            minimumDuration: 1000, maximumDistance: 10,
            onBegin: { _ in
                {
                    cleanups += 1
                    hook.action?()
                }
            },
            onPressingChanged: { pressing.append($0) },
            onRecognized: { recognitions += 1 })
        let fixture = try RetirementFixture(
            previous: [departing], incoming: [incoming], appeared: true,
            beforeAdmission: { runtime, _ in runtime.pointerDown(at: Point(x: 10, y: 10)) })
        defer {
            hook.action = nil
            fixture.finish()
        }
        XCTAssertEqual(pressing, [true])
        var sawPublishedIncoming = false
        var gateStillRejectedOldRow = false
        hook.action = {
            sawPublishedIncoming =
                incoming.parent === fixture.container
                && fixture.container.children.contains { $0 === incoming }
            fixture.container.addChild(departing)
            gateStillRejectedOldRow = departing.parent == nil
            fixture.container.addChild(authored)
        }

        let result = fixture.replace()

        XCTAssertFalse(result.completed)
        XCTAssertTrue(result.didMutate)
        XCTAssertEqual(cleanups, 1)
        XCTAssertEqual(pressing, [true, false])
        XCTAssertEqual(recognitions, 0)
        XCTAssertTrue(sawPublishedIncoming)
        XCTAssertTrue(gateStillRejectedOldRow)
        XCTAssertTrue(fixture.candidate.isCurrent, "Physical reentry must reject even without replacing the source")
        XCTAssertTrue(fixture.admission.isCurrent, "Appending a child does not change the admitted owner or layout")
        XCTAssertEqual(result.completion?.isCurrent, false)
        XCTAssertEqual(incomingEditor.attachCalls, 1)
        XCTAssertEqual(incomingEditor.detachCalls, 0)
        XCTAssertTrue(incoming.parent === fixture.container)
        XCTAssertEqual(result.children.count, 2)
        XCTAssertTrue(result.children[0] === incoming)
        XCTAssertTrue(result.children[1] === authored)
        XCTAssertTrue(fixture.container.children.last === authored)
    }

    func testLegacyAdapterHistoryCleanupCannotMoveAnUngatedChildFromARetiringParent() async throws {
        let container = row("adapter container", tag: "container")
        let descendant = row("ungated child", tag: "descendant")
        container.addChild(descendant)
        let addDestination = row("detached destination", tag: "add")
        let replaceDestination = row("replace destination", tag: "replace")
        let replaceOriginal = row("replace original", tag: "replace-original")
        replaceDestination.addChild(replaceOriginal)
        let setDestination = row("set destination", tag: "set")
        let setOriginal = row("set original", tag: "set-original")
        setDestination.addChild(setOriginal)
        let runtime = RetainedViewRuntime(root: row("runtime", tag: "runtime"))
        runtime.clock = { 0 }
        runtime.root.addChild(container)
        runtime.root.addChild(replaceDestination)
        runtime.root.addChild(setDestination)
        let provider = RetainedLazyListDataSource<Int, [ViewNode]>()
        guard provider.replaceData([0], id: \.self, rowContent: { _ in [descendant] }) else {
            throw RetirementFixtureError.setup
        }
        defer { provider.close() }
        let adapter = try XCTUnwrap(
            RetainedLazyListRuntimeAdapter(
                provider: provider, estimatedExtent: 40, prefetchExtent: 0,
                maximumMountedRecords: 4, maximumMountedLeaves: 16, maximumProtectedRecords: 1))
        container.retainedSubtreeBuildLease = RetirementTestLease()
        container.retainedLazyListAdapter = adapter
        XCTAssertTrue(adapter.ownsAttachment(container))
        // Seed only the raw adapter's cache. No checked admission or checked
        // subtree retirement participates in the operation under test.
        do {
            let context = try XCTUnwrap(
                RetainedLazyListMeasurementContext(
                    width: 100, displayScale: 1, contentRevision: 0, environmentRevision: 0))
            let viewport = try XCTUnwrap(
                RetainedLazyListRuntimeAdapter.Viewport(context: context, offset: 0, extent: 20))
            let budget = try XCTUnwrap(RetainedLazyListWorkBudget(elementLimit: 4, roundLimit: 2))
            guard
                case .ready(let candidate) = adapter.prepare(
                    viewport: viewport, protectedRoots: [], budget: budget)
            else { throw RetirementFixtureError.setup }
            XCTAssertTrue(container.setChildren(candidate.children).completed)
            XCTAssertTrue(adapter.complete(candidate: candidate, adoptedChildren: container.children))
        }
        XCTAssertEqual(adapter.mountedRecordCount, 1)
        let storage = RetainedScrollObserverStorage()
        let observer = RetainedScrollGeometryObserver(
            transform: { _ in RetirementObservedValue() }, action: { _, _ in })
        storage.geometry = [observer]
        container.scrollObserverStorage = storage
        let replaceProof = replaceOriginal.captureLazyListAttachmentProof()
        let setProof = setOriginal.captureLazyListAttachmentProof()
        var cleanupCount = 0
        var cleanupEntry: [Bool] = []
        var rejectedMoves: [Bool] = []
        var setCompleted: Bool?
        var destinationDismantles = [0, 0]
        replaceOriginal.onDismantlePlatformView = { _ in destinationDismantles[0] += 1 }
        setOriginal.onDismantlePlatformView = { _ in destinationDismantles[1] += 1 }
        defer {
            replaceOriginal.onDismantlePlatformView = nil
            setOriginal.onDismantlePlatformView = nil
        }
        // The only owner of this payload is the observer's old history. Its
        // destructor runs when the legacy detach helper's captured history
        // unwinds, after native detach/map release but before gate completion.
        observer.previousValue = RetirementObservedValue(
            payload: RetirementHistoryDeinitAction {
                [
                    adapter, container, descendant, addDestination, replaceDestination,
                    replaceOriginal, setDestination, setOriginal, observer
                ] in
                cleanupCount += 1
                let childProof = descendant.captureLazyListAttachmentProof()
                cleanupEntry = [
                    !container.captureLazyListAttachmentProof().isCurrent,
                    childProof.isCurrent,
                    adapter.ownsAttachment(container),
                    adapter.mountedRecordCount == 0,
                    container.parent == nil && descendant.parent === container,
                    descendant.hasSameLazyListRuntime(as: addDestination),
                    observer.previousValue == nil,
                ]
                addDestination.addChild(descendant)
                rejectedMoves.append(
                    addDestination.children.isEmpty && descendant.parent === container
                        && container.children.count == 1 && container.children.first === descendant
                        && childProof.isCurrent)
                replaceDestination.replaceChild(at: 0, with: descendant)
                rejectedMoves.append(
                    replaceDestination.children.count == 1 && replaceDestination.children.first === replaceOriginal
                        && replaceOriginal.parent === replaceDestination && replaceProof.isCurrent
                        && descendant.parent === container && childProof.isCurrent)
                let result = setDestination.setChildren([descendant])
                setCompleted = result.completed
                rejectedMoves.append(
                    result.children.count == 1 && result.children.first === setOriginal
                        && setDestination.children.count == 1 && setDestination.children.first === setOriginal
                        && setOriginal.parent === setDestination && setProof.isCurrent
                        && descendant.parent === container && childProof.isCurrent)
            })
        provider.close()
        XCTAssertNil(provider.metadata)
        XCTAssertEqual(cleanupCount, 0)

        container.removeFromParent()

        XCTAssertEqual(cleanupCount, 1)
        XCTAssertEqual(cleanupEntry, [true, true, true, true, true, true, true])
        XCTAssertEqual(rejectedMoves, [true, true, true])
        XCTAssertEqual(setCompleted, false)
        XCTAssertEqual(destinationDismantles, [0, 0])
        XCTAssertTrue(container.captureLazyListAttachmentProof().isCurrent)
        XCTAssertFalse(adapter.ownsAttachment(container))
        XCTAssertEqual(adapter.mountedRecordCount, 0)
        XCTAssertNil(observer.previousValue)
        XCTAssertTrue(descendant.parent === container)
        XCTAssertTrue(container.children.first === descendant)
        // The restriction ends with the old cleanup. A fresh move can now
        // remove the child from the detached container without stale members.
        addDestination.addChild(descendant)
        XCTAssertTrue(descendant.parent === addDestination)
        XCTAssertTrue(addDestination.children.first === descendant)
        XCTAssertTrue(container.children.isEmpty)
        XCTAssertEqual(cleanupCount, 1)
    }

    private func row(_ text: String, tag: String, y: Double = 0) -> ViewNode {
        let node = ViewNode(frame: Rect(x: 0, y: y, width: 100, height: 20), text: text)
        node.nodeTag = tag
        return node
    }
}

@MainActor
private final class RetirementFixture {
    let provider: RetainedLazyListDataSource<Int, [ViewNode]>
    let adapter: RetainedLazyListRuntimeAdapter
    let container: ViewNode
    let runtime: RetainedViewRuntime
    let lease: RetirementTestLease
    let epoch: RetirementTestEpoch
    let candidate: RetainedLazyListRuntimeAdapter.Candidate
    let admission: RetainedLazyListAdoptionAdmission
    private let fixtureRoots: [ViewNode]
    private var didFinish = false

    init(
        previous: [ViewNode], incoming: [ViewNode], appeared: Bool = false,
        outside: [ViewNode] = [], viewportEviction: Bool = false,
        beforeAdmission: @MainActor (RetainedViewRuntime, ViewNode) -> Void = { _, _ in }
    ) throws {
        let provider = RetainedLazyListDataSource<Int, [ViewNode]>()
        let keys = viewportEviction ? [0, 1] : [0]
        guard
            provider.replaceData(
                keys, id: \.self,
                rowContent: { index in viewportEviction && index == 0 ? previous : incoming })
        else { throw RetirementFixtureError.setup }
        let adapter = try XCTUnwrap(
            RetainedLazyListRuntimeAdapter(
                provider: provider, estimatedExtent: 40, prefetchExtent: 0,
                maximumMountedRecords: 4, maximumMountedLeaves: 16, maximumProtectedRecords: 1))
        let container = ViewNode(frame: Rect(x: 0, y: 0, width: 100, height: 60))
        for node in previous { container.addChild(node) }
        let runtime = RetainedViewRuntime(root: ViewNode(frame: Rect(x: 0, y: 0, width: 100, height: 80)))
        runtime.clock = { 0 }
        runtime.root.addChild(container)
        for node in outside { runtime.root.addChild(node) }
        // Appearance and pointer setup cannot run after the dormant adapter
        // and its build admission are installed: that would ask layout to
        // resolve a different candidate and could suppress appearance delivery.
        if appeared { _ = runtime.renderFrame() }
        beforeAdmission(runtime, container)
        let lease = RetirementTestLease()
        container.retainedSubtreeBuildLease = lease
        container.retainedLazyListAdapter = adapter
        guard adapter.ownsAttachment(container) else { throw RetirementFixtureError.setup }
        let context = try XCTUnwrap(
            RetainedLazyListMeasurementContext(
                width: 100, displayScale: 1, contentRevision: 0, environmentRevision: 0))
        if viewportEviction {
            // The first cohort really remains in the provider when the next
            // viewport omits it. Do not disguise deletion or a changed leaf
            // shape as virtualization just to bypass structural transitions.
            let previousViewport = try XCTUnwrap(
                RetainedLazyListRuntimeAdapter.Viewport(context: context, offset: 0, extent: 20))
            let previousBudget = try XCTUnwrap(RetainedLazyListWorkBudget(elementLimit: 4, roundLimit: 2))
            guard
                case .ready(let previousCandidate) = adapter.prepare(
                    viewport: previousViewport, protectedRoots: [], budget: previousBudget)
            else { throw RetirementFixtureError.setup }
            let (previousEpoch, previousAdmission) = try Self.beginAdmission(
                adapter: adapter, candidate: previousCandidate, container: container, runtime: runtime)
            let seeded = container.setChildren(previousCandidate.children, admission: previousAdmission)
            let didComplete =
                seeded.completed && previousAdmission.isCurrent
                && adapter.complete(candidate: previousCandidate, adoptedChildren: seeded.children)
            if didComplete || seeded.didMutate { previousEpoch.commit() } else { previousEpoch.abandon() }
            previousEpoch.finishAfterCallbacks()
            runtime.retainedBuildCoordinator.finishBuild()
            guard didComplete else { throw RetirementFixtureError.setup }
        }
        let viewport = try XCTUnwrap(
            RetainedLazyListRuntimeAdapter.Viewport(
                context: context, offset: viewportEviction ? 40 : 0, extent: viewportEviction ? 20 : 60))
        let budget = try XCTUnwrap(RetainedLazyListWorkBudget(elementLimit: 4, roundLimit: 2))
        guard
            case .ready(let candidate) = adapter.prepare(
                viewport: viewport, protectedRoots: [], budget: budget)
        else { throw RetirementFixtureError.setup }
        let (epoch, admission) = try Self.beginAdmission(
            adapter: adapter, candidate: candidate, container: container, runtime: runtime)
        self.provider = provider
        self.adapter = adapter
        self.container = container
        self.runtime = runtime
        self.lease = lease
        self.epoch = epoch
        self.candidate = candidate
        self.admission = admission
        self.fixtureRoots = previous + incoming + outside + [container, runtime.root]
    }

    func replace(removalReason: RetainedChildRemovalReason = .structural) -> RetainedLazyListAdoptionResult {
        container.setChildren(candidate.children, admission: admission, removalReason: removalReason)
    }

    func finish() {
        guard !didFinish else { return }
        didFinish = true
        provider.close()
        runtime.clock = { 0 }
        runtime.onAccessibilityFocusChanged = nil
        var pending = fixtureRoots
        var visited: Set<ObjectIdentifier> = []
        while let node = pending.popLast() {
            guard visited.insert(ObjectIdentifier(node)).inserted else { continue }
            pending.append(contentsOf: node.children)
            node.onUpdatePlatformView = nil
            node.onDismantlePlatformView = nil
            node.onDisappear = nil
            node.onDisappearWithNode = nil
            node.onFocusExit = nil
            node.onFocusEnter = nil
            node.onPointerExit = nil
            node.onPointerUpOutside = nil
            node.longPressGesture = nil
            if let editor = node.textInputController as? RetirementTestTextController { editor.clearCallbacks() }
        }
        if admission.didMutate { epoch.commit() } else { epoch.abandon() }
        epoch.finishAfterCallbacks()
        runtime.retainedBuildCoordinator.finishBuild()
    }

    private static func beginAdmission(
        adapter: RetainedLazyListRuntimeAdapter, candidate: RetainedLazyListRuntimeAdapter.Candidate,
        container: ViewNode, runtime: RetainedViewRuntime
    ) throws -> (RetirementTestEpoch, RetainedLazyListAdoptionAdmission) {
        let coordinator = runtime.retainedBuildCoordinator
        let sequence = try XCTUnwrap(coordinator.beginBuild())
        let epoch = RetirementTestEpoch()
        coordinator.install(epoch, startedAt: sequence)
        guard epoch.willAdopt() else {
            epoch.abandon()
            epoch.finishAfterCallbacks()
            coordinator.finishBuild()
            throw RetirementFixtureError.setup
        }
        let admission = RetainedLazyListAdoptionAdmission(
            adapter: adapter, candidate: candidate, container: container, runtime: runtime,
            coordinator: coordinator, sequence: sequence)
        guard admission.isCurrent else {
            epoch.abandon()
            epoch.finishAfterCallbacks()
            coordinator.finishBuild()
            throw RetirementFixtureError.setup
        }
        return (epoch, admission)
    }
}

private enum RetirementFixtureError: Error { case setup }

@MainActor
private final class RetirementTestLease: RetainedSubtreeBuildLease {
    var canBuild: Bool { true }
    func beginBuild() -> (any RetainedBuildEpoch)? { RetirementTestEpoch() }
}

@MainActor
private final class RetirementTestEpoch: RetainedBuildEpoch {
    private var prepared = false
    var canAdopt: Bool { !prepared }
    func supersede() {}
    func willAdopt() -> Bool {
        guard !prepared else { return false }
        prepared = true
        return true
    }
    func commit() {}
    func abandon() {}
    func finishAfterCallbacks() {}
}

/// Revocation only changes native scalars. It invokes no callback and retains
/// the previous weak owner until detach, so old cleanup cannot clear a newer
/// owner installed by a callback. Each test uses a distinct physical editor.
@MainActor
private final class RetirementTestTextController: RetainedTextInputController {
    var onAttach: (() -> Void)?
    var onWillDetach: (() -> Void)?
    var onDetach: (() -> Void)?
    private weak var owner: ViewNode?
    private var authorized = false
    private(set) var attachCalls = 0
    private(set) var reconcileCalls = 0
    private(set) var revokeCalls = 0
    private(set) var willDetachCalls = 0
    private(set) var detachCalls = 0

    func isAuthorized(for node: ViewNode) -> Bool { owner === node && authorized }

    func attach(to node: ViewNode) {
        owner = node
        authorized = true
        attachCalls += 1
        onAttach?()
    }

    func prepareForReconciliation(from previous: (any RetainedTextInputController)?, onto node: ViewNode) {
        if let previous, previous !== self { previous.revokeOwnership(from: node) }
    }

    func reconcile(from previous: (any RetainedTextInputController)?, onto node: ViewNode) {
        reconcileCalls += 1
    }

    func revokeOwnership(from node: ViewNode) {
        guard owner === node, authorized else { return }
        authorized = false
        revokeCalls += 1
    }

    func willDetach(from node: ViewNode) {
        guard owner === node else { return }
        willDetachCalls += 1
        onWillDetach?()
    }

    func detach(from node: ViewNode) {
        guard owner === node else { return }
        authorized = false
        owner = nil
        detachCalls += 1
        onDetach?()
    }

    func clearCallbacks() {
        onAttach = nil
        onWillDetach = nil
        onDetach = nil
    }
}

@MainActor
private final class RetirementCleanupHook {
    var action: (@MainActor () -> Void)?
}

private final class RetirementHistoryDeinitAction {
    let action: @MainActor () -> Void
    init(_ action: @escaping @MainActor () -> Void) { self.action = action }
    deinit { MainActor.assumeIsolated { [action] in action() } }
}

private struct RetirementObservedValue: Equatable {
    let payload: RetirementHistoryDeinitAction?
    init(payload: RetirementHistoryDeinitAction? = nil) { self.payload = payload }
    static func == (lhs: Self, rhs: Self) -> Bool { lhs.payload === rhs.payload }
}
