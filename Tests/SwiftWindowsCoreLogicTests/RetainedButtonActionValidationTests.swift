import SwiftWindowsCore
@preconcurrency import XCTest

@testable import SwiftWindowsUI

@MainActor
final class RetainedButtonActionValidationTests: XCTestCase {
    func testDiagnosticsAreDisabledByDefault() async throws {
        let fixture = try ButtonValidationFixture(collectDiagnostics: false)
        defer { fixture.finish() }

        XCTAssertNil(fixture.adoption.validationSnapshot)
        XCTAssertTrue(fixture.adoption.isCurrent)
        XCTAssertNil(fixture.adoption.validationSnapshot)
    }

    func testRepeatedChecksVisitEveryWitnessExactlyOnce() async throws {
        for leafCount in [0, 4, 31] {
            let fixture = try ButtonValidationFixture(leafCount: leafCount)
            defer { fixture.finish() }
            let before = try XCTUnwrap(fixture.adoption.validationSnapshot)
            XCTAssertEqual(before.witnessCount, leafCount + 3)
            XCTAssertEqual(before.checkCount, 0)
            XCTAssertEqual(before.witnessVisitCount, 0)

            for _ in 0..<7 { XCTAssertTrue(fixture.adoption.isCurrent) }

            let after = try XCTUnwrap(fixture.adoption.validationSnapshot)
            XCTAssertEqual(after.checkCount, 7)
            XCTAssertEqual(after.witnessVisitCount, 7 * UInt64(after.witnessCount))
            XCTAssertFalse(after.didOverflow)
        }
    }

    func testSnapshotsDoNotChangeWhenLaterChecksRun() async throws {
        let fixture = try ButtonValidationFixture()
        defer { fixture.finish() }
        let before = try XCTUnwrap(fixture.adoption.validationSnapshot)

        XCTAssertTrue(fixture.adoption.isCurrent)

        let after = try XCTUnwrap(fixture.adoption.validationSnapshot)
        XCTAssertEqual(before.checkCount, 0)
        XCTAssertEqual(before.witnessVisitCount, 0)
        XCTAssertEqual(after.checkCount, 1)
        XCTAssertEqual(after.witnessVisitCount, UInt64(after.witnessCount))
    }

    func testRefusedOperationDoesNotVisitAnyWitness() async throws {
        let fixture = try ButtonValidationFixture()
        defer { fixture.finish() }
        fixture.finish()
        let before = try XCTUnwrap(fixture.adoption.validationSnapshot)

        XCTAssertFalse(fixture.adoption.isCurrent)

        let after = try XCTUnwrap(fixture.adoption.validationSnapshot)
        XCTAssertEqual(after.checkCount - before.checkCount, 1)
        XCTAssertEqual(after.witnessVisitCount, before.witnessVisitCount)
    }

    func testAllInvalidWitnessesStopAtTheFirstRefusal() async throws {
        let fixture = try ButtonValidationFixture(leafCount: 8)
        defer { fixture.finish() }
        for node in fixture.capturedNodes {
            let unchangedIdentity = node.retainedViewIdentity
            node.retainedViewIdentity = unchangedIdentity
        }
        let before = try XCTUnwrap(fixture.adoption.validationSnapshot)

        XCTAssertFalse(fixture.adoption.isCurrent)

        let after = try XCTUnwrap(fixture.adoption.validationSnapshot)
        XCTAssertEqual(after.checkCount - before.checkCount, 1)
        XCTAssertEqual(after.witnessVisitCount - before.witnessVisitCount, 1)
    }

    func testQueryRefusalDoesNotBecomeAStickyWriteRefusal() async throws {
        let fixture = try ButtonValidationFixture()
        defer { fixture.finish() }
        let original = fixture.parent.children
        XCTAssertTrue(fixture.parent.setChildren([fixture.button, fixture.leaves[1], fixture.leaves[0]]).completed)
        XCTAssertFalse(fixture.adoption.isCurrent)

        XCTAssertTrue(fixture.parent.setChildren(original).completed)

        XCTAssertTrue(fixture.adoption.isCurrent)
    }

    func testFailedAuthorizedWriteRemainsRejectedAfterRestoration() async throws {
        let fixture = try ButtonValidationFixture()
        defer { fixture.finish() }
        let original = fixture.parent.children
        XCTAssertTrue(fixture.parent.setChildren([fixture.button, fixture.leaves[1], fixture.leaves[0]]).completed)
        XCTAssertFalse(fixture.adoption.recordChildrenWrite(on: fixture.runtime.root))
        XCTAssertTrue(fixture.parent.setChildren(original).completed)
        let before = try XCTUnwrap(fixture.adoption.validationSnapshot)

        XCTAssertFalse(fixture.adoption.isCurrent)
        XCTAssertFalse(fixture.adoption.recordChildrenWrite(on: fixture.parent))

        let after = try XCTUnwrap(fixture.adoption.validationSnapshot)
        XCTAssertEqual(after.checkCount - before.checkCount, 1)
        XCTAssertEqual(after.witnessVisitCount, before.witnessVisitCount)
    }

    func testExpiredWeakTargetStillRefusesValidation() async throws {
        let runtime = RetainedViewRuntime(root: ViewNode())
        defer {
            runtime.stopRenderLifecycleCallbacks()
            runtime.cancelRenderLifecycleTasks()
        }
        var node: ViewNode? = makeValidationButton(runtime: runtime)
        weak var observedNode = node
        let adoption = try XCTUnwrap(
            RetainedButtonActionAdoption(
                retainedRoots: [try XCTUnwrap(node)], sourceRoots: [], collectValidationDiagnostics: true))
        let check = try makeValidationCleanupCheck(runtime: runtime)
        defer { _ = adoption.finish(completed: false, check: check, completion: nil) }
        node = nil
        XCTAssertNil(observedNode)
        let before = try XCTUnwrap(adoption.validationSnapshot)

        XCTAssertFalse(adoption.isCurrent)

        let after = try XCTUnwrap(adoption.validationSnapshot)
        XCTAssertEqual(after.checkCount - before.checkCount, 1)
        XCTAssertEqual(after.witnessVisitCount - before.witnessVisitCount, 1)
    }

    func testChildTableChangesRemainRejected() async throws {
        for change in 0..<4 {
            let fixture = try ButtonValidationFixture()
            defer { fixture.finish() }
            let children: [ViewNode]
            switch change {
            case 0: children = [fixture.button, fixture.leaves[1], fixture.leaves[0]]
            case 1: children = [fixture.button, fixture.leaves[0]]
            case 2: children = [fixture.button, fixture.leaves[0], fixture.leaves[1], ViewNode()]
            default: children = [fixture.button, fixture.leaves[0], ViewNode()]
            }
            XCTAssertTrue(fixture.parent.setChildren(children).completed)

            XCTAssertFalse(fixture.adoption.isCurrent, "change \(change)")
        }
    }

    func testParentChangeRemainsRejected() async throws {
        let fixture = try ButtonValidationFixture()
        defer { fixture.finish() }
        let replacementParent = ViewNode()
        replacementParent.addChild(fixture.leaves[0])
        XCTAssertTrue(fixture.leaves[0].parent === replacementParent)

        XCTAssertFalse(fixture.adoption.isCurrent)
        withExtendedLifetime(replacementParent) {}
    }

    func testRuntimeChangeRemainsRejected() async throws {
        let fixture = try ButtonValidationFixture()
        defer { fixture.finish() }
        let replacementRuntime = RetainedViewRuntime(root: ViewNode())
        defer {
            replacementRuntime.stopRenderLifecycleCallbacks()
            replacementRuntime.cancelRenderLifecycleTasks()
        }
        replacementRuntime.root.addChild(fixture.leaves[0])
        XCTAssertTrue(fixture.leaves[0].retainedLazyListRuntime === replacementRuntime)

        XCTAssertFalse(fixture.adoption.isCurrent)
    }

    func testOwnerIdentityPresenceAndRetirementRemainChecked() async throws {
        for change in 0..<4 {
            let fixture = try ButtonValidationFixture()
            defer { fixture.finish() }
            switch change {
            case 0: fixture.button.buttonActionOwner = nil
            case 1:
                fixture.button.buttonActionOwner = RetainedButtonActionOwner(
                    action: nil, node: fixture.button, runtime: fixture.runtime)
            case 2: fixture.owner.retire()
            default:
                fixture.leaves[0].buttonActionOwner = RetainedButtonActionOwner(
                    action: nil, node: fixture.leaves[0], runtime: fixture.runtime)
            }

            XCTAssertFalse(fixture.adoption.isCurrent, "change \(change)")
        }
    }

    func testEqualIdentityAssignmentAndIdentityABARemainRejected() async throws {
        for replaceBeforeRestoring in [false, true] {
            let fixture = try ButtonValidationFixture()
            defer { fixture.finish() }
            let node = fixture.leaves[0]
            let original = node.retainedViewIdentity
            if replaceBeforeRestoring {
                node.retainedViewIdentity = RetainedViewIdentity(segments: [.role(.content)])
            }
            node.retainedViewIdentity = original
            XCTAssertEqual(node.retainedViewIdentity, original)

            XCTAssertFalse(fixture.adoption.isCurrent)
        }
    }

    func testReturningToTheSameAttachmentDoesNotRefreshItsProof() async throws {
        let fixture = try ButtonValidationFixture()
        defer { fixture.finish() }
        let node = fixture.leaves[1]
        node.removeFromParent()
        fixture.parent.addChild(node)
        XCTAssertTrue(node.parent === fixture.parent)
        XCTAssertTrue(node.retainedLazyListRuntime === fixture.runtime)

        XCTAssertFalse(fixture.adoption.isCurrent)
    }

    func testAuthorizedChildWriteStillAdvancesOnlyItsWitness() async throws {
        let fixture = try ButtonValidationFixture()
        defer { fixture.finish() }
        XCTAssertTrue(fixture.parent.setChildren([fixture.button, fixture.leaves[1], fixture.leaves[0]]).completed)
        XCTAssertTrue(fixture.adoption.recordChildrenWrite(on: fixture.parent))
        let before = try XCTUnwrap(fixture.adoption.validationSnapshot)

        XCTAssertTrue(fixture.adoption.isCurrent)

        let after = try XCTUnwrap(fixture.adoption.validationSnapshot)
        XCTAssertEqual(after.checkCount - before.checkCount, 1)
        XCTAssertEqual(after.witnessVisitCount - before.witnessVisitCount, UInt64(after.witnessCount))
    }

    func testKeepingScalarSnapshotsDoesNotKeepSourceOrPayloadAlive() async throws {
        let runtime = RetainedViewRuntime(root: ViewNode())
        defer {
            runtime.stopRenderLifecycleCallbacks()
            runtime.cancelRenderLifecycleTasks()
        }
        let events = ButtonValidationReleaseEvents()
        var source: ViewNode? = makeValidationProbedButton(runtime: runtime, events: events)
        weak var observedSource = source
        let adoption = try XCTUnwrap(
            RetainedButtonActionAdoption(
                retainedRoots: [], sourceRoots: [try XCTUnwrap(source)], collectValidationDiagnostics: true))
        let check = try makeValidationCleanupCheck(runtime: runtime)
        defer { _ = adoption.finish(completed: false, check: check, completion: nil) }
        XCTAssertTrue(adoption.isCurrent)
        let snapshot = try XCTUnwrap(adoption.validationSnapshot)

        XCTAssertFalse(adoption.finish(completed: false, check: check, completion: nil))
        source = nil

        XCTAssertNil(observedSource)
        XCTAssertNil(events.probe)
        XCTAssertEqual(events.releases, 1)
        XCTAssertEqual(snapshot.checkCount, 1)
        XCTAssertEqual(snapshot.witnessVisitCount, 1)
        XCTAssertEqual(snapshot.witnessCount, 1)
        XCTAssertFalse(snapshot.didOverflow)
        withExtendedLifetime(snapshot) {}
    }

    func testDiagnosticArithmeticSaturatesAndReportsOverflow() async {
        // These are standalone arithmetic boundary inputs, not observations
        // claiming that an adoption actually executed UInt64.max checks.
        var counters = RetainedButtonActionAdoption.ValidationCounters(
            witnessCount: 3, checkCount: .max - 1, witnessVisitCount: .max - 1)
        counters.recordCheck()
        counters.recordVisit()
        let exactMaximum = counters.snapshot
        XCTAssertEqual(exactMaximum.checkCount, .max)
        XCTAssertEqual(exactMaximum.witnessVisitCount, .max)
        XCTAssertFalse(exactMaximum.didOverflow)

        counters.recordCheck()
        counters.recordVisit()
        counters.recordCheck()
        counters.recordVisit()

        let saturated = counters.snapshot
        XCTAssertEqual(saturated.checkCount, .max)
        XCTAssertEqual(saturated.witnessVisitCount, .max)
        XCTAssertEqual(saturated.witnessCount, 3)
        XCTAssertTrue(saturated.didOverflow)
        XCTAssertFalse(exactMaximum.didOverflow)
    }
}

@MainActor
private final class ButtonValidationFixture {
    let runtime: RetainedViewRuntime
    let parent: ViewNode
    let button: ViewNode
    let leaves: [ViewNode]
    let owner: RetainedButtonActionOwner
    let adoption: RetainedButtonActionAdoption
    private let cleanupCheck: ComponentHost.NodeReconcileAdmission
    private var didFinish = false

    var capturedNodes: [ViewNode] { [runtime.root, parent, button] + leaves }

    init(leafCount: Int = 2, collectDiagnostics: Bool = true) throws {
        let runtime = RetainedViewRuntime(root: ViewNode())
        let button = makeValidationButton(runtime: runtime)
        let owner = try XCTUnwrap(button.buttonActionOwner)
        let leaves = (0..<leafCount).map { _ in ViewNode() }
        let parent = ViewNode(children: [button] + leaves)
        runtime.root.addChild(parent)
        let cleanupCheck = try makeValidationCleanupCheck(runtime: runtime)
        let candidate =
            collectDiagnostics
            ? RetainedButtonActionAdoption(
                retainedRoots: [parent], sourceRoots: [], collectValidationDiagnostics: true)
            : RetainedButtonActionAdoption(retainedRoots: [parent], sourceRoots: [])
        self.runtime = runtime
        self.parent = parent
        self.button = button
        self.leaves = leaves
        self.owner = owner
        adoption = try XCTUnwrap(candidate)
        self.cleanupCheck = cleanupCheck
    }

    func finish() {
        guard !didFinish else { return }
        didFinish = true
        _ = adoption.finish(completed: false, check: cleanupCheck, completion: nil)
        runtime.stopRenderLifecycleCallbacks()
        runtime.cancelRenderLifecycleTasks()
    }
}

@MainActor
private func makeValidationButton(runtime: RetainedViewRuntime, action: (() -> Void)? = nil) -> ViewNode {
    let node = ViewNode()
    node.buttonActionOwner = RetainedButtonActionOwner(action: action, node: node, runtime: runtime)
    return node
}

@MainActor
private func makeValidationCleanupCheck(runtime: RetainedViewRuntime) throws -> ComponentHost.NodeReconcileAdmission {
    try XCTUnwrap(
        ComponentHost.makeRemovalTransitionCheck(
            admission: nil, target: runtime.root, parent: runtime.root, proposedChildren: [], lazyJournal: nil))
}

@MainActor
@inline(never)
private func makeValidationProbedButton(
    runtime: RetainedViewRuntime, events: ButtonValidationReleaseEvents
) -> ViewNode {
    let probe = ButtonValidationReleaseProbe(events: events)
    events.probe = probe
    return makeValidationButton(runtime: runtime) { [probe] in withExtendedLifetime(probe) {} }
}

@MainActor
private final class ButtonValidationReleaseEvents {
    var releases = 0
    weak var probe: ButtonValidationReleaseProbe?
}

@MainActor
private final class ButtonValidationReleaseProbe {
    let events: ButtonValidationReleaseEvents
    init(events: ButtonValidationReleaseEvents) { self.events = events }
    isolated deinit { events.releases += 1 }
}
