import CUIAInterop
import SwiftWindowsCore
import Synchronization

enum UIANativeHRESULT {
    static let succeeded: Int32 = 0
    static let failed = Int32(bitPattern: 0x8000_4005)
    static let unexpected = Int32(bitPattern: 0x8000_FFFF)
    static let elementNotAvailable = Int32(bitPattern: 0x8004_0201)

    static func forOwnerFailure(_ failure: NativeWindowOwnerFailure) -> Int32 {
        switch failure {
        case .unavailable, .closed, .closing, .ownerStopped, .staleWindow:
            return elementNotAvailable
        default:
            return failed
        }
    }
}

/// The diagnostics contain values only. Keeping them separate from the context
/// owner prevents context -> callback/wake box -> context ownership cycles.
final class UIANativeDiagnostics: Sendable {
    private struct State {
        var listening: Bool?
        var disconnectResult: Int32?
        var failure: NativeWindowOwnerFailure?
        var drainWakeFailure: NativeWindowOwnerFailure?
    }

    private let state = Mutex(State())

    var listening: Bool? { state.withLock { $0.listening } }
    var disconnectResult: Int32? { state.withLock { $0.disconnectResult } }
    var failure: NativeWindowOwnerFailure? { state.withLock { $0.failure } }
    var drainWakeFailure: NativeWindowOwnerFailure? { state.withLock { $0.drainWakeFailure } }

    func recordListening(_ value: Bool) {
        state.withLock { $0.listening = value }
    }

    func recordDisconnect(_ result: Int32) {
        state.withLock { $0.disconnectResult = result }
    }

    func recordFailure(_ failure: NativeWindowOwnerFailure) {
        state.withLock { $0.failure = failure }
    }

    func recordDrainWakeFailure(_ failure: NativeWindowOwnerFailure) {
        state.withLock {
            $0.drainWakeFailure = failure
            $0.failure = failure
        }
    }
}

/// A checked Sendable owner for the revocation capability, not for an HWND or a
/// COM provider. Pointer access is protected by one short lock. Temporary C
/// references are retained under that lock and released after unlocking.
final class UIANativeProviderSession: Sendable {
    private struct State {
        var context: OpaquePointer?
        var installed = false
        var revoked = false
    }

    let windowKey: NativeWindowKey
    let attachmentID = NativeWindowAttachmentID()
    let diagnostics = UIANativeDiagnostics()
    private let commandSink: any NativeWindowCommandSink
    private let state = Mutex(State())

    init(windowKey: NativeWindowKey, commandSink: any NativeWindowCommandSink) {
        self.windowKey = windowKey
        self.commandSink = commandSink
    }

    deinit {
        let context = state.withLock { stored in
            let context = stored.context
            stored.context = nil
            stored.revoked = true
            return context
        }
        if let context {
            SWU_UIARevokeProviderContext(context)
            SWU_UIAReleaseProviderContext(context)
        }
    }

    var isAvailable: Bool {
        state.withLock { stored in
            guard !stored.revoked, let context = stored.context else { return false }
            return SWU_UIAProviderContextIsAvailable(context) != 0
        }
    }

    var clientListeningObservation: Bool? { diagnostics.listening }
    var disconnectResult: Int32? { diagnostics.disconnectResult }

    func recordFailure(_ failure: NativeWindowOwnerFailure) {
        diagnostics.recordFailure(failure)
    }

    /// The attachment already owns the factory's initial reference. The
    /// session takes a separate reference for local, nonblocking revocation.
    func bind(_ context: OpaquePointer) throws {
        SWU_UIARetainProviderContext(context)
        let failure: NativeWindowOwnerFailure? = state.withLock { stored in
            if stored.revoked { return .closing }
            if stored.installed { return .duplicateAttachment(attachmentID) }
            stored.installed = true
            stored.context = context
            return nil
        }
        if let failure {
            SWU_UIAReleaseProviderContext(context)
            throw failure
        }
    }

    func releaseContext(_ expected: OpaquePointer) {
        let context = state.withLock { stored in
            guard stored.context == expected else { return Optional<OpaquePointer>.none }
            let context = stored.context
            stored.context = nil
            stored.revoked = true
            return context
        }
        if let context { SWU_UIAReleaseProviderContext(context) }
    }

    func revoke() {
        let context = state.withLock { stored in
            stored.revoked = true
            guard let context = stored.context else { return Optional<OpaquePointer>.none }
            SWU_UIARetainProviderContext(context)
            return context
        }
        if let context {
            SWU_UIARevokeProviderContext(context)
            SWU_UIAReleaseProviderContext(context)
        }
    }

    func submit(_ event: UIAProviderNativeEvent) {
        guard isAvailable else { return }
        let reply = NativeWindowReply<Void> { [diagnostics] result in
            if case .failure(let failure) = result { diagnostics.recordFailure(failure) }
        }
        commandSink.submit(
            UIANativeEventCommand(
                windowKey: windowKey, attachmentID: attachmentID, event: event, reply: reply))
    }

    func submitDisconnect() {
        let reply = NativeWindowReply<Int32?> { [diagnostics] result in
            switch result {
            case .success(let result):
                if let result { diagnostics.recordDisconnect(result) }
            case .failure(let failure):
                diagnostics.recordFailure(failure)
            }
        }
        commandSink.submit(
            UIANativeDisconnectCommand(
                windowKey: windowKey, attachmentID: attachmentID, reply: reply))
    }
}

/// The C method and the Swift request each own a reference to the same heap
/// token. Its final release, after both actor work and C marshalling, drains the
/// full native call. No raw token escapes the lock protecting this owner.
final class UIANativeCallLease: Sendable {
    private let call: Mutex<OpaquePointer?>

    init(retaining call: OpaquePointer) {
        SWU_UIARetainCall(call)
        self.call = Mutex(call)
    }

    deinit {
        let released = call.withLock { stored in
            let result = stored
            stored = nil
            return result
        }
        if let released { SWU_UIAReleaseCall(released) }
    }

    var isAvailable: Bool {
        call.withLock { stored in
            guard let stored else { return false }
            return SWU_UIACallStatus(stored) >= 0
        }
    }

    func fail(_ hresult: Int32) {
        call.withLock { stored in
            if let stored { SWU_UIACallFail(stored, hresult) }
        }
    }

    func revokeOwner() {
        let retained = call.withLock { stored in
            guard let stored else { return Optional<OpaquePointer>.none }
            SWU_UIARetainCall(stored)
            return stored
        }
        if let retained {
            // Revocation can signal the native drain wake. Neither that signal
            // nor a final release runs while the Swift token lock is held.
            SWU_UIACallRevokeOwner(retained)
            SWU_UIAReleaseCall(retained)
        }
    }

    func callbackContext() -> UIANativeCallbackContext? {
        call.withLock { stored in
            guard let stored, let context = SWU_UIACallOwnerContext(stored) else { return nil }
            return Unmanaged<UIANativeCallbackContext>.fromOpaque(context).takeUnretainedValue()
        }
    }
}

/// C owns this box, but never the actor bridge. Its implicit nonisolated final
/// destruction releases only weak storage and Sendable native observation
/// values, and is safe on the last releasing COM thread.
@MainActor
final class UIANativeCallbackContext {
    nonisolated let windowKey: NativeWindowKey
    nonisolated let snapshotSource: any NativeWindowSnapshotSource
    nonisolated let diagnostics: UIANativeDiagnostics
    weak var bridge: UIAProviderBridge?

    init(
        windowKey: NativeWindowKey, snapshotSource: any NativeWindowSnapshotSource,
        diagnostics: UIANativeDiagnostics
    ) {
        self.windowKey = windowKey
        self.snapshotSource = snapshotSource
        self.diagnostics = diagnostics
    }

    func receive(_ envelope: UIAProviderRequestEnvelope, lease: UIANativeCallLease) -> UIAProviderReply? {
        guard lease.isAvailable else { return nil }
        guard let bridge else {
            // Weak zeroing can precede the isolated bridge deinitializer.
            // Constant provider methods must also become unavailable now.
            lease.revokeOwner()
            lease.fail(UIANativeHRESULT.elementNotAvailable)
            return nil
        }
        defer { withExtendedLifetime(bridge) {} }
        return bridge.receiveNativeRequest(envelope, lease: lease)
    }
}

func releaseUIANativeCallbackContext(_ context: UnsafeMutableRawPointer?) {
    guard let context else { return }
    Unmanaged<UIANativeCallbackContext>.fromOpaque(context).release()
}

/// This bridge waits only for the main actor. In particular, an external COM
/// callback never asks N for fresher geometry while N may be inside that COM
/// operation. Input/event ordering is restored by the actor's beforeRequest
/// hook through the copied geometry's nativeSequence.
enum UIANativeRequestDispatch {
    static func perform(_ call: OpaquePointer?, _ request: UIAProviderRequest) -> UIAProviderReply? {
        guard let call else { return nil }
        let lease = UIANativeCallLease(retaining: call)
        guard lease.isAvailable else { return nil }
        guard let context = lease.callbackContext() else {
            lease.revokeOwner()
            lease.fail(UIANativeHRESULT.elementNotAvailable)
            return nil
        }
        let surface: NativeWindowSurface
        switch context.snapshotSource.snapshot() {
        case .success(let value):
            guard value.key == context.windowKey else {
                context.diagnostics.recordFailure(.staleWindow)
                lease.fail(UIANativeHRESULT.elementNotAvailable)
                return nil
            }
            surface = value
        case .failure(let failure):
            context.diagnostics.recordFailure(failure)
            lease.fail(UIANativeHRESULT.forOwnerFailure(failure))
            return nil
        }
        let envelope = UIAProviderRequestEnvelope(surface: surface, request: request)
        return UIAProviderBridge.onMain {
            context.receive(envelope, lease: lease)
        }
    }

    static func unexpectedReply(_ call: OpaquePointer?) {
        guard let call else { return }
        // Fail preserves a prior terminal status rather than overwriting it.
        SWU_UIACallFail(call, UIANativeHRESULT.unexpected)
    }
}

/// The wake owns only the native owner's nonblocking signal and value
/// diagnostics. It neither closes an HWND nor calls an actor from C teardown.
final class UIANativeDrainWake: Sendable {
    private let wake: @Sendable () -> Result<Void, NativeWindowOwnerFailure>
    private let diagnostics: UIANativeDiagnostics

    init(
        wake: @escaping @Sendable () -> Result<Void, NativeWindowOwnerFailure>,
        diagnostics: UIANativeDiagnostics
    ) {
        self.wake = wake
        self.diagnostics = diagnostics
    }

    func signal() -> Int32 {
        switch wake() {
        case .success:
            return UIANativeHRESULT.succeeded
        case .failure(let failure):
            diagnostics.recordDrainWakeFailure(failure)
            return UIANativeHRESULT.forOwnerFailure(failure)
        }
    }
}

func signalUIANativeDrainWake(_ context: UnsafeMutableRawPointer?) -> Int32 {
    guard let context else { return UIANativeHRESULT.failed }
    return Unmanaged<UIANativeDrainWake>.fromOpaque(context).takeUnretainedValue().signal()
}

func releaseUIANativeDrainWake(_ context: UnsafeMutableRawPointer?) {
    guard let context else { return }
    Unmanaged<UIANativeDrainWake>.fromOpaque(context).release()
}
