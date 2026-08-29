import SwiftWindowsCore
@preconcurrency import XCTest

@testable import SwiftWindowsUI
@testable import WinSwiftUI

@MainActor
private final class TaskReentryWork {
    var starts: [Int] = []
    var cancellations: [Int] = []
    var completions: [Int] = []
    var cancelledAtEntry: [Int: Bool] = [:]
    var ready: [Int: XCTestExpectation] = [:]
    var finished: [Int: XCTestExpectation] = [:]
    var onCancellation: (@MainActor (Int) -> Void)?
    var ignoresCancellation = false
    private var suspensions: [Int: CheckedContinuation<Void, Never>] = [:]
    private var isFinishing = false

    func run(_ version: Int, holding payload: TaskReentryPayload?) async {
        starts.append(version)
        cancelledAtEntry[version] = Task.isCancelled
        await withTaskCancellationHandler(
            operation: {
                await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                    if isFinishing || (Task.isCancelled && !ignoresCancellation) {
                        continuation.resume()
                    } else {
                        suspensions[version] = continuation
                    }
                    // Positive readiness means the handler and suspension are
                    // installed, not just that the async closure was enqueued.
                    ready.removeValue(forKey: version)?.fulfill()
                }
            },
            onCancel: {
                // These tests cancel from a synchronous MainActor host operation
                // after readiness, or install an already-cancelled action on it.
                MainActor.assumeIsolated { [weak self] in self?.cancel(version) }
            })
        withExtendedLifetime(payload) {}
        completions.append(version)
        finished.removeValue(forKey: version)?.fulfill()
    }

    private func cancel(_ version: Int) {
        guard !cancellations.contains(version) else { return }
        cancellations.append(version)
        let continuation = ignoresCancellation ? nil : suspensions.removeValue(forKey: version)
        onCancellation?(version)
        continuation?.resume()
    }

    func releaseSuspensions() {
        isFinishing = true
        let pending = Array(suspensions.values)
        suspensions.removeAll()
        for continuation in pending { continuation.resume() }
    }
}

@MainActor
private final class TaskReentryPayload {
    let onRelease: @MainActor () -> Void

    init(onRelease: @escaping @MainActor () -> Void = {}) { self.onRelease = onRelease }

    isolated deinit { onRelease() }
}

@MainActor
private final class TaskReentryHashGate {
    var action: (@MainActor () -> Void)?
    var firings = 0

    func fire() {
        guard let action else { return }
        self.action = nil
        firings += 1
        action()
    }
}

private struct TaskReentryKey: Hashable {
    let value: Int
    let gate: TaskReentryHashGate

    static func == (lhs: Self, rhs: Self) -> Bool { lhs.value == rhs.value }

    func hash(into hasher: inout Hasher) {
        hasher.combine(value)
        MainActor.assumeIsolated { gate.fire() }
    }
}

private struct TaskReentryID: Equatable {
    let value: Int
    let probe: TaskReentryProbe

    static func == (lhs: Self, rhs: Self) -> Bool {
        MainActor.assumeIsolated {
            lhs.probe.comparisons.append([lhs.value, rhs.value])
            lhs.probe.onCompare?()
            return lhs.value == rhs.value
        }
    }
}

@MainActor
private final class TaskReentryProbe {
    let work = TaskReentryWork()
    let hashing = TaskReentryHashGate()
    weak var host: MountedOnChangeTestHost?
    var value = 0
    var key = 7
    var width = 20.0
    var comparisons: [[Int]] = []
    var constructionCount = 0
    var constructionDepth = 0
    var maximumConstructionDepth = 0
    var includeChildCell = false
    var childCell: MountedStateCell<Int>?
    var nestedCell: MountedStateCell<Int>?
    var payload: TaskReentryPayload?
    var onConstruct: (@MainActor () -> Void)?
    var onCompare: (@MainActor () -> Void)?
    var onLookup: (@MainActor (StateMountEpoch) -> Void)?

    func close() {
        hashing.action = nil
        onConstruct = nil
        onCompare = nil
        onLookup = nil
        work.onCancellation = nil
        host?.close()
        work.releaseSuspensions()
    }
}

private enum TaskReentryChildOwner {}
private enum TaskReentryNestedOwner {}
private enum TaskReentryCellSlot {}

@MainActor
private struct TaskReentryLeaf: View {
    typealias Body = Never
    let value: Int
    let width: Double
    let probe: TaskReentryProbe

    var body: Never { fatalError("The construction fixture supplies its retained component") }

    func makeComponent(context: ViewBuildContext) -> Component {
        Component { _ in
            probe.constructionCount += 1
            probe.constructionDepth += 1
            probe.maximumConstructionDepth = max(probe.maximumConstructionDepth, probe.constructionDepth)
            defer { probe.constructionDepth -= 1 }
            let epoch = context.viewIdentity.installedOwner?.installationEpoch
            if probe.includeChildCell, let epoch {
                let identity = context.retainedViewIdentity.appending(.role(.overlay)).appending(
                    .view(ObjectIdentifier(TaskReentryChildOwner.self)))
                let slot = StatePropertySlot(concreteTypes: [ObjectIdentifier(TaskReentryCellSlot.self)])
                probe.childCell = epoch.owner(at: identity)?.resolve(at: slot) { 81 }
            }
            probe.onConstruct?()
            if let onLookup = probe.onLookup {
                probe.onLookup = nil
                guard let epoch else {
                    XCTFail("The mounted component must have its real installation epoch")
                    return Controls.label("uninstalled")
                }
                // All ordinary source installation has completed. The next
                // authored key access belongs to the task observer resolver.
                probe.hashing.action = { onLookup(epoch) }
            }
            let node = Controls.panel(preferredSize: Size(width: width, height: 24), isHitTestVisible: false)
            node.accessibilityIdentifier = "task.reentry.\(value)"
            return node
        }
    }
}

@MainActor
private struct TaskReentryView: View {
    typealias Body = Never
    let probe: TaskReentryProbe

    var body: Never { fatalError("The fixture delegates to one public task modifier") }

    func makeComponent(context: ViewBuildContext) -> Component {
        let value = probe.value
        let work = probe.work
        let payload = probe.payload
        let child = makeViewComponent(
            TaskReentryLeaf(value: value, width: probe.width, probe: probe)
                .task(id: TaskReentryID(value: value, probe: probe)) {
                    await work.run(value, holding: payload)
                }, context: context)
        return Component { runtime in
            defer { probe.hashing.action = nil }
            return child.makeNode(runtime: runtime)
        }
    }
}

@MainActor
private struct TaskReentryUnusedView: View {
    typealias Body = Never
    let probe: TaskReentryProbe

    var body: Never { fatalError("The unused component is deliberately not materialized") }

    func makeComponent(context: ViewBuildContext) -> Component {
        _ = makeViewComponent(TaskReentryView(probe: probe), context: context.withViewIdentityRole(.overlay))
        return Component { _ in Controls.label("materialized") }
    }
}

@MainActor
private final class TaskRetainedSourceProbe {
    let node = Controls.panel(preferredSize: Size(width: 20, height: 24), isHitTestVisible: false)
    let work = TaskReentryWork()
    weak var host: MountedOnChangeTestHost?
    var isCandidate = false
    var version = 0
    var payload: TaskReentryPayload?
    var afterMaterialized: (@MainActor () -> Void)?
}

@MainActor
private struct TaskRetainedSourceLeaf: View {
    typealias Body = Never
    let node: ViewNode

    var body: Never { fatalError("The fixture intentionally retains its construction node") }

    func makeComponent(context: ViewBuildContext) -> Component {
        Component { _ in node }
    }
}

@MainActor
private struct TaskRetainedSourceView: View {
    typealias Body = Never
    let probe: TaskRetainedSourceProbe

    var body: Never { fatalError("This internal producer tests candidate transport ownership") }

    func makeComponent(context: ViewBuildContext) -> Component {
        let version = probe.version
        let work = probe.work
        let payload = probe.payload
        let component = makeViewComponent(
            TaskRetainedSourceLeaf(node: probe.node).task(id: version) {
                await work.run(version, holding: payload)
            }, context: context)
        return Component { runtime in
            let node = component.makeNode(runtime: runtime)
            probe.afterMaterialized?()
            return node
        }
    }
}

@MainActor
final class MountedTaskIDReentryTests: XCTestCase {
    func testUnmaterializedTaskComponentDoesNotCompareOrCreateWork() async {
        let probe = TaskReentryProbe()
        let unexpected = invertedStart(0, in: probe)
        let host = MountedOnChangeTestHost { AnyView(TaskReentryUnusedView(probe: probe)) }
        probe.host = host
        defer { probe.close() }
        host.render()
        probe.value = 1
        host.reload()
        host.render()
        XCTAssertEqual(probe.constructionCount, 0)
        XCTAssertTrue(probe.comparisons.isEmpty)
        await fulfillment(of: [unexpected], timeout: 0.05)
        XCTAssertTrue(probe.work.starts.isEmpty)
        XCTAssertTrue(probe.work.cancellations.isEmpty)
    }

    func testRejectedViewThatFitsCandidateDoesNotStartItsTask() async {
        let rejected = TaskReentryProbe()
        rejected.width = 800
        let selected = TaskReentryProbe()
        selected.value = 2
        let noRejected = invertedStart(0, in: rejected)
        let selectedReady = expectStart(2, in: selected)
        let host = MountedOnChangeTestHost {
            AnyView(
                ViewThatFits(in: .horizontal) {
                    TaskReentryView(probe: rejected)
                    TaskReentryView(probe: selected)
                })
        }
        selected.host = host
        defer {
            selected.close()
            rejected.close()
        }
        host.render()
        await fulfillment(of: [selectedReady], timeout: 2)
        await fulfillment(of: [noRejected], timeout: 0.05)
        XCTAssertEqual(selected.work.starts, [2])
        XCTAssertTrue(rejected.work.starts.isEmpty)
        XCTAssertTrue(rejected.comparisons.isEmpty)
    }

    func testSupersededConstructionKeepsTheLastAdoptedTaskBaseline() async {
        let probe = TaskReentryProbe()
        let host = makeHost(probe)
        defer { probe.close() }
        let firstReady = expectStart(0, in: probe)
        host.render()
        await fulfillment(of: [firstReady], timeout: 2)
        let nextReady = expectStart(2, in: probe)
        probe.onConstruct = {
            probe.onConstruct = nil
            probe.value = 2
            probe.host?.reload()
        }
        probe.value = 1
        host.reload()
        XCTAssertEqual(probe.comparisons, [[0, 2]])
        XCTAssertEqual(probe.work.cancellations, [0])
        XCTAssertEqual(probe.constructionCount, 3)
        XCTAssertEqual(probe.maximumConstructionDepth, 1)
        await fulfillment(of: [nextReady], timeout: 2)
        XCTAssertEqual(probe.work.starts, [0, 2])
        XCTAssertFalse(host.componentHost.isBuilding)
    }

    func testCloseDuringConstructionDiscardsTheTaskProposal() async {
        let probe = TaskReentryProbe()
        let host = makeHost(probe)
        defer { probe.close() }
        let ready = expectStart(0, in: probe)
        host.render()
        await fulfillment(of: [ready], timeout: 2)
        let rejected = invertedStart(1, in: probe)
        probe.onConstruct = { probe.host?.close() }
        probe.value = 1
        host.reload()
        XCTAssertTrue(host.isClosed)
        XCTAssertTrue(probe.comparisons.isEmpty)
        XCTAssertEqual(probe.work.starts, [0])
        XCTAssertEqual(probe.work.cancellations, [0])
        XCTAssertEqual(host.coordinator.registry.liveOwnerCount, 0)
        XCTAssertTrue(host.runtime.root.children.isEmpty)
        await fulfillment(of: [rejected], timeout: 0.05)
        XCTAssertEqual(probe.work.starts, [0])
    }

    func testCloseDuringObserverOwnerLookupDoesNotReachTaskComparison() async {
        let probe = TaskReentryProbe()
        let host = makeHost(probe)
        defer { probe.close() }
        let ready = expectStart(0, in: probe)
        host.render()
        await fulfillment(of: [ready], timeout: 2)
        let rejected = invertedStart(1, in: probe)
        probe.onLookup = { _ in probe.host?.close() }
        probe.value = 1
        host.reload()
        XCTAssertEqual(probe.hashing.firings, 1)
        XCTAssertTrue(host.isClosed)
        XCTAssertTrue(probe.comparisons.isEmpty)
        XCTAssertEqual(probe.work.starts, [0])
        XCTAssertEqual(probe.work.cancellations, [0])
        XCTAssertEqual(host.coordinator.registry.liveOwnerCount, 0)
        await fulfillment(of: [rejected], timeout: 0.05)
        XCTAssertEqual(probe.work.starts, [0])
    }

    func testSupersessionDuringObserverLookupDoesNotPublishTheRejectedID() async {
        let probe = TaskReentryProbe()
        let host = makeHost(probe)
        defer { probe.close() }
        let ready = expectStart(0, in: probe)
        host.render()
        await fulfillment(of: [ready], timeout: 2)
        let nextReady = expectStart(2, in: probe)
        probe.onLookup = { _ in
            probe.value = 2
            probe.host?.reload()
        }
        probe.value = 1
        host.reload()
        XCTAssertEqual(probe.hashing.firings, 1)
        XCTAssertEqual(probe.comparisons, [[0, 2]])
        XCTAssertEqual(probe.work.cancellations, [0])
        await fulfillment(of: [nextReady], timeout: 2)
        XCTAssertEqual(probe.work.starts, [0, 2])
    }

    func testMaterializedObserverFallbackKeepsRunningTaskAndNestedOrdinaryWork() async throws {
        let probe = TaskReentryProbe()
        let host = makeHost(probe)
        defer { probe.close() }
        let ready = expectStart(0, in: probe)
        host.render()
        await fulfillment(of: [ready], timeout: 2)
        probe.onLookup = { epoch in self.resolveNestedCell(in: epoch, probe: probe) }
        probe.value = 1
        host.reload()
        XCTAssertEqual(probe.hashing.firings, 1)
        XCTAssertTrue(try XCTUnwrap(probe.nestedCell).isWritable)
        XCTAssertEqual(probe.nestedCell?.readValue(), 41)
        XCTAssertTrue(probe.comparisons.isEmpty)
        XCTAssertTrue(probe.work.cancellations.isEmpty)
        XCTAssertEqual(probe.work.starts, [0])

        let nextReady = expectStart(2, in: probe)
        probe.value = 2
        host.reload()
        XCTAssertEqual(probe.comparisons, [[0, 2]], "The rejected ID must not become the comparison baseline")
        await fulfillment(of: [nextReady], timeout: 2)
        XCTAssertEqual(probe.work.starts, [0, 2])
        XCTAssertEqual(probe.work.cancellations, [0])
    }

    func testPendingFallbackUsesCommittedActionWithoutKeepingUnrelatedChildState() async throws {
        let probe = TaskReentryProbe()
        probe.includeChildCell = true
        let host = makeHost(probe)
        defer { probe.close() }
        let child = try XCTUnwrap(probe.childCell)
        XCTAssertTrue(child.isWritable)
        probe.includeChildCell = false
        probe.onLookup = { epoch in self.resolveNestedCell(in: epoch, probe: probe) }
        probe.value = 1
        host.reload()
        XCTAssertEqual(probe.hashing.firings, 1)
        XCTAssertFalse(child.isWritable)
        XCTAssertEqual(child.readValue(), 81)
        XCTAssertTrue(try XCTUnwrap(probe.nestedCell).isWritable)
        XCTAssertTrue(probe.comparisons.isEmpty)
        let committedReady = expectStart(0, in: probe)
        host.render()
        await fulfillment(of: [committedReady], timeout: 2)
        XCTAssertEqual(probe.work.starts, [0], "A rejected declaration cannot replace the committed pending action")
    }

    func testRejectedFallbackCandidateDoesNotKeepAnOutgoingPhysicalTask() async {
        let primary = TaskReentryProbe()
        let fallback = TaskReentryProbe()
        fallback.value = 2
        let host = MountedOnChangeTestHost {
            AnyView(
                ViewThatFits(in: .horizontal) {
                    TaskReentryView(probe: primary).id(TaskReentryKey(value: 7, gate: primary.hashing))
                    TaskReentryView(probe: fallback)
                })
        }
        primary.host = host
        defer {
            primary.close()
            fallback.close()
        }
        let initialReady = expectStart(0, in: primary)
        host.render()
        await fulfillment(of: [initialReady], timeout: 2)
        primary.width = 800
        primary.value = 1
        primary.onLookup = { epoch in self.resolveNestedCell(in: epoch, probe: primary) }
        host.reload()
        XCTAssertEqual(primary.hashing.firings, 1)
        XCTAssertTrue(primary.comparisons.isEmpty)
        XCTAssertEqual(primary.work.cancellations, [0])
        let fallbackReady = expectStart(2, in: fallback)
        host.render()
        await fulfillment(of: [fallbackReady], timeout: 2)
        XCTAssertEqual(primary.work.starts, [0])
        XCTAssertEqual(fallback.work.starts, [2])
    }

    func testEqualityClosingTheHostDoesNotRestartTheProposedTask() async {
        let probe = TaskReentryProbe()
        let host = makeHost(probe)
        defer { probe.close() }
        let ready = expectStart(0, in: probe)
        host.render()
        await fulfillment(of: [ready], timeout: 2)
        let rejected = invertedStart(1, in: probe)
        probe.onCompare = {
            probe.onCompare = nil
            probe.host?.close()
        }
        probe.value = 1
        host.reload()
        XCTAssertEqual(probe.comparisons, [[0, 1]])
        XCTAssertTrue(host.isClosed)
        XCTAssertEqual(probe.work.cancellations, [0])
        XCTAssertEqual(probe.work.starts, [0])
        await fulfillment(of: [rejected], timeout: 0.05)
        XCTAssertEqual(probe.work.starts, [0])
    }

    func testEqualityReentryCompletesAcceptedAttemptBeforeQueuedReplacement() async {
        let probe = TaskReentryProbe()
        let host = makeHost(probe)
        defer { probe.close() }
        let ready = expectStart(0, in: probe)
        host.render()
        await fulfillment(of: [ready], timeout: 2)
        let firstAccepted = expectStart(1, in: probe)
        let secondAccepted = expectStart(2, in: probe)
        var completions: [Int] = []
        host.componentHost.onReloadCompleted = { completions.append(probe.value) }
        probe.onCompare = {
            probe.onCompare = nil
            probe.value = 2
            probe.host?.reload()
        }
        probe.value = 1
        host.reload()
        XCTAssertEqual(probe.comparisons, [[0, 1], [1, 2]])
        XCTAssertEqual(completions, [2, 2], "Both accepted requests finish; completion reads the current model")
        await fulfillment(of: [firstAccepted, secondAccepted], timeout: 2)
        XCTAssertEqual(probe.work.starts.sorted(), [0, 1, 2])
        XCTAssertEqual(probe.work.cancelledAtEntry[1], true)
        XCTAssertEqual(probe.work.cancelledAtEntry[2], false)
        XCTAssertEqual(probe.work.cancellations.sorted(), [0, 1])
    }

    func testEqualityKeyReplacementDoesNotBorrowTheDepartingTargetsAppearance() async throws {
        let probe = TaskReentryProbe()
        let host = makeHost(probe)
        defer { probe.close() }
        let ready = expectStart(0, in: probe)
        host.render()
        await fulfillment(of: [ready], timeout: 2)
        let original = try XCTUnwrap(host.runtime.root.children.first)
        let acceptedBeforeReplacement = expectStart(1, in: probe)
        let prematureReplacement = invertedStart(2, in: probe)
        probe.onCompare = {
            probe.onCompare = nil
            probe.key = 8
            probe.value = 2
            probe.host?.reload()
        }
        probe.value = 1
        host.reload()
        let replacement = try XCTUnwrap(host.runtime.root.children.first)
        XCTAssertFalse(replacement === original)
        XCTAssertFalse(replacement.hasAppeared)
        XCTAssertEqual(probe.comparisons, [[0, 1]])
        await fulfillment(of: [acceptedBeforeReplacement], timeout: 2)
        await fulfillment(of: [prematureReplacement], timeout: 0.05)
        XCTAssertEqual(probe.work.starts.sorted(), [0, 1])
        XCTAssertEqual(probe.work.cancelledAtEntry[1], true)

        let freshAppearance = expectStart(2, in: probe)
        host.render()
        await fulfillment(of: [freshAppearance], timeout: 2)
        XCTAssertEqual(probe.work.starts.sorted(), [0, 1, 2])
        XCTAssertEqual(probe.work.cancellations.sorted(), [0, 1])
        XCTAssertEqual(probe.work.cancelledAtEntry[2], false)
    }

    func testSynchronousCancellationClosingHostPreventsPostCancelLaunch() async {
        let probe = TaskReentryProbe()
        let host = makeHost(probe)
        defer { probe.close() }
        let ready = expectStart(0, in: probe)
        host.render()
        await fulfillment(of: [ready], timeout: 2)
        let rejected = invertedStart(1, in: probe)
        probe.work.onCancellation = { _ in probe.host?.close() }
        probe.value = 1
        host.reload()
        XCTAssertTrue(host.isClosed)
        XCTAssertEqual(probe.work.cancellations, [0])
        XCTAssertEqual(probe.work.starts, [0])
        XCTAssertTrue(host.runtime.root.children.isEmpty)
        await fulfillment(of: [rejected], timeout: 0.05)
        XCTAssertEqual(probe.work.starts, [0])
    }

    func testCancellationReentryCannotEraseTheLaterQueuedAttempt() async {
        let probe = TaskReentryProbe()
        let host = makeHost(probe)
        defer { probe.close() }
        let ready = expectStart(0, in: probe)
        host.render()
        await fulfillment(of: [ready], timeout: 2)
        let accepted = expectStart(1, in: probe)
        let latest = expectStart(2, in: probe)
        probe.work.onCancellation = { version in
            guard version == 0 else { return }
            probe.work.onCancellation = nil
            probe.value = 2
            probe.host?.reload()
        }
        probe.value = 1
        host.reload()
        await fulfillment(of: [accepted, latest], timeout: 2)
        XCTAssertEqual(probe.comparisons, [[0, 1], [1, 2]])
        XCTAssertEqual(probe.work.starts.sorted(), [0, 1, 2])
        XCTAssertEqual(probe.work.cancellations.sorted(), [0, 1])
        XCTAssertEqual(probe.work.cancelledAtEntry[2], false)
        XCTAssertFalse(host.isClosed)
        XCTAssertFalse(host.componentHost.isBuilding)
    }

    func testPhysicalCancellationReinsertWaitsForItsOwnAppearance() async throws {
        let probe = TaskReentryProbe()
        let host = makeHost(probe)
        defer { probe.close() }
        let ready = expectStart(0, in: probe)
        host.render()
        await fulfillment(of: [ready], timeout: 2)
        let outgoing = try XCTUnwrap(host.runtime.root.children.first)
        probe.work.onCancellation = { _ in
            probe.work.onCancellation = nil
            probe.value = 1
            probe.host?.reload()
        }
        // Single-child removal publishes the detached edge before its
        // cancellation hook. This does not rely on bulk-clear reentry.
        host.runtime.root.removeChild(outgoing)
        let replacement = try XCTUnwrap(host.runtime.root.children.first)
        XCTAssertFalse(replacement === outgoing)
        XCTAssertFalse(replacement.hasAppeared)
        XCTAssertEqual(probe.work.cancellations, [0])
        XCTAssertEqual(probe.work.starts, [0])
        let replacementReady = expectStart(1, in: probe)
        host.render()
        await fulfillment(of: [replacementReady], timeout: 2)
        XCTAssertEqual(probe.work.starts, [0, 1])
        XCTAssertEqual(probe.work.cancelledAtEntry[1], false)
    }

    func testPendingActionCaptureCleanupCanCloseBeforeReplacementLaunch() async {
        let probe = TaskReentryProbe()
        var releases = 0
        probe.payload = TaskReentryPayload {
            releases += 1
            probe.host?.close()
        }
        weak var payload = probe.payload
        let host = makeHost(probe)
        defer { probe.close() }
        let rejected = invertedStart(1, in: probe)
        probe.payload = nil
        XCTAssertNotNil(payload, "The accepted pending declaration intentionally owns its action")
        probe.value = 1
        host.reload()
        XCTAssertEqual(releases, 1)
        XCTAssertNil(payload)
        XCTAssertTrue(host.isClosed)
        XCTAssertTrue(probe.work.starts.isEmpty)
        XCTAssertTrue(probe.work.cancellations.isEmpty)
        await fulfillment(of: [rejected], timeout: 0.05)
        XCTAssertTrue(probe.work.starts.isEmpty)
    }

    func testAbandonedProposalReleasesItsActionCaptureWithoutCreatingWork() async {
        let probe = TaskReentryProbe()
        let host = makeHost(probe)
        defer { probe.close() }
        let ready = expectStart(0, in: probe)
        host.render()
        await fulfillment(of: [ready], timeout: 2)
        let released = expectation(description: "the abandoned candidate released its sole action capture")
        var releases = 0
        probe.payload = TaskReentryPayload {
            releases += 1
            released.fulfill()
        }
        weak var payload = probe.payload
        let rejected = invertedStart(1, in: probe)
        let latest = expectStart(2, in: probe)
        probe.onConstruct = {
            probe.onConstruct = nil
            probe.payload = nil
            probe.value = 2
            probe.host?.reload()
        }
        probe.value = 1
        host.reload()
        await fulfillment(of: [latest, released], timeout: 2)
        await fulfillment(of: [rejected], timeout: 0.05)
        XCTAssertNil(payload)
        XCTAssertEqual(releases, 1)
        XCTAssertEqual(probe.comparisons, [[0, 2]])
        XCTAssertEqual(probe.work.starts, [0, 2])
        XCTAssertEqual(probe.work.cancellations, [0])
    }

    func testCooperativeActionCapturesReleaseAfterReplacementRemovalAndClose() async {
        for ending in 0..<3 {
            let probe = TaskReentryProbe()
            var visible = true
            var releases = 0
            let released = expectation(description: "ending \(ending) released the old action payload")
            probe.payload = TaskReentryPayload {
                releases += 1
                released.fulfill()
            }
            weak var payload = probe.payload
            let host = MountedOnChangeTestHost {
                AnyView(
                    VStack {
                        if visible {
                            TaskReentryView(probe: probe)
                                .id(TaskReentryKey(value: probe.key, gate: probe.hashing))
                        }
                    })
            }
            probe.host = host
            defer { probe.close() }
            let ready = expectStart(0, in: probe)
            let finished = expectation(description: "ending \(ending) completed the cancelled action")
            probe.work.finished[0] = finished
            host.render()
            await fulfillment(of: [ready], timeout: 2)
            probe.payload = nil
            XCTAssertNotNil(payload)

            if ending == 0 {
                let replacementReady = expectStart(1, in: probe)
                probe.value = 1
                host.reload()
                await fulfillment(of: [replacementReady], timeout: 2)
            } else if ending == 1 {
                visible = false
                host.reload()
            } else {
                host.close()
            }
            await fulfillment(of: [finished, released], timeout: 2)
            XCTAssertEqual(probe.work.cancellations, [0])
            XCTAssertEqual(probe.work.completions, [0])
            XCTAssertNil(payload)
            XCTAssertEqual(releases, 1)
        }
    }

    func testNoncooperativeCancelledTaskOwnsPayloadOnlyUntilItsActualCompletion() async {
        let probe = TaskReentryProbe()
        probe.work.ignoresCancellation = true
        var releases = 0
        let released = expectation(description: "all intentional action owners released the payload")
        probe.payload = TaskReentryPayload {
            releases += 1
            released.fulfill()
        }
        weak var payload = probe.payload
        let host = makeHost(probe)
        defer { probe.close() }
        probe.payload = nil
        let ready = expectStart(0, in: probe)
        let finished = expectation(description: "the noncooperative action actually finished")
        probe.work.finished[0] = finished
        host.render()
        await fulfillment(of: [ready], timeout: 2)
        host.close()
        XCTAssertEqual(probe.work.cancellations, [0])
        XCTAssertTrue(probe.work.completions.isEmpty)
        XCTAssertNotNil(payload, "Cooperative cancellation does not destroy a suspended action's own captures")
        XCTAssertEqual(releases, 0)
        probe.work.releaseSuspensions()
        await fulfillment(of: [finished, released], timeout: 2)
        XCTAssertEqual(probe.work.completions, [0])
        XCTAssertNil(payload)
        XCTAssertEqual(releases, 1)
        XCTAssertEqual(host.coordinator.registry.liveOwnerCount, 0)
    }

    func testRetainedRejectedSourceReleasesCandidateCapturesWithoutLosingAcceptedWork() async {
        let probe = TaskRetainedSourceProbe()
        let node = probe.node
        let host = MountedOnChangeTestHost {
            if probe.isCandidate { return AnyView(TaskRetainedSourceView(probe: probe)) }
            return AnyView(Text("accepted fallback"))
        }
        probe.host = host
        defer {
            probe.afterMaterialized = nil
            host.close()
            probe.work.releaseSuspensions()
        }

        // Keep the same source node externally alive through two rejected
        // builds. Transport links must not become owners of abandoned actions.
        for version in 1...2 {
            let released = expectation(description: "rejected source \(version) released its action capture")
            probe.payload = TaskReentryPayload { released.fulfill() }
            weak var payload = probe.payload
            let unexpected = expectation(description: "rejected source \(version) did not create a task")
            unexpected.isInverted = true
            probe.work.ready[version] = unexpected
            probe.version = version
            probe.afterMaterialized = {
                probe.afterMaterialized = nil
                probe.payload = nil
                XCTAssertNotNil(payload, "The current materialized build still owns its proposed action")
                probe.isCandidate = false
                probe.host?.reload()
            }
            probe.isCandidate = true
            host.reload()
            await fulfillment(of: [released], timeout: 2)
            await fulfillment(of: [unexpected], timeout: 0.05)
            XCTAssertNil(payload)
            XCTAssertNil(node.parent)
            XCTAssertFalse(node.hasAppeared)
            XCTAssertEqual(node.existingRetainedTaskState?.hasCommittedSlots, false)
            XCTAssertTrue(probe.work.starts.isEmpty)
            XCTAssertTrue(probe.work.cancellations.isEmpty)
        }

        // An accepted epoch must keep its declaration through weak transport,
        // then hand ownership to the committed slot before the build finishes.
        let released = expectation(description: "accepted source released its capture after terminal cleanup")
        probe.payload = TaskReentryPayload { released.fulfill() }
        weak var payload = probe.payload
        probe.version = 3
        probe.afterMaterialized = {
            probe.afterMaterialized = nil
            probe.payload = nil
            XCTAssertNotNil(payload)
        }
        let beforeRender = expectation(description: "accepted source still waits for its first appearance")
        beforeRender.isInverted = true
        probe.work.ready[3] = beforeRender
        probe.isCandidate = true
        host.reload()
        XCTAssertTrue(node.parent === host.runtime.root)
        XCTAssertFalse(node.hasAppeared)
        XCTAssertEqual(node.existingRetainedTaskState?.hasCommittedSlots, true)
        XCTAssertNotNil(payload, "The committed slot owns the pending action after epoch finish")
        await fulfillment(of: [beforeRender], timeout: 0.05)

        let ready = expectation(description: "accepted source installed its task handler")
        let finished = expectation(description: "accepted source's cancelled action finished")
        probe.work.ready[3] = ready
        probe.work.finished[3] = finished
        host.render()
        await fulfillment(of: [ready], timeout: 2)
        XCTAssertEqual(probe.work.starts, [3])
        XCTAssertNotNil(payload)
        host.close()
        await fulfillment(of: [finished, released], timeout: 2)
        XCTAssertEqual(probe.work.cancellations, [3])
        XCTAssertEqual(probe.work.completions, [3])
        XCTAssertNil(payload)
        XCTAssertTrue(node === probe.node, "The external node remains alive after its actions retire")
    }

    private func makeHost(_ probe: TaskReentryProbe) -> MountedOnChangeTestHost {
        let host = MountedOnChangeTestHost {
            AnyView(TaskReentryView(probe: probe).id(TaskReentryKey(value: probe.key, gate: probe.hashing)))
        }
        probe.host = host
        return host
    }

    private func expectStart(_ version: Int, in probe: TaskReentryProbe) -> XCTestExpectation {
        let expected = expectation(description: "task \(version) installed its cancellation handler")
        probe.work.ready[version] = expected
        return expected
    }

    private func invertedStart(_ version: Int, in probe: TaskReentryProbe) -> XCTestExpectation {
        let unexpected = expectation(description: "the rejected task \(version) must not start")
        unexpected.isInverted = true
        probe.work.ready[version] = unexpected
        return unexpected
    }

    private func resolveNestedCell(in epoch: StateMountEpoch, probe: TaskReentryProbe) {
        let identity = RetainedViewIdentity(segments: [.view(ObjectIdentifier(TaskReentryNestedOwner.self))])
        let slot = StatePropertySlot(concreteTypes: [ObjectIdentifier(TaskReentryCellSlot.self)])
        probe.nestedCell = epoch.owner(at: identity)?.resolve(at: slot) { 41 }
        XCTAssertNotNil(probe.nestedCell)
    }
}
