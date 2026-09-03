import SwiftWindowsCore
import SwiftWindowsGraphics
import SwiftWindowsPlatform

/// Serializes the host's native presentation requests without blocking the UI
/// actor. A request is removed only when its real native reply arrives; neither
/// command admission nor an actor task's scheduling order is a completion.
@MainActor
final class NativeHostPresentationQueue {
    typealias Completion = @MainActor (Result<NativePresentationReceipt, NativeWindowOwnerFailure>) -> Void

    private struct Pending: Sendable {
        let id: NativeWindowRequestID
        let surface: NativeWindowSurface
        let expectedGeneration: UInt64?
        let operation: NativePresentationOperation
        let smokeTag: NativeOwnedSmokeFrameTag?
        let acquisition: NativeDisplayAcquisition.Context?
        let completion: Completion
    }

    private let sink: any NativeWindowCommandSink
    private let attachmentID: NativeWindowAttachmentID
    private let teardownStore: NativePresentationTeardownStore
    private let smokeObservation: Win32NativeSmokeObservation?
    private let acquisition: NativeDisplayAcquisition.Recorder?
    private var pending: [Pending] = []
    private var executing: Pending?
    private var acceptsRequests = true
    private var isDeliveringCompletion = false
    private var isRejectingPendingRequests = false
    private var drainCallbacks: [@MainActor () -> Void] = []

    init(
        sink: any NativeWindowCommandSink, attachmentID: NativeWindowAttachmentID,
        teardownStore: NativePresentationTeardownStore,
        smokeObservation: Win32NativeSmokeObservation? = nil,
        acquisition: NativeDisplayAcquisition.Recorder? = nil
    ) {
        self.sink = sink
        self.attachmentID = attachmentID
        self.teardownStore = teardownStore
        self.smokeObservation = smokeObservation
        self.acquisition = acquisition
    }

    func submit(
        _ operation: NativePresentationOperation, surface: NativeWindowSurface,
        requiresSurfaceGeneration: Bool = true, smokeTag: NativeOwnedSmokeFrameTag? = nil,
        preparation: NativeDisplayAcquisition.Preparation? = nil, completion: @escaping Completion
    ) {
        guard acceptsRequests else {
            acquisition?.noteRefusedPreparation(preparation)
            completion(.failure(.closing))
            return
        }
        let requestID = NativeWindowRequestID()
        let capture = acquisition?.prepare(
            requestID: requestID,
            binding: NativeDisplayAcquisition.Binding(
                windowKey: surface.key, attachmentID: attachmentID, surfaceGeneration: surface.generation),
            operation: operation.kind, preparation: preparation)
        pending.append(
            Pending(
                id: requestID, surface: surface,
                expectedGeneration: requiresSurfaceGeneration ? surface.generation : nil,
                operation: operation, smokeTag: smokeTag, acquisition: capture, completion: completion
            )
        )
        advance()
    }

    /// A passive actor observation. It does not register a drain callback or
    /// advance presentation; a claimed native reply is still outstanding here
    /// until the existing completion task consumes it.
    var smokeOutstandingRequestCount: Int { pending.count + (executing == nil ? 0 : 1) }

    /// Pending work has never reached the owner and can be rejected now. The
    /// executing request keeps its completion until the native operation has
    /// actually returned, even if a close was requested by a UIA callback.
    func invalidate() {
        guard acceptsRequests else { return }
        acceptsRequests = false
        isRejectingPendingRequests = true
        let rejected = pending
        pending.removeAll()
        for request in rejected {
            request.acquisition?.rejectedLocally()
            request.acquisition?.beginActorDelivery(rejected: true)
            request.completion(.failure(.closing))
            request.acquisition?.endActorDelivery()
        }
        isRejectingPendingRequests = false
        notifyDrainedIfNeeded()
    }

    /// A native close acknowledgement can precede the actor task carrying a
    /// render's final results. This actor-only barrier waits for consumption,
    /// including unsent work rejected during invalidation, without blocking N.
    func whenDrained(_ callback: @escaping @MainActor () -> Void) {
        drainCallbacks.append(callback)
        notifyDrainedIfNeeded()
    }

    /// Passive only: observing the barrier never advances native work.
    var isDrained: Bool {
        executing == nil && pending.isEmpty && !isDeliveringCompletion && !isRejectingPendingRequests
    }

    private func notifyDrainedIfNeeded() {
        guard isDrained else { return }
        let callbacks = drainCallbacks
        drainCallbacks.removeAll()
        for callback in callbacks { callback() }
    }

    private func advance() {
        guard acceptsRequests, !isDeliveringCompletion, executing == nil, !pending.isEmpty else { return }
        let request = pending.removeFirst()
        executing = request
        let smokeObservation = self.smokeObservation
        if let tag = request.smokeTag {
            smokeObservation?.record(
                .framePrepared, windowKey: request.surface.key, requestID: request.id,
                attachmentID: attachmentID,
                generation: request.surface.generation, nativeSequence: request.surface.geometry.nativeSequence,
                revision: tag.contentRevision, auxiliary: tag.phase)
        }
        let reply = NativeWindowReply<NativePresentationReceipt> { [self] result in
            // Core can reject the original commandReply without invoking the
            // command's reject method. Observe this actual terminal callback.
            request.acquisition?.receivedReply(result)
            recordNativeOwnedSmokeFrameReply(
                smokeObservation, kind: .frameReplyReceived, requestID: request.id,
                surface: request.surface, tag: request.smokeTag, result: result)
            Task { @MainActor in
                complete(requestID: request.id, result: result)
            }
        }
        let command = NativePresentationCommand(
            windowKey: request.surface.key, attachmentID: attachmentID,
            expectedSurfaceGeneration: request.expectedGeneration, requestID: request.id,
            operation: request.operation, reply: reply, teardownStore: teardownStore, acquisition: request.acquisition
        )
        _ = sink.submit(command)
    }

    private func complete(
        requestID: NativeWindowRequestID,
        result: Result<NativePresentationReceipt, NativeWindowOwnerFailure>
    ) {
        guard let request = executing, request.id == requestID else { return }
        executing = nil
        isDeliveringCompletion = true
        let validated: Result<NativePresentationReceipt, NativeWindowOwnerFailure>
        if case .success(let receipt) = result {
            if receipt.requestID != request.id || receipt.attachmentID != attachmentID
                || receipt.operation != request.operation.kind
            {
                validated = .failure(
                    .execution("Native presentation replied to a different request, operation or attachment."))
            } else if receipt.surface.key != request.surface.key {
                validated = .failure(.staleWindow)
            } else if let expected = request.expectedGeneration, receipt.surface.generation != expected {
                validated = .failure(.staleSurface(expected: expected, actual: receipt.surface.generation))
            } else {
                validated = result
            }
        } else {
            validated = result
        }
        recordNativeOwnedSmokeFrameReply(
            smokeObservation, kind: .frameReplyConsumed, requestID: request.id,
            surface: request.surface, tag: request.smokeTag, result: validated)
        if case .failure = validated {
            request.acquisition?.beginActorDelivery(rejected: true)
        } else {
            request.acquisition?.beginActorDelivery(rejected: false)
        }
        request.completion(validated)
        request.acquisition?.endActorDelivery()
        isDeliveringCompletion = false
        advance()
        notifyDrainedIfNeeded()
    }
}

/// Installs the native UIA front during asynchronous host setup. The factory
/// creates and the context retains the provider on the native owner; only the
/// real installation result crosses back to the actor.
struct NativeHostAttachmentInstallCommand: NativeWindowOwnerCommand {
    let windowKey: NativeWindowKey
    let requestID: NativeWindowRequestID
    let factory: any NativeWindowOwnerAttachmentFactory
    let reply: NativeWindowReply<Void>
    var commandReply: NativeWindowCommandReply { reply.commandReply }

    func execute(in context: any NativeWindowOwnerContext) throws {
        let attachment = try factory.makeAttachment(in: context)
        do {
            try context.install(attachment, for: factory.attachmentID)
        } catch {
            attachment.beginQuiescence()
            let cleanup = attachment.detach()
            if !cleanup.isDetached || !cleanup.failures.isEmpty {
                throw NativeWindowOwnerFailure.execution(
                    "Attachment installation failed: \(error); native cleanup failed: \(cleanup.failures)"
                )
            }
            throw error
        }
        reply.complete(.success(()))
    }

    func reject(_ failure: NativeWindowOwnerFailure) {
        reply.complete(.failure(failure))
    }
}

/// The actor may have advanced while a native render was running. Only the
/// exact returned submission and surface can update its submitted-content
/// memory; a successful Swift return, old generation, or offscreen draw cannot.
struct NativeHostFrameDisposition: Equatable, Sendable {
    let canTrackSubmittedContent: Bool
    let needsRepaint: Bool

    static func hasCurrentSubmission(
        submittedRevision: UInt64?, currentRevision: UInt64,
        attachedSurfaceGeneration: UInt64?, currentSurfaceGeneration: UInt64?,
        isAttached: Bool, needsImmediateRepaint: Bool, hasUnpreparedContent: Bool
    ) -> Bool {
        guard isAttached, !needsImmediateRepaint, !hasUnpreparedContent,
            let submittedRevision, submittedRevision == currentRevision,
            let attachedSurfaceGeneration, let currentSurfaceGeneration
        else { return false }
        return attachedSurfaceGeneration == currentSurfaceGeneration
    }

    init(
        snapshot: NativePresentationSnapshot, preparedSurfaceGeneration: UInt64,
        returnedSurfaceGeneration: UInt64, currentSurfaceGeneration: UInt64?,
        preparedContentRevision: UInt64, currentContentRevision: UInt64
    ) {
        let sameSurface =
            preparedSurfaceGeneration == returnedSurfaceGeneration
            && currentSurfaceGeneration == returnedSurfaceGeneration
        canTrackSubmittedContent = snapshot.lastFrameSubmission?.outcome == .submitted && sameSurface
        needsRepaint =
            snapshot.presentationState.needsImmediateRepaint || !sameSurface
            || preparedContentRevision != currentContentRevision
    }
}

/// Attachment results describe the native buffers that were created. The
/// actor can already have a newer geometry observation when the result arrives;
/// that newer observation owns layout while the old native buffers need resize.
struct NativeHostAttachmentSurfaces: Equatable, Sendable {
    let actorSurface: NativeWindowSurface
    let attachedSurface: NativeWindowSurface
    var requiresNativeResize: Bool { actorSurface.generation != attachedSurface.generation }

    init?(attachedSurface: NativeWindowSurface, currentSurface: NativeWindowSurface?) {
        guard let currentSurface, currentSurface.key == attachedSurface.key else { return nil }
        self.actorSurface = currentSurface
        self.attachedSurface = attachedSurface
    }
}
