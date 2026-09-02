import SwiftWindowsCore
import XCTest

@testable import SwiftWindowsUI
@testable import WinSwiftUI

@MainActor
final class DeferredListProjectionCancellationTests: XCTestCase {
    func testManagedFactoryCancellationPreservesTheOriginalAcceptedSource() async throws {
        for builder in [false, true] {
            let probe = DeferredCancellationProbe(phase: .factory)
            let data = DeferredCancellationCollection(probe: probe)
            let host = MountedLazyListTestHost { deferredCancellationList(data, probe: probe, builder: builder) }
            defer { host.close() }
            let list = try host.list()
            let adapter = try XCTUnwrap(list.retainedLazyListAdapter)
            let binding = try XCTUnwrap(adapter.managedLogicalDescriptorBinding)
            let generation = binding.sourceGeneration
            let originalDescriptor = binding.scope.snapshot().acceptedDescriptor
            let rootCompletions = host.events.rootCompletions
            XCTAssertTrue(binding.isCurrent)
            XCTAssertTrue(generation.isCurrent)
            XCTAssertTrue(originalDescriptor === binding.descriptor)
            XCTAssertTrue(probe.factories.isEmpty)

            // The factory captures and rejects its actual entered-row receipt.
            // It still returns a View, which must never reach its custom body.
            _ = host.layout()

            XCTAssertFalse(probe.factories.isEmpty)
            XCTAssertTrue(probe.factories.allSatisfy { $0 == 7 })
            XCTAssertEqual(probe.factories.count, probe.cancelledAdmissions.count)
            XCTAssertEqual(probe.missingAdmissions, 0)
            XCTAssertTrue(probe.currentAtCancellation.allSatisfy { $0 })
            XCTAssertTrue(probe.cancelledAdmissions.allSatisfy { !$0.isCurrent })
            XCTAssertTrue(probe.bodies.isEmpty)
            XCTAssertTrue(probe.nodeFactories.isEmpty)
            XCTAssertEqual(adapter.mountedRecordCount, 0)
            XCTAssertTrue(list.children.isEmpty)
            XCTAssertFalse(host.isClosed)
            XCTAssertFalse(host.runtime.hasActiveRetainedBuild)
            XCTAssertEqual(host.events.rootCompletions, rootCompletions)
            XCTAssertEqual(host.events.stateInvalidations, 0)
            XCTAssertEqual(host.events.observedInvalidations, 0)

            // Check the objects captured before layout without asking the host
            // to reload, acquire another receipt, or repeat the layout request.
            XCTAssertTrue(list.retainedLazyListAdapter === adapter)
            XCTAssertTrue(adapter.managedLogicalDescriptorBinding === binding)
            XCTAssertTrue(adapter.ownsAttachment(list))
            XCTAssertTrue(binding.scope.snapshot().acceptedDescriptor === originalDescriptor)
            XCTAssertTrue(binding.isCurrent)
            XCTAssertTrue(generation.isCurrent)
            XCTAssertEqual(binding.sourceGeneration, generation)
            XCTAssertEqual(adapter.logicalRecordCount, 1)
            XCTAssertEqual(data.values, [7])
        }
    }

    func testManagedSourceCheckCancellationPreservesTheOriginalAcceptedSource() async throws {
        for builder in [false, true] {
            let probe = DeferredCancellationProbe(phase: .sourceCount)
            let data = DeferredCancellationCollection(probe: probe)
            let host = MountedLazyListTestHost { deferredCancellationList(data, probe: probe, builder: builder) }
            defer { host.close() }
            let list = try host.list()
            let adapter = try XCTUnwrap(list.retainedLazyListAdapter)
            let binding = try XCTUnwrap(adapter.managedLogicalDescriptorBinding)
            let generation = binding.sourceGeneration
            let originalDescriptor = binding.scope.snapshot().acceptedDescriptor
            let rootCompletions = host.events.rootCompletions
            XCTAssertTrue(binding.isCurrent)
            XCTAssertTrue(generation.isCurrent)
            XCTAssertTrue(originalDescriptor === binding.descriptor)
            XCTAssertTrue(probe.cancelledAdmissions.isEmpty)
            XCTAssertTrue(probe.factories.isEmpty)

            // Metadata collection has no entered lazy-row context. The first
            // row source check does: its real collection count getter cancels
            // that receipt while returning the unchanged count and model data.
            _ = host.layout()

            XCTAssertFalse(probe.cancelledAdmissions.isEmpty)
            XCTAssertEqual(probe.missingAdmissions, 0)
            XCTAssertTrue(probe.currentAtCancellation.allSatisfy { $0 })
            XCTAssertTrue(probe.cancelledAdmissions.allSatisfy { !$0.isCurrent })
            XCTAssertTrue(probe.factories.isEmpty)
            XCTAssertTrue(probe.bodies.isEmpty)
            XCTAssertTrue(probe.nodeFactories.isEmpty)
            XCTAssertEqual(adapter.mountedRecordCount, 0)
            XCTAssertTrue(list.children.isEmpty)
            XCTAssertFalse(host.isClosed)
            XCTAssertFalse(host.runtime.hasActiveRetainedBuild)
            XCTAssertEqual(host.events.rootCompletions, rootCompletions)
            XCTAssertEqual(host.events.stateInvalidations, 0)
            XCTAssertEqual(host.events.observedInvalidations, 0)
            XCTAssertTrue(list.retainedLazyListAdapter === adapter)
            XCTAssertTrue(adapter.managedLogicalDescriptorBinding === binding)
            XCTAssertTrue(adapter.ownsAttachment(list))
            XCTAssertTrue(binding.scope.snapshot().acceptedDescriptor === originalDescriptor)
            XCTAssertTrue(binding.isCurrent)
            XCTAssertTrue(generation.isCurrent)
            XCTAssertEqual(binding.sourceGeneration, generation)
            XCTAssertEqual(adapter.logicalRecordCount, 1)
            XCTAssertEqual(data.values, [7])
        }
    }
}

private enum DeferredCancellationPhase {
    case factory, sourceCount
}

@MainActor
private final class DeferredCancellationProbe {
    let phase: DeferredCancellationPhase
    var factories: [Int] = []
    var bodies: [Int] = []
    var nodeFactories: [Int] = []
    var cancelledAdmissions: [LazyListResolutionReceipt] = []
    var currentAtCancellation: [Bool] = []
    var missingAdmissions = 0

    init(phase: DeferredCancellationPhase) { self.phase = phase }

    func content(for value: Int) -> [AnyView] {
        factories.append(value)
        if phase == .factory {
            if let admission = ViewBuildContextScope.current?.viewIdentity.lazyList?.admission {
                cancel(admission)
            } else {
                missingAdmissions += 1
            }
        }
        return [AnyView(DeferredCancellationBody(value: value, probe: self))]
    }

    func readCount() {
        guard phase == .sourceCount,
            let admission = ViewBuildContextScope.current?.viewIdentity.lazyList?.admission
        else { return }
        cancel(admission)
    }

    private func cancel(_ admission: LazyListResolutionReceipt) {
        currentAtCancellation.append(admission.isCurrent)
        cancelledAdmissions.append(admission)
        admission.reject()
    }
}

/// The public collection keeps exactly the same count, indices, and values.
/// Only its count getter can cancel an already-entered finite row admission.
private final class DeferredCancellationCollection: RandomAccessCollection {
    typealias Index = Int
    let values = [7]
    let probe: DeferredCancellationProbe

    init(probe: DeferredCancellationProbe) { self.probe = probe }

    var startIndex: Int { values.startIndex }
    var endIndex: Int { values.endIndex }
    var count: Int {
        MainActor.assumeIsolated { [probe] in probe.readCount() }
        return values.count
    }
    subscript(index: Int) -> Int { values[index] }
    func index(after index: Int) -> Int { index + 1 }
    func index(before index: Int) -> Int { index - 1 }
    func index(_ index: Int, offsetBy distance: Int) -> Int { index + distance }
    func distance(from start: Int, to end: Int) -> Int { end - start }
}

@MainActor
private struct DeferredCancellationBody: View {
    let value: Int
    let probe: DeferredCancellationProbe

    var body: some View {
        probe.bodies.append(value)
        return DeferredCancellationComponent(value: value, probe: probe)
    }
}

@MainActor
private struct DeferredCancellationComponent: View {
    typealias Body = Never
    let value: Int
    let probe: DeferredCancellationProbe

    var body: Never { fatalError("Component fixture has no body") }

    func makeComponent(context: ViewBuildContext) -> Component {
        Component { [probe, value] _ in
            probe.nodeFactories.append(value)
            return Controls.panel(preferredSize: Size(width: 100, height: 24), isHitTestVisible: false)
        }
    }
}

@MainActor
@ViewBuilder
private func deferredCancellationList(
    _ data: DeferredCancellationCollection, probe: DeferredCancellationProbe, builder: Bool
) -> some View {
    if builder {
        List { ForEach(data, id: \.self) { probe.content(for: $0) } }
    } else {
        List(data, id: \.self) { probe.content(for: $0) }
    }
}
