import SwiftWindowsCore
@preconcurrency import XCTest

@testable import SwiftWindowsUI
@testable import WinSwiftUI

@MainActor
private final class MountedPreferenceLifecycleProbe {
    weak var host: MountedOnChangeTestHost?
    weak var runtime: RetainedViewRuntime?
    var value = 0
    var events: [String] = []
    var comparisons: [[Int]] = []
    var constructionDepth = 0
    var maximumConstructionDepth = 0
    var constructionCount = 0
    var reductionDepth = 0
    var maximumReductionDepth = 0
    var reductionCount = 0
    var callbackDepth = 0
    var maximumCallbackDepth = 0
    var onConstruct: (@MainActor () -> Void)?
    var onReduce: (@MainActor () -> Void)?
    var onCompare: (@MainActor () -> Void)?
    var state: Binding<Int>?

    var comparedValue: MountedPreferenceLifecycleValue {
        MountedPreferenceLifecycleValue(number: value, probe: self)
    }

    func record(_ name: String, value: Int, action: () -> Void = {}) {
        callbackDepth += 1
        maximumCallbackDepth = max(maximumCallbackDepth, callbackDepth)
        defer { callbackDepth -= 1 }
        events.append("\(name):\(value)")
        action()
    }
}

@MainActor
private struct MountedPreferenceLifecycleConstructionLeaf: View {
    typealias Body = Never
    let value: Int
    let probe: MountedPreferenceLifecycleProbe

    var body: Never { fatalError("The preference construction leaf has no body") }

    func makeComponent(context: ViewBuildContext) -> Component {
        Component { runtime in
            probe.runtime = runtime
            probe.constructionCount += 1
            probe.constructionDepth += 1
            probe.maximumConstructionDepth = max(probe.maximumConstructionDepth, probe.constructionDepth)
            defer { probe.constructionDepth -= 1 }
            probe.onConstruct?()
            return Controls.label("value=\(value)")
        }
    }
}

private struct MountedPreferenceLifecycleIntKey: PreferenceKey {
    static var defaultValue: Int { 0 }

    static func reduce(value: inout Int, nextValue: () -> Int) { value = nextValue() }
}

@MainActor
private final class MountedPreferenceLifecyclePayload {
    private let onRelease: @MainActor () -> Void

    init(onRelease: @escaping @MainActor () -> Void = {}) { self.onRelease = onRelease }

    isolated deinit { onRelease() }
}

// These witnesses are entered only through the suite's actual main-actor
// mounted builds. Equality ignores the payload while recording which adopted
// baseline the observer compares; no observer callback is invoked directly.
private struct MountedPreferenceLifecycleValue: Equatable {
    let number: Int
    var ignoredPayload = 0
    var probe: MountedPreferenceLifecycleProbe?
    var payload: MountedPreferenceLifecyclePayload?

    static func == (lhs: Self, rhs: Self) -> Bool {
        MainActor.assumeIsolated {
            let probe = lhs.probe ?? rhs.probe
            probe?.comparisons.append([lhs.number, lhs.ignoredPayload, rhs.number, rhs.ignoredPayload])
            probe?.onCompare?()
            return lhs.number == rhs.number
        }
    }
}

private struct MountedPreferenceLifecycleValueKey: PreferenceKey {
    static var defaultValue: MountedPreferenceLifecycleValue { MountedPreferenceLifecycleValue(number: 0) }

    static func reduce(
        value: inout MountedPreferenceLifecycleValue, nextValue: () -> MountedPreferenceLifecycleValue
    ) {
        let next = nextValue()
        value = next
        MainActor.assumeIsolated {
            guard let probe = next.probe else { return }
            probe.reductionCount += 1
            probe.reductionDepth += 1
            probe.maximumReductionDepth = max(probe.maximumReductionDepth, probe.reductionDepth)
            defer { probe.reductionDepth -= 1 }
            probe.onReduce?()
        }
    }
}

private struct MountedPreferenceLifecycleDefaultKey: PreferenceKey {
    @MainActor static var onDefault: (@MainActor () -> Void)?

    // PreferenceKey has a nonisolated requirement. This hook is used only by
    // a synchronous mounted-host build inside the main-actor test below.
    static var defaultValue: MountedPreferenceLifecycleValue {
        MainActor.assumeIsolated {
            let action = onDefault
            onDefault = nil
            action?()
            return MountedPreferenceLifecycleValue(number: 0)
        }
    }

    static func reduce(
        value: inout MountedPreferenceLifecycleValue, nextValue: () -> MountedPreferenceLifecycleValue
    ) {
        value = nextValue()
    }
}

@MainActor
private struct MountedPreferenceLifecycleUnusedComponent: View {
    typealias Body = Never
    let probe: MountedPreferenceLifecycleProbe

    var body: Never { fatalError("The unused preference component has no body") }

    func makeComponent(context: ViewBuildContext) -> Component {
        _ = makeViewComponent(
            Color.clear
                .preference(key: MountedPreferenceLifecycleValueKey.self, value: probe.comparedValue)
                .onPreferenceChange(MountedPreferenceLifecycleValueKey.self) { value in
                    probe.record("unused", value: value.number)
                },
            context: context.withViewIdentityRole(.overlay))
        return Component { _ in Controls.label("used") }
    }
}

@MainActor
private struct MountedPreferenceLifecycleCascadeView: View {
    let probe: MountedPreferenceLifecycleProbe
    @State private var value = 0

    var body: some View {
        let binding = $value
        probe.state = binding
        return HStack {
            Color.clear
                .preference(key: MountedPreferenceLifecycleIntKey.self, value: value)
                .onPreferenceChange(MountedPreferenceLifecycleIntKey.self) { new in
                    probe.record(
                        "first", value: new,
                        action: {
                            if new == 1 { binding.wrappedValue = 2 }
                        })
                }
            Color.clear
                .preference(key: MountedPreferenceLifecycleIntKey.self, value: value)
                .onPreferenceChange(MountedPreferenceLifecycleIntKey.self) { new in
                    probe.record("second", value: new)
                }
        }
    }
}

@MainActor
final class MountedPreferenceLifecycleTests: XCTestCase {
    func testActionsSeeAdoptedNodesAfterConstructionAndBeforeRootCompletion() async {
        let probe = MountedPreferenceLifecycleProbe()
        var labelsDuringActions: [[String]] = []
        var depthsDuringActions: [Int] = []
        let host = MountedOnChangeTestHost {
            AnyView(
                MountedPreferenceLifecycleConstructionLeaf(value: probe.value, probe: probe)
                    .preference(key: MountedPreferenceLifecycleIntKey.self, value: probe.value)
                    .onPreferenceChange(MountedPreferenceLifecycleIntKey.self) { value in
                        labelsDuringActions.append(probe.runtime.map { self.labels(in: $0.root) } ?? [])
                        depthsDuringActions.append(probe.constructionDepth)
                        probe.record("change", value: value)
                    })
        }
        defer { host.close() }
        probe.host = host
        host.componentHost.onReloadCompleted = { probe.events.append("completed") }
        probe.value = 1
        host.reload()

        XCTAssertEqual(labelsDuringActions, [["value=0"], ["value=1"]])
        XCTAssertEqual(depthsDuringActions, [0, 0])
        XCTAssertEqual(probe.events, ["change:0", "change:1", "completed"])
        XCTAssertFalse(host.componentHost.isBuilding)
    }

    func testRejectedViewThatFitsCandidateKeepsOnlyItsAdoptedHistory() async {
        let probe = MountedPreferenceLifecycleProbe()
        probe.value = 1
        var primaryFits = false
        let host = MountedOnChangeTestHost {
            AnyView(
                ViewThatFits(in: .horizontal) {
                    Color.red.frame(width: primaryFits ? 20 : 800, height: 40)
                        .preference(key: MountedPreferenceLifecycleValueKey.self, value: probe.comparedValue)
                        .onPreferenceChange(MountedPreferenceLifecycleValueKey.self) { value in
                            probe.record("primary", value: value.number)
                        }
                    Color.blue.frame(width: 20, height: 40)
                        .preference(key: MountedPreferenceLifecycleIntKey.self, value: 100 + probe.value)
                        .onPreferenceChange(MountedPreferenceLifecycleIntKey.self) { value in
                            probe.record("fallback", value: value)
                        }
                })
        }
        defer { host.close() }
        XCTAssertEqual(probe.events, ["fallback:101"])
        XCTAssertTrue(probe.comparisons.isEmpty)
        XCTAssertGreaterThan(probe.reductionCount, 0, "A measured candidate may still reduce its preference")

        probe.value = 2
        primaryFits = true
        host.reload()
        XCTAssertEqual(probe.events, ["fallback:101", "primary:2"])
        XCTAssertTrue(probe.comparisons.isEmpty, "The rejected value must not establish a baseline")
        probe.value = 3
        primaryFits = false
        host.reload()
        XCTAssertTrue(probe.comparisons.isEmpty, "A rejected materialization must not enter equality")
        probe.value = 4
        primaryFits = true
        host.reload()

        XCTAssertEqual(probe.events, ["fallback:101", "primary:2", "fallback:103", "primary:4"])
        XCTAssertEqual(probe.comparisons, [[2, 0, 4, 0]])
    }

    func testDeclaringAnUnusedComponentDoesNotAdmitAPreferenceObserver() async {
        let probe = MountedPreferenceLifecycleProbe()
        let host = MountedOnChangeTestHost { AnyView(MountedPreferenceLifecycleUnusedComponent(probe: probe)) }
        defer { host.close() }
        probe.value = 1
        host.reload()
        host.render()

        XCTAssertTrue(probe.events.isEmpty)
        XCTAssertTrue(probe.comparisons.isEmpty)
        XCTAssertEqual(labels(in: host.runtime.root), ["used"])
    }

    func testRetirementDuringConstructionDoesNotCompareOrDeliverProvisionalValues() async {
        for closes in [false, true] {
            let probe = MountedPreferenceLifecycleProbe()
            let host = MountedOnChangeTestHost {
                AnyView(
                    MountedPreferenceLifecycleConstructionLeaf(value: probe.value, probe: probe)
                        .preference(key: MountedPreferenceLifecycleValueKey.self, value: probe.comparedValue)
                        .onPreferenceChange(MountedPreferenceLifecycleValueKey.self) { value in
                            probe.record("change", value: value.number)
                        })
            }
            defer { host.close() }
            probe.host = host
            XCTAssertEqual(probe.events, ["change:0"])
            probe.events.removeAll()
            probe.onConstruct = {
                probe.onConstruct = nil
                if closes {
                    probe.host?.close()
                } else {
                    probe.value = 2
                    probe.host?.reload()
                }
            }
            probe.value = 1
            host.reload()

            if closes {
                XCTAssertTrue(probe.events.isEmpty)
                XCTAssertTrue(probe.comparisons.isEmpty)
                XCTAssertTrue(host.isClosed)
                XCTAssertTrue(host.runtime.root.children.isEmpty)
                XCTAssertEqual(host.coordinator.registry.liveOwnerCount, 0)
            } else {
                XCTAssertEqual(probe.events, ["change:2"])
                XCTAssertEqual(probe.comparisons, [[0, 0, 2, 0]])
                XCTAssertEqual(labels(in: host.runtime.root), ["value=2"])
                XCTAssertEqual(probe.constructionCount, 3)
                host.reload()
                XCTAssertEqual(probe.events, ["change:2"])
            }
            XCTAssertEqual(probe.maximumConstructionDepth, 1)
            XCTAssertFalse(host.componentHost.isBuilding)
        }
    }

    func testSupersededReductionDoesNotAdvanceTheLastAdoptedBaseline() async {
        let probe = MountedPreferenceLifecycleProbe()
        let host = MountedOnChangeTestHost {
            AnyView(
                MountedPreferenceLifecycleConstructionLeaf(value: probe.value, probe: probe)
                    .preference(key: MountedPreferenceLifecycleValueKey.self, value: probe.comparedValue)
                    .onPreferenceChange(MountedPreferenceLifecycleValueKey.self) { value in
                        probe.record("change", value: value.number)
                    })
        }
        defer { host.close() }
        probe.host = host
        probe.events.removeAll()
        var reducerWasBuilding = false
        probe.onReduce = {
            probe.onReduce = nil
            reducerWasBuilding = probe.host?.componentHost.isBuilding == true
            probe.value = 2
            probe.host?.reload()
        }
        probe.value = 1
        host.reload()

        // Reduction remains construction work. Cancellation does not promise
        // to interrupt the reducer or the traversal immediately.
        XCTAssertTrue(reducerWasBuilding)
        XCTAssertEqual(probe.events, ["change:2"])
        XCTAssertEqual(probe.comparisons, [[0, 0, 2, 0]])
        XCTAssertEqual(labels(in: host.runtime.root), ["value=2"])
        XCTAssertEqual(probe.maximumReductionDepth, 1)
        XCTAssertEqual(probe.maximumConstructionDepth, 1)
        XCTAssertFalse(host.componentHost.isBuilding)
    }

    func testCloseDuringReductionCannotContinueIntoComparisonOrAction() async {
        let probe = MountedPreferenceLifecycleProbe()
        let host = MountedOnChangeTestHost {
            AnyView(
                Color.clear
                    .preference(key: MountedPreferenceLifecycleValueKey.self, value: probe.comparedValue)
                    .onPreferenceChange(MountedPreferenceLifecycleValueKey.self) { value in
                        probe.record("change", value: value.number)
                    })
        }
        defer { host.close() }
        probe.host = host
        probe.events.removeAll()
        var reducerWasBuilding = false
        probe.onReduce = {
            probe.onReduce = nil
            reducerWasBuilding = probe.host?.componentHost.isBuilding == true
            probe.host?.close()
        }
        probe.value = 1
        host.reload()

        XCTAssertTrue(reducerWasBuilding)
        XCTAssertTrue(probe.events.isEmpty)
        XCTAssertTrue(probe.comparisons.isEmpty)
        XCTAssertTrue(host.isClosed)
        XCTAssertTrue(host.runtime.root.children.isEmpty)
        XCTAssertEqual(host.coordinator.registry.liveOwnerCount, 0)
        XCTAssertFalse(host.componentHost.isBuilding)
    }

    func testDefaultResolutionRemainsProvisionalWhenItSupersedesOrClosesConstruction() async {
        defer { MountedPreferenceLifecycleDefaultKey.onDefault = nil }
        for closes in [false, true] {
            let probe = MountedPreferenceLifecycleProbe()
            probe.value = 1
            var providesValue = true
            let host = MountedOnChangeTestHost {
                AnyView(
                    Group {
                        if providesValue {
                            Color.clear
                                .preference(key: MountedPreferenceLifecycleDefaultKey.self, value: probe.comparedValue)
                        } else {
                            Color.clear
                        }
                    }
                    .onPreferenceChange(MountedPreferenceLifecycleDefaultKey.self) { value in
                        probe.record("change", value: value.number)
                    })
            }
            defer { host.close() }
            probe.host = host
            XCTAssertEqual(probe.events, ["change:1"])
            probe.events.removeAll()
            var hookCalls = 0
            MountedPreferenceLifecycleDefaultKey.onDefault = {
                hookCalls += 1
                if closes {
                    probe.host?.close()
                } else {
                    providesValue = true
                    probe.value = 2
                    probe.host?.reload()
                }
            }
            providesValue = false
            host.reload()

            // Only the hook is one-shot; the traversal may keep consulting
            // defaultValue after cancellation. No lookup-count claim is made.
            XCTAssertEqual(hookCalls, 1)
            if closes {
                XCTAssertTrue(probe.events.isEmpty)
                XCTAssertTrue(probe.comparisons.isEmpty)
                XCTAssertTrue(host.isClosed)
                XCTAssertEqual(host.coordinator.registry.liveOwnerCount, 0)
            } else {
                XCTAssertEqual(probe.events, ["change:2"])
                XCTAssertEqual(probe.comparisons, [[1, 0, 2, 0]])
                host.reload()
                XCTAssertEqual(probe.events, ["change:2"])
            }
            XCTAssertFalse(host.componentHost.isBuilding)
        }
    }

    func testEqualityClosingTheHostCannotContinueIntoThePreferenceAction() async {
        let probe = MountedPreferenceLifecycleProbe()
        let host = MountedOnChangeTestHost {
            AnyView(
                Color.clear
                    .preference(key: MountedPreferenceLifecycleValueKey.self, value: probe.comparedValue)
                    .onPreferenceChange(MountedPreferenceLifecycleValueKey.self) { value in
                        probe.record("change", value: value.number)
                    })
        }
        defer { host.close() }
        probe.host = host
        probe.events.removeAll()
        probe.onCompare = {
            probe.onCompare = nil
            probe.events.append("compare")
            probe.host?.close()
        }
        probe.value = 1
        host.reload()

        XCTAssertEqual(probe.events, ["compare"])
        XCTAssertEqual(probe.comparisons, [[0, 0, 1, 0]])
        XCTAssertTrue(host.isClosed)
        XCTAssertEqual(host.coordinator.registry.liveOwnerCount, 0)
    }

    func testEqualityReentryFinishesTheAdoptedPreferenceActionBeforeTheQueuedBuild() async {
        let probe = MountedPreferenceLifecycleProbe()
        let host = MountedOnChangeTestHost {
            AnyView(
                Color.clear
                    .preference(key: MountedPreferenceLifecycleValueKey.self, value: probe.comparedValue)
                    .onPreferenceChange(MountedPreferenceLifecycleValueKey.self) { value in
                        probe.record("change", value: value.number)
                    })
        }
        defer { host.close() }
        probe.host = host
        probe.events.removeAll()
        probe.onCompare = {
            probe.onCompare = nil
            probe.events.append("compare")
            probe.value = 2
            probe.host?.reload()
        }
        probe.value = 1
        host.reload()

        XCTAssertEqual(probe.events, ["compare", "change:1", "change:2"])
        XCTAssertEqual(probe.comparisons, [[0, 0, 1, 0], [1, 0, 2, 0]])
        XCTAssertEqual(probe.maximumCallbackDepth, 1)
        XCTAssertFalse(host.componentHost.isBuilding)
    }

    func testStateMutationFromTheFirstActionDoesNotSkipTheSecondAdoptedPreferenceObserver() async throws {
        let probe = MountedPreferenceLifecycleProbe()
        let host = MountedOnChangeTestHost { AnyView(MountedPreferenceLifecycleCascadeView(probe: probe)) }
        defer { host.close() }
        XCTAssertEqual(probe.events, ["first:0", "second:0"])
        probe.events.removeAll()
        let binding = try XCTUnwrap(probe.state)
        binding.wrappedValue = 1

        XCTAssertEqual(probe.events, ["first:1", "second:1", "first:2", "second:2"])
        XCTAssertEqual(binding.wrappedValue, 2)
        XCTAssertEqual(probe.maximumCallbackDepth, 1)
        XCTAssertFalse(host.componentHost.isBuilding)
    }

    func testClosingFromTheFirstActionRevokesTheRemainingAdoptedPreferenceObserver() async {
        let probe = MountedPreferenceLifecycleProbe()
        let host = MountedOnChangeTestHost {
            AnyView(
                HStack {
                    Color.clear
                        .preference(key: MountedPreferenceLifecycleIntKey.self, value: probe.value)
                        .onPreferenceChange(MountedPreferenceLifecycleIntKey.self) { value in
                            probe.record("first", value: value, action: { probe.host?.close() })
                        }
                    Color.clear
                        .preference(key: MountedPreferenceLifecycleIntKey.self, value: probe.value)
                        .onPreferenceChange(MountedPreferenceLifecycleIntKey.self) { value in
                            probe.record("second", value: value)
                        }
                })
        }
        defer { host.close() }
        probe.host = host
        XCTAssertEqual(probe.events, ["first:0", "second:0"])
        probe.events.removeAll()
        probe.value = 1
        host.reload()

        XCTAssertEqual(probe.events, ["first:1"])
        XCTAssertTrue(host.isClosed)
        XCTAssertEqual(host.coordinator.registry.liveOwnerCount, 0)
    }

    func testEqualityEquivalentPreferencePayloadKeepsThePriorBaselineUntilAChange() async {
        let probe = MountedPreferenceLifecycleProbe()
        var value = MountedPreferenceLifecycleValue(number: 0, ignoredPayload: 10, probe: probe)
        var received: [[Int]] = []
        let host = MountedOnChangeTestHost {
            AnyView(
                Color.clear
                    .preference(key: MountedPreferenceLifecycleValueKey.self, value: value)
                    .onPreferenceChange(MountedPreferenceLifecycleValueKey.self) { new in
                        received.append([new.number, new.ignoredPayload])
                    })
        }
        defer { host.close() }
        value = MountedPreferenceLifecycleValue(number: 0, ignoredPayload: 20, probe: probe)
        host.reload()
        value = MountedPreferenceLifecycleValue(number: 1, ignoredPayload: 30, probe: probe)
        host.reload()
        value = MountedPreferenceLifecycleValue(number: 1, ignoredPayload: 31, probe: probe)
        host.reload()
        value = MountedPreferenceLifecycleValue(number: 2, ignoredPayload: 40, probe: probe)
        host.reload()

        // This pins the retained Windows value policy, not native SwiftUI
        // parity for Equatable types with ignored reference or payload fields.
        XCTAssertEqual(received, [[0, 10], [1, 30], [2, 40]])
        XCTAssertEqual(probe.comparisons, [[0, 10, 0, 20], [0, 10, 1, 30], [1, 30, 1, 31], [1, 30, 2, 40]])
    }

    func testOldPreferencePayloadCleanupRunsAfterTheAdoptedBatchAndQueuesReentry() async {
        let probe = MountedPreferenceLifecycleProbe()
        var observed = MountedPreferenceLifecycleValue(number: 0, probe: probe)
        var cleanupWasBuilding = false
        var payloadWasAliveDuringAction = false
        observed.payload = MountedPreferenceLifecyclePayload(
            onRelease: {
                probe.events.append("release.begin")
                cleanupWasBuilding = probe.host?.componentHost.isBuilding == true
                observed = MountedPreferenceLifecycleValue(number: 2, probe: probe)
                probe.host?.reload()
                probe.events.append("release.end")
            })
        weak var oldPayload = observed.payload
        let host = MountedOnChangeTestHost {
            AnyView(
                HStack {
                    Color.clear
                        .preference(key: MountedPreferenceLifecycleValueKey.self, value: observed)
                        .onPreferenceChange(MountedPreferenceLifecycleValueKey.self) { value in
                            if value.number == 1 { payloadWasAliveDuringAction = oldPayload != nil }
                            probe.record("first", value: value.number)
                        }
                    Color.clear
                        .preference(key: MountedPreferenceLifecycleIntKey.self, value: observed.number)
                        .onPreferenceChange(MountedPreferenceLifecycleIntKey.self) { value in
                            probe.record("second", value: value)
                        }
                })
        }
        defer { host.close() }
        probe.host = host
        XCTAssertEqual(probe.events, ["first:0", "second:0"])
        probe.events.removeAll()
        observed = MountedPreferenceLifecycleValue(number: 1, probe: probe)
        XCTAssertNotNil(oldPayload)
        host.reload()

        XCTAssertEqual(probe.events, ["first:1", "second:1", "release.begin", "release.end", "first:2", "second:2"])
        XCTAssertTrue(payloadWasAliveDuringAction)
        XCTAssertTrue(cleanupWasBuilding)
        XCTAssertNil(oldPayload)
        XCTAssertEqual(probe.maximumCallbackDepth, 1)
    }

    func testAbandonedPreferenceActionCaptureCleanupCannotPublishItsValueOrReenterConstruction() async {
        let probe = MountedPreferenceLifecycleProbe()
        var capture: MountedPreferenceLifecyclePayload?
        var cleanupWasBuilding = false
        let host = MountedOnChangeTestHost {
            let captured = capture
            return AnyView(
                MountedPreferenceLifecycleConstructionLeaf(value: probe.value, probe: probe)
                    .preference(key: MountedPreferenceLifecycleValueKey.self, value: probe.comparedValue)
                    .onPreferenceChange(MountedPreferenceLifecycleValueKey.self) { value in
                        withExtendedLifetime(captured) {}
                        probe.record("change", value: value.number)
                    })
        }
        defer { host.close() }
        probe.host = host
        probe.events.removeAll()
        capture = MountedPreferenceLifecyclePayload(
            onRelease: {
                probe.events.append("release.begin")
                cleanupWasBuilding = probe.host?.componentHost.isBuilding == true
                probe.value = 3
                probe.host?.reload()
                probe.events.append("release.end")
            })
        weak var oldCapture = capture
        probe.onConstruct = {
            guard probe.value == 1 else { return }
            probe.onConstruct = nil
            capture = nil
            probe.value = 2
            probe.host?.reload()
        }
        probe.value = 1
        host.reload()

        XCTAssertEqual(probe.events, ["release.begin", "release.end", "change:3"])
        XCTAssertTrue(cleanupWasBuilding)
        XCTAssertNil(oldCapture)
        XCTAssertEqual(probe.maximumConstructionDepth, 1)
        XCTAssertEqual(labels(in: host.runtime.root), ["value=3"])
        XCTAssertFalse(probe.comparisons.contains { $0[0] == 1 || $0[2] == 1 })
    }

    func testUnmountAndCloseReleaseRegistryHistoryWithoutInvalidatingRetainedNodeMetadata() async {
        for closesDirectly in [false, true] {
            var isMounted = true
            var releaseCount = 0
            var value: MountedPreferenceLifecycleValue? = MountedPreferenceLifecycleValue(
                number: 0, payload: MountedPreferenceLifecyclePayload(onRelease: { releaseCount += 1 }))
            weak var payload = value?.payload
            var actions = 0
            let host = MountedOnChangeTestHost {
                if isMounted, let value {
                    return AnyView(
                        Color.clear
                            .preference(key: MountedPreferenceLifecycleValueKey.self, value: value)
                            .onPreferenceChange(MountedPreferenceLifecycleValueKey.self) { _ in actions += 1 })
                }
                return AnyView(EmptyView())
            }
            defer { host.close() }
            var retainedNode = host.runtime.root.children.first
            XCTAssertNotNil(retainedNode)
            value = nil
            if closesDirectly {
                host.close()
            } else {
                isMounted = false
                host.reload()
            }

            // The registry must retire its history, but a node intentionally
            // kept by a caller still owns its ordinary preference metadata.
            XCTAssertNotNil(payload)
            withExtendedLifetime(retainedNode) {}
            retainedNode = nil
            XCTAssertNil(payload, "Unmount must release registry history before host close")
            XCTAssertEqual(releaseCount, 1)
            XCTAssertEqual(actions, 1)
            host.close()
            XCTAssertEqual(host.coordinator.registry.liveOwnerCount, 0)
            XCTAssertEqual(host.coordinator.registry.retiringOwnerCount, 0)
        }
    }

    func testGeometrySubtreeNotifiesItsInnerObserverWhileOuterObservationWaitsForRootRefresh() async {
        var preference = 10
        var innerValues: [Int] = []
        var outerValues: [Int] = []
        let host = MountedOnChangeTestHost {
            AnyView(
                GeometryReader { proxy in
                    Text("width=\(Int(proxy.size.width))")
                        .preference(key: MountedPreferenceLifecycleIntKey.self, value: preference)
                        .onPreferenceChange(MountedPreferenceLifecycleIntKey.self) { innerValues.append($0) }
                }
                .onPreferenceChange(MountedPreferenceLifecycleIntKey.self) { outerValues.append($0) })
        }
        defer { host.close() }
        host.render()
        XCTAssertEqual(innerValues, [10])
        XCTAssertEqual(outerValues, [10])
        preference = 20
        host.runtime.root.frame = Rect(x: 0, y: 0, width: 500, height: 300)
        host.render()
        host.render()

        XCTAssertEqual(labels(in: host.runtime.root), ["width=500"])
        XCTAssertEqual(innerValues, [10, 20])
        XCTAssertEqual(outerValues, [10], "A subtree-only build has not reevaluated the outer observer")

        // This records the current Windows refresh boundary. It does not
        // claim native SwiftUI parity or automatic upward preference delivery.
        // The shared test host has a fixed seed canvas, so a model preference
        // separates outer refresh from the reader's subsequent layout pass.
        host.reload()
        host.render()
        XCTAssertEqual(innerValues, [10, 20])
        XCTAssertEqual(outerValues, [10, 20])
        XCTAssertEqual(labels(in: host.runtime.root), ["width=500"])
        XCTAssertFalse(host.componentHost.isBuilding)
    }

    private func labels(in node: ViewNode) -> [String] {
        (node.text.map { [$0] } ?? []) + node.children.flatMap { labels(in: $0) }
    }
}
