import SwiftWindowsCore
import XCTest

@testable import SwiftWindowsUI
@testable import WinSwiftUI

@MainActor
final class DeferredListBindingCancellationTests: XCTestCase {
    func testManagedBindingGetterCancellationPreservesOriginalAcceptedSource() async throws {
        for builder in [false, true] {
            let probe = DeferredBindingCancellationProbe(cancelsEnteredRead: true)
            let source = probe.makeBinding()
            let host = MountedLazyListTestHost {
                deferredBindingCancellationList(source, probe: probe, builder: builder)
            }
            defer { host.close() }
            let list = try host.list()
            let adapter = try XCTUnwrap(list.retainedLazyListAdapter)
            let binding = try XCTUnwrap(adapter.managedLogicalDescriptorBinding)
            let generation = binding.sourceGeneration
            let originalDescriptor = binding.scope.snapshot().acceptedDescriptor
            let originalValues = probe.values
            let getterCalls = probe.getterCalls
            let rootCompletions = host.events.rootCompletions
            XCTAssertTrue(binding.isCurrent)
            XCTAssertTrue(generation.isCurrent)
            XCTAssertTrue(originalDescriptor === binding.descriptor)
            XCTAssertEqual(adapter.logicalRecordCount, 1)
            XCTAssertTrue(probe.enteredAdmissions.isEmpty)
            XCTAssertEqual(probe.factoryCalls, 0)

            // The stable array getter rejects only the actual entered-row
            // receipt. It returns the same values and does not write State.
            _ = host.layout()

            XCTAssertGreaterThan(probe.getterCalls, getterCalls)
            XCTAssertFalse(probe.enteredAdmissions.isEmpty)
            XCTAssertEqual(probe.cancellations, probe.enteredAdmissions.count)
            XCTAssertTrue(probe.currentAtRead.allSatisfy { $0 })
            XCTAssertTrue(probe.enteredAdmissions.allSatisfy { !$0.isCurrent })
            XCTAssertEqual(probe.factoryCalls, 0)
            XCTAssertEqual(probe.bodyCalls, 0)
            XCTAssertEqual(probe.nodeFactoryCalls, 0)
            XCTAssertEqual(probe.setterCalls, 0)
            XCTAssertEqual(probe.values, originalValues)
            XCTAssertEqual(adapter.mountedRecordCount, 0)
            XCTAssertTrue(list.children.isEmpty)
            XCTAssertFalse(host.isClosed)
            XCTAssertFalse(host.runtime.hasActiveRetainedBuild)
            XCTAssertEqual(host.events.rootCompletions, rootCompletions)
            XCTAssertEqual(host.events.stateInvalidations, 0)
            XCTAssertEqual(host.events.observedInvalidations, 0)

            // Inspect the original accepted objects without acquiring another
            // receipt, refreshing the source, or asking for another layout.
            XCTAssertTrue(list.retainedLazyListAdapter === adapter)
            XCTAssertTrue(adapter.managedLogicalDescriptorBinding === binding)
            XCTAssertTrue(adapter.ownsAttachment(list))
            XCTAssertTrue(binding.scope.snapshot().acceptedDescriptor === originalDescriptor)
            XCTAssertTrue(binding.isCurrent)
            XCTAssertTrue(generation.isCurrent)
            XCTAssertEqual(binding.sourceGeneration, generation)
            XCTAssertEqual(adapter.logicalRecordCount, 1)
        }
    }

    func testMissingCapturedBindingKeyPermanentlyRevokesOriginalAcceptedSource() async throws {
        for builder in [false, true] {
            let probe = DeferredBindingCancellationProbe(cancelsEnteredRead: false)
            let source = probe.makeBinding()
            let host = MountedLazyListTestHost {
                deferredBindingCancellationList(source, probe: probe, builder: builder)
            }
            defer { host.close() }
            let list = try host.list()
            let adapter = try XCTUnwrap(list.retainedLazyListAdapter)
            let binding = try XCTUnwrap(adapter.managedLogicalDescriptorBinding)
            let generation = binding.sourceGeneration
            let originalDescriptor = binding.scope.snapshot().acceptedDescriptor
            let originalValues = probe.values
            let getterCalls = probe.getterCalls
            let rootCompletions = host.events.rootCompletions
            XCTAssertTrue(binding.isCurrent)
            XCTAssertTrue(generation.isCurrent)
            XCTAssertTrue(originalDescriptor === binding.descriptor)
            XCTAssertEqual(adapter.logicalRecordCount, 1)
            XCTAssertTrue(probe.enteredAdmissions.isEmpty)
            XCTAssertEqual(probe.factoryCalls, 0)

            // Change only the nonobserved backing array, retaining its count.
            // The captured key 7 is genuinely absent from this current value.
            probe.values = [DeferredBindingCancellationRow(id: 8)]
            _ = host.layout()

            XCTAssertGreaterThan(probe.getterCalls, getterCalls)
            XCTAssertFalse(probe.enteredAdmissions.isEmpty)
            XCTAssertTrue(probe.currentAtRead.allSatisfy { $0 })
            XCTAssertEqual(probe.cancellations, 0)
            XCTAssertEqual(probe.factoryCalls, 0)
            XCTAssertEqual(probe.bodyCalls, 0)
            XCTAssertEqual(probe.nodeFactoryCalls, 0)
            XCTAssertEqual(probe.setterCalls, 0)
            XCTAssertEqual(probe.values.map(\.id), [8])
            XCTAssertEqual(adapter.mountedRecordCount, 0)
            XCTAssertTrue(list.children.isEmpty)
            XCTAssertFalse(host.isClosed)
            XCTAssertFalse(host.runtime.hasActiveRetainedBuild)
            XCTAssertFalse(binding.isCurrent)
            XCTAssertFalse(generation.isCurrent)
            XCTAssertEqual(adapter.logicalRecordCount, 0)

            // Restoration performs no getter, setter, reload, or layout. A
            // permanently rejected original source cannot become current again.
            let readsAfterRejection = probe.getterCalls
            probe.values = originalValues

            XCTAssertEqual(probe.values, originalValues)
            XCTAssertEqual(probe.getterCalls, readsAfterRejection)
            XCTAssertEqual(probe.setterCalls, 0)
            XCTAssertEqual(probe.factoryCalls, 0)
            XCTAssertEqual(probe.bodyCalls, 0)
            XCTAssertEqual(probe.nodeFactoryCalls, 0)
            XCTAssertEqual(host.events.rootCompletions, rootCompletions)
            XCTAssertEqual(host.events.stateInvalidations, 0)
            XCTAssertEqual(host.events.observedInvalidations, 0)
            XCTAssertTrue(list.retainedLazyListAdapter === adapter)
            XCTAssertTrue(adapter.managedLogicalDescriptorBinding === binding)
            XCTAssertTrue(adapter.ownsAttachment(list))
            XCTAssertTrue(binding.scope.snapshot().acceptedDescriptor === originalDescriptor)
            XCTAssertEqual(binding.sourceGeneration, generation)
            XCTAssertFalse(binding.isCurrent)
            XCTAssertFalse(generation.isCurrent)
            XCTAssertEqual(adapter.logicalRecordCount, 0)
        }
    }
}

private struct DeferredBindingCancellationRow: Equatable {
    let id: Int
}

/// This model deliberately has no State, observation, or invalidation hook.
@MainActor
private final class DeferredBindingCancellationProbe {
    let cancelsEnteredRead: Bool
    var values = [DeferredBindingCancellationRow(id: 7)]
    var getterCalls = 0
    var setterCalls = 0
    var factoryCalls = 0
    var bodyCalls = 0
    var nodeFactoryCalls = 0
    var enteredAdmissions: [LazyListResolutionReceipt] = []
    var currentAtRead: [Bool] = []
    var cancellations = 0

    init(cancelsEnteredRead: Bool) { self.cancelsEnteredRead = cancelsEnteredRead }

    func makeBinding() -> Binding<[DeferredBindingCancellationRow]> {
        Binding(
            get: { [self] in self.readValues() },
            set: { [self] values in
                self.setterCalls += 1
                self.values = values
            })
    }

    private func readValues() -> [DeferredBindingCancellationRow] {
        getterCalls += 1
        if let admission = ViewBuildContextScope.current?.viewIdentity.lazyList?.admission {
            currentAtRead.append(admission.isCurrent)
            enteredAdmissions.append(admission)
            if cancelsEnteredRead {
                cancellations += 1
                admission.reject()
            }
        }
        return values
    }

    func content(_ binding: Binding<DeferredBindingCancellationRow>) -> [AnyView] {
        // Do not read the element Binding: any factory entry is itself a
        // failure, regardless of what a later escaped-binding getter would do.
        factoryCalls += 1
        return [AnyView(DeferredBindingCancellationBody(probe: self))]
    }
}

@MainActor
private struct DeferredBindingCancellationBody: View {
    let probe: DeferredBindingCancellationProbe

    var body: some View {
        probe.bodyCalls += 1
        return DeferredBindingCancellationComponent(probe: probe)
    }
}

@MainActor
private struct DeferredBindingCancellationComponent: View {
    typealias Body = Never
    let probe: DeferredBindingCancellationProbe

    var body: Never { fatalError("Component fixture has no body") }

    func makeComponent(context: ViewBuildContext) -> Component {
        Component { [probe] _ in
            probe.nodeFactoryCalls += 1
            return Controls.panel(preferredSize: Size(width: 100, height: 24), isHitTestVisible: false)
        }
    }
}

@MainActor
@ViewBuilder
private func deferredBindingCancellationList(
    _ source: Binding<[DeferredBindingCancellationRow]>, probe: DeferredBindingCancellationProbe, builder: Bool
) -> some View {
    if builder {
        List { ForEach(source, id: \.id) { probe.content($0) } }
    } else {
        List(source, id: \.id) { probe.content($0) }
    }
}
