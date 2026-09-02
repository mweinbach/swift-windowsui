import SwiftWindowsCore
@preconcurrency import XCTest

@testable import SwiftWindowsUI
@testable import WinSwiftUI

@MainActor
final class MountedDescriptorOwnerRenewalTests: XCTestCase {
    func testRemovedButtonRenewsOuterModifierOwnerWhenExplicitIDChanges() async throws {
        try assertButtonRestoration(changesExplicitID: true)
    }

    func testRemovedButtonRenewsOwnerWithoutReusingRetiredPhysicalAction() async throws {
        try assertButtonRestoration(changesExplicitID: false)
    }

    func testRemovedStateOutputStartsFreshGenerationAndLeavesOldBindingRevoked() async throws {
        let probe = DescriptorOwnerRenewalProbe()
        let host = MountedOnChangeTestHost {
            AnyView(DescriptorOwnerRenewalStateValue(probe: probe))
        }
        defer { host.close() }
        host.render()
        let original = try XCTUnwrap(probe.latest)
        original.value.wrappedValue = 7
        host.render()
        XCTAssertTrue(try XCTUnwrap(probe.latest).owner === original.owner)
        XCTAssertEqual(original.value.wrappedValue, 7)
        let departed = try XCTUnwrap(descriptorRenewalNode("renewal.value", in: host.runtime.root))
        XCTAssertEqual(departed.text, "value=7")
        let parent = try XCTUnwrap(departed.parent)

        parent.removeChild(departed)
        let entriesAfterRemoval = probe.entries
        original.value.wrappedValue = 91
        XCTAssertEqual(original.value.wrappedValue, 7)
        XCTAssertEqual(probe.entries, entriesAfterRemoval)
        XCTAssertNil(departed.parent)

        host.reload()
        host.render()
        let current = try XCTUnwrap(probe.latest)
        let restored = try XCTUnwrap(descriptorRenewalNode("renewal.value", in: host.runtime.root))
        XCTAssertFalse(restored === departed)
        XCTAssertFalse(current.owner === original.owner)
        XCTAssertNotEqual(current.owner.generation, original.owner.generation)
        XCTAssertTrue(current.owner.isLive)
        XCTAssertFalse(original.owner.isLive)
        XCTAssertEqual(current.value.wrappedValue, 0)
        XCTAssertEqual(restored.text, "value=0")

        let entriesAfterRestoration = probe.entries
        original.value.wrappedValue = 92
        XCTAssertEqual(original.value.wrappedValue, 7)
        XCTAssertEqual(current.value.wrappedValue, 0)
        XCTAssertEqual(probe.entries, entriesAfterRestoration)

        current.value.wrappedValue = 3
        host.render()
        XCTAssertTrue(try XCTUnwrap(probe.latest).owner === current.owner)
        XCTAssertEqual(current.value.wrappedValue, 3)
        XCTAssertEqual(descriptorRenewalNode("renewal.value", in: host.runtime.root)?.text, "value=3")
        let entriesAfterSuccessorReload = probe.entries
        original.value.wrappedValue = 93
        XCTAssertEqual(original.value.wrappedValue, 7)
        XCTAssertEqual(current.value.wrappedValue, 3)
        XCTAssertEqual(probe.entries, entriesAfterSuccessorReload)
        XCTAssertNil(departed.parent)
    }

    func testReplacementWinsOverPreservedPredecessorAtTheSameIdentity() async throws {
        let probe = DescriptorOwnerRenewalPreservationProbe()
        let host = MountedOnChangeTestHost {
            AnyView(
                VStack {
                    DescriptorOwnerRenewalPreserver(probe: probe)
                    DescriptorOwnerRenewalMixedStateValue(probe: probe)
                })
        }
        defer { host.close() }
        host.render()
        let original = try XCTUnwrap(probe.latest)
        original.value.wrappedValue = 7
        host.render()
        XCTAssertTrue(try XCTUnwrap(probe.latest).owner === original.owner)
        XCTAssertTrue(try XCTUnwrap(probe.latest).observation === original.observation)
        let departed = try XCTUnwrap(descriptorRenewalNode("renewal.mixed", in: host.runtime.root))
        let parent = try XCTUnwrap(departed.parent)
        parent.removeChild(departed)

        // This compatibility observation shares the State owner, but has no
        // native owned slot. Preserve it before the later sibling requests a
        // replacement so both preservation paths compete with the new owner.
        XCTAssertTrue(original.observation.isWritable)
        probe.predecessor = original
        probe.preservePredecessor = true
        host.reload()
        host.render()
        probe.preservePredecessor = false

        XCTAssertEqual(probe.preservationResults, [true])
        let current = try XCTUnwrap(probe.latest)
        XCTAssertFalse(current.owner === original.owner)
        XCTAssertFalse(current.observation === original.observation)
        XCTAssertTrue(host.coordinator.registry.owner(at: original.owner.identity) === current.owner)
        XCTAssertTrue(current.owner.isLive)
        XCTAssertFalse(original.owner.isLive)
        XCTAssertEqual(current.value.wrappedValue, 0)
        XCTAssertTrue(current.observation.isWritable)
        XCTAssertEqual(current.observation.readValue().value, 11)
        XCTAssertFalse(original.observation.isWritable)
        XCTAssertFalse(original.observation.write(DescriptorOwnerRenewalObservation(value: 99)))
        XCTAssertEqual(original.observation.readValue().value, 11)
        original.value.wrappedValue = 99
        XCTAssertEqual(original.value.wrappedValue, 7)
        XCTAssertEqual(current.value.wrappedValue, 0)

        // Cleanup by the predecessor's generation cannot retire its successor.
        host.coordinator.registry.finishRetirement(of: original.owner.generation)
        current.value.wrappedValue = 9
        host.render()
        XCTAssertTrue(try XCTUnwrap(probe.latest).owner === current.owner)
        XCTAssertTrue(try XCTUnwrap(probe.latest).observation === current.observation)
        XCTAssertTrue(current.observation.isWritable)
        XCTAssertEqual(current.value.wrappedValue, 9)
        XCTAssertEqual(descriptorRenewalNode("renewal.mixed", in: host.runtime.root)?.text, "mixed=9")
        XCTAssertFalse(original.observation.write(DescriptorOwnerRenewalObservation(value: 100)))
        XCTAssertEqual(original.observation.readValue().value, 11)
        XCTAssertNil(departed.parent)
    }

    func testRemovingOneChildPreservesItsStillDeclaredAncestorOwnerAndState() async throws {
        let probe = DescriptorOwnerRenewalProbe()
        let host = MountedOnChangeTestHost {
            AnyView(DescriptorOwnerRenewalStatePair(probe: probe))
        }
        defer { host.close() }
        host.render()
        let original = try XCTUnwrap(probe.latest)
        original.value.wrappedValue = 7
        host.render()
        let first = try XCTUnwrap(descriptorRenewalNode("renewal.first", in: host.runtime.root))
        let second = try XCTUnwrap(descriptorRenewalNode("renewal.second", in: host.runtime.root))
        let parent = try XCTUnwrap(first.parent)
        XCTAssertTrue(second.parent === parent)

        parent.removeChild(first)
        XCTAssertNil(first.parent)
        XCTAssertTrue(second.parent === parent)
        host.reload()
        host.render()

        let current = try XCTUnwrap(probe.latest)
        let restoredFirst = try XCTUnwrap(descriptorRenewalNode("renewal.first", in: host.runtime.root))
        XCTAssertFalse(restoredFirst === first)
        XCTAssertTrue(current.owner === original.owner)
        XCTAssertEqual(current.owner.generation, original.owner.generation)
        XCTAssertTrue(current.owner.isLive)
        XCTAssertEqual(current.value.wrappedValue, 7)
        XCTAssertEqual(restoredFirst.text, "first=7")
        XCTAssertEqual(descriptorRenewalNode("renewal.second", in: host.runtime.root)?.text, "second=7")

        original.value.wrappedValue = 8
        host.render()
        XCTAssertTrue(try XCTUnwrap(probe.latest).owner === original.owner)
        XCTAssertEqual(descriptorRenewalNode("renewal.first", in: host.runtime.root)?.text, "first=8")
        XCTAssertEqual(descriptorRenewalNode("renewal.second", in: host.runtime.root)?.text, "second=8")
    }

    private func assertButtonRestoration(
        changesExplicitID: Bool, file: StaticString = #filePath, line: UInt = #line
    ) throws {
        var generation = 0
        var calls = 0
        var rootType: ObjectIdentifier?
        let host = MountedOnChangeTestHost {
            let value = AnyView(
                Button("Action") { calls += 1 }
                    .accessibilityIdentifier("renewal.action")
                    .id(generation))
            rootType = value.viewTypeIdentifier
            return value
        }
        defer { host.close() }
        host.render()
        let originalNode = try descriptorRenewalButton(in: host, file: file, line: line)
        let originalProjection = try descriptorRenewalProjection(
            for: originalNode, in: host.runtime, file: file, line: line)
        XCTAssertTrue(originalProjection.actions.isEmpty, file: file, line: line)
        XCTAssertTrue(originalProjection.invokeDefaultAction(), file: file, line: line)
        host.render()
        XCTAssertEqual(calls, 1, file: file, line: line)
        XCTAssertTrue(
            try descriptorRenewalButton(in: host, file: file, line: line) === originalNode, file: file, line: line)

        // The outer modifier is installed before its explicit ID is appended
        // to descendant paths. Its lookup key is unchanged in both cases.
        let originalType = try XCTUnwrap(rootType, file: file, line: line)
        let identity = RetainedViewIdentity().appending(.view(originalType))
        let originalOwner = try XCTUnwrap(host.coordinator.registry.owner(at: identity), file: file, line: line)
        XCTAssertTrue(originalOwner.isLive, file: file, line: line)
        let escapedAction = try XCTUnwrap(originalNode.onActivate, file: file, line: line)
        let parent = try XCTUnwrap(originalNode.parent, file: file, line: line)

        parent.removeChild(originalNode)
        XCTAssertNil(originalNode.parent, file: file, line: line)
        XCTAssertFalse(originalProjection.invokeDefaultAction(), file: file, line: line)
        escapedAction()
        XCTAssertEqual(calls, 1, file: file, line: line)
        if changesExplicitID { generation += 1 }

        host.reload()
        host.render()
        XCTAssertEqual(rootType, originalType, file: file, line: line)
        let currentNode = try descriptorRenewalButton(in: host, file: file, line: line)
        let currentOwner = try XCTUnwrap(host.coordinator.registry.owner(at: identity), file: file, line: line)
        XCTAssertFalse(currentNode === originalNode, file: file, line: line)
        XCTAssertFalse(currentOwner === originalOwner, file: file, line: line)
        XCTAssertNotEqual(currentOwner.generation, originalOwner.generation, file: file, line: line)
        XCTAssertTrue(currentOwner.isLive, file: file, line: line)
        XCTAssertFalse(originalOwner.isLive, file: file, line: line)
        let currentProjection = try descriptorRenewalProjection(
            for: currentNode, in: host.runtime, file: file, line: line)
        XCTAssertTrue(currentProjection.invokeDefaultAction(), file: file, line: line)
        XCTAssertEqual(calls, 2, file: file, line: line)
        XCTAssertFalse(originalProjection.invokeDefaultAction(), file: file, line: line)
        escapedAction()
        XCTAssertEqual(calls, 2, file: file, line: line)
        XCTAssertNil(originalNode.parent, file: file, line: line)
    }
}

@MainActor
private struct DescriptorOwnerRenewalCapture {
    let owner: StateMountOwner
    let value: Binding<Int>
}

@MainActor
private final class DescriptorOwnerRenewalProbe {
    var latest: DescriptorOwnerRenewalCapture?
    var entries = 0

    func record(owner: StateMountOwner?, value: Binding<Int>) {
        entries += 1
        latest = owner.map { DescriptorOwnerRenewalCapture(owner: $0, value: value) }
    }
}

@MainActor
private struct DescriptorOwnerRenewalStateValue: View {
    let probe: DescriptorOwnerRenewalProbe
    @State private var value = 0

    var body: some View {
        probe.record(owner: ViewBuildContextScope.current?.viewIdentity.installedOwner, value: $value)
        return Text("value=\(value)").accessibilityIdentifier("renewal.value")
    }
}

@MainActor
private struct DescriptorOwnerRenewalStatePair: View {
    let probe: DescriptorOwnerRenewalProbe
    @State private var value = 0

    var body: some View {
        probe.record(owner: ViewBuildContextScope.current?.viewIdentity.installedOwner, value: $value)
        return VStack {
            Text("first=\(value)").accessibilityIdentifier("renewal.first")
            Text("second=\(value)").accessibilityIdentifier("renewal.second")
        }
    }
}

private struct DescriptorOwnerRenewalObservation {
    let value: Int
}

@MainActor
private struct DescriptorOwnerRenewalMixedCapture {
    let owner: StateMountOwner
    let value: Binding<Int>
    let observation: MountedStateCell<DescriptorOwnerRenewalObservation>
}

@MainActor
private final class DescriptorOwnerRenewalPreservationProbe {
    var latest: DescriptorOwnerRenewalMixedCapture?
    var predecessor: DescriptorOwnerRenewalMixedCapture?
    var preservePredecessor = false
    var preservationResults: [Bool] = []

    func record(value: Binding<Int>) {
        guard let context = ViewBuildContextScope.current,
            let owner = context.viewIdentity.installedOwner,
            let epoch = context.viewIdentity.installedEpoch,
            let observed = epoch.resolveSyntheticObservation(
                at: owner.identity, seed: { DescriptorOwnerRenewalObservation(value: 11) })
        else {
            XCTFail("The stateful value must install its compatibility observation")
            return
        }
        XCTAssertTrue(observed.owner === owner)
        latest = DescriptorOwnerRenewalMixedCapture(owner: owner, value: value, observation: observed.cell)
    }

    func preserve() {
        guard preservePredecessor, let predecessor,
            let epoch = ViewBuildContextScope.current?.viewIdentity.installedEpoch
        else { return }
        let observation = epoch.committedSyntheticObservation(
            at: predecessor.owner.identity, as: DescriptorOwnerRenewalObservation.self)
        preservationResults.append(observation?.prepare(in: epoch) == true)
        epoch.preserveDeclaredSubtree(at: predecessor.owner.identity)
    }
}

@MainActor
private struct DescriptorOwnerRenewalPreserver: View {
    let probe: DescriptorOwnerRenewalPreservationProbe

    var body: some View {
        probe.preserve()
        return Text("Preserver")
    }
}

@MainActor
private struct DescriptorOwnerRenewalMixedStateValue: View {
    let probe: DescriptorOwnerRenewalPreservationProbe
    @State private var value = 0

    var body: some View {
        probe.record(value: $value)
        return Text("mixed=\(value)").accessibilityIdentifier("renewal.mixed")
    }
}

@MainActor
private func descriptorRenewalNode(_ identifier: String, in node: ViewNode) -> ViewNode? {
    if node.accessibilityIdentifier == identifier { return node }
    for child in node.children {
        if let found = descriptorRenewalNode(identifier, in: child) { return found }
    }
    return nil
}

@MainActor
private func descriptorRenewalProjection(
    for node: ViewNode, in runtime: RetainedViewRuntime,
    file: StaticString, line: UInt
) throws -> AccessibilityElementProjection {
    try XCTUnwrap(
        AccessibilityProjection.project(runtime: runtime)?.flattened().first { $0.sourceNode === node },
        file: file, line: line)
}

@MainActor
private func descriptorRenewalButton(
    in host: MountedOnChangeTestHost, file: StaticString, line: UInt
) throws -> ViewNode {
    let element = try XCTUnwrap(
        AccessibilityProjection.project(runtime: host.runtime)?.flattened().first {
            $0.controlType == .button && $0.name == "Action"
        }, file: file, line: line)
    return try XCTUnwrap(element.sourceNode, file: file, line: line)
}
