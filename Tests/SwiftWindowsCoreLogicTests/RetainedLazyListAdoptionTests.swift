import SwiftWindowsCore
import XCTest

@testable import SwiftWindowsUI

/// These fixtures enter the dormant adapter's concrete coordinator admission.
/// They do not enable the facade or qualify native editors, focus, UIA, layout
/// settlement, or the cost of an arbitrary application row factory.
@MainActor
final class RetainedLazyListAdoptionTests: XCTestCase {
    func testOrdinaryReconciliationStillUpdatesAReusedRawNode() async {
        let cached = row("cached")
        let runtime = RetainedViewRuntime(root: ViewNode(frame: Rect(x: 0, y: 0, width: 100, height: 60)))
        runtime.root.addChild(cached)
        var updates = 0
        cached.onUpdatePlatformView = { _ in updates += 1 }

        ComponentHost.reconcileChildren(of: runtime.root, oldChildren: runtime.root.children, newNodes: [cached])
        ComponentHost.adopt(source: cached, into: cached)

        XCTAssertEqual(updates, 2)
        XCTAssertTrue(runtime.root.children.first === cached)
    }

    func testMatchedRowsReturnActualRetainedNodesAndRefreshTheirContent() async throws {
        let first = row("old first", tag: "first")
        let second = row("old second", tag: "second")
        let incomingFirst = row("new first", tag: "first")
        let incomingSecond = row("new second", tag: "second")
        let fixture = try AdoptionFixture(previous: [first, second], incoming: [incomingSecond, incomingFirst])
        defer { fixture.finish() }

        let result = fixture.reconcile()

        XCTAssertTrue(result.completed)
        XCTAssertTrue(result.didMutate)
        XCTAssertEqual(result.children.count, 2)
        XCTAssertTrue(result.children[0] === second)
        XCTAssertTrue(result.children[1] === first)
        XCTAssertEqual(second.text, "new second")
        XCTAssertEqual(first.text, "new first")
        XCTAssertTrue(first.parent === fixture.container)
        XCTAssertTrue(second.parent === fixture.container)
    }

    func testSourceOrderSnapshotAllowsPlannedChildTransfers() async throws {
        let previous = row("old parent")
        let retained = row("old retained", tag: "retained")
        previous.addChild(retained)
        let incoming = row("new parent")
        let incomingRetained = row("new retained", tag: "retained")
        let insertion = row("inserted", tag: "inserted")
        incoming.addChild(incomingRetained)
        incoming.addChild(insertion)
        let fixture = try AdoptionFixture(previous: [previous], incoming: [incoming])
        defer { fixture.finish() }

        let result = ComponentHost.adopt(source: incoming, into: previous, admission: fixture.admission)

        XCTAssertTrue(result.completed)
        XCTAssertTrue(result.completion?.isCurrent == true)
        XCTAssertEqual(result.children.count, 2)
        XCTAssertTrue(result.children[0] === retained)
        XCTAssertTrue(result.children[1] === insertion)
        XCTAssertEqual(retained.text, "new retained")
        XCTAssertTrue(insertion.parent === previous)
        XCTAssertEqual(incoming.children.count, 1)
        XCTAssertTrue(incoming.children.first === incomingRetained)
    }

    func testInsertedSiblingCallbackCannotChangePreparedDescendantsAndContinue() async throws {
        let insertion = row("insertion")
        let first = row("first", tag: "first")
        first.addChild(row("prepared child", tag: "child"))
        let second = row("second", tag: "second")
        let third = row("third", tag: "third")
        insertion.addChild(first)
        insertion.addChild(second)
        insertion.addChild(third)
        var secondModifiers = 0
        var thirdModifiers = 0
        second.reconcileAnimationModifiers = [
            .init(transaction: { _ in
                secondModifiers += 1
                first.removeAllChildren()
            })
        ]
        third.reconcileAnimationModifiers = [.init(transaction: { _ in thirdModifiers += 1 })]
        let fixture = try AdoptionFixture(previous: [], incoming: [insertion])
        defer { fixture.finish() }

        let result = fixture.reconcile()

        XCTAssertFalse(result.completed)
        XCTAssertTrue(result.children.isEmpty)
        XCTAssertEqual(secondModifiers, 1)
        XCTAssertEqual(thirdModifiers, 0)
        XCTAssertTrue(first.children.isEmpty)
        XCTAssertNil(insertion.parent)
    }

    func testLaterRowCannotPublishAChangedPreparedInsertionSubtree() async throws {
        let retained = row("old retained", tag: "retained")
        let insertion = row("insertion", tag: "insertion")
        insertion.addChild(row("prepared child", tag: "child"))
        let incomingRetained = row("new retained", tag: "retained")
        let fixture = try AdoptionFixture(previous: [retained], incoming: [insertion, incomingRetained])
        defer { fixture.finish() }
        incomingRetained.onUpdatePlatformView = { _ in insertion.removeAllChildren() }

        let result = fixture.reconcile()

        XCTAssertFalse(result.completed)
        XCTAssertEqual(result.children.count, 1)
        XCTAssertTrue(result.children.first === retained)
        XCTAssertEqual(retained.text, "new retained")
        XCTAssertTrue(insertion.children.isEmpty)
        XCTAssertNil(insertion.parent)
    }

    func testClosedSourceRejectsBeforeAnyRetainedMutation() async throws {
        let previous = row("old")
        let incoming = row("new")
        let fixture = try AdoptionFixture(previous: [previous], incoming: [incoming])
        defer { fixture.finish() }
        fixture.provider.close()

        let result = fixture.reconcile()

        XCTAssertFalse(result.completed)
        XCTAssertFalse(result.didMutate)
        XCTAssertTrue(result.children.first === previous)
        XCTAssertEqual(previous.text, "old")
    }

    func testAdmissionCannotMutateAnUnrelatedSubtree() async throws {
        let fixture = try AdoptionFixture(previous: [row("old")], incoming: [row("new")])
        defer { fixture.finish() }
        let outside = row("outside")
        let outsideChild = row("outside child")
        outside.addChild(outsideChild)

        let adopted = ComponentHost.adopt(source: row("replacement"), into: outside, admission: fixture.admission)
        let reconciled = ComponentHost.reconcileChildren(
            of: outside, oldChildren: outside.children, newNodes: [], admission: fixture.admission)

        XCTAssertFalse(adopted.completed)
        XCTAssertFalse(reconciled.completed)
        XCTAssertFalse(fixture.admission.didMutate)
        XCTAssertTrue(fixture.admission.isCurrent)
        XCTAssertEqual(outside.text, "outside")
        XCTAssertTrue(outside.children.first === outsideChild)
    }

    func testIdentityHashInvalidationRejectsThePreparedPlanBeforeMutation() async throws {
        let hooks = AdoptionKeyHooks()
        let previous = [row("old first"), row("old second")]
        let incoming = [row("new first"), row("new second")]
        for index in previous.indices {
            previous[index].retainedViewIdentity = identity(index, hooks: hooks)
            incoming[index].retainedViewIdentity = identity(index, hooks: hooks)
        }
        let fixture = try AdoptionFixture(previous: previous, incoming: incoming)
        defer {
            hooks.onHash = nil
            fixture.finish()
        }
        var hashCalls = 0
        hooks.onHash = {
            hashCalls += 1
            fixture.provider.close()
        }

        let result = fixture.reconcile()

        XCTAssertGreaterThan(hashCalls, 0)
        XCTAssertFalse(result.completed)
        XCTAssertFalse(result.didMutate)
        XCTAssertTrue(result.children[0] === previous[0])
        XCTAssertTrue(result.children[1] === previous[1])
        XCTAssertEqual(previous.map(\.text), ["old first", "old second"])
    }

    func testEqualIdentityAssignmentFromHashingRejectsBeforeMutation() async throws {
        let hooks = AdoptionKeyHooks()
        let previous = [row("old first"), row("old second")]
        let incoming = [row("new first"), row("new second")]
        for index in previous.indices {
            previous[index].retainedViewIdentity = identity(index, hooks: hooks)
            incoming[index].retainedViewIdentity = identity(index, hooks: hooks)
        }
        let fixture = try AdoptionFixture(previous: previous, incoming: incoming)
        defer {
            hooks.onHash = nil
            fixture.finish()
        }
        let originalIdentity = try XCTUnwrap(previous[0].retainedViewIdentity)
        var hashCalls = 0
        hooks.onHash = {
            hashCalls += 1
            previous[0].retainedViewIdentity = originalIdentity
        }

        let result = fixture.reconcile()

        XCTAssertGreaterThan(hashCalls, 0)
        XCTAssertFalse(result.completed)
        XCTAssertFalse(result.didMutate)
        XCTAssertNotNil(fixture.provider.metadata)
        XCTAssertEqual(previous.map(\.text), ["old first", "old second"])
    }

    func testHashCallbackCannotReplaceTheCapturedSourceChildOrder() async throws {
        let hooks = AdoptionKeyHooks()
        let previous = row("old parent")
        let oldFirst = row("old first", tag: "first")
        let oldSecond = row("old second", tag: "second")
        let incoming = row("new parent")
        let newFirst = row("new first", tag: "first")
        let newSecond = row("new second", tag: "second")
        for (index, pair) in [(oldFirst, newFirst), (oldSecond, newSecond)].enumerated() {
            pair.0.retainedViewIdentity = identity(index, hooks: hooks)
            pair.1.retainedViewIdentity = identity(index, hooks: hooks)
            previous.addChild(pair.0)
            incoming.addChild(pair.1)
        }
        let fixture = try AdoptionFixture(previous: [previous], incoming: [incoming])
        defer {
            hooks.onHash = nil
            fixture.finish()
        }
        var hashCalls = 0
        hooks.onHash = {
            hashCalls += 1
            incoming.setChildren([newSecond, newFirst])
        }

        let result = ComponentHost.adopt(source: incoming, into: previous, admission: fixture.admission)

        XCTAssertGreaterThan(hashCalls, 0)
        XCTAssertFalse(result.completed)
        XCTAssertFalse(result.didMutate)
        XCTAssertEqual(previous.text, "old parent")
        XCTAssertTrue(previous.children[0] === oldFirst)
        XCTAssertTrue(previous.children[1] === oldSecond)
        XCTAssertTrue(incoming.children[0] === newSecond)
        XCTAssertTrue(incoming.children[1] === newFirst)
    }

    func testEqualPropertyComparisonStillChecksAdmissionBeforeLaterWrites() async throws {
        let hooks = AdoptionKeyHooks()
        let previous = row("old")
        let incoming = row("new")
        previous.dragContainerItemID = AnyHashable(AdoptionCallbackKey(value: 7, hooks: hooks))
        incoming.dragContainerItemID = AnyHashable(AdoptionCallbackKey(value: 7, hooks: hooks))
        previous.dragContainerNamespaceID = "old namespace"
        incoming.dragContainerNamespaceID = "new namespace"
        let fixture = try AdoptionFixture(previous: [previous], incoming: [incoming])
        defer {
            hooks.onEqual = nil
            fixture.finish()
        }
        var comparisons = 0
        hooks.onEqual = {
            comparisons += 1
            fixture.provider.close()
        }

        let result = fixture.reconcile()

        XCTAssertGreaterThan(comparisons, 0)
        XCTAssertFalse(result.completed)
        XCTAssertTrue(result.didMutate)
        XCTAssertEqual(previous.dragContainerNamespaceID, "old namespace")
        XCTAssertTrue(result.children.first === previous)
    }

    func testOutgoingCanvasCleanupStopsBeforeCopyingText() async throws {
        let previous = row("old")
        let incoming = row("new")
        let fixture = try AdoptionFixture(previous: [previous], incoming: [incoming])
        defer { fixture.finish() }
        var cleanups = 0
        installCanvasCleanup(on: previous) {
            cleanups += 1
            fixture.provider.close()
        }

        let result = fixture.reconcile()

        XCTAssertEqual(cleanups, 1)
        XCTAssertFalse(result.completed)
        XCTAssertTrue(result.didMutate)
        XCTAssertNil(previous.canvasDraw)
        XCTAssertEqual(previous.text, "old")
        XCTAssertTrue(result.children.first === previous)
    }

    func testOutgoingHandlerCleanupCanReplaceItsOwnSlotWithoutBeingOverwritten() async throws {
        let previous = row("old")
        let incoming = row("new")
        let fixture = try AdoptionFixture(previous: [previous], incoming: [incoming])
        defer { fixture.finish() }
        var cleanups = 0
        var replacementCalls = 0
        var oldRepeatCalls = 0
        previous.onRepeatActivate = { oldRepeatCalls += 1 }
        installActivationCleanup(on: previous) {
            cleanups += 1
            previous.onActivate = { replacementCalls += 1 }
            fixture.provider.close()
        }

        let result = fixture.reconcile()
        previous.onActivate?()
        previous.onRepeatActivate?()

        XCTAssertFalse(result.completed)
        XCTAssertEqual(cleanups, 1)
        XCTAssertEqual(replacementCalls, 1)
        XCTAssertEqual(oldRepeatCalls, 1)
    }

    func testGeometryReaderBodyAndSizePublishBeforeOldBodyCleanup() async throws {
        let previous = row("old")
        let incoming = row("new")
        let previousChild = row("old child", tag: "child")
        previous.addChild(previousChild)
        incoming.addChild(row("new child", tag: "child"))
        incoming.geometryReaderBuild = { _, _ in [] }
        incoming.geometryReaderBuiltSize = Size(width: 140, height: 60)
        let fixture = try AdoptionFixture(previous: [previous], incoming: [incoming])
        defer { fixture.finish() }
        var observedSize: Size?
        var cleanups = 0
        installGeometryCleanup(on: previous) {
            cleanups += 1
            observedSize = previous.geometryReaderBuiltSize
            previous.geometryReaderBuiltSize = Size(width: 9, height: 11)
            fixture.provider.close()
        }

        let result = fixture.reconcile()

        XCTAssertFalse(result.completed)
        XCTAssertEqual(cleanups, 1)
        XCTAssertEqual(observedSize, Size(width: 140, height: 60))
        XCTAssertEqual(previous.geometryReaderBuiltSize, Size(width: 9, height: 11))
        XCTAssertTrue(previous.children.first === previousChild)
        XCTAssertEqual(previousChild.text, "old child")
    }

    func testPlatformCallbackStopsBeforeDescendantsAndLaterSiblings() async throws {
        let first = row("old first", tag: "first")
        let oldChild = row("old child", tag: "child")
        first.addChild(oldChild)
        let second = row("old second", tag: "second")
        let incomingFirst = row("new first", tag: "first")
        incomingFirst.addChild(row("new child", tag: "child"))
        let incomingSecond = row("new second", tag: "second")
        let fixture = try AdoptionFixture(previous: [first, second], incoming: [incomingFirst, incomingSecond])
        defer { fixture.finish() }
        var firstUpdates = 0
        var secondUpdates = 0
        incomingFirst.onUpdatePlatformView = { _ in
            firstUpdates += 1
            fixture.provider.close()
        }
        incomingSecond.onUpdatePlatformView = { _ in secondUpdates += 1 }

        let result = fixture.reconcile()

        XCTAssertFalse(result.completed)
        XCTAssertTrue(result.didMutate)
        XCTAssertEqual(firstUpdates, 1)
        XCTAssertEqual(secondUpdates, 0)
        XCTAssertEqual(first.text, "new first")
        XCTAssertEqual(oldChild.text, "old child")
        XCTAssertEqual(second.text, "old second")
        XCTAssertTrue(result.children[0] === first)
        XCTAssertTrue(result.children[1] === second)
    }

    func testEqualRetainedIdentityAssignmentStopsBeforeDescendantAdoption() async throws {
        let previous = row("old parent")
        let child = row("old child", tag: "child")
        previous.addChild(child)
        let incoming = row("new parent")
        incoming.addChild(row("new child", tag: "child"))
        let fixture = try AdoptionFixture(previous: [previous], incoming: [incoming])
        defer { fixture.finish() }
        let originalIdentity = previous.retainedViewIdentity
        incoming.onUpdatePlatformView = { _ in previous.retainedViewIdentity = originalIdentity }

        let result = fixture.reconcile()

        XCTAssertFalse(result.completed)
        XCTAssertTrue(result.didMutate)
        XCTAssertNotNil(fixture.provider.metadata)
        XCTAssertTrue(previous.children.first === child)
        XCTAssertEqual(child.text, "old child")
    }

    func testChangedLaterDescendantPlanRejectsBeforeItsPropertyCallbacks() async throws {
        let first = row("old first", tag: "first")
        let second = row("old second", tag: "second")
        second.addChild(row("old child", tag: "child"))
        let incomingFirst = row("new first", tag: "first")
        let incomingSecond = row("new second", tag: "second")
        incomingSecond.addChild(row("new child", tag: "child"))
        let fixture = try AdoptionFixture(previous: [first, second], incoming: [incomingFirst, incomingSecond])
        defer { fixture.finish() }
        var secondUpdates = 0
        incomingFirst.onUpdatePlatformView = { _ in second.removeAllChildren() }
        incomingSecond.onUpdatePlatformView = { _ in secondUpdates += 1 }

        let result = fixture.reconcile()

        XCTAssertFalse(result.completed)
        XCTAssertEqual(secondUpdates, 0)
        XCTAssertEqual(second.text, "old second")
        XCTAssertTrue(second.children.isEmpty)
    }

    func testLaterCallbackCannotChangeAnAlreadyCompletedDescendantAndContinue() async throws {
        let first = row("old first", tag: "first")
        let oldChild = row("old child", tag: "child")
        first.addChild(oldChild)
        let second = row("old second", tag: "second")
        let third = row("old third", tag: "third")
        let incomingFirst = row("new first", tag: "first")
        incomingFirst.addChild(row("new child", tag: "child"))
        let incomingSecond = row("new second", tag: "second")
        let incomingThird = row("new third", tag: "third")
        let fixture = try AdoptionFixture(
            previous: [first, second, third], incoming: [incomingFirst, incomingSecond, incomingThird])
        defer { fixture.finish() }
        incomingSecond.onUpdatePlatformView = { _ in first.removeAllChildren() }
        var thirdUpdates = 0
        incomingThird.onUpdatePlatformView = { _ in thirdUpdates += 1 }

        let result = fixture.reconcile()

        XCTAssertFalse(result.completed)
        XCTAssertFalse(fixture.admission.isCurrent)
        XCTAssertEqual(first.text, "new first")
        XCTAssertTrue(first.children.isEmpty)
        XCTAssertEqual(third.text, "old third")
        XCTAssertEqual(thirdUpdates, 0)
    }

    func testLateDepartedPayloadCleanupCannotReportAChangedDeepSubtreeAsComplete() async throws {
        let previous = row("old parent")
        let retained = row("old retained", tag: "retained")
        retained.addChild(row("old grandchild", tag: "grandchild"))
        previous.addChild(retained)
        let replacement = row("callback replacement", tag: "replacement")
        var cleanups = 0
        addDepartingRow(to: previous) {
            cleanups += 1
            retained.removeAllChildren()
            retained.addChild(replacement)
        }
        let incoming = row("new parent")
        let incomingRetained = row("new retained", tag: "retained")
        incomingRetained.addChild(row("new grandchild", tag: "grandchild"))
        incoming.addChild(incomingRetained)
        let fixture = try AdoptionFixture(previous: [previous], incoming: [incoming])
        defer { fixture.finish() }

        let result = ComponentHost.adopt(source: incoming, into: previous, admission: fixture.admission)

        XCTAssertEqual(cleanups, 1)
        XCTAssertFalse(result.completed)
        XCTAssertNil(result.completion)
        XCTAssertTrue(result.children.first === retained)
        XCTAssertTrue(retained.children.first === replacement)
    }

    func testCompletionDetectsDeepDetachAndReattachAfterTheCallReturns() async throws {
        let previous = row("old parent")
        let retained = row("old retained", tag: "retained")
        let grandchild = row("old grandchild", tag: "grandchild")
        retained.addChild(grandchild)
        previous.addChild(retained)
        let incoming = row("new parent")
        let incomingRetained = row("new retained", tag: "retained")
        incomingRetained.addChild(row("new grandchild", tag: "grandchild"))
        incoming.addChild(incomingRetained)
        let fixture = try AdoptionFixture(previous: [previous], incoming: [incoming])
        defer { fixture.finish() }

        let result = fixture.reconcile()
        XCTAssertTrue(result.completed)
        let completion = try XCTUnwrap(result.completion)
        XCTAssertTrue(completion.isCurrent)
        grandchild.removeFromParent()
        retained.addChild(grandchild)

        XCTAssertTrue(retained.children.first === grandchild)
        XCTAssertFalse(completion.isCurrent)
    }

    func testCompletionDoesNotRetainTheSubtreeOrItsPayloads() async throws {
        var cleanups = 0
        let completion = try XCTUnwrap(captureEphemeralSubtreeCompletion { cleanups += 1 })

        XCTAssertEqual(cleanups, 1)
        XCTAssertFalse(completion.isCurrent)
    }

    func testCompletionIdentityChecksDoNotInvokeApplicationHashingOrEquality() async throws {
        let hooks = AdoptionKeyHooks()
        let node = row("retained")
        let originalIdentity = identity(42, hooks: hooks)
        node.retainedViewIdentity = originalIdentity
        let completion = try XCTUnwrap(RetainedLazyListAdoptionCompletion(of: node))
        var hashCalls = 0
        var comparisons = 0
        hooks.onHash = { hashCalls += 1 }
        hooks.onEqual = { comparisons += 1 }
        defer {
            hooks.onHash = nil
            hooks.onEqual = nil
        }

        XCTAssertTrue(completion.isCurrent)
        XCTAssertTrue(completion.isCurrent)
        node.retainedViewIdentity = originalIdentity

        XCTAssertFalse(completion.isCurrent)
        XCTAssertEqual(hashCalls, 0)
        XCTAssertEqual(comparisons, 0)
    }

    func testLaterCallbackCannotStealAPreparedInsertionFromANewerParent() async throws {
        let retained = row("old", tag: "retained")
        let insertion = row("inserted", tag: "inserted")
        let incomingRetained = row("new", tag: "retained")
        let newerParent = row("newer parent", tag: "other")
        let fixture = try AdoptionFixture(previous: [retained], incoming: [insertion, incomingRetained])
        defer { fixture.finish() }
        incomingRetained.onUpdatePlatformView = { _ in newerParent.addChild(insertion) }

        let result = fixture.reconcile()

        XCTAssertFalse(result.completed)
        XCTAssertTrue(insertion.parent === newerParent)
        XCTAssertTrue(newerParent.children.first === insertion)
        XCTAssertEqual(result.children.count, 1)
        XCTAssertTrue(result.children.first === retained)
    }

    func testContainerDetachAndReattachDoesNotReviveTheOldAdmission() async throws {
        let previous = row("old")
        let oldChild = row("old child", tag: "child")
        previous.addChild(oldChild)
        let incoming = row("new")
        incoming.addChild(row("new child", tag: "child"))
        let fixture = try AdoptionFixture(previous: [previous], incoming: [incoming])
        defer { fixture.finish() }
        incoming.onUpdatePlatformView = { _ in
            fixture.container.removeFromParent()
            fixture.runtime.root.addChild(fixture.container)
        }

        let result = fixture.reconcile()

        XCTAssertFalse(result.completed)
        XCTAssertFalse(fixture.admission.isCurrent)
        XCTAssertTrue(fixture.container.parent === fixture.runtime.root)
        XCTAssertTrue(previous.children.first === oldChild)
        XCTAssertEqual(oldChild.text, "old child")
    }

    func testAnimationTriggerInvalidationStopsBeforeAnotherModifier() async throws {
        let hooks = AdoptionKeyHooks()
        let previous = row("old")
        let incoming = row("new")
        var transformations = 0
        let animation = Animation(duration: 0.4, easing: .linear)
        previous.reconcileAnimationModifiers = [
            .init(transaction: { _ in }),
            .init(animation: animation, value: AdoptionCallbackKey(value: 1, hooks: hooks)),
        ]
        incoming.reconcileAnimationModifiers = [
            .init(transaction: { _ in transformations += 1 }),
            .init(animation: animation, value: AdoptionCallbackKey(value: 2, hooks: hooks)),
        ]
        let fixture = try AdoptionFixture(previous: [previous], incoming: [incoming])
        defer {
            hooks.onEqual = nil
            fixture.finish()
        }
        hooks.onEqual = { fixture.provider.close() }

        let result = fixture.reconcile()

        XCTAssertFalse(result.completed)
        XCTAssertEqual(transformations, 0)
        XCTAssertEqual(previous.text, "old")
    }

    func testPropertyCleanupRejectsAReorderedSourceBeforeLaterCopies() async throws {
        let previous = row("old parent")
        let oldFirst = row("old first", tag: "first")
        let oldSecond = row("old second", tag: "second")
        previous.addChild(oldFirst)
        previous.addChild(oldSecond)
        let incoming = row("new parent")
        let newFirst = row("new first", tag: "first")
        let newSecond = row("new second", tag: "second")
        incoming.addChild(newFirst)
        incoming.addChild(newSecond)
        let fixture = try AdoptionFixture(previous: [previous], incoming: [incoming])
        defer { fixture.finish() }
        var cleanups = 0
        installCanvasCleanup(on: previous) {
            cleanups += 1
            incoming.setChildren([newSecond, newFirst])
        }

        let result = ComponentHost.adopt(source: incoming, into: previous, admission: fixture.admission)

        XCTAssertEqual(cleanups, 1)
        XCTAssertFalse(result.completed)
        XCTAssertTrue(result.didMutate)
        XCTAssertEqual(previous.text, "old parent")
        XCTAssertTrue(previous.children[0] === oldFirst)
        XCTAssertTrue(previous.children[1] === oldSecond)
        XCTAssertTrue(incoming.children[0] === newSecond)
    }

    func testNestedCleanupRejectsAncestorSourceReorderBeforeLaterChildCopies() async throws {
        let previous = row("old parent")
        let oldFirst = row("old first", tag: "first")
        let oldSecond = row("old second", tag: "second")
        previous.addChild(oldFirst)
        previous.addChild(oldSecond)
        let incoming = row("new parent")
        let newFirst = row("new first", tag: "first")
        let newSecond = row("new second", tag: "second")
        incoming.addChild(newFirst)
        incoming.addChild(newSecond)
        let fixture = try AdoptionFixture(previous: [previous], incoming: [incoming])
        defer { fixture.finish() }
        var cleanups = 0
        var firstUpdates = 0
        newFirst.onUpdatePlatformView = { _ in firstUpdates += 1 }
        installCanvasCleanup(on: oldFirst) {
            cleanups += 1
            incoming.setChildren([newSecond, newFirst])
        }

        let result = ComponentHost.adopt(source: incoming, into: previous, admission: fixture.admission)

        XCTAssertEqual(cleanups, 1)
        XCTAssertFalse(result.completed)
        XCTAssertTrue(result.didMutate)
        XCTAssertEqual(previous.text, "new parent")
        XCTAssertEqual(oldFirst.text, "old first")
        XCTAssertEqual(oldSecond.text, "old second")
        XCTAssertEqual(firstUpdates, 0)
        XCTAssertTrue(previous.children[0] === oldFirst)
        XCTAssertTrue(previous.children[1] === oldSecond)
        XCTAssertTrue(incoming.children[0] === newSecond)
    }

    func testClockInvalidationDoesNotInstallAnAnimation() async throws {
        let previous = row("old")
        let incoming = row("new")
        incoming.opacity = 0.4
        incoming.implicitReconcileAnimation = .init(duration: 1, easing: .linear)
        let fixture = try AdoptionFixture(previous: [previous], incoming: [incoming])
        defer { fixture.finish() }
        var clockCalls = 0
        fixture.runtime.clock = {
            clockCalls += 1
            fixture.provider.close()
            return 42
        }

        let result = fixture.reconcile()

        XCTAssertFalse(result.completed)
        XCTAssertEqual(clockCalls, 1)
        XCTAssertEqual(previous.opacity, 1)
        XCTAssertTrue(previous.animationStates.isEmpty)
    }

    func testNonfiniteClockCannotReportAnUninstalledDestinationAsComplete() async throws {
        let previous = row("old")
        let incoming = row("new")
        incoming.opacity = 0.4
        incoming.implicitReconcileAnimation = .init(duration: 1, easing: .linear)
        let fixture = try AdoptionFixture(previous: [previous], incoming: [incoming])
        defer { fixture.finish() }
        fixture.runtime.clock = { .nan }

        let result = fixture.reconcile()

        XCTAssertFalse(result.completed)
        XCTAssertFalse(fixture.admission.isCurrent)
        XCTAssertEqual(previous.opacity, 1)
        XCTAssertTrue(previous.animationStates.isEmpty)
    }

    func testControllerAttachInvalidationStopsBeforeReconciliation() async throws {
        let previous = row("old")
        let incoming = row("new")
        let fixture = try AdoptionFixture(previous: [previous], incoming: [incoming])
        defer { fixture.finish() }
        let controller = AdoptionTestTextController()
        controller.onAttach = { fixture.provider.close() }
        incoming.textInputController = controller

        let result = fixture.reconcile()

        XCTAssertFalse(result.completed)
        XCTAssertEqual(controller.attachCalls, 1)
        XCTAssertEqual(controller.reconcileCalls, 0)
    }

    func testControllerDetachDoesNotClearACallbacksReplacement() async throws {
        let previous = row("old")
        let incoming = row("new")
        let fixture = try AdoptionFixture(previous: [previous], incoming: [incoming])
        defer { fixture.finish() }
        let oldController = AdoptionTestTextController()
        let replacement = AdoptionTestTextController()
        previous.textInputController = oldController
        oldController.onDetach = {
            previous.textInputController = replacement
            fixture.provider.close()
        }

        let result = fixture.reconcile()

        XCTAssertFalse(result.completed)
        XCTAssertEqual(oldController.detachCalls, 1)
        XCTAssertTrue(previous.textInputController === replacement)
    }

    func testObserverHistoryCleanupStopsBeforePublishingLaterConfiguration() async throws {
        let previous = row("old")
        let incoming = row("new")
        previous.scrollReaderID = "old reader"
        incoming.scrollReaderID = "new reader"
        let fixture = try AdoptionFixture(previous: [previous], incoming: [incoming])
        defer { fixture.finish() }
        let oldStorage = RetainedScrollObserverStorage()
        let newStorage = RetainedScrollObserverStorage()
        let oldObserver = observedValueObserver()
        let newObserver = observedValueObserver()
        oldObserver.previousValue = AdoptionObservedValue()
        installObservedCleanup(on: newObserver) { fixture.provider.close() }
        oldStorage.geometry = [oldObserver]
        newStorage.geometry = [newObserver]
        previous.scrollObserverStorage = oldStorage
        incoming.scrollObserverStorage = newStorage

        let result = fixture.reconcile()

        XCTAssertFalse(result.completed)
        XCTAssertTrue(previous.scrollObserverStorage === oldStorage)
        XCTAssertTrue(oldStorage.geometry.first === oldObserver)
        XCTAssertEqual(previous.scrollReaderID, "old reader")
    }

    func testNestedObserverResetRevokesItsOperationWithoutAProviderChange() async throws {
        let previous = row("old")
        let incoming = row("new")
        previous.scrollReaderID = "old reader"
        incoming.scrollReaderID = "new reader"
        let fixture = try AdoptionFixture(previous: [previous], incoming: [incoming])
        defer { fixture.finish() }
        let oldStorage = RetainedScrollObserverStorage()
        let newStorage = RetainedScrollObserverStorage()
        let oldObserver = observedValueObserver()
        let newObserver = observedValueObserver()
        oldObserver.previousValue = AdoptionObservedValue()
        installObservedCleanup(on: newObserver) { oldStorage.reset() }
        oldStorage.geometry = [oldObserver]
        newStorage.geometry = [newObserver]
        previous.scrollObserverStorage = oldStorage
        incoming.scrollObserverStorage = newStorage

        let result = fixture.reconcile()

        XCTAssertFalse(result.completed)
        XCTAssertTrue(fixture.admission.isCurrent)
        XCTAssertTrue(oldStorage.geometry.first === oldObserver)
        XCTAssertNil(oldObserver.previousValue)
        XCTAssertEqual(previous.scrollReaderID, "old reader")
    }

    func testIncomingObserverResetRejectsTheCapturedRegistrationSnapshot() async throws {
        let previous = row("old")
        let incoming = row("new")
        previous.scrollReaderID = "old reader"
        incoming.scrollReaderID = "new reader"
        let fixture = try AdoptionFixture(previous: [previous], incoming: [incoming])
        defer { fixture.finish() }
        let oldStorage = RetainedScrollObserverStorage()
        let newStorage = RetainedScrollObserverStorage()
        let oldObserver = observedValueObserver()
        let newObserver = observedValueObserver()
        oldObserver.previousValue = AdoptionObservedValue()
        installObservedCleanup(on: newObserver) { newStorage.reset() }
        oldStorage.geometry = [oldObserver]
        newStorage.geometry = [newObserver]
        previous.scrollObserverStorage = oldStorage
        incoming.scrollObserverStorage = newStorage

        let result = fixture.reconcile()

        XCTAssertFalse(result.completed)
        XCTAssertTrue(fixture.admission.isCurrent)
        XCTAssertTrue(oldStorage.geometry.first === oldObserver)
        XCTAssertNil(newObserver.previousValue)
        XCTAssertEqual(previous.scrollReaderID, "old reader")
    }

    func testObserverSourceAxisRecreationStopsBeforeLaterHistoryCleanup() async throws {
        let previous = row("old")
        previous.scrollAxis = .vertical
        let incoming = row("new")
        let fixture = try AdoptionFixture(previous: [previous], incoming: [incoming])
        defer { fixture.finish() }
        let selected = row("selected source")
        selected.scrollAxis = .vertical
        fixture.runtime.root.addChild(selected)
        let storage = RetainedScrollObserverStorage()
        let first = observedValueObserver()
        let second = observedValueObserver()
        storage.geometry = [first, second]
        storage.selectSource(previous)
        installObservedCleanup(on: first) {
            selected.scrollAxis = nil
            selected.scrollAxis = .vertical
        }
        second.previousValue = AdoptionObservedValue()

        let completed = storage.selectSource(selected, admission: fixture.admission)

        XCTAssertFalse(completed)
        XCTAssertTrue(fixture.admission.isCurrent)
        XCTAssertNotNil(second.previousValue)
    }

    func testRetiredObserverHistoryIsClearedBeforeAnyPayloadIsReleased() async {
        let storage = RetainedScrollObserverStorage()
        let first = observedValueObserver()
        let second = observedValueObserver()
        storage.geometry = [first, second]
        var cleanups = 0
        var allHistoryWasCleared = true
        for observer in [first, second] {
            installObservedCleanup(on: observer) {
                cleanups += 1
                allHistoryWasCleared = allHistoryWasCleared && first.previousValue == nil && second.previousValue == nil
            }
        }

        var retired: [Any]? = storage.takeLazyListRetiredHistory()
        XCTAssertEqual(retired?.count, 2)
        XCTAssertEqual(cleanups, 0)
        XCTAssertNil(first.previousValue)
        XCTAssertNil(second.previousValue)
        retired = nil

        XCTAssertEqual(cleanups, 2)
        XCTAssertTrue(allHistoryWasCleared)
    }

    func testSameAdapterRefreshPreservesActualMaterializedChildren() async throws {
        let nestedProvider = RetainedLazyListDataSource<Int, [ViewNode]>()
        defer { nestedProvider.close() }
        let nestedAdapter = try XCTUnwrap(
            RetainedLazyListRuntimeAdapter(
                provider: nestedProvider, estimatedExtent: 20, prefetchExtent: 0,
                maximumMountedRecords: 4, maximumMountedLeaves: 16, maximumProtectedRecords: 1))
        let nestedLease = AdoptionTestLease()
        let previous = row("materialized")
        let retainedContainer = row("old container", tag: "container")
        retainedContainer.addChild(previous)
        retainedContainer.retainedSubtreeBuildLease = nestedLease
        retainedContainer.retainedLazyListAdapter = nestedAdapter
        let incomingContainer = row("new container", tag: "container")
        incomingContainer.retainedSubtreeBuildLease = nestedLease
        incomingContainer.retainedLazyListAdapter = nestedAdapter
        let fixture = try AdoptionFixture(previous: [retainedContainer], incoming: [incomingContainer])
        defer { fixture.finish() }
        XCTAssertTrue(incomingContainer.children.isEmpty)

        let result = ComponentHost.adopt(
            source: incomingContainer, into: retainedContainer, admission: fixture.admission)

        XCTAssertTrue(result.completed)
        XCTAssertEqual(result.children.count, 1)
        XCTAssertTrue(result.children.first === previous)
        XCTAssertTrue(previous.parent === retainedContainer)
        XCTAssertEqual(previous.text, "materialized")
        XCTAssertEqual(retainedContainer.text, "new container")
    }

    private func row(_ text: String, tag: String = "row") -> ViewNode {
        let node = ViewNode(frame: Rect(x: 0, y: 0, width: 100, height: 20), text: text)
        node.nodeTag = tag
        return node
    }

    private func identity(_ value: Int, hooks: AdoptionKeyHooks) -> RetainedViewIdentity {
        .init(segments: [.keyed(.init(AdoptionCallbackKey(value: value, hooks: hooks)))])
    }

    private func installCanvasCleanup(on node: ViewNode, action: @escaping @MainActor () -> Void) {
        let payload = AdoptionDeinitAction(action)
        node.canvasDraw = { [payload] _, _ in withExtendedLifetime(payload) {} }
    }

    private func addDepartingRow(to parent: ViewNode, action: @escaping @MainActor () -> Void) {
        let departing = row("departing", tag: "departing")
        installCanvasCleanup(on: departing, action: action)
        parent.addChild(departing)
    }

    private func captureEphemeralSubtreeCompletion(
        action: @escaping @MainActor () -> Void
    ) -> RetainedLazyListAdoptionCompletion? {
        let root = row("ephemeral root")
        let child = row("ephemeral child")
        installCanvasCleanup(on: child, action: action)
        root.addChild(child)
        return RetainedLazyListAdoptionCompletion(of: root)
    }

    private func installActivationCleanup(on node: ViewNode, action: @escaping @MainActor () -> Void) {
        let payload = AdoptionDeinitAction(action)
        node.onActivate = { [payload] in withExtendedLifetime(payload) {} }
    }

    private func installGeometryCleanup(on node: ViewNode, action: @escaping @MainActor () -> Void) {
        let payload = AdoptionDeinitAction(action)
        node.geometryReaderBuiltSize = Size(width: 3, height: 4)
        node.geometryReaderBuild = { [payload] _, _ in
            withExtendedLifetime(payload) {}
            return []
        }
    }

    private func observedValueObserver() -> RetainedScrollGeometryObserver {
        RetainedScrollGeometryObserver(transform: { _ in AdoptionObservedValue() }, action: { _, _ in })
    }

    private func installObservedCleanup(
        on observer: RetainedScrollGeometryObserver, action: @escaping @MainActor () -> Void
    ) {
        observer.previousValue = AdoptionObservedValue(payload: AdoptionDeinitAction(action))
    }
}

@MainActor
private final class AdoptionFixture {
    let provider: RetainedLazyListDataSource<Int, [ViewNode]>
    let adapter: RetainedLazyListRuntimeAdapter
    let container: ViewNode
    let runtime: RetainedViewRuntime
    let lease: AdoptionTestLease
    let epoch: AdoptionTestEpoch
    let candidate: RetainedLazyListRuntimeAdapter.Candidate
    let admission: RetainedLazyListAdoptionAdmission

    init(previous: [ViewNode], incoming: [ViewNode]) throws {
        let provider = RetainedLazyListDataSource<Int, [ViewNode]>()
        guard
            provider.replaceData(
                [0], id: \.self, identityRoot: .init(segments: [.role(.content)]), rowContent: { _, _ in incoming })
        else {
            throw AdoptionFixtureError.setup
        }
        let row = try XCTUnwrap(provider.metadata?.rows.first)
        let request = try XCTUnwrap(provider.request(for: row.token))
        let prefix = try XCTUnwrap(provider.identityPrefix(for: request))
        // These fixture roots have explicit authored tags or known structural
        // slots. Configure both sides before mounting/admission; the factory
        // never rewrites an identity on an already retained alias.
        let previousPaths = previous.enumerated().map { Self.fixturePath(for: $0.element, index: $0.offset) }
        let incomingPaths = incoming.enumerated().map { Self.fixturePath(for: $0.element, index: $0.offset) }
        var configured: Set<ObjectIdentifier> = []
        for (nodes, paths) in [(previous, previousPaths), (incoming, incomingPaths)] {
            for (index, node) in nodes.enumerated() where configured.insert(ObjectIdentifier(node)).inserted {
                node.retainedViewIdentity = prefix.appending(contentsOf: paths[index])
            }
        }
        let adapter = try XCTUnwrap(
            RetainedLazyListRuntimeAdapter(
                provider: provider, estimatedExtent: 20, prefetchExtent: 0,
                maximumMountedRecords: 4, maximumMountedLeaves: 16, maximumProtectedRecords: 1))
        let context = try XCTUnwrap(
            RetainedLazyListMeasurementContext(width: 100, displayScale: 1, contentRevision: 0, environmentRevision: 0))
        let viewport = try XCTUnwrap(RetainedLazyListRuntimeAdapter.Viewport(context: context, offset: 0, extent: 60))
        let budget = try XCTUnwrap(RetainedLazyListWorkBudget(elementLimit: 4, roundLimit: 2))
        let container = ViewNode(frame: Rect(x: 0, y: 0, width: 100, height: 60))
        for node in previous { container.addChild(node) }
        let runtime = RetainedViewRuntime(root: ViewNode(frame: Rect(x: 0, y: 0, width: 100, height: 60)))
        runtime.root.addChild(container)
        let lease = AdoptionTestLease()
        container.retainedSubtreeBuildLease = lease
        container.retainedLazyListAdapter = adapter
        let coordinator = runtime.retainedBuildCoordinator
        let sequence = try XCTUnwrap(coordinator.beginBuild())
        let epoch = AdoptionTestEpoch()
        coordinator.install(epoch, startedAt: sequence)
        let admission = RetainedLazyListAdoptionAdmission(
            adapter: adapter, container: container, runtime: runtime,
            coordinator: coordinator, sequence: sequence)
        var setupCompleted = false
        defer {
            if !setupCompleted {
                epoch.abandon()
                epoch.finishAfterCallbacks()
                coordinator.finishBuild()
            }
        }
        guard
            case .ready(let candidate) = adapter.prepare(
                viewport: viewport, protectedRoots: [], budget: budget, admission: admission),
            admission.installCandidate(candidate), epoch.willAdopt(), admission.isCurrent
        else { throw AdoptionFixtureError.setup }
        self.provider = provider
        self.adapter = adapter
        self.container = container
        self.runtime = runtime
        self.lease = lease
        self.epoch = epoch
        self.candidate = candidate
        self.admission = admission
        setupCompleted = true
    }

    private static func fixturePath(for node: ViewNode, index: Int) -> [RetainedViewIdentity.Segment] {
        if let identity = node.retainedViewIdentity { return [.role(.content)] + identity.segments }
        if let tag = node.nodeTag { return [.role(.content), .explicit(.init(tag))] }
        return [.role(.content), .slot(index)]
    }

    func reconcile() -> RetainedLazyListAdoptionResult {
        ComponentHost.reconcileChildren(
            of: container, oldChildren: container.children, newNodes: candidate.children, admission: admission)
    }

    func finish() {
        provider.close()
        // Tests intentionally retain fixture state in reentrant callbacks.
        // Release those captures even when an assertion exposed an early stop.
        runtime.clock = { 0 }
        var pending = candidate.children + [container]
        var visited: Set<ObjectIdentifier> = []
        while let node = pending.popLast() {
            guard visited.insert(ObjectIdentifier(node)).inserted else { continue }
            pending.append(contentsOf: node.children)
            node.onUpdatePlatformView = nil
            node.canvasDraw = nil
            node.onActivate = nil
            node.onRepeatActivate = nil
            node.geometryReaderBuild = nil
            node.reconcileAnimationModifiers = []
            if let controller = node.textInputController as? AdoptionTestTextController {
                controller.onAttach = nil
                controller.onDetach = nil
            }
            _ = node.scrollObserverStorage?.takeLazyListRetiredHistory()
        }
        if admission.didMutate { epoch.commit() } else { epoch.abandon() }
        epoch.finishAfterCallbacks()
        runtime.retainedBuildCoordinator.finishBuild()
    }
}

private enum AdoptionFixtureError: Error { case setup }

@MainActor
private final class AdoptionTestLease: RetainedSubtreeBuildLease {
    var canBuild: Bool { true }
    func beginBuild() -> (any RetainedBuildEpoch)? { AdoptionTestEpoch() }
}

@MainActor
private final class AdoptionTestEpoch: RetainedBuildEpoch {
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

@MainActor
private final class AdoptionTestTextController: RetainedTextInputController {
    var onAttach: (() -> Void)?
    var onDetach: (() -> Void)?
    private(set) var attachCalls = 0
    private(set) var reconcileCalls = 0
    private(set) var detachCalls = 0

    func attach(to node: ViewNode) {
        attachCalls += 1
        onAttach?()
    }
    func reconcile(from previous: (any RetainedTextInputController)?, onto node: ViewNode) {
        reconcileCalls += 1
    }
    func detach(from node: ViewNode) {
        detachCalls += 1
        onDetach?()
    }
}

@MainActor
private final class AdoptionKeyHooks {
    var onHash: (() -> Void)?
    var onEqual: (() -> Void)?
}

private struct AdoptionCallbackKey: Hashable {
    let value: Int
    let hooks: AdoptionKeyHooks

    static func == (lhs: Self, rhs: Self) -> Bool {
        MainActor.assumeIsolated { lhs.hooks.onEqual?() }
        return lhs.value == rhs.value
    }
    func hash(into hasher: inout Hasher) {
        MainActor.assumeIsolated { hooks.onHash?() }
        hasher.combine(value)
    }
}

private final class AdoptionDeinitAction {
    let action: @MainActor () -> Void
    init(_ action: @escaping @MainActor () -> Void) { self.action = action }
    deinit { MainActor.assumeIsolated { [action] in action() } }
}

private struct AdoptionObservedValue: Equatable {
    let payload: AdoptionDeinitAction?
    init(payload: AdoptionDeinitAction? = nil) { self.payload = payload }
    static func == (lhs: Self, rhs: Self) -> Bool { lhs.payload === rhs.payload }
}
