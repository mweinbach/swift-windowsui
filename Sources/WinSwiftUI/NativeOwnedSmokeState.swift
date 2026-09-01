import Foundation
import SwiftWindowsCore
import SwiftWindowsGraphics
import SwiftWindowsPlatform
import Synchronization

/// Private vocabulary for the fixed executable; no application settings,
/// authored payloads, native UI pointers, or observer callbacks are stored.
struct NativeOwnedSmokeFailure: Error, Sendable, Encodable {
    let reason: String
    let nativeCode: Int64?
    let detail: String?
    let detailWasTruncated: Bool

    init(_ reason: String, code: Int64? = nil, detail: String? = nil) {
        self.reason = reason
        nativeCode = code
        self.detail = detail.map { String($0.prefix(512)) }
        detailWasTruncated = (detail?.count ?? 0) > 512
    }

    init(_ reason: String, error: any Error) {
        self.init(reason, code: nativeOwnedSmokeFailureCode(error), detail: String(describing: error))
    }
}

func nativeOwnedSmokeFailureCode(_ error: any Error) -> Int64? {
    guard let failure = error as? NativeWindowOwnerFailure else { return nil }
    switch failure {
    case .native(_, let code): return code
    case .postFailed(let code): return Int64(code)
    default: return nil
    }
}

struct NativeOwnedSmokeFrameTag: Sendable {
    let phase: UInt64
    let contentRevision: UInt64
}

enum NativeOwnedSmokeFrameFlags {
    static let transportSucceeded: UInt32 = 1 << 0
    static let presentationSucceeded: UInt32 = 1 << 1
    static let submitted: UInt32 = 1 << 2
    static let attached: UInt32 = 1 << 3
    static let hasFrameID: UInt32 = 1 << 4
    static let hardwareAdapter: UInt32 = 1 << 5
    static let softwareAdapter: UInt32 = 1 << 6
    static let expectedBackend: UInt32 = 1 << 7
    static let currentContent: UInt32 = 1 << 8
    static let scenePath: UInt32 = 1 << 9

    static func receipt(_ receipt: NativePresentationReceipt) -> UInt32 {
        var flags = transportSucceeded
        if receipt.failure == nil { flags |= presentationSucceeded }
        if receipt.snapshot.lastFrameSubmission?.outcome == .submitted { flags |= submitted }
        if receipt.snapshot.isAttached { flags |= attached }
        if receipt.snapshot.lastFrameSubmission?.id != nil { flags |= hasFrameID }
        if receipt.snapshot.lastFrameSubmission?.adapterIsSoftware == false { flags |= hardwareAdapter }
        if receipt.snapshot.lastFrameSubmission?.adapterIsSoftware == true { flags |= softwareAdapter }
        if receipt.operation == .renderScene { flags |= scenePath }
        return flags
    }
}

func recordNativeOwnedSmokeFrameReply(
    _ observation: Win32NativeSmokeObservation?, kind: Win32NativeSmokeEventKind,
    requestID: NativeWindowRequestID, surface: NativeWindowSurface, tag: NativeOwnedSmokeFrameTag?,
    result: Result<NativePresentationReceipt, NativeWindowOwnerFailure>
) {
    guard let observation, let tag else { return }
    switch result {
    case .success(let receipt):
        let frameID = receipt.snapshot.lastFrameSubmission?.id
        observation.record(
            kind, windowKey: receipt.surface.key, requestID: requestID,
            attachmentID: receipt.attachmentID,
            generation: receipt.surface.generation, deviceGeneration: frameID?.deviceGeneration,
            frameNumber: frameID?.frameNumber, nativeStartedAtSeconds: receipt.startedAtSeconds,
            nativeCompletedAtSeconds: receipt.completedAtSeconds,
            nativeSequence: receipt.surface.geometry.nativeSequence,
            revision: tag.contentRevision, auxiliary: tag.phase,
            flags: NativeOwnedSmokeFrameFlags.receipt(receipt))
    case .failure(let failure):
        observation.record(
            kind, windowKey: surface.key, requestID: requestID, generation: surface.generation,
            revision: tag.contentRevision, value: nativeOwnedSmokeFailureCode(failure), auxiliary: tag.phase)
    }
}

struct NativeOwnedSmokeHostSnapshot: Sendable, Encodable {
    let phase: Int
    let isClosed: Bool
    let hasNativeSurface: Bool
    let framePending: Bool
    let presentationPending: Bool
    let queuedPresentationRequests: Int
    let contentIsDirty: Bool
    let hasActiveAnimations: Bool
    let reloadScheduled: Bool
    let contentRevision: UInt64
    let lastPresentedRevision: UInt64?
    let surfaceGeneration: UInt64?
    let ingressQueued: Int
    let ingressTurnScheduled: Bool
    let receivedNativeSequence: UInt64
    let mailboxQueued: Int
    let nativeTurnActive: Bool
    let nativeWorkInFlight: Bool

    var isSettled: Bool {
        !isClosed && hasNativeSurface && !framePending && !presentationPending
            && queuedPresentationRequests == 0 && !contentIsDirty && !hasActiveAnimations && !reloadScheduled
            && contentRevision == lastPresentedRevision && ingressQueued == 0 && !ingressTurnScheduled
            && mailboxQueued == 0 && !nativeTurnActive && !nativeWorkInFlight
    }
}

/// Only copied values and explicitly retained thread-safe C resources cross
/// this fixture boundary. A and N never wait on this storage or call a hook
/// while holding its mutex. The independent controller owns the blocking waits.
final class NativeOwnedSmokeSharedState: Sendable {
    struct Snapshot: Sendable {
        var failures: [NativeOwnedSmokeFailure] = []
        var replyMask: UInt64 = 0
        var framePhaseMask: UInt8 = 0
        var windowKey: NativeWindowKey?
        var provider: Win32NativeSmokeProvider?
        var gate: Win32NativeSmokePublicationGate?
        var externalResult: Win32NativeSmokeControlTypeResult?
        var idleStart: NativeOwnedSmokeHostSnapshot?
        var idleEnd: NativeOwnedSmokeHostSnapshot?
        var ownerExitCode: Int32?
        var lateReplyCount = 0
        var lateReplyWasOwnerStopped = false
    }

    let observation: Win32NativeSmokeObservation
    let expectedBackendNames: Set<String>
    private let state = Mutex(Snapshot())

    init(observation: Win32NativeSmokeObservation, expectedBackendNames: Set<String>) {
        self.observation = observation
        self.expectedBackendNames = expectedBackendNames
    }

    func snapshot() -> Snapshot { state.withLock { $0 } }

    func fail(_ failure: NativeOwnedSmokeFailure) {
        state.withLock { stored in
            if stored.failures.count < 16 { stored.failures.append(failure) }
        }
        observation.record(.fixtureFailure, value: failure.nativeCode)
    }

    func installProvider(_ provider: Win32NativeSmokeProvider, windowKey: NativeWindowKey) -> Bool {
        state.withLock { stored in
            guard stored.provider == nil else { return false }
            stored.provider = provider
            stored.windowKey = windowKey
            return true
        }
    }

    func installGate(_ gate: Win32NativeSmokePublicationGate) -> Bool {
        state.withLock { stored in
            guard stored.gate == nil else { return false }
            stored.gate = gate
            return true
        }
    }

    func recordReply(
        ordinal: UInt32, requestID: NativeWindowRequestID,
        result: Result<NativeWindowSurface, NativeWindowOwnerFailure>
    ) {
        guard ordinal < 64 else {
            fail(NativeOwnedSmokeFailure("invalid-owned-command-reply-ordinal"))
            return
        }
        let bit = UInt64(1) << ordinal
        let duplicate = state.withLock { stored in
            let duplicate = stored.replyMask & bit != 0
            stored.replyMask |= bit
            return duplicate
        }
        if duplicate { fail(NativeOwnedSmokeFailure("duplicate-owned-command-reply")) }
        switch result {
        case .success(let surface):
            observation.record(
                .ownedCommandReply, windowKey: surface.key, requestID: requestID, generation: surface.generation,
                nativeSequence: surface.geometry.nativeSequence, value: Int64(ordinal), flags: 1)
        case .failure(let failure):
            observation.record(
                .ownedCommandReply, requestID: requestID, value: Int64(ordinal), flags: 0)
            fail(NativeOwnedSmokeFailure("owned-command-rejected-or-failed", error: failure))
        }
    }

    func recordAcceptedFrame(phase: UInt64) {
        guard phase < 3 else {
            fail(NativeOwnedSmokeFailure("unknown-frame-phase"))
            return
        }
        state.withLock { $0.framePhaseMask |= UInt8(1) << phase }
    }

    func recordIdle(_ snapshot: NativeOwnedSmokeHostSnapshot, ending: Bool) {
        state.withLock { stored in
            if ending { stored.idleEnd = snapshot } else { stored.idleStart = snapshot }
        }
    }

    func recordExternalResult(_ result: Win32NativeSmokeControlTypeResult) {
        state.withLock { $0.externalResult = result }
    }

    func recordOwnerExit(_ code: Int32) { state.withLock { $0.ownerExitCode = code } }

    func recordLateReply(_ result: Result<NativeWindowSurface, NativeWindowOwnerFailure>) {
        state.withLock { stored in
            stored.lateReplyCount += 1
            if case .failure(.ownerStopped) = result { stored.lateReplyWasOwnerStopped = true }
        }
        observation.record(.staleCommandRejected, flags: snapshot().lateReplyWasOwnerStopped ? 1 : 0)
    }

    func releaseExternalResources() {
        let previous = state.withLock { stored in
            let previous = (stored.provider, stored.gate)
            stored.provider = nil
            stored.gate = nil
            return previous
        }
        withExtendedLifetime(previous) {}
    }
}

@MainActor
final class NativeOwnedSmokeHostProbe {
    let shared: NativeOwnedSmokeSharedState
    var observation: Win32NativeSmokeObservation { shared.observation }
    private var adoptedPhase: UInt64 = 0
    private var adoptedRevision: UInt64?
    private var nestedProvider: Win32NativeSmokeProvider?

    init(shared: NativeOwnedSmokeSharedState) { self.shared = shared }

    func noteAdoptedContent(phase: Int, revision: UInt64) {
        adoptedPhase = UInt64(phase)
        adoptedRevision = revision
    }

    func frameTag(revision: UInt64) -> NativeOwnedSmokeFrameTag? {
        // Geometry may advance the retained revision without another content
        // adoption. The controlled model phase changes only at the existing
        // reload-completed hook, never merely because the model was mutated.
        guard adoptedRevision != nil else { return nil }
        return NativeOwnedSmokeFrameTag(phase: adoptedPhase, contentRevision: revision)
    }

    func armNestedQuery(_ provider: Win32NativeSmokeProvider) { nestedProvider = provider }

    func beforeRetainedQuery(_ surface: NativeWindowSurface) {
        observation.record(
            .actorQueryEntered, windowKey: surface.key, generation: surface.generation,
            nativeSequence: surface.geometry.nativeSequence)
        guard let provider = nestedProvider else { return }
        nestedProvider = nil
        let result = provider.controlType()
        observation.record(
            .nestedQueryCompleted, value: Int64(result.status), auxiliary: UInt64(UInt32(bitPattern: result.value)))
        guard result.status == Int32(bitPattern: 0x8000_4005), result.value == 0 else {
            shared.fail(NativeOwnedSmokeFailure("nested-query-did-not-preserve-E_FAIL", code: Int64(result.status)))
            return
        }
    }

    func frameConsumed(
        _ receipt: NativePresentationReceipt, tag: NativeOwnedSmokeFrameTag?, canTrackCurrentContent: Bool
    ) {
        guard let tag, receipt.failure == nil, receipt.snapshot.lastFrameSubmission?.outcome == .submitted else {
            return
        }
        var flags = NativeOwnedSmokeFrameFlags.receipt(receipt)
        if shared.expectedBackendNames.contains(receipt.snapshot.backendDisplayName) {
            flags |= NativeOwnedSmokeFrameFlags.expectedBackend
        }
        if canTrackCurrentContent { flags |= NativeOwnedSmokeFrameFlags.currentContent }
        let frameID = receipt.snapshot.lastFrameSubmission?.id
        let required =
            NativeOwnedSmokeFrameFlags.transportSucceeded | NativeOwnedSmokeFrameFlags.presentationSucceeded
            | NativeOwnedSmokeFrameFlags.submitted | NativeOwnedSmokeFrameFlags.attached
            | NativeOwnedSmokeFrameFlags.hasFrameID | NativeOwnedSmokeFrameFlags.hardwareAdapter
            | NativeOwnedSmokeFrameFlags.expectedBackend | NativeOwnedSmokeFrameFlags.currentContent
        if flags & required == required { shared.recordAcceptedFrame(phase: tag.phase) }
        observation.record(
            .frameSubmitted, windowKey: receipt.surface.key, requestID: receipt.requestID,
            attachmentID: receipt.attachmentID,
            generation: receipt.surface.generation, deviceGeneration: frameID?.deviceGeneration,
            frameNumber: frameID?.frameNumber, nativeStartedAtSeconds: receipt.startedAtSeconds,
            nativeCompletedAtSeconds: receipt.completedAtSeconds,
            nativeSequence: receipt.surface.geometry.nativeSequence,
            revision: tag.contentRevision, auxiliary: tag.phase, flags: flags)
    }
}
