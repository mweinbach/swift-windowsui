import SwiftWindowsCore
import XCTest

@testable import SwiftWindowsUI

@MainActor
final class RetainedButtonActionConstructionTests: XCTestCase {
    private typealias Source = RetainedLazyListDataSource<Int, [ViewNode]>
    private typealias Adapter = RetainedLazyListRuntimeAdapter

    func testRootFactoryCannotInvokeItsPendingButtonBeforePublication() async throws {
        let runtime = makeRuntime()
        let host = ComponentHost(runtime: runtime)
        var calls = 0
        var built: ViewNode?
        host.setComponents { [self] in
            [
                Component { constructionRuntime in
                    let node = self.button(in: constructionRuntime) { calls += 1 }
                    built = node
                    node.onActivate?()
                    return node
                }
            ]
        }

        let retained = try XCTUnwrap(built)
        XCTAssertEqual(calls, 0)
        XCTAssertTrue(runtime.root.children.first === retained)
        retained.onActivate?()
        XCTAssertEqual(calls, 1)
        XCTAssertNil(runtime.buttonActionConstruction)
    }

    func testUnusedRootConstructionIsRetiredEvenWhenItsNodeEscapes() async throws {
        let runtime = makeRuntime()
        let host = ComponentHost(runtime: runtime)
        var calls = 0
        var escaped: ViewNode?
        host.setComponents { [self] in
            let node = button(in: runtime) { calls += 1 }
            escaped = node
            node.onActivate?()
            return []
        }

        let node = try XCTUnwrap(escaped)
        XCTAssertTrue(node.buttonActionOwner?.isRetired == true)
        runtime.root.addChild(node)
        node.onActivate?()
        XCTAssertEqual(calls, 0)
        XCTAssertNil(runtime.buttonActionConstruction)
    }

    func testCasualInsertionDoesNotAuthorizeAConstructingSource() async {
        let runtime = makeRuntime()
        let construction = RetainedButtonActionConstruction(runtime: runtime)
        var calls = 0
        let node = button(in: runtime) { calls += 1 }

        runtime.root.addChild(node)
        node.onActivate?()
        construction.finish()
        node.onActivate?()

        XCTAssertEqual(calls, 0)
        XCTAssertTrue(node.buttonActionOwner?.isRetired == true)
        XCTAssertNil(runtime.buttonActionConstruction)
    }

    func testEarlyThrowBalancesConstructionAndRetiresEscapedSource() async throws {
        let runtime = makeRuntime()
        var escaped: ViewNode?
        var calls = 0
        do {
            try withThrowingConstruction(runtime) { [self] in
                escaped = button(in: runtime) { calls += 1 }
                throw ConstructionFailure.stopped
            }
            XCTFail("The test constructor must throw")
        } catch ConstructionFailure.stopped {}

        let node = try XCTUnwrap(escaped)
        node.onActivate?()
        runtime.root.addChild(node)
        node.onActivate?()
        XCTAssertEqual(calls, 0)
        XCTAssertTrue(node.buttonActionOwner?.isRetired == true)
        XCTAssertNil(runtime.buttonActionConstruction)
    }

    func testNestedRejectedConstructionDoesNotConsumeItsOuterFrame() async {
        let runtime = makeRuntime()
        var calls: [String] = []
        let outer = RetainedButtonActionConstruction(runtime: runtime)
        let outerNode = button(in: runtime) { calls.append("outer") }
        let inner = RetainedButtonActionConstruction(runtime: runtime)
        let innerNode = button(in: runtime, tag: "inner") { calls.append("inner") }

        inner.finish()
        XCTAssertTrue(runtime.buttonActionConstruction === outer)
        XCTAssertTrue(
            ComponentHost.reconcileChildren(of: runtime.root, oldChildren: [], newNodes: [outerNode]).completed)
        outer.finish()
        outerNode.onActivate?()
        innerNode.onActivate?()

        XCTAssertEqual(calls, ["outer"])
        XCTAssertNil(runtime.buttonActionConstruction)
    }

    func testConstructionFramesAreIsolatedBetweenRuntimes() async {
        let firstRuntime = makeRuntime()
        let secondRuntime = makeRuntime()
        let construction = RetainedButtonActionConstruction(runtime: firstRuntime)
        var calls: [String] = []
        let pending = button(in: firstRuntime) { calls.append("first") }
        let standalone = button(in: secondRuntime) { calls.append("second") }

        pending.onActivate?()
        standalone.onActivate?()
        construction.finish()

        XCTAssertEqual(calls, ["second"])
        XCTAssertNil(firstRuntime.buttonActionConstruction)
        XCTAssertNil(secondRuntime.buttonActionConstruction)
    }

    func testAcceptedChildDeclarationSurvivesOuterConstructionCleanup() async {
        let runtime = makeRuntime()
        let outer = RetainedButtonActionConstruction(runtime: runtime)
        let inner = RetainedButtonActionConstruction(runtime: runtime)
        var calls = 0
        let node = button(in: runtime) { calls += 1 }

        XCTAssertTrue(ComponentHost.reconcileChildren(of: runtime.root, oldChildren: [], newNodes: [node]).completed)
        inner.finish()
        outer.finish()
        node.onActivate?()

        XCTAssertEqual(calls, 1)
        XCTAssertFalse(node.buttonActionOwner?.isRetired == true)
    }

    func testLazyFactoryThatRejectsBeforeCandidateRetiresAnUnreturnedButton() async throws {
        let runtime = makeRuntime()
        let source = Source()
        var escaped: ViewNode?
        var calls = 0
        XCTAssertTrue(
            source.replaceData([0], id: \.self) { [self, weak source] _ in
                let node = button(in: runtime) { calls += 1 }
                escaped = node
                node.onActivate?()
                source?.close()
                return []
            })
        let adapter = try adapter(source, runtime: runtime)

        guard case .obsolete = adapter.prepare(viewport: try viewport(), protectedRoots: [], budget: try budget())
        else {
            return XCTFail("The closed provider must reject before yielding a Candidate")
        }

        let node = try XCTUnwrap(escaped)
        node.onActivate?()
        runtime.root.addChild(node)
        node.onActivate?()
        XCTAssertEqual(calls, 0)
        XCTAssertTrue(node.buttonActionOwner?.isRetired == true)
        XCTAssertNil(runtime.buttonActionConstruction)
    }

    func testRowOneBuiltThenRowTwoRejectedRetiresWholePendingBatch() async throws {
        let runtime = makeRuntime()
        let source = Source()
        var escaped: ViewNode?
        var factories: [Int] = []
        var calls = 0
        XCTAssertTrue(
            source.replaceData([0, 1], id: \.self) { [self, weak source] value in
                factories.append(value)
                if value == 1 {
                    source?.close()
                    return []
                }
                let node = button(in: runtime) { calls += 1 }
                escaped = node
                return [node]
            })
        let adapter = try adapter(source, runtime: runtime)

        guard
            case .obsolete = adapter.prepare(
                viewport: try viewport(extent: 40), protectedRoots: [], budget: try budget())
        else { return XCTFail("A later row rejection must abandon the earlier constructed row") }

        let node = try XCTUnwrap(escaped)
        XCTAssertEqual(factories, [0, 1])
        XCTAssertTrue(node.buttonActionOwner?.isRetired == true)
        XCTAssertFalse(
            ComponentHost.reconcileChildren(of: runtime.root, oldChildren: [], newNodes: [node]).completed)
        runtime.root.addChild(node)
        node.onActivate?()
        XCTAssertEqual(calls, 0)
    }

    func testDiscardedCandidateCannotLaterBeInsertedAsAnAuthorizedButton() async throws {
        let runtime = makeRuntime()
        let source = Source()
        var calls = 0
        XCTAssertTrue(
            source.replaceData([0], id: \.self) { [self] _ in
                [button(in: runtime) { calls += 1 }]
            })
        let adapter = try adapter(source, runtime: runtime)
        let candidate = try ready(adapter)
        let node = try XCTUnwrap(candidate.children.first)
        let saved = node.onActivate

        candidate.discardBuiltContent()
        runtime.root.addChild(node)
        saved?()
        node.onActivate?()

        XCTAssertTrue(candidate.children.isEmpty)
        XCTAssertTrue(node.buttonActionOwner?.isRetired == true)
        XCTAssertEqual(calls, 0)
    }

    func testDroppingCandidatePermissionCannotBeReplacedByLaterPhysicalAttachment() async throws {
        let runtime = makeRuntime()
        let source = Source()
        var calls = 0
        XCTAssertTrue(
            source.replaceData([0], id: \.self) { [self] _ in
                [button(in: runtime) { calls += 1 }]
            })
        let adapter = try adapter(source, runtime: runtime)
        var candidate: Adapter.Candidate? = try ready(adapter)
        let node = try XCTUnwrap(candidate?.children.first)
        let saved = node.onActivate
        candidate = nil

        XCTAssertFalse(
            ComponentHost.reconcileChildren(of: runtime.root, oldChildren: [], newNodes: [node]).completed)
        runtime.root.addChild(node)
        saved?()
        XCTAssertEqual(calls, 0)
    }

    func testCandidateDiscardPreservesAnAcceptedTransferredDeclaration() async throws {
        let runtime = makeRuntime()
        var calls: [String] = []
        let retained = button(in: runtime) { calls.append("old") }
        runtime.root.addChild(retained)
        let savedOld = retained.onActivate
        let source = Source()
        XCTAssertTrue(
            source.replaceData([0], id: \.self) { [self] _ in
                [button(in: runtime) { calls.append("new") }]
            })
        let adapter = try adapter(source, runtime: runtime)
        let candidate = try ready(adapter)
        let fresh = try XCTUnwrap(candidate.children.first)
        let result = ComponentHost.reconcileChildren(
            of: runtime.root, oldChildren: runtime.root.children, newNodes: candidate.children)
        XCTAssertTrue(result.completed)

        candidate.discardBuiltContent()
        savedOld?()
        retained.onActivate?()

        XCTAssertTrue(runtime.root.children.first === retained)
        XCTAssertNil(fresh.buttonActionOwner)
        XCTAssertEqual(calls, ["new"])
    }

    func testAcceptedDeclarationSurvivesCandidateReleaseAndLaterProviderClose() async throws {
        let runtime = makeRuntime()
        var calls: [String] = []
        let retained = button(in: runtime) { calls.append("old") }
        runtime.root.addChild(retained)
        let savedOld = retained.onActivate
        let source = Source()
        XCTAssertTrue(
            source.replaceData([0], id: \.self) { [self] _ in
                [button(in: runtime) { calls.append("new") }]
            })
        let adapter = try adapter(source, runtime: runtime)
        var candidate: Adapter.Candidate? = try ready(adapter)
        weak var observedCandidate = candidate
        let nodes = try XCTUnwrap(candidate?.children)
        let fresh = try XCTUnwrap(nodes.first)
        XCTAssertTrue(
            ComponentHost.reconcileChildren(
                of: runtime.root, oldChildren: runtime.root.children, newNodes: nodes
            ).completed)

        candidate = nil
        source.close()

        XCTAssertNil(observedCandidate)
        XCTAssertNil(fresh.buttonActionOwner)
        XCTAssertTrue(runtime.root.children.first === retained)
        savedOld?()
        retained.onActivate?()
        XCTAssertEqual(calls, ["new"])
    }

    func testDiscardingNewLazyPrefixDoesNotRetireASurvivingAcceptedRow() async throws {
        let runtime = makeRuntime()
        let source = Source()
        var calls: [Int] = []
        XCTAssertTrue(
            source.replaceData([0, 1], id: \.self) { [self] value in
                [button(in: runtime, tag: "row \(value)") { calls.append(value) }]
            })
        let adapter = try adapter(source, runtime: runtime)
        let first = try ready(adapter)
        XCTAssertTrue(
            ComponentHost.reconcileChildren(of: runtime.root, oldChildren: [], newNodes: first.children).completed)
        XCTAssertTrue(adapter.complete(candidate: first, adoptedChildren: runtime.root.children))
        first.discardBuiltContent()
        let old = try XCTUnwrap(runtime.root.children.first)
        let second = try ready(adapter, extent: 40)
        XCTAssertTrue(second.children.contains(where: { $0 === old }))
        let pending = try XCTUnwrap(second.children.first(where: { $0 !== old }))

        second.discardBuiltContent()
        old.onActivate?()
        pending.onActivate?()

        XCTAssertEqual(calls, [0])
        XCTAssertFalse(old.buttonActionOwner?.isRetired == true)
        XCTAssertTrue(pending.buttonActionOwner?.isRetired == true)
    }

    func testEmptyCandidateCleanupDoesNotRevokeAnUnrelatedLiveControl() async throws {
        let runtime = makeRuntime()
        var calls = 0
        let outside = button(in: runtime) { calls += 1 }
        runtime.root.addChild(outside)
        let source = Source()
        XCTAssertTrue(source.replaceData([0], id: \.self) { _ in [] })
        let adapter = try adapter(source, runtime: runtime)
        let candidate = try ready(adapter)
        XCTAssertTrue(candidate.children.isEmpty)

        candidate.discardBuiltContent()
        outside.onActivate?()

        XCTAssertEqual(calls, 1)
    }

    func testPendingReplacementStaysClosedDuringPlatformUpdateCallback() async {
        let runtime = makeRuntime()
        var calls: [String] = []
        let retained = button(in: runtime) { calls.append("old") }
        runtime.root.addChild(retained)
        let incoming = button(in: runtime) { calls.append("new") }
        var updates = 0
        incoming.onUpdatePlatformView = { node in
            updates += 1
            node.onActivate?()
        }

        XCTAssertTrue(ComponentHost.adopt(source: incoming, into: retained).completed)
        XCTAssertEqual(updates, 1)
        XCTAssertTrue(calls.isEmpty)
        retained.onActivate?()
        XCTAssertEqual(calls, ["new"])
    }

    func testUnmanagedGeometryBodyWithNoResultRetiresItsEscapedButton() async throws {
        let runtime = makeRuntime()
        let reader = ViewNode(frame: Rect(x: 0, y: 0, width: 120, height: 60))
        var escaped: ViewNode?
        var calls = 0
        var builds = 0
        reader.geometryReaderBuild = { [self] constructionRuntime, _ in
            builds += 1
            let node = button(in: constructionRuntime) { calls += 1 }
            escaped = node
            node.onActivate?()
            return []
        }
        runtime.root.addChild(reader)

        _ = runtime.renderFrame()

        XCTAssertGreaterThan(builds, 0)
        let node = try XCTUnwrap(escaped)
        node.onActivate?()
        XCTAssertEqual(calls, 0)
        XCTAssertTrue(node.buttonActionOwner?.isRetired == true)
        XCTAssertNil(runtime.buttonActionConstruction)
    }

    func testDroppingCandidateReleasesItsPayloadWhileTheSourceNodeRemainsAlive() async throws {
        let runtime = makeRuntime()
        let source = Source()
        var releases = 0
        var calls = 0
        weak var weakProbe: ButtonConstructionReleaseProbe?
        XCTAssertTrue(
            source.replaceData([0], id: \.self) { [self] _ in
                let probe = ButtonConstructionReleaseProbe { releases += 1 }
                weakProbe = probe
                return [
                    button(in: runtime) { [probe] in
                        withExtendedLifetime(probe) { calls += 1 }
                    }
                ]
            })
        let adapter = try adapter(source, runtime: runtime)
        var candidate: Adapter.Candidate? = try ready(adapter)
        let node = try XCTUnwrap(candidate?.children.first)
        let saved = node.onActivate
        XCTAssertNotNil(weakProbe)

        candidate = nil

        XCTAssertNil(weakProbe)
        XCTAssertEqual(releases, 1)
        XCTAssertTrue(node.buttonActionOwner?.isRetired == true)
        runtime.root.addChild(node)
        saved?()
        XCTAssertEqual(calls, 0)
        XCTAssertNil(runtime.buttonActionConstruction)
    }

    func testConstructionFinishKeepsDestructorCreatedButtonsUncallable() async throws {
        let runtime = makeRuntime()
        let construction = RetainedButtonActionConstruction(runtime: runtime)
        var escaped: ViewNode?
        var calls = 0
        var releases = 0
        let rejected = buttonWithRelease(in: runtime) { [self] in
            releases += 1
            let late = button(in: runtime) { calls += 1 }
            escaped = late
            late.onActivate?()
        }

        construction.finish()

        let late = try XCTUnwrap(escaped)
        XCTAssertEqual(releases, 1)
        XCTAssertTrue(rejected.buttonActionOwner?.isRetired == true)
        XCTAssertTrue(late.buttonActionOwner?.isRetired == true)
        XCTAssertEqual(calls, 0)
        runtime.root.addChild(late)
        late.onActivate?()
        XCTAssertEqual(calls, 0)
        XCTAssertNil(runtime.buttonActionConstruction)
    }

    func testKeepingCandidateSourcesClosesOnlyTheRejectedCleanupTail() async throws {
        let runtime = makeRuntime()
        let construction = RetainedButtonActionConstruction(runtime: runtime)
        var calls: [String] = []
        let selected = button(in: runtime) { calls.append("selected") }
        var escaped: ViewNode?
        let rejected = buttonWithRelease(in: runtime) { [self] in
            let late = button(in: runtime) { calls.append("late") }
            escaped = late
            late.onActivate?()
        }

        construction.keepPendingSources(in: [selected])

        let late = try XCTUnwrap(escaped)
        XCTAssertTrue(rejected.buttonActionOwner?.isRetired == true)
        XCTAssertTrue(late.buttonActionOwner?.isRetired == true)
        XCTAssertTrue(calls.isEmpty)
        XCTAssertTrue(
            ComponentHost.reconcileChildren(of: runtime.root, oldChildren: [], newNodes: [selected]).completed)
        construction.finish()
        selected.onActivate?()
        late.onActivate?()
        XCTAssertEqual(calls, ["selected"])
        XCTAssertNil(runtime.buttonActionConstruction)
    }

    func testSelectiveAdoptionPayloadCleanupCannotCreateAnIdleStandaloneButton() async throws {
        let runtime = makeRuntime()
        var releases = 0
        var calls: [String] = []
        var escaped: ViewNode?
        let retained = buttonWithRelease(in: runtime) { [self] in
            releases += 1
            let late = button(in: runtime) { calls.append("late") }
            escaped = late
            late.onActivate?()
        }
        runtime.root.addChild(retained)
        let source = button(in: runtime) { calls.append("accepted") }
        XCTAssertNil(runtime.buttonActionConstruction)

        let result = ComponentHost.adopt(source: source, into: retained)

        XCTAssertTrue(result.completed)
        XCTAssertEqual(releases, 1)
        let late = try XCTUnwrap(escaped)
        XCTAssertTrue(late.buttonActionOwner?.isRetired == true)
        late.onActivate?()
        retained.onActivate?()
        XCTAssertEqual(calls, ["accepted"])
        XCTAssertNil(runtime.buttonActionConstruction)
    }

    func testDroppedNestedCandidateDoesNotConsumeAnOuterPendingConstruction() async throws {
        let runtime = makeRuntime()
        let outer = RetainedButtonActionConstruction(runtime: runtime)
        var calls: [String] = []
        let outerNode = button(in: runtime) { calls.append("outer") }
        let source = Source()
        var releases = 0
        XCTAssertTrue(
            source.replaceData([0], id: \.self) { [self] _ in
                [buttonWithRelease(in: runtime) { releases += 1 }]
            })
        let adapter = try adapter(source, runtime: runtime)
        var candidate: Adapter.Candidate? = try ready(adapter)
        let abandoned = try XCTUnwrap(candidate?.children.first)

        candidate = nil

        XCTAssertEqual(releases, 1)
        XCTAssertTrue(abandoned.buttonActionOwner?.isRetired == true)
        XCTAssertTrue(runtime.buttonActionConstruction === outer)
        XCTAssertTrue(
            ComponentHost.reconcileChildren(of: runtime.root, oldChildren: [], newNodes: [outerNode]).completed)
        outer.finish()
        outerNode.onActivate?()
        XCTAssertEqual(calls, ["outer"])
        XCTAssertNil(runtime.buttonActionConstruction)
    }

    func testDroppingOuterCandidateRetiresItWhileAnInnerCandidateKeepsItsFrameAlive() async throws {
        let runtime = makeRuntime()
        let innerParent = ViewNode()
        runtime.root.addChild(innerParent)
        let innerSource = Source()
        var releases: [String] = []
        var calls: [String] = []
        weak var outerPayload: ButtonConstructionReleaseProbe?
        weak var innerPayload: ButtonConstructionReleaseProbe?
        XCTAssertTrue(
            innerSource.replaceData([0], id: \.self) { [self] _ in
                let payload = ButtonConstructionReleaseProbe { releases.append("inner") }
                innerPayload = payload
                return [button(in: runtime) { [payload] in withExtendedLifetime(payload) { calls.append("inner") } }]
            })
        let innerAdapter = try XCTUnwrap(
            Adapter(
                provider: innerSource, estimatedExtent: 20, prefetchExtent: 0,
                maximumMountedRecords: 8, maximumMountedLeaves: 8, maximumProtectedRecords: 2))
        XCTAssertTrue(innerAdapter.claimAttachment(to: innerParent))
        var innerCandidate: Adapter.Candidate?
        var nestedError: Error?
        let outerSource = Source()
        XCTAssertTrue(
            outerSource.replaceData([0], id: \.self) { [self] _ in
                do { innerCandidate = try ready(innerAdapter) } catch { nestedError = error }
                let payload = ButtonConstructionReleaseProbe { releases.append("outer") }
                outerPayload = payload
                return [button(in: runtime) { [payload] in withExtendedLifetime(payload) { calls.append("outer") } }]
            })
        let outerAdapter = try adapter(outerSource, runtime: runtime)
        var outerCandidate: Adapter.Candidate? = try ready(outerAdapter)
        XCTAssertNil(nestedError)
        let heldInnerCandidate = try XCTUnwrap(innerCandidate)
        let outerNode = try XCTUnwrap(outerCandidate?.children.first)
        let saved = outerNode.onActivate
        XCTAssertNotNil(outerPayload)
        XCTAssertNotNil(innerPayload)

        outerCandidate = nil

        XCTAssertEqual(releases, ["outer"])
        XCTAssertNil(outerPayload)
        XCTAssertNotNil(innerPayload)
        XCTAssertTrue(outerNode.buttonActionOwner?.isRetired == true)
        XCTAssertFalse(ComponentHost.adopt(source: outerNode, into: ViewNode()).completed)
        saved?()
        XCTAssertTrue(calls.isEmpty)
        XCTAssertNil(runtime.buttonActionConstruction)
        heldInnerCandidate.discardBuiltContent()
        XCTAssertEqual(Set(releases), Set(["outer", "inner"]))
        XCTAssertEqual(releases.count, 2)
        XCTAssertNil(innerPayload)
    }

    func testCandidateDropRevokesHeldAndUnheldSourcesBeforeTheirFieldsAreReleased() async throws {
        let runtime = makeRuntime()
        let source = Source()
        var frame: RetainedButtonActionConstruction?
        var heldNode: ViewNode?
        weak var unheldNode: ViewNode?
        weak var heldOwner: RetainedButtonActionOwner?
        weak var unheldOwner: RetainedButtonActionOwner?
        var releases: [Int] = []
        var nativeStatesAtRelease: [Bool] = []
        var calls = 0
        var escaped: [() -> Void] = []
        XCTAssertTrue(
            source.replaceData([0], id: \.self) { [self] _ in
                frame = runtime.buttonActionConstruction
                var nodes: [ViewNode] = []
                for index in 0..<2 {
                    let payload = ButtonConstructionReleaseProbe {
                        releases.append(index)
                        nativeStatesAtRelease.append(heldOwner?.isRetired == true && unheldOwner?.isRetired == true)
                        for action in escaped { action() }
                    }
                    let node = button(in: runtime) { [payload] in withExtendedLifetime(payload) { calls += 1 } }
                    if index == 0 {
                        heldNode = node
                        heldOwner = node.buttonActionOwner
                    } else {
                        unheldNode = node
                        unheldOwner = node.buttonActionOwner
                    }
                    if let action = node.onActivate { escaped.append(action) }
                    nodes.append(node)
                }
                return nodes
            })
        let adapter = try adapter(source, runtime: runtime)
        var candidate: Adapter.Candidate? = try ready(adapter)
        XCTAssertNotNil(frame)
        XCTAssertNotNil(unheldNode)
        XCTAssertEqual(candidate?.recordLeafCounts, [2])

        candidate = nil

        XCTAssertEqual(Set(releases), Set([0, 1]))
        XCTAssertEqual(releases.count, 2)
        XCTAssertEqual(nativeStatesAtRelease, [true, true])
        XCTAssertEqual(calls, 0)
        XCTAssertNotNil(heldNode)
        XCTAssertNil(unheldNode)
        XCTAssertTrue(heldOwner?.isRetired == true)
        frame = nil
        XCTAssertNil(runtime.buttonActionConstruction)
    }

    func testClosedConstructionCannotEnrollAndRetireAnAlreadyAcceptedOwner() async {
        let runtime = makeRuntime()
        var calls = 0
        let accepted = button(in: runtime) { calls += 1 }
        runtime.root.addChild(accepted)
        let construction = RetainedButtonActionConstruction(runtime: runtime)
        let cleanup = construction.closedCleanupFrame()

        cleanup.registerSources(in: [accepted])
        cleanup.finish()
        construction.finish()

        XCTAssertFalse(accepted.buttonActionOwner?.isRetired == true)
        accepted.onActivate?()
        XCTAssertEqual(calls, 1)
        XCTAssertNil(runtime.buttonActionConstruction)
    }

    func testDetachedWrapperDoesNotPreventItsButtonFromEnteringACandidate() async throws {
        let runtime = makeRuntime()
        var calls = 0
        let wrapper = ViewNode()
        let node = button(in: runtime) { calls += 1 }
        wrapper.addChild(node)
        let saved = node.onActivate
        saved?()
        XCTAssertEqual(calls, 1)
        let source = Source()
        XCTAssertTrue(source.replaceData([0], id: \.self) { _ in [wrapper] })
        let adapter = try adapter(source, runtime: runtime)
        let candidate = try ready(adapter)
        saved?()
        XCTAssertEqual(calls, 1)

        candidate.discardBuiltContent()

        XCTAssertTrue(node.buttonActionOwner?.isRetired == true)
        runtime.root.addChild(wrapper)
        saved?()
        XCTAssertEqual(calls, 1)
    }

    func testCandidateFieldCleanupKeepsDestructorCreatedButtonsUncallable() async throws {
        let runtime = makeRuntime()
        let source = Source()
        var releases = 0
        var calls = 0
        var escaped: ViewNode?
        XCTAssertTrue(
            source.replaceData([0], id: \.self) { [self] _ in
                let node = ViewNode()
                let payload = ButtonConstructionReleaseProbe {
                    releases += 1
                    let late = self.button(in: runtime) { calls += 1 }
                    escaped = late
                    late.onActivate?()
                }
                node.onUpdatePlatformView = { [payload] _ in withExtendedLifetime(payload) {} }
                return [node]
            })
        let adapter = try adapter(source, runtime: runtime)
        var candidate: Adapter.Candidate? = try ready(adapter)
        XCTAssertEqual(candidate?.children.count, 1)

        candidate = nil

        XCTAssertEqual(releases, 1)
        let late = try XCTUnwrap(escaped)
        XCTAssertTrue(late.buttonActionOwner?.isRetired == true)
        late.onActivate?()
        XCTAssertEqual(calls, 0)
        XCTAssertNil(runtime.buttonActionConstruction)
    }

    func testCleanupFrameDoesNotRestoreAPredecessorThatFinishedWhileItWasActive() async {
        let runtime = makeRuntime()
        let original = RetainedButtonActionConstruction(runtime: runtime)
        let cleanup = original.closedCleanupFrame()

        original.finish()

        XCTAssertTrue(runtime.buttonActionConstruction === cleanup)
        cleanup.finish()
        XCTAssertNil(runtime.buttonActionConstruction)
    }

    func testClosedNestedConstructionCannotRetireAnOuterPendingSource() async {
        let runtime = makeRuntime()
        let outer = RetainedButtonActionConstruction(runtime: runtime)
        var calls = 0
        let pending = button(in: runtime) { calls += 1 }
        let cleanup = outer.closedCleanupFrame()

        cleanup.registerSources(in: [pending])
        cleanup.finish()

        XCTAssertFalse(pending.buttonActionOwner?.isRetired == true)
        XCTAssertTrue(runtime.buttonActionConstruction === outer)
        XCTAssertTrue(
            ComponentHost.reconcileChildren(of: runtime.root, oldChildren: [], newNodes: [pending]).completed)
        outer.finish()
        pending.onActivate?()
        XCTAssertEqual(calls, 1)
        XCTAssertNil(runtime.buttonActionConstruction)
    }

    func testHeldCandidateWithRevokedProviderCannotAuthorizeItsEscapedSource() async throws {
        let runtime = makeRuntime()
        let source = Source()
        var calls = 0
        XCTAssertTrue(
            source.replaceData([0], id: \.self) { [self] _ in
                [button(in: runtime) { calls += 1 }]
            })
        let adapter = try adapter(source, runtime: runtime)
        let candidate = try ready(adapter)
        let node = try XCTUnwrap(candidate.children.first)
        let saved = node.onActivate

        source.close()

        XCTAssertFalse(candidate.isCurrent)
        XCTAssertFalse(ComponentHost.adopt(source: node, into: ViewNode()).completed)
        runtime.root.addChild(node)
        saved?()
        XCTAssertEqual(calls, 0)
        candidate.discardBuiltContent()
        XCTAssertTrue(node.buttonActionOwner?.isRetired == true)
    }

    // Attachment receipts must reject callback mutations while preserving
    // ordinary, fully accepted transfer through the same callout boundaries.
    func testTemporaryParentDismantleCannotRestoreAnUnpublishedDescendantAttachment() async {
        let runtime = makeRuntime()
        let temporary = ViewNode()
        let incoming = ViewNode()
        var calls = 0
        var dismantles = 0
        let pending = button(in: runtime) { calls += 1 }
        let saved = pending.onActivate
        incoming.addChild(pending)
        temporary.addChild(incoming)
        incoming.onDismantlePlatformView = { _ in
            dismantles += 1
            pending.removeFromParent()
            incoming.addChild(pending)
        }
        defer { incoming.onDismantlePlatformView = nil }

        let result = ComponentHost.reconcileChildren(of: runtime.root, oldChildren: [], newNodes: [incoming])

        XCTAssertEqual(dismantles, 1)
        XCTAssertFalse(result.completed)
        XCTAssertTrue(pending.buttonActionOwner?.isRetired == true)
        saved?()
        XCTAssertEqual(calls, 0)
    }

    func testControllerAttachCannotRestoreAnUnpublishedDescendantAttachment() async {
        let runtime = makeRuntime()
        let incoming = ViewNode()
        var calls = 0
        let pending = button(in: runtime) { calls += 1 }
        let saved = pending.onActivate
        incoming.addChild(pending)
        let controller = ButtonConstructionAttachmentController()
        incoming.textInputController = controller
        controller.onAttach = {
            pending.removeFromParent()
            incoming.addChild(pending)
        }

        let result = ComponentHost.reconcileChildren(of: runtime.root, oldChildren: [], newNodes: [incoming])

        XCTAssertEqual(controller.attachCalls, 1)
        XCTAssertFalse(result.completed)
        XCTAssertTrue(pending.buttonActionOwner?.isRetired == true)
        saved?()
        XCTAssertEqual(calls, 0)
    }

    func testTemporaryParentCallbackCannotHaveItsNewParentTableOverwrittenByStaleInsertion() async {
        let runtime = makeRuntime()
        let temporary = ViewNode()
        let incoming = ViewNode()
        var calls = 0
        let pending = button(in: runtime) { calls += 1 }
        incoming.addChild(pending)
        temporary.addChild(incoming)
        let interloper = ViewNode()
        incoming.onDismantlePlatformView = { _ in runtime.root.addChild(interloper) }
        defer { incoming.onDismantlePlatformView = nil }

        let result = ComponentHost.reconcileChildren(of: runtime.root, oldChildren: [], newNodes: [incoming])

        XCTAssertFalse(result.completed)
        XCTAssertEqual(runtime.root.children.count, 1)
        XCTAssertTrue(runtime.root.children.first === interloper)
        pending.onActivate?()
        XCTAssertEqual(calls, 0)
    }

    func testTemporaryParentAndControllerCallbacksKeepActionClosedUntilSuccessfulInsertion() async {
        let runtime = makeRuntime()
        let temporary = ViewNode()
        let incoming = ViewNode()
        var events: [String] = []
        let pending = button(in: runtime) { events.append("action") }
        let saved = pending.onActivate
        incoming.addChild(pending)
        temporary.addChild(incoming)
        incoming.onDismantlePlatformView = { _ in
            events.append("dismantle")
            saved?()
        }
        defer { incoming.onDismantlePlatformView = nil }
        let controller = ButtonConstructionAttachmentController()
        incoming.textInputController = controller
        controller.onAttach = {
            events.append("attach")
            saved?()
        }

        let result = ComponentHost.reconcileChildren(of: runtime.root, oldChildren: [], newNodes: [incoming])

        XCTAssertTrue(result.completed)
        XCTAssertEqual(events, ["dismantle", "attach"])
        XCTAssertEqual(controller.attachCalls, 1)
        XCTAssertTrue(temporary.children.isEmpty)
        XCTAssertTrue(runtime.root.children.first === incoming)
        XCTAssertTrue(incoming.parent === runtime.root)
        XCTAssertTrue(pending.parent === incoming)
        XCTAssertTrue(pending.isRetainedLazyListAttached(in: runtime))
        saved?()
        pending.onActivate?()
        XCTAssertEqual(events, ["dismantle", "attach", "action", "action"])
    }

    func testTemporaryAncestorAttachmentABACannotAuthorizePendingInsertion() async {
        let runtime = makeRuntime()
        let ancestor = ViewNode()
        let temporary = ViewNode()
        let incoming = ViewNode()
        ancestor.addChild(temporary)
        var calls = 0
        var dismantles = 0
        let pending = button(in: runtime) { calls += 1 }
        let saved = pending.onActivate
        incoming.addChild(pending)
        temporary.addChild(incoming)
        incoming.onDismantlePlatformView = { _ in
            dismantles += 1
            temporary.removeFromParent()
            ancestor.addChild(temporary)
        }
        defer { incoming.onDismantlePlatformView = nil }

        let result = ComponentHost.reconcileChildren(of: runtime.root, oldChildren: [], newNodes: [incoming])

        XCTAssertEqual(dismantles, 1)
        XCTAssertFalse(result.completed)
        XCTAssertTrue(runtime.root.children.isEmpty)
        XCTAssertTrue(temporary.parent === ancestor)
        XCTAssertTrue(pending.buttonActionOwner?.isRetired == true)
        saved?()
        XCTAssertEqual(calls, 0)
    }

    func testScheduledDepartureKeepsIdentityProofDuringLaterBranchMatching() async {
        let runtime = makeRuntime()
        var calls = 0
        let retained = button(in: runtime) { calls += 1 }
        runtime.root.addChild(retained)
        let saved = retained.onActivate
        let presenter = retained.beginFileDialogPresentation(kind: .exporter)
        XCTAssertTrue(presenter.isValid)
        let originalIdentity = retained.retainedViewIdentity
        let probe = ButtonConstructionDepartureProbe()
        probe.shouldRun = { !presenter.isValid }
        probe.action = { retained.retainedViewIdentity = originalIdentity }
        let oldBranch = ViewNode()
        let newBranch = ViewNode()
        let branchIdentity = RetainedViewIdentity(segments: [.keyed(.init("surviving branch"))])
        oldBranch.retainedViewIdentity = branchIdentity
        newBranch.retainedViewIdentity = branchIdentity
        let oldLeaf = ViewNode()
        let newLeaf = ViewNode()
        oldLeaf.retainedViewIdentity = RetainedViewIdentity(
            segments: [.keyed(.init(ButtonConstructionDepartureKey(probe: probe)))])
        newLeaf.retainedViewIdentity = RetainedViewIdentity(
            segments: [.keyed(.init(ButtonConstructionDepartureKey(probe: probe)))])
        oldBranch.addChild(oldLeaf)
        newBranch.addChild(newLeaf)
        runtime.root.addChild(oldBranch)

        let result = ComponentHost.reconcileChildren(
            of: runtime.root, oldChildren: runtime.root.children, newNodes: [newBranch])

        XCTAssertEqual(probe.calls, 1)
        XCTAssertFalse(result.completed)
        XCTAssertEqual(runtime.root.children.count, 2)
        XCTAssertTrue(runtime.root.children.first === retained)
        XCTAssertFalse(retained.buttonActionOwner?.isRetired == true)
        saved?()
        XCTAssertEqual(calls, 1)
    }

    func testDescendantAdoptionCannotReleaseAnAncestorsRetiredPayload() async {
        let runtime = makeRuntime()
        var releases = 0
        var calls = 0
        let ancestor = buttonWithRelease(in: runtime) { releases += 1 }
        let retained = button(in: runtime) {}
        ancestor.addChild(retained)
        runtime.root.addChild(ancestor)
        ancestor.revokeTextInputOwnership()
        XCTAssertTrue(ancestor.buttonActionOwner?.isRetired == true)
        XCTAssertEqual(releases, 0)
        let source = button(in: runtime) { calls += 1 }

        let result = ComponentHost.adopt(source: source, into: retained)

        XCTAssertTrue(result.completed)
        XCTAssertEqual(releases, 0, "An ancestor witness owns no payload cleanup")
        retained.onActivate?()
        XCTAssertEqual(calls, 1)
        ancestor.removeFromParent()
        XCTAssertEqual(releases, 1)
    }

    func testMountedPassiveSourceTransfersBesidePendingButton() async {
        let runtime = makeRuntime()
        let otherRuntime = makeRuntime()
        let source = mountedPassiveSource(in: otherRuntime)
        let originalIdentity = source.root.retainedViewIdentity
        var calls = 0
        var events: [String] = []
        let pending = button(in: runtime) { calls += 1 }
        let saved = pending.onActivate
        source.root.onDismantlePlatformView = { _ in
            events.append("dismantle")
            saved?()
        }
        source.root.onDisappear = { events.append("root disappear") }
        source.leaf.onDisappear = { events.append("leaf disappear") }
        defer { source.root.onDismantlePlatformView = nil }

        let result = ComponentHost.reconcileChildren(
            of: runtime.root, oldChildren: [], newNodes: [source.root, pending])

        XCTAssertTrue(result.completed)
        XCTAssertEqual(events, ["dismantle", "root disappear", "leaf disappear"])
        XCTAssertTrue(otherRuntime.root.children.isEmpty)
        XCTAssertEqual(
            runtime.root.children.map(ObjectIdentifier.init), [source.root, pending].map(ObjectIdentifier.init))
        XCTAssertTrue(source.root.parent === runtime.root)
        XCTAssertTrue(source.leaf.parent === source.root)
        XCTAssertTrue(source.root.retainedLazyListRuntime === runtime)
        XCTAssertTrue(source.leaf.retainedLazyListRuntime === runtime)
        XCTAssertEqual(source.root.retainedViewIdentity, originalIdentity)
        for controller in [source.rootController, source.leafController] {
            XCTAssertEqual(controller.attachCalls, 2)
            XCTAssertEqual(controller.detachCalls, 1)
            XCTAssertTrue(controller.isAuthorized)
        }
        XCTAssertEqual(calls, 0)
        saved?()
        pending.onActivate?()
        XCTAssertEqual(calls, 2)
    }

    func testMountedSourceDepartureFinishesAfterButtonAdmissionExpires() async {
        for stopsRuntime in [false, true] {
            let runtime = makeRuntime()
            let otherRuntime = makeRuntime()
            let source = mountedPassiveSource(in: otherRuntime)
            let originalIdentity = source.root.retainedViewIdentity
            var calls = 0
            var events: [String] = []
            let pending = button(in: runtime) { calls += 1 }
            let saved = pending.onActivate
            source.root.onDismantlePlatformView = { _ in
                events.append("dismantle")
                if stopsRuntime {
                    runtime.stopRenderLifecycleCallbacks()
                } else {
                    source.root.retainedViewIdentity = originalIdentity
                }
                saved?()
            }
            source.root.onDisappear = { events.append("root disappear") }
            source.leaf.onDisappear = { events.append("leaf disappear") }
            source.rootController.onWillDetach = { events.append("root will detach") }
            source.rootController.onDetach = { events.append("root detach") }
            source.leafController.onWillDetach = { events.append("leaf will detach") }
            source.leafController.onDetach = { events.append("leaf detach") }
            defer { source.root.onDismantlePlatformView = nil }

            let result = ComponentHost.reconcileChildren(
                of: runtime.root, oldChildren: [], newNodes: [source.root, pending])

            XCTAssertFalse(result.completed)
            XCTAssertEqual(
                events,
                [
                    "dismantle", "root disappear", "leaf disappear", "root will detach", "root detach",
                    "leaf will detach", "leaf detach",
                ])
            XCTAssertTrue(otherRuntime.root.children.isEmpty)
            XCTAssertTrue(runtime.root.children.isEmpty)
            XCTAssertNil(source.root.parent)
            XCTAssertNil(source.root.retainedLazyListRuntime)
            XCTAssertNil(source.leaf.retainedLazyListRuntime)
            XCTAssertFalse(source.root.hasAppeared)
            XCTAssertFalse(source.leaf.hasAppeared)
            for controller in [source.rootController, source.leafController] {
                XCTAssertEqual(controller.attachCalls, 1)
                XCTAssertEqual(controller.detachCalls, 1)
                XCTAssertFalse(controller.isAuthorized)
            }
            XCTAssertEqual(runtime.permitsRetainedActionInvocation, !stopsRuntime)
            XCTAssertTrue(otherRuntime.permitsRetainedActionInvocation)
            XCTAssertTrue(pending.buttonActionOwner?.isRetired == true)
            saved?()
            XCTAssertEqual(calls, 0)
        }
    }

    func testMountedSourceControllerCallbacksCannotInterruptOwedDeparture() async {
        for expiresDuringDetach in [false, true] {
            let runtime = makeRuntime()
            let otherRuntime = makeRuntime()
            let source = mountedPassiveSource(in: otherRuntime)
            var calls = 0
            let pending = button(in: runtime) { calls += 1 }
            let saved = pending.onActivate
            let expire: @MainActor () -> Void = { runtime.stopRenderLifecycleCallbacks() }
            if expiresDuringDetach {
                source.rootController.onDetach = expire
            } else {
                source.rootController.onWillDetach = expire
            }

            let result = ComponentHost.reconcileChildren(
                of: runtime.root, oldChildren: [], newNodes: [source.root, pending])

            XCTAssertFalse(result.completed)
            XCTAssertTrue(otherRuntime.root.children.isEmpty)
            XCTAssertTrue(runtime.root.children.isEmpty)
            XCTAssertNil(source.root.parent)
            XCTAssertNil(source.root.retainedLazyListRuntime)
            XCTAssertNil(source.leaf.retainedLazyListRuntime)
            for controller in [source.rootController, source.leafController] {
                XCTAssertEqual(controller.willDetachCalls, 1)
                XCTAssertEqual(controller.detachCalls, 1)
                XCTAssertFalse(controller.isAuthorized)
            }
            saved?()
            XCTAssertEqual(calls, 0)
        }
    }

    func testMountedSourceCleanupDetachesItsCapturedControllerBeforeAttachingReplacement() async {
        let runtime = makeRuntime()
        let otherRuntime = makeRuntime()
        let source = mountedPassiveSource(in: otherRuntime)
        let replacement = ButtonConstructionAttachmentController()
        source.rootController.onWillDetach = { source.root.textInputController = replacement }
        var calls = 0
        let pending = button(in: runtime) { calls += 1 }

        let result = ComponentHost.reconcileChildren(
            of: runtime.root, oldChildren: [], newNodes: [source.root, pending])

        XCTAssertTrue(result.completed)
        XCTAssertEqual(source.rootController.detachCalls, 1)
        XCTAssertFalse(source.rootController.isAuthorized)
        XCTAssertTrue(source.root.textInputController === replacement)
        XCTAssertEqual(replacement.attachCalls, 2, "The live setter attaches before the destination transfer")
        XCTAssertEqual(replacement.detachCalls, 0)
        XCTAssertTrue(replacement.isAuthorized)
        pending.onActivate?()
        XCTAssertEqual(calls, 1)
    }

    func testRejectedMountedSourceFinishesOldTasksBeforePendingButtonPayloadRelease() async {
        let runtime = makeRuntime()
        let otherRuntime = makeRuntime()
        let source = mountedPassiveSource(in: otherRuntime)
        let originalIdentity = source.root.retainedViewIdentity
        let ready = expectation(description: "Source tasks installed")
        ready.expectedFulfillmentCount = 2
        let completed = expectation(description: "Source tasks completed")
        completed.expectedFulfillmentCount = 2
        let rootTask = ButtonConstructionTaskProbe(ready: ready, completed: completed)
        let leafTask = ButtonConstructionTaskProbe(ready: ready, completed: completed)
        var events: [String] = []
        var cancellationsAtRelease: [Int] = []
        let pending = buttonWithRelease(in: runtime) {
            cancellationsAtRelease.append(rootTask.cancelCount + leafTask.cancelCount)
        }
        source.root.onDismantlePlatformView = { _ in
            events.append("dismantle")
            source.root.retainedViewIdentity = originalIdentity
        }
        source.root.onDisappear = { events.append("root disappear") }
        source.leaf.onDisappear = { events.append("leaf disappear") }
        rootTask.onCancellation = { events.append("root cancel") }
        leafTask.onCancellation = { events.append("leaf cancel") }
        source.root.launchLifecycleTask(
            ViewLifecycleTaskLaunch(key: "root", priority: .userInitiated) { await rootTask.run() })
        source.leaf.launchLifecycleTask(
            ViewLifecycleTaskLaunch(key: "leaf", priority: .userInitiated) { await leafTask.run() })
        defer {
            source.root.onDismantlePlatformView = nil
            runtime.stopRenderLifecycleCallbacks()
            runtime.cancelRenderLifecycleTasks()
            otherRuntime.stopRenderLifecycleCallbacks()
            otherRuntime.cancelRenderLifecycleTasks()
            rootTask.release()
            leafTask.release()
        }
        await fulfillment(of: [ready], timeout: 5)

        let result = ComponentHost.reconcileChildren(
            of: runtime.root, oldChildren: [], newNodes: [source.root, pending])

        XCTAssertFalse(result.completed)
        XCTAssertEqual(events, ["dismantle", "root disappear", "root cancel", "leaf disappear", "leaf cancel"])
        XCTAssertEqual(rootTask.cancelCount, 1)
        XCTAssertEqual(leafTask.cancelCount, 1)
        XCTAssertEqual(cancellationsAtRelease, [2])
        XCTAssertEqual(source.rootController.detachCalls, 1)
        XCTAssertEqual(source.leafController.detachCalls, 1)
        await fulfillment(of: [completed], timeout: 5)
    }

    func testMountedSourceCleanupCannotDetachAReparentedDescendantsController() async {
        for replacesController in [false, true] {
            let runtime = makeRuntime()
            let otherRuntime = makeRuntime()
            let destination = makeRuntime()
            let source = mountedPassiveSource(in: otherRuntime)
            let replacement = ButtonConstructionAttachmentController()
            var calls = 0
            var movedAttachment: RetainedLazyListAttachmentProof?
            var events: [String] = []
            let pending = button(in: runtime) { calls += 1 }
            let saved = pending.onActivate
            source.root.onDismantlePlatformView = { _ in
                events.append("dismantle")
                destination.root.addChild(source.leaf)
                if replacesController {
                    source.leaf.textInputController = replacement
                }
                movedAttachment = source.leaf.captureLazyListAttachmentProof()
            }
            source.root.onDisappear = { events.append("root disappear") }
            source.leaf.onDisappear = { events.append("leaf disappear") }
            defer { source.root.onDismantlePlatformView = nil }

            let result = ComponentHost.reconcileChildren(
                of: runtime.root, oldChildren: [], newNodes: [source.root, pending])

            XCTAssertFalse(result.completed)
            XCTAssertEqual(events, ["dismantle", "leaf disappear", "root disappear"])
            XCTAssertTrue(runtime.root.children.isEmpty)
            XCTAssertTrue(otherRuntime.root.children.isEmpty)
            XCTAssertNil(source.root.parent)
            XCTAssertNil(source.root.retainedLazyListRuntime)
            XCTAssertEqual(source.rootController.detachCalls, 1)
            XCTAssertTrue(source.root.children.isEmpty)
            XCTAssertTrue(destination.root.children.first === source.leaf)
            XCTAssertTrue(source.leaf.parent === destination.root)
            XCTAssertTrue(source.leaf.retainedLazyListRuntime === destination)
            XCTAssertTrue(movedAttachment?.isCurrent == true)
            XCTAssertEqual(source.leafController.attachCalls, 2)
            XCTAssertEqual(source.leafController.detachCalls, 1)
            if replacesController {
                XCTAssertTrue(source.leaf.textInputController === replacement)
                XCTAssertTrue(replacement.isAuthorized)
                XCTAssertEqual(replacement.attachCalls, 1)
                XCTAssertEqual(replacement.detachCalls, 0)
            } else {
                XCTAssertTrue(source.leaf.textInputController === source.leafController)
                XCTAssertTrue(source.leafController.isAuthorized)
            }
            saved?()
            XCTAssertEqual(calls, 0)
        }
    }

    func testMountedSourceHoverCleanupCannotAnimateAReparentedDescendant() async {
        for movesDuringClock in [false, true] {
            let runtime = makeRuntime()
            let otherRuntime = makeRuntime()
            let destination = makeRuntime()
            let source = mountedPassiveSource(in: otherRuntime)
            source.leaf.interactionSurface = RetainedInteractionSurface(
                idleBackground: .black, hoveredBackground: .white, hoverDuration: 1)
            otherRuntime.clock = { 100 }
            destination.clock = { 100 }
            otherRuntime.pointerMoved(to: Point(x: 10, y: 10))
            XCTAssertTrue(source.leaf.isHovered)
            var movedAttachment: RetainedLazyListAttachmentProof?
            var moves = 0
            let move: @MainActor () -> Void = {
                moves += 1
                destination.root.addChild(source.leaf)
                destination.pointerMoved(to: Point(x: 10, y: 10))
                movedAttachment = source.leaf.captureLazyListAttachmentProof()
            }
            if movesDuringClock {
                var isArmed = true
                otherRuntime.clock = {
                    if isArmed {
                        isArmed = false
                        move()
                    }
                    return 100
                }
            } else {
                source.leaf.onPointerExit = {
                    source.leaf.onPointerExit = nil
                    move()
                }
            }
            let pending = button(in: runtime) {}
            defer {
                source.leaf.onPointerExit = nil
                otherRuntime.clock = { 100 }
            }

            let result = ComponentHost.reconcileChildren(
                of: runtime.root, oldChildren: [], newNodes: [source.root, pending])

            XCTAssertFalse(result.completed)
            XCTAssertEqual(moves, 1)
            XCTAssertTrue(source.leaf.parent === destination.root)
            XCTAssertTrue(source.leaf.retainedLazyListRuntime === destination)
            XCTAssertTrue(source.leaf.isHovered)
            XCTAssertTrue(movedAttachment?.isCurrent == true)
            XCTAssertFalse(otherRuntime.hasActiveAnimations)
            XCTAssertTrue(destination.hasActiveAnimations)
            XCTAssertEqual(source.rootController.detachCalls, 1)
            XCTAssertEqual(source.leafController.detachCalls, 1)
            XCTAssertTrue(pending.buttonActionOwner?.isRetired == true)
        }
    }

    func testMountedSourceDisappearancePreservesExplicitTaskCancellationOrder() async {
        let runtime = makeRuntime()
        let otherRuntime = makeRuntime()
        let source = mountedPassiveSource(in: otherRuntime)
        let originalIdentity = source.root.retainedViewIdentity
        let ready = expectation(description: "Original task installed")
        let completed = expectation(description: "Original task completed")
        let task = ButtonConstructionTaskProbe(ready: ready, completed: completed)
        var events: [String] = []
        source.root.onDismantlePlatformView = { _ in source.root.retainedViewIdentity = originalIdentity }
        source.root.onDisappear = {
            events.append("begin")
            source.root.cancelLifecycleTask(key: "root")
            events.append("end")
        }
        task.onCancellation = { events.append("cancel") }
        source.root.launchLifecycleTask(
            ViewLifecycleTaskLaunch(key: "root", priority: .userInitiated) { await task.run() })
        defer {
            source.root.onDismantlePlatformView = nil
            source.root.onDisappear = nil
            runtime.stopRenderLifecycleCallbacks()
            runtime.cancelRenderLifecycleTasks()
            otherRuntime.stopRenderLifecycleCallbacks()
            otherRuntime.cancelRenderLifecycleTasks()
            task.release()
        }
        await fulfillment(of: [ready], timeout: 5)
        let pending = button(in: runtime) {}

        let result = ComponentHost.reconcileChildren(
            of: runtime.root, oldChildren: [], newNodes: [source.root, pending])

        XCTAssertFalse(result.completed)
        XCTAssertEqual(events, ["begin", "cancel", "end"])
        XCTAssertEqual(task.cancelCount, 1)
        XCTAssertEqual(source.rootController.detachCalls, 1)
        XCTAssertEqual(source.leafController.detachCalls, 1)
        XCTAssertTrue(pending.buttonActionOwner?.isRetired == true)
        await fulfillment(of: [completed], timeout: 5)
    }

    func testMountedSourceCleanupPreservesHoverInstalledByAnEarlierCallback() async {
        for phase in ["exit", "drag", "dismantle", "willDetach"] {
            let runtime = makeRuntime()
            let otherRuntime = makeRuntime()
            let source = mountedPassiveSource(in: otherRuntime)
            let survivor = ViewNode(frame: Rect(x: 120, y: 0, width: 40, height: 30))
            var enters = 0
            var exits = 0
            var moves = 0
            var pressedEnds = 0
            var dragStarts = 0
            var dragChanges: [Point] = []
            var dragEnds: [Point] = []
            survivor.onPointerEnter = { enters += 1 }
            survivor.onPointerExit = { exits += 1 }
            otherRuntime.root.addChild(survivor)
            let survivorAttachment = survivor.captureLazyListAttachmentProof()
            source.leaf.onPointerUpOutside = { pressedEnds += 1 }
            otherRuntime.pointerMoved(to: Point(x: 10, y: 10))
            XCTAssertTrue(source.leaf.isHovered, phase)
            let move: @MainActor () -> Void = {
                moves += 1
                otherRuntime.pointerMoved(to: Point(x: 130, y: 10))
            }
            switch phase {
            case "exit":
                source.leaf.onPointerExit = {
                    source.leaf.onPointerExit = nil
                    move()
                }
            case "drag":
                source.leaf.onDragStart = { _ in dragStarts += 1 }
                source.leaf.onDragChange = { point, _ in dragChanges.append(point) }
                source.leaf.onDragEnd = { point, _ in
                    dragEnds.append(point)
                    move()
                }
                otherRuntime.pointerDown(at: Point(x: 10, y: 10))
                otherRuntime.pointerMoved(to: Point(x: 20, y: 10))
            case "dismantle":
                source.root.onDismantlePlatformView = { _ in move() }
                otherRuntime.pointerDown(at: Point(x: 10, y: 10))
            default:
                source.rootController.onWillDetach = move
                otherRuntime.pointerDown(at: Point(x: 10, y: 10))
            }
            var calls = 0
            let pending = button(in: runtime) { calls += 1 }
            defer {
                source.root.onDismantlePlatformView = nil
                source.leaf.onPointerExit = nil
                source.leaf.onDragEnd = nil
            }

            let result = ComponentHost.reconcileChildren(
                of: runtime.root, oldChildren: [], newNodes: [source.root, pending])

            XCTAssertTrue(result.completed, phase)
            XCTAssertEqual(moves, 1, phase)
            XCTAssertEqual(enters, 1, phase)
            XCTAssertEqual(exits, 0, phase)
            XCTAssertTrue(survivor.isHovered, phase)
            XCTAssertTrue(survivorAttachment.isCurrent, phase)
            XCTAssertEqual(otherRuntime.root.children.map(ObjectIdentifier.init), [ObjectIdentifier(survivor)], phase)
            XCTAssertTrue(source.root.parent === runtime.root, phase)
            XCTAssertEqual(source.rootController.detachCalls, 1, phase)
            XCTAssertEqual(source.leafController.detachCalls, 1, phase)
            XCTAssertEqual(pressedEnds, phase == "dismantle" || phase == "willDetach" ? 1 : 0, phase)
            XCTAssertEqual(dragStarts, phase == "drag" ? 1 : 0, phase)
            XCTAssertEqual(dragChanges, phase == "drag" ? [Point(x: 20, y: 10)] : [], phase)
            XCTAssertEqual(dragEnds, phase == "drag" ? [Point(x: 20, y: 10)] : [], phase)
            pending.onActivate?()
            XCTAssertEqual(calls, 1, phase)

            otherRuntime.pointerMoved(to: Point(x: 130, y: 10))
            XCTAssertEqual(enters, 1, phase)
            otherRuntime.pointerExitedWindow()
            XCTAssertEqual(exits, 1, phase)
            XCTAssertFalse(survivor.isHovered, phase)
        }
    }

    private func mountedPassiveSource(in runtime: RetainedViewRuntime) -> (
        root: ViewNode, leaf: ViewNode,
        rootController: ButtonConstructionAttachmentController,
        leafController: ButtonConstructionAttachmentController
    ) {
        let root = ViewNode(frame: Rect(x: 0, y: 0, width: 100, height: 80))
        let leaf = ViewNode(frame: Rect(x: 0, y: 0, width: 40, height: 30))
        root.retainedViewIdentity = RetainedViewIdentity(segments: [.keyed(.init("foreign"))])
        leaf.retainedViewIdentity = RetainedViewIdentity(segments: [.keyed(.init("foreign leaf"))])
        let rootController = ButtonConstructionAttachmentController()
        let leafController = ButtonConstructionAttachmentController()
        root.textInputController = rootController
        leaf.textInputController = leafController
        root.addChild(leaf)
        runtime.root.addChild(root)
        _ = runtime.renderFrame()
        XCTAssertTrue(root.hasAppeared)
        XCTAssertTrue(leaf.hasAppeared)
        return (root, leaf, rootController, leafController)
    }

    private func buttonWithRelease(
        in runtime: RetainedViewRuntime, onRelease: @escaping @MainActor () -> Void
    ) -> ViewNode {
        let probe = ButtonConstructionReleaseProbe(onRelease)
        return button(in: runtime) { [probe] in withExtendedLifetime(probe) {} }
    }

    private func withThrowingConstruction(
        _ runtime: RetainedViewRuntime, perform body: () throws -> Void
    ) rethrows {
        let construction = RetainedButtonActionConstruction(runtime: runtime)
        defer { construction.finish() }
        try body()
    }

    private func makeRuntime() -> RetainedViewRuntime {
        RetainedViewRuntime(root: ViewNode(frame: Rect(x: 0, y: 0, width: 200, height: 100), isHitTestVisible: false))
    }

    private func button(
        in runtime: RetainedViewRuntime, tag: String = "button", action: @escaping () -> Void
    ) -> ViewNode {
        let node = Controls.button(
            runtime: runtime, frame: Rect(x: 20, y: 20, width: 100, height: 20), cornerRadius: 4,
            palette: SurfacePalette(idle: .gray, focused: .blue, pressed: .black), action: action)
        node.nodeTag = tag
        return node
    }

    private func adapter(_ source: Source, runtime: RetainedViewRuntime) throws -> Adapter {
        let adapter = try XCTUnwrap(
            Adapter(
                provider: source, estimatedExtent: 20, prefetchExtent: 0,
                maximumMountedRecords: 8, maximumMountedLeaves: 8, maximumProtectedRecords: 2))
        XCTAssertTrue(adapter.claimAttachment(to: runtime.root))
        return adapter
    }

    private func viewport(extent: Double = 20) throws -> Adapter.Viewport {
        let context = try XCTUnwrap(
            RetainedLazyListMeasurementContext(width: 100, displayScale: 1, contentRevision: 0, environmentRevision: 0))
        return try XCTUnwrap(Adapter.Viewport(context: context, offset: 0, extent: extent))
    }

    private func budget() throws -> RetainedLazyListWorkBudget {
        try XCTUnwrap(RetainedLazyListWorkBudget(elementLimit: 16, roundLimit: 4))
    }

    private func ready(_ adapter: Adapter, extent: Double = 20) throws -> Adapter.Candidate {
        guard
            case .ready(let candidate) = adapter.prepare(
                viewport: try viewport(extent: extent), protectedRoots: [], budget: try budget())
        else {
            XCTFail("Expected one pending Candidate")
            throw ConstructionFailure.noCandidate
        }
        return candidate
    }
}

private enum ConstructionFailure: Error {
    case stopped
    case noCandidate
}

@MainActor
private final class ButtonConstructionReleaseProbe {
    private let onRelease: @MainActor () -> Void
    init(_ onRelease: @escaping @MainActor () -> Void) { self.onRelease = onRelease }
    isolated deinit { onRelease() }
}

@MainActor
private final class ButtonConstructionAttachmentController: RetainedTextInputController {
    var onAttach: (@MainActor () -> Void)?
    var onWillDetach: (@MainActor () -> Void)?
    var onDetach: (@MainActor () -> Void)?
    private(set) var attachCalls = 0
    private(set) var willDetachCalls = 0
    private(set) var detachCalls = 0
    private(set) var isAuthorized = false
    private weak var owner: ViewNode?

    func attach(to node: ViewNode) {
        owner = node
        isAuthorized = true
        attachCalls += 1
        let action = onAttach
        onAttach = nil
        action?()
    }

    func reconcile(from previous: (any RetainedTextInputController)?, onto node: ViewNode) {}

    func revokeOwnership(from node: ViewNode) {
        if owner === node { isAuthorized = false }
    }

    func willDetach(from node: ViewNode) {
        willDetachCalls += 1
        let action = onWillDetach
        onWillDetach = nil
        action?()
    }

    func detach(from node: ViewNode) {
        detachCalls += 1
        if owner === node {
            isAuthorized = false
            owner = nil
        }
        let action = onDetach
        onDetach = nil
        action?()
    }
}

/// Cancellation in this fixture is driven only by MainActor departure/close.
/// Readiness acknowledges installation of both handler and continuation.
@MainActor
private final class ButtonConstructionTaskProbe {
    let ready: XCTestExpectation
    let completed: XCTestExpectation
    var onCancellation: (@MainActor () -> Void)?
    private(set) var cancelCount = 0
    private var continuation: CheckedContinuation<Void, Never>?
    private var wasReleased = false

    init(ready: XCTestExpectation, completed: XCTestExpectation) {
        self.ready = ready
        self.completed = completed
    }

    func run() async {
        await withTaskCancellationHandler(
            operation: {
                await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                    if Task.isCancelled || wasReleased {
                        continuation.resume()
                    } else {
                        self.continuation = continuation
                    }
                    ready.fulfill()
                }
            },
            onCancel: { [weak self] in
                let probe = self
                MainActor.assumeIsolated { probe?.cancel() }
            })
        completed.fulfill()
    }

    private func cancel() {
        guard cancelCount == 0 else { return }
        cancelCount += 1
        let previous = continuation
        continuation = nil
        onCancellation?()
        previous?.resume()
    }

    func release() {
        wasReleased = true
        let previous = continuation
        continuation = nil
        previous?.resume()
    }
}

@MainActor
private final class ButtonConstructionDepartureProbe {
    var shouldRun: @MainActor () -> Bool = { false }
    var action: (@MainActor () -> Void)?
    private(set) var calls = 0

    func fire() {
        guard let action, shouldRun() else { return }
        self.action = nil
        calls += 1
        action()
    }
}

private struct ButtonConstructionDepartureKey: Hashable {
    let probe: ButtonConstructionDepartureProbe

    func hash(into hasher: inout Hasher) {
        MainActor.assumeIsolated { probe.fire() }
        hasher.combine(0)
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        MainActor.assumeIsolated {
            lhs.probe.fire()
            rhs.probe.fire()
        }
        return true
    }
}
