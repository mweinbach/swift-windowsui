import SwiftWindowsCore
import SwiftWindowsGraphics
@preconcurrency import XCTest

@testable import SwiftWindowsPlatform
@testable import SwiftWindowsUI
@testable import WinSwiftUI

/// Retained ownership tests for supported struct styles, not native style-cascade characterization.
@MainActor
final class ProgressViewStyleMountedTests: XCTestCase {
    func testReturnedBodyStateSurvivesParentRebuildAndUpdatedConfiguration() async throws {
        let model = ProgressMountedModel()
        let fixture = ProgressMountedWindow(
            ProgressMountedParent(model: model) {
                ProgressView(value: model.progress)
                    .progressViewStyle(
                        ProgressMountedCountingStyle(
                            name: "progress", styleSeed: model.revision + 10, bodySeed: model.revision + 20))
            })
        defer { fixture.close() }
        let original = try fixture.node("progress.body.value")
        try fixture.assertText("0.25", "progress.fraction")

        try fixture.activate("progress.body.increment")
        fixture.flush()
        model.revision = 100
        model.progress = 0.75
        fixture.flush()

        try fixture.assertCounts(style: 10, body: 21, name: "progress")
        try fixture.assertText("0.75", "progress.fraction")
        XCTAssertTrue(try fixture.node("progress.body.value") === original)
        try fixture.activate("progress.body.increment")
        fixture.flush()
        try fixture.assertCounts(style: 10, body: 22, name: "progress")
    }

    func testStructStyleStateInstallsBeforeMakeBodyAndRetainsItsMountedValue() async throws {
        let model = ProgressMountedModel()
        let capture = ProgressMountedCapture()
        let fixture = ProgressMountedWindow(
            ProgressMountedParent(model: model) {
                ProgressView(value: model.progress)
                    .progressViewStyle(
                        ProgressMountedCountingStyle(
                            name: "progress", styleSeed: model.revision + 7, bodySeed: 40, capture: capture))
            })
        defer { fixture.close() }
        XCTAssertEqual(capture.makeBodyValues["progress"]?.last, 7)
        let binding = try capture.binding("progress.style")

        binding.wrappedValue = 8
        fixture.flush()
        model.revision = 500
        fixture.flush()

        XCTAssertEqual(capture.makeBodyValues["progress"]?.last, 8)
        XCTAssertEqual(binding.wrappedValue, 8)
        try fixture.assertCounts(style: 8, body: 40, name: "progress")
        try fixture.activate("progress.style.increment")
        fixture.flush()
        XCTAssertEqual(capture.makeBodyValues["progress"]?.last, 9)
        try fixture.assertCounts(style: 9, body: 40, name: "progress")
    }

    func testChangingStyleTypeRetiresStyleAndBodyOwnersWithTheSameReturnedBodyType() async throws {
        let model = ProgressMountedModel()
        let capture = ProgressMountedCapture()
        let fixture = ProgressMountedWindow(
            ProgressMountedParent(model: model) {
                progressMountedSelectedStyle(model: model, capture: capture)
            })
        defer { fixture.close() }
        try fixture.activate("progress.style.increment")
        try fixture.activate("progress.body.increment")
        fixture.flush()
        let oldStyle = try capture.binding("progress.style")
        let oldBody = try capture.binding("progress.body")
        let original = try fixture.node("progress.body.value")

        model.usesAlternate = true
        fixture.flush()

        try fixture.assertCounts(style: 70, body: 80, name: "progress")
        XCTAssertFalse(try fixture.node("progress.body.value") === original)
        let reloads = fixture.host.executedReloadCount
        oldStyle.wrappedValue = 999
        oldBody.wrappedValue = 999
        await fixture.drain()
        XCTAssertEqual(oldStyle.wrappedValue, 11)
        XCTAssertEqual(oldBody.wrappedValue, 21)
        XCTAssertEqual(fixture.host.executedReloadCount, reloads)
        try fixture.assertCounts(style: 70, body: 80, name: "progress")

        model.usesAlternate = false
        fixture.flush()
        try fixture.assertCounts(style: 10, body: 20, name: "progress")
    }

    func testInheritedSourceStyleGivesSiblingProgressViewsIndependentState() async throws {
        let model = ProgressMountedModel()
        let source = ProgressMountedCountingStyle(name: "shared", styleSeed: 5, bodySeed: 50)
        let fixture = ProgressMountedWindow(
            ProgressMountedParent(model: model) {
                VStack {
                    ProgressView(value: 0.25).accessibilityIdentifier("left")
                    ProgressView(value: 0.75).accessibilityIdentifier("right")
                }
                .progressViewStyle(source)
            })
        defer { fixture.close() }
        let left = try fixture.node("shared.body.value", within: "left")
        let right = try fixture.node("shared.body.value", within: "right")
        XCTAssertNotEqual(try XCTUnwrap(left.retainedViewIdentity), try XCTUnwrap(right.retainedViewIdentity))

        try fixture.activate("shared.style.increment", within: "left")
        try fixture.activate("shared.body.increment", within: "right")
        try fixture.activate("shared.body.increment", within: "right")
        model.revision += 1
        fixture.flush()

        try fixture.assertCounts(style: 6, body: 50, name: "shared", within: "left")
        try fixture.assertCounts(style: 5, body: 52, name: "shared", within: "right")
        XCTAssertTrue(try fixture.node("shared.body.value", within: "left") === left)
        XCTAssertTrue(try fixture.node("shared.body.value", within: "right") === right)
    }

    func testSameSourceStyleInTwoHostsInvalidatesOnlyItsOwnHost() async throws {
        let source = ProgressView(value: 0.5)
            .progressViewStyle(ProgressMountedCountingStyle(name: "shared", styleSeed: 0, bodySeed: 10))
        let configuration = progressMountedConfiguration(source)
        let first = ProgressMountedWindow(configuration: configuration)
        defer { first.close() }
        try first.activate("shared.style.increment")
        try first.activate("shared.body.increment")
        first.flush()

        let second = ProgressMountedWindow(configuration: configuration)
        defer { second.close() }
        try second.assertCounts(style: 0, body: 10, name: "shared")
        let secondReloads = second.host.executedReloadCount
        try first.activate("shared.style.increment")
        try first.activate("shared.body.increment")
        first.flush()
        second.flush()

        try first.assertCounts(style: 2, body: 12, name: "shared")
        try second.assertCounts(style: 0, body: 10, name: "shared")
        XCTAssertEqual(second.host.executedReloadCount, secondReloads)
        let firstReloads = first.host.executedReloadCount
        try second.activate("shared.body.increment")
        second.flush()
        first.flush()
        XCTAssertEqual(first.host.executedReloadCount, firstReloads)
        try first.assertCounts(style: 2, body: 12, name: "shared")

        first.close()
        try second.activate("shared.style.increment")
        second.flush()
        try second.assertCounts(style: 1, body: 11, name: "shared")
    }

    func testKeyedReorderAndReinsertionRetainOnlySurvivingStyleAndBodyOwners() async throws {
        let model = ProgressMountedModel()
        let source = ProgressMountedCountingStyle(name: "row", styleSeed: 0, bodySeed: 10)
        let fixture = ProgressMountedWindow(
            ProgressMountedParent(model: model) {
                VStack {
                    ForEach(model.rows, id: \.self) { row in
                        ProgressView(value: 0.5).accessibilityIdentifier("row.\(row.value)")
                    }
                }
                .progressViewStyle(source)
            })
        defer { fixture.close() }
        try fixture.activate("row.style.increment", within: "row.1")
        try fixture.activate("row.body.increment", within: "row.1")
        try fixture.activate("row.body.increment", within: "row.2")
        fixture.flush()
        let first = try fixture.node("row.body.value", within: "row.1")
        let second = try fixture.node("row.body.value", within: "row.2")

        model.rows = [2, 3, 1].map(ProgressMountedRow.init)
        fixture.flush()

        try fixture.assertCounts(style: 1, body: 11, name: "row", within: "row.1")
        try fixture.assertCounts(style: 0, body: 11, name: "row", within: "row.2")
        try fixture.assertCounts(style: 0, body: 10, name: "row", within: "row.3")
        XCTAssertTrue(try fixture.node("row.body.value", within: "row.1") === first)
        XCTAssertTrue(try fixture.node("row.body.value", within: "row.2") === second)

        model.rows = [2, 3].map(ProgressMountedRow.init)
        fixture.flush()
        model.rows = [1, 2, 3].map(ProgressMountedRow.init)
        fixture.flush()

        try fixture.assertCounts(style: 0, body: 10, name: "row", within: "row.1")
        try fixture.assertCounts(style: 0, body: 11, name: "row", within: "row.2")
        XCTAssertFalse(try fixture.node("row.body.value", within: "row.1") === first)
        XCTAssertTrue(try fixture.node("row.body.value", within: "row.2") === second)
    }

    func testConditionalStyleReplacementPreservesFollowingSiblingState() async throws {
        let model = ProgressMountedModel()
        let fixture = ProgressMountedWindow(
            ProgressMountedParent(model: model) {
                if model.firstBranch {
                    ProgressView(value: 0.25)
                        .progressViewStyle(ProgressMountedCountingStyle(name: "branch", styleSeed: 10, bodySeed: 100))
                } else {
                    ProgressView(value: 0.75)
                        .progressViewStyle(ProgressMountedCountingStyle(name: "branch", styleSeed: 20, bodySeed: 200))
                }
                ProgressView(value: 0.5)
                    .progressViewStyle(ProgressMountedCountingStyle(name: "following", styleSeed: 30, bodySeed: 300))
            })
        defer { fixture.close() }
        try fixture.activate("branch.style.increment")
        try fixture.activate("branch.body.increment")
        try fixture.activate("following.style.increment")
        try fixture.activate("following.body.increment")
        fixture.flush()
        let following = try fixture.node("following.body.value")
        try fixture.assertCounts(style: 11, body: 101, name: "branch")

        model.firstBranch = false
        fixture.flush()
        try fixture.assertCounts(style: 20, body: 200, name: "branch")
        try fixture.assertCounts(style: 31, body: 301, name: "following")
        model.firstBranch = true
        fixture.flush()

        try fixture.assertCounts(style: 10, body: 100, name: "branch")
        try fixture.assertCounts(style: 31, body: 301, name: "following")
        XCTAssertTrue(try fixture.node("following.body.value") === following)
    }

    func testConfigurationLabelRolesHaveIndependentStateAcrossParentRebuilds() async throws {
        let model = ProgressMountedModel()
        let fixture = ProgressMountedWindow(
            ProgressMountedParent(model: model) {
                ProgressView(
                    value: model.progress,
                    label: { ProgressMountedLabel(name: "shared.label", seed: model.revision + 3) },
                    currentValueLabel: { ProgressMountedLabel(name: "shared.label", seed: model.revision + 3) }
                )
                .progressViewStyle(ProgressMountedCountingStyle(name: "progress", styleSeed: 0, bodySeed: 0))
            })
        defer { fixture.close() }
        let label = try fixture.node("shared.label.value", within: "progress.label")
        let current = try fixture.node("shared.label.value", within: "progress.current")
        XCTAssertNotEqual(try XCTUnwrap(label.retainedViewIdentity), try XCTUnwrap(current.retainedViewIdentity))
        try fixture.activate("shared.label.increment", within: "progress.label")
        try fixture.activate("shared.label.increment", within: "progress.current")
        try fixture.activate("shared.label.increment", within: "progress.current")
        model.revision = 100
        model.progress = 0.75
        fixture.flush()

        try fixture.assertText("4", "shared.label.value", within: "progress.label")
        try fixture.assertText("5", "shared.label.value", within: "progress.current")
        try fixture.assertText("0.75", "progress.fraction")
        XCTAssertTrue(try fixture.node("shared.label.value", within: "progress.label") === label)
        XCTAssertTrue(try fixture.node("shared.label.value", within: "progress.current") === current)
    }

    func testConfigurationDelegateKeepsStatefulLabelAndCurrentValueLabelOwnersSeparate() async throws {
        let model = ProgressMountedModel()
        let fixture = ProgressMountedWindow(
            ProgressMountedParent(model: model) {
                progressMountedDelegatedLabels(model: model)
            })
        defer { fixture.close() }
        let label = try fixture.node("delegated.value", within: "delegated.label")
        let current = try fixture.node("delegated.value", within: "delegated.current")
        XCTAssertFalse(label === current)
        XCTAssertNotEqual(try XCTUnwrap(label.retainedViewIdentity), try XCTUnwrap(current.retainedViewIdentity))

        try fixture.activate("delegated.increment", within: "delegated.label")
        try fixture.activate("delegated.increment", within: "delegated.current")
        try fixture.activate("delegated.increment", within: "delegated.current")
        model.revision = 100
        model.progress = 0.75
        fixture.flush()

        try fixture.assertText("4", "delegated.value", within: "delegated.label")
        try fixture.assertText("5", "delegated.value", within: "delegated.current")
        XCTAssertTrue(try fixture.node("delegated.value", within: "delegated.label") === label)
        XCTAssertTrue(try fixture.node("delegated.value", within: "delegated.current") === current)
        try fixture.activate("delegated.increment", within: "delegated.label")
        fixture.flush()
        try fixture.assertText("5", "delegated.value", within: "delegated.label")
        try fixture.assertText("5", "delegated.value", within: "delegated.current")
    }

    func testRepeatedConfigurationLabelsBuildDistinctMountedOwners() async throws {
        let model = ProgressMountedModel()
        let fixture = ProgressMountedWindow(
            ProgressMountedParent(model: model) {
                ProgressView(
                    value: model.progress,
                    label: { ProgressMountedLabel(name: "label", seed: model.revision + 1) },
                    currentValueLabel: { ProgressMountedLabel(name: "current", seed: model.revision + 10) }
                )
                .progressViewStyle(ProgressMountedRepeatingLabelsStyle())
            })
        defer { fixture.close() }
        let firstLabel = try fixture.node("label.value", within: "first")
        let secondLabel = try fixture.node("label.value", within: "second")
        let firstCurrent = try fixture.node("current.value", within: "first")
        let secondCurrent = try fixture.node("current.value", within: "second")
        XCTAssertFalse(firstLabel === secondLabel)
        XCTAssertFalse(firstCurrent === secondCurrent)
        XCTAssertNotEqual(firstLabel.retainedViewIdentity, secondLabel.retainedViewIdentity)
        XCTAssertNotEqual(firstCurrent.retainedViewIdentity, secondCurrent.retainedViewIdentity)

        try fixture.activate("label.increment", within: "first")
        try fixture.activate("current.increment", within: "second")
        model.revision = 100
        fixture.flush()

        try fixture.assertText("2", "label.value", within: "first")
        try fixture.assertText("1", "label.value", within: "second")
        try fixture.assertText("10", "current.value", within: "first")
        try fixture.assertText("11", "current.value", within: "second")
        XCTAssertTrue(try fixture.node("label.value", within: "first") === firstLabel)
        XCTAssertTrue(try fixture.node("current.value", within: "second") === secondCurrent)
    }

    func testNestedSameTypeOverrideHasIndependentStyleAndBodyIdentity() async throws {
        let model = ProgressMountedModel()
        let fixture = ProgressMountedWindow(
            ProgressMountedParent(model: model) {
                ProgressView(value: model.progress)
                    .progressViewStyle(
                        ProgressMountedCountingStyle(
                            name: "outer", styleSeed: 10, bodySeed: 20, nestsOverride: model.showsNested))
            })
        defer { fixture.close() }
        let outer = try fixture.node("outer.body.value")
        let inner = try fixture.node("nested.body.value")
        XCTAssertNotEqual(try XCTUnwrap(outer.retainedViewIdentity), try XCTUnwrap(inner.retainedViewIdentity))
        try fixture.activate("outer.style.increment")
        try fixture.activate("outer.body.increment")
        try fixture.activate("nested.style.increment")
        try fixture.activate("nested.body.increment")
        model.revision += 1
        fixture.flush()
        try fixture.assertCounts(style: 11, body: 21, name: "outer")
        try fixture.assertCounts(style: 31, body: 41, name: "nested")

        model.showsNested = false
        fixture.flush()
        XCTAssertFalse(fixture.contains("nested.body.value"))
        try fixture.assertCounts(style: 11, body: 21, name: "outer")
        model.showsNested = true
        fixture.flush()

        try fixture.assertCounts(style: 11, body: 21, name: "outer")
        try fixture.assertCounts(style: 30, body: 40, name: "nested")
        XCTAssertTrue(try fixture.node("outer.body.value") === outer)
        XCTAssertFalse(try fixture.node("nested.body.value") === inner)
    }

    func testRemovedProgressRejectsEscapedStyleBodyAndLabelWritesAfterReinsertion() async throws {
        let model = ProgressMountedModel()
        let capture = ProgressMountedCapture()
        let fixture = ProgressMountedWindow(
            ProgressMountedParent(model: model) {
                if model.showsChild { progressMountedCapturedLabels(capture: capture) }
            })
        defer { fixture.close() }
        let names = ["progress.style", "progress.body", "label", "current"]
        for name in names { try fixture.activate("\(name).increment") }
        fixture.flush()
        let escaped = try names.map { try capture.binding($0) }

        model.showsChild = false
        fixture.flush()
        XCTAssertFalse(fixture.contains("progress.body.value"))
        let removedReloads = fixture.host.executedReloadCount
        for binding in escaped { binding.wrappedValue = 99 }
        await fixture.drain()
        XCTAssertEqual(escaped.map(\.wrappedValue), [1, 1, 1, 1])
        XCTAssertEqual(fixture.host.executedReloadCount, removedReloads)

        model.showsChild = true
        fixture.flush()
        let reinsertedReloads = fixture.host.executedReloadCount
        for binding in escaped { binding.wrappedValue = 100 }
        await fixture.drain()

        XCTAssertEqual(escaped.map(\.wrappedValue), [1, 1, 1, 1])
        XCTAssertEqual(fixture.host.executedReloadCount, reinsertedReloads)
        for name in names { try fixture.assertText("0", "\(name).value") }
        try fixture.activate("label.increment")
        fixture.flush()
        try fixture.assertText("1", "label.value")
        try fixture.assertCounts(style: 0, body: 0, name: "progress")
    }

    func testClosedHostRejectsEscapedStyleBodyAndLabelWritesWithoutReloading() async throws {
        let capture = ProgressMountedCapture()
        let fixture = ProgressMountedWindow(progressMountedCapturedLabels(capture: capture))
        defer { fixture.close() }
        let names = ["progress.style", "progress.body", "label", "current"]
        let escaped = try names.map { try capture.binding($0) }
        for binding in escaped { binding.wrappedValue = 4 }
        fixture.flush()
        for name in names { try fixture.assertText("4", "\(name).value") }

        fixture.close()
        let reloads = fixture.host.executedReloadCount
        let frames = fixture.renderer.frameCount
        for binding in escaped { binding.wrappedValue = 99 }
        await fixture.drain()

        XCTAssertEqual(escaped.map(\.wrappedValue), [4, 4, 4, 4])
        XCTAssertEqual(fixture.host.executedReloadCount, reloads)
        XCTAssertEqual(fixture.renderer.frameCount, frames)
        XCTAssertEqual(fixture.renderer.detachCount, 1)
        XCTAssertFalse(fixture.host.currentTimerState.isEnabled)
    }

    func testSynchronousMakeBodyCloseDoesNotAdoptOrReactivateTheCandidate() async throws {
        let probe = ProgressMountedEpochProbe()
        let fixture = ProgressMountedWindow(ProgressMountedEpochRoot(probe: probe), epoch: probe)
        defer { fixture.close() }
        let phase = try XCTUnwrap(probe.phase)
        probe.onStyleMakeBody = { [weak probe] phase in
            guard let probe, phase == 1 else { return }
            probe.onStyleMakeBody = nil
            if let host = probe.host { host.windowWillClose(host.platformWindow) }
        }

        try fixture.activate("epoch.next")
        await fixture.drain()

        XCTAssertTrue(probe.stylePhases.contains(1), "The close must interrupt authored makeBody")
        XCTAssertFalse(probe.appearedPhases.contains(1))
        XCTAssertFalse(fixture.contains("candidate.style.value"))
        XCTAssertFalse(probe.completedTexts.contains { $0.contains("candidate style=10") })
        XCTAssertEqual(probe.closeCount, 1)
        XCTAssertEqual(fixture.renderer.detachCount, 1)
        let candidate = try XCTUnwrap(probe.styleBindings[1])
        let reloads = fixture.host.executedReloadCount
        let frames = fixture.renderer.frameCount

        attemptRetiredProgressMountedRecordWrite(candidate, probe: probe)
        phase.wrappedValue = 2
        await fixture.drain()

        XCTAssertEqual(candidate.wrappedValue.count, 10)
        XCTAssertNil(probe.rejectedPayload)
        XCTAssertEqual(fixture.host.executedReloadCount, reloads)
        XCTAssertEqual(fixture.renderer.frameCount, frames)
        XCTAssertEqual(probe.closeCount, 1)
        XCTAssertFalse(fixture.host.currentTimerState.isEnabled)
    }

    func testSynchronousMakeBodySupersedesAndRetiresCandidateWhileKeepingCommittedState() async throws {
        let probe = ProgressMountedEpochProbe()
        let fixture = ProgressMountedWindow(ProgressMountedEpochRoot(probe: probe), epoch: probe)
        defer { fixture.close() }
        try fixture.activate("accepted.style.increment")
        try fixture.activate("accepted.body.increment")
        fixture.flush()
        let original = try fixture.node("accepted.body.value")
        let acceptedStyle = try XCTUnwrap(probe.styleBindings[0])
        let acceptedBody = try XCTUnwrap(probe.bodyBindings[0])
        let phase = try XCTUnwrap(probe.phase)
        probe.onCheckpointMakeBody = { [weak probe] candidatePhase in
            guard let probe, candidatePhase == 1 else { return }
            probe.onCheckpointMakeBody = nil
            phase.wrappedValue = 2
        }

        try fixture.activate("epoch.next")
        await fixture.drain()

        XCTAssertTrue(probe.stylePhases.contains(1))
        XCTAssertTrue(probe.bodyPhases.contains(1), "Build provisional body state before the later style supersedes it")
        XCTAssertFalse(probe.appearedPhases.contains(1))
        XCTAssertFalse(probe.completedTexts.contains { $0.contains("candidate body=110") })
        XCTAssertFalse(fixture.contains("candidate.body.value"))
        try fixture.assertText("accepted style=1", "accepted.style.value")
        try fixture.assertText("accepted body=101", "accepted.body.value")
        XCTAssertTrue(try fixture.node("accepted.body.value") === original)
        var abandonedStyle: Binding<ProgressMountedRecord>? = try XCTUnwrap(probe.styleBindings[1])
        var abandonedBody: Binding<ProgressMountedRecord>? = try XCTUnwrap(probe.bodyBindings[1])
        weak var stylePayload = abandonedStyle?.wrappedValue.payload
        weak var bodyPayload = abandonedBody?.wrappedValue.payload
        XCTAssertNotNil(stylePayload)
        XCTAssertNotNil(bodyPayload)
        let reloads = fixture.host.executedReloadCount

        attemptRetiredProgressMountedRecordWrite(try XCTUnwrap(abandonedStyle), probe: probe)
        XCTAssertNil(probe.rejectedPayload)
        attemptRetiredProgressMountedRecordWrite(try XCTUnwrap(abandonedBody), probe: probe)
        XCTAssertNil(probe.rejectedPayload)
        await fixture.drain()

        XCTAssertEqual(abandonedStyle?.wrappedValue.count, 10)
        XCTAssertEqual(abandonedBody?.wrappedValue.count, 110)
        XCTAssertEqual(fixture.host.executedReloadCount, reloads)
        acceptedStyle.wrappedValue.count += 1
        acceptedBody.wrappedValue.count += 1
        await fixture.drain()
        try fixture.assertText("accepted style=2", "accepted.style.value")
        try fixture.assertText("accepted body=102", "accepted.body.value")
        XCTAssertTrue(try fixture.node("accepted.body.value") === original)

        probe.styleBindings[1] = nil
        probe.bodyBindings[1] = nil
        abandonedStyle = nil
        abandonedBody = nil
        await fixture.drain()
        XCTAssertNil(stylePayload, "Discarded style state has no registry or external read owner")
        XCTAssertNil(bodyPayload, "Discarded body state has no registry or external read owner")
    }
}

@MainActor
private final class ProgressMountedModel: ObservableObject {
    @Published var revision = 0
    @Published var progress = 0.25
    @Published var rows = [1, 2].map(ProgressMountedRow.init)
    @Published var usesAlternate = false
    @Published var firstBranch = true
    @Published var showsChild = true
    @Published var showsNested = true
}

private struct ProgressMountedRow: Hashable, CustomStringConvertible {
    let value: Int
    var description: String { "shared" }
}

@MainActor
private struct ProgressMountedParent: View {
    @ObservedObject private var model: ProgressMountedModel
    private let content: @MainActor () -> [AnyView]

    init(model: ProgressMountedModel, @ViewBuilder content: @escaping @MainActor () -> [AnyView]) {
        self.model = model
        self.content = content
    }

    var body: some View {
        let revision = model.revision
        return VStack(alignment: .leading, spacing: 8) {
            Text("Parent \(revision)").accessibilityIdentifier("parent.revision")
            content()
        }
    }
}

@MainActor
private final class ProgressMountedCapture {
    var bindings: [String: Binding<Int>] = [:]
    var makeBodyValues: [String: [Int]] = [:]

    func recordStyle(name: String, value: Int, binding: Binding<Int>) {
        bindings["\(name).style"] = binding
        makeBodyValues[name, default: []].append(value)
    }

    func binding(_ name: String, file: StaticString = #filePath, line: UInt = #line) throws -> Binding<Int> {
        try XCTUnwrap(bindings[name], "Expected a mounted binding for \(name)", file: file, line: line)
    }
}

@MainActor
private struct ProgressMountedCountingStyle: ProgressViewStyle {
    @State private var count: Int
    let name: String
    let bodySeed: Int
    let capture: ProgressMountedCapture?
    let nestsOverride: Bool

    init(
        name: String, styleSeed: Int, bodySeed: Int,
        capture: ProgressMountedCapture? = nil, nestsOverride: Bool = false
    ) {
        self.name = name
        self.bodySeed = bodySeed
        self.capture = capture
        self.nestsOverride = nestsOverride
        _count = State(initialValue: styleSeed)
    }

    func makeBody(configuration: Configuration) -> ProgressMountedCountingBody {
        let value = count
        capture?.recordStyle(name: name, value: value, binding: $count)
        return ProgressMountedCountingBody(
            name: name, seed: bodySeed, styleValue: value, styleBinding: $count,
            configuration: configuration, capture: capture, nestsOverride: nestsOverride)
    }
}

@MainActor
private struct ProgressMountedAlternateStyle: ProgressViewStyle {
    @State private var count = 70
    let capture: ProgressMountedCapture

    func makeBody(configuration: Configuration) -> ProgressMountedCountingBody {
        let value = count
        capture.recordStyle(name: "progress", value: value, binding: $count)
        return ProgressMountedCountingBody(
            name: "progress", seed: 80, styleValue: value, styleBinding: $count,
            configuration: configuration, capture: capture, nestsOverride: false)
    }
}

@MainActor
private func progressMountedSelectedStyle(model: ProgressMountedModel, capture: ProgressMountedCapture) -> AnyView {
    let source = ProgressView(value: model.progress)
    if model.usesAlternate {
        return AnyView(source.progressViewStyle(ProgressMountedAlternateStyle(capture: capture)))
    }
    return AnyView(
        source.progressViewStyle(
            ProgressMountedCountingStyle(name: "progress", styleSeed: 10, bodySeed: 20, capture: capture)))
}

@MainActor
private struct ProgressMountedCountingBody: View {
    @State private var count: Int
    let name: String
    let styleValue: Int
    let styleBinding: Binding<Int>
    let configuration: ProgressViewStyleConfiguration
    let capture: ProgressMountedCapture?
    let nestsOverride: Bool

    init(
        name: String, seed: Int, styleValue: Int, styleBinding: Binding<Int>,
        configuration: ProgressViewStyleConfiguration, capture: ProgressMountedCapture?, nestsOverride: Bool
    ) {
        self.name = name
        self.styleValue = styleValue
        self.styleBinding = styleBinding
        self.configuration = configuration
        self.capture = capture
        self.nestsOverride = nestsOverride
        _count = State(initialValue: seed)
    }

    var body: some View {
        let value = count
        capture?.bindings["\(name).body"] = $count
        return VStack(alignment: .leading, spacing: 2) {
            Text(String(styleValue)).accessibilityIdentifier("\(name).style.value")
            Button("Increment \(name) style") { styleBinding.wrappedValue += 1 }
                .accessibilityIdentifier("\(name).style.increment")
            Text(String(value)).accessibilityIdentifier("\(name).body.value")
            Button("Increment \(name) body") { count += 1 }
                .accessibilityIdentifier("\(name).body.increment")
            Text(configuration.fractionCompleted.map { String($0) } ?? "nil")
                .accessibilityIdentifier("\(name).fraction")
            if let label = configuration.label {
                VStack { label }.accessibilityIdentifier("\(name).label")
            }
            if let current = configuration.currentValueLabel {
                VStack { current }.accessibilityIdentifier("\(name).current")
            }
            if nestsOverride {
                ProgressView(configuration)
                    .progressViewStyle(ProgressMountedCountingStyle(name: "nested", styleSeed: 30, bodySeed: 40))
            }
        }
    }
}

@MainActor
private struct ProgressMountedLabel: View {
    @State private var count: Int
    let name: String
    let capture: ProgressMountedCapture?

    init(name: String, seed: Int, capture: ProgressMountedCapture? = nil) {
        self.name = name
        self.capture = capture
        _count = State(initialValue: seed)
    }

    var body: some View {
        let value = count
        capture?.bindings[name] = $count
        return VStack(alignment: .leading, spacing: 2) {
            Text(String(value)).accessibilityIdentifier("\(name).value")
            Button("Increment \(name)") { count += 1 }.accessibilityIdentifier("\(name).increment")
        }
    }
}

@MainActor
private struct ProgressMountedRepeatingLabelsStyle: ProgressViewStyle {
    func makeBody(configuration: Configuration) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack {
                configuration.label
                configuration.currentValueLabel
            }
            .accessibilityIdentifier("first")
            VStack {
                configuration.label
                configuration.currentValueLabel
            }
            .accessibilityIdentifier("second")
        }
    }
}

@MainActor
private struct ProgressMountedDelegatingStyle: ProgressViewStyle {
    func makeBody(configuration: Configuration) -> some View {
        ProgressView(configuration)
    }
}

@MainActor
private func progressMountedDelegatedLabels(model: ProgressMountedModel) -> some View {
    let source = ProgressMountedLabel(name: "delegated", seed: model.revision + 3)
    return ProgressView(
        value: model.progress,
        label: { source.accessibilityIdentifier("delegated.label") },
        currentValueLabel: { source.accessibilityIdentifier("delegated.current") }
    )
    .progressViewStyle(ProgressMountedDelegatingStyle())
}

@MainActor
private func progressMountedCapturedLabels(capture: ProgressMountedCapture) -> some View {
    ProgressView(
        value: 0.5,
        label: { ProgressMountedLabel(name: "label", seed: 0, capture: capture) },
        currentValueLabel: { ProgressMountedLabel(name: "current", seed: 0, capture: capture) }
    )
    .progressViewStyle(ProgressMountedCountingStyle(name: "progress", styleSeed: 0, bodySeed: 0, capture: capture))
}

private final class ProgressMountedPayload {}

private struct ProgressMountedRecord {
    var count: Int
    var payload: ProgressMountedPayload?
}

@MainActor
private final class ProgressMountedEpochProbe {
    weak var host: WinSwiftUIWindowHost?
    weak var rejectedPayload: ProgressMountedPayload?
    var phase: Binding<Int>?
    var styleBindings: [Int: Binding<ProgressMountedRecord>] = [:]
    var bodyBindings: [Int: Binding<ProgressMountedRecord>] = [:]
    var stylePhases: [Int] = []
    var bodyPhases: [Int] = []
    var appearedPhases: [Int] = []
    var completedTexts: [[String]] = []
    var onStyleMakeBody: ((Int) -> Void)?
    var onCheckpointMakeBody: ((Int) -> Void)?
    var closeCount = 0
}

@MainActor
private struct ProgressMountedEpochRoot: View {
    @State private var phase = 0
    let probe: ProgressMountedEpochProbe

    var body: some View {
        let value = phase
        probe.phase = $phase
        return VStack(alignment: .leading, spacing: 8) {
            Button("Build candidate") { phase = 1 }.accessibilityIdentifier("epoch.next")
            if value == 1 {
                ProgressView(value: 0.5)
                    .progressViewStyle(ProgressMountedEpochStyle(name: "candidate", phase: value, probe: probe))
            } else {
                ProgressView(value: 0.5)
                    .progressViewStyle(ProgressMountedEpochStyle(name: "accepted", phase: value, probe: probe))
            }
            ProgressView(value: 0.5)
                .progressViewStyle(ProgressMountedCheckpointStyle(phase: value, probe: probe))
        }
    }
}

@MainActor
private struct ProgressMountedEpochStyle: ProgressViewStyle {
    @State private var record: ProgressMountedRecord
    let name: String
    let phase: Int
    let probe: ProgressMountedEpochProbe

    init(name: String, phase: Int, probe: ProgressMountedEpochProbe) {
        self.name = name
        self.phase = phase
        self.probe = probe
        _record = State(initialValue: ProgressMountedRecord(count: phase * 10, payload: ProgressMountedPayload()))
    }

    func makeBody(configuration: Configuration) -> ProgressMountedEpochBody {
        let count = record.count
        probe.styleBindings[phase] = $record
        probe.stylePhases.append(phase)
        probe.onStyleMakeBody?(phase)
        return ProgressMountedEpochBody(name: name, phase: phase, styleCount: count, style: $record, probe: probe)
    }
}

@MainActor
private struct ProgressMountedEpochBody: View {
    @State private var record: ProgressMountedRecord
    let name: String
    let phase: Int
    let styleCount: Int
    let style: Binding<ProgressMountedRecord>
    let probe: ProgressMountedEpochProbe

    init(
        name: String, phase: Int, styleCount: Int,
        style: Binding<ProgressMountedRecord>, probe: ProgressMountedEpochProbe
    ) {
        self.name = name
        self.phase = phase
        self.styleCount = styleCount
        self.style = style
        self.probe = probe
        _record = State(initialValue: ProgressMountedRecord(count: 100 + phase * 10, payload: ProgressMountedPayload()))
    }

    var body: some View {
        let count = record.count
        probe.bodyBindings[phase] = $record
        probe.bodyPhases.append(phase)
        return VStack(alignment: .leading, spacing: 2) {
            Text("\(name) style=\(styleCount)").accessibilityIdentifier("\(name).style.value")
            Button("Increment \(name) style") { style.wrappedValue.count += 1 }
                .accessibilityIdentifier("\(name).style.increment")
            Text("\(name) body=\(count)").accessibilityIdentifier("\(name).body.value")
            Button("Increment \(name) body") { record.count += 1 }
                .accessibilityIdentifier("\(name).body.increment")
        }
        .onAppear { probe.appearedPhases.append(phase) }
    }
}

@MainActor
private struct ProgressMountedCheckpointStyle: ProgressViewStyle {
    let phase: Int
    let probe: ProgressMountedEpochProbe

    func makeBody(configuration: Configuration) -> some View {
        probe.onCheckpointMakeBody?(phase)
        return Text("Checkpoint \(phase)").accessibilityIdentifier("epoch.checkpoint")
    }
}

@MainActor
private func attemptRetiredProgressMountedRecordWrite(
    _ binding: Binding<ProgressMountedRecord>, probe: ProgressMountedEpochProbe
) {
    let payload = ProgressMountedPayload()
    probe.rejectedPayload = payload
    binding.wrappedValue = ProgressMountedRecord(count: 999, payload: payload)
}

@MainActor
private func progressMountedConfiguration<Content: View>(_ content: Content) -> WindowGroupConfiguration {
    WindowGroupConfiguration(
        title: "Progress style ownership", size: IntSize(width: 640, height: 900), clearColor: .black,
        content: [AnyView(content)])
}

@MainActor
private final class ProgressMountedClock {
    var now = 5_000.0
}

@MainActor
private final class ProgressMountedRenderer: RenderBackend {
    private(set) var frameCount = 0
    private(set) var detachCount = 0

    func attach(to surface: SurfaceDescriptor) throws {}
    func resize(to size: IntSize) throws {}
    func render(frame: RenderFrame) throws { frameCount += 1 }
    func detach() { detachCount += 1 }
}

/// The fake surface never creates an HWND; retained text/layout may still call DirectWrite or GDI.
@MainActor
private final class ProgressMountedWindow {
    let host: WinSwiftUIWindowHost
    let window: Win32Window
    let clock: ProgressMountedClock
    let renderer: ProgressMountedRenderer

    var runtime: RetainedViewRuntime { host.hostedRuntime }

    convenience init<Content: View>(_ content: Content, epoch: ProgressMountedEpochProbe? = nil) {
        self.init(configuration: progressMountedConfiguration(content), epoch: epoch)
    }

    init(configuration: WindowGroupConfiguration, epoch: ProgressMountedEpochProbe? = nil) {
        let clock = ProgressMountedClock()
        let renderer = ProgressMountedRenderer()
        let surface = SurfaceDescriptor(
            windowHandle: NativeWindowHandle(rawPointer: UnsafeMutableRawPointer(bitPattern: 0x1))!,
            pixelSize: configuration.size, scaleFactor: 1)
        let window = Win32Window(title: configuration.title, clientSize: configuration.size)
        let host = WinSwiftUIWindowHost(
            configuration: configuration, platformWindow: window,
            renderer: renderer, batchRenderer: nil,
            surfaceDescriptorProvider: { _ in surface }, startupProbeConfiguration: nil)
        self.clock = clock
        self.renderer = renderer
        self.window = window
        self.host = host
        if let epoch {
            epoch.host = host
            host.onWindowClosed = { [weak epoch] _ in epoch?.closeCount += 1 }
            host.onReloadContentCompleted = { [weak host, weak epoch] in
                guard let host, let epoch else { return }
                epoch.completedTexts.append(progressMountedNodes(in: host.hostedRuntime.root).compactMap(\.text))
            }
        }
        host.frameClock = { clock.now }
        host.hostedRuntime.clock = { clock.now }
        host.windowDidCreate(window)
        flush()
        host.resetObservabilityCounters()
    }

    func flush() {
        for _ in 0..<2 {
            clock.now += 0.02
            host.windowNeedsDisplay(window)
        }
    }

    func drain() async {
        for _ in 0..<3 {
            flush()
            await Task.yield()
        }
    }

    func close() { host.windowWillClose(window) }

    func contains(_ identifier: String) -> Bool {
        progressMountedNodes(in: runtime.root).contains { $0.accessibilityIdentifier == identifier }
    }

    func node(
        _ identifier: String, within scope: String? = nil,
        file: StaticString = #filePath, line: UInt = #line
    ) throws -> ViewNode {
        let root = try scope.map { try node($0, file: file, line: line) } ?? runtime.root
        let matches = progressMountedNodes(in: root).filter { $0.accessibilityIdentifier == identifier }
        XCTAssertEqual(matches.count, 1, "Expected one node identified as \(identifier)", file: file, line: line)
        return try XCTUnwrap(matches.first, file: file, line: line)
    }

    func activate(_ identifier: String, within scope: String? = nil) throws {
        let identified = try node(identifier, within: scope)
        let control = try XCTUnwrap(
            progressMountedNodes(in: identified).first { $0.isFocusable && $0.onActivate != nil })
        runtime.requestFocus(control)
        XCTAssertTrue(runtime.focusedNode === control)
        host.window(window, keyDown: KeyboardEvent(keyCode: KeyboardKey.space.rawValue))
    }

    func assertText(
        _ expected: String, _ identifier: String, within scope: String? = nil,
        file: StaticString = #filePath, line: UInt = #line
    ) throws {
        let actual = try node(identifier, within: scope, file: file, line: line).text
        XCTAssertEqual(actual, expected, file: file, line: line)
    }

    func assertCounts(
        style: Int, body: Int, name: String, within scope: String? = nil,
        file: StaticString = #filePath, line: UInt = #line
    ) throws {
        try assertText(String(style), "\(name).style.value", within: scope, file: file, line: line)
        try assertText(String(body), "\(name).body.value", within: scope, file: file, line: line)
    }
}

@MainActor
private func progressMountedNodes(in node: ViewNode) -> [ViewNode] {
    [node] + node.children.flatMap { progressMountedNodes(in: $0) }
}
