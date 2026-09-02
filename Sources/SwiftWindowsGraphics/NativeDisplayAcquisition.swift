import Foundation
import SwiftWindowsCore
import Synchronization

/// Raw application observations, not ETW events, displayed frames, or a timing
/// verdict. PID/TID/address values still require lifetime evidence before they
/// can be normalized into NativeDisplayMeasurement's supplied-fact identities.
package enum NativeDisplayAcquisition {
    package static let maximumClocks = 8
    package static let maximumEpochs = 64
    package static let maximumAttempts = 8192
    package static let maximumReceipts = 8192
    package static let maximumEncodedBytes = 32 * 1024 * 1024

    package struct Sample: Equatable, Sendable {
        package let ticks: UInt64
        package let processID: UInt32
        package let threadID: UInt32
        package init(ticks: UInt64, processID: UInt32, threadID: UInt32) {
            self.ticks = ticks
            self.processID = processID
            self.threadID = threadID
        }
    }

    package struct Binding: Equatable, Sendable {
        package let windowKey: NativeWindowKey
        package let attachmentID: NativeWindowAttachmentID
        package let surfaceGeneration: UInt64
        package init(windowKey: NativeWindowKey, attachmentID: NativeWindowAttachmentID, surfaceGeneration: UInt64) {
            self.windowKey = windowKey
            self.attachmentID = attachmentID
            self.surfaceGeneration = surfaceGeneration
        }
    }

    package struct Preparation: Equatable, Sendable {
        package enum Boundary: String, Sendable { case scene, queue }
        package let at: Sample?
        package let contentRevision: UInt64?
        package let boundary: Boundary
        package init(at: Sample?, contentRevision: UInt64?, boundary: Boundary) {
            self.at = at
            self.contentRevision = contentRevision
            self.boundary = boundary
        }
    }

    /// Lower capacities are useful for deterministic tests; raising any bound
    /// is rejected. This journal has one fixed native QPC source, not a registry.
    package struct Limits: Equatable, Sendable {
        package let attempts: Int
        package let epochs: Int
        package let receipts: Int
        package init(attempts: Int = 8192, epochs: Int = 64, receipts: Int = 8192) {
            self.attempts = attempts
            self.epochs = epochs
            self.receipts = receipts
        }
    }

    package enum Fault: String, Hashable, Sendable {
        case clockUnavailable, processChanged, nativeThreadChanged, chronology
        case duplicateRequest, capacity, duplicateReply, requestIdentity, receiptIdentity
        case scopeMismatch, deliveryOrder, missingEpoch, epochIdentity, multiplePresent, staleSubmission
        case unsupportedBackend, unsupportedFramePath, requestRejected, abandoned, lateObservation
    }

    package enum CaptureError: Error, Sendable {
        case invalidConfiguration
        case incomplete(Set<Fault>)
        case pendingWork
        case alreadyFinalized
        case encodedByteLimit
    }

    package enum NativeOutcome: String, Sendable { case returned, failed, threw }
    package enum ReplyOutcome: String, Sendable { case returned, failed, rejected }
    package enum EpochOpen: String, Sendable { case created, surfaceChanged }
    package enum EpochClose: String, Sendable { case released, surfaceChanged }

    package struct PresentRecord: Equatable, Sendable {
        package let epochID: UInt64
        package let address: UInt64
        package let frame: BackendFrameID
        package let syncInterval: UInt32
        package let flags: UInt32
        package fileprivate(set) var began: Sample?
        package fileprivate(set) var ended: Sample?
        package fileprivate(set) var hresult: Int32?
    }

    package struct RequestRecord: Equatable, Sendable {
        package let requestID: NativeWindowRequestID
        package let binding: Binding
        package let operation: NativePresentationOperationKind
        package let preparation: Preparation
        package fileprivate(set) var actualBinding: Binding?
        package fileprivate(set) var nativeEntered: Sample?
        package fileprivate(set) var nativeCompleted: Sample?
        package fileprivate(set) var nativeOutcome: NativeOutcome?
        package fileprivate(set) var rendererInvoked = false
        package fileprivate(set) var present: PresentRecord?
        package fileprivate(set) var submission: BackendFrameSubmission?
        package fileprivate(set) var replyArrived: Sample?
        package fileprivate(set) var replyOutcome: ReplyOutcome?
        package fileprivate(set) var replyBinding: Binding?
        package fileprivate(set) var replyFrame: BackendFrameID?
        package fileprivate(set) var actorConsumed: Sample?
        package fileprivate(set) var actorDeliveryFinished = false
        package fileprivate(set) var locallyRejected = false
        fileprivate var nativeBegan = false
        fileprivate var nativeFinished = false
        fileprivate var scopeActive = false
        fileprivate var replyFinished = false
        fileprivate var actorBegan = false
    }

    package struct EpochRecord: Equatable, Sendable {
        package let id: UInt64
        package let binding: Binding
        package let address: UInt64
        package let deviceGeneration: UInt64
        package let opened: Sample?
        package let openedBy: EpochOpen
        package fileprivate(set) var closed: Sample?
        package fileprivate(set) var closedBy: EpochClose?
        package fileprivate(set) var isClosed = false
    }

    package struct Diagnostics: Equatable, Sendable {
        package let attempts: Int
        package let receipts: Int
        package let activeScopes: Int
        package let openEpochs: Int
        package let pendingActorDeliveries: Int
        package let localRejections: Int
        package let faults: Set<Fault>
    }

    /// State holds copied values only. Sampling occurs before taking the mutex;
    /// no callback, native resource release, writer, task, or wait runs under it.
    package final class Recorder: Sendable {
        package let sessionID: UUID
        package let processID: UInt32
        package let frequency: UInt64
        private let limits: Limits
        private let sampler: @Sendable () -> Sample?
        private let state: Mutex<State>

        fileprivate struct State {
            var requests: [RequestRecord] = []
            var indices: [NativeWindowRequestID: Int] = [:]
            var epochs: [EpochRecord] = []
            var receipts = 0
            var nativeThreadID: UInt32?
            var skippedPreparations: UInt64 = 0
            var refusedPreparations: UInt64 = 0
            var faults: Set<Fault> = []
            var finalized = false
        }

        package init(
            sessionID: UUID, processID: UInt32, frequency: UInt64,
            limits: Limits = Limits(), sample: @escaping @Sendable () -> Sample?
        ) throws {
            guard processID != 0, frequency != 0,
                (1...maximumAttempts).contains(limits.attempts),
                (1...maximumEpochs).contains(limits.epochs),
                (1...maximumReceipts).contains(limits.receipts)
            else { throw CaptureError.invalidConfiguration }
            self.sessionID = sessionID
            self.processID = processID
            self.frequency = frequency
            self.limits = limits
            sampler = sample
            var initial = State()
            initial.requests.reserveCapacity(limits.attempts)
            initial.indices.reserveCapacity(limits.attempts)
            initial.epochs.reserveCapacity(limits.epochs)
            state = Mutex(initial)
        }

        package func sample() -> Sample? { sampler() }

        package var diagnostics: Diagnostics {
            state.withLock {
                Diagnostics(
                    attempts: $0.requests.count, receipts: $0.receipts,
                    activeScopes: $0.requests.filter(\.scopeActive).count,
                    openEpochs: $0.epochs.filter { !$0.isClosed }.count,
                    pendingActorDeliveries: $0.requests.filter { !$0.actorDeliveryFinished }.count,
                    localRejections: $0.requests.filter(\.locallyRejected).count, faults: $0.faults)
            }
        }

        package func prepare(
            requestID: NativeWindowRequestID, binding: Binding, operation: NativePresentationOperationKind,
            preparation: Preparation? = nil
        ) -> Context? {
            // A supplied failed scene sample remains failed; do not replace it
            // with a later queue timestamp or another clock.
            let prepared = preparation ?? Preparation(at: sample(), contentRevision: nil, boundary: .queue)
            let slot: Int? = state.withLock { state in
                guard !state.finalized else {
                    state.faults.insert(.lateObservation)
                    return nil
                }
                guard state.indices[requestID] == nil else {
                    state.faults.insert(.duplicateRequest)
                    return nil
                }
                guard state.requests.count < limits.attempts else {
                    state.faults.insert(.capacity)
                    return nil
                }
                check(prepared.at, native: false, state: &state)
                let slot = state.requests.count
                state.requests.append(
                    RequestRecord(
                        requestID: requestID, binding: binding, operation: operation, preparation: prepared))
                state.indices[requestID] = slot
                return slot
            }
            return slot.map {
                Context(recorder: self, slot: $0, requestID: requestID, binding: binding, operation: operation)
            }
        }

        package func noteSkippedPreparation(_ preparation: Preparation? = nil) {
            notePreparation(refused: false, preparation: preparation)
        }
        package func noteRefusedPreparation(_ preparation: Preparation? = nil) {
            notePreparation(refused: true, preparation: preparation)
        }

        private func notePreparation(refused: Bool, preparation: Preparation?) {
            state.withLock { state in
                guard !state.finalized else {
                    state.faults.insert(.lateObservation)
                    return
                }
                if let preparation { check(preparation.at, native: false, state: &state) }
                let current = refused ? state.refusedPreparations : state.skippedPreparations
                let (next, overflow) = current.addingReportingOverflow(1)
                guard !overflow else {
                    state.faults.insert(.capacity)
                    return
                }
                if refused { state.refusedPreparations = next } else { state.skippedPreparations = next }
            }
        }

        package func abandon() { state.withLock { $0.faults.insert(.abandoned) } }

        /// The composition root may call this only after successful native
        /// drain/join. These checks supplement that proof; they do not perform
        /// a join, authenticate a caller, or manufacture a capture lifetime.
        package func finishAfterDrain() throws -> Snapshot {
            try state.withLock { state in
                guard !state.finalized else { throw CaptureError.alreadyFinalized }
                guard state.faults.isEmpty else { throw CaptureError.incomplete(state.faults) }
                guard
                    state.requests.allSatisfy({ record in
                        record.actorDeliveryFinished && !record.scopeActive
                            && (!record.nativeBegan || record.nativeFinished)
                            && (record.replyFinished || record.locallyRejected)
                            && (record.present == nil || record.present?.hresult != nil)
                    }), state.epochs.allSatisfy(\.isClosed)
                else { throw CaptureError.pendingWork }
                state.finalized = true
                return Snapshot(
                    sessionID: sessionID, processID: processID, frequency: frequency,
                    requests: state.requests, epochs: state.epochs,
                    skippedPreparations: state.skippedPreparations, refusedPreparations: state.refusedPreparations)
            }
        }

        fileprivate func check(_ sample: Sample?, native: Bool, state: inout State) {
            guard let sample, sample.threadID != 0 else {
                state.faults.insert(.clockUnavailable)
                return
            }
            guard sample.processID == processID else {
                state.faults.insert(.processChanged)
                return
            }
            if native {
                if let existing = state.nativeThreadID, existing != sample.threadID {
                    state.faults.insert(.nativeThreadChanged)
                } else {
                    state.nativeThreadID = sample.threadID
                }
            }
        }

        fileprivate func update(_ context: Context, _ body: (inout State, Int) -> Void) {
            state.withLock { state in
                guard !state.finalized else {
                    state.faults.insert(.lateObservation)
                    return
                }
                guard context.recorder === self, state.requests.indices.contains(context.slot),
                    state.requests[context.slot].requestID == context.requestID
                else {
                    state.faults.insert(.requestIdentity)
                    return
                }
                body(&state, context.slot)
            }
        }

        fileprivate func openEpoch(_ context: Context, address: UInt64, deviceGeneration: UInt64) -> EpochToken? {
            let at = sample()
            var slot: Int?
            update(context) { state, index in
                check(at, native: true, state: &state)
                guard state.requests[index].scopeActive, address != 0 else {
                    state.faults.insert(.scopeMismatch)
                    return
                }
                guard state.epochs.count < limits.epochs else {
                    state.faults.insert(.capacity)
                    return
                }
                guard !state.epochs.contains(where: { !$0.isClosed && $0.address == address }) else {
                    state.faults.insert(.epochIdentity)
                    return
                }
                slot = state.epochs.count
                state.epochs.append(
                    EpochRecord(
                        id: UInt64(state.epochs.count), binding: context.binding, address: address,
                        deviceGeneration: deviceGeneration, opened: at, openedBy: .created))
            }
            return slot.map { EpochToken(recorder: self, slot: $0) }
        }

        fileprivate func rebind(_ token: EpochToken, to context: Context) -> EpochToken? {
            let at = sample()
            var result: EpochToken?
            update(context) { state, index in
                check(at, native: true, state: &state)
                guard token.recorder === self, state.epochs.indices.contains(token.slot),
                    !state.epochs[token.slot].isClosed, state.requests[index].scopeActive
                else {
                    state.faults.insert(.epochIdentity)
                    return
                }
                let previous = state.epochs[token.slot]
                guard previous.binding.windowKey == context.binding.windowKey,
                    previous.binding.attachmentID == context.binding.attachmentID
                else {
                    state.faults.insert(.epochIdentity)
                    return
                }
                if previous.binding == context.binding {
                    result = token
                    return
                }
                guard state.epochs.count < limits.epochs else {
                    state.faults.insert(.capacity)
                    return
                }
                state.epochs[token.slot].isClosed = true
                state.epochs[token.slot].closed = at
                state.epochs[token.slot].closedBy = .surfaceChanged
                let next = state.epochs.count
                state.epochs.append(
                    EpochRecord(
                        id: UInt64(next), binding: context.binding, address: previous.address,
                        deviceGeneration: previous.deviceGeneration, opened: at, openedBy: .surfaceChanged))
                result = EpochToken(recorder: self, slot: next)
            }
            return result
        }

        fileprivate func release(_ token: EpochToken, at: Sample?) {
            state.withLock { state in
                guard !state.finalized else {
                    state.faults.insert(.lateObservation)
                    return
                }
                check(at, native: true, state: &state)
                guard token.recorder === self, state.epochs.indices.contains(token.slot),
                    !state.epochs[token.slot].isClosed
                else {
                    state.faults.insert(.epochIdentity)
                    return
                }
                let opened = state.epochs[token.slot].opened
                if let opened, let at, at.ticks < opened.ticks { state.faults.insert(.chronology) }
                state.epochs[token.slot].isClosed = true
                state.epochs[token.slot].closed = at
                state.epochs[token.slot].closedBy = .released
            }
        }

        fileprivate func present(
            _ context: Context, epoch: EpochToken?, frame: BackendFrameID,
            address: UInt64, syncInterval: UInt32, flags: UInt32
        ) -> PresentTicket? {
            var accepted = false
            update(context) { state, index in
                guard state.requests[index].scopeActive, state.requests[index].rendererInvoked,
                    context.operation == .renderScene
                else {
                    state.faults.insert(.scopeMismatch)
                    return
                }
                guard state.requests[index].present == nil else {
                    state.faults.insert(.multiplePresent)
                    return
                }
                guard let epoch else {
                    state.faults.insert(.missingEpoch)
                    return
                }
                guard epoch.recorder === self, state.epochs.indices.contains(epoch.slot) else {
                    state.faults.insert(.epochIdentity)
                    return
                }
                let original = state.epochs[epoch.slot]
                guard !original.isClosed, original.binding == context.binding,
                    original.address == address, original.deviceGeneration == frame.deviceGeneration
                else {
                    state.faults.insert(.epochIdentity)
                    return
                }
                state.requests[index].present = PresentRecord(
                    epochID: original.id, address: address, frame: frame, syncInterval: syncInterval, flags: flags)
                accepted = true
            }
            return accepted ? PresentTicket(context: context) : nil
        }

        fileprivate func receive(
            _ context: Context, result: Result<NativePresentationReceipt, NativeWindowOwnerFailure>
        ) {
            let at = sample()
            update(context) { state, index in
                check(at, native: false, state: &state)
                guard !state.requests[index].replyFinished else {
                    state.faults.insert(.duplicateReply)
                    return
                }
                guard state.receipts < limits.receipts else {
                    state.faults.insert(.capacity)
                    return
                }
                state.receipts += 1
                state.requests[index].replyFinished = true
                state.requests[index].replyArrived = at
                switch result {
                case .failure:
                    state.requests[index].replyOutcome = .rejected
                    state.faults.insert(.requestRejected)
                case .success(let receipt):
                    let binding = Binding(
                        windowKey: receipt.surface.key, attachmentID: receipt.attachmentID,
                        surfaceGeneration: receipt.surface.generation)
                    state.requests[index].replyBinding = binding
                    state.requests[index].replyFrame = receipt.snapshot.lastFrameSubmission?.id
                    state.requests[index].replyOutcome = receipt.failure == nil ? .returned : .failed
                    guard receipt.requestID == context.requestID, receipt.operation == context.operation,
                        binding.windowKey == context.binding.windowKey,
                        binding.attachmentID == context.binding.attachmentID,
                        !context.requiresSurfaceGeneration
                            || binding.surfaceGeneration == context.binding.surfaceGeneration
                    else {
                        state.faults.insert(.receiptIdentity)
                        return
                    }
                    if !state.requests[index].nativeFinished { state.faults.insert(.deliveryOrder) }
                    if let frame = state.requests[index].present?.frame,
                        frame != receipt.snapshot.lastFrameSubmission?.id
                    {
                        state.faults.insert(.staleSubmission)
                    }
                }
            }
        }
    }

    /// An immutable request association; it contains no surface handle, runtime,
    /// command closure, window owner, attachment, backend, or COM object.
    package struct Context: Sendable {
        package let recorder: Recorder
        fileprivate let slot: Int
        package let requestID: NativeWindowRequestID
        package let binding: Binding
        package let operation: NativePresentationOperationKind

        package func matches(_ other: Context) -> Bool { recorder === other.recorder && slot == other.slot }
        fileprivate var requiresSurfaceGeneration: Bool {
            switch operation {
            case .install, .attach, .resize, .renderScene, .renderFrame: return true
            case .configure, .poll, .detach: return false
            }
        }

        package func invalidate(_ fault: Fault) { recorder.update(self) { state, _ in state.faults.insert(fault) } }

        package func enteredNative(actualBinding: Binding) {
            let at = recorder.sample()
            recorder.update(self) { state, index in
                recorder.check(at, native: true, state: &state)
                guard !state.requests[index].nativeBegan else {
                    state.faults.insert(.deliveryOrder)
                    return
                }
                state.requests[index].nativeBegan = true
                state.requests[index].nativeEntered = at
                state.requests[index].actualBinding = actualBinding
                if binding.windowKey != actualBinding.windowKey || binding.attachmentID != actualBinding.attachmentID
                    || (requiresSurfaceGeneration && binding.surfaceGeneration != actualBinding.surfaceGeneration)
                {
                    state.faults.insert(.requestIdentity)
                }
                if let prepared = state.requests[index].preparation.at, let at, at.ticks < prepared.ticks {
                    state.faults.insert(.chronology)
                }
            }
        }

        package func endedNative(_ outcome: NativeOutcome) {
            let at = recorder.sample()
            recorder.update(self) { state, index in
                recorder.check(at, native: true, state: &state)
                guard state.requests[index].nativeBegan, !state.requests[index].nativeFinished,
                    !state.requests[index].scopeActive
                else {
                    state.faults.insert(.deliveryOrder)
                    return
                }
                if let entered = state.requests[index].nativeEntered, let at, at.ticks < entered.ticks {
                    state.faults.insert(.chronology)
                }
                if let ended = state.requests[index].present?.ended, let at, at.ticks < ended.ticks {
                    state.faults.insert(.chronology)
                }
                state.requests[index].nativeFinished = true
                state.requests[index].nativeCompleted = at
                state.requests[index].nativeOutcome = outcome
            }
        }

        package func beginScope() -> Bool {
            var accepted = false
            recorder.update(self) { state, index in
                guard state.requests[index].nativeBegan, !state.requests[index].nativeFinished,
                    !state.requests[index].scopeActive
                else {
                    state.faults.insert(.scopeMismatch)
                    return
                }
                state.requests[index].scopeActive = true
                accepted = true
            }
            return accepted
        }

        package func endScope() {
            recorder.update(self) { state, index in
                guard state.requests[index].scopeActive else {
                    state.faults.insert(.scopeMismatch)
                    return
                }
                state.requests[index].scopeActive = false
            }
        }

        package func invokedRenderer() {
            recorder.update(self) { state, index in
                guard state.requests[index].scopeActive, !state.requests[index].rendererInvoked else {
                    state.faults.insert(.scopeMismatch)
                    return
                }
                state.requests[index].rendererInvoked = true
            }
        }

        package func recordSubmission(_ submission: BackendFrameSubmission?) {
            recorder.update(self) { state, index in
                guard state.requests[index].scopeActive, state.requests[index].rendererInvoked else {
                    state.faults.insert(.staleSubmission)
                    return
                }
                if let frame = state.requests[index].present?.frame, frame != submission?.id {
                    state.faults.insert(.staleSubmission)
                }
                state.requests[index].submission = submission
            }
        }

        package func receivedReply(_ result: Result<NativePresentationReceipt, NativeWindowOwnerFailure>) {
            recorder.receive(self, result: result)
        }

        package func rejectedLocally() {
            recorder.update(self) { state, index in
                guard !state.requests[index].nativeBegan, !state.requests[index].replyFinished,
                    !state.requests[index].locallyRejected
                else {
                    state.faults.insert(.deliveryOrder)
                    return
                }
                state.requests[index].locallyRejected = true
                state.faults.insert(.requestRejected)
            }
        }

        package func beginActorDelivery(rejected: Bool) {
            let at = recorder.sample()
            recorder.update(self) { state, index in
                recorder.check(at, native: false, state: &state)
                guard !state.requests[index].actorBegan,
                    state.requests[index].replyFinished || state.requests[index].locallyRejected
                else {
                    state.faults.insert(.deliveryOrder)
                    return
                }
                state.requests[index].actorBegan = true
                state.requests[index].actorConsumed = at
                if rejected { state.faults.insert(.requestRejected) }
            }
        }

        package func endActorDelivery() {
            recorder.update(self) { state, index in
                guard state.requests[index].actorBegan, !state.requests[index].actorDeliveryFinished else {
                    state.faults.insert(.deliveryOrder)
                    return
                }
                state.requests[index].actorDeliveryFinished = true
            }
        }

        package func openEpoch(address: UInt64, deviceGeneration: UInt64) -> EpochToken? {
            recorder.openEpoch(self, address: address, deviceGeneration: deviceGeneration)
        }

        package func preparePresent(
            epoch: EpochToken?, frame: BackendFrameID, address: UInt64, syncInterval: UInt32, flags: UInt32
        ) -> PresentTicket? {
            recorder.present(
                self, epoch: epoch, frame: frame, address: address, syncInterval: syncInterval, flags: flags)
        }
    }

    /// Independent of the last request: owner teardown can release the native
    /// swap chain after every request context has already been cleared.
    package struct EpochToken: Sendable {
        fileprivate let recorder: Recorder
        fileprivate let slot: Int
        package func sample() -> Sample? { recorder.sample() }
        package func didRelease(at: Sample?) { recorder.release(self, at: at) }
        package func rebound(to context: Context) -> EpochToken? { recorder.rebind(self, to: context) }
    }

    package struct PresentTicket: Sendable {
        fileprivate let context: Context
        package func sample() -> Sample? { context.recorder.sample() }

        /// Sampling brackets only the existing native call; the mutex update
        /// happens after the ending sample and before HRESULT recovery handling.
        package func returned(_ hresult: Int32, began: Sample?, ended: Sample?) {
            context.recorder.update(context) { state, index in
                context.recorder.check(began, native: true, state: &state)
                context.recorder.check(ended, native: true, state: &state)
                guard state.requests[index].scopeActive, var present = state.requests[index].present,
                    present.hresult == nil
                else {
                    state.faults.insert(.multiplePresent)
                    return
                }
                if let began, let ended, ended.ticks < began.ticks { state.faults.insert(.chronology) }
                present.began = began
                present.ended = ended
                present.hresult = hresult
                state.requests[index].present = present
            }
        }
    }

    /// Available only as a whole, after the recorder's completion checks. This
    /// is raw app evidence even when a test supplied every value synthetically.
    package struct Snapshot: Sendable {
        package let sessionID: UUID
        package let processID: UInt32
        package let frequency: UInt64
        package let requests: [RequestRecord]
        package let epochs: [EpochRecord]
        package let skippedPreparations: UInt64
        package let refusedPreparations: UInt64

        package func encoded(maximumBytes: Int = NativeDisplayAcquisition.maximumEncodedBytes) throws -> Data {
            guard (1...NativeDisplayAcquisition.maximumEncodedBytes).contains(maximumBytes),
                requests.count <= maximumAttempts, epochs.count <= maximumEpochs
            else { throw CaptureError.encodedByteLimit }
            var output = Data()
            func append(_ data: Data) throws {
                let (next, overflow) = output.count.addingReportingOverflow(data.count)
                guard !overflow, next <= maximumBytes else { throw CaptureError.encodedByteLimit }
                output.append(data)
            }
            func literal(_ value: String) throws { try append(Data(value.utf8)) }
            let header: [String: Any] = [
                "schema": 1, "kind": "nativeApplicationJournal", "sessionID": sessionID.uuidString,
                "processID": processID, "clock": "nativeQPC", "frequency": String(frequency),
                "nativeJournalComplete": true, "normalizedLifetimes": false,
                "containsDisplayFacts": false, "containsInputEffects": false,
                "skippedPreparations": String(skippedPreparations), "refusedPreparations": String(refusedPreparations),
            ]
            let headerData = try JSONSerialization.data(withJSONObject: header, options: [.sortedKeys])
            try append(Data(headerData.dropLast()))
            try literal(",\"requests\":[")
            for (index, request) in requests.enumerated() {
                if index != 0 { try literal(",") }
                try append(JSONSerialization.data(withJSONObject: request.json, options: [.sortedKeys]))
            }
            try literal("],\"epochs\":[")
            for (index, epoch) in epochs.enumerated() {
                if index != 0 { try literal(",") }
                try append(JSONSerialization.data(withJSONObject: epoch.json, options: [.sortedKeys]))
            }
            try literal("]}")
            return output
        }
    }
}

/// Optional package capability, leaving existing backend conformers and the
/// public presentation contract unchanged. Calls occur only inside perform's
/// native reentry/quiescence gate. A failed begin must preserve any outer scope.
package protocol NativeDisplayAcquisitionBackend: AnyObject {
    func beginDisplayAcquisition(_ context: NativeDisplayAcquisition.Context) -> Bool
    func endDisplayAcquisition(_ context: NativeDisplayAcquisition.Context)
}

private func acquisitionJSONSample(_ sample: NativeDisplayAcquisition.Sample?) -> Any {
    guard let sample else { return NSNull() }
    return ["ticks": String(sample.ticks), "processID": sample.processID, "threadID": sample.threadID] as [String: Any]
}

private func acquisitionJSONFrame(_ frame: BackendFrameID?) -> Any {
    guard let frame else { return NSNull() }
    return ["deviceGeneration": String(frame.deviceGeneration), "frameNumber": String(frame.frameNumber)]
}

extension NativeDisplayAcquisition.Binding {
    fileprivate var json: [String: Any] {
        [
            "windowID": windowKey.windowID.uuidString, "windowLifetimeID": windowKey.lifetimeID.uuidString,
            "attachmentID": attachmentID.rawValue.uuidString, "surfaceGeneration": String(surfaceGeneration),
        ]
    }
}

extension NativeDisplayAcquisition.RequestRecord {
    fileprivate var json: [String: Any] {
        var value: [String: Any] = [
            "requestID": requestID.rawValue.uuidString, "binding": binding.json, "operation": operation.rawValue,
            "prepared": acquisitionJSONSample(preparation.at), "preparationBoundary": preparation.boundary.rawValue,
            "contentRevision": preparation.contentRevision.map(String.init) as Any? ?? NSNull(),
            "actualBinding": actualBinding?.json as Any? ?? NSNull(),
            "nativeEntered": acquisitionJSONSample(nativeEntered),
            "nativeCompleted": acquisitionJSONSample(nativeCompleted),
            "nativeOutcome": nativeOutcome?.rawValue as Any? ?? NSNull(), "rendererInvoked": rendererInvoked,
            "replyArrived": acquisitionJSONSample(replyArrived),
            "replyOutcome": replyOutcome?.rawValue as Any? ?? NSNull(),
            "replyBinding": replyBinding?.json as Any? ?? NSNull(), "replyFrame": acquisitionJSONFrame(replyFrame),
            "actorConsumed": acquisitionJSONSample(actorConsumed), "actorDeliveryFinished": actorDeliveryFinished,
            "locallyRejected": locallyRejected,
        ]
        if let present {
            value["present"] =
                [
                    "epochID": String(present.epochID), "address": String(present.address),
                    "frame": acquisitionJSONFrame(present.frame),
                    "syncInterval": present.syncInterval, "flags": present.flags,
                    "began": acquisitionJSONSample(present.began), "ended": acquisitionJSONSample(present.ended),
                    "hresult": present.hresult as Any? ?? NSNull(),
                ] as [String: Any]
        } else {
            value["present"] = NSNull()
        }
        if let submission {
            value["submission"] =
                [
                    "frame": acquisitionJSONFrame(submission.id), "outcome": String(describing: submission.outcome),
                    "gpuTimingStatus": String(describing: submission.gpuTimingStatus),
                    "adapterIsSoftware": submission.adapterIsSoftware as Any? ?? NSNull(),
                ] as [String: Any]
        } else {
            value["submission"] = NSNull()
        }
        return value
    }
}

extension NativeDisplayAcquisition.EpochRecord {
    fileprivate var json: [String: Any] {
        [
            "id": String(id), "binding": binding.json, "address": String(address),
            "deviceGeneration": String(deviceGeneration),
            "opened": acquisitionJSONSample(opened), "openedBy": openedBy.rawValue,
            "closed": acquisitionJSONSample(closed), "closedBy": closedBy?.rawValue as Any? ?? NSNull(),
            "isClosed": isClosed,
        ]
    }
}
