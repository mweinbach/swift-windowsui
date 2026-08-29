import SwiftWindowsCore
@preconcurrency import XCTest

@testable import SwiftWindowsUI
@testable import WinSwiftUI

/// Exercises the internal managed row route, not public List activation or
/// native scheduling/parity. Every row is built by the production lazy driver.
@MainActor
final class MountedLazyListStateTests: XCTestCase {
    func testFirstViewportVisitAfterRootCommitInstallsStateAndStateObjectOnce() async throws {
        let probe = MountedLazyListStateProbe()
        let host = MountedLazyListTestHost { mountedLazyListStateContent(probe) }
        defer {
            host.close()
            probe.clear()
        }

        try host.assertCommittedDescriptor()
        XCTAssertEqual(host.events.rootCompletions, 1)
        XCTAssertFalse(host.componentHost.isBuilding)
        XCTAssertFalse(host.runtime.hasActiveRetainedBuild)
        XCTAssertTrue(probe.rowFactoryCalls.isEmpty)
        XCTAssertTrue(probe.objectFactoryCalls.isEmpty)
        XCTAssertTrue(probe.captures.isEmpty)
        let list = try host.list()
        let adapter = try XCTUnwrap(list.retainedLazyListAdapter)
        XCTAssertEqual(adapter.logicalRecordCount, probe.rows.count)
        XCTAssertEqual(adapter.mountedRecordCount, 0)
        XCTAssertTrue(list.children.isEmpty)

        XCTAssertNotNil(host.layout())

        let first = try probe.capture(row: 0, in: host)
        XCTAssertEqual(first.counter.wrappedValue, 100)
        XCTAssertEqual(first.model.value, 100)
        XCTAssertTrue(first.owner.isLive)
        XCTAssertTrue(host.coordinator.registry.owner(at: first.owner.identity) === first.owner)
        XCTAssertEqual(probe.objectFactoryCalls[0], 1)
        XCTAssertNil(probe.rowFactoryCalls[20], "Metadata must not evaluate a never-visited row")
        XCTAssertNil(probe.objectFactoryCalls[20])
        XCTAssertEqual(probe.missingOwnerCount, 0)
        XCTAssertEqual(probe.appearances[0, default: 0], 0, "A layout query is not presentation")

        let generation = first.owner.generation
        XCTAssertNotNil(host.layout())
        let again = try probe.capture(row: 0, in: host)
        XCTAssertTrue(again.owner === first.owner)
        XCTAssertEqual(again.owner.generation, generation)
        XCTAssertTrue(again.model === first.model)
        XCTAssertEqual(probe.objectFactoryCalls[0], 1)
    }

    func testEvictionKeepsOwnedStateAndObjectWhileReturnGetsANewPhysicalRow() async throws {
        let probe = MountedLazyListStateProbe()
        let host = MountedLazyListTestHost { mountedLazyListStateContent(probe) }
        defer {
            host.close()
            probe.clear()
        }
        host.render()
        let first = try probe.capture(row: 0, in: host)
        let original = try host.rowRoot("lazy.state.0")
        let attachment = original.captureLazyListAttachmentProof()
        XCTAssertTrue(attachment.isCurrent)
        XCTAssertEqual(probe.appearances[0], 1)

        try host.scroll(to: 1)
        host.render()
        XCTAssertTrue(try host.rowRoot("lazy.state.0") === original)
        XCTAssertTrue(attachment.isCurrent)
        XCTAssertEqual(probe.appearances[0], 1)
        XCTAssertEqual(probe.disappearances[0, default: 0], 0)

        try host.scroll(to: 200)
        XCTAssertFalse(host.contains(original))
        XCTAssertFalse(attachment.isCurrent)
        XCTAssertEqual(probe.disappearances[0], 1)
        XCTAssertTrue(first.owner.isLive)
        XCTAssertTrue(host.coordinator.registry.owner(at: first.owner.identity) === first.owner)
        let rowFactoryCount = probe.rowFactoryCalls[0]
        let objectNotifications = host.events.observedInvalidations

        first.counter.wrappedValue = 41
        first.objectValue.wrappedValue = 17
        XCTAssertNotNil(host.layout())

        XCTAssertEqual(first.counter.wrappedValue, 41)
        XCTAssertEqual(first.model.value, 17)
        XCTAssertEqual(probe.rowFactoryCalls[0], rowFactoryCount)
        XCTAssertEqual(probe.objectFactoryCalls[0], 1)
        XCTAssertNil(host.find("lazy.state.0"))
        XCTAssertEqual(host.events.observedInvalidations, objectNotifications)
        XCTAssertTrue(first.owner.isLive)

        try host.scroll(to: 0)
        let returned = try host.rowRoot("lazy.state.0")
        let current = try probe.capture(row: 0, in: host)
        XCTAssertFalse(returned === original)
        XCTAssertTrue(returned.captureLazyListAttachmentProof().isCurrent)
        XCTAssertFalse(attachment.isCurrent, "A return must not revive the old physical proof")
        XCTAssertTrue(current.owner === first.owner)
        XCTAssertEqual(current.owner.generation, first.owner.generation)
        XCTAssertEqual(current.counter.wrappedValue, 41)
        XCTAssertTrue(current.model === first.model)
        XCTAssertEqual(current.model.value, 17)
        XCTAssertEqual(probe.objectFactoryCalls[0], 1)
        XCTAssertEqual(probe.appearances[0], 1)
        host.render()
        XCTAssertEqual(probe.appearances[0], 2)
        XCTAssertEqual(probe.disappearances[0], 1)
    }

    func testColdDeletionAndReinsertionRejectOldRawMemberAndCollectionBindings() async throws {
        let probe = MountedLazyListRecordProbe()
        let host = MountedLazyListTestHost { mountedLazyListRecordContent(probe) }
        defer {
            host.close()
            probe.clear()
        }
        XCTAssertNotNil(host.layout())
        let raw = try XCTUnwrap(probe.raw[0])
        let member = try XCTUnwrap(probe.members[0])
        let element = try XCTUnwrap(probe.elements[0])
        let oldOwner = try XCTUnwrap(probe.owners[0])
        weak var oldPayload = raw.wrappedValue.payload
        try host.scroll(to: 200)

        probe.rows.removeAll { $0.id == 0 }
        host.reload()
        XCTAssertNotNil(host.layout())
        probe.clear(row: 0)
        XCTAssertFalse(oldOwner.isLive)
        XCTAssertNil(host.coordinator.registry.owner(at: oldOwner.identity))
        XCTAssertNotNil(oldPayload, "The three intentionally escaped bindings still own the retired snapshot")

        probe.rows.insert(MountedLazyListStateData(id: 0, seed: 900), at: 0)
        host.reload()
        try host.scroll(to: 0)
        let replacement = try XCTUnwrap(probe.raw[0])
        let replacementOwner = try XCTUnwrap(probe.owners[0])
        XCTAssertFalse(replacementOwner === oldOwner)
        XCTAssertNotEqual(replacementOwner.generation, oldOwner.generation)
        XCTAssertEqual(replacement.wrappedValue.number, 900)
        let invalidations = host.events.stateInvalidations

        let rejectedPayload = attemptMountedLazyListRetiredRecordReplacement(raw)
        member.wrappedValue = 8_000
        element.wrappedValue = 9_000

        XCTAssertNil(rejectedPayload.value, "A rejected old setter must not retain its proposed replacement")
        XCTAssertEqual(raw.wrappedValue.number, 100)
        XCTAssertEqual(member.wrappedValue, 100)
        XCTAssertEqual(element.wrappedValue, 100)
        XCTAssertEqual(replacement.wrappedValue.number, 900)
        XCTAssertEqual(replacement.wrappedValue.values, [900, 901])
        XCTAssertEqual(host.events.stateInvalidations, invalidations)
        XCTAssertNotNil(oldPayload, "Read handles intentionally remain strong until this test returns")
    }

    func testColdDeletionReleasesRegistryPayloadAfterTheLastEscapedBindingIsDropped() async throws {
        let probe = MountedLazyListRecordProbe()
        let host = MountedLazyListTestHost { mountedLazyListRecordContent(probe) }
        defer {
            host.close()
            probe.clear()
        }

        let lifetime = try makeMountedLazyListDeletedRecordLifetime(host: host, probe: probe)

        XCTAssertFalse(lifetime.owner.isLive)
        XCTAssertNotNil(lifetime.payload, "Only the explicit escaped binding should retain the old value")
        lifetime.binding = nil
        withExtendedLifetime((host, lifetime.owner)) {
            XCTAssertNil(lifetime.payload, "The cold registry, finished build and retired owner must release ownership")
        }
    }

    func testOneSharedRowValueHasIndependentStateAndObjectsInTwoHosts() async throws {
        let probe = MountedLazyListStateProbe()
        let data = MountedLazyListStateData(id: 0, seed: 100)
        let shared = MountedLazyListStateRow(data: data, probe: probe)
        let first = MountedLazyListTestHost {
            ManagedLazyListContent(
                [data], id: \.key, estimatedExtent: 20, prefetchExtent: 0,
                maximumMountedRecords: 8, maximumMountedLeaves: 16, maximumProtectedRecords: 2
            ) { _ in shared }
        }
        let second = MountedLazyListTestHost {
            ManagedLazyListContent(
                [data], id: \.key, estimatedExtent: 20, prefetchExtent: 0,
                maximumMountedRecords: 8, maximumMountedLeaves: 16, maximumProtectedRecords: 2
            ) { _ in shared }
        }
        defer {
            first.close()
            second.close()
            probe.clear()
        }
        XCTAssertNotNil(first.layout())
        XCTAssertNotNil(second.layout())
        let firstCapture = try probe.capture(row: 0, in: first)
        let secondCapture = try probe.capture(row: 0, in: second)
        XCTAssertFalse(firstCapture.owner === secondCapture.owner)
        XCTAssertFalse(firstCapture.model === secondCapture.model)
        XCTAssertEqual(probe.objectFactoryCalls[0], 2)

        firstCapture.counter.wrappedValue = 41
        firstCapture.objectValue.wrappedValue = 17
        XCTAssertNotNil(first.layout())
        XCTAssertTrue(try probe.capture(row: 0, in: first).owner === firstCapture.owner)
        XCTAssertTrue(try probe.capture(row: 0, in: first).model === firstCapture.model)
        XCTAssertEqual(probe.objectFactoryCalls[0], 2)
        XCTAssertEqual(firstCapture.counter.wrappedValue, 41)
        XCTAssertEqual(firstCapture.model.value, 17)
        XCTAssertEqual(secondCapture.counter.wrappedValue, 100)
        XCTAssertEqual(secondCapture.model.value, 100)
        let secondRoot = try second.rowRoot("lazy.state.0")
        let secondAttachment = secondRoot.captureLazyListAttachmentProof()

        first.close()
        firstCapture.counter.wrappedValue = 500
        firstCapture.objectValue.wrappedValue = 600

        XCTAssertEqual(firstCapture.counter.wrappedValue, 41)
        XCTAssertEqual(firstCapture.model.value, 17)
        XCTAssertTrue(secondCapture.owner.isLive)
        XCTAssertTrue(secondAttachment.isCurrent)
        XCTAssertEqual(secondCapture.counter.wrappedValue, 100)
        secondCapture.counter.wrappedValue = 42
        secondCapture.objectValue.wrappedValue = 18
        XCTAssertNotNil(second.layout())
        XCTAssertTrue(try probe.capture(row: 0, in: second).owner === secondCapture.owner)
        XCTAssertTrue(try probe.capture(row: 0, in: second).model === secondCapture.model)
        XCTAssertEqual(secondCapture.counter.wrappedValue, 42)
        XCTAssertEqual(secondCapture.model.value, 18)
    }

    func testOneSharedRowValueHasIndependentOccurrencesInTwoListScopes() async throws {
        let probe = MountedLazyListStateProbe()
        let data = MountedLazyListStateData(id: 0, seed: 100)
        let shared = MountedLazyListStateRow(data: data, probe: probe)
        let host = MountedLazyListTestHost(size: Size(width: 240, height: 40)) {
            HStack(spacing: 0) {
                ManagedLazyListContent(
                    [data], id: \.key, estimatedExtent: 20, prefetchExtent: 0,
                    maximumMountedRecords: 8, maximumMountedLeaves: 16, maximumProtectedRecords: 2
                ) { _ in shared }
                ManagedLazyListContent(
                    [data], id: \.key, estimatedExtent: 20, prefetchExtent: 0,
                    maximumMountedRecords: 8, maximumMountedLeaves: 16, maximumProtectedRecords: 2
                ) { _ in shared }
            }
            .frame(width: 240, height: 40)
        }
        defer {
            host.close()
            probe.clear()
        }
        XCTAssertNotNil(host.layout())
        let captures = probe.liveCaptures(row: 0, in: host).sorted { $0.owner.generation < $1.owner.generation }
        XCTAssertEqual(captures.count, 2)
        let first = try XCTUnwrap(captures.first)
        let second = try XCTUnwrap(captures.last)
        XCTAssertFalse(first.owner === second.owner)
        XCTAssertNotEqual(first.owner.identity, second.owner.identity)
        XCTAssertFalse(first.model === second.model)
        XCTAssertEqual(probe.objectFactoryCalls[0], 2)
        XCTAssertEqual(host.lists.count, 2)

        first.counter.wrappedValue = 41
        first.objectValue.wrappedValue = 17
        XCTAssertNotNil(host.layout())
        let current = probe.liveCaptures(row: 0, in: host)

        XCTAssertEqual(current.count, 2)
        XCTAssertTrue(current.contains { $0.owner === first.owner })
        XCTAssertTrue(current.contains { $0.owner === second.owner })
        XCTAssertEqual(first.counter.wrappedValue, 41)
        XCTAssertEqual(first.model.value, 17)
        XCTAssertEqual(second.counter.wrappedValue, 100)
        XCTAssertEqual(second.model.value, 100)
        XCTAssertTrue(second.owner.isLive)
    }

    func testKeyedReorderingAndInsertionKeepOwnersDespiteEqualKeyDescriptions() async throws {
        let probe = MountedLazyListStateProbe()
        let host = MountedLazyListTestHost(size: Size(width: 120, height: 80)) {
            mountedLazyListStateContent(probe)
        }
        defer {
            host.close()
            probe.clear()
        }
        XCTAssertNotNil(host.layout())
        let zero = try probe.capture(row: 0, in: host)
        let one = try probe.capture(row: 1, in: host)
        zero.counter.wrappedValue = 41
        one.counter.wrappedValue = 42
        XCTAssertNotNil(host.layout())
        XCTAssertEqual(probe.rows[0].key.description, probe.rows[1].key.description)
        XCTAssertNotEqual(probe.rows[0].key, probe.rows[1].key)
        let zeroRoot = try host.rowRoot("lazy.state.0")
        let oneRoot = try host.rowRoot("lazy.state.1")

        probe.rows.swapAt(0, 1)
        probe.rows.insert(MountedLazyListStateData(id: 99, seed: 999), at: 0)
        host.reload()
        XCTAssertNotNil(host.layout())

        XCTAssertTrue(try host.rowRoot("lazy.state.0") === zeroRoot)
        XCTAssertTrue(try host.rowRoot("lazy.state.1") === oneRoot)
        XCTAssertTrue(try probe.capture(row: 0, in: host).owner === zero.owner)
        XCTAssertTrue(try probe.capture(row: 1, in: host).owner === one.owner)
        XCTAssertEqual(zero.counter.wrappedValue, 41)
        XCTAssertEqual(one.counter.wrappedValue, 42)
        XCTAssertEqual(probe.objectFactoryCalls[0], 1)
        XCTAssertEqual(probe.objectFactoryCalls[1], 1)
        XCTAssertEqual(try probe.capture(row: 99, in: host).counter.wrappedValue, 999)
    }

    func testDuplicateKeyOccurrencesHaveSeparateOwnedCellsWithoutANativeParityClaim() async throws {
        let probe = MountedLazyListStateProbe()
        probe.rows = [
            MountedLazyListStateData(id: 0, seed: 100),
            MountedLazyListStateData(id: 0, seed: 200),
        ]
        let host = MountedLazyListTestHost { mountedLazyListStateContent(probe) }
        defer {
            host.close()
            probe.clear()
        }
        XCTAssertNotNil(host.layout())
        let captures = probe.liveCaptures(row: 0, in: host).sorted { $0.owner.generation < $1.owner.generation }
        XCTAssertEqual(captures.count, 2)
        let first = try XCTUnwrap(captures.first)
        let second = try XCTUnwrap(captures.last)
        XCTAssertFalse(first.owner === second.owner)
        XCTAssertNotEqual(first.owner.identity, second.owner.identity)
        XCTAssertEqual([first.counter.wrappedValue, second.counter.wrappedValue], [100, 200])
        XCTAssertFalse(first.model === second.model)

        first.counter.wrappedValue = 41
        XCTAssertNotNil(host.layout())
        let current = probe.liveCaptures(row: 0, in: host)

        XCTAssertEqual(current.count, 2)
        XCTAssertTrue(current.contains { $0.owner === first.owner })
        XCTAssertTrue(current.contains { $0.owner === second.owner })
        XCTAssertEqual(first.counter.wrappedValue, 41)
        XCTAssertEqual(second.counter.wrappedValue, 200)
        XCTAssertEqual(probe.objectFactoryCalls[0], 2)
    }
}

/// Shared only by these new fixtures. Observation callbacks use real center
/// tokens; their synchronous reload is not the window host's async scheduler.
@MainActor
final class MountedLazyListTestHost {
    let runtime: RetainedViewRuntime
    let componentHost: ComponentHost
    let coordinator: StateMountCoordinator
    let observations: MountedLazyListObservationRecorder
    let events: MountedLazyListHostEvents
    private(set) var isClosed = false

    init<Content: View>(
        size: Size = Size(width: 120, height: 40),
        observations suppliedObservations: MountedLazyListObservationRecorder? = nil,
        content: @escaping @MainActor () -> Content
    ) {
        let runtime = RetainedViewRuntime(
            root: ViewNode(frame: Rect(x: 0, y: 0, width: size.width, height: size.height)))
        runtime.clock = { 0 }
        let componentHost = ComponentHost(runtime: runtime)
        let observations = suppliedObservations ?? MountedLazyListObservationRecorder()
        let events = MountedLazyListHostEvents()
        let coordinator = StateMountCoordinator(
            invalidate: { [weak componentHost, weak events] in
                events?.recordStateInvalidation()
                componentHost?.reload()
            },
            observeObject: { [weak observations] object in observations?.observe(object) },
            updateObservedObjects: { [weak componentHost, weak observations] committed, retained, replacesRoot in
                componentHost?.observedObjects = committed
                observations?.update(committed: committed, retained: retained, replacesRoot: replacesRoot)
            })
        self.runtime = runtime
        self.componentHost = componentHost
        self.coordinator = coordinator
        self.observations = observations
        self.events = events
        componentHost.buildLifecycle = coordinator
        componentHost.shouldUpdate = { [weak self] in self?.isClosed == false }
        componentHost.onReloadCompleted = { [weak events] in events?.recordRootCompletion() }
        observations.onNotification = { [weak self] _ in
            guard let self, !self.isClosed else { return }
            self.events.recordObservedInvalidation()
            self.componentHost.reload()
        }
        let context = ViewBuildContext(
            stateMountCoordinator: coordinator,
            canvasSizeProvider: { [weak runtime] in runtime?.root.frame.size ?? size },
            invalidateHandler: { [weak componentHost] in componentHost?.reload() })
        componentHost.setComponents { [weak self] in
            guard self?.isClosed == false else { return [] }
            return [makeViewComponent(content(), context: context)]
        }
    }

    var nodes: [ViewNode] { Self.descendants(in: runtime.root) }
    var lists: [ViewNode] { nodes.filter { $0.retainedLazyListAdapter != nil } }

    func reload() {
        guard !isClosed else { return }
        componentHost.reload()
    }

    @discardableResult
    func layout() -> Rect? {
        guard !isClosed else { return nil }
        return runtime.resolvedLayoutFrame(of: runtime.root)
    }

    func render() {
        guard !isClosed else { return }
        _ = runtime.renderScene()
    }

    func find(_ identifier: String) -> ViewNode? {
        nodes.first { $0.accessibilityIdentifier == identifier }
    }

    func contains(_ node: ViewNode) -> Bool { nodes.contains { $0 === node } }

    func list(index: Int = 0, file: StaticString = #filePath, line: UInt = #line) throws -> ViewNode {
        let available = lists
        return try XCTUnwrap(
            available.indices.contains(index) ? available[index] : nil,
            "Expected managed lazy list \(index)", file: file, line: line)
    }

    func scrollContainer(
        index: Int = 0, file: StaticString = #filePath, line: UInt = #line
    ) throws -> ViewNode {
        var ancestor = try list(index: index, file: file, line: line).parent
        while let node = ancestor {
            if node.scrollAxis != nil { return node }
            ancestor = node.parent
        }
        return try XCTUnwrap(nil as ViewNode?, "Expected the actual managed scroll ancestor", file: file, line: line)
    }

    func rowRoot(
        _ identifier: String, listIndex: Int = 0,
        file: StaticString = #filePath, line: UInt = #line
    ) throws -> ViewNode {
        let roots = try list(index: listIndex, file: file, line: line).children
        let matches = roots.filter { root in
            Self.descendants(in: root).contains { $0.accessibilityIdentifier == identifier }
        }
        XCTAssertEqual(matches.count, 1, "Expected one physical row for \(identifier)", file: file, line: line)
        return try XCTUnwrap(matches.first, file: file, line: line)
    }

    func scroll(
        to offset: Double, listIndex: Int = 0,
        file: StaticString = #filePath, line: UInt = #line
    ) throws {
        let scroll = try scrollContainer(index: listIndex, file: file, line: line)
        scroll.scrollOffset = offset
        XCTAssertNotNil(layout(), file: file, line: line)
    }

    func assertCommittedDescriptor(
        index: Int = 0, file: StaticString = #filePath, line: UInt = #line
    ) throws {
        let adapter = try XCTUnwrap(
            try list(index: index, file: file, line: line).retainedLazyListAdapter, file: file, line: line)
        let binding = try XCTUnwrap(adapter.managedLogicalDescriptorBinding, file: file, line: line)
        XCTAssertTrue(binding.isCurrent, file: file, line: line)
        XCTAssertTrue(binding.scope.isLogicallyLive, file: file, line: line)
        // The exposed snapshot can prune expired weak roster entries, but it
        // cannot publish a descriptor or materialize a row for this assertion.
        let acceptedDescriptor = binding.scope.snapshot().acceptedDescriptor
        XCTAssertTrue(acceptedDescriptor === binding.descriptor, file: file, line: line)
        XCTAssertFalse(runtime.hasActiveRetainedBuild, file: file, line: line)
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
        observations.close()
    }

    static func descendants(in root: ViewNode) -> [ViewNode] {
        var result: [ViewNode] = []
        var pending = [root]
        var seen: Set<ObjectIdentifier> = []
        while let node = pending.popLast() {
            guard seen.insert(ObjectIdentifier(node)).inserted else { continue }
            result.append(node)
            pending.append(contentsOf: node.children.reversed())
        }
        return result
    }
}

@MainActor
final class MountedLazyListHostEvents {
    private(set) var stateInvalidations = 0
    private(set) var observedInvalidations = 0
    private(set) var rootCompletions = 0

    func recordStateInvalidation() { stateInvalidations += 1 }
    func recordObservedInvalidation() { observedInvalidations += 1 }
    func recordRootCompletion() { rootCompletions += 1 }
}

@MainActor
final class MountedLazyListModel: ObservableObject {
    @Published var value: Int
    let serial: Int

    init(value: Int, serial: Int) {
        self.value = value
        self.serial = serial
    }
}

private struct MountedLazyListStateKey: Hashable, CustomStringConvertible {
    let value: Int
    var description: String { "same-description" }
}

private struct MountedLazyListStateData {
    let id: Int
    let seed: Int
    var key: MountedLazyListStateKey { MountedLazyListStateKey(value: id) }
}

@MainActor
private struct MountedLazyListStateCapture {
    let row: Int
    let owner: StateMountOwner
    let counter: Binding<Int>
    let objectValue: Binding<Int>
    let model: MountedLazyListModel
}

@MainActor
private final class MountedLazyListStateProbe {
    var rows = (0..<32).map { MountedLazyListStateData(id: $0, seed: 100 + $0) }
    private(set) var rowFactoryCalls: [Int: Int] = [:]
    private(set) var objectFactoryCalls: [Int: Int] = [:]
    private(set) var captures: [ObjectIdentifier: MountedLazyListStateCapture] = [:]
    private(set) var appearances: [Int: Int] = [:]
    private(set) var disappearances: [Int: Int] = [:]
    private(set) var missingOwnerCount = 0
    private var nextObjectSerial = 0

    func makeRow(_ data: MountedLazyListStateData) -> MountedLazyListStateRow {
        rowFactoryCalls[data.id, default: 0] += 1
        return MountedLazyListStateRow(data: data, probe: self)
    }

    func makeModel(row: Int, seed: Int) -> MountedLazyListModel {
        objectFactoryCalls[row, default: 0] += 1
        nextObjectSerial += 1
        return MountedLazyListModel(value: seed, serial: nextObjectSerial)
    }

    func record(
        row: Int, owner: StateMountOwner?, counter: Binding<Int>,
        objectValue: Binding<Int>, model: MountedLazyListModel
    ) {
        guard let owner else {
            missingOwnerCount += 1
            return
        }
        captures[ObjectIdentifier(owner)] = MountedLazyListStateCapture(
            row: row, owner: owner, counter: counter, objectValue: objectValue, model: model)
    }

    func liveCaptures(row: Int, in host: MountedLazyListTestHost) -> [MountedLazyListStateCapture] {
        captures.values.filter {
            $0.row == row && host.coordinator.registry.owner(at: $0.owner.identity) === $0.owner
        }
    }

    func capture(
        row: Int, in host: MountedLazyListTestHost,
        file: StaticString = #filePath, line: UInt = #line
    ) throws -> MountedLazyListStateCapture {
        let matches = liveCaptures(row: row, in: host)
        XCTAssertEqual(matches.count, 1, "Expected one installed owner for row \(row)", file: file, line: line)
        return try XCTUnwrap(matches.first, file: file, line: line)
    }

    func didAppear(_ row: Int) { appearances[row, default: 0] += 1 }
    func didDisappear(_ row: Int) { disappearances[row, default: 0] += 1 }
    func clear() { captures.removeAll() }
}

@MainActor
private struct MountedLazyListStateRow: View {
    @State private var counter: Int
    @StateObject private var model: MountedLazyListModel
    let row: Int
    let probe: MountedLazyListStateProbe

    init(data: MountedLazyListStateData, probe: MountedLazyListStateProbe) {
        row = data.id
        self.probe = probe
        _counter = State(initialValue: data.seed)
        _model = StateObject(wrappedValue: probe.makeModel(row: data.id, seed: data.seed))
    }

    var body: some View {
        let row = self.row
        let probe = self.probe
        probe.record(
            row: row, owner: ViewBuildContextScope.current?.viewIdentity.installedOwner,
            counter: $counter, objectValue: $model.value, model: model)
        return Color.blue.frame(width: 120, height: 20)
            .accessibilityIdentifier("lazy.state.\(row)")
            .onAppear { [weak probe] in probe?.didAppear(row) }
            .onDisappear { [weak probe] in probe?.didDisappear(row) }
    }
}

@MainActor
private func mountedLazyListStateContent(_ probe: MountedLazyListStateProbe) -> some View {
    ManagedLazyListContent(
        probe.rows, id: \.key, estimatedExtent: 20, prefetchExtent: 0,
        maximumMountedRecords: 8, maximumMountedLeaves: 16, maximumProtectedRecords: 2
    ) { data in probe.makeRow(data) }
}

private final class MountedLazyListPayload {
    let number: Int
    init(_ number: Int) { self.number = number }
}

private struct MountedLazyListRecord {
    var number: Int
    var values: [Int]
    var payload: MountedLazyListPayload
}

@MainActor
private final class MountedLazyListWeakPayload {
    weak var value: MountedLazyListPayload?
    init(_ value: MountedLazyListPayload) { self.value = value }
}

@MainActor
private final class MountedLazyListRecordProbe {
    var rows = (0..<32).map { MountedLazyListStateData(id: $0, seed: 100 + $0) }
    var raw: [Int: Binding<MountedLazyListRecord>] = [:]
    var members: [Int: Binding<Int>] = [:]
    var elements: [Int: Binding<Int>] = [:]
    var owners: [Int: StateMountOwner] = [:]

    func clear(row: Int) {
        raw.removeValue(forKey: row)
        members.removeValue(forKey: row)
        elements.removeValue(forKey: row)
        owners.removeValue(forKey: row)
    }

    func clear() {
        raw.removeAll()
        members.removeAll()
        elements.removeAll()
        owners.removeAll()
    }
}

@MainActor
private struct MountedLazyListRecordRow: View {
    @State private var record: MountedLazyListRecord
    let row: Int
    let probe: MountedLazyListRecordProbe

    init(data: MountedLazyListStateData, probe: MountedLazyListRecordProbe) {
        row = data.id
        self.probe = probe
        _record = State(
            initialValue: MountedLazyListRecord(
                number: data.seed, values: [data.seed, data.seed + 1], payload: MountedLazyListPayload(data.seed)))
    }

    var body: some View {
        probe.raw[row] = $record
        probe.members[row] = $record.number
        probe.elements[row] = $record.values[0]
        probe.owners[row] = ViewBuildContextScope.current?.viewIdentity.installedOwner
        return Color.green.frame(width: 120, height: 20)
            .accessibilityIdentifier("lazy.record.\(row)")
    }
}

@MainActor
private func mountedLazyListRecordContent(_ probe: MountedLazyListRecordProbe) -> some View {
    ManagedLazyListContent(
        probe.rows, id: \.key, estimatedExtent: 20, prefetchExtent: 0,
        maximumMountedRecords: 8, maximumMountedLeaves: 16, maximumProtectedRecords: 2
    ) { data in MountedLazyListRecordRow(data: data, probe: probe) }
}

@MainActor
private func attemptMountedLazyListRetiredRecordReplacement(
    _ binding: Binding<MountedLazyListRecord>
) -> MountedLazyListWeakPayload {
    let payload = MountedLazyListPayload(7_000)
    let weakPayload = MountedLazyListWeakPayload(payload)
    binding.wrappedValue = MountedLazyListRecord(number: 7_000, values: [7_000], payload: payload)
    return weakPayload
}

@MainActor
private final class MountedLazyListDeletedRecordLifetime {
    var binding: Binding<MountedLazyListRecord>?
    weak var payload: MountedLazyListPayload?
    let owner: StateMountOwner

    init(binding: Binding<MountedLazyListRecord>, owner: StateMountOwner) {
        self.binding = binding
        payload = binding.wrappedValue.payload
        self.owner = owner
    }
}

@MainActor
private func makeMountedLazyListDeletedRecordLifetime(
    host: MountedLazyListTestHost, probe: MountedLazyListRecordProbe
) throws -> MountedLazyListDeletedRecordLifetime {
    XCTAssertNotNil(host.layout())
    let binding = try XCTUnwrap(probe.raw[0])
    let owner = try XCTUnwrap(probe.owners[0])
    let result = MountedLazyListDeletedRecordLifetime(binding: binding, owner: owner)
    try host.scroll(to: 200)
    probe.rows.removeAll { $0.id == 0 }
    host.reload()
    XCTAssertNotNil(host.layout())
    probe.clear(row: 0)
    return result
}
