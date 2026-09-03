import SwiftWindowsCore

/// Diagnostic arithmetic only. No UI owner, callback, proof, or currentness is retained.
@MainActor
final class RetainedConstructionValidationCounters {
    struct Snapshot: Sendable, Equatable {
        var admissionBuildChecks: UInt64 = 0
        var forestValidations: UInt64 = 0
        var completionValidations: UInt64 = 0
        var forestNodeVisits: UInt64 = 0
        var forestFailures: UInt64 = 0
        var maximumForestNodeVisits: UInt64 = 0
        var modalSnapshotRequests: UInt64 = 0
        var modalScans: UInt64 = 0
        var modalDispatchNodeVisits: UInt64 = 0
        var maximumModalNodeVisits: UInt64 = 0
        var overflowed = false

        /// Called only at a phase boundary, never by a validation check.
        var jsonFields: String {
            "\"admissionBuildChecks\":\(admissionBuildChecks),"
                + "\"forestValidations\":\(forestValidations),"
                + "\"completionValidations\":\(completionValidations),"
                + "\"forestNodeVisits\":\(forestNodeVisits),"
                + "\"forestFailures\":\(forestFailures),"
                + "\"maximumForestNodeVisits\":\(maximumForestNodeVisits),"
                + "\"modalSnapshotRequests\":\(modalSnapshotRequests),"
                + "\"modalScans\":\(modalScans),"
                + "\"modalDispatchNodeVisits\":\(modalDispatchNodeVisits),"
                + "\"maximumModalNodeVisits\":\(maximumModalNodeVisits),"
                + "\"overflowed\":\(overflowed)"
        }
    }

    enum PhaseRecord {
        case snapshot(Snapshot)
        case capReached(Snapshot)
        case disabled
    }

    private(set) var snapshot = Snapshot()
    private let phaseRecordLimit: UInt64
    private var phaseRecords: UInt64 = 0
    private var reportedPhaseCap = false

    init(phaseRecordLimit: UInt64 = 512) {
        precondition(phaseRecordLimit <= 512)
        self.phaseRecordLimit = phaseRecordLimit
    }

    func recordAdmissionCheck(count: UInt64 = 1) {
        if Self.add(count, to: &snapshot.admissionBuildChecks) { snapshot.overflowed = true }
    }

    func recordForestStart() {
        if Self.add(1, to: &snapshot.forestValidations) { snapshot.overflowed = true }
    }

    func recordCompletionValidation() {
        if Self.add(1, to: &snapshot.completionValidations) { snapshot.overflowed = true }
    }

    func recordForestResult(nodeVisits: Int, isCurrent: Bool) {
        guard nodeVisits >= 0 else {
            snapshot.overflowed = true
            return
        }
        let visits = UInt64(nodeVisits)
        if Self.add(visits, to: &snapshot.forestNodeVisits) { snapshot.overflowed = true }
        snapshot.maximumForestNodeVisits = max(snapshot.maximumForestNodeVisits, visits)
        if !isCurrent, Self.add(1, to: &snapshot.forestFailures) { snapshot.overflowed = true }
    }

    func recordModalRequest() {
        if Self.add(1, to: &snapshot.modalSnapshotRequests) { snapshot.overflowed = true }
    }

    func recordModalScan() {
        if Self.add(1, to: &snapshot.modalScans) { snapshot.overflowed = true }
    }

    func recordModalResult(nodeVisits: UInt64) {
        if Self.add(nodeVisits, to: &snapshot.modalDispatchNodeVisits) { snapshot.overflowed = true }
        snapshot.maximumModalNodeVisits = max(snapshot.maximumModalNodeVisits, nodeVisits)
    }

    func nextPhaseRecord() -> PhaseRecord {
        if phaseRecords < phaseRecordLimit {
            phaseRecords += 1
            return .snapshot(snapshot)
        }
        guard !reportedPhaseCap else { return .disabled }
        reportedPhaseCap = true
        return .capReached(snapshot)
    }

    private static func add(_ delta: UInt64, to value: inout UInt64) -> Bool {
        let sum = value.addingReportingOverflow(delta)
        value = sum.overflow ? UInt64.max : sum.partialValue
        return sum.overflow
    }
}

/// Only existing phase boundaries use this wrapper. It cannot retain a runtime or node.
@MainActor
struct RetainedConstructionPhaseTrace {
    let trace: RetainedConstructionTrace
    let counters: RetainedConstructionValidationCounters?

    @discardableResult
    func record(_ event: StaticString, span: UInt64? = nil, host: UInt? = nil, node: UInt? = nil) -> UInt64? {
        guard let counters else { return trace.record(event, span: span, host: host, node: node) }
        switch counters.nextPhaseRecord() {
        case .snapshot(let snapshot):
            return trace.recordValidationPhase(
                event, span: span, host: host, node: node, monotonicSeconds: PlatformClock.now(),
                snapshot: snapshot, partial: snapshot.overflowed)
        case .capReached(let snapshot):
            trace.recordValidationPhase(
                "validation.capReached", monotonicSeconds: PlatformClock.now(), snapshot: snapshot, partial: true)
            return trace.record(event, span: span, host: host, node: node)
        case .disabled:
            return trace.record(event, span: span, host: host, node: node)
        }
    }
}
