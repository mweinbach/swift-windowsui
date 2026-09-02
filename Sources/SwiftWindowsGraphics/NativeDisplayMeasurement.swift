import Foundation
import SwiftWindowsCore

/// Checks bounded, caller-supplied associations. This does not acquire or
/// authenticate a capture, define demanded frames, or qualify hardware.
/// A matched join is unique only among the supplied facts.
package enum NativeDisplayMeasurement {
    /// A normalized source record/subfact identity, never a timestamp tie breaker.
    package struct FactID: Hashable, Sendable {
        package var source: UInt32
        package var ordinal: UInt64
        package var part: UInt32

        package init(source: UInt32, ordinal: UInt64, part: UInt32) {
            self.source = source
            self.ordinal = ordinal
            self.part = part
        }
    }

    package struct Process: Hashable, Sendable {
        package var pid: UInt32
        package var lifetime: UUID

        package init(pid: UInt32, lifetime: UUID) {
            self.pid = pid
            self.lifetime = lifetime
        }
    }

    /// The lifetime is supplied normalization, not an extra field on DXGI Stop.
    package struct Thread: Hashable, Sendable {
        package var process: Process
        package var tid: UInt32
        package var lifetime: UUID

        package init(process: Process, tid: UInt32, lifetime: UUID) {
            self.process = process
            self.tid = tid
            self.lifetime = lifetime
        }
    }

    package struct Window: Hashable, Sendable {
        package var process: Process
        package var key: NativeWindowKey

        package init(process: Process, key: NativeWindowKey) {
            self.process = process
            self.key = key
        }
    }

    /// Zero ticks are valid. Missing clock metadata is not a zero sentinel.
    package struct Stamp: Hashable, Sendable {
        package var clock: UInt32
        package var ticks: UInt64

        package init(clock: UInt32, ticks: UInt64) {
            self.clock = clock
            self.ticks = ticks
        }
    }

    package struct Interval: Hashable, Sendable {
        package var begin: Stamp
        package var end: Stamp

        package init(begin: Stamp, end: Stamp) {
            self.begin = begin
            self.end = end
        }
    }

    package enum ClockSource: Equatable, Sendable {
        case nativeQPC
        case etl(clockType: UInt32?, rawTimestamps: Bool?)
    }

    /// Nil means unknown when relevant to the source. No counter is repaired to zero.
    package struct Health: Equatable, Sendable {
        package var finalized: Bool?
        package var decoderComplete: Bool?
        package var eventsLost: UInt64?
        package var buffersLost: UInt64?
        package var decoderOverflow: UInt64?
        package var rejectedRecords: UInt64?

        package init(
            finalized: Bool?,
            decoderComplete: Bool?,
            eventsLost: UInt64?,
            buffersLost: UInt64?,
            decoderOverflow: UInt64?,
            rejectedRecords: UInt64?
        ) {
            self.finalized = finalized
            self.decoderComplete = decoderComplete
            self.eventsLost = eventsLost
            self.buffersLost = buffersLost
            self.decoderOverflow = decoderOverflow
            self.rejectedRecords = rejectedRecords
        }
    }

    package struct Clock: Equatable, Sendable {
        package var id: UInt32
        package var origin: UInt64?
        package var frequency: UInt64?
        package var source: ClockSource
        package var health: Health

        package init(id: UInt32, origin: UInt64?, frequency: UInt64?, source: ClockSource, health: Health) {
            self.id = id
            self.origin = origin
            self.frequency = frequency
            self.source = source
            self.health = health
        }
    }

    /// A closed original-issuance mapping. Later epochs never replace this identity.
    package struct Epoch: Equatable, Sendable {
        package var id: FactID
        package var epoch: UInt64
        package var thread: Thread
        package var window: Window
        package var attachment: NativeWindowAttachmentID
        package var surfaceGeneration: UInt64
        package var deviceGeneration: UInt64
        package var address: UInt64
        package var interval: Interval

        package init(
            id: FactID,
            epoch: UInt64,
            thread: Thread,
            window: Window,
            attachment: NativeWindowAttachmentID,
            surfaceGeneration: UInt64,
            deviceGeneration: UInt64,
            address: UInt64,
            interval: Interval
        ) {
            self.id = id
            self.epoch = epoch
            self.thread = thread
            self.window = window
            self.attachment = attachment
            self.surfaceGeneration = surfaceGeneration
            self.deviceGeneration = deviceGeneration
            self.address = address
            self.interval = interval
        }
    }

    package enum NoPresentReason: Equatable, Sendable {
        case commandRejected, renderFailed, cancelled, skipped, offscreen
    }

    package enum Presentation: Equatable, Sendable {
        case called(
            epoch: UInt64, address: UInt64, interval: Interval,
            syncInterval: UInt32, flags: UInt32, result: Int32)
        case notCalled(NoPresentReason)
        case unknown
    }

    package struct Attempt: Equatable, Sendable {
        package var id: FactID
        package var request: NativeWindowRequestID
        package var thread: Thread
        package var window: Window
        package var attachment: NativeWindowAttachmentID
        package var surfaceGeneration: UInt64
        package var frame: BackendFrameID?
        package var prepared: Stamp
        package var presentation: Presentation

        package init(
            id: FactID,
            request: NativeWindowRequestID,
            thread: Thread,
            window: Window,
            attachment: NativeWindowAttachmentID,
            surfaceGeneration: UInt64,
            frame: BackendFrameID?,
            prepared: Stamp,
            presentation: Presentation
        ) {
            self.id = id
            self.request = request
            self.thread = thread
            self.window = window
            self.attachment = attachment
            self.surfaceGeneration = surfaceGeneration
            self.frame = frame
            self.prepared = prepared
            self.presentation = presentation
        }
    }

    package enum DXGIKind: Equatable, Sendable {
        case start(address: UInt64, syncInterval: UInt32, flags: UInt32)
        case stop(result: Int32)
    }

    /// Stop intentionally has no address or independent swapchain identity.
    package struct DXGIEvent: Equatable, Sendable {
        package var id: FactID
        package var thread: Thread
        package var at: Stamp
        package var kind: DXGIKind

        package init(id: FactID, thread: Thread, at: Stamp, kind: DXGIKind) {
            self.id = id
            self.thread = thread
            self.at = at
            self.kind = kind
        }
    }

    package enum DispositionState: Equatable, Sendable {
        case displayed, discarded, lost, unknown
    }

    package struct Disposition: Equatable, Sendable {
        package var id: FactID
        package var start: FactID
        package var state: DispositionState

        package init(id: FactID, start: FactID, state: DispositionState) {
            self.id = id
            self.start = start
            self.state = state
        }
    }

    package struct Output: Hashable, Sendable {
        package var adapter: UInt64
        package var source: UInt32
        package var epoch: UInt64

        package init(adapter: UInt64, source: UInt32, epoch: UInt64) {
            self.adapter = adapter
            self.source = source
            self.epoch = epoch
        }
    }

    /// One API call may have zero or many display observations. Output is not Hz.
    package struct Display: Equatable, Sendable {
        package var id: FactID
        package var start: FactID
        package var index: UInt32
        package var output: Output
        package var at: Stamp

        package init(id: FactID, start: FactID, index: UInt32, output: Output, at: Stamp) {
            self.id = id
            self.start = start
            self.index = index
            self.output = output
            self.at = at
        }
    }

    package enum ReceiptOutcome: Equatable, Sendable {
        case returned, failed, cancelled, rejected
    }

    /// Thread and frame identify original issuance, not the current delivery epoch.
    package struct Receipt: Equatable, Sendable {
        package var id: FactID
        package var request: NativeWindowRequestID
        package var thread: Thread
        package var window: Window
        package var attachment: NativeWindowAttachmentID
        package var surfaceGeneration: UInt64
        package var frame: BackendFrameID?
        package var completed: Stamp
        package var delivered: Stamp
        package var outcome: ReceiptOutcome

        package init(
            id: FactID,
            request: NativeWindowRequestID,
            thread: Thread,
            window: Window,
            attachment: NativeWindowAttachmentID,
            surfaceGeneration: UInt64,
            frame: BackendFrameID?,
            completed: Stamp,
            delivered: Stamp,
            outcome: ReceiptOutcome
        ) {
            self.id = id
            self.request = request
            self.thread = thread
            self.window = window
            self.attachment = attachment
            self.surfaceGeneration = surfaceGeneration
            self.frame = frame
            self.completed = completed
            self.delivered = delivered
            self.outcome = outcome
        }
    }

    package struct InputID: Hashable, Sendable {
        package var window: Window
        package var nativeSequence: UInt64

        package init(window: Window, nativeSequence: UInt64) {
            self.window = window
            self.nativeSequence = nativeSequence
        }
    }

    package enum InputBoundary: Equatable, Sendable {
        case nativeDequeue, injectedBeforeSend, reportedEarlier
    }

    package enum Effect: Equatable, Sendable {
        case represented(request: NativeWindowRequestID)
        case superseded(by: InputID)
        case coalesced, cancelled, ignored, deferred, unknown
    }

    /// The effect relation and boundary are declarations, not authenticated causality.
    package struct Input: Equatable, Sendable {
        package var id: FactID
        package var input: InputID
        package var at: Stamp
        package var boundary: InputBoundary
        package var effect: Effect

        package init(id: FactID, input: InputID, at: Stamp, boundary: InputBoundary, effect: Effect) {
            self.id = id
            self.input = input
            self.at = at
            self.boundary = boundary
            self.effect = effect
        }
    }

    package struct Coverage: Equatable, Sendable {
        package var window: Window
        package var requested: Interval
        package var observed: Interval?
        package var headComplete: Bool?
        package var tailComplete: Bool?
        package var missing: [Interval]

        package init(
            window: Window,
            requested: Interval,
            observed: Interval?,
            headComplete: Bool?,
            tailComplete: Bool?,
            missing: [Interval]
        ) {
            self.window = window
            self.requested = requested
            self.observed = observed
            self.headComplete = headComplete
            self.tailComplete = tailComplete
            self.missing = missing
        }
    }

    package struct Batch: Equatable, Sendable {
        package var clocks: [Clock]
        package var epochs: [Epoch]
        package var attempts: [Attempt]
        package var events: [DXGIEvent]
        package var dispositions: [Disposition]
        package var displays: [Display]
        package var receipts: [Receipt]
        package var inputs: [Input]
        package var coverage: Coverage

        package init(
            clocks: [Clock],
            epochs: [Epoch],
            attempts: [Attempt],
            events: [DXGIEvent],
            dispositions: [Disposition],
            displays: [Display],
            receipts: [Receipt],
            inputs: [Input],
            coverage: Coverage
        ) {
            self.clocks = clocks
            self.epochs = epochs
            self.attempts = attempts
            self.events = events
            self.dispositions = dispositions
            self.displays = displays
            self.receipts = receipts
            self.inputs = inputs
            self.coverage = coverage
        }
    }

    package enum Resource: Equatable, Sendable {
        case clocks, epochs, attempts, events, starts, stops, dispositions
        case displays, receipts, inputs, missingIntervals, total, issues, gaps
    }

    package enum Rejection: Error, Equatable, Sendable {
        case capacity(resource: Resource, actual: Int, limit: Int)
        case arithmeticOverflow
        case duplicateFact(FactID)
        case duplicateClock(UInt32)
        case duplicateEpoch(UInt64)
        case duplicateRequest(NativeWindowRequestID)
        case duplicateInput(InputID)
        case duplicateDisplay(start: FactID, index: UInt32)
    }

    package enum Severity: Equatable, Sendable {
        case incomplete, contradictory
    }

    package enum IssueCode: Equatable, Sendable {
        case clockMissing, clockMetadataMissing, clockMismatch, clockNotQPC
        case invalidFrequency, sourceRoleMismatch, sourceUnfinalized
        case sourceDecodeIncomplete, sourceHealthMissing, sourceLoss
        case reversedInterval, emptyCoverage, identityMismatch, frameUnavailable
        case frameMismatch, epochMissing, epochAmbiguous, epochMismatch
        case threadOrderAmbiguous, orphanStart, orphanStop, nativeCallsOverlap
        case pairMissing, pairAmbiguous, pairReused, startMismatch, stopMismatch
        case presentationUnknown, referenceMissing, referenceWrongKind
        case dispositionMultiple, dispositionMissing, displayMissing
        case displayContradiction, displayBeforeStart, receiptMissing, receiptMultiple
        case receiptIdentityMismatch, receiptOrder, preparationOrder
        case inputWindowMismatch, inputOrder, supersessionInvalid, effectUnresolved
        case coverageMissing, coverageIncomplete, headIncomplete, tailIncomplete
        case coverageHole, unclaimedPair
    }

    package struct Issue: Equatable, Sendable {
        package var severity: Severity
        package var code: IssueCode
        package var fact: FactID?
        package var clock: UInt32?

        package init(severity: Severity, code: IssueCode, fact: FactID?, clock: UInt32?) {
            self.severity = severity
            self.code = code
            self.fact = fact
            self.clock = clock
        }
    }

    package enum APIResult: Equatable, Sendable {
        case unobserved
        case notCalled(NoPresentReason)
        case apiReturned(Int32)
        case apiFailed(Int32)
    }

    package enum Join: Equatable, Sendable {
        case notApplicable, unavailable, missing, ambiguous
        case matched(start: FactID, stop: FactID)
    }

    package struct AttemptAssociation: Equatable, Sendable {
        package var request: NativeWindowRequestID
        package var apiResult: APIResult
        package var join: Join
        package var disposition: DispositionState?
        package var displayFactIDs: [FactID]
        package var receiptFactID: FactID?
        package var receiptOutcome: ReceiptOutcome?

        package init(
            request: NativeWindowRequestID,
            apiResult: APIResult,
            join: Join,
            disposition: DispositionState?,
            displayFactIDs: [FactID],
            receiptFactID: FactID?,
            receiptOutcome: ReceiptOutcome?
        ) {
            self.request = request
            self.apiResult = apiResult
            self.join = join
            self.disposition = disposition
            self.displayFactIDs = displayFactIDs
            self.receiptFactID = receiptFactID
            self.receiptOutcome = receiptOutcome
        }
    }

    package enum RelationValidity: Equatable, Sendable {
        case consistent, incomplete, contradictory
    }

    package struct InputAssociation: Equatable, Sendable {
        package var input: InputID
        package var effect: Effect
        package var relation: RelationValidity

        package init(input: InputID, effect: Effect, relation: RelationValidity) {
            self.input = input
            self.effect = effect
            self.relation = relation
        }
    }

    /// Complement of supplied closed call brackets only. This is not unmet demand.
    package struct Gap: Equatable, Sendable {
        package var interval: Interval
        package var includesBegin: Bool
        package var includesEnd: Bool

        package init(interval: Interval, includesBegin: Bool, includesEnd: Bool) {
            self.interval = interval
            self.includesBegin = includesBegin
            self.includesEnd = includesEnd
        }
    }

    package enum Summary: Equatable, Sendable {
        case consistentSuppliedFacts, incompleteSuppliedFacts, contradictorySuppliedFacts
    }

    package struct Report: Equatable, Sendable {
        package var attempts: [AttemptAssociation]
        package var inputs: [InputAssociation]
        package var noSuppliedPresent: [Gap]
        package var issues: [Issue]

        package init(
            attempts: [AttemptAssociation], inputs: [InputAssociation],
            noSuppliedPresent: [Gap], issues: [Issue]
        ) {
            self.attempts = attempts
            self.inputs = inputs
            self.noSuppliedPresent = noSuppliedPresent
            self.issues = issues
        }

        package var summary: Summary {
            if issues.contains(where: { $0.severity == .contradictory }) {
                return .contradictorySuppliedFacts
            }
            return issues.isEmpty ? .consistentSuppliedFacts : .incompleteSuppliedFacts
        }
    }

    package enum Check: Equatable, Sendable {
        case rejected(Rejection)
        case checked(Report)
    }

    package static func check(_ batch: Batch) -> Check {
        do {
            var checker = Checker(batch: batch)
            return .checked(try checker.run())
        } catch {
            return .rejected(error)
        }
    }

    private enum Role {
        case native, etl
    }

    private enum FactKind: Equatable {
        case epoch, attempt, start, stop, disposition, display, receipt, input
    }

    private struct Basis: Equatable {
        let origin: UInt64
        let frequency: UInt64
    }

    private struct DisplayKey: Hashable {
        let start: FactID
        let index: UInt32
    }

    private struct Pair {
        let start: DXGIEvent
        let stop: DXGIEvent
    }

    private enum ThreadState {
        case paired, unavailable, incomplete, ambiguous
    }

    private struct Checker {
        let batch: Batch
        var clocks: [UInt32: Clock] = [:]
        var bases: [UInt32: Basis] = [:]
        var kinds: [FactID: FactKind] = [:]
        var usable: Set<FactID> = []
        var validity: [FactID: RelationValidity] = [:]
        var callIntervals: [Int: Interval] = [:]
        var callChronology: Set<Int> = []
        var issues: [Issue] = []
        var threadOrder: [Thread] = []
        var eventsByThread: [Thread: [DXGIEvent]] = [:]
        var threadStates: [Thread: ThreadState] = [:]
        var pairsByThread: [Thread: [Pair]] = [:]
        var pairs: [Pair] = []
        var eventsByID: [FactID: DXGIEvent] = [:]
        var dispositionsByStart: [FactID: [Disposition]] = [:]
        var displaysByStart: [FactID: [Display]] = [:]
        var receiptsByRequest: [NativeWindowRequestID: [Receipt]] = [:]
        var attemptsByRequest: [NativeWindowRequestID: Attempt] = [:]
        var inputsByID: [InputID: Input] = [:]

        init(batch: Batch) {
            self.batch = batch
        }

        mutating func run() throws(Rejection) -> Report {
            try preflight()
            buildIndexes()
            try validateClocks()
            try validateFacts()
            try pairEvents()
            try validateObservations()
            let attempts = try associateAttempts()
            let inputs = try associateInputs()
            let gaps = try coverageGaps()
            return Report(attempts: attempts, inputs: inputs, noSuppliedPresent: gaps, issues: issues)
        }

        private func capacity(_ resource: Resource, _ actual: Int, _ limit: Int) throws(Rejection) {
            guard actual <= limit else {
                throw .capacity(resource: resource, actual: actual, limit: limit)
            }
        }

        private func preflight() throws(Rejection) {
            let counts: [(Resource, Int, Int)] = [
                (.clocks, batch.clocks.count, 8), (.epochs, batch.epochs.count, 64),
                (.attempts, batch.attempts.count, 8192), (.events, batch.events.count, 16384),
                (.dispositions, batch.dispositions.count, 8192), (.displays, batch.displays.count, 16384),
                (.receipts, batch.receipts.count, 8192), (.inputs, batch.inputs.count, 8192),
                (.missingIntervals, batch.coverage.missing.count, 64),
            ]
            var total = 1
            for (resource, count, limit) in counts {
                try capacity(resource, count, limit)
                let addition = total.addingReportingOverflow(count)
                guard !addition.overflow else { throw .arithmeticOverflow }
                total = addition.partialValue
            }
            try capacity(.total, total, 65536)
            var starts = 0
            var stops = 0
            for event in batch.events {
                switch event.kind {
                case .start:
                    let next = starts.addingReportingOverflow(1)
                    guard !next.overflow else { throw .arithmeticOverflow }
                    starts = next.partialValue
                case .stop:
                    let next = stops.addingReportingOverflow(1)
                    guard !next.overflow else { throw .arithmeticOverflow }
                    stops = next.partialValue
                }
            }
            try capacity(.starts, starts, 8192)
            try capacity(.stops, stops, 8192)

            try unique(batch.clocks.map(\.id), duplicate: Rejection.duplicateClock)
            try unique(batch.epochs.map(\.epoch), duplicate: Rejection.duplicateEpoch)
            try unique(batch.attempts.map(\.request), duplicate: Rejection.duplicateRequest)
            try unique(batch.inputs.map(\.input), duplicate: Rejection.duplicateInput)
            let displayKeys = batch.displays.map { DisplayKey(start: $0.start, index: $0.index) }
            try unique(displayKeys) { .duplicateDisplay(start: $0.start, index: $0.index) }
            let factRosters = [
                batch.epochs.map(\.id), batch.attempts.map(\.id), batch.events.map(\.id),
                batch.dispositions.map(\.id), batch.displays.map(\.id), batch.receipts.map(\.id),
                batch.inputs.map(\.id),
            ]
            var factIDs: Set<FactID> = []
            for roster in factRosters {
                for id in roster {
                    guard factIDs.insert(id).inserted else { throw .duplicateFact(id) }
                }
            }
        }

        private func unique<Value: Hashable>(
            _ values: [Value], duplicate: (Value) -> Rejection
        ) throws(Rejection) {
            var seen: Set<Value> = []
            for value in values {
                guard seen.insert(value).inserted else { throw duplicate(value) }
            }
        }

        private mutating func buildIndexes() {
            // Capacity and duplicate validation precede every association index.
            for clock in batch.clocks { clocks[clock.id] = clock }
            for epoch in batch.epochs { kinds[epoch.id] = .epoch }
            for attempt in batch.attempts {
                kinds[attempt.id] = .attempt
                attemptsByRequest[attempt.request] = attempt
            }
            for event in batch.events {
                switch event.kind {
                case .start: kinds[event.id] = .start
                case .stop: kinds[event.id] = .stop
                }
                eventsByID[event.id] = event
                if eventsByThread[event.thread] == nil { threadOrder.append(event.thread) }
                eventsByThread[event.thread, default: []].append(event)
            }
            for disposition in batch.dispositions {
                kinds[disposition.id] = .disposition
                dispositionsByStart[disposition.start, default: []].append(disposition)
            }
            for display in batch.displays {
                kinds[display.id] = .display
                displaysByStart[display.start, default: []].append(display)
            }
            for receipt in batch.receipts {
                kinds[receipt.id] = .receipt
                receiptsByRequest[receipt.request, default: []].append(receipt)
            }
            for input in batch.inputs {
                kinds[input.id] = .input
                inputsByID[input.input] = input
            }
        }

        private mutating func note(
            _ severity: Severity, _ code: IssueCode, fact: FactID? = nil, clock: UInt32? = nil
        ) throws(Rejection) {
            let addition = issues.count.addingReportingOverflow(1)
            guard !addition.overflow else { throw .arithmeticOverflow }
            try capacity(.issues, addition.partialValue, 1024)
            issues.append(Issue(severity: severity, code: code, fact: fact, clock: clock))
            if let fact {
                if severity == .contradictory {
                    validity[fact] = .contradictory
                } else if validity[fact] != .contradictory {
                    validity[fact] = .incomplete
                }
            }
        }

        private mutating func validateClocks() throws(Rejection) {
            for clock in batch.clocks {
                var established = true
                if clock.origin == nil || clock.frequency == nil {
                    try note(.incomplete, .clockMetadataMissing, clock: clock.id)
                    established = false
                }
                if clock.frequency == 0 {
                    try note(.contradictory, .invalidFrequency, clock: clock.id)
                    established = false
                }
                let requiredCounters: [UInt64?]
                switch clock.source {
                case .nativeQPC:
                    requiredCounters = [clock.health.decoderOverflow, clock.health.rejectedRecords]
                case .etl(let clockType, let rawTimestamps):
                    requiredCounters = [
                        clock.health.decoderOverflow, clock.health.eventsLost, clock.health.buffersLost,
                    ]
                    if clockType == nil || rawTimestamps == nil {
                        try note(.incomplete, .clockMetadataMissing, clock: clock.id)
                        established = false
                    }
                    if let clockType, clockType != 1 {
                        try note(.contradictory, .clockNotQPC, clock: clock.id)
                        established = false
                    }
                    if rawTimestamps == false {
                        try note(.contradictory, .clockNotQPC, clock: clock.id)
                        established = false
                    }
                }
                if clock.health.finalized == nil || clock.health.decoderComplete == nil
                    || requiredCounters.contains(where: { $0 == nil })
                {
                    try note(.incomplete, .sourceHealthMissing, clock: clock.id)
                }
                if clock.health.finalized == false {
                    try note(.incomplete, .sourceUnfinalized, clock: clock.id)
                }
                if clock.health.decoderComplete == false {
                    try note(.incomplete, .sourceDecodeIncomplete, clock: clock.id)
                }
                let allCounters = [
                    clock.health.eventsLost, clock.health.buffersLost,
                    clock.health.decoderOverflow, clock.health.rejectedRecords,
                ]
                if allCounters.contains(where: { value in
                    if let value { return value != 0 }
                    return false
                }) {
                    try note(.incomplete, .sourceLoss, clock: clock.id)
                }
                if established, let origin = clock.origin, let frequency = clock.frequency {
                    bases[clock.id] = Basis(origin: origin, frequency: frequency)
                }
            }
        }

        private mutating func source(
            _ id: UInt32, role: Role?, fact: FactID?
        ) throws(Rejection) -> Bool {
            guard let clock = clocks[id] else {
                try note(.incomplete, .clockMissing, fact: fact, clock: id)
                return false
            }
            let matches: Bool
            switch (role, clock.source) {
            case (.none, _), (.some(.native), .nativeQPC), (.some(.etl), .etl):
                matches = true
            default:
                matches = false
            }
            if !matches { try note(.contradictory, .sourceRoleMismatch, fact: fact, clock: id) }
            return matches
        }

        private mutating func comparable(
            _ stamps: [Stamp], role: Role? = nil, fact: FactID? = nil
        ) throws(Rejection) -> Bool {
            var reference: Basis?
            var valid = true
            for stamp in stamps {
                if try !source(stamp.clock, role: role, fact: fact) { valid = false }
                guard let basis = bases[stamp.clock] else {
                    valid = false
                    continue
                }
                if let reference, reference != basis {
                    try note(.contradictory, .clockMismatch, fact: fact, clock: stamp.clock)
                    valid = false
                } else if reference == nil {
                    reference = basis
                }
            }
            return valid
        }

        private mutating func factTiming(
            _ id: FactID, role: Role, stamps: [Stamp], stampRole: Role?,
            sameSource: Bool = false
        ) throws(Rejection) -> Bool {
            var valid = try source(id.source, role: role, fact: id)
            if bases[id.source] == nil { valid = false }
            if try !comparable(stamps, role: stampRole, fact: id) { valid = false }
            for stamp in stamps {
                if sameSource && stamp.clock != id.source {
                    try note(.contradictory, .sourceRoleMismatch, fact: id, clock: stamp.clock)
                    valid = false
                }
                if let factBasis = bases[id.source], let stampBasis = bases[stamp.clock],
                    factBasis != stampBasis
                {
                    try note(.contradictory, .clockMismatch, fact: id, clock: stamp.clock)
                    valid = false
                }
            }
            return valid
        }

        private mutating func interval(
            _ value: Interval, role: Role? = nil, fact: FactID? = nil
        ) throws(Rejection) -> Bool {
            guard try comparable([value.begin, value.end], role: role, fact: fact) else { return false }
            guard value.begin.ticks <= value.end.ticks else {
                try note(.contradictory, .reversedInterval, fact: fact)
                return false
            }
            return true
        }

        private mutating func validateFacts() throws(Rejection) {
            for epoch in batch.epochs {
                var valid = try factTiming(
                    epoch.id, role: .native, stamps: [epoch.interval.begin, epoch.interval.end],
                    stampRole: .native)
                if try !interval(epoch.interval, role: .native, fact: epoch.id) { valid = false }
                if epoch.thread.process != epoch.window.process {
                    try note(.contradictory, .identityMismatch, fact: epoch.id)
                    valid = false
                }
                if valid { usable.insert(epoch.id) }
            }
            for (index, attempt) in batch.attempts.enumerated() {
                var valid = try factTiming(
                    attempt.id, role: .native, stamps: [attempt.prepared], stampRole: .native)
                if attempt.thread.process != attempt.window.process {
                    try note(.contradictory, .identityMismatch, fact: attempt.id)
                    valid = false
                }
                if case .called(_, _, let span, _, _, _) = attempt.presentation {
                    if try interval(span, role: .native, fact: attempt.id) {
                        callIntervals[index] = span
                    } else {
                        valid = false
                    }
                    let chronology = try factTiming(
                        attempt.id, role: .native,
                        stamps: [attempt.prepared, span.begin, span.end], stampRole: .native)
                    if chronology, attempt.prepared.ticks > span.begin.ticks {
                        try note(.contradictory, .preparationOrder, fact: attempt.id)
                        valid = false
                    }
                    if !chronology { valid = false }
                    if valid { callChronology.insert(index) }
                    if attempt.frame == nil {
                        try note(.incomplete, .frameUnavailable, fact: attempt.id)
                        valid = false
                    }
                }
                if valid { usable.insert(attempt.id) }
            }
            for event in batch.events {
                if try factTiming(
                    event.id, role: .etl, stamps: [event.at], stampRole: .etl, sameSource: true)
                {
                    usable.insert(event.id)
                }
            }
            for disposition in batch.dispositions {
                if try factTiming(disposition.id, role: .etl, stamps: [], stampRole: .etl) {
                    usable.insert(disposition.id)
                }
            }
            for display in batch.displays {
                if try factTiming(
                    display.id, role: .etl, stamps: [display.at], stampRole: .etl, sameSource: true)
                {
                    usable.insert(display.id)
                }
            }
            for receipt in batch.receipts {
                var valid = try factTiming(
                    receipt.id, role: .native, stamps: [receipt.completed, receipt.delivered],
                    stampRole: .native)
                if valid, receipt.completed.ticks > receipt.delivered.ticks {
                    try note(.contradictory, .receiptOrder, fact: receipt.id)
                    valid = false
                }
                if receipt.thread.process != receipt.window.process {
                    try note(.contradictory, .receiptIdentityMismatch, fact: receipt.id)
                    valid = false
                }
                if valid { usable.insert(receipt.id) }
            }
            for input in batch.inputs {
                let role: Role? = input.boundary == .reportedEarlier ? nil : .native
                if try factTiming(input.id, role: .native, stamps: [input.at], stampRole: role) {
                    usable.insert(input.id)
                }
            }
        }
        private mutating func pairEvents() throws(Rejection) {
            for thread in threadOrder {
                let events = eventsByThread[thread] ?? []
                guard events.allSatisfy({ usable.contains($0.id) }),
                    try comparable(events.map(\.at), role: .etl, fact: events.first?.id)
                else {
                    threadStates[thread] = .unavailable
                    continue
                }
                var ticks: Set<UInt64> = []
                if events.contains(where: { !ticks.insert($0.at.ticks).inserted }) {
                    try note(.incomplete, .threadOrderAmbiguous, fact: events.first?.id)
                    threadStates[thread] = .ambiguous
                    continue
                }
                let ordered = events.sorted { $0.at.ticks < $1.at.ticks }
                var pending: DXGIEvent?
                var localPairs: [Pair] = []
                var ambiguous = false
                var incomplete = false
                for event in ordered {
                    switch event.kind {
                    case .start:
                        if pending != nil {
                            try note(.incomplete, .threadOrderAmbiguous, fact: event.id)
                            ambiguous = true
                        }
                        pending = event
                    case .stop:
                        if let start = pending {
                            localPairs.append(Pair(start: start, stop: event))
                            pending = nil
                        } else {
                            try note(.incomplete, .orphanStop, fact: event.id)
                            incomplete = true
                        }
                    }
                }
                if let pending {
                    try note(.incomplete, .orphanStart, fact: pending.id)
                    incomplete = true
                }
                // Never salvage a first/last pair from a thread with unresolved
                // sequence structure. This small model does not reconstruct stacks.
                if ambiguous {
                    threadStates[thread] = .ambiguous
                } else if incomplete {
                    threadStates[thread] = .incomplete
                } else {
                    threadStates[thread] = .paired
                    pairsByThread[thread] = localPairs
                    pairs.append(contentsOf: localPairs)
                }
            }
        }

        private mutating func startReference(
            _ id: FactID, from fact: FactID
        ) throws(Rejection) -> DXGIEvent? {
            guard let kind = kinds[id] else {
                try note(.incomplete, .referenceMissing, fact: fact)
                return nil
            }
            guard kind == .start else {
                try note(.contradictory, .referenceWrongKind, fact: fact)
                return nil
            }
            return eventsByID[id]
        }

        private mutating func validateObservations() throws(Rejection) {
            let paired = Set(pairs.map { $0.start.id })
            var dispositionGroups: Set<FactID> = []
            for disposition in batch.dispositions {
                if dispositionGroups.insert(disposition.start).inserted,
                    (dispositionsByStart[disposition.start]?.count ?? 0) > 1
                {
                    try note(.contradictory, .dispositionMultiple, fact: disposition.id)
                }
                if let start = try startReference(disposition.start, from: disposition.id) {
                    if !paired.contains(start.id) {
                        try note(.incomplete, .pairMissing, fact: disposition.id)
                    }
                    // An unstamped fact still belongs to its original clock
                    // basis. Do not fabricate a timestamp to check this edge.
                    if let dispositionBasis = bases[disposition.id.source],
                        let startBasis = bases[start.at.clock]
                    {
                        if dispositionBasis != startBasis {
                            try note(
                                .contradictory, .clockMismatch, fact: disposition.id,
                                clock: disposition.id.source)
                            usable.remove(disposition.id)
                        }
                    } else {
                        usable.remove(disposition.id)
                    }
                }
                switch disposition.state {
                case .lost:
                    try note(.incomplete, .sourceLoss, fact: disposition.id)
                case .unknown:
                    try note(.incomplete, .presentationUnknown, fact: disposition.id)
                case .displayed, .discarded:
                    break
                }
            }
            for display in batch.displays {
                guard let start = try startReference(display.start, from: display.id) else { continue }
                if !paired.contains(start.id) { try note(.incomplete, .pairMissing, fact: display.id) }
                if usable.contains(display.id), usable.contains(start.id),
                    try comparable([start.at, display.at], role: .etl, fact: display.id),
                    display.at.ticks < start.at.ticks
                {
                    try note(.contradictory, .displayBeforeStart, fact: display.id)
                }
                // There is deliberately no Stop<=display or receipt<=display rule.
            }
            for event in batch.events {
                guard case .start = event.kind else { continue }
                let dispositions = dispositionsByStart[event.id] ?? []
                let displays = displaysByStart[event.id] ?? []
                if dispositions.isEmpty {
                    try note(.incomplete, .dispositionMissing, fact: event.id)
                }
                for disposition in dispositions {
                    if disposition.state == .displayed && displays.isEmpty {
                        try note(.incomplete, .displayMissing, fact: disposition.id)
                    }
                    if disposition.state == .discarded && !displays.isEmpty {
                        try note(.contradictory, .displayContradiction, fact: disposition.id)
                    }
                }
            }
            var receiptGroups: Set<NativeWindowRequestID> = []
            for receipt in batch.receipts {
                if receiptGroups.insert(receipt.request).inserted,
                    (receiptsByRequest[receipt.request]?.count ?? 0) > 1
                {
                    try note(.contradictory, .receiptMultiple, fact: receipt.id)
                }
                if attemptsByRequest[receipt.request] == nil {
                    try note(.incomplete, .referenceMissing, fact: receipt.id)
                }
            }
        }

        private mutating func overlappingCalls() throws(Rejection) -> Set<Int> {
            var order: [Thread] = []
            var grouped: [Thread: [Int]] = [:]
            for (index, attempt) in batch.attempts.enumerated() where callIntervals[index] != nil {
                if grouped[attempt.thread] == nil { order.append(attempt.thread) }
                grouped[attempt.thread, default: []].append(index)
            }
            var result: Set<Int> = []
            for thread in order {
                let indices = grouped[thread] ?? []
                let stamps = indices.compactMap { callIntervals[$0]?.begin }
                guard try comparable(stamps, role: .native) else { continue }
                let entries = indices.compactMap { index in
                    callIntervals[index].map { (index, $0) }
                }.sorted { $0.1.begin.ticks < $1.1.begin.ticks }
                var furthest: (index: Int, end: UInt64)?
                for (index, span) in entries {
                    if let previous = furthest {
                        if span.begin.ticks <= previous.end {
                            result.insert(previous.index)
                            result.insert(index)
                        }
                        if span.end.ticks > previous.end { furthest = (index, span.end.ticks) }
                    } else {
                        furthest = (index, span.end.ticks)
                    }
                }
            }
            return result
        }

        private mutating func epochJoin(
            attempt: Attempt, epochID: UInt64, address: UInt64, span: Interval, pair: Pair
        ) throws(Rejection) -> Join? {
            guard let epoch = batch.epochs.first(where: { $0.epoch == epochID }) else {
                try note(.incomplete, .epochMissing, fact: attempt.id)
                return .missing
            }
            let relevant = batch.epochs.filter {
                $0.address == address && $0.window.process == attempt.window.process
            }
            guard usable.contains(epoch.id), relevant.allSatisfy({ usable.contains($0.id) }),
                try comparable(
                    [span.begin, pair.start.at]
                        + relevant.flatMap { [$0.interval.begin, $0.interval.end] },
                    fact: attempt.id)
            else { return .unavailable }
            let nativeMappings = relevant.filter {
                $0.interval.begin.ticks <= span.begin.ticks && span.begin.ticks <= $0.interval.end.ticks
            }
            let eventMappings = relevant.filter {
                $0.interval.begin.ticks <= pair.start.at.ticks && pair.start.at.ticks <= $0.interval.end.ticks
            }
            if nativeMappings.count > 1 || eventMappings.count > 1 {
                try note(.incomplete, .epochAmbiguous, fact: attempt.id)
                return .ambiguous
            }
            guard nativeMappings.first?.epoch == epochID, eventMappings.first?.epoch == epochID,
                epoch.address == address, epoch.thread == attempt.thread, epoch.window == attempt.window,
                epoch.attachment == attempt.attachment, epoch.surfaceGeneration == attempt.surfaceGeneration
            else {
                try note(.contradictory, .epochMismatch, fact: attempt.id)
                return .unavailable
            }
            guard let frame = attempt.frame else { return .unavailable }
            guard frame.deviceGeneration == epoch.deviceGeneration else {
                try note(.contradictory, .frameMismatch, fact: attempt.id)
                return .unavailable
            }
            return nil
        }

        private mutating func receipt(for attempt: Attempt) throws(Rejection) -> Receipt? {
            let candidates = receiptsByRequest[attempt.request] ?? []
            if candidates.isEmpty {
                try note(.incomplete, .receiptMissing, fact: attempt.id)
                return nil
            }
            var matched: Receipt?
            for receipt in candidates {
                var valid = usable.contains(attempt.id) && usable.contains(receipt.id)
                if receipt.thread != attempt.thread || receipt.window != attempt.window
                    || receipt.attachment != attempt.attachment
                    || receipt.surfaceGeneration != attempt.surfaceGeneration
                {
                    try note(.contradictory, .receiptIdentityMismatch, fact: receipt.id)
                    valid = false
                }
                if receipt.frame != attempt.frame {
                    try note(.contradictory, .frameMismatch, fact: receipt.id)
                    valid = false
                }
                var stamps = [attempt.prepared, receipt.completed, receipt.delivered]
                var callEnd: Stamp?
                if case .called(_, _, let span, _, _, _) = attempt.presentation {
                    callEnd = span.end
                    stamps.append(span.end)
                }
                let chronology = try comparable(stamps, role: .native, fact: receipt.id)
                if chronology {
                    if attempt.prepared.ticks > receipt.completed.ticks
                        || receipt.completed.ticks > receipt.delivered.ticks
                        || (callEnd.map { $0.ticks > receipt.completed.ticks } ?? false)
                    {
                        try note(.contradictory, .receiptOrder, fact: receipt.id)
                        valid = false
                    }
                } else {
                    valid = false
                }
                if valid && candidates.count == 1 { matched = receipt }
            }
            return matched
        }

        private mutating func associateAttempts() throws(Rejection) -> [AttemptAssociation] {
            let overlapping = try overlappingCalls()
            var candidates: [Int: Pair] = [:]
            var owners: [FactID: [Int]] = [:]
            var joins: [Int: Join] = [:]
            for (index, attempt) in batch.attempts.enumerated() {
                guard case .called = attempt.presentation else { continue }
                guard let span = callIntervals[index] else {
                    joins[index] = .unavailable
                    continue
                }
                switch threadStates[attempt.thread] {
                case .some(.ambiguous):
                    joins[index] = .ambiguous
                    continue
                case .some(.unavailable):
                    joins[index] = .unavailable
                    continue
                case .some(.incomplete), .none:
                    try note(.incomplete, .pairMissing, fact: attempt.id)
                    joins[index] = .missing
                    continue
                case .some(.paired):
                    break
                }
                let threadPairs = pairsByThread[attempt.thread] ?? []
                let comparableStamps = [span.begin, span.end] + threadPairs.flatMap { [$0.start.at, $0.stop.at] }
                guard try comparable(comparableStamps, fact: attempt.id) else {
                    joins[index] = .unavailable
                    continue
                }
                let matches = threadPairs.filter {
                    span.begin.ticks <= $0.start.at.ticks && $0.stop.at.ticks <= span.end.ticks
                }
                if matches.isEmpty {
                    try note(.incomplete, .pairMissing, fact: attempt.id)
                    joins[index] = .missing
                } else if matches.count > 1 {
                    try note(.incomplete, .pairAmbiguous, fact: attempt.id)
                    joins[index] = .ambiguous
                } else if let pair = matches.first {
                    candidates[index] = pair
                    owners[pair.start.id, default: []].append(index)
                }
            }
            var result: [AttemptAssociation] = []
            var claimed: Set<FactID> = []
            for (index, attempt) in batch.attempts.enumerated() {
                let apiResult: APIResult
                var join: Join
                switch attempt.presentation {
                case .notCalled(let reason):
                    apiResult = .notCalled(reason)
                    join = .notApplicable
                case .unknown:
                    apiResult = .unobserved
                    join = .unavailable
                    try note(.incomplete, .presentationUnknown, fact: attempt.id)
                case .called(let epoch, let address, let span, let sync, let flags, let code):
                    apiResult = code < 0 ? .apiFailed(code) : .apiReturned(code)
                    join = joins[index] ?? .unavailable
                    if let pair = candidates[index] {
                        var valid = usable.contains(attempt.id)
                        if case .start(let observedAddress, let observedSync, let observedFlags) = pair.start.kind,
                            observedAddress != address || observedSync != sync || observedFlags != flags
                        {
                            try note(.contradictory, .startMismatch, fact: attempt.id)
                            valid = false
                        }
                        if case .stop(let observedCode) = pair.stop.kind, observedCode != code {
                            try note(.contradictory, .stopMismatch, fact: attempt.id)
                            valid = false
                        }
                        if let epochFailure = try epochJoin(
                            attempt: attempt, epochID: epoch, address: address, span: span, pair: pair)
                        {
                            join = epochFailure
                            valid = false
                        }
                        if valid { join = .matched(start: pair.start.id, stop: pair.stop.id) }
                        if (owners[pair.start.id]?.count ?? 0) > 1 {
                            try note(.incomplete, .pairReused, fact: attempt.id)
                            join = .ambiguous
                        }
                    }
                    if overlapping.contains(index) {
                        try note(.incomplete, .nativeCallsOverlap, fact: attempt.id)
                        join = .ambiguous
                    }
                }
                var disposition: DispositionState?
                var displayIDs: [FactID] = []
                if case .matched(let start, _) = join {
                    claimed.insert(start)
                    let states = dispositionsByStart[start] ?? []
                    if states.count == 1, let state = states.first, usable.contains(state.id) {
                        disposition = state.state
                    }
                    displayIDs = (displaysByStart[start] ?? []).map(\.id)
                }
                let receipt = try receipt(for: attempt)
                result.append(
                    AttemptAssociation(
                        request: attempt.request, apiResult: apiResult, join: join,
                        disposition: disposition, displayFactIDs: displayIDs,
                        receiptFactID: receipt?.id, receiptOutcome: receipt?.outcome))
            }
            for pair in pairs where !claimed.contains(pair.start.id) {
                try note(.incomplete, .unclaimedPair, fact: pair.start.id)
            }
            return result
        }
        private func relation(for ids: [FactID]) -> RelationValidity {
            if ids.contains(where: { validity[$0] == .contradictory }) { return .contradictory }
            if ids.contains(where: { !usable.contains($0) || validity[$0] == .incomplete }) {
                return .incomplete
            }
            return .consistent
        }

        private mutating func associateInputs() throws(Rejection) -> [InputAssociation] {
            var relations: [[FactID]] = []
            for input in batch.inputs {
                var related = [input.id]
                switch input.effect {
                case .represented(let request):
                    if let attempt = attemptsByRequest[request] {
                        related.append(attempt.id)
                        if attempt.window != input.input.window {
                            try note(.contradictory, .inputWindowMismatch, fact: input.id)
                        }
                        if try comparable([input.at, attempt.prepared], fact: input.id),
                            input.at.ticks > attempt.prepared.ticks
                        {
                            try note(.contradictory, .inputOrder, fact: input.id)
                        }
                    } else {
                        try note(.incomplete, .referenceMissing, fact: input.id)
                    }
                case .superseded(let successor):
                    if let target = inputsByID[successor] {
                        related.append(target.id)
                        if successor == input.input
                            || successor.nativeSequence <= input.input.nativeSequence
                        {
                            try note(.contradictory, .supersessionInvalid, fact: input.id)
                        }
                        if successor.window != input.input.window {
                            try note(.contradictory, .inputWindowMismatch, fact: input.id)
                        }
                        if try comparable([input.at, target.at], fact: input.id),
                            target.at.ticks < input.at.ticks
                        {
                            try note(.contradictory, .inputOrder, fact: input.id)
                        }
                    } else {
                        try note(.incomplete, .referenceMissing, fact: input.id)
                    }
                case .deferred, .unknown:
                    try note(.incomplete, .effectUnresolved, fact: input.id)
                case .coalesced, .cancelled, .ignored:
                    break
                }
                relations.append(related)
            }
            // Resolve relation states after every input has been checked; a
            // successor appearing later in the array must not get a free pass.
            return batch.inputs.enumerated().map { index, input in
                InputAssociation(
                    input: input.input, effect: input.effect, relation: relation(for: relations[index]))
            }
        }

        private mutating func coverageGaps() throws(Rejection) -> [Gap] {
            let coverage = batch.coverage
            let requestedValid = try interval(coverage.requested)
            if coverage.headComplete != true { try note(.incomplete, .headIncomplete) }
            if coverage.tailComplete != true { try note(.incomplete, .tailIncomplete) }
            if let observed = coverage.observed {
                let observedValid = try interval(observed)
                if requestedValid, observedValid,
                    try comparable([
                        coverage.requested.begin, coverage.requested.end, observed.begin, observed.end,
                    ]),
                    observed.begin.ticks > coverage.requested.begin.ticks
                        || observed.end.ticks < coverage.requested.end.ticks
                {
                    try note(.incomplete, .coverageIncomplete)
                }
            } else {
                try note(.incomplete, .coverageMissing)
            }
            for missing in coverage.missing {
                let missingValid = try interval(missing)
                if requestedValid && missingValid {
                    _ = try comparable([
                        coverage.requested.begin, coverage.requested.end, missing.begin, missing.end,
                    ])
                }
                try note(.incomplete, .coverageHole)
            }
            guard requestedValid else { return [] }
            guard coverage.requested.begin.ticks < coverage.requested.end.ticks else {
                try note(.incomplete, .emptyCoverage)
                return []
            }
            var spans: [Interval] = []
            for (index, attempt) in batch.attempts.enumerated() where attempt.window == coverage.window {
                guard case .called = attempt.presentation else { continue }
                guard callChronology.contains(index), let span = callIntervals[index],
                    try comparable(
                        [coverage.requested.begin, coverage.requested.end, span.begin, span.end],
                        fact: attempt.id)
                else { return [] }
                if span.end.ticks < coverage.requested.begin.ticks
                    || span.begin.ticks > coverage.requested.end.ticks
                {
                    continue
                }
                spans.append(
                    Interval(
                        begin: span.begin.ticks < coverage.requested.begin.ticks
                            ? coverage.requested.begin : span.begin,
                        end: span.end.ticks > coverage.requested.end.ticks
                            ? coverage.requested.end : span.end))
            }
            // Subtract closed supplied brackets, retaining boundary sources and
            // exact endpoint inclusion. Never generate or classify frame demand.
            spans.sort { $0.begin.ticks < $1.begin.ticks }
            var merged: [Interval] = []
            for span in spans {
                if let last = merged.last, span.begin.ticks <= last.end.ticks {
                    if span.end.ticks > last.end.ticks { merged[merged.count - 1].end = span.end }
                } else {
                    merged.append(span)
                }
            }
            var gaps: [Gap] = []
            var cursor = coverage.requested.begin
            var includesCursor = true
            for span in merged {
                if cursor.ticks < span.begin.ticks {
                    gaps.append(
                        Gap(
                            interval: Interval(begin: cursor, end: span.begin),
                            includesBegin: includesCursor, includesEnd: false))
                }
                cursor = span.end
                includesCursor = false
            }
            if cursor.ticks < coverage.requested.end.ticks {
                gaps.append(
                    Gap(
                        interval: Interval(begin: cursor, end: coverage.requested.end),
                        includesBegin: includesCursor, includesEnd: true))
            }
            let limit = batch.attempts.count.addingReportingOverflow(1)
            guard !limit.overflow else { throw .arithmeticOverflow }
            try capacity(.gaps, gaps.count, limit.partialValue)
            return gaps
        }
    }
}
