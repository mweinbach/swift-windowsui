import SwiftWindowsCore
import SwiftWindowsGraphics
@preconcurrency import XCTest

@testable import SwiftWindowsPlatform
@testable import SwiftWindowsUI
@testable import WinSwiftUI

@MainActor
final class MountedStateEpochTests: XCTestCase {
    func testClosingTheHostDuringConstructionDoesNotAdoptOrReactivateTheCandidate() async throws {
        let probe = MountedEpochProbe()
        let harness = MountedEpochHarness(MountedEpochReplacementRoot(probe: probe), probe: probe)
        defer { harness.close() }
        probe.onCandidateBody = { [weak probe] phase in
            guard let probe, phase == 1 else { return }
            probe.onCandidateBody = nil
            if let host = probe.host { host.windowWillClose(host.platformWindow) }
        }

        try harness.activate("replacement.next")
        await harness.drain()

        XCTAssertTrue(probe.visitedPhases.contains(1), "The close must interrupt a real candidate body")
        XCTAssertFalse(probe.appearedPhases.contains(1))
        XCTAssertFalse(harness.texts.contains("phase=1 count=10"))
        XCTAssertEqual(probe.closeCount, 1)
        XCTAssertEqual(harness.renderer.detachCount, 1)
        XCTAssertFalse(harness.host.currentTimerState.isEnabled)
        let reloads = harness.host.executedReloadCount
        let frames = harness.renderer.renderedFrames.count
        let candidate = try XCTUnwrap(probe.candidateBindings[1])

        candidate.wrappedValue = 99
        probe.phase?.wrappedValue = 2
        await harness.drain()

        XCTAssertEqual(harness.host.executedReloadCount, reloads)
        XCTAssertEqual(harness.renderer.renderedFrames.count, frames)
        XCTAssertEqual(probe.closeCount, 1)
        XCTAssertFalse(harness.texts.contains("phase=2 count=20"))
    }

    func testLiveAncestorMutationSupersedesConstructionAndRetiresItsProvisionalState() async throws {
        let probe = MountedEpochProbe()
        let harness = MountedEpochHarness(MountedEpochReplacementRoot(probe: probe), probe: probe)
        defer { harness.close() }
        let mountedPhase = try XCTUnwrap(probe.phase)
        probe.onCandidateBody = { [weak probe] phase in
            guard let probe, phase == 1 else { return }
            probe.onCandidateBody = nil
            mountedPhase.wrappedValue = 2
        }

        try harness.activate("replacement.next")
        await harness.drain()

        XCTAssertTrue(probe.visitedPhases.contains(1))
        XCTAssertEqual(try harness.text("candidate.value"), "phase=2 count=20")
        XCTAssertFalse(probe.appearedPhases.contains(1))
        XCTAssertTrue(probe.appearedPhases.contains(2))
        XCTAssertFalse(probe.completedTexts.contains { $0.contains("phase=1 count=10") })
        let abandoned = try XCTUnwrap(probe.candidateBindings[1])
        let replacement = try harness.node("candidate.value")
        let reloads = harness.host.executedReloadCount

        abandoned.wrappedValue = 777
        await harness.drain()

        XCTAssertEqual(harness.host.executedReloadCount, reloads)
        XCTAssertTrue(try harness.node("candidate.value") === replacement)
        XCTAssertEqual(try harness.text("candidate.value"), "phase=2 count=20")
        try harness.activate("candidate.increment")
        await harness.drain()
        XCTAssertEqual(try harness.text("candidate.value"), "phase=2 count=21")
    }

    func testDisappearanceCanReadDepartingStateAndQueueAWriteToItsSurvivingAncestor() async throws {
        let probe = MountedEpochProbe()
        let harness = MountedEpochHarness(MountedEpochReentrantRoot(probe: probe), probe: probe)
        defer { harness.close() }
        try harness.activate("departing.increment")
        try harness.activate("departing.increment")
        try harness.activate("survivor.increment")
        try harness.activate("survivor.increment")
        let outgoing = try XCTUnwrap(probe.counterBindings["departing"])
        let survivor = try harness.node("survivor.value")

        try harness.activate("reentrant.remove")
        await harness.drain()

        XCTAssertEqual(probe.cleanupValues, [2], "Cleanup retains read access to the outgoing generation")
        XCTAssertEqual(probe.cleanupValuesAfterRejectedWrite, [2], "Writes are revoked before cleanup executes")
        XCTAssertEqual(try harness.text("ancestor.value"), "ancestor=1")
        XCTAssertEqual(try harness.text("replacement.value"), "replacement=0")
        XCTAssertEqual(try harness.text("survivor.value"), "survivor=2")
        XCTAssertTrue(try harness.node("survivor.value") === survivor)
        XCTAssertNil(harness.find("departing.value"))
        let reloads = harness.host.executedReloadCount

        outgoing.wrappedValue = 888
        await harness.drain()

        XCTAssertEqual(harness.host.executedReloadCount, reloads)
        XCTAssertEqual(try harness.text("ancestor.value"), "ancestor=1")
        XCTAssertEqual(try harness.text("replacement.value"), "replacement=0")
        try harness.activate("replacement.increment")
        await harness.drain()
        XCTAssertEqual(try harness.text("replacement.value"), "replacement=1")
        XCTAssertEqual(probe.cleanupValues, [2])
    }

    func testReentrantAncestorWriteKeepsItsFullAnimationTransactionAfterAdoption() async throws {
        let probe = MountedEpochProbe()
        var transaction = Transaction(animation: .linear(duration: 0.75))
        transaction.isContinuous = true
        transaction.scrollTargetAnchor = .bottom
        transaction.tracksVelocity = true
        probe.cleanupTransaction = transaction
        let harness = MountedEpochHarness(MountedEpochReentrantRoot(probe: probe), probe: probe)
        defer { harness.close() }
        let target = try harness.node("ancestor.opacity")
        let startedAt = harness.clock.now

        try withAnimation(.linear(duration: 4)) {
            try harness.activate("reentrant.remove")
        }
        await harness.drain(advanceClock: false)

        let completion = try XCTUnwrap(probe.ancestorCompletions.first { $0.text == "ancestor=1" })
        let captured = try XCTUnwrap(completion.transaction)
        XCTAssertEqual(captured.animation?.duration, 0.75)
        XCTAssertEqual(captured.animation?.easing, .linear)
        XCTAssertTrue(captured.isContinuous)
        XCTAssertEqual(captured.scrollTargetAnchor, .bottom)
        XCTAssertTrue(captured.tracksVelocity)
        XCTAssertFalse(captured.disablesAnimations)
        let animation = try XCTUnwrap(target.animationStates[.opacity])
        XCTAssertEqual(animation.startTime, startedAt, accuracy: 0.0001)
        XCTAssertEqual(animation.duration, 0.75, accuracy: 0.0001)
        XCTAssertEqual(animation.startValue, 1, accuracy: 0.0001)
        XCTAssertEqual(animation.endValue, 0.2, accuracy: 0.0001)
        XCTAssertNil(currentTransaction)
        XCTAssertNil(currentAnimationTransaction)

        harness.present(at: startedAt + 0.375)
        XCTAssertEqual(target.opacity, 0.6, accuracy: 0.0001)
        harness.present(at: startedAt + 0.75)
        XCTAssertEqual(target.opacity, 0.2, accuracy: 0.0001)
        XCTAssertNil(target.animationStates[.opacity])
    }

    func testReentrantExplicitNilTransactionDoesNotInheritTheOuterRemovalAnimation() async throws {
        let probe = MountedEpochProbe()
        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        transaction.isContinuous = true
        transaction.scrollTargetAnchor = .trailing
        transaction.tracksVelocity = true
        probe.cleanupTransaction = transaction
        let harness = MountedEpochHarness(MountedEpochReentrantRoot(probe: probe), probe: probe)
        defer { harness.close() }
        let target = try harness.node("ancestor.opacity")

        try withAnimation(.linear(duration: 4)) {
            try harness.activate("reentrant.remove")
            XCTAssertEqual(currentTransaction?.animation?.duration, 4)
        }
        await harness.drain()

        let completion = try XCTUnwrap(probe.ancestorCompletions.first { $0.text == "ancestor=1" })
        let captured = try XCTUnwrap(completion.transaction, "Explicit nil must survive as an actual transaction")
        XCTAssertNil(captured.animation)
        XCTAssertTrue(captured.disablesAnimations)
        XCTAssertTrue(captured.isContinuous)
        XCTAssertEqual(captured.scrollTargetAnchor, .trailing)
        XCTAssertTrue(captured.tracksVelocity)
        XCTAssertEqual(target.opacity, 0.2, accuracy: 0.0001)
        XCTAssertNil(target.animationStates[.opacity])
        XCTAssertNil(currentTransaction)
        XCTAssertNil(currentAnimationTransaction)
    }

    func testAbandonedCandidateKeepsCommittedObservationAndDiscardsItsOwnSubscription() async throws {
        let probe = MountedEpochProbe()
        let committed = MountedEpochObservedModel()
        let candidate = MountedEpochObservedModel()
        let harness = MountedEpochHarness(
            MountedEpochObservationRoot(committed: committed, candidate: candidate, probe: probe), probe: probe)
        defer { harness.close() }
        let mountedPhase = try XCTUnwrap(probe.phase)
        let committedID = ObjectIdentifier(committed)
        var notificationsDuringCandidate: [ObjectIdentifier] = []
        var isEvaluatingCandidate = false
        harness.host.onObservedObjectReloadScheduled = { identifier, _ in
            if isEvaluatingCandidate { notificationsDuringCandidate.append(identifier) }
        }
        probe.onCandidateBody = { [weak probe] phase in
            guard let probe, phase == 1 else { return }
            probe.onCandidateBody = nil
            isEvaluatingCandidate = true
            committed.value = 7
            isEvaluatingCandidate = false
            mountedPhase.wrappedValue = 2
        }

        try harness.activate("observation.next")
        await harness.drain()

        XCTAssertEqual(notificationsDuringCandidate, [committedID])
        XCTAssertEqual(try harness.text("observation.value"), "committed=7 phase=2")
        XCTAssertFalse(probe.completedTexts.contains { $0.contains("candidate=0 phase=1") })
        XCTAssertFalse(probe.appearedPhases.contains(1))
        var subsequentNotifications: [ObjectIdentifier] = []
        harness.host.onObservedObjectReloadScheduled = { identifier, _ in
            subsequentNotifications.append(identifier)
        }
        let reloads = harness.host.executedReloadCount

        candidate.value = 8
        await harness.drain()

        XCTAssertTrue(subsequentNotifications.isEmpty, "An abandoned-only dependency must be unsubscribed")
        XCTAssertEqual(harness.host.executedReloadCount, reloads)
        committed.value = 9
        await harness.drain()

        XCTAssertEqual(subsequentNotifications, [committedID])
        XCTAssertEqual(try harness.text("observation.value"), "committed=9 phase=2")
    }

    func testGeometrySubtreeResizesKeepItsMountedStateAndDoNotSweepSiblingState() async throws {
        let probe = MountedEpochProbe()
        let harness = MountedEpochHarness(MountedEpochGeometryRoot(probe: probe), probe: probe)
        defer { harness.close() }
        try harness.activate("geometry.increment")
        try harness.activate("geometry.increment")
        try harness.activate("sibling.increment")
        try harness.activate("sibling.increment")
        let reader = try harness.reader()
        let geometryValue = try harness.node("geometry.value")
        let siblingValue = try harness.node("sibling.value")
        var resolves = harness.runtime.geometryReaderResolveCount
        let hostReloads = harness.host.executedReloadCount

        for size in [IntSize(width: 640, height: 480), IntSize(width: 360, height: 280)] {
            harness.runtime.setRootSize(size)
            _ = harness.runtime.renderFrame()

            XCTAssertTrue(try harness.reader() === reader)
            XCTAssertTrue(try harness.node("geometry.value") === geometryValue)
            XCTAssertTrue(try harness.node("sibling.value") === siblingValue)
            XCTAssertEqual(try harness.text("geometry.value"), "geometry=2")
            XCTAssertEqual(try harness.text("sibling.value"), "sibling=2")
            XCTAssertEqual(
                try harness.text("geometry.size"), MountedEpochGeometryContent.label(for: reader.resolvedFrame.size))
            XCTAssertGreaterThan(harness.runtime.geometryReaderResolveCount, resolves)
            resolves = harness.runtime.geometryReaderResolveCount
        }

        XCTAssertEqual(harness.host.executedReloadCount, hostReloads, "The runtime alone must rebuild the reader scope")
        try harness.activate("geometry.increment")
        await harness.drain()
        XCTAssertEqual(try harness.text("geometry.value"), "geometry=3")
        XCTAssertEqual(try harness.text("sibling.value"), "sibling=2")
    }

    func testCapturedRetiredReaderCannotRebuildBeforeOrAfterTheSamePathRemounts() async throws {
        let probe = MountedEpochProbe()
        let harness = MountedEpochHarness(MountedEpochGeometryRoot(probe: probe), probe: probe)
        defer { harness.close() }
        try harness.activate("geometry.increment")
        try harness.activate("sibling.increment")
        let reader = try harness.reader()
        let oldBuilder = try XCTUnwrap(reader.geometryReaderBuild)
        let oldBinding = try XCTUnwrap(probe.counterBindings["geometry"])

        try harness.activate("geometry.toggle")
        await harness.drain()

        XCTAssertNil(harness.find("geometry.value"))
        let visitsAfterRemoval = probe.geometryBodyCount
        let reloadsAfterRemoval = harness.host.executedReloadCount
        let afterRemoval = oldBuilder(harness.runtime, Size(width: 510, height: 310))
        oldBinding.wrappedValue = 99
        await harness.drain()

        XCTAssertTrue(afterRemoval.isEmpty)
        XCTAssertEqual(probe.geometryBodyCount, visitsAfterRemoval)
        XCTAssertEqual(harness.host.executedReloadCount, reloadsAfterRemoval)
        XCTAssertEqual(try harness.text("sibling.value"), "sibling=1")
        try harness.activate("geometry.toggle")
        await harness.drain()
        let replacement = try harness.reader()
        XCTAssertFalse(replacement === reader)
        XCTAssertEqual(replacement.retainedViewIdentity, reader.retainedViewIdentity)
        XCTAssertEqual(try harness.text("geometry.value"), "geometry=0")
        let visitsAfterRemount = probe.geometryBodyCount
        let reloadsAfterRemount = harness.host.executedReloadCount

        let afterRemount = oldBuilder(harness.runtime, Size(width: 530, height: 330))
        oldBinding.wrappedValue = 100
        await harness.drain()

        XCTAssertTrue(afterRemount.isEmpty)
        XCTAssertEqual(probe.geometryBodyCount, visitsAfterRemount)
        XCTAssertEqual(harness.host.executedReloadCount, reloadsAfterRemount)
        XCTAssertEqual(try harness.text("geometry.value"), "geometry=0")
        XCTAssertEqual(try harness.text("sibling.value"), "sibling=1")
        try harness.activate("geometry.increment")
        await harness.drain()
        XCTAssertEqual(try harness.text("geometry.value"), "geometry=1")
    }

    func testReaderRemovedDuringItsRealResizeBuildCannotAdoptTheObsoleteSubtree() async throws {
        let probe = MountedEpochProbe()
        let harness = MountedEpochHarness(MountedEpochGeometryRoot(probe: probe), probe: probe)
        defer { harness.close() }
        try harness.activate("geometry.increment")
        try harness.activate("sibling.increment")
        let reader = try harness.reader()
        let oldBuilder = try XCTUnwrap(reader.geometryReaderBuild)
        let originalBuildSize = reader.geometryReaderBuiltSize
        let sibling = try harness.node("sibling.value")
        let mountedVisibility = try XCTUnwrap(probe.showReader)
        var interruptedBuilds = 0
        probe.onGeometryBody = { [weak probe] size in
            guard let probe, size.width > 500 else { return }
            probe.onGeometryBody = nil
            interruptedBuilds += 1
            mountedVisibility.wrappedValue = false
        }

        harness.runtime.setRootSize(IntSize(width: 640, height: 480))
        _ = harness.runtime.renderFrame()
        await harness.drain()

        XCTAssertEqual(interruptedBuilds, 1)
        XCTAssertNil(harness.find("geometry.value"))
        XCTAssertEqual(reader.geometryReaderBuiltSize, originalBuildSize)
        XCTAssertTrue(try harness.node("sibling.value") === sibling)
        XCTAssertEqual(try harness.text("sibling.value"), "sibling=1")
        XCTAssertTrue(oldBuilder(harness.runtime, Size(width: 620, height: 340)).isEmpty)
        try harness.activate("geometry.toggle")
        await harness.drain()
        XCTAssertEqual(try harness.text("geometry.value"), "geometry=0")
        XCTAssertEqual(try harness.text("sibling.value"), "sibling=1")
    }

    func testClosingDuringARealGeometryResizeRetiresBothReaderAndSiblingOwners() async throws {
        let probe = MountedEpochProbe()
        let harness = MountedEpochHarness(MountedEpochGeometryRoot(probe: probe), probe: probe)
        defer { harness.close() }
        try harness.activate("geometry.increment")
        try harness.activate("sibling.increment")
        let reader = try harness.reader()
        let oldBuilder = try XCTUnwrap(reader.geometryReaderBuild)
        let siblingBinding = try XCTUnwrap(probe.counterBindings["sibling"])
        let originalSizeText = try harness.text("geometry.size")
        let originalBuildSize = reader.geometryReaderBuiltSize
        var interruptedBuilds = 0
        probe.onGeometryBody = { [weak probe] size in
            guard let probe, size.width > 500 else { return }
            probe.onGeometryBody = nil
            interruptedBuilds += 1
            if let host = probe.host { host.windowWillClose(host.platformWindow) }
        }

        harness.runtime.setRootSize(IntSize(width: 640, height: 480))
        _ = harness.runtime.renderFrame()
        await harness.drain()

        XCTAssertEqual(interruptedBuilds, 1)
        XCTAssertEqual(probe.closeCount, 1)
        XCTAssertEqual(harness.renderer.detachCount, 1)
        XCTAssertEqual(reader.geometryReaderBuiltSize, originalBuildSize)
        if let remaining = harness.find("geometry.size") {
            XCTAssertEqual(remaining.text, originalSizeText, "Closing cannot publish the in-progress reader candidate")
        }
        let geometryVisits = probe.geometryBodyCount
        let reloads = harness.host.executedReloadCount
        let frames = harness.renderer.renderedFrames.count

        XCTAssertTrue(oldBuilder(harness.runtime, Size(width: 660, height: 500)).isEmpty)
        siblingBinding.wrappedValue = 900
        await harness.drain()

        XCTAssertEqual(probe.geometryBodyCount, geometryVisits)
        XCTAssertEqual(harness.host.executedReloadCount, reloads)
        XCTAssertEqual(harness.renderer.renderedFrames.count, frames)
        XCTAssertFalse(harness.host.currentTimerState.isEnabled)
    }
}

@MainActor
private final class MountedEpochProbe {
    weak var host: WinSwiftUIWindowHost?
    var phase: Binding<Int>?
    var showReader: Binding<Bool>?
    var candidateBindings: [Int: Binding<Int>] = [:]
    var counterBindings: [String: Binding<Int>] = [:]
    var visitedPhases: [Int] = []
    var appearedPhases: [Int] = []
    var completedTexts: [[String]] = []
    var cleanupValues: [Int] = []
    var cleanupValuesAfterRejectedWrite: [Int] = []
    var cleanupTransaction: Transaction?
    var ancestorCompletions: [MountedEpochCompletion] = []
    var onCandidateBody: ((Int) -> Void)?
    var onGeometryBody: ((Size) -> Void)?
    var geometryBodyCount = 0
    var closeCount = 0

    func visitCandidate(_ phase: Int, binding: Binding<Int>) {
        candidateBindings[phase] = binding
        visitedPhases.append(phase)
        onCandidateBody?(phase)
    }
}

private struct MountedEpochCompletion {
    let text: String
    let transaction: Transaction?
}

@MainActor
private struct MountedEpochReplacementRoot: View {
    let probe: MountedEpochProbe
    @State private var phase = 0

    var body: some View {
        probe.phase = $phase
        return VStack(alignment: .leading, spacing: 8) {
            Button("Next phase") { phase += 1 }
                .accessibilityIdentifier("replacement.next")
            MountedEpochCandidate(phase: phase, probe: probe)
                .id(phase)
        }
        .padding(12)
    }
}

@MainActor
private struct MountedEpochCandidate: View {
    let phase: Int
    let probe: MountedEpochProbe
    @State private var count: Int

    init(phase: Int, probe: MountedEpochProbe) {
        self.phase = phase
        self.probe = probe
        _count = State(initialValue: phase * 10)
    }

    var body: some View {
        let value = count
        probe.visitCandidate(phase, binding: $count)
        return VStack(alignment: .leading, spacing: 4) {
            Text("phase=\(phase) count=\(value)")
                .accessibilityIdentifier("candidate.value")
            Button("Increment candidate") { count += 1 }
                .accessibilityIdentifier("candidate.increment")
        }
        .onAppear { probe.appearedPhases.append(phase) }
    }
}

@MainActor
private struct MountedEpochCounter: View {
    let name: String
    let probe: MountedEpochProbe
    @State private var count = 0

    var body: some View {
        let value = count
        probe.counterBindings[name] = $count
        return VStack(alignment: .leading, spacing: 4) {
            Text("\(name)=\(value)")
                .accessibilityIdentifier("\(name).value")
            Button("Increment \(name)") { count += 1 }
                .accessibilityIdentifier("\(name).increment")
        }
    }
}

@MainActor
private struct MountedEpochReentrantRoot: View {
    let probe: MountedEpochProbe
    @State private var showsChild = true
    @State private var total = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button("Remove child") { showsChild = false }
                .accessibilityIdentifier("reentrant.remove")
            Text("ancestor=\(total)")
                .accessibilityIdentifier("ancestor.value")
            Rectangle()
                .fill(WinSwiftUI.Color.blue)
                .frame(width: 80, height: 24)
                .opacity(total == 0 ? 1 : 0.2)
                .accessibilityIdentifier("ancestor.opacity")
            if showsChild {
                MountedEpochDepartingChild(total: $total, probe: probe)
            } else {
                MountedEpochCounter(name: "replacement", probe: probe)
            }
            MountedEpochCounter(name: "survivor", probe: probe)
        }
        .padding(12)
    }
}

@MainActor
private struct MountedEpochDepartingChild: View {
    @Binding var total: Int
    let probe: MountedEpochProbe
    @State private var count = 0

    var body: some View {
        let value = count
        probe.counterBindings["departing"] = $count
        return VStack(alignment: .leading, spacing: 4) {
            Text("departing=\(value)")
                .accessibilityIdentifier("departing.value")
            Button("Increment departing") { count += 1 }
                .accessibilityIdentifier("departing.increment")
        }
        .onDisappear {
            probe.cleanupValues.append(count)
            count = 999
            probe.cleanupValuesAfterRejectedWrite.append(count)
            if let transaction = probe.cleanupTransaction {
                withTransaction(transaction) { total += 1 }
            } else {
                total += 1
            }
        }
    }
}

@MainActor
private final class MountedEpochObservedModel: ObservableObject {
    @Published var value = 0
}

@MainActor
private struct MountedEpochObservationRoot: View {
    let committed: MountedEpochObservedModel
    let candidate: MountedEpochObservedModel
    let probe: MountedEpochProbe
    @State private var phase = 0

    var body: some View {
        probe.phase = $phase
        return VStack(alignment: .leading, spacing: 8) {
            Button("Next observed phase") { phase += 1 }
                .accessibilityIdentifier("observation.next")
            if phase == 1 {
                MountedEpochObservedBranch(model: candidate, name: "candidate", phase: phase, probe: probe)
            } else {
                MountedEpochObservedBranch(model: committed, name: "committed", phase: phase, probe: probe)
            }
        }
        .padding(12)
    }
}

@MainActor
private struct MountedEpochObservedBranch: View {
    @ObservedObject var model: MountedEpochObservedModel
    let name: String
    let phase: Int
    let probe: MountedEpochProbe
    @State private var count = 0

    var body: some View {
        let value = model.value
        probe.visitCandidate(phase, binding: $count)
        return Text("\(name)=\(value) phase=\(phase)")
            .accessibilityIdentifier("observation.value")
            .onAppear { probe.appearedPhases.append(phase) }
    }
}

@MainActor
private struct MountedEpochGeometryRoot: View {
    let probe: MountedEpochProbe
    @State private var showsReader = true

    var body: some View {
        probe.showReader = $showsReader
        return VStack(alignment: .leading, spacing: 0) {
            Button("Toggle reader") { showsReader.toggle() }
                .accessibilityIdentifier("geometry.toggle")
                .frame(height: 40)
            if showsReader {
                GeometryReader { proxy in
                    MountedEpochGeometryContent(size: proxy.size, probe: probe)
                }
            }
            MountedEpochCounter(name: "sibling", probe: probe)
                .frame(height: 60)
        }
    }
}

@MainActor
private struct MountedEpochGeometryContent: View {
    let size: Size
    let probe: MountedEpochProbe
    @State private var count = 0

    static func label(for size: Size) -> String {
        "slot=\(Int(size.width.rounded()))x\(Int(size.height.rounded()))"
    }

    var body: some View {
        let value = count
        probe.counterBindings["geometry"] = $count
        probe.geometryBodyCount += 1
        probe.onGeometryBody?(size)
        return VStack(alignment: .leading, spacing: 4) {
            Text("geometry=\(value)")
                .accessibilityIdentifier("geometry.value")
            Text(Self.label(for: size))
                .accessibilityIdentifier("geometry.size")
            Button("Increment geometry") { count += 1 }
                .accessibilityIdentifier("geometry.increment")
        }
    }
}

@MainActor
private final class MountedEpochHarness {
    let host: WinSwiftUIWindowHost
    let window: Win32Window
    let renderer: FakeRenderBackend
    let clock: RuntimeTestClock

    init<Content: View>(_ content: Content, probe: MountedEpochProbe) {
        let clock = RuntimeTestClock()
        clock.now = 5_000
        let renderer = FakeRenderBackend()
        let surface = SurfaceDescriptor(
            windowHandle: NativeWindowHandle(rawPointer: UnsafeMutableRawPointer(bitPattern: 0x1))!,
            pixelSize: IntSize(width: 400, height: 400), scaleFactor: 1)
        let window = Win32Window(title: "Mounted State epochs", clientSize: surface.pixelSize)
        let host = WinSwiftUIWindowHost(
            configuration: WindowGroupConfiguration(
                title: "Mounted State epochs", size: surface.pixelSize, clearColor: .black,
                content: [AnyView(content)]),
            platformWindow: window, renderer: renderer, batchRenderer: nil,
            surfaceDescriptorProvider: { _ in surface }, startupProbeConfiguration: nil)
        self.host = host
        self.window = window
        self.renderer = renderer
        self.clock = clock
        probe.host = host
        host.onWindowClosed = { [weak probe] _ in probe?.closeCount += 1 }
        host.onReloadContentCompleted = { [weak host, weak probe] in
            guard let host, let probe else { return }
            let nodes = mountedEpochNodes(in: host.hostedRuntime.root)
            probe.completedTexts.append(nodes.compactMap(\.text))
            if let text = nodes.first(where: { $0.accessibilityIdentifier == "ancestor.value" })?.text {
                probe.ancestorCompletions.append(MountedEpochCompletion(text: text, transaction: currentTransaction))
            }
        }
        host.frameClock = { clock.now }
        host.hostedRuntime.clock = { clock.now }
        host.windowDidCreate(window)
        host.resetObservabilityCounters()
    }

    var runtime: RetainedViewRuntime { host.hostedRuntime }
    var nodes: [ViewNode] { mountedEpochNodes(in: runtime.root) }
    var texts: [String] { nodes.compactMap(\.text) }

    func find(_ identifier: String) -> ViewNode? {
        nodes.first { $0.accessibilityIdentifier == identifier }
    }

    func node(_ identifier: String, file: StaticString = #filePath, line: UInt = #line) throws -> ViewNode {
        let matches = nodes.filter { $0.accessibilityIdentifier == identifier }
        XCTAssertEqual(matches.count, 1, "Expected one \(identifier)", file: file, line: line)
        return try XCTUnwrap(matches.first, file: file, line: line)
    }

    func text(_ identifier: String, file: StaticString = #filePath, line: UInt = #line) throws -> String {
        try XCTUnwrap(node(identifier, file: file, line: line).text, file: file, line: line)
    }

    func reader(file: StaticString = #filePath, line: UInt = #line) throws -> ViewNode {
        let matches = nodes.filter { $0.geometryReaderBuild != nil }
        XCTAssertEqual(matches.count, 1, file: file, line: line)
        return try XCTUnwrap(matches.first, file: file, line: line)
    }

    func activate(_ identifier: String, file: StaticString = #filePath, line: UInt = #line) throws {
        let control = try node(identifier, file: file, line: line)
        XCTAssertNotNil(control.onActivate, file: file, line: line)
        runtime.requestFocus(control)
        host.window(window, keyDown: KeyboardEvent(keyCode: KeyboardKey.space.rawValue))
    }

    func present(at timestamp: Double) {
        clock.now = timestamp
        host.windowNeedsDisplay(window)
    }

    func drain(advanceClock: Bool = true) async {
        // Exercise the native frame wake and let stale executor fallbacks run.
        // No test calls a control's stored activation closure directly.
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
private func mountedEpochNodes(in node: ViewNode) -> [ViewNode] {
    [node] + node.children.flatMap { mountedEpochNodes(in: $0) }
}
