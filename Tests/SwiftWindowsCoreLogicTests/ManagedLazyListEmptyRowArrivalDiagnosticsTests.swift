import SwiftWindowsCore
import SwiftWindowsGraphics
@preconcurrency import XCTest

@testable import SwiftWindowsUI
@testable import WinSwiftUI

/// The original insertion regression stays unchanged. This companion records
/// only its existing callbacks and native state at the same operation boundaries.
@MainActor
final class ManagedLazyListEmptyRowArrivalDiagnosticsTests: XCTestCase {
    func testAcceptedEmptyRowReportsItsOriginalReceiptThroughPhysicalInsertion() async throws {
        let probe = ManagedEmptyArrivalProbe()
        let host = MountedLazyListTestHost(size: Size(width: 160, height: 40)) {
            managedEmptyArrivalList(probe)
        }
        host.runtime.clock = { probe.sampleClock() }
        defer {
            host.close()
            probe.capture = nil
        }

        probe.phase = "initial-layout"
        XCTAssertNotNil(host.layout())
        let list = try host.list()
        let adapter = try XCTUnwrap(list.retainedLazyListAdapter)
        XCTAssertEqual(adapter.mountedRecordCount, 1, "An accepted empty row still has a native row table")
        XCTAssertTrue(list.children.isEmpty)
        XCTAssertEqual(probe.bodyCalls, 0)
        // Only this already accepted, sole logical row is observed. Keep weak
        // activities and native IDs/proofs, not a new owner or declaration pin.
        probe.original = ManagedEmptyArrivalWitness(activity: adapter.materializedRowActivities.first)
        probe.report("before-reload", list: list, in: host.runtime)

        probe.showsRows = true
        probe.phase = "reload"
        withAnimation(.linear(duration: 0.8)) { host.reload() }
        probe.report("after-reload", list: list, in: host.runtime)
        XCTAssertEqual(probe.bodyCalls, 0)

        probe.phase = "replacement-layout"
        probe.report("before-replacement-layout", list: list, in: host.runtime)
        XCTAssertNotNil(host.layout())
        probe.report("after-replacement-layout", list: list, in: host.runtime)

        let row = try XCTUnwrap(host.find("managed.empty.arrival.0"))
        let insertion = try XCTUnwrap(row.animationStates[.opacity])
        let recipients = host.nodes.filter { $0.animationStates[.opacity] != nil }
        XCTAssertEqual(recipients.count, 1, "A single row insertion must not start duplicate ancestor fades")
        XCTAssertTrue(recipients.first === row)
        XCTAssertEqual(insertion.startTime, 10, accuracy: 0.0001)
        XCTAssertEqual(insertion.duration, 0.8, accuracy: 0.0001)
        XCTAssertEqual(insertion.startValue, 0, accuracy: 0.0001)
        XCTAssertEqual(insertion.endValue, 1, accuracy: 0.0001)
        XCTAssertEqual(row.opacity, 0, accuracy: 0.0001)
        try host.assertCommittedDescriptor()
    }
}

private struct ManagedEmptyArrivalData: Identifiable {
    let id = 0
    let seed = 100
    let opacity = 1.0
}

@MainActor
private final class ManagedEmptyArrivalWitness {
    weak var activity: RetainedLazyListMaterializedRowActivity?
    weak var logical: RetainedLazyListLogicalMembershipReceipt?
    weak var physical: RetainedLazyListPhysicalActivityReceipt?
    let membershipID: RetainedLazyListMembershipID?
    let physicalID: RetainedLazyListPhysicalActivityID?
    let actuals: [RetainedLazyListActualAttachment]

    init(activity: RetainedLazyListMaterializedRowActivity?) {
        self.activity = activity
        logical = activity?.logicalMembership
        physical = activity?.physical
        membershipID = activity?.logicalMembership.id
        physicalID = activity?.physical.id
        actuals = activity?.physical.actualAttachments ?? []
    }
}

@MainActor
private final class ManagedEmptyArrivalProbe {
    let rows = [ManagedEmptyArrivalData()]
    var showsRows = false
    var phase = "initial-descriptor"
    var original: ManagedEmptyArrivalWitness?
    var capture: (owner: StateMountOwner, value: Binding<Int>)?
    private(set) var factoryCalls = 0
    private(set) var constructorCalls = 0
    private(set) var bodyCalls = 0
    private(set) var clockReads = 0
    // Identity objects prevent address reuse without pinning a journal, source,
    // row activity, or an application-owned payload between attempts.
    private var attempts: [RetainedLazyListAttemptID] = []
    private var descriptorAttempts: [RetainedLazyListAttemptID] = []

    func recordFactory() {
        factoryCalls += 1
        reportCallback("factory")
    }

    func makeRow(_ data: ManagedEmptyArrivalData) -> ManagedEmptyArrivalRow {
        constructorCalls += 1
        return ManagedEmptyArrivalRow(data, probe: self)
    }

    func recordBody(value: Binding<Int>) {
        bodyCalls += 1
        reportCallback("body")
        guard let owner = ViewBuildContextScope.current?.viewIdentity.installedOwner else {
            XCTFail("The managed row must install its State owner")
            return
        }
        capture = (owner, value)
    }

    func sampleClock() -> Double {
        clockReads += 1
        return 10
    }

    func report(_ boundary: String, list: ViewNode, in runtime: RetainedViewRuntime) {
        let current = list.retainedLazyListAdapter
        let binding = current?.managedLogicalDescriptorBinding
        let fields = [
            "boundary=\(boundary)", "factories=\(factoryCalls)", "constructors=\(constructorCalls)",
            "bodies=\(bodyCalls)", "clockReads=\(clockReads)",
            "containerAttached=\(list.isRetainedLazyListAttached(in: runtime))",
            "adapterOwnsContainer=\(current?.ownsAttachment(list) == true)",
            "mountedRecords=\(current?.mountedRecordCount ?? -1)",
            "mountedLeaves=\(current?.mountedLeafCount ?? -1)", "children=\(list.children.count)",
            "unresolved=\(current?.hasUnresolvedWork == true)",
            "currentSnapshot=\(current?.hasCurrentLogicalSnapshot == true)",
            "contentExtent=\(current?.contentExtent ?? -1)", "bindingCurrent=\(binding?.isCurrent == true)",
            "descriptorAccepted=\(binding.map { $0.scope.containsDeclaredDescriptor($0.descriptor) } == true)",
            "oldActivityExists=\(original?.activity != nil)",
            "oldRequestCurrent=\(original?.activity?.request.isGenerationCurrent == true)",
            "oldLogicalDeclared=\(original?.logical?.isDeclared == true)",
            "oldPhysicalActive=\(original?.physical?.state == .active)",
            "oldActualCount=\(original?.actuals.count ?? -1)",
            "oldActualsAttached=\(original?.actuals.allSatisfy(\.isAttached) == true)",
            "retainedBuildActive=\(runtime.hasActiveRetainedBuild)",
        ]
        print("EMPTY_ROW_ARRIVAL " + fields.joined(separator: " "))
    }

    private func reportCallback(_ kind: String) {
        let native = ViewBuildContextScope.current?.viewIdentity.lazyList?.native
        if let attempt = native?.attempt, !attempts.contains(where: { $0 === attempt }) { attempts.append(attempt) }
        if let attempt = native?.descriptorBuildAttemptID,
            !descriptorAttempts.contains(where: { $0 === attempt })
        {
            descriptorAttempts.append(attempt)
        }
        let attemptIndex = attempts.firstIndex { $0 === native?.attempt } ?? -1
        let descriptorIndex = descriptorAttempts.firstIndex { $0 === native?.descriptorBuildAttemptID } ?? -1
        let fields = [
            "callback=\(kind)", "phase=\(phase)", "factories=\(factoryCalls)", "bodies=\(bodyCalls)",
            "attempt=\(attemptIndex)", "descriptorAttempt=\(descriptorIndex)",
            "sourceIndex=\(native?.rowRequest.sourceIndex ?? -1)",
            "requestCurrent=\(native?.rowRequest.isGenerationCurrent == true)",
            "logicalDeclared=\(native?.logicalMembership.isDeclared == true)",
            "physicalActive=\(native?.physical.state == .active)",
            "sameLogicalID=\(native?.membership === original?.membershipID)",
            "samePhysicalID=\(native?.physical.id === original?.physicalID)",
        ]
        print("EMPTY_ROW_ARRIVAL " + fields.joined(separator: " "))
    }
}

@MainActor
private struct ManagedEmptyArrivalRow: View {
    @State private var value: Int
    let data: ManagedEmptyArrivalData
    let probe: ManagedEmptyArrivalProbe

    init(_ data: ManagedEmptyArrivalData, probe: ManagedEmptyArrivalProbe) {
        self.data = data
        self.probe = probe
        _value = State(initialValue: data.seed)
    }

    var body: some View {
        probe.recordBody(value: $value)
        let content = Color.blue
            .frame(width: 120, height: 20)
            .opacity(data.opacity)
            .transition(.asymmetric(insertion: .opacity, removal: .identity))
            .accessibilityIdentifier("managed.empty.arrival.\(data.id)")
        return AnyView(content)
    }
}

@MainActor
private func managedEmptyArrivalList(_ probe: ManagedEmptyArrivalProbe) -> some View {
    ManagedLazyListContent(
        probe.rows, id: \.id, estimatedExtent: 20, prefetchExtent: 0,
        maximumMountedRecords: 8, maximumMountedLeaves: 16, maximumProtectedRecords: 2
    ) { data in
        // A local declaration adds no result-builder child or identity segment.
        let _ = probe.recordFactory()
        if probe.showsRows { probe.makeRow(data) }
    }
}
