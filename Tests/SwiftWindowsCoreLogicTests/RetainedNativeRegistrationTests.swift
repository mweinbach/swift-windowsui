import SwiftWindowsCore
import SwiftWindowsGraphics
@preconcurrency import XCTest

@testable import SwiftWindowsUI

/// Registry ownership only. These tests do not qualify pending controller
/// cleanup or the ordinary registration before its runtime field is installed.
@MainActor
final class RetainedNativeRegistrationTests: XCTestCase {
    func testNormalRegistrationPathsKeepNoRecordedReceipts() async throws {
        let node = Self.observerNode()
        let runtime = RetainedViewRuntime(root: node)
        node.animationStates = [.opacity: Self.animation()]
        let storage = try XCTUnwrap(node.scrollObserverStorage)
        for _ in 0..<8 {
            node.scrollObserverStorage = storage
            node.animationStates = [.opacity: Self.animation()]
        }
        XCTAssertEqual(runtime.scrollObservationRegistrationCount, 1)
        XCTAssertEqual(runtime.animatingNodeRegistrationCount, 1)
        XCTAssertEqual(runtime.recordedScrollObservationInsertionCount, 0)
        XCTAssertEqual(runtime.recordedAnimatingNodeRegistrationCount, 0)
    }

    func testNilRuntimeOriginRejectsBothRecordingWrites() async {
        let runtime = RetainedViewRuntime(root: ViewNode())
        let node = Self.observerNode()
        node.animationStates = [.opacity: Self.animation()]
        guard case .unavailable = runtime.registerScrollObservationNodeRecordingInsertion(node) else {
            return XCTFail("An unattached origin must not create scroll membership or ownership")
        }
        guard case .unavailable = runtime.registerAnimatingNodeRecordingPublication(node) else {
            return XCTFail("An unattached origin must not create animation membership or ownership")
        }
        XCTAssertEqual(runtime.scrollObservationRegistrationCount, 0)
        XCTAssertEqual(runtime.animatingNodeRegistrationCount, 0)
        XCTAssertEqual(runtime.recordedScrollObservationInsertionCount, 0)
        XCTAssertEqual(runtime.recordedAnimatingNodeRegistrationCount, 0)
    }

    func testUnpublishedNativeRegistryCannotIssueAnInsertionReceipt() async {
        let node = Self.observerNode()
        let runtime = RetainedViewRuntime(root: node)
        let otherRegistry = RetainedScrollObserverRegistry()
        guard case .unavailable = otherRegistry.registerRecordingInsertion(node, runtime: runtime) else {
            return XCTFail("Only the runtime's actual current native registry may record an insertion")
        }
        XCTAssertEqual(otherRegistry.registrationCount, 0)
        XCTAssertEqual(otherRegistry.recordedInsertionCount, 0)
        XCTAssertEqual(runtime.scrollObservationRegistrationCount, 1)
        XCTAssertEqual(runtime.recordedScrollObservationInsertionCount, 0)
    }

    func testForeignRuntimeOriginRejectsWritesWithoutRevokingOriginalReceipts() async throws {
        let fixture = try Self.scrollFixture()
        let runtime = fixture.runtime
        fixture.node.animationStates = [.opacity: Self.animation()]
        let animationReceipt = try Self.animationReceipt(runtime, node: fixture.node)
        let foreign = RetainedViewRuntime(root: ViewNode())
        guard case .unavailable = foreign.registerScrollObservationNodeRecordingInsertion(fixture.node) else {
            return XCTFail("A foreign runtime must not register the node")
        }
        guard case .unavailable = foreign.registerAnimatingNodeRecordingPublication(fixture.node) else {
            return XCTFail("A foreign runtime must not register the node")
        }
        XCTAssertEqual(foreign.scrollObservationRegistrationCount, 0)
        XCTAssertEqual(foreign.animatingNodeRegistrationCount, 0)
        XCTAssertEqual(foreign.recordedScrollObservationInsertionCount, 0)
        XCTAssertEqual(foreign.recordedAnimatingNodeRegistrationCount, 0)
        XCTAssertEqual(runtime.recordedScrollObservationInsertionCount, 1)
        XCTAssertEqual(runtime.recordedAnimatingNodeRegistrationCount, 1)
        XCTAssertEqual(runtime.removeOriginalScrollObservationInsertion(fixture.receipt), .removed)
        XCTAssertEqual(runtime.removeOriginalAnimatingNodeRegistration(animationReceipt), .removed)
    }

    func testScrollInsertionRemovesOnceWithoutClearingPayloadOrHistory() async throws {
        let fixture = try Self.scrollFixture()
        _ = fixture.runtime.renderScene()
        let observer = try XCTUnwrap(fixture.storage.geometry.first)
        let previous = try XCTUnwrap(observer.previousValue as? Double)
        let generation = fixture.storage.generation
        let source = fixture.storage.source
        let alias = fixture.receipt
        XCTAssertEqual(fixture.runtime.removeOriginalScrollObservationInsertion(fixture.receipt), .removed)
        XCTAssertEqual(fixture.runtime.removeOriginalScrollObservationInsertion(alias), .alreadyConsumed)
        XCTAssertEqual(fixture.runtime.scrollObservationRegistrationCount, 0)
        XCTAssertEqual(fixture.runtime.recordedScrollObservationInsertionCount, 0)
        XCTAssertTrue(fixture.node.scrollObserverStorage === fixture.storage)
        XCTAssertTrue(fixture.storage.geometry.first === observer)
        XCTAssertEqual(observer.previousValue as? Double, previous)
        XCTAssertEqual(fixture.storage.generation, generation)
        XCTAssertTrue(fixture.storage.source === source)
    }

    func testScrollNoOpDoesNotAcquireOrRevokeTheOriginalInsertion() async throws {
        let fixture = try Self.scrollFixture()
        for _ in 0..<2 {
            let result = fixture.runtime.registerScrollObservationNodeRecordingInsertion(fixture.node)
            guard case .alreadyRegistered = result else {
                return XCTFail("An existing entry has no new owned insertion")
            }
        }
        XCTAssertEqual(fixture.runtime.scrollObservationRegistrationCount, 1)
        XCTAssertEqual(fixture.runtime.recordedScrollObservationInsertionCount, 1)
        XCTAssertEqual(fixture.runtime.removeOriginalScrollObservationInsertion(fixture.receipt), .removed)
    }

    func testControllerCreatedScrollRegistrationMakesOuterRecordingANoOp() async {
        let runtime = RetainedViewRuntime(root: ViewNode(frame: Rect(x: 0, y: 0, width: 100, height: 100)))
        let node = Self.observerNode()
        let events = NativeRegistrationEvents()
        node.textInputController = NativeRegistrationController { [weak runtime] node in
            node.observeScrollVisibility { value in events.visibility.append(value) }
            guard let runtime else { return XCTFail("The fixture runtime must remain alive") }
            guard case .alreadyRegistered = runtime.registerScrollObservationNodeRecordingInsertion(node) else {
                return XCTFail("The callback's earlier real registration belongs to the callback")
            }
            events.noOpCalls += 1
        }
        runtime.root.addChild(node)
        _ = runtime.renderScene()
        XCTAssertEqual(events.noOpCalls, 1)
        XCTAssertEqual(runtime.scrollObservationRegistrationCount, 1)
        XCTAssertEqual(runtime.recordedScrollObservationInsertionCount, 0)
        XCTAssertEqual(events.visibility, [true])
    }

    func testSameStoragePublicationRevokesOnlyRecordedCleanup() async throws {
        let fixture = try Self.scrollFixture()
        _ = fixture.runtime.renderScene()
        let observer = try XCTUnwrap(fixture.storage.geometry.first)
        let previous = observer.previousValue as? Double
        let generation = fixture.storage.generation
        fixture.node.scrollObserverStorage = fixture.storage
        XCTAssertEqual(fixture.runtime.removeOriginalScrollObservationInsertion(fixture.receipt), .notCurrent)
        XCTAssertEqual(fixture.runtime.scrollObservationRegistrationCount, 1)
        XCTAssertEqual(fixture.runtime.recordedScrollObservationInsertionCount, 0)
        XCTAssertTrue(fixture.node.scrollObserverStorage === fixture.storage)
        XCTAssertEqual(observer.previousValue as? Double, previous)
        XCTAssertEqual(fixture.storage.generation, generation)
    }

    func testNilThenSameStorageCannotRestoreOldInsertionOwnership() async throws {
        let fixture = try Self.scrollFixture()
        fixture.node.scrollObserverStorage = nil
        fixture.node.scrollObserverStorage = fixture.storage
        XCTAssertEqual(fixture.runtime.removeOriginalScrollObservationInsertion(fixture.receipt), .notCurrent)
        XCTAssertEqual(fixture.runtime.scrollObservationRegistrationCount, 1)
        XCTAssertEqual(fixture.runtime.recordedScrollObservationInsertionCount, 0)
        _ = fixture.runtime.renderScene()
        XCTAssertEqual(fixture.events.geometry, [0])
    }

    func testStorageReplacementRevokesBeforeReleasedCaptureReentersCleanup() async throws {
        var fixture: NativeScrollRegistrationFixture? = try Self.scrollFixture()
        let runtime = try XCTUnwrap(fixture?.runtime)
        let node = try XCTUnwrap(fixture?.node)
        let receipt = try XCTUnwrap(fixture?.receipt)
        let events = NativeRegistrationEvents()
        weak var oldStorage = fixture?.storage
        Self.addReleaseCapture(to: try XCTUnwrap(fixture?.storage)) { [weak runtime] in
            guard let runtime else { return XCTFail("The fixture runtime must remain alive") }
            events.removals.append(runtime.removeOriginalScrollObservationInsertion(receipt))
        }
        let replacement = Self.observerStorage(events: events)
        fixture = nil
        node.scrollObserverStorage = replacement
        XCTAssertNil(oldStorage)
        XCTAssertEqual(events.removals, [.notCurrent])
        XCTAssertTrue(node.scrollObserverStorage === replacement)
        XCTAssertEqual(runtime.scrollObservationRegistrationCount, 1)
        XCTAssertEqual(runtime.recordedScrollObservationInsertionCount, 0)
        _ = runtime.renderScene()
        XCTAssertEqual(events.geometry, [0])
        XCTAssertEqual(runtime.removeOriginalScrollObservationInsertion(receipt), .alreadyConsumed)
    }

    func testNilStorageReleaseCanPublishReplacementWithoutOldCleanupRemovingIt() async throws {
        var fixture: NativeScrollRegistrationFixture? = try Self.scrollFixture()
        let runtime = try XCTUnwrap(fixture?.runtime)
        let node = try XCTUnwrap(fixture?.node)
        let receipt = try XCTUnwrap(fixture?.receipt)
        let events = NativeRegistrationEvents()
        let replacement = Self.observerStorage(events: events)
        weak var oldStorage = fixture?.storage
        Self.addReleaseCapture(to: try XCTUnwrap(fixture?.storage)) { [weak runtime, weak node] in
            node?.scrollObserverStorage = replacement
            guard let runtime else { return XCTFail("The fixture runtime must remain alive") }
            events.removals.append(runtime.removeOriginalScrollObservationInsertion(receipt))
        }
        fixture = nil
        node.scrollObserverStorage = nil
        XCTAssertNil(oldStorage)
        XCTAssertEqual(events.removals, [.notCurrent])
        XCTAssertTrue(node.scrollObserverStorage === replacement)
        XCTAssertEqual(runtime.scrollObservationRegistrationCount, 1)
        XCTAssertEqual(runtime.recordedScrollObservationInsertionCount, 0)
        _ = runtime.renderScene()
        XCTAssertEqual(events.geometry, [0])
    }

    func testScrollCompactionKeepsTheExactSurvivingInsertion() async throws {
        let fixture = try Self.scrollFixture(prefixObservers: 130)
        let departed = fixture.runtime.root.children.filter { $0 !== fixture.node }
        XCTAssertEqual(fixture.runtime.scrollObservationRegistrationCount, 131)
        for node in departed { fixture.runtime.root.removeChild(node) }
        XCTAssertEqual(fixture.runtime.scrollObservationRegistrationCount, 1)
        XCTAssertEqual(fixture.runtime.recordedScrollObservationInsertionCount, 1)
        _ = fixture.runtime.renderScene()
        XCTAssertEqual(fixture.runtime.removeOriginalScrollObservationInsertion(fixture.receipt), .removed)
        XCTAssertEqual(fixture.runtime.scrollObservationRegistrationCount, 0)
    }

    func testScrollCompactionDropsExpiredUnrecordedNodesWithoutRetainingThem() async {
        let registry = RetainedScrollObserverRegistry()
        weak var weakNode: ViewNode?
        do {
            let node = ViewNode()
            weakNode = node
            registry.register(node)
            XCTAssertEqual(registry.registrationCount, 1)
            XCTAssertEqual(registry.recordedInsertionCount, 0)
        }
        XCTAssertNil(weakNode)
        registry.compact()
        XCTAssertTrue(registry.isEmpty)
        XCTAssertTrue(registry.nodes.isEmpty)
        XCTAssertEqual(registry.recordedInsertionCount, 0)
    }

    func testReleasedScrollRegistryCannotBeReacquiredThroughTheSameNode() async throws {
        let fixture = try Self.scrollFixture()
        weak var registry = fixture.receipt.registry
        fixture.node.scrollObserverStorage = nil
        XCTAssertNil(registry, "The escaped receipt must not retain the retired native registry")
        fixture.node.scrollObserverStorage = fixture.storage
        XCTAssertEqual(fixture.runtime.removeOriginalScrollObservationInsertion(fixture.receipt), .notCurrent)
        XCTAssertEqual(fixture.runtime.scrollObservationRegistrationCount, 1)
        XCTAssertEqual(fixture.runtime.recordedScrollObservationInsertionCount, 0)
    }

    func testWrongRuntimeRemovalConsumesScrollReceiptBeforeRetry() async throws {
        let fixture = try Self.scrollFixture()
        let foreign = RetainedViewRuntime(root: ViewNode())
        XCTAssertEqual(foreign.removeOriginalScrollObservationInsertion(fixture.receipt), .notCurrent)
        XCTAssertEqual(fixture.runtime.removeOriginalScrollObservationInsertion(fixture.receipt), .alreadyConsumed)
        XCTAssertEqual(fixture.runtime.scrollObservationRegistrationCount, 1)
        XCTAssertEqual(foreign.scrollObservationRegistrationCount, 0)
        fixture.node.scrollObserverStorage = fixture.storage
        XCTAssertEqual(fixture.runtime.recordedScrollObservationInsertionCount, 0)
    }

    func testNormalDetachAndReattachPreserveNewScrollMembership() async throws {
        let fixture = try Self.scrollFixture()
        fixture.node.textInputController = nil
        fixture.runtime.root.removeChild(fixture.node)
        let next = RetainedViewRuntime(root: ViewNode(frame: Rect(x: 0, y: 0, width: 100, height: 100)))
        next.root.addChild(fixture.node)
        XCTAssertEqual(fixture.runtime.removeOriginalScrollObservationInsertion(fixture.receipt), .notCurrent)
        XCTAssertEqual(fixture.runtime.scrollObservationRegistrationCount, 0)
        XCTAssertEqual(next.scrollObservationRegistrationCount, 1)
        XCTAssertTrue(fixture.node.scrollObserverStorage === fixture.storage)
    }

    func testEscapedReceiptsRetainNoRuntimeNodeOrObserverPayload() async throws {
        var scrollReceipt: RetainedScrollRegistrationReceipt?
        var animationReceipt: RetainedAnimatingNodeRegistrationReceipt?
        weak var weakRuntime: RetainedViewRuntime?
        weak var weakNode: ViewNode?
        weak var weakStorage: RetainedScrollObserverStorage?
        weak var weakProbe: NativeRegistrationReleaseProbe?
        let events = NativeRegistrationEvents()
        do {
            let fixture = try Self.scrollFixture()
            weakRuntime = fixture.runtime
            weakNode = fixture.node
            weakStorage = fixture.storage
            weakProbe = Self.addReleaseCapture(to: fixture.storage) { events.releases += 1 }
            fixture.node.animationStates = [.opacity: Self.animation()]
            scrollReceipt = fixture.receipt
            animationReceipt = try Self.animationReceipt(fixture.runtime, node: fixture.node)
        }
        XCTAssertNil(weakRuntime)
        XCTAssertNil(weakNode)
        XCTAssertNil(weakStorage)
        XCTAssertNil(weakProbe)
        XCTAssertEqual(events.releases, 1)
        let other = RetainedViewRuntime(root: ViewNode())
        XCTAssertEqual(other.removeOriginalScrollObservationInsertion(try XCTUnwrap(scrollReceipt)), .notCurrent)
        XCTAssertEqual(other.removeOriginalAnimatingNodeRegistration(try XCTUnwrap(animationReceipt)), .notCurrent)
    }

    func testAnimationPublicationRemovesOnceWithoutChangingScalarOrColorPayloads() async throws {
        let node = ViewNode(frame: Rect(x: 0, y: 0, width: 20, height: 20), backgroundColor: .black)
        let runtime = RetainedViewRuntime(root: node)
        node.animationStates = [.opacity: Self.animation()]
        runtime.animateBackgroundColor(of: node, to: .white, duration: 10, at: 0, easing: .linear)
        let receipt = try Self.animationReceipt(runtime, node: node)
        let alias = receipt
        XCTAssertEqual(runtime.removeOriginalAnimatingNodeRegistration(receipt), .removed)
        XCTAssertEqual(runtime.removeOriginalAnimatingNodeRegistration(alias), .alreadyConsumed)
        XCTAssertEqual(runtime.animatingNodeRegistrationCount, 0)
        XCTAssertEqual(runtime.recordedAnimatingNodeRegistrationCount, 0)
        XCTAssertEqual(node.animationStates[.opacity]?.endValue, 1)
        XCTAssertEqual(node.animationStates[.opacity]?.duration, 10)
        XCTAssertTrue(runtime.hasActiveAnimations, "The independent color animation must remain registered")
        _ = runtime.tickAnimations(at: 5)
        XCTAssertEqual(node.backgroundColor, Color(red: 0.5, green: 0.5, blue: 0.5))
    }

    func testRepeatedAnimationPublicationSupersedesOnlyTheEarlierReceipt() async throws {
        let (runtime, node) = Self.animationFixture()
        let first = try Self.animationReceipt(runtime, node: node)
        let second = try Self.animationReceipt(runtime, node: node)
        XCTAssertEqual(runtime.recordedAnimatingNodeRegistrationCount, 1)
        XCTAssertEqual(runtime.removeOriginalAnimatingNodeRegistration(first), .notCurrent)
        XCTAssertEqual(runtime.animatingNodeRegistrationCount, 1)
        XCTAssertEqual(runtime.removeOriginalAnimatingNodeRegistration(second), .removed)
        XCTAssertEqual(node.animationStates[.opacity]?.endValue, 1)
    }

    func testEmptyThenRestartedAnimationCannotBeRemovedByOldReceipt() async throws {
        let (runtime, node) = Self.animationFixture()
        let receipt = try Self.animationReceipt(runtime, node: node)
        node.animationStates = [:]
        node.animationStates = [.opacity: Self.animation(end: 0.8)]
        XCTAssertEqual(runtime.removeOriginalAnimatingNodeRegistration(receipt), .notCurrent)
        XCTAssertEqual(runtime.animatingNodeRegistrationCount, 1)
        XCTAssertEqual(runtime.recordedAnimatingNodeRegistrationCount, 0)
        XCTAssertEqual(node.animationStates[.opacity]?.endValue, 0.8)
        XCTAssertTrue(runtime.hasActiveAnimations)
    }

    func testNonemptyAnimationReplacementRevokesCleanupAndKeepsNewMotionDriving() async throws {
        let (runtime, node) = Self.animationFixture()
        let receipt = try Self.animationReceipt(runtime, node: node)
        node.animationStates = [.opacity: Self.animation(end: 0.8)]
        XCTAssertEqual(runtime.recordedAnimatingNodeRegistrationCount, 0)
        XCTAssertEqual(runtime.removeOriginalAnimatingNodeRegistration(receipt), .notCurrent)
        XCTAssertEqual(runtime.animatingNodeRegistrationCount, 1)
        XCTAssertTrue(runtime.hasActiveAnimations)
        _ = runtime.tickAnimations(at: 5)
        XCTAssertEqual(node.opacity, 0.4, accuracy: 0.000_001)
        XCTAssertTrue(runtime.hasActiveAnimations)
    }

    func testAnimationSameKeyMutationRevokesCleanupWithoutRemovingRegistration() async throws {
        let (runtime, node) = Self.animationFixture()
        let receipt = try Self.animationReceipt(runtime, node: node)
        node.animationStates[.opacity]?.endValue = 0.6
        XCTAssertEqual(runtime.removeOriginalAnimatingNodeRegistration(receipt), .notCurrent)
        XCTAssertEqual(runtime.animatingNodeRegistrationCount, 1)
        XCTAssertEqual(runtime.recordedAnimatingNodeRegistrationCount, 0)
        XCTAssertEqual(node.animationStates[.opacity]?.endValue, 0.6)
    }

    func testNonemptyAnimationRemovalMutationPreservesRemainingMotion() async throws {
        let (runtime, node) = Self.animationFixture()
        node.animationStates[.frameWidth] = Self.animation(end: 40)
        let receipt = try Self.animationReceipt(runtime, node: node)
        node.animationStates.removeValue(forKey: .frameWidth)
        XCTAssertEqual(runtime.removeOriginalAnimatingNodeRegistration(receipt), .notCurrent)
        XCTAssertEqual(runtime.animatingNodeRegistrationCount, 1)
        XCTAssertEqual(runtime.recordedAnimatingNodeRegistrationCount, 0)
        XCTAssertNotNil(node.animationStates[.opacity])
        XCTAssertNil(node.animationStates[.frameWidth])
    }

    func testEqualAnimationAssignmentIsStillANewPayloadPublication() async throws {
        let (runtime, node) = Self.animationFixture()
        let receipt = try Self.animationReceipt(runtime, node: node)
        let sameValues = node.animationStates
        node.animationStates = sameValues
        XCTAssertEqual(runtime.removeOriginalAnimatingNodeRegistration(receipt), .notCurrent)
        XCTAssertEqual(runtime.animatingNodeRegistrationCount, 1)
        XCTAssertEqual(runtime.recordedAnimatingNodeRegistrationCount, 0)
        XCTAssertEqual(node.animationStates[.opacity]?.endValue, 1)
    }

    func testReleasedCallbackCaptureCannotRemoveAlreadyPublishedReplacementMotion() async throws {
        let (runtime, node) = Self.animationFixture()
        let receipt = try Self.animationReceipt(runtime, node: node)
        let events = NativeRegistrationEvents()
        // AnimationState is scalar-only. This is an actual separate callback
        // capture release after publication, not an invented animation deinit.
        var released: NativeRegistrationReleaseProbe? = NativeRegistrationReleaseProbe { [weak runtime] in
            guard let runtime else { return XCTFail("The fixture runtime must remain alive") }
            events.removals.append(runtime.removeOriginalAnimatingNodeRegistration(receipt))
        }
        weak var weakReleased = released
        node.animationStates = [.opacity: Self.animation(end: 0.7)]
        released = nil
        XCTAssertNil(weakReleased)
        XCTAssertEqual(events.removals, [.notCurrent])
        XCTAssertEqual(runtime.animatingNodeRegistrationCount, 1)
        XCTAssertEqual(node.animationStates[.opacity]?.endValue, 0.7)
        XCTAssertTrue(runtime.hasActiveAnimations)
    }

    func testAnimationSweepPreservesTheLiveOriginalPublication() async throws {
        let (runtime, node) = Self.animationFixture()
        let receipt = try Self.animationReceipt(runtime, node: node)
        _ = runtime.tickAnimations(at: 1)
        XCTAssertEqual(runtime.recordedAnimatingNodeRegistrationCount, 1)
        XCTAssertEqual(runtime.animatingNodeRegistrationCount, 1)
        XCTAssertEqual(runtime.removeOriginalAnimatingNodeRegistration(receipt), .removed)
        XCTAssertEqual(node.animationStates[.opacity]?.endValue, 1)
    }

    func testNaturalAnimationCompletionRevokesTheRecordedPublication() async throws {
        let (runtime, node) = Self.animationFixture()
        let receipt = try Self.animationReceipt(runtime, node: node)
        _ = runtime.tickAnimations(at: 11)
        XCTAssertTrue(node.animationStates.isEmpty)
        XCTAssertEqual(runtime.animatingNodeRegistrationCount, 0)
        XCTAssertEqual(runtime.recordedAnimatingNodeRegistrationCount, 0)
        XCTAssertEqual(runtime.removeOriginalAnimatingNodeRegistration(receipt), .notCurrent)
        XCTAssertFalse(runtime.hasActiveAnimations)
    }

    func testWrongRuntimeRemovalConsumesAnimationReceiptBeforeRetry() async throws {
        let (runtime, node) = Self.animationFixture()
        let receipt = try Self.animationReceipt(runtime, node: node)
        let foreign = RetainedViewRuntime(root: ViewNode())
        XCTAssertEqual(foreign.removeOriginalAnimatingNodeRegistration(receipt), .notCurrent)
        XCTAssertEqual(runtime.removeOriginalAnimatingNodeRegistration(receipt), .alreadyConsumed)
        XCTAssertEqual(runtime.animatingNodeRegistrationCount, 1)
        XCTAssertEqual(foreign.animatingNodeRegistrationCount, 0)
        XCTAssertTrue(runtime.hasActiveAnimations)
        node.animationStates = [:]
        XCTAssertEqual(runtime.recordedAnimatingNodeRegistrationCount, 0)
    }

    func testNormalAnimationDetachAndReattachPreserveNewRuntimeRegistration() async throws {
        let node = ViewNode()
        let old = RetainedViewRuntime(root: ViewNode(children: [node]))
        node.animationStates = [.opacity: Self.animation()]
        let receipt = try Self.animationReceipt(old, node: node)
        old.root.removeChild(node)
        let next = RetainedViewRuntime(root: ViewNode())
        next.root.addChild(node)
        XCTAssertEqual(old.removeOriginalAnimatingNodeRegistration(receipt), .notCurrent)
        XCTAssertEqual(old.animatingNodeRegistrationCount, 0)
        XCTAssertEqual(next.animatingNodeRegistrationCount, 1)
        XCTAssertEqual(node.animationStates[.opacity]?.endValue, 1)
        XCTAssertTrue(next.hasActiveAnimations)
    }

    private static func animation(end: Double = 1) -> AnimationState {
        AnimationState(startValue: 0, endValue: end, startTime: 0, duration: 10, easing: .linear)
    }

    private static func animationFixture() -> (RetainedViewRuntime, ViewNode) {
        let node = ViewNode(frame: Rect(x: 0, y: 0, width: 20, height: 20))
        let runtime = RetainedViewRuntime(root: node)
        node.animationStates = [.opacity: animation()]
        return (runtime, node)
    }

    private static func animationReceipt(
        _ runtime: RetainedViewRuntime, node: ViewNode
    ) throws -> RetainedAnimatingNodeRegistrationReceipt {
        guard case .registered(let receipt) = runtime.registerAnimatingNodeRecordingPublication(node) else {
            XCTFail("Expected one actual animation publication in the matching runtime")
            throw NativeRegistrationFixtureError.unavailable
        }
        return receipt
    }

    private static func observerNode(events: NativeRegistrationEvents? = nil) -> ViewNode {
        let node = ViewNode(
            frame: Rect(x: 10, y: 10, width: 80, height: 80), clipsToBounds: true, scrollAxis: .vertical,
            children: [ViewNode(frame: Rect(x: 0, y: 0, width: 80, height: 300))])
        node.observeScrollGeometry(of: { $0.contentOffset.y }, action: { _, value in events?.geometry.append(value) })
        return node
    }

    private static func observerStorage(events: NativeRegistrationEvents) -> RetainedScrollObserverStorage {
        let storage = RetainedScrollObserverStorage()
        storage.geometry.append(
            RetainedScrollGeometryObserver(
                transform: { $0.contentOffset.y }, action: { _, value in events.geometry.append(value) }))
        return storage
    }

    private static func scrollFixture(prefixObservers: Int = 0) throws -> NativeScrollRegistrationFixture {
        let runtime = RetainedViewRuntime(root: ViewNode(frame: Rect(x: 0, y: 0, width: 100, height: 100)))
        for _ in 0..<prefixObservers { runtime.root.addChild(observerNode()) }
        let events = NativeRegistrationEvents()
        let node = observerNode(events: events)
        var captured: RetainedScrollRegistrationReceipt?
        node.textInputController = NativeRegistrationController { [weak runtime] node in
            guard let runtime else { return XCTFail("Expected an installed runtime before the controller call") }
            guard case .inserted(let receipt) = runtime.registerScrollObservationNodeRecordingInsertion(node) else {
                return XCTFail("Expected the controller to perform the first actual registry insertion")
            }
            captured = receipt
        }
        runtime.root.addChild(node)
        return NativeScrollRegistrationFixture(
            runtime: runtime, node: node, storage: try XCTUnwrap(node.scrollObserverStorage),
            receipt: try XCTUnwrap(captured), events: events)
    }

    @discardableResult
    private static func addReleaseCapture(
        to storage: RetainedScrollObserverStorage, action: @escaping @MainActor () -> Void
    ) -> NativeRegistrationReleaseProbe {
        let probe = NativeRegistrationReleaseProbe(action)
        storage.geometry.append(
            RetainedScrollGeometryObserver(
                transform: { $0.contentOffset.y }, action: { [probe] _, _ in withExtendedLifetime(probe) {} }))
        return probe
    }
}

private enum NativeRegistrationFixtureError: Error { case unavailable }

@MainActor
private struct NativeScrollRegistrationFixture {
    let runtime: RetainedViewRuntime
    let node: ViewNode
    let storage: RetainedScrollObserverStorage
    let receipt: RetainedScrollRegistrationReceipt
    let events: NativeRegistrationEvents
}

@MainActor
private final class NativeRegistrationEvents {
    var geometry: [Double] = []
    var visibility: [Bool] = []
    var removals: [RetainedNativeRegistrationRemovalResult] = []
    var noOpCalls = 0
    var releases = 0
}

@MainActor
private final class NativeRegistrationController: RetainedTextInputController {
    private let onAttach: @MainActor (ViewNode) -> Void

    init(_ onAttach: @escaping @MainActor (ViewNode) -> Void) { self.onAttach = onAttach }
    func attach(to node: ViewNode) { onAttach(node) }
    func reconcile(from previous: (any RetainedTextInputController)?, onto node: ViewNode) {}
    func detach(from node: ViewNode) {}
}

@MainActor
private final class NativeRegistrationReleaseProbe {
    private let onRelease: @MainActor () -> Void

    init(_ onRelease: @escaping @MainActor () -> Void) { self.onRelease = onRelease }
    isolated deinit { onRelease() }
}
