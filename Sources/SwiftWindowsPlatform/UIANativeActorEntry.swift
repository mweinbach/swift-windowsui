import CUIAInterop
import Dispatch
import Synchronization

/// Records a synchronous actor-to-C call chain, not an inferred executor or a
/// provider-family grant. Only a real queued actor receive or an explicit
/// already-actor interop caller may enter. There is no async/public overload.
enum UIANativeActorEntry {
    static var isActive: Bool { SWU_UIAHasActorEntry() != 0 }

    @MainActor
    static func withScope<Result>(_ body: @MainActor () -> Result) -> Result {
        withoutActuallyEscaping(body) { operation in
            var result: Result?
            let invocation = UIANativeActorInvocation { result = .some(operation()) }
            withExtendedLifetime(invocation) {
                SWU_UIAWithActorEntry(Unmanaged.passUnretained(invocation).toOpaque(), invokeUIANativeActorBody)
            }
            guard let result else { preconditionFailure("The synchronous actor entry did not return a value") }
            return result
        }
    }
}

@MainActor
private final class UIANativeActorInvocation {
    let body: @MainActor () -> Void

    init(body: @escaping @MainActor () -> Void) { self.body = body }
}

private func invokeUIANativeActorBody(_ context: UnsafeMutableRawPointer?) {
    guard let context else { preconditionFailure("A synchronous actor entry requires its invocation") }
    let invocation = Unmanaged<UIANativeActorInvocation>.fromOpaque(context).takeUnretainedValue()
    // The explicit actor wrapper is already running on this same synchronous
    // stack. This assertion checks that promise; it never mints the witness.
    MainActor.assumeIsolated { invocation.body() }
}

/// One foreign C caller owns the wait. A nil reply is a completed failure,
/// distinct from a pending receive. No lock is held while waking or waiting.
final class UIANativeActorReplyCell: Sendable {
    private enum State: Sendable {
        case pending
        case completed(UIAProviderReply?)
    }

    private let state = Mutex(State.pending)
    private let completed = DispatchSemaphore(value: 0)

    func complete(_ reply: UIAProviderReply?) {
        let claimed = state.withLock { stored in
            guard case .pending = stored else { return false }
            stored = .completed(reply)
            return true
        }
        if claimed { completed.signal() }
    }

    func wait() -> UIAProviderReply? {
        completed.wait()
        return state.withLock { stored in
            guard case .completed(let reply) = stored else {
                preconditionFailure("The actor reply signaled before completion")
            }
            return reply
        }
    }
}
