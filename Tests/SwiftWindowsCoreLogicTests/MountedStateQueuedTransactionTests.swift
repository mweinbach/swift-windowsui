import SwiftWindowsCore
import SwiftWindowsGraphics
@preconcurrency import XCTest

@testable import SwiftWindowsPlatform
@testable import SwiftWindowsUI
@testable import WinSwiftUI

/// Pins the Windows retained queue policy: keep distinct transactions when
/// no State write intervenes, and reject requests older than a newer mounted
/// State mutation. These are not native SwiftUI callback-timing claims.
@MainActor
final class MountedStateQueuedTransactionTests: XCTestCase {
    func testQueuedStateBindingBuildPrecedesItsControlsRestoredTransactionWithoutRestartingAnimation() async throws {
        let probe = MountedQueuedTransactionProbe()
        let committed = MountedQueuedObservedModel()
        let candidate = MountedQueuedObservedModel()
        let harness = MountedQueuedTransactionHarness(probe: probe, committed: committed, candidate: candidate)
        defer { harness.close() }
        let toggle = try harness.node("queued.enabled")
        let target = try harness.node("queued.opacity")
        let startedAt = harness.clock.now
        routeDuringCandidate([toggle], in: harness, probe: probe)

        try harness.activate("queued.begin")
        await harness.drain()

        let completions = probe.explicitCompletions
        XCTAssertEqual(completions.map { $0.transaction?.animation?.duration }, [1, 4])
        let bindingCompletion = try XCTUnwrap(completions.first)
        let controlCompletion = try XCTUnwrap(completions.last)
        try assertTransaction(bindingCompletion, matches: MountedQueuedTransactions.binding)
        try assertTransaction(controlCompletion, matches: MountedQueuedTransactions.outer)
        XCTAssertEqual(bindingCompletion.status, MountedQueuedTransactionRoot.enabledStatus)
        XCTAssertEqual(controlCompletion.status, MountedQueuedTransactionRoot.enabledStatus)
        XCTAssertEqual(bindingCompletion.animationDuration, 1)
        XCTAssertEqual(
            controlCompletion.animationDuration, 1, "The control's no-op rebuild must keep the binding tween")
        XCTAssertEqual(bindingCompletion.animationStartTime, controlCompletion.animationStartTime)
        XCTAssertEqual(controlCompletion.animationEndValue, 0.2)
        XCTAssertTrue(try harness.node("queued.opacity") === target)
        try assertAnimation(target, startTime: startedAt, duration: 1, endpoint: 0.2)
        XCTAssertNil(currentTransaction)
        XCTAssertNil(currentAnimationTransaction)
        await assertAbandonedObservation(candidate, committed: committed, probe: probe, in: harness)

        harness.present(at: startedAt + 0.5)
        XCTAssertEqual(target.opacity, 0.6, accuracy: 0.0001)
        XCTAssertEqual(target.animationStates[.opacity]?.startTime, startedAt)
        XCTAssertEqual(target.animationStates[.opacity]?.duration, 1)
        harness.present(at: startedAt + 1)
        XCTAssertEqual(target.opacity, 0.2, accuracy: 0.0001)
        XCTAssertNil(target.animationStates[.opacity])
    }

    func testStateWriteFromQueuedBuildCompletionSupersedesOlderControlRequest() async throws {
        let probe = MountedQueuedTransactionProbe()
        let committed = MountedQueuedObservedModel()
        let candidate = MountedQueuedObservedModel()
        let harness = MountedQueuedTransactionHarness(probe: probe, committed: committed, candidate: candidate)
        defer { harness.close() }
        let toggle = try harness.node("queued.enabled")
        let target = try harness.node("queued.opacity")
        let alternate = try XCTUnwrap(probe.alternateBinding)
        let startedAt = harness.clock.now
        routeDuringCandidate([toggle], in: harness, probe: probe)
        probe.onCompletion = { [weak probe] completion in
            guard let probe, completion.transaction?.animation?.duration == 1 else { return }
            probe.onCompletion = nil
            // This binding came from the original committed root, before A
            // evaluated. B's completion still owns the build guard here.
            withTransaction(MountedQueuedTransactions.followup) {
                alternate.wrappedValue = true
            }
            XCTAssertEqual(currentTransaction?.animation?.duration, 1)
        }

        try harness.activate("queued.begin")
        await harness.drain()

        let completions = probe.explicitCompletions
        XCTAssertEqual(completions.map { $0.transaction?.animation?.duration }, [1, 3])
        let bindingCompletion = try XCTUnwrap(completions.first)
        let followupCompletion = try XCTUnwrap(completions.last)
        try assertTransaction(bindingCompletion, matches: MountedQueuedTransactions.binding)
        try assertTransaction(followupCompletion, matches: MountedQueuedTransactions.followup)
        XCTAssertEqual(bindingCompletion.status, MountedQueuedTransactionRoot.enabledStatus)
        XCTAssertEqual(bindingCompletion.animationDuration, 1)
        XCTAssertEqual(bindingCompletion.animationEndValue, 0.2)
        XCTAssertEqual(followupCompletion.status, MountedQueuedTransactionRoot.alternateStatus)
        XCTAssertEqual(followupCompletion.animationDuration, 3)
        XCTAssertEqual(followupCompletion.animationEndValue, 0.8)
        XCTAssertTrue(try harness.node("queued.opacity") === target)
        try assertAnimation(target, startTime: startedAt, duration: 3, endpoint: 0.8)
        XCTAssertNil(currentTransaction)
        XCTAssertNil(currentAnimationTransaction)
        await assertAbandonedObservation(candidate, committed: committed, probe: probe, in: harness)

        harness.present(at: startedAt + 1.5)
        XCTAssertEqual(target.opacity, 0.9, accuracy: 0.0001)
        XCTAssertEqual(target.animationStates[.opacity]?.startTime, startedAt)
        XCTAssertEqual(target.animationStates[.opacity]?.duration, 3)
        harness.present(at: startedAt + 3)
        XCTAssertEqual(target.opacity, 0.8, accuracy: 0.0001)
        XCTAssertNil(target.animationStates[.opacity])
    }

    func testNewerQueuedStateWriteCannotBeAdoptedUnderAnOlderStateTransaction() async throws {
        let probe = MountedQueuedTransactionProbe()
        let committed = MountedQueuedObservedModel()
        let candidate = MountedQueuedObservedModel()
        let harness = MountedQueuedTransactionHarness(probe: probe, committed: committed, candidate: candidate)
        defer { harness.close() }
        let enabled = try harness.node("queued.enabled")
        let alternate = try harness.node("queued.alternate")
        let target = try harness.node("queued.opacity")
        let startedAt = harness.clock.now
        routeDuringCandidate([enabled, alternate], in: harness, probe: probe)

        try harness.activate("queued.begin")
        await harness.drain()

        let completions = probe.explicitCompletions
        let first = try XCTUnwrap(completions.first)
        XCTAssertFalse(completions.contains { $0.transaction?.animation?.duration == 1 })
        XCTAssertTrue(completions.allSatisfy { $0.transaction?.animation?.duration == 4 })
        try assertTransaction(first, matches: MountedQueuedTransactions.alternateBinding)
        XCTAssertEqual(first.status, MountedQueuedTransactionRoot.alternateStatus)
        XCTAssertEqual(first.animationDuration, 4)
        XCTAssertEqual(first.animationEndValue, 0.8)
        for completion in completions {
            XCTAssertEqual(completion.status, MountedQueuedTransactionRoot.alternateStatus)
            XCTAssertEqual(completion.animationDuration, 4)
            XCTAssertEqual(completion.animationStartTime, startedAt)
            XCTAssertEqual(completion.animationEndValue, 0.8)
        }
        XCTAssertTrue(try harness.node("queued.opacity") === target)
        try assertAnimation(target, startTime: startedAt, duration: 4, endpoint: 0.8)
        XCTAssertNil(currentTransaction)
        XCTAssertNil(currentAnimationTransaction)
        await assertAbandonedObservation(candidate, committed: committed, probe: probe, in: harness)

        harness.present(at: startedAt + 2)
        XCTAssertEqual(target.opacity, 0.9, accuracy: 0.0001)
        XCTAssertEqual(target.animationStates[.opacity]?.startTime, startedAt)
        XCTAssertEqual(target.animationStates[.opacity]?.duration, 4)
        harness.present(at: startedAt + 4)
        XCTAssertEqual(target.opacity, 0.8, accuracy: 0.0001)
        XCTAssertNil(target.animationStates[.opacity])
    }

    func testCandidateObservationRemainsPendingThroughAReentrantNativeFrame() async throws {
        let probe = MountedQueuedTransactionProbe()
        let committed = MountedQueuedObservedModel()
        let candidate = MountedQueuedObservedModel()
        let harness = MountedQueuedTransactionHarness(probe: probe, committed: committed, candidate: candidate)
        defer { harness.close() }
        let started = try XCTUnwrap(probe.startedBinding)
        var decisions: [Bool] = []
        var decisionsDuringCandidate: [Bool] = []
        var isEvaluatingCandidate = false
        var reentrantFrames = 0
        harness.host.onObservedObjectReloadTaskCompleted = { didReload in
            decisions.append(didReload)
            if isEvaluatingCandidate { decisionsDuringCandidate.append(didReload) }
        }
        probe.onCandidateBody = { [weak harness] in
            guard let harness else {
                XCTFail("The candidate must evaluate inside the live host")
                return
            }
            XCTAssertTrue(harness.runtime.hasActiveRetainedBuild)
            isEvaluatingCandidate = true
            defer { isEvaluatingCandidate = false }
            candidate.value = 7
            XCTAssertEqual(harness.host.scheduledReloadCount, 1)
            let framesBefore = harness.renderer.renderedFrames.count
            // A requested idle frame cannot be skipped as identical. Advancing
            // the clock also clears presentation pacing, proving the native
            // frame reaches observation draining while A is still building.
            harness.host.requestDiagnosticsFrame()
            harness.present(at: harness.clock.now + 0.02)
            reentrantFrames += harness.renderer.renderedFrames.count - framesBefore
            XCTAssertEqual(harness.renderer.renderedFrames.count, framesBefore + 1)
            XCTAssertTrue(harness.runtime.hasActiveRetainedBuild)
        }

        // A Button's later context.invalidate() would independently rebuild
        // the cached candidate text and hide a lost observation notification.
        // This is the original installed State binding and its real host
        // invalidation, with no additional control invalidation afterward.
        started.wrappedValue = true
        XCTAssertEqual(reentrantFrames, 1)
        XCTAssertTrue(decisionsDuringCandidate.isEmpty)
        await harness.drain(advanceClock: true)

        XCTAssertEqual(decisions, [true])
        XCTAssertEqual(harness.host.skippedObservedObjectReloadCount, 0)
        XCTAssertTrue(probe.registeredObjectIDs.contains(ObjectIdentifier(candidate)))
        XCTAssertEqual(probe.scheduledObjectIDs, [ObjectIdentifier(candidate)])
        let cachedCompletion = try XCTUnwrap(probe.completions.firstIndex { $0.observation == "candidate=0" })
        let updatedCompletion = try XCTUnwrap(probe.completions.firstIndex { $0.observation == "candidate=7" })
        XCTAssertLessThan(cachedCompletion, updatedCompletion)
        XCTAssertEqual(harness.text("queued.observation"), "candidate=7")
        XCTAssertEqual(harness.text("queued.status"), "started=true enabled=false alternate=false")
        XCTAssertEqual(committed.value, 0)
        XCTAssertNil(currentTransaction)
        XCTAssertNil(currentAnimationTransaction)
    }

    private func routeDuringCandidate(
        _ toggles: [ViewNode], in harness: MountedQueuedTransactionHarness, probe: MountedQueuedTransactionProbe
    ) {
        probe.onCandidateBody = { [weak harness] in
            guard let harness else {
                XCTFail("The host must remain alive while its candidate evaluates")
                return
            }
            XCTAssertTrue(harness.runtime.hasActiveRetainedBuild)
            withTransaction(MountedQueuedTransactions.outer) {
                for toggle in toggles {
                    XCTAssertTrue(harness.nodes.contains { $0 === toggle }, "Route input to the old retained Toggle")
                    harness.activate(toggle)
                    XCTAssertEqual(currentTransaction?.animation?.duration, 4)
                    XCTAssertEqual(currentAnimationTransaction?.duration, 4)
                }
            }
            XCTAssertNil(currentTransaction)
            XCTAssertNil(currentAnimationTransaction)
        }
    }

    private func assertTransaction(
        _ completion: MountedQueuedCompletion, matches expected: Transaction,
        file: StaticString = #filePath, line: UInt = #line
    ) throws {
        let transaction = try XCTUnwrap(completion.transaction, file: file, line: line)
        XCTAssertEqual(transaction.animation?.duration, expected.animation?.duration, file: file, line: line)
        XCTAssertEqual(transaction.animation?.easing, expected.animation?.easing, file: file, line: line)
        XCTAssertEqual(transaction.isContinuous, expected.isContinuous, file: file, line: line)
        XCTAssertEqual(transaction.scrollTargetAnchor, expected.scrollTargetAnchor, file: file, line: line)
        XCTAssertEqual(transaction.tracksVelocity, expected.tracksVelocity, file: file, line: line)
        XCTAssertEqual(transaction.disablesAnimations, expected.disablesAnimations, file: file, line: line)
        XCTAssertEqual(completion.legacyAnimationDuration, expected.animation?.duration, file: file, line: line)
    }

    private func assertAnimation(
        _ target: ViewNode, startTime: Double, duration: Double, endpoint: Double,
        file: StaticString = #filePath, line: UInt = #line
    ) throws {
        let animation = try XCTUnwrap(target.animationStates[.opacity], file: file, line: line)
        XCTAssertEqual(target.opacity, 1, accuracy: 0.0001, file: file, line: line)
        XCTAssertEqual(animation.startValue, 1, accuracy: 0.0001, file: file, line: line)
        XCTAssertEqual(animation.endValue, endpoint, accuracy: 0.0001, file: file, line: line)
        XCTAssertEqual(animation.startTime, startTime, accuracy: 0.0001, file: file, line: line)
        XCTAssertEqual(animation.duration, duration, accuracy: 0.0001, file: file, line: line)
        XCTAssertEqual(animation.easing, .linear, file: file, line: line)
    }

    private func assertAbandonedObservation(
        _ candidate: MountedQueuedObservedModel, committed: MountedQueuedObservedModel,
        probe: MountedQueuedTransactionProbe, in harness: MountedQueuedTransactionHarness,
        file: StaticString = #filePath, line: UInt = #line
    ) async {
        XCTAssertEqual(probe.candidateBodyVisits, 1, file: file, line: line)
        XCTAssertEqual(probe.candidateAppearances, 0, file: file, line: line)
        XCTAssertTrue(probe.registeredObjectIDs.contains(ObjectIdentifier(candidate)), file: file, line: line)
        XCTAssertFalse(
            probe.completions.contains { $0.observation?.hasPrefix("candidate=") == true }, file: file, line: line)
        let reloads = harness.host.executedReloadCount
        let schedules = harness.host.scheduledReloadCount
        let notifications = probe.scheduledObjectIDs.count

        candidate.value = 99
        await harness.drain()

        XCTAssertEqual(harness.host.executedReloadCount, reloads, file: file, line: line)
        XCTAssertEqual(harness.host.scheduledReloadCount, schedules, file: file, line: line)
        XCTAssertEqual(probe.scheduledObjectIDs.count, notifications, file: file, line: line)
        XCTAssertEqual(committed.value, 0, file: file, line: line)
        XCTAssertEqual(harness.text("queued.observation"), "committed=0", file: file, line: line)
    }
}

@MainActor
private enum MountedQueuedTransactions {
    static var binding: Transaction {
        var transaction = Transaction(animation: .linear(duration: 1))
        transaction.isContinuous = true
        transaction.scrollTargetAnchor = .bottom
        transaction.tracksVelocity = true
        return transaction
    }

    static var outer: Transaction {
        var transaction = Transaction(animation: .linear(duration: 4))
        transaction.scrollTargetAnchor = .top
        return transaction
    }

    static var followup: Transaction {
        var transaction = Transaction(animation: .linear(duration: 3))
        transaction.isContinuous = true
        transaction.scrollTargetAnchor = .trailing
        transaction.tracksVelocity = true
        return transaction
    }

    static var alternateBinding: Transaction {
        var transaction = Transaction(animation: .linear(duration: 4))
        transaction.isContinuous = true
        transaction.scrollTargetAnchor = .leading
        transaction.tracksVelocity = true
        return transaction
    }
}

@MainActor
private final class MountedQueuedObservedModel: ObservableObject {
    @Published var value = 0
}

private struct MountedQueuedCompletion {
    let transaction: Transaction?
    let legacyAnimationDuration: Double?
    let status: String?
    let observation: String?
    let animationStartTime: Double?
    let animationDuration: Double?
    let animationEndValue: Double?
}

@MainActor
private final class MountedQueuedTransactionProbe {
    var startedBinding: Binding<Bool>?
    var alternateBinding: Binding<Bool>?
    var onCandidateBody: (() -> Void)?
    var onCompletion: ((MountedQueuedCompletion) -> Void)?
    var completions: [MountedQueuedCompletion] = []
    var registeredObjectIDs: [ObjectIdentifier] = []
    var scheduledObjectIDs: [ObjectIdentifier] = []
    var candidateBodyVisits = 0
    var candidateAppearances = 0

    var explicitCompletions: [MountedQueuedCompletion] {
        // The initiating Button can request an additional unscoped rebuild
        // after its State setter returns. It is not one of B, C, or D.
        completions.filter { $0.transaction?.animation != nil }
    }

    func visitCandidate() {
        candidateBodyVisits += 1
        let callback = onCandidateBody
        onCandidateBody = nil
        callback?()
    }
}

@MainActor
private struct MountedQueuedTransactionRoot: View {
    static let enabledStatus = "started=true enabled=true alternate=false"
    static let alternateStatus = "started=true enabled=true alternate=true"

    let probe: MountedQueuedTransactionProbe
    let committed: MountedQueuedObservedModel
    let candidate: MountedQueuedObservedModel
    @State private var started = false
    @State private var enabled = false
    @State private var alternate = false

    var body: some View {
        let isCandidate = started && !enabled
        let opacity = enabled ? (alternate ? 0.8 : 0.2) : 1
        let status = "started=\(started) enabled=\(enabled) alternate=\(alternate)"
        probe.startedBinding = $started
        probe.alternateBinding = $alternate
        return VStack(alignment: .leading, spacing: 8) {
            Button("Start candidate") { started = true }
                .accessibilityIdentifier("queued.begin")
            Toggle("Enabled", isOn: $enabled.transaction(MountedQueuedTransactions.binding))
                .labelsHidden()
                .accessibilityIdentifier("queued.enabled")
            Toggle("Alternate", isOn: $alternate.transaction(MountedQueuedTransactions.alternateBinding))
                .labelsHidden()
                .accessibilityIdentifier("queued.alternate")
            Rectangle()
                .fill(WinSwiftUI.Color.blue)
                .frame(width: 80, height: 24)
                .opacity(opacity)
                .accessibilityIdentifier("queued.opacity")
            Text(status)
                .accessibilityIdentifier("queued.status")
            MountedQueuedObservedValue(
                model: isCandidate ? candidate : committed, isCandidate: isCandidate, probe: probe)
        }
        .padding(12)
    }
}

@MainActor
private struct MountedQueuedObservedValue: View {
    @ObservedObject var model: MountedQueuedObservedModel
    let isCandidate: Bool
    let probe: MountedQueuedTransactionProbe

    var body: some View {
        // Register the candidate-only dependency before reentering the host.
        let value = model.value
        if isCandidate { probe.visitCandidate() }
        return Text("\(isCandidate ? "candidate" : "committed")=\(value)")
            .accessibilityIdentifier("queued.observation")
            .onAppear {
                if isCandidate { probe.candidateAppearances += 1 }
            }
    }
}

@MainActor
private final class MountedQueuedTransactionHarness {
    let host: WinSwiftUIWindowHost
    let window: Win32Window
    let renderer: FakeRenderBackend
    let clock: RuntimeTestClock

    init(
        probe: MountedQueuedTransactionProbe, committed: MountedQueuedObservedModel,
        candidate: MountedQueuedObservedModel
    ) {
        let clock = RuntimeTestClock()
        clock.now = 5_000
        let renderer = FakeRenderBackend()
        let surface = SurfaceDescriptor(
            windowHandle: NativeWindowHandle(rawPointer: UnsafeMutableRawPointer(bitPattern: 0x1))!,
            pixelSize: IntSize(width: 400, height: 320), scaleFactor: 1)
        let window = Win32Window(title: "Mounted State queued transactions", clientSize: surface.pixelSize)
        let content = MountedQueuedTransactionRoot(probe: probe, committed: committed, candidate: candidate)
        let host = WinSwiftUIWindowHost(
            configuration: WindowGroupConfiguration(
                title: "Mounted State queued transactions", size: surface.pixelSize, clearColor: .black,
                content: [AnyView(content)]),
            platformWindow: window, renderer: renderer, batchRenderer: nil,
            surfaceDescriptorProvider: { _ in surface }, startupProbeConfiguration: nil)
        self.host = host
        self.window = window
        self.renderer = renderer
        self.clock = clock
        host.frameClock = { clock.now }
        host.hostedRuntime.clock = { clock.now }
        host.windowDidCreate(window)
        host.resetObservabilityCounters()
        host.onObservedObjectRegistered = { [weak probe] identifier in
            probe?.registeredObjectIDs.append(identifier)
        }
        host.onObservedObjectReloadScheduled = { [weak probe] identifier, _ in
            probe?.scheduledObjectIDs.append(identifier)
        }
        host.onReloadContentCompleted = { [weak self, weak probe] in
            guard let self, let probe else { return }
            let animation = nodes.first { $0.accessibilityIdentifier == "queued.opacity" }?.animationStates[.opacity]
            let completion = MountedQueuedCompletion(
                transaction: currentTransaction,
                legacyAnimationDuration: currentAnimationTransaction?.duration,
                status: text("queued.status"), observation: text("queued.observation"),
                animationStartTime: animation?.startTime, animationDuration: animation?.duration,
                animationEndValue: animation?.endValue)
            probe.completions.append(completion)
            probe.onCompletion?(completion)
        }
    }

    var runtime: RetainedViewRuntime { host.hostedRuntime }
    var nodes: [ViewNode] { mountedQueuedTransactionNodes(in: runtime.root) }

    func node(_ identifier: String, file: StaticString = #filePath, line: UInt = #line) throws -> ViewNode {
        let matches = nodes.filter { $0.accessibilityIdentifier == identifier }
        XCTAssertEqual(matches.count, 1, "Expected one \(identifier)", file: file, line: line)
        return try XCTUnwrap(matches.first, file: file, line: line)
    }

    func text(_ identifier: String) -> String? {
        nodes.first { $0.accessibilityIdentifier == identifier }?.text
    }

    func activate(_ identifier: String, file: StaticString = #filePath, line: UInt = #line) throws {
        activate(try node(identifier, file: file, line: line), file: file, line: line)
    }

    func activate(_ control: ViewNode, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertNotNil(control.onActivate, file: file, line: line)
        runtime.requestFocus(control)
        host.window(window, keyDown: KeyboardEvent(keyCode: KeyboardKey.space.rawValue))
    }

    func present(at timestamp: Double) {
        clock.now = timestamp
        host.windowNeedsDisplay(window)
    }

    func drain(advanceClock: Bool = false) async {
        // Keep animation time pinned while queued work and executor fallbacks
        // settle. The tests advance the fake clock explicitly for tween samples.
        for _ in 0..<3 {
            if advanceClock { clock.now += 0.02 }
            host.windowNeedsDisplay(window)
            await Task.yield()
        }
    }

    func close() {
        host.windowWillClose(window)
    }
}

@MainActor
private func mountedQueuedTransactionNodes(in node: ViewNode) -> [ViewNode] {
    [node] + node.children.flatMap { mountedQueuedTransactionNodes(in: $0) }
}
