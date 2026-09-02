import SwiftWindowsCore
import XCTest

@testable import SwiftWindowsUI

@MainActor
final class OrdinaryFinalChildrenCutBoundaryTests: XCTestCase {
    func testFinalFieldWriteReleasesPayloadAfterWithdrawalBeforeDeferredCleanup() async throws {
        let fixture = CutBoundaryFixture()
        let parent = fixture.runtime.root
        let outgoing = ViewNode()
        let incoming = ViewNode()
        parent.addChild(outgoing)
        let releases = CutBoundaryReleases(parent: parent, incoming: incoming)
        var callbackError: Error?
        outgoing.onDismantlePlatformView = { departing in
            releases.events.append("dismantle")
            XCTAssertTrue(departing === outgoing)
            XCTAssertTrue(parent.children.isEmpty)
            do {
                try installCutBoundaryPayload(fixture, parent: parent, releases: releases)
                releases.events.append("accepted")
                XCTAssertTrue(releases.node != nil)
                XCTAssertEqual(releases.count, 0)
                fixture.runtime.afterRetainedCallbacks {
                    releases.events.append("deferred")
                    XCTAssertEqual(releases.count, 1)
                    XCTAssertNil(releases.node)
                    XCTAssertTrue(releases.fieldWasRequestedAtRelease)
                    XCTAssertTrue(releases.ownershipWasWithdrawnAtRelease)
                }
            } catch {
                callbackError = error
            }
        }
        defer { outgoing.onDismantlePlatformView = nil }

        releases.events.append("replace-begin")
        let result = parent.setChildren([incoming])
        releases.events.append("replace-returned")

        if let callbackError { throw callbackError }
        let evidence = try XCTUnwrap(releases.evidence)
        XCTAssertEqual(
            releases.events,
            ["replace-begin", "dismantle", "accepted", "payload-release", "deferred", "replace-returned"])
        XCTAssertEqual(releases.count, 1)
        XCTAssertNil(releases.node)
        XCTAssertTrue(releases.fieldWasRequestedAtRelease)
        XCTAssertTrue(releases.ownershipWasWithdrawnAtRelease)
        XCTAssertTrue(result.completed)
        XCTAssertTrue(result.didMutate)
        XCTAssertEqual(result.children.count, 1)
        XCTAssertTrue(result.children.first === incoming)
        XCTAssertTrue(incoming.parent === parent)
        XCTAssertTrue(incoming.retainedLazyListRuntime === fixture.runtime)
        evidence.assertWithdrawn()
        fixture.assertRootIsCurrent()
    }

    func testRefusalSurvivesDeferredCallbackThatInstallsRequestedChildren() async throws {
        let fixture = CutBoundaryFixture()
        let parent = fixture.runtime.root
        let outgoing = ViewNode()
        let incoming = ViewNode()
        parent.addChild(outgoing)
        let malformed = ViewNode()
        let repeated = ViewNode()
        let duplicateResult = malformed.setChildren([repeated, repeated])
        XCTAssertTrue(duplicateResult.completed)
        var late: CutBoundaryPublication?
        var callbackError: Error?
        var deferredCount = 0
        var nestedCompleted = false
        outgoing.onDismantlePlatformView = { departing in
            XCTAssertTrue(departing === outgoing)
            XCTAssertTrue(parent.children.isEmpty)
            do {
                let publication = try fixture.acceptSource(identity: 1, parent: parent)
                late = publication
                parent.addChild(malformed)
                publication.evidence.assertLive()
                fixture.runtime.afterRetainedCallbacks {
                    deferredCount += 1
                    // Refusal must not partially withdraw the earlier valid sibling.
                    XCTAssertEqual(parent.children.count, 2)
                    XCTAssertTrue(parent.children.first === publication.node)
                    XCTAssertTrue(parent.children.last === malformed)
                    publication.evidence.assertLive()
                    let repaired = malformed.setChildren([repeated])
                    XCTAssertTrue(repaired.completed)
                    let nested = parent.setChildren([incoming])
                    nestedCompleted = nested.completed
                    XCTAssertTrue(nested.completed)
                    XCTAssertTrue(parent.children.first === incoming)
                }
                XCTAssertEqual(deferredCount, 0)
            } catch {
                callbackError = error
            }
        }
        defer { outgoing.onDismantlePlatformView = nil }

        let result = parent.setChildren([incoming])

        if let callbackError { throw callbackError }
        let publication = try XCTUnwrap(late)
        XCTAssertEqual(deferredCount, 1)
        XCTAssertTrue(nestedCompleted)
        XCTAssertFalse(result.completed)
        XCTAssertTrue(result.didMutate)
        XCTAssertEqual(result.children.count, 1)
        XCTAssertTrue(result.children.first === incoming)
        XCTAssertEqual(parent.children.count, 1)
        XCTAssertTrue(parent.children.first === incoming)
        XCTAssertNil(outgoing.parent)
        XCTAssertNil(outgoing.retainedLazyListRuntime)
        publication.evidence.assertWithdrawn()
        fixture.assertRootIsCurrent()
    }

    func testMalformedOmittedForestDoesNotWithdrawAnEarlierValidSibling() async throws {
        let fixture = CutBoundaryFixture()
        let parent = fixture.runtime.root
        let outgoing = ViewNode()
        let incoming = ViewNode()
        parent.addChild(outgoing)
        let malformed = ViewNode()
        let repeated = ViewNode()
        XCTAssertTrue(malformed.setChildren([repeated, repeated]).completed)
        var late: CutBoundaryPublication?
        var callbackError: Error?
        outgoing.onDismantlePlatformView = { departing in
            XCTAssertTrue(departing === outgoing)
            XCTAssertTrue(parent.children.isEmpty)
            do {
                let publication = try fixture.acceptSource(identity: 1, parent: parent)
                late = publication
                parent.addChild(malformed)
                XCTAssertEqual(malformed.children.count, 2)
                XCTAssertTrue(malformed.children.allSatisfy { $0 === repeated })
                publication.evidence.assertLive()
            } catch {
                callbackError = error
            }
        }
        defer {
            outgoing.onDismantlePlatformView = nil
            _ = malformed.setChildren([repeated])
        }

        let result = parent.setChildren([incoming])

        if let callbackError { throw callbackError }
        let publication = try XCTUnwrap(late)
        XCTAssertFalse(result.completed)
        XCTAssertTrue(result.didMutate)
        XCTAssertEqual(result.children.count, 2)
        XCTAssertTrue(result.children.first === publication.node)
        XCTAssertTrue(result.children.last === malformed)
        XCTAssertEqual(parent.children.count, 2)
        XCTAssertTrue(parent.children.first === publication.node)
        XCTAssertTrue(parent.children.last === malformed)
        XCTAssertFalse(parent.children.contains { $0 === incoming })
        XCTAssertNil(outgoing.parent)
        XCTAssertNil(outgoing.retainedLazyListRuntime)
        publication.evidence.assertLive()
        fixture.assertRootIsCurrent()
    }

    func testDepthRefusalDoesNotWithdrawAnEarlierValidSibling() async throws {
        let fixture = CutBoundaryFixture()
        let parent = fixture.runtime.root
        let outgoing = ViewNode()
        let incoming = ViewNode()
        parent.addChild(outgoing)
        let deepRoot = ViewNode()
        var chain = [deepRoot]
        let depthLimit = ViewNode.maximumTraversalDepth
        XCTAssertGreaterThan(depthLimit, 0)
        var late: CutBoundaryPublication?
        var callbackError: Error?
        outgoing.onDismantlePlatformView = { departing in
            XCTAssertTrue(departing === outgoing)
            XCTAssertTrue(parent.children.isEmpty)
            do {
                let publication = try fixture.acceptSource(identity: 1, parent: parent)
                late = publication
                parent.addChild(deepRoot)
                // Attach one empty leaf at a time: no recursive mounting of a
                // prebuilt deep subtree, and no change to the production cap.
                for _ in 0..<depthLimit {
                    let child = ViewNode()
                    chain.last?.addChild(child)
                    chain.append(child)
                }
                XCTAssertEqual(chain.count, depthLimit + 1)
                XCTAssertTrue(chain.last?.retainedLazyListRuntime === fixture.runtime)
                publication.evidence.assertLive()
            } catch {
                callbackError = error
            }
        }
        defer {
            outgoing.onDismantlePlatformView = nil
            // Remove leaves before parents instead of recursively detaching
            // the full over-depth tree during fixture cleanup.
            for node in chain.reversed() { node.removeAllChildren() }
        }

        let result = parent.setChildren([incoming])

        if let callbackError { throw callbackError }
        let publication = try XCTUnwrap(late)
        XCTAssertFalse(result.completed)
        XCTAssertTrue(result.didMutate)
        XCTAssertEqual(result.children.count, 2)
        XCTAssertTrue(result.children.first === publication.node)
        XCTAssertTrue(result.children.last === deepRoot)
        XCTAssertEqual(parent.children.count, 2)
        XCTAssertFalse(parent.children.contains { $0 === incoming })
        XCTAssertNil(outgoing.parent)
        XCTAssertNil(outgoing.retainedLazyListRuntime)
        XCTAssertEqual(ViewNode.maximumTraversalDepth, depthLimit)
        publication.evidence.assertLive()
        fixture.assertRootIsCurrent()
    }

    func testChangedMountedRuntimeRefusesCutWithoutWithdrawingNewMember() async throws {
        let original = CutBoundaryFixture()
        let destination = CutBoundaryFixture()
        let parent = ViewNode()
        original.runtime.root.addChild(parent)
        let outgoing = ViewNode()
        let incoming = ViewNode()
        parent.addChild(outgoing)
        var late: CutBoundaryPublication?
        var callbackError: Error?
        outgoing.onDismantlePlatformView = { departing in
            XCTAssertTrue(departing === outgoing)
            XCTAssertTrue(parent.children.isEmpty)
            parent.removeFromParent()
            XCTAssertNil(parent.retainedLazyListRuntime)
            destination.runtime.root.addChild(parent)
            XCTAssertTrue(parent.retainedLazyListRuntime === destination.runtime)
            do {
                let publication = try destination.acceptSource(identity: 1, parent: parent)
                late = publication
                publication.evidence.assertLive()
            } catch {
                callbackError = error
            }
        }
        defer { outgoing.onDismantlePlatformView = nil }

        let result = parent.setChildren([incoming])

        if let callbackError { throw callbackError }
        let publication = try XCTUnwrap(late)
        XCTAssertFalse(result.completed)
        XCTAssertTrue(result.didMutate)
        XCTAssertEqual(result.children.count, 1)
        XCTAssertTrue(result.children.first === publication.node)
        XCTAssertTrue(parent.parent === destination.runtime.root)
        XCTAssertTrue(parent.retainedLazyListRuntime === destination.runtime)
        XCTAssertTrue(parent.children.first === publication.node)
        XCTAssertFalse(parent.children.contains { $0 === incoming })
        XCTAssertNil(outgoing.parent)
        XCTAssertNil(outgoing.retainedLazyListRuntime)
        publication.evidence.assertLive()
        original.assertRootIsCurrent()
        destination.assertRootIsCurrent()
    }

    func testDetachedToMountedReentryRefusesCutWithoutWithdrawingNewMember() async throws {
        let destination = CutBoundaryFixture()
        let parent = ViewNode()
        let outgoing = ViewNode()
        let incoming = ViewNode()
        parent.addChild(outgoing)
        XCTAssertNil(parent.retainedLazyListRuntime)
        var late: CutBoundaryPublication?
        var callbackError: Error?
        outgoing.onDismantlePlatformView = { departing in
            XCTAssertTrue(departing === outgoing)
            XCTAssertTrue(parent.children.isEmpty)
            destination.runtime.root.addChild(parent)
            XCTAssertTrue(parent.retainedLazyListRuntime === destination.runtime)
            do {
                let publication = try destination.acceptSource(identity: 1, parent: parent)
                late = publication
                publication.evidence.assertLive()
            } catch {
                callbackError = error
            }
        }
        defer { outgoing.onDismantlePlatformView = nil }

        let result = parent.setChildren([incoming])

        if let callbackError { throw callbackError }
        let publication = try XCTUnwrap(late)
        XCTAssertFalse(result.completed)
        XCTAssertTrue(result.didMutate)
        XCTAssertEqual(result.children.count, 1)
        XCTAssertTrue(result.children.first === publication.node)
        XCTAssertTrue(parent.parent === destination.runtime.root)
        XCTAssertTrue(parent.retainedLazyListRuntime === destination.runtime)
        XCTAssertFalse(parent.children.contains { $0 === incoming })
        XCTAssertNil(outgoing.parent)
        XCTAssertNil(outgoing.retainedLazyListRuntime)
        publication.evidence.assertLive()
        destination.assertRootIsCurrent()
    }

    func testCoherentDetachedCutPreservesTheExistingNativeHolder() async throws {
        let parent = ViewNode()
        let outgoing = ViewNode()
        let incoming = ViewNode()
        let late = ViewNode()
        let storage = late.lazyListActivityStorage()
        let holder = try XCTUnwrap(late.captureOwnedPhysicalReferences(for: storage))
        let originalAttachment = storage.attachmentID
        parent.addChild(outgoing)
        var callbacks = 0
        outgoing.onDismantlePlatformView = { departing in
            callbacks += 1
            XCTAssertTrue(departing === outgoing)
            XCTAssertTrue(parent.children.isEmpty)
            parent.addChild(late)
            XCTAssertNil(parent.retainedLazyListRuntime)
            XCTAssertNil(late.retainedLazyListRuntime)
            XCTAssertTrue(holder.matches(storage))
            XCTAssertTrue(storage.attachmentID === originalAttachment)
        }
        defer { outgoing.onDismantlePlatformView = nil }

        let result = parent.setChildren([incoming])

        XCTAssertEqual(callbacks, 1)
        XCTAssertTrue(result.completed)
        XCTAssertTrue(result.didMutate)
        XCTAssertEqual(result.children.count, 1)
        XCTAssertTrue(result.children.first === incoming)
        XCTAssertTrue(incoming.parent === parent)
        XCTAssertNil(parent.retainedLazyListRuntime)
        XCTAssertNil(incoming.retainedLazyListRuntime)
        XCTAssertTrue(late.retainedLazyListActivityStorage === storage)
        XCTAssertTrue(holder.matches(storage))
        XCTAssertTrue(storage.attachmentID === originalAttachment)
    }

    func testNoOmittedMembersDoNotRefuseAfterRuntimeChange() async throws {
        let original = CutBoundaryFixture()
        let destination = CutBoundaryFixture()
        let parent = ViewNode()
        original.runtime.root.addChild(parent)
        let outgoing = ViewNode()
        let incoming = ViewNode()
        parent.addChild(outgoing)
        var callbacks = 0
        var accepted: CutBoundaryEvidence?
        var callbackError: Error?
        outgoing.onDismantlePlatformView = { departing in
            callbacks += 1
            XCTAssertTrue(departing === outgoing)
            XCTAssertTrue(parent.children.isEmpty)
            parent.removeFromParent()
            destination.runtime.root.addChild(parent)
            XCTAssertTrue(parent.children.isEmpty)
            XCTAssertTrue(parent.retainedLazyListRuntime === destination.runtime)
            do {
                let publication = try destination.acceptSource(identity: 1, parent: parent, node: incoming)
                accepted = publication.evidence
                XCTAssertEqual(parent.children.count, 1)
                XCTAssertTrue(parent.children.first === incoming)
                publication.evidence.assertLive()
            } catch {
                callbackError = error
            }
        }
        defer { outgoing.onDismantlePlatformView = nil }

        let result = parent.setChildren([incoming])

        if let callbackError { throw callbackError }
        let evidence = try XCTUnwrap(accepted)
        evidence.assertLive()
        XCTAssertEqual(callbacks, 1)
        XCTAssertTrue(result.completed)
        XCTAssertTrue(result.didMutate)
        XCTAssertEqual(result.children.count, 1)
        XCTAssertTrue(result.children.first === incoming)
        XCTAssertTrue(parent.children.first === incoming)
        XCTAssertTrue(parent.parent === destination.runtime.root)
        XCTAssertTrue(incoming.parent === parent)
        XCTAssertTrue(incoming.retainedLazyListRuntime === destination.runtime)
        XCTAssertNil(outgoing.parent)
        XCTAssertNil(outgoing.retainedLazyListRuntime)
        original.assertRootIsCurrent()
        destination.assertRootIsCurrent()
    }
}

// The same real normal-source insertion/completion sequence as Final6 and
// Raw3. No declaration-only, final-field or scope acknowledgement is invented.
@MainActor
private final class CutBoundaryFixture {
    let runtime: RetainedViewRuntime
    private let host: RetainedLazyListLogicalHostLifetime
    private let rootOwner: RetainedLazyListDescriptorOwnerLifetime
    private let rootActual: RetainedLazyListActualAttachment

    init() {
        let runtime = RetainedViewRuntime(root: ViewNode())
        self.runtime = runtime
        host = runtime.lazyListLogicalHostLifetime
        let storage = runtime.root.lazyListActivityStorage()
        rootOwner = storage.descriptorOwnerLifetime
        rootActual = storage.captureActualAttachment(of: runtime.root, in: runtime)
    }

    func acceptSource(
        identity: Int, parent: ViewNode, node suppliedNode: ViewNode? = nil,
        file: StaticString = #filePath, line: UInt = #line
    ) throws -> CutBoundaryPublication {
        assertRootIsCurrent(file: file, line: line)
        XCTAssertTrue(parent.retainedLazyListRuntime === runtime, file: file, line: line)
        let node = suppliedNode ?? ViewNode()
        XCTAssertNil(node.parent, file: file, line: line)
        XCTAssertNil(node.retainedLazyListRuntime, file: file, line: line)
        node.retainedViewIdentity = RetainedViewIdentity().appending(.slot(identity))
        let scope = RetainedLazyListDescriptorBuildScope(
            origin: .componentHostRoot, hostLifetime: host, ownerLifetime: rootOwner)
        let journal = RetainedLazyListAdoptionJournal(
            descriptorScope: scope, transaction: RetainedBuildTransaction())
        defer {
            journal.releaseUnadoptedTransport()
            scope.finish()
        }
        let attribution = try XCTUnwrap(scope.registerOrdinaryComponent(), file: file, line: line)
        let slot = RetainedOwnedSlotGenerationID()
        let owned = try XCTUnwrap(
            attribution.registerOwnedComponent(
                owner: RetainedOwnedComponentID(), slots: [slot], continuing: nil, declarationOnly: false),
            file: file, line: line)
        let group = try XCTUnwrap(attribution.registerGroup(kind: .observation), file: file, line: line)
        XCTAssertTrue(attribution.recordSourceOutput(node, group: group), file: file, line: line)
        _ = try XCTUnwrap(attribution.closeGroup(group), file: file, line: line)
        let contribution = try XCTUnwrap(attribution.contribution(for: group), file: file, line: line)
        let preparation = try XCTUnwrap(journal.preparation(), file: file, line: line)
        XCTAssertEqual(preparation.ownedComponentDeclarations.count, 1, file: file, line: line)
        let plan = try XCTUnwrap(
            preparation.ownedComponentDeclarations.first { $0.receipt === owned }, file: file, line: line)
        XCTAssertFalse(plan.declarationOnly, file: file, line: line)
        XCTAssertEqual(plan.sourcePayloads.count, 1, file: file, line: line)
        XCTAssertFalse(owned.hasAcceptedDeclaration, file: file, line: line)
        XCTAssertTrue(journal.beginOrdinaryAdoption(), file: file, line: line)
        XCTAssertTrue(journal.prepareInsertedNode(from: node), file: file, line: line)
        XCTAssertTrue(journal.markMutationStarted(), file: file, line: line)
        parent.addChild(node)
        XCTAssertTrue(node.parent === parent, file: file, line: line)
        XCTAssertTrue(node.retainedLazyListRuntime === runtime, file: file, line: line)
        _ = journal.recordAcceptedInsertedNode(on: node)
        _ = journal.recordCompletedNode(from: node, to: node)
        let disposition = journal.seal(completedCheckedAdoption: true)
        let facts = disposition.acceptedOwnedComponents
        XCTAssertEqual(facts.count, 2, file: file, line: line)
        let insertion = try XCTUnwrap(facts.first, file: file, line: line)
        let completion = try XCTUnwrap(facts.last, file: file, line: line)
        XCTAssertFalse(insertion.actual === completion.actual, file: file, line: line)
        let storage = node.lazyListActivityStorage()
        for fact in facts {
            XCTAssertTrue(fact.plan === plan, file: file, line: line)
            switch fact.kind {
            case .structuralEntry: break
            default: XCTFail("Expected a normal source publication", file: file, line: line)
            }
            let payload = try XCTUnwrap(fact.sourcePayload, file: file, line: line)
            XCTAssertTrue(plan.sourcePayloads.contains { $0 === payload }, file: file, line: line)
            XCTAssertTrue(fact.plan.receipt === owned, file: file, line: line)
            XCTAssertEqual(fact.slots.count, 1, file: file, line: line)
            XCTAssertTrue(fact.slots.first === slot, file: file, line: line)
            XCTAssertTrue(fact.actual.node === node, file: file, line: line)
            XCTAssertTrue(fact.actual.target === storage.targetID, file: file, line: line)
            XCTAssertTrue(fact.actual.attachment === storage.attachmentID, file: file, line: line)
            XCTAssertTrue(fact.actual.isAttached, file: file, line: line)
        }
        XCTAssertTrue(disposition.retiredOwnedSlots.isEmpty, file: file, line: line)
        XCTAssertTrue(disposition.retiredOwnedComponents.isEmpty, file: file, line: line)
        let evidence = CutBoundaryEvidence(owned: owned, actual: insertion.actual, contribution: contribution)
        evidence.assertLive(file: file, line: line)
        return CutBoundaryPublication(node: node, evidence: evidence)
    }

    func assertRootIsCurrent(file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(runtime.lazyListLogicalHostLifetime === host, file: file, line: line)
        XCTAssertTrue(host.isOpen, file: file, line: line)
        XCTAssertTrue(
            runtime.root.lazyListActivityStorage().descriptorOwnerLifetime === rootOwner, file: file, line: line)
        XCTAssertTrue(rootOwner.isCurrent, file: file, line: line)
        XCTAssertTrue(rootActual.isAttached, file: file, line: line)
    }
}

@MainActor
private struct CutBoundaryPublication {
    let node: ViewNode
    let evidence: CutBoundaryEvidence
}

// This escaped record retains only native receipts, never a source node.
@MainActor
private struct CutBoundaryEvidence {
    let owned: RetainedOwnedComponentReceipt
    let actual: RetainedLazyListActualAttachment
    let contribution: RetainedDescriptorContributionReceipt

    var ownershipWasWithdrawn: Bool {
        owned.hasAcceptedDeclaration && !owned.hasDeclaredComponent
            && owned.slots.allSatisfy {
                !owned.hasAcceptedOwnership(for: $0) && !owned.permitsOwnedWrite(for: $0)
            }
    }

    func assertLive(file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(actual.isAttached, file: file, line: line)
        XCTAssertTrue(contribution.isActive, file: file, line: line)
        XCTAssertTrue(owned.hasAcceptedDeclaration, file: file, line: line)
        XCTAssertTrue(owned.hasDeclaredComponent, file: file, line: line)
        for slot in owned.slots {
            XCTAssertTrue(owned.hasAcceptedOwnership(for: slot), file: file, line: line)
            XCTAssertTrue(owned.permitsOwnedWrite(for: slot), file: file, line: line)
        }
    }

    func assertWithdrawn(file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertFalse(actual.isAttached, file: file, line: line)
        XCTAssertFalse(contribution.isActive, file: file, line: line)
        XCTAssertTrue(owned.hasAcceptedDeclaration, file: file, line: line)
        XCTAssertFalse(owned.hasDeclaredComponent, file: file, line: line)
        for slot in owned.slots {
            XCTAssertFalse(owned.hasAcceptedOwnership(for: slot), file: file, line: line)
            XCTAssertFalse(owned.permitsOwnedWrite(for: slot), file: file, line: line)
        }
    }
}

@MainActor
private final class CutBoundaryReleases {
    weak var node: ViewNode?
    private weak var parent: ViewNode?
    private weak var incoming: ViewNode?
    var evidence: CutBoundaryEvidence?
    var events: [String] = []
    var count = 0
    var fieldWasRequestedAtRelease = false
    var ownershipWasWithdrawnAtRelease = false

    init(parent: ViewNode, incoming: ViewNode) {
        self.parent = parent
        self.incoming = incoming
    }

    func recordRelease() {
        count += 1
        events.append("payload-release")
        fieldWasRequestedAtRelease =
            incoming != nil && parent?.children.count == 1 && parent?.children.first === incoming
        ownershipWasWithdrawnAtRelease = evidence?.ownershipWasWithdrawn == true
    }
}

@MainActor
private final class CutBoundaryPayload {
    let releases: CutBoundaryReleases
    init(_ releases: CutBoundaryReleases) { self.releases = releases }
    isolated deinit { releases.recordRelease() }
}

@MainActor
@inline(never)
private func installCutBoundaryPayload(
    _ fixture: CutBoundaryFixture, parent: ViewNode, releases: CutBoundaryReleases
) throws {
    let payload = CutBoundaryPayload(releases)
    let node = ViewNode()
    node.platformViewCoordinator = payload
    let publication = try fixture.acceptSource(identity: 1, parent: parent, node: node)
    releases.node = node
    releases.evidence = publication.evidence
}
