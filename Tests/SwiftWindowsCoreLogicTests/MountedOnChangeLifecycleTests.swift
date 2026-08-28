import SwiftWindowsCore
@preconcurrency import XCTest

@testable import SwiftWindowsUI
@testable import WinSwiftUI

@MainActor
private final class OnChangeLifecycleProbe {
    weak var host: MountedOnChangeTestHost?
    weak var runtime: RetainedViewRuntime?
    var value = 0
    var events: [String] = []
    var constructionDepth = 0
    var maximumConstructionDepth = 0
    var constructionCount = 0
    var onConstruct: (@MainActor () -> Void)?
    var onCompare: (@MainActor () -> Void)?
    var state: Binding<Int>?
    var callbackDepth = 0
    var maximumCallbackDepth = 0

    func record(_ name: String, old: Int, new: Int, action: () -> Void = {}) {
        callbackDepth += 1
        maximumCallbackDepth = max(maximumCallbackDepth, callbackDepth)
        defer { callbackDepth -= 1 }
        events.append("\(name):\(old)->\(new)")
        action()
    }
}

@MainActor
private struct OnChangeConstructionLeaf: View {
    typealias Body = Never
    let value: Int
    let probe: OnChangeLifecycleProbe

    var body: Never { fatalError("The construction leaf has no body") }

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

private struct OnChangeComparedValue: Equatable {
    let number: Int
    let probe: OnChangeLifecycleProbe
    var ignoredPayload = 0

    static func == (lhs: Self, rhs: Self) -> Bool {
        MainActor.assumeIsolated {
            lhs.probe.onCompare?()
            return lhs.number == rhs.number
        }
    }
}

@MainActor
private final class OnChangeLifetimePayload {
    private let onRelease: @MainActor () -> Void

    init(onRelease: @escaping @MainActor () -> Void = {}) { self.onRelease = onRelease }

    isolated deinit { onRelease() }
}

private struct OnChangePayloadValue: Equatable {
    let number: Int
    let payload: OnChangeLifetimePayload?

    static func == (lhs: Self, rhs: Self) -> Bool { lhs.number == rhs.number }
}

private struct OnChangeIgnoredPayloadValue: Equatable {
    let number: Int
    let ignoredPayload: Int

    static func == (lhs: Self, rhs: Self) -> Bool { lhs.number == rhs.number }
}

@MainActor
private struct OnChangeCascadeView: View {
    let probe: OnChangeLifecycleProbe
    @State private var value = 0

    var body: some View {
        let binding = $value
        probe.state = binding
        return HStack {
            Color.clear.onChange(of: value) { old, new in
                probe.record(
                    "first", old: old, new: new,
                    action: {
                        if new == 1 { binding.wrappedValue = 2 }
                    })
            }
            Color.clear.onChange(of: value) { old, new in
                probe.record("second", old: old, new: new)
            }
        }
    }
}

@MainActor
private struct OnChangeUnusedComponentView: View {
    typealias Body = Never
    let probe: OnChangeLifecycleProbe

    var body: Never { fatalError("The unused component probe has no body") }

    func makeComponent(context: ViewBuildContext) -> Component {
        _ = makeViewComponent(
            Color.clear.onChange(of: probe.value, initial: true) { _, _ in probe.events.append("unused") },
            context: context.withViewIdentityRole(.overlay))
        return Component { _ in Controls.label("used") }
    }
}

@MainActor
final class MountedOnChangeLifecycleTests: XCTestCase {
    func testActionsSeeAdoptedNodesAfterConstructionAndBeforeRequestCompletion() async {
        let probe = OnChangeLifecycleProbe()
        var labelsDuringActions: [[String]] = []
        var depthsDuringActions: [Int] = []
        let host = MountedOnChangeTestHost {
            AnyView(
                OnChangeConstructionLeaf(value: probe.value, probe: probe)
                    .onChange(of: probe.value, initial: true) { old, new in
                        labelsDuringActions.append(probe.runtime.map { self.labels(in: $0.root) } ?? [])
                        depthsDuringActions.append(probe.constructionDepth)
                        probe.record("change", old: old, new: new)
                    })
        }
        defer { host.close() }
        probe.host = host
        host.componentHost.onReloadCompleted = { probe.events.append("completed") }
        probe.value = 1
        host.reload()

        XCTAssertEqual(labelsDuringActions, [["value=0"], ["value=1"]])
        XCTAssertEqual(depthsDuringActions, [0, 0])
        XCTAssertEqual(probe.events, ["change:0->0", "change:0->1", "completed"])
        XCTAssertFalse(host.componentHost.isBuilding)
    }

    func testSupersededConstructionDoesNotAdvanceTheLastAdoptedValue() async {
        let probe = OnChangeLifecycleProbe()
        let host = MountedOnChangeTestHost {
            AnyView(
                OnChangeConstructionLeaf(value: probe.value, probe: probe)
                    .onChange(of: probe.value) { old, new in probe.record("change", old: old, new: new) })
        }
        defer { host.close() }
        probe.host = host
        probe.onConstruct = {
            guard probe.value == 1 else { return }
            probe.onConstruct = nil
            probe.value = 2
            probe.host?.reload()
        }
        probe.value = 1
        host.reload()

        XCTAssertEqual(probe.events, ["change:0->2"])
        XCTAssertEqual(labels(in: host.runtime.root), ["value=2"])
        XCTAssertEqual(probe.constructionCount, 3)
        XCTAssertEqual(probe.maximumConstructionDepth, 1)
        host.reload()
        XCTAssertEqual(probe.events, ["change:0->2"])
    }

    func testCloseDuringConstructionDiscardsItsPendingAction() async {
        let probe = OnChangeLifecycleProbe()
        let host = MountedOnChangeTestHost {
            AnyView(
                OnChangeConstructionLeaf(value: probe.value, probe: probe)
                    .onChange(of: probe.value) { old, new in probe.record("change", old: old, new: new) })
        }
        defer { host.close() }
        probe.host = host
        probe.onConstruct = { probe.host?.close() }
        probe.value = 1
        host.reload()

        XCTAssertTrue(host.isClosed)
        XCTAssertTrue(probe.events.isEmpty)
        XCTAssertTrue(host.runtime.root.children.isEmpty)
        XCTAssertEqual(host.coordinator.registry.liveOwnerCount, 0)
        XCTAssertFalse(host.componentHost.isBuilding)
    }

    func testRejectedViewThatFitsCandidateHasNoInitialDelivery() async {
        var events: [String] = []
        let host = MountedOnChangeTestHost {
            AnyView(
                ViewThatFits(in: .horizontal) {
                    Color.red.frame(width: 800, height: 40)
                        .onChange(of: 1, initial: true) { _, _ in events.append("rejected") }
                    Color.blue.frame(width: 20, height: 40)
                        .onChange(of: 1, initial: true) { _, _ in events.append("selected") }
                })
        }
        defer { host.close() }
        host.render()
        host.reload()
        XCTAssertEqual(events, ["selected"])
    }

    func testRejectedDeclaredCandidateKeepsOnlyItsPreviousAdoptedHistory() async {
        var value = 1
        var primaryFits = true
        var events: [String] = []
        let host = MountedOnChangeTestHost {
            AnyView(
                ViewThatFits(in: .horizontal) {
                    Color.red.frame(width: primaryFits ? 20 : 800, height: 40)
                        .onChange(of: value, initial: true) { old, new in
                            events.append("primary:\(old)->\(new)")
                        }
                    Color.blue.frame(width: 20, height: 40)
                        .onChange(of: value, initial: true) { old, new in
                            events.append("fallback:\(old)->\(new)")
                        }
                })
        }
        defer { host.close() }
        XCTAssertEqual(events, ["primary:1->1"])
        value = 2
        primaryFits = false
        host.reload()
        XCTAssertEqual(events, ["primary:1->1", "fallback:2->2"])
        value = 3
        primaryFits = true
        host.reload()
        XCTAssertEqual(events, ["primary:1->1", "fallback:2->2", "primary:1->3"])
    }

    func testDeclaringAnUnusedComponentDoesNotAdmitAnObserver() async {
        let probe = OnChangeLifecycleProbe()
        let host = MountedOnChangeTestHost { AnyView(OnChangeUnusedComponentView(probe: probe)) }
        defer { host.close() }
        probe.value = 1
        host.reload()
        host.render()
        XCTAssertTrue(probe.events.isEmpty)
        XCTAssertEqual(labels(in: host.runtime.root), ["used"])
    }

    func testEqualityClosingTheHostCannotContinueIntoTheAction() async {
        let probe = OnChangeLifecycleProbe()
        let host = MountedOnChangeTestHost {
            AnyView(
                Color.clear.onChange(of: OnChangeComparedValue(number: probe.value, probe: probe)) { _, _ in
                    probe.events.append("action")
                })
        }
        defer { host.close() }
        probe.host = host
        probe.onCompare = {
            probe.onCompare = nil
            probe.events.append("compare")
            probe.host?.close()
        }
        probe.value = 1
        host.reload()

        XCTAssertEqual(probe.events, ["compare"])
        XCTAssertTrue(host.isClosed)
        XCTAssertEqual(host.coordinator.registry.liveOwnerCount, 0)
    }

    func testEqualityReentryFinishesTheAdoptedActionBeforeTheQueuedBuild() async {
        let probe = OnChangeLifecycleProbe()
        let host = MountedOnChangeTestHost {
            AnyView(
                Color.clear.onChange(of: OnChangeComparedValue(number: probe.value, probe: probe)) { old, new in
                    probe.record("change", old: old.number, new: new.number)
                })
        }
        defer { host.close() }
        probe.host = host
        probe.onCompare = {
            probe.onCompare = nil
            probe.events.append("compare")
            probe.value = 2
            probe.host?.reload()
        }
        probe.value = 1
        host.reload()

        XCTAssertEqual(probe.events, ["compare", "change:0->1", "change:1->2"])
        XCTAssertEqual(probe.maximumCallbackDepth, 1)
        XCTAssertFalse(host.componentHost.isBuilding)
    }

    func testStateMutationFromTheFirstActionDoesNotSkipTheSecondAdoptedObserver() async throws {
        let probe = OnChangeLifecycleProbe()
        let host = MountedOnChangeTestHost { AnyView(OnChangeCascadeView(probe: probe)) }
        defer { host.close() }
        let binding = try XCTUnwrap(probe.state)
        binding.wrappedValue = 1

        XCTAssertEqual(probe.events, ["first:0->1", "second:0->1", "first:1->2", "second:1->2"])
        XCTAssertEqual(binding.wrappedValue, 2)
        XCTAssertEqual(probe.maximumCallbackDepth, 1)
        XCTAssertFalse(host.componentHost.isBuilding)
    }

    func testEqualityEquivalentPayloadKeepsThePriorBaselineUntilAChange() async {
        var value = OnChangeIgnoredPayloadValue(number: 0, ignoredPayload: 10)
        var changes: [[Int]] = []
        let host = MountedOnChangeTestHost {
            AnyView(
                Color.clear.onChange(of: value) { old, new in
                    changes.append([old.number, old.ignoredPayload, new.number, new.ignoredPayload])
                })
        }
        defer { host.close() }
        value = OnChangeIgnoredPayloadValue(number: 0, ignoredPayload: 20)
        host.reload()
        XCTAssertTrue(changes.isEmpty)
        value = OnChangeIgnoredPayloadValue(number: 1, ignoredPayload: 30)
        host.reload()
        value = OnChangeIgnoredPayloadValue(number: 1, ignoredPayload: 31)
        host.reload()
        value = OnChangeIgnoredPayloadValue(number: 2, ignoredPayload: 40)
        host.reload()

        // This preserves the previous Windows value policy. A native paired
        // fixture is still needed before claiming SwiftUI equivalence.
        XCTAssertEqual(changes, [[0, 10, 1, 30], [1, 30, 2, 40]])
    }

    func testEqualComparisonReentryCannotRestoreOverTheQueuedUnequalChange() async {
        let probe = OnChangeLifecycleProbe()
        var payload = 10
        var changes: [[Int]] = []
        let host = MountedOnChangeTestHost {
            let value = OnChangeComparedValue(number: probe.value, probe: probe, ignoredPayload: payload)
            return AnyView(
                Color.clear.onChange(of: value) { old, new in
                    changes.append([old.number, old.ignoredPayload, new.number, new.ignoredPayload])
                })
        }
        defer { host.close() }
        probe.host = host
        probe.onCompare = {
            probe.onCompare = nil
            probe.value = 1
            payload = 30
            probe.host?.reload()
        }
        payload = 20
        host.reload()
        XCTAssertEqual(changes, [[0, 10, 1, 30]])
        probe.value = 2
        payload = 40
        host.reload()
        XCTAssertEqual(changes, [[0, 10, 1, 30], [1, 30, 2, 40]])
        XCTAssertFalse(host.componentHost.isBuilding)
    }

    func testClosingFromTheFirstActionRevokesTheRemainingAdoptedObservers() async {
        let probe = OnChangeLifecycleProbe()
        let host = MountedOnChangeTestHost {
            AnyView(
                HStack {
                    Color.clear.onChange(of: probe.value) { old, new in
                        probe.record("first", old: old, new: new)
                        probe.host?.close()
                    }
                    Color.clear.onChange(of: probe.value) { old, new in
                        probe.record("second", old: old, new: new)
                    }
                })
        }
        defer { host.close() }
        probe.host = host
        probe.value = 1
        host.reload()

        XCTAssertEqual(probe.events, ["first:0->1"])
        XCTAssertTrue(host.isClosed)
        XCTAssertEqual(host.coordinator.registry.liveOwnerCount, 0)
    }

    func testOldValueCleanupRunsAfterTheAdoptedBatchAndQueuesReentry() async {
        let probe = OnChangeLifecycleProbe()
        var observed = OnChangePayloadValue(number: 0, payload: nil)
        var cleanupWasBuilding = false
        var payloadWasAliveDuringAction = false
        observed = OnChangePayloadValue(
            number: 0,
            payload: OnChangeLifetimePayload {
                probe.events.append("release")
                cleanupWasBuilding = probe.host?.componentHost.isBuilding == true
                observed = OnChangePayloadValue(number: 2, payload: nil)
                probe.host?.reload()
            })
        weak var oldPayload = observed.payload
        let host = MountedOnChangeTestHost {
            AnyView(
                HStack {
                    Color.clear.onChange(of: observed) { old, new in
                        if old.number == 0 { payloadWasAliveDuringAction = old.payload != nil && oldPayload != nil }
                        probe.record("first", old: old.number, new: new.number)
                    }
                    Color.clear.onChange(of: observed.number) { old, new in
                        probe.record("second", old: old, new: new)
                    }
                })
        }
        defer { host.close() }
        probe.host = host
        observed = OnChangePayloadValue(number: 1, payload: nil)
        XCTAssertNotNil(oldPayload)
        host.reload()

        XCTAssertEqual(probe.events, ["first:0->1", "second:0->1", "release", "first:1->2", "second:1->2"])
        XCTAssertTrue(payloadWasAliveDuringAction)
        XCTAssertTrue(cleanupWasBuilding)
        XCTAssertNil(oldPayload)
        XCTAssertEqual(probe.maximumCallbackDepth, 1)
    }

    func testAbandonedActionCaptureCleanupCannotPublishItsValueOrReenterABuild() async {
        let probe = OnChangeLifecycleProbe()
        var capture: OnChangeLifetimePayload?
        var cleanupWasBuilding = false
        let host = MountedOnChangeTestHost {
            let captured = capture
            return AnyView(
                OnChangeConstructionLeaf(value: probe.value, probe: probe)
                    .onChange(of: probe.value) { old, new in
                        withExtendedLifetime(captured) {}
                        probe.record("change", old: old, new: new)
                    })
        }
        defer { host.close() }
        probe.host = host
        capture = OnChangeLifetimePayload {
            probe.events.append("release")
            cleanupWasBuilding = probe.host?.componentHost.isBuilding == true
            probe.value = 3
            probe.host?.reload()
        }
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

        XCTAssertEqual(probe.events, ["release", "change:0->3"])
        XCTAssertTrue(cleanupWasBuilding)
        XCTAssertNil(oldCapture)
        XCTAssertEqual(probe.maximumConstructionDepth, 1)
        XCTAssertEqual(labels(in: host.runtime.root), ["value=3"])
    }

    func testUnmountAndCloseReleaseRegistryOwnedLastValues() async {
        for closesDirectly in [false, true] {
            var isMounted = true
            var releaseCount = 0
            var value: OnChangePayloadValue? = OnChangePayloadValue(
                number: 0, payload: OnChangeLifetimePayload { releaseCount += 1 })
            weak var payload = value?.payload
            var actions = 0
            let host = MountedOnChangeTestHost {
                if isMounted, let value {
                    return AnyView(Color.clear.onChange(of: value) { _, _ in actions += 1 })
                }
                return AnyView(EmptyView())
            }
            value = nil
            XCTAssertNotNil(payload)
            if closesDirectly {
                host.close()
            } else {
                isMounted = false
                host.reload()
                XCTAssertNil(payload, "Unmount must release history without relying on host close")
                XCTAssertEqual(releaseCount, 1)
                host.close()
            }
            XCTAssertNil(payload)
            XCTAssertEqual(releaseCount, 1)
            XCTAssertEqual(actions, 0)
            XCTAssertEqual(host.coordinator.registry.liveOwnerCount, 0)
        }
    }

    func testGeometrySubtreeRebuildPreservesHistoryAndRemovalRetiresItsObserver() async {
        var showsReader = true
        var changes: [[Int]] = []
        let host = MountedOnChangeTestHost {
            if showsReader {
                return AnyView(
                    GeometryReader { proxy in
                        Color.clear.onChange(of: Int(proxy.size.width), initial: true) { old, new in
                            changes.append([old, new])
                        }
                    })
            }
            return AnyView(EmptyView())
        }
        defer { host.close() }
        host.render()
        XCTAssertEqual(changes, [[400, 400]])
        host.runtime.root.frame = Rect(x: 0, y: 0, width: 500, height: 300)
        host.render()
        host.render()
        XCTAssertEqual(changes, [[400, 400], [400, 500]])
        showsReader = false
        host.reload()
        host.runtime.root.frame = Rect(x: 0, y: 0, width: 600, height: 300)
        host.render()
        XCTAssertEqual(changes, [[400, 400], [400, 500]])
    }

    private func labels(in node: ViewNode) -> [String] {
        (node.text.map { [$0] } ?? []) + node.children.flatMap { labels(in: $0) }
    }
}
