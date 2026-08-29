import Foundation
import SwiftWindowsCore

/// A retained consumer must distinguish revocation from both cancellation and
/// failure. It still retires its operation when the native request has unwound.
package enum DialogRequestOutcome<Selection> {
    case selected(Selection)
    case cancelled
    case failed(Error)
    case revoked
}

/// One window lifetime's actor-owned dialog completions. Commands carry only
/// copied values and a checked reply; native code never calls the retained
/// completion, reads a binding, or accesses this session's mutable state.
@MainActor
package final class NativeDialogSession {
    private struct PendingRequest {
        let id: NativeWindowRequestID
        let request: NativeDialogRequest
        let isCurrent: @MainActor () -> Bool
        let completion: @MainActor (NativeDialogResponse) -> Void
    }

    package let windowKey: NativeWindowKey
    private let commandSink: any NativeWindowCommandSink
    private let executor: NativeDialogExecutor
    private var queuedRequests: [PendingRequest] = []
    private var activeRequest: PendingRequest?
    private var isDrainingRequests = false
    private var isDeliveringCompletion = false
    package private(set) var isValid = true
    package private(set) var lastFailure: NativeDialogFailure?

    package var hasPendingRequests: Bool {
        activeRequest != nil || !queuedRequests.isEmpty || isDrainingRequests || isDeliveringCompletion
    }

    package init(
        windowKey: NativeWindowKey, commandSink: any NativeWindowCommandSink,
        executor: NativeDialogExecutor = .live
    ) {
        self.windowKey = windowKey
        self.commandSink = commandSink
        self.executor = executor
    }

    /// Revoke result consumption before host teardown. Submitted work remains
    /// pinned until its actual native terminal reply. Never-submitted payloads
    /// retire on a fresh actor turn, after synchronous host capability teardown.
    package func invalidate() {
        guard isValid else { return }
        isValid = false
        Task { @MainActor in self.retireQueuedRequests() }
    }

    package func request(
        _ request: NativeDialogRequest,
        isCurrent: @escaping @MainActor () -> Bool = { true },
        completion: @escaping @MainActor (NativeDialogResponse) -> Void
    ) {
        guard isValid else {
            completion(.revoked)
            return
        }
        let requestID = NativeWindowRequestID()
        queuedRequests.append(
            PendingRequest(id: requestID, request: request, isCurrent: isCurrent, completion: completion))
        drainPendingRequests()
    }

    /// Native commands never wait for the actor to consume an earlier result.
    /// Instead the actor submits one operation and keeps this gate through its
    /// complete callback, reset and capture cleanup before admitting the next.
    private func drainPendingRequests() {
        guard isValid, activeRequest == nil, !isDrainingRequests, !isDeliveringCompletion else { return }
        isDrainingRequests = true
        defer { isDrainingRequests = false }
        while isValid, activeRequest == nil, !queuedRequests.isEmpty {
            var next: PendingRequest? = queuedRequests.removeFirst()
            let canSubmit = next?.isCurrent() == true
            guard isValid else {
                // A predicate can begin host teardown. Put this unsent record
                // back so the fresh actor retirement owns all queued cleanup.
                if let next { queuedRequests.insert(next, at: 0) }
                next = nil
                return
            }
            if !canSubmit {
                next?.completion(.revoked)
                // Release actor-only predicates and completion captures while
                // reentrant requests still see the drain gate held.
                next = nil
                continue
            }
            activeRequest = next
            let requestID = next!.id
            let request = next!.request
            next = nil
            submit(request, requestID: requestID)
        }
    }

    private func retireQueuedRequests() {
        guard !isValid, !isDrainingRequests, !isDeliveringCompletion else { return }
        isDrainingRequests = true
        defer { isDrainingRequests = false }
        while !queuedRequests.isEmpty {
            var retired: PendingRequest? = queuedRequests.removeFirst()
            retired?.completion(.revoked)
            retired = nil
        }
    }

    private func submit(_ request: NativeDialogRequest, requestID: NativeWindowRequestID) {
        let reply = NativeWindowReply<NativeDialogResponse> { [self] result in
            // The isolated router is Sendable; no retained payload is read on
            // the native callback thread. Its final release occurs after this
            // actor task has delivered or retired the matching completion.
            Task { @MainActor in
                self.complete(requestID, result: result)
            }
        }
        let command = NativeDialogCommand(
            windowKey: windowKey, requestID: requestID, request: request,
            executor: executor, reply: reply)
        if case .rejected(let failure) = commandSink.submit(command) {
            // The sink normally rejects the command itself. Checked completion
            // also makes a synchronous admission failure terminal without a
            // second callback when both paths report the same rejection.
            command.reject(failure)
        }
    }

    private func complete(
        _ requestID: NativeWindowRequestID,
        result: Result<NativeDialogResponse, NativeWindowOwnerFailure>
    ) {
        guard activeRequest?.id == requestID else { return }
        isDeliveringCompletion = true
        var completed = activeRequest
        activeRequest = nil
        let response: NativeDialogResponse
        if isValid {
            switch result {
            case .success(let value): response = value
            case .failure(let error): response = .failed(.transport(error))
            }
        } else {
            response = .revoked
        }
        if case .failed(let failure) = response { lastFailure = failure }
        completed?.completion(response)
        completed = nil
        isDeliveringCompletion = false
        drainPendingRequests()
    }
}
