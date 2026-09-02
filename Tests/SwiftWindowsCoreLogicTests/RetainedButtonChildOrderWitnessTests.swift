@preconcurrency import XCTest

@testable import SwiftWindowsUI

@MainActor
final class RetainedButtonChildOrderWitnessTests: XCTestCase {
    func testChildOrderWitnessAgreesWithArrayIdentityComparison() async throws {
        let cases: [(name: String, indices: [Int], expected: Bool)] = [
            ("unchanged", [0, 1], true),
            ("reordered", [1, 0], false),
            ("inserted", [0, 1, 2], false),
            ("removed", [0], false),
            ("equal-count replacement", [0, 2], false),
        ]
        for entry in cases {
            let fixture = try ButtonChildOrderWitnessFixture()
            defer { fixture.finish() }
            let original = fixture.parent.children.map(ObjectIdentifier.init)
            XCTAssertTrue(fixture.adoption.isCurrent, entry.name)

            let children = [fixture.button] + entry.indices.map { fixture.leaves[$0] }
            XCTAssertTrue(fixture.parent.setChildren(children).completed, entry.name)
            fixture.assertUnchangedNonChildWitnesses()

            let arrayOracle = original == fixture.parent.children.map(ObjectIdentifier.init)
            XCTAssertEqual(arrayOracle, entry.expected, entry.name)
            XCTAssertEqual(fixture.adoption.isCurrent, arrayOracle, entry.name)
        }
    }

    func testAuthorizedChildWriteAdvancesOnlyThatCapturedOrder() async throws {
        let fixture = try ButtonChildOrderWitnessFixture()
        defer { fixture.finish() }
        let original = fixture.parent.children
        let accepted = [fixture.button, fixture.leaves[1], fixture.leaves[0]]
        XCTAssertTrue(fixture.adoption.isCurrent)

        // These detached nodes have no removal, task, or animation callbacks.
        // Advance only the parent table immediately after its native write.
        let result = fixture.parent.setChildren(accepted)
        let recorded = fixture.adoption.recordChildrenWrite(on: fixture.parent)
        XCTAssertTrue(result.completed)
        XCTAssertTrue(recorded)
        fixture.assertUnchangedNonChildWitnesses()
        XCTAssertTrue(fixture.adoption.isCurrent)
        XCTAssertEqual(fixture.parent.children.map(ObjectIdentifier.init), accepted.map(ObjectIdentifier.init))

        XCTAssertTrue(fixture.parent.setChildren(original).completed)
        fixture.assertUnchangedNonChildWitnesses()
        XCTAssertFalse(fixture.adoption.isCurrent, "The accepted order remains the current obligation")
    }

    func testAuthorizedChildWriteCannotRefreshUnrelatedChildMutation() async throws {
        let fixture = try ButtonChildOrderWitnessFixture()
        defer { fixture.finish() }
        XCTAssertTrue(fixture.adoption.isCurrent)

        let intended = fixture.parent.setChildren([fixture.button, fixture.leaves[1], fixture.leaves[0]])
        let unrelated = fixture.outer.setChildren([fixture.neighbor, fixture.parent])
        let recorded = fixture.adoption.recordChildrenWrite(on: fixture.parent)
        XCTAssertTrue(intended.completed)
        XCTAssertTrue(unrelated.completed)
        fixture.assertUnchangedNonChildWitnesses()
        XCTAssertFalse(recorded, "The child-order exception applies only to the named parent")
        XCTAssertFalse(fixture.adoption.isCurrent)
        XCTAssertFalse(fixture.adoption.recordChildrenWrite(on: fixture.outer), "A failed operation stays rejected")
    }
}

@MainActor
private final class ButtonChildOrderWitnessFixture {
    let runtime: RetainedViewRuntime
    let outer: ViewNode
    let parent: ViewNode
    let button: ViewNode
    let leaves: [ViewNode]
    let neighbor: ViewNode
    let adoption: RetainedButtonActionAdoption
    private let owner: RetainedButtonActionOwner
    private let attachments: [RetainedLazyListAttachmentProof]
    private let identities: [RetainedLazyListViewIdentityProof]
    private let cleanupCheck: ComponentHost.NodeReconcileAdmission

    init() throws {
        let runtime = RetainedViewRuntime(root: ViewNode())
        let button = ViewNode()
        let leaves = [ViewNode(), ViewNode(), ViewNode()]
        let parent = ViewNode(children: [button, leaves[0], leaves[1]])
        let neighbor = ViewNode()
        let outer = ViewNode(children: [parent, neighbor])
        let owner = RetainedButtonActionOwner(action: nil, node: button, runtime: runtime)
        button.buttonActionOwner = owner
        let cleanupCheck = try XCTUnwrap(
            ComponentHost.makeRemovalTransitionCheck(
                admission: nil, target: parent, parent: parent, proposedChildren: [], lazyJournal: nil))

        // Only the Button is a retained root. Its ancestors' child tables are
        // witnessed, but their other children are not captured descendants.
        // Removing or replacing a leaf therefore isolates the order predicate.
        let adoption = try XCTUnwrap(RetainedButtonActionAdoption(retainedRoots: [button], sourceRoots: []))
        self.runtime = runtime
        self.outer = outer
        self.parent = parent
        self.button = button
        self.leaves = leaves
        self.neighbor = neighbor
        self.owner = owner
        self.adoption = adoption
        self.cleanupCheck = cleanupCheck
        attachments = [outer, parent, button].map { $0.captureLazyListAttachmentProof() }
        identities = [outer, parent, button].map { $0.captureLazyListIdentityProof() }
    }

    func assertUnchangedNonChildWitnesses(file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(attachments.allSatisfy(\.isCurrent), file: file, line: line)
        XCTAssertTrue(identities.allSatisfy(\.isCurrent), file: file, line: line)
        XCTAssertNil(outer.buttonActionOwner, file: file, line: line)
        XCTAssertNil(parent.buttonActionOwner, file: file, line: line)
        XCTAssertTrue(button.buttonActionOwner === owner, file: file, line: line)
        XCTAssertFalse(owner.isRetired, file: file, line: line)
        XCTAssertTrue(runtime.permitsRetainedActionInvocation, file: file, line: line)
    }

    func finish() {
        _ = adoption.finish(completed: false, check: cleanupCheck, completion: nil)
        runtime.stopRenderLifecycleCallbacks()
        runtime.cancelRenderLifecycleTasks()
    }
}
