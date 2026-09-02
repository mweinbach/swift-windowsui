import CUIAInterop
import SwiftWindowsCore

/// Immutable native-call functions; tests can replace them with Sendable,
/// headless probes. Unlike the legacy seam these never capture actor state.
struct UIANativeCalls: Sendable {
    var clientsAreListening: @Sendable () -> Bool
    var returnProvider: @Sendable (UnsafeMutableRawPointer?, UInt, Int, UnsafeMutableRawPointer) -> Int
    var disconnectProvider: @Sendable (UnsafeMutableRawPointer) -> Int32
    var raiseFocusChanged: @Sendable (UnsafeMutableRawPointer) -> Void
    var raiseStructureChanged: @Sendable (UnsafeMutableRawPointer) -> Void
    var raiseLiveRegionChanged: @Sendable (UnsafeMutableRawPointer) -> Void

    static var live: UIANativeCalls {
        UIANativeCalls(
            clientsAreListening: { SWU_UIAClientsAreListening() != 0 },
            returnProvider: { SWU_UIAReturnRawElementProvider($0, $1, $2, $3) },
            disconnectProvider: { SWU_UIATryDisconnectProvider($0) },
            raiseFocusChanged: { SWU_UIARaiseAutomationFocusChanged($0) },
            raiseStructureChanged: { SWU_UIARaiseStructureChanged($0) },
            raiseLiveRegionChanged: { SWU_UIARaiseLiveRegionChanged($0) })
    }
}

struct UIANativeProviderFactory: NativeWindowOwnerAttachmentFactory {
    let session: UIANativeProviderSession
    let callbackContext: UIANativeCallbackContext
    let nativeCalls: UIANativeCalls
    let supportsLogicalItems: Bool

    init(
        session: UIANativeProviderSession, callbackContext: UIANativeCallbackContext,
        nativeCalls: UIANativeCalls, supportsLogicalItems: Bool = false
    ) {
        self.session = session
        self.callbackContext = callbackContext
        self.nativeCalls = nativeCalls
        self.supportsLogicalItems = supportsLogicalItems
    }

    var attachmentID: NativeWindowAttachmentID { session.attachmentID }

    func makeAttachment(in context: any NativeWindowOwnerContext) throws -> any NativeWindowOwnerAttachment {
        guard context.surface.key == session.windowKey else { throw NativeWindowOwnerFailure.staleWindow }
        let retainedCallback = Unmanaged.passRetained(callbackContext).toOpaque()
        let drainWake = UIANativeDrainWake(wake: context.wake, diagnostics: session.diagnostics)
        let retainedWake = Unmanaged.passRetained(drainWake).toOpaque()
        var callbacks = UIANativeProviderCallbacks.make(
            context: retainedCallback, supportsLogicalItems: supportsLogicalItems)
        var wake = SWUUIADrainWake()
        wake.context = retainedWake
        wake.signal = signalUIANativeDrainWake
        wake.releaseContext = releaseUIANativeDrainWake
        guard
            let nativeContext = SWU_UIACreateProviderContextWithCallsAndInvokeResult(
                &callbacks, releaseUIANativeCallbackContext, &wake,
                { call, element in
                    UIANativeProviderCallbacks.invokeDefaultActionResult(call, element)
                })
        else {
            // The factory adopts both boxes only on success.
            releaseUIANativeCallbackContext(retainedCallback)
            releaseUIANativeDrainWake(retainedWake)
            throw NativeWindowOwnerFailure.execution("Unable to create UIA provider context")
        }
        do {
            try session.bind(nativeContext)
        } catch {
            SWU_UIARevokeProviderContext(nativeContext)
            SWU_UIAReleaseProviderContext(nativeContext)
            throw error
        }
        return UIANativeProviderAttachment(
            session: session, context: nativeContext,
            hwnd: context.surface.descriptor.windowHandle?.rawPointer, nativeCalls: nativeCalls)
    }
}

/// N owns this object and every provider pointer stored in it. Provider COM
/// methods may execute elsewhere, but own their separate context/call leases.
final class UIANativeProviderAttachment: Win32NativeAccessibilityAttachment {
    private let session: UIANativeProviderSession
    private let nativeCalls: UIANativeCalls
    private var nativeContext: OpaquePointer?
    private var hwnd: UnsafeMutableRawPointer?
    private var rootProvider: UnsafeMutableRawPointer?
    private var attemptedDisconnect = false
    private var detachFailures: [NativeWindowOwnerFailure] = []

    init(
        session: UIANativeProviderSession, context: OpaquePointer,
        hwnd: UnsafeMutableRawPointer?, nativeCalls: UIANativeCalls
    ) {
        self.session = session
        nativeContext = context
        self.hwnd = hwnd
        self.nativeCalls = nativeCalls
    }

    deinit {
        // Normal native teardown calls detach. A failed installation still
        // revokes and balances local references without outbound COM in deinit.
        session.revoke()
        if let rootProvider { SWU_UIAReleaseProvider(rootProvider) }
        if let nativeContext {
            session.releaseContext(nativeContext)
            SWU_UIAReleaseProviderContext(nativeContext)
        }
    }

    private var isAvailable: Bool {
        guard let nativeContext else { return false }
        return session.isAvailable && SWU_UIAProviderContextIsAvailable(nativeContext) != 0
    }

    func beginQuiescence() {
        session.revoke()
    }

    var isQuiescent: Bool {
        guard let nativeContext else { return true }
        return SWU_UIAProviderContextIsQuiescent(nativeContext) != 0
    }

    func detach() -> NativeWindowAttachmentDetachResult {
        beginQuiescence()
        guard isQuiescent else {
            return NativeWindowAttachmentDetachResult(isDetached: false)
        }
        guard let nativeContext else {
            return NativeWindowAttachmentDetachResult(isDetached: true, failures: detachFailures)
        }
        if let result = disconnect(), result < 0 {
            detachFailures.append(.native(operation: "UiaDisconnectProvider", code: Int64(result)))
        }
        let wakeResult = SWU_UIAProviderContextDrainWakeResult(nativeContext)
        if wakeResult < 0, let failure = session.diagnostics.drainWakeFailure {
            detachFailures.append(failure)
        }
        if let rootProvider {
            self.rootProvider = nil
            SWU_UIAReleaseProvider(rootProvider)
        }
        self.nativeContext = nil
        hwnd = nil
        session.releaseContext(nativeContext)
        SWU_UIAReleaseProviderContext(nativeContext)
        return NativeWindowAttachmentDetachResult(isDetached: true, failures: detachFailures)
    }

    func handleGetObject(
        wParam: UInt, lParam: Int, in context: any NativeWindowOwnerContext
    ) -> Int? {
        guard context.surface.key == session.windowKey, isAvailable,
            Int32(truncatingIfNeeded: lParam) == -25
        else { return nil }
        hwnd = context.surface.descriptor.windowHandle?.rawPointer
        let listening = nativeCalls.clientsAreListening()
        session.diagnostics.recordListening(listening)
        guard listening, isAvailable, let nativeContext else { return nil }
        if rootProvider == nil {
            rootProvider = makeRootProvider(context: nativeContext)
        }
        guard isAvailable, let rootProvider else { return nil }
        SWU_UIAAddRefProvider(rootProvider)
        defer { SWU_UIAReleaseProvider(rootProvider) }
        let result = nativeCalls.returnProvider(hwnd, wParam, lParam, rootProvider)
        return isAvailable ? result : nil
    }

    /// Local revocation always precedes the one real native disconnect attempt.
    /// Failure is retained verbatim and never reopens the family or retries.
    func disconnect() -> Int32? {
        session.revoke()
        guard !attemptedDisconnect else { return session.disconnectResult }
        attemptedDisconnect = true
        guard let rootProvider else { return nil }
        SWU_UIAAddRefProvider(rootProvider)
        defer { SWU_UIAReleaseProvider(rootProvider) }
        let result = nativeCalls.disconnectProvider(rootProvider)
        session.diagnostics.recordDisconnect(result)
        return result
    }

    /// The caller already ran the retained callback. Native events are not a
    /// condition of its Bool/Void result and must not be awaited by that actor.
    func emit(_ event: UIAProviderNativeEvent) throws {
        guard isAvailable else { throw NativeWindowOwnerFailure.closing }
        let listening = nativeCalls.clientsAreListening()
        session.diagnostics.recordListening(listening)
        guard listening else { return }
        guard isAvailable, let nativeContext else { throw NativeWindowOwnerFailure.closing }
        switch event {
        case .structureChanged:
            guard let rootProvider else { return }
            SWU_UIAAddRefProvider(rootProvider)
            defer { SWU_UIAReleaseProvider(rootProvider) }
            nativeCalls.raiseStructureChanged(rootProvider)
        case .focusChanged(let element):
            guard let provider = SWU_UIACreateElementProviderWithContext(nativeContext, hwnd, element) else {
                throw NativeWindowOwnerFailure.execution("Unable to create UIA focus provider")
            }
            defer { SWU_UIAReleaseProvider(provider) }
            guard isAvailable else { throw NativeWindowOwnerFailure.closing }
            nativeCalls.raiseFocusChanged(provider)
        case .liveRegionChanged(let element):
            guard let provider = SWU_UIACreateElementProviderWithContext(nativeContext, hwnd, element) else {
                throw NativeWindowOwnerFailure.execution("Unable to create UIA live-region provider")
            }
            defer { SWU_UIAReleaseProvider(provider) }
            guard isAvailable else { throw NativeWindowOwnerFailure.closing }
            nativeCalls.raiseLiveRegionChanged(provider)
        }
    }

    /// Headless peer: uses the production context and full-call callback table.
    /// It performs no HWND query, client probe, or outbound UI Automation call.
    func retainedRootProviderForTesting() -> UnsafeMutableRawPointer? {
        guard isAvailable, let nativeContext else { return nil }
        if rootProvider == nil {
            rootProvider = makeRootProvider(context: nativeContext)
        }
        guard isAvailable, let rootProvider else { return nil }
        SWU_UIAAddRefProvider(rootProvider)
        return rootProvider
    }

    /// A native root is permanently identified by this attachment's original
    /// HWND. Headless fixtures have no HWND and retain the generic root path.
    private func makeRootProvider(context: OpaquePointer) -> UnsafeMutableRawPointer? {
        if let hwnd {
            return SWU_UIACreateOwnedHWNDRootProviderWithContext(context, hwnd)
        }
        return SWU_UIACreateRootProviderWithContext(context, nil)
    }
}

struct UIANativeEventCommand: NativeWindowOwnerCommand {
    let windowKey: NativeWindowKey
    let attachmentID: NativeWindowAttachmentID
    let event: UIAProviderNativeEvent
    let reply: NativeWindowReply<Void>
    let requestID = NativeWindowRequestID()
    var commandReply: NativeWindowCommandReply { reply.commandReply }

    func execute(in context: any NativeWindowOwnerContext) throws {
        guard context.surface.key == windowKey else { throw NativeWindowOwnerFailure.staleWindow }
        guard let attachment = context.attachment(for: attachmentID) as? UIANativeProviderAttachment else {
            throw NativeWindowOwnerFailure.missingAttachment(attachmentID)
        }
        try attachment.emit(event)
        // Void means the native event path returned (or no client/root needed
        // it), not that UI Automation supplied a successful HRESULT.
        reply.complete(.success(()))
    }

    func reject(_ failure: NativeWindowOwnerFailure) {
        reply.complete(.failure(failure))
    }
}

struct UIANativeDisconnectCommand: NativeWindowOwnerCommand {
    let windowKey: NativeWindowKey
    let attachmentID: NativeWindowAttachmentID
    let reply: NativeWindowReply<Int32?>
    let requestID = NativeWindowRequestID()
    var commandReply: NativeWindowCommandReply { reply.commandReply }

    func execute(in context: any NativeWindowOwnerContext) throws {
        guard context.surface.key == windowKey else { throw NativeWindowOwnerFailure.staleWindow }
        guard let attachment = context.attachment(for: attachmentID) as? UIANativeProviderAttachment else {
            throw NativeWindowOwnerFailure.missingAttachment(attachmentID)
        }
        reply.complete(.success(attachment.disconnect()))
    }

    func reject(_ failure: NativeWindowOwnerFailure) {
        reply.complete(.failure(failure))
    }
}
