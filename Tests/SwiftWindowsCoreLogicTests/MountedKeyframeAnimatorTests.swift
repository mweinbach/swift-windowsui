import SwiftWindowsCore
import XCTest

@testable import SwiftWindowsUI
@testable import WinSwiftUI

@MainActor
final class KeyframeTestClock {
    var now = 0.0
}

/// No window, scheduler wait, Task, or wall-clock sampling. The native frame
/// timestamp and the runtime's start clock are controlled by the same fixture.
@MainActor
final class KeyframeAnimatorTestHost {
    let runtime: RetainedViewRuntime
    let componentHost: ComponentHost
    let coordinator: StateMountCoordinator
    let clock = KeyframeTestClock()
    private(set) var isClosed = false

    init(size: Size = Size(width: 200, height: 100), content: @escaping @MainActor () -> AnyView) {
        let runtime = RetainedViewRuntime(
            root: ViewNode(frame: Rect(x: 0, y: 0, width: size.width, height: size.height)))
        let componentHost = ComponentHost(runtime: runtime)
        let coordinator = StateMountCoordinator(
            invalidate: { [weak componentHost] in componentHost?.reload() },
            observeObject: { _ in },
            updateObservedObjects: { _, _, _ in })
        self.runtime = runtime
        self.componentHost = componentHost
        self.coordinator = coordinator
        let capturedClock = clock
        runtime.clock = { [weak capturedClock] in capturedClock?.now ?? 0 }
        componentHost.buildLifecycle = coordinator
        componentHost.shouldUpdate = { [weak self] in self?.isClosed == false }
        let context = ViewBuildContext(
            stateMountCoordinator: coordinator, canvasSizeProvider: { size },
            invalidateHandler: { [weak componentHost] in componentHost?.reload() })
        componentHost.setComponents { [weak self] in
            guard self?.isClosed == false else { return [] }
            return [makeViewComponent(content(), context: context)]
        }
    }

    var nodes: [ViewNode] {
        var result: [ViewNode] = []
        var pending = [runtime.root]
        while let node = pending.popLast() {
            result.append(node)
            pending.append(contentsOf: node.children.reversed())
        }
        return result
    }

    func reload() {
        guard !isClosed else { return }
        componentHost.reload()
    }

    func tick(_ timestamp: Double) {
        guard !isClosed else { return }
        clock.now = timestamp
        runtime.tickAnimations(at: timestamp)
    }

    @discardableResult
    func layout() -> Rect? {
        guard !isClosed else { return nil }
        return runtime.resolvedLayoutFrame(of: runtime.root)
    }

    func sample(_ identifier: String = "sample", file: StaticString = #filePath, line: UInt = #line) throws -> Double {
        let node = try XCTUnwrap(
            nodes.first { $0.accessibilityIdentifier == identifier }, file: file, line: line)
        return node.transform.translationX
    }

    func close() {
        guard !isClosed else { return }
        isClosed = true
        runtime.stopRenderLifecycleCallbacks()
        coordinator.close()
        componentHost.onReloadCompleted = nil
        componentHost.setComponents { [] }
        runtime.cancelRenderLifecycleTasks()
        runtime.root.removeAllChildren()
    }
}

@MainActor
final class KeyframeTestProbe {
    var trigger = 0
    var repeating = true
    var show = true
    var identity = 0
    var initialValue = 0.0
    var target = 1.0
    var duration = 1.0
    var factoryInputs: [Double] = []
    var contentValues: [Double] = []
    var onFactory: (() -> Void)?
    var onContent: ((Double) -> Void)?
}

@MainActor
private final class KeyframeLifecycleProbe {
    weak var host: KeyframeAnimatorTestHost?
    weak var payload: KeyframeLifetimePayload?
    var onCompare: (() -> Void)?
    var comparisonCount = 0
    var releaseCount = 0
    var observerValue = 0
    var observerDeliveries = 0
}

private struct KeyframeRetiringTrigger: Equatable {
    let value: Int
    let probe: KeyframeLifecycleProbe

    static func == (lhs: Self, rhs: Self) -> Bool {
        MainActor.assumeIsolated {
            lhs.probe.comparisonCount += 1
            lhs.probe.onCompare?()
            return lhs.value == rhs.value
        }
    }
}

@MainActor
private final class KeyframeLifetimePayload {
    let onRelease: @MainActor () -> Void

    init(onRelease: @escaping @MainActor () -> Void) {
        self.onRelease = onRelease
    }

    isolated deinit { onRelease() }
}

private struct KeyframeReleasingFrames: Keyframes {
    typealias Value = Double
    let payload: KeyframeLifetimePayload

    var body: some Keyframes<Double> {
        MoveKeyframe(2.0)
        LinearKeyframe(1.0, duration: 1)
    }
}

@MainActor
private final class KeyframeLazyProbe {
    let animation = KeyframeTestProbe()
    var state: Binding<Int>?
    var owner: StateMountOwner?
}

@MainActor
private struct KeyframeLazyRow: View {
    @State private var counter = 7
    let row: Int
    let probe: KeyframeLazyProbe

    var body: some View {
        if row == 0 {
            probe.state = $counter
            probe.owner = ViewBuildContextScope.current?.viewIdentity.installedOwner
            return AnyView(
                keyframeTestRepeatingView(probe.animation, identifier: "lazy.keyframe.0")
                    .frame(width: 120, height: 20))
        }
        return AnyView(Color.blue.frame(width: 120, height: 20))
    }
}

@MainActor
func keyframeTestSampleView(_ value: Double, identifier: String = "sample") -> some View {
    Rectangle()
        .frame(width: 20, height: 20)
        .offset(x: value)
        .accessibilityIdentifier(identifier)
}

@MainActor
func keyframeTestContent(_ probe: KeyframeTestProbe, value: Double, identifier: String = "sample") -> some View {
    probe.contentValues.append(value)
    probe.onContent?(value)
    return keyframeTestSampleView(value, identifier: identifier)
}

@MainActor
func keyframeTestFrames(_ probe: KeyframeTestProbe, initialValue: Double) -> some Keyframes<Double> {
    probe.factoryInputs.append(initialValue)
    probe.onFactory?()
    return KeyframeTrack {
        LinearKeyframe(probe.target, duration: probe.duration)
    }
}

@MainActor
func keyframeTestTriggeredView(_ probe: KeyframeTestProbe, identifier: String = "sample") -> some View {
    KeyframeAnimator(initialValue: probe.initialValue, trigger: probe.trigger) { value in
        keyframeTestContent(probe, value: value, identifier: identifier)
    } keyframes: { value in
        keyframeTestFrames(probe, initialValue: value)
    }
}

@MainActor
func keyframeTestRepeatingView(_ probe: KeyframeTestProbe, identifier: String = "sample") -> some View {
    KeyframeAnimator(initialValue: probe.initialValue, repeating: probe.repeating) { value in
        keyframeTestContent(probe, value: value, identifier: identifier)
    } keyframes: { value in
        keyframeTestFrames(probe, initialValue: value)
    }
}

@MainActor
final class MountedKeyframeAnimatorTests: XCTestCase {
    func testTriggerMountSeedsWithoutStartingUntilTheValueChanges() async throws {
        let probe = KeyframeTestProbe()
        let host = KeyframeAnimatorTestHost { AnyView(keyframeTestTriggeredView(probe)) }
        defer { host.close() }

        XCTAssertEqual(try host.sample(), 0)
        XCTAssertTrue(probe.factoryInputs.isEmpty)
        XCTAssertFalse(host.runtime.hasActiveAnimations)
        probe.trigger = 1
        host.reload()
        XCTAssertEqual(probe.factoryInputs, [0])
        XCTAssertTrue(host.runtime.hasActiveAnimations)
        host.tick(0.25)
        XCTAssertEqual(try host.sample(), 0.25, accuracy: 0.000_001)
        host.tick(1)
        XCTAssertEqual(try host.sample(), 1, accuracy: 0.000_001)
        XCTAssertFalse(host.runtime.hasActiveAnimations)
    }

    func testUnchangedRebuildKeepsTheOriginalStartAndMountedInitialValue() async throws {
        let probe = KeyframeTestProbe()
        let host = KeyframeAnimatorTestHost { AnyView(keyframeTestTriggeredView(probe)) }
        defer { host.close() }
        probe.trigger = 1
        host.reload()
        host.tick(0.25)
        probe.initialValue = 99
        host.reload()
        host.tick(0.75)

        XCTAssertEqual(try host.sample(), 0.75, accuracy: 0.000_001)
        XCTAssertEqual(probe.factoryInputs, [0])
    }

    func testTheSameSourceViewHasIndependentMountedPlaybackInTwoHosts() async throws {
        let probe = KeyframeTestProbe()
        let source = keyframeTestRepeatingView(probe)
        let first = KeyframeAnimatorTestHost { AnyView(source) }
        let second = KeyframeAnimatorTestHost { AnyView(source) }
        defer {
            first.close()
            second.close()
        }

        first.tick(0.25)
        second.tick(0.75)

        XCTAssertEqual(try first.sample(), 0.25, accuracy: 0.000_001)
        XCTAssertEqual(try second.sample(), 0.75, accuracy: 0.000_001)
        XCTAssertEqual(probe.factoryInputs, [0, 0])
        first.close()
        XCTAssertFalse(first.runtime.hasActiveAnimations)
        XCTAssertTrue(second.runtime.hasActiveAnimations)
    }

    func testBothRepeatingSiblingsAdvanceAfterOneSynchronousFrameRebuild() async throws {
        let left = KeyframeTestProbe()
        let right = KeyframeTestProbe()
        let host = KeyframeAnimatorTestHost {
            AnyView(
                HStack {
                    keyframeTestRepeatingView(left, identifier: "left")
                    keyframeTestRepeatingView(right, identifier: "right")
                })
        }
        defer { host.close() }

        host.tick(0.5)
        XCTAssertEqual(try host.sample("left"), 0.5, accuracy: 0.000_001)
        XCTAssertEqual(try host.sample("right"), 0.5, accuracy: 0.000_001)
        host.tick(0.75)
        XCTAssertEqual(try host.sample("left"), 0.75, accuracy: 0.000_001)
        XCTAssertEqual(try host.sample("right"), 0.75, accuracy: 0.000_001)
        XCTAssertEqual(left.factoryInputs, [0])
        XCTAssertEqual(right.factoryInputs, [0])
    }

    func testExplicitIdentityRetiresTheOldRunBeforeStartingTheNewOccurrence() async throws {
        let probe = KeyframeTestProbe()
        let host = KeyframeAnimatorTestHost {
            AnyView(keyframeTestRepeatingView(probe).id(probe.identity))
        }
        defer { host.close() }
        host.tick(0.4)
        XCTAssertEqual(try host.sample(), 0.4, accuracy: 0.000_001)
        probe.identity = 1
        host.reload()
        XCTAssertEqual(try host.sample(), 0, accuracy: 0.000_001)
        host.tick(0.6)

        XCTAssertEqual(try host.sample(), 0.2, accuracy: 0.000_001)
        XCTAssertEqual(probe.factoryInputs, [0, 0])
    }

    func testConditionalDepartureCancelsBeforeAnyAppearanceCallback() async throws {
        let probe = KeyframeTestProbe()
        let host = KeyframeAnimatorTestHost {
            AnyView(
                Group {
                    if probe.show { keyframeTestRepeatingView(probe) }
                })
        }
        defer { host.close() }
        XCTAssertTrue(host.runtime.hasActiveAnimations)
        probe.show = false
        host.reload()

        XCTAssertFalse(host.runtime.hasActiveAnimations)
        XCTAssertFalse(host.nodes.contains { $0.accessibilityIdentifier == "sample" })
        host.tick(20)
        XCTAssertEqual(probe.factoryInputs, [0])
    }

    func testCloseCancelsTheExactSlotImmediatelyWithoutAFrame() async throws {
        let probe = KeyframeTestProbe()
        let host = KeyframeAnimatorTestHost { AnyView(keyframeTestRepeatingView(probe)) }
        XCTAssertTrue(host.runtime.hasActiveAnimations)

        host.close()

        XCTAssertFalse(host.runtime.hasActiveAnimations)
        XCTAssertTrue(host.runtime.root.children.isEmpty)
        XCTAssertEqual(probe.factoryInputs, [0])
    }

    func testAClaimedDueCallbackCannotAdvanceAfterAnEarlierCallbackUnmountsIt() async throws {
        let probe = KeyframeTestProbe()
        let host = KeyframeAnimatorTestHost {
            AnyView(
                Group {
                    if probe.show { keyframeTestRepeatingView(probe) }
                })
        }
        defer { host.close() }
        host.runtime.scheduleDeferredRebuild(key: "000-retire-keyframe", delay: 0) { [weak host] in
            probe.show = false
            host?.reload()
        }
        let priorValues = probe.contentValues

        host.tick(0.5)

        XCTAssertEqual(probe.contentValues, priorValues)
        XCTAssertEqual(probe.factoryInputs, [0])
        XCTAssertFalse(host.runtime.hasActiveAnimations)
    }

    func testAbandonedReversibleRetirementDoesNotCancelThePreservedRun() async throws {
        let probe = KeyframeTestProbe()
        let host = KeyframeAnimatorTestHost { AnyView(keyframeTestRepeatingView(probe)) }
        defer { host.close() }
        let epoch = try XCTUnwrap(host.coordinator.beginBuild())
        XCTAssertTrue(epoch.willAdopt())
        XCTAssertTrue(host.runtime.hasActiveAnimations)

        epoch.abandon()
        epoch.finishAfterCallbacks()
        host.tick(0.5)

        XCTAssertEqual(try host.sample(), 0.5, accuracy: 0.000_001)
        XCTAssertEqual(probe.factoryInputs, [0])
        XCTAssertTrue(host.runtime.hasActiveAnimations)
    }

    func testFrameClaimDuringReversibleRetirementSurvivesAbandonment() async throws {
        let probe = KeyframeTestProbe()
        let host = KeyframeAnimatorTestHost { AnyView(keyframeTestRepeatingView(probe)) }
        defer { host.close() }
        let epoch = try XCTUnwrap(host.coordinator.beginBuild())
        XCTAssertTrue(epoch.willAdopt())
        let contentBefore = probe.contentValues

        host.tick(0.25)

        XCTAssertEqual(probe.contentValues, contentBefore, "A retiring owner cannot publish a sample")
        XCTAssertEqual(probe.factoryInputs, [0])
        epoch.abandon()
        epoch.finishAfterCallbacks()
        host.tick(0.5)

        XCTAssertEqual(try host.sample(), 0.5, accuracy: 0.000_001)
        XCTAssertEqual(probe.factoryInputs, [0])
        XCTAssertTrue(host.runtime.hasActiveAnimations)
    }

    func testFrameClaimBetweenCommitAndDeliveryWaitsForTheNewProposal() async throws {
        let probe = KeyframeTestProbe()
        let lifecycle = KeyframeLifecycleProbe()
        let host = KeyframeAnimatorTestHost {
            AnyView(
                HStack {
                    Color.clear.onChange(of: lifecycle.observerValue) { _, _ in
                        lifecycle.observerDeliveries += 1
                        lifecycle.host?.tick(0.5)
                    }
                    keyframeTestRepeatingView(probe)
                })
        }
        lifecycle.host = host
        defer { host.close() }
        lifecycle.observerValue = 1

        host.reload()

        XCTAssertEqual(lifecycle.observerDeliveries, 1)
        XCTAssertEqual(try host.sample(), 0, "The pending keyframe proposal has not delivered during the first action")
        XCTAssertEqual(probe.factoryInputs, [0])
        XCTAssertTrue(host.runtime.hasActiveAnimations)
        host.tick(0.5)
        XCTAssertEqual(try host.sample(), 0.5, accuracy: 0.000_001)
    }

    func testKeyedReorderingKeepsEachSurvivingRunAndPhysicalSample() async throws {
        let first = KeyframeTestProbe()
        let second = KeyframeTestProbe()
        second.target = 2
        let probes = [first, second]
        var rows = [0, 1]
        let host = KeyframeAnimatorTestHost {
            AnyView(
                HStack {
                    ForEach(rows, id: \.self) { row in
                        keyframeTestRepeatingView(probes[row], identifier: "row.\(row)")
                    }
                })
        }
        defer { host.close() }
        host.tick(0.25)
        let firstNode = try XCTUnwrap(host.nodes.first { $0.accessibilityIdentifier == "row.0" })
        let secondNode = try XCTUnwrap(host.nodes.first { $0.accessibilityIdentifier == "row.1" })
        rows = [1, 0]

        host.reload()
        host.tick(0.75)

        XCTAssertEqual(try host.sample("row.0"), 0.75, accuracy: 0.000_001)
        XCTAssertEqual(try host.sample("row.1"), 1.5, accuracy: 0.000_001)
        XCTAssertTrue(host.nodes.first { $0.accessibilityIdentifier == "row.0" } === firstNode)
        XCTAssertTrue(host.nodes.first { $0.accessibilityIdentifier == "row.1" } === secondNode)
        XCTAssertEqual(first.factoryInputs, [0])
        XCTAssertEqual(second.factoryInputs, [0])
    }

    func testTriggerComparisonClosingTheOwnerDoesNotEnterTheNewFactory() async throws {
        let probe = KeyframeTestProbe()
        let lifecycle = KeyframeLifecycleProbe()
        let host = KeyframeAnimatorTestHost {
            AnyView(
                KeyframeAnimator(
                    initialValue: 0.0, trigger: KeyframeRetiringTrigger(value: probe.trigger, probe: lifecycle)
                ) { value in
                    keyframeTestSampleView(value)
                } keyframes: { value in
                    keyframeTestFrames(probe, initialValue: value)
                })
        }
        lifecycle.host = host
        lifecycle.onCompare = { [weak host] in host?.close() }
        probe.trigger = 1

        host.reload()

        XCTAssertEqual(lifecycle.comparisonCount, 1)
        XCTAssertTrue(probe.factoryInputs.isEmpty)
        XCTAssertTrue(host.isClosed)
        XCTAssertTrue(host.runtime.root.children.isEmpty)
        XCTAssertFalse(host.runtime.hasActiveAnimations)
        lifecycle.onCompare = nil
    }

    func testCompiledFactoryCaptureCleanupClosingTheOwnerCannotPublish() async throws {
        let probe = KeyframeTestProbe()
        let lifecycle = KeyframeLifecycleProbe()
        probe.show = false
        let host = KeyframeAnimatorTestHost {
            AnyView(
                Group {
                    if probe.show {
                        KeyframeAnimator(initialValue: 0.0) { value in
                            keyframeTestContent(probe, value: value)
                        } keyframes: { _ in
                            let payload = KeyframeLifetimePayload { [weak lifecycle] in
                                lifecycle?.releaseCount += 1
                                lifecycle?.host?.close()
                            }
                            lifecycle.payload = payload
                            return KeyframeReleasingFrames(payload: payload)
                        }
                    }
                })
        }
        lifecycle.host = host
        probe.show = true

        host.reload()

        XCTAssertEqual(lifecycle.releaseCount, 1)
        XCTAssertNil(lifecycle.payload)
        XCTAssertTrue(host.isClosed)
        XCTAssertTrue(host.runtime.root.children.isEmpty)
        XCTAssertFalse(host.runtime.hasActiveAnimations)
        XCTAssertTrue(probe.contentValues.allSatisfy { $0 == 0 })
    }

    func testFinalRetirementReleasesTheLastFactoryCaptureWithoutAnotherFrame() async throws {
        let probe = KeyframeTestProbe()
        let lifecycle = KeyframeLifecycleProbe()
        let host = KeyframeAnimatorTestHost {
            let payload = KeyframeLifetimePayload { [weak lifecycle] in lifecycle?.releaseCount += 1 }
            lifecycle.payload = payload
            return AnyView(
                KeyframeAnimator(initialValue: 0.0) { value in
                    keyframeTestSampleView(value)
                } keyframes: { [payload] value in
                    withExtendedLifetime(payload) { keyframeTestFrames(probe, initialValue: value) }
                })
        }
        XCTAssertNotNil(lifecycle.payload)
        XCTAssertTrue(host.runtime.hasActiveAnimations)
        let releasesBefore = lifecycle.releaseCount

        host.close()

        XCTAssertNil(lifecycle.payload)
        XCTAssertGreaterThan(lifecycle.releaseCount, releasesBefore)
        XCTAssertFalse(host.runtime.hasActiveAnimations)
    }

    func testPublicListEvictionRetiresPlaybackButPreservesLogicalStateOnReturn() async throws {
        let probe = KeyframeLazyProbe()
        let clock = KeyframeTestClock()
        let host = MountedLazyListTestHost {
            List(Array(0..<1000), id: \.self) { row in
                KeyframeLazyRow(row: row, probe: probe)
            }
            .scrollIndicators(.hidden)
        }
        host.runtime.clock = { clock.now }
        defer {
            host.close()
            probe.state = nil
            probe.owner = nil
        }
        try host.assertCommittedDescriptor()
        XCTAssertNotNil(host.layout())
        let state = try XCTUnwrap(probe.state)
        let owner = try XCTUnwrap(probe.owner)
        XCTAssertEqual(probe.animation.factoryInputs, [0])
        clock.now = 0.25
        host.runtime.tickAnimations(at: clock.now)
        XCTAssertNotNil(host.layout())
        XCTAssertEqual(try XCTUnwrap(host.find("lazy.keyframe.0")).transform.translationX, 0.25, accuracy: 0.000_001)

        try host.scroll(to: 4000)

        XCTAssertNil(host.find("lazy.keyframe.0"))
        XCTAssertTrue(owner.isLive)
        XCTAssertFalse(host.runtime.hasActiveAnimations)
        state.wrappedValue = 41
        XCTAssertNotNil(host.layout())
        clock.now = 4
        host.runtime.tickAnimations(at: clock.now)
        XCTAssertEqual(probe.animation.factoryInputs, [0])
        XCTAssertEqual(state.wrappedValue, 41)
        try host.scroll(to: 0)

        XCTAssertTrue(probe.owner === owner)
        XCTAssertEqual(probe.state?.wrappedValue, 41)
        XCTAssertEqual(probe.animation.factoryInputs, [0, 0])
        XCTAssertEqual(try XCTUnwrap(host.find("lazy.keyframe.0")).transform.translationX, 0, accuracy: 0.000_001)
        clock.now = 4.5
        host.runtime.tickAnimations(at: clock.now)
        XCTAssertNotNil(host.layout())
        XCTAssertEqual(try XCTUnwrap(host.find("lazy.keyframe.0")).transform.translationX, 0.5, accuracy: 0.000_001)
    }

    func testContentSupersessionBeforeAdoptionDoesNotEnterTheKeyframesFactory() async throws {
        let probe = KeyframeTestProbe()
        probe.show = false
        let host = KeyframeAnimatorTestHost {
            AnyView(
                Group {
                    if probe.show { keyframeTestRepeatingView(probe) }
                })
        }
        defer { host.close() }
        probe.onContent = { [weak host] _ in
            probe.onContent = nil
            probe.show = false
            host?.reload()
        }
        probe.show = true

        host.reload()

        XCTAssertTrue(probe.factoryInputs.isEmpty)
        XCTAssertFalse(host.runtime.hasActiveAnimations)
        XCTAssertFalse(host.nodes.contains { $0.accessibilityIdentifier == "sample" })
    }

    func testFactoryClosingItsHostCannotPublishOrRearmTheOldRun() async throws {
        let probe = KeyframeTestProbe()
        probe.show = false
        let host = KeyframeAnimatorTestHost {
            AnyView(
                Group {
                    if probe.show { keyframeTestRepeatingView(probe) }
                })
        }
        probe.onFactory = { [weak host] in host?.close() }
        probe.show = true

        host.reload()

        XCTAssertTrue(host.isClosed)
        XCTAssertTrue(host.runtime.root.children.isEmpty)
        XCTAssertFalse(host.runtime.hasActiveAnimations)
        XCTAssertEqual(probe.factoryInputs, [0])
        probe.onFactory = nil
    }

    func testGeometryReaderUsesTheAdoptedSubtreeOwnerAndClock() async throws {
        let probe = KeyframeTestProbe()
        let host = KeyframeAnimatorTestHost {
            AnyView(
                GeometryReader { _ in
                    keyframeTestRepeatingView(probe)
                })
        }
        defer { host.close() }
        XCTAssertNotNil(host.layout())
        XCTAssertTrue(host.runtime.hasActiveAnimations)

        host.tick(0.5)
        XCTAssertNotNil(host.layout())

        XCTAssertEqual(try host.sample(), 0.5, accuracy: 0.000_001)
        XCTAssertEqual(probe.factoryInputs, [0])
    }

    func testUnmanagedComponentOnlySamplesTheBeginningAndDoesNotAcquirePlayback() async throws {
        let runtime = RetainedViewRuntime(root: ViewNode(frame: Rect(x: 0, y: 0, width: 100, height: 100)))
        runtime.clock = { 0 }
        let animator = KeyframeAnimator(initialValue: 0.0) { value in
            keyframeTestSampleView(value)
        } keyframes: { _ in
            MoveKeyframe(2.0)
            LinearKeyframe(10.0, duration: 1)
        }
        let context = ViewBuildContext(
            canvasSizeProvider: { Size(width: 100, height: 100) }, invalidateHandler: {})
        let node = animator.makeComponent(context: context).makeNode(runtime: runtime)
        runtime.root.addChild(node)

        XCTAssertEqual(node.children.first?.transform.translationX, 2)
        XCTAssertFalse(runtime.hasActiveAnimations)
        runtime.tickAnimations(at: 0.5)
        XCTAssertEqual(node.children.first?.transform.translationX, 2)
    }

    func testTimestampQueueForwardsTheFrameWithoutSamplingASecondClock() async throws {
        let runtime = RetainedViewRuntime(root: ViewNode(frame: Rect(x: 0, y: 0, width: 100, height: 100)))
        var clockCalls = 0
        var timestamps: [Double] = []
        var legacyCalls = 0
        runtime.clock = {
            clockCalls += 1
            return 10
        }
        runtime.scheduleDeferredFrameRebuild(key: "frame", at: 10) { timestamps.append($0) }
        XCTAssertEqual(clockCalls, 0)
        runtime.scheduleDeferredRebuild(key: "legacy", delay: 0.5) { legacyCalls += 1 }
        XCTAssertEqual(clockCalls, 1)

        runtime.tickAnimations(at: 10.25)

        XCTAssertEqual(timestamps, [10.25])
        XCTAssertEqual(legacyCalls, 0)
        XCTAssertEqual(clockCalls, 1)
        XCTAssertTrue(runtime.hasActiveAnimations)
        runtime.tickAnimations(at: 10.5)
        XCTAssertEqual(timestamps, [10.25])
        XCTAssertEqual(legacyCalls, 1)
        XCTAssertFalse(runtime.hasActiveAnimations)
    }

    func testCancellingATimestampSlotDoesNotCancelAnotherOwnerOrLegacyWork() async throws {
        let runtime = RetainedViewRuntime(root: ViewNode(frame: Rect(x: 0, y: 0, width: 100, height: 100)))
        runtime.clock = { 0 }
        var events: [String] = []
        runtime.scheduleDeferredFrameRebuild(key: "first", at: 0) { _ in events.append("first") }
        runtime.scheduleDeferredFrameRebuild(key: "second", at: 0) { _ in events.append("second") }
        runtime.scheduleDeferredRebuild(key: "legacy", delay: 0) { events.append("legacy") }

        runtime.cancelDeferredRebuild(key: "first")
        runtime.tickAnimations(at: 0.5)

        XCTAssertEqual(events, ["legacy", "second"])
        XCTAssertFalse(runtime.hasActiveAnimations)
    }
}
