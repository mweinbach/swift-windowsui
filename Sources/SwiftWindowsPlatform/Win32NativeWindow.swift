import CUIAInterop
import Foundation
import SwiftWindowsCore
import Synchronization
import WinSDK

private let win32NativeAnimationMessage = UINT(WM_APP + 0x122)

/// A queued native timer post contains a unique timer identity, never a Swift
/// pointer. Recreating a window or changing timer modes cannot turn an old
/// queued tick into input for the new lifetime even if Windows reuses HWND.
private final class Win32NativeAnimationGate: Sendable {
    let handleValue: UInt
    let lowWord: UInt
    let highWord: Int
    let windowKey: NativeWindowKey
    let observation: Win32NativeSmokeObservation?
    let outstanding = Atomic<Bool>(false)

    init(handleValue: UInt, windowKey: NativeWindowKey, observation: Win32NativeSmokeObservation?) {
        self.handleValue = handleValue
        self.windowKey = windowKey
        self.observation = observation
        let bytes = Foundation.UUID().uuid
        let low = [bytes.0, bytes.1, bytes.2, bytes.3, bytes.4, bytes.5, bytes.6, bytes.7]
        let high = [bytes.8, bytes.9, bytes.10, bytes.11, bytes.12, bytes.13, bytes.14, bytes.15]
        lowWord = low.enumerated().reduce(UInt(0)) { $0 | (UInt($1.element) << ($1.offset * 8)) }
        highWord = Int(bitPattern: high.enumerated().reduce(UInt(0)) { $0 | (UInt($1.element) << ($1.offset * 8)) })
    }

    func consume() { outstanding.store(false, ordering: .releasing) }
}

private func win32NativeAnimationCallback(_ raw: UnsafeMutableRawPointer?, _: UInt8) {
    guard let raw else { return }
    let gate = Unmanaged<Win32NativeAnimationGate>.fromOpaque(raw).takeUnretainedValue()
    gate.observation?.record(.nativeAnimationCallback, windowKey: gate.windowKey)
    let (claimed, _) = gate.outstanding.compareExchange(
        expected: false, desired: true, ordering: .acquiringAndReleasing)
    guard claimed else { return }
    guard let handle = HWND(bitPattern: gate.handleValue) else {
        gate.observation?.record(.nativeAnimationPost, windowKey: gate.windowKey)
        gate.consume()
        return
    }
    let posted = PostMessageW(handle, win32NativeAnimationMessage, WPARAM(gate.lowWord), LPARAM(gate.highWord))
    let error: Int64? = posted ? nil : Int64(GetLastError())
    gate.observation?.record(
        .nativeAnimationPost, windowKey: gate.windowKey, value: error, flags: posted ? 1 : 0)
    if !posted { gate.consume() }
}

/// Only the native owner calls this specialization. The attachment obtains
/// its HWND from the current context; no MainActor bridge crosses this API.
package protocol Win32NativeAccessibilityAttachment: NativeWindowOwnerAttachment {
    func handleGetObject(wParam: UInt, lParam: Int, in context: any NativeWindowOwnerContext) -> Int?
}

/// Constructed in the CreateThread entry point. Neither this object nor a
/// Win32NativeWindowState is Sendable: their only pointers live in HWND native
/// storage and are dereferenced by that same thread's window procedures.
final class Win32NativeLoop {
    let mailbox: Win32NativePumpMailbox
    private var controlWindow: HWND?
    private var controlWasDestroyed = false
    private var windows: [NativeWindowKey: Win32NativeWindowState] = [:]
    private var dispatchDepth = 0
    private var executingNativeWork = false
    private var needsWakeAfterUnwind = false
    private var stopping = false
    private var pendingFatalFailure: NativeWindowOwnerFailure?
    private var isWindowClassRegistered = false
    private var observedTurnSequence: UInt64 = 0

    init(mailbox: Win32NativePumpMailbox) {
        self.mailbox = mailbox
    }

    func run() -> DWORD {
        var ownsCOMInitialization = false
        defer {
            // Both S_OK and S_FALSE own a matching uninitialization. Every
            // returning path below has finished HWND/attachment cleanup;
            // process-fatal parking intentionally never reaches this defer.
            if ownsCOMInitialization { CoUninitialize() }
        }
        do {
            let apartmentResult = CoInitializeEx(nil, DWORD(COINIT_APARTMENTTHREADED.rawValue))
            mailbox.smokeObservation?.record(.nativeCOMInitialized, value: Int64(apartmentResult))
            guard apartmentResult >= 0 else {
                throw NativeWindowOwnerFailure.native(operation: "CoInitializeEx(STA)", code: Int64(apartmentResult))
            }
            ownsCOMInitialization = true
            Win32NativeWindowUtilities.enableHighDpiSupport()
            try registerClass(name: Self.controlClassName, procedure: Self.controlProcedure, style: 0)
            guard let instance = GetModuleHandleW(nil) else { throw nativeFailure("GetModuleHandleW") }
            let created = Self.controlClassName.withNativeWideChars { name in
                CreateWindowExW(
                    0, name, name, 0, 0, 0, 0, 0, HWND(bitPattern: -3), nil, instance,
                    Unmanaged.passUnretained(self).toOpaque())
            }
            guard let created else { throw nativeFailure("CreateWindowExW(control)") }
            controlWindow = created
            mailbox.smokeObservation?.record(.nativeOwnerReady)
            mailbox.didStart(controlHandle: UInt(bitPattern: created))

            // The Swift BOOL overlay cannot represent GetMessage's -1. Use
            // the documented public entry point with its real signed return
            // type, so an error is never interpreted as an ordinary message.
            guard let user32 = GetModuleHandleW(Array("user32.dll".utf16) + [0]),
                let address = "GetMessageW".withCString({ GetProcAddress(user32, $0) })
            else { throw nativeFailure("GetProcAddress(GetMessageW)") }
            typealias ReadMessage = @convention(c) (UnsafeMutablePointer<MSG>?, HWND?, UINT, UINT) -> Int32
            let readMessage = unsafeBitCast(address, to: ReadMessage.self)
            var message = MSG()
            while true {
                let result = readMessage(&message, nil, 0, 0)
                if result == -1 {
                    let failure = nativeFailure("GetMessageW")
                    if windows.isEmpty { throw failure }
                    parkForFatalExit(failure)
                }
                if result == 0 {
                    guard windows.isEmpty else {
                        let failure = NativeWindowOwnerFailure.execution(
                            "WM_QUIT arrived while native windows remain alive")
                        parkForFatalExit(failure)
                    }
                    let exitCode = DWORD(truncatingIfNeeded: message.wParam)
                    if let controlWindow {
                        guard DestroyWindow(controlWindow) else {
                            parkForFatalExit(nativeFailure("DestroyWindow(control)"))
                        }
                        guard controlWasDestroyed else {
                            parkForFatalExit(.execution("Control HWND destruction was not observed"))
                        }
                    }
                    return exitCode
                }
                // Keep only the original receiver category across dispatch, which may destroy its target.
                let smokeTarget: UInt64? =
                    mailbox.smokeObservation == nil ? nil : smokeMessageTarget(for: message.hwnd).rawValue
                mailbox.smokeObservation?.record(
                    .nativeMessageDispatched, value: Int64(message.message),
                    auxiliary: smokeTarget, flags: message.hwnd == controlWindow ? 1 : 2)
                TranslateMessage(&message)
                DispatchMessageW(&message)
                mailbox.smokeObservation?.record(
                    .nativeDispatchReturned, value: Int64(message.message),
                    auxiliary: smokeTarget, flags: message.hwnd == controlWindow ? 1 : 2)
                finishDestructionAfterDispatch()
                if let pendingFatalFailure { parkForFatalExit(pendingFatalFailure) }
            }
        } catch {
            let failure = error as? NativeWindowOwnerFailure ?? .execution(String(describing: error))
            mailbox.didFailToStart(failure)
            if let controlWindow {
                guard DestroyWindow(controlWindow) else {
                    parkForFatalExit(nativeFailure("DestroyWindow(control startup rollback)"))
                }
                guard controlWasDestroyed else {
                    parkForFatalExit(.execution("Control HWND startup rollback did not observe non-client destruction"))
                }
            }
            self.controlWindow = nil
            return DWORD(ERROR_INVALID_FUNCTION)
        }
    }

    private func smokeMessageTarget(for target: HWND?) -> Win32NativeSmokeMessageTarget {
        let matchesControl = target != nil && target == controlWindow
        var matchesRegistered = false
        if let target, !matchesControl {
            for window in windows.values {
                if window.matchesRecordedMessageTarget(target) {
                    matchesRegistered = true
                    break
                }
            }
        }
        return .classify(
            hasWindowHandle: target != nil, matchesControlWindow: matchesControl,
            matchesRegisteredWindow: matchesRegistered)
    }

    private func parkForFatalExit(_ failure: NativeWindowOwnerFailure) -> Never {
        // Notify all actor facades and owned replies before parking. Their
        // explicit fatal path calls ExitProcess(1); this is not normal window
        // teardown and produces no fabricated destroyed/joined receipt.
        mailbox.smokeObservation?.record(.nativeOwnerFailure, value: win32NativeSmokeFailureValue(failure))
        for window in Array(windows.values) { window.failOwner(failure) }
        mailbox.failOwner(failure)
        Sleep(INFINITE)
        // No retry or polling loop. If an injected/failed wait returns, keep
        // the same explicit process-fatal policy instead of unwinding an
        // owner whose HWND backpointers and native resources are still live.
        ExitProcess(1)
        fatalError("ExitProcess returned from native owner fatal shutdown")
    }

    /// Input exhaustion revokes the entire owner explicitly. The failure path
    /// never waits for actor catch-up or for the current native/modal operation.
    /// Queued ordinary work and uncommitted lifecycle waiters fail. An
    /// executing ordinary operation or committed destruction keeps its real
    /// reply if it returns. Process-fatal exit may terminate a still-running
    /// native call and must never be described as graceful completion.
    func failInputIngress(_ failure: NativeWindowOwnerFailure) {
        guard pendingFatalFailure == nil else { return }
        pendingFatalFailure = failure
        mailbox.smokeObservation?.record(.nativeOwnerFailure, value: win32NativeSmokeFailureValue(failure))
        for window in Array(windows.values) { window.failOwner(failure) }
        mailbox.failOwner(failure)
    }

    func withDispatch<Result>(_ body: () throws -> Result) rethrows -> Result {
        dispatchDepth += 1
        defer {
            dispatchDepth -= 1
            if dispatchDepth == 0, needsWakeAfterUnwind, pendingFatalFailure == nil {
                needsWakeAfterUnwind = false
                _ = mailbox.signal()
            }
        }
        return try body()
    }

    private func consumeWake() {
        mailbox.smokeObservation?.record(.nativeWakeReceived)
        mailbox.consumeWake()
        guard pendingFatalFailure == nil else { return }
        guard dispatchDepth == 1, !executingNativeWork else {
            mailbox.smokeObservation?.record(
                .nativeWakeDeferred, value: Int64(dispatchDepth), flags: executingNativeWork ? 1 : 0)
            needsWakeAfterUnwind = true
            return
        }
        executingNativeWork = true
        mailbox.observeNativeTurn(active: true)
        var handledCommands = 0
        let observedTurn: UInt64?
        if let observation = mailbox.smokeObservation {
            if observedTurnSequence < UInt64.max { observedTurnSequence += 1 }
            observedTurn = observedTurnSequence
            let depth = mailbox.smokeQueueSnapshot.queuedWork
            observation.record(.nativeTurnBegan, queueDepth: UInt64(depth), turnID: observedTurn)
        } else {
            observedTurn = nil
        }
        defer {
            executingNativeWork = false
            mailbox.observeNativeTurn(active: false)
            if let observation = mailbox.smokeObservation {
                let depth = mailbox.smokeQueueSnapshot.queuedWork
                observation.record(
                    .nativeTurnEnded, queueDepth: UInt64(depth), turnID: observedTurn,
                    value: Int64(handledCommands), flags: needsWakeAfterUnwind ? 1 : 0)
            }
        }

        for window in Array(windows.values) { window.progressDestruction() }
        while !stopping, pendingFatalFailure == nil, handledCommands < 16, let work = mailbox.takeNext() {
            handledCommands += 1
            mailbox.observeNativeWork(inFlight: true)
            defer { mailbox.observeNativeWork(inFlight: false) }
            switch work {
            case .create(let creation):
                createWindow(creation)
            case .command(let command):
                guard let window = windows[command.windowKey] else {
                    command.reject(.staleWindow)
                    continue
                }
                window.execute(command)
            case .close(let request):
                guard let window = windows[request.key] else {
                    request.complete(.failure(.staleWindow), beforeCompletion: { self.mailbox.retireClose(request) })
                    continue
                }
                window.beginDestruction(request)
            case .stop:
                guard windows.isEmpty else {
                    mailbox.rejectStop(.execution("Cannot stop the native owner before its windows are destroyed"))
                    continue
                }
                stopping = true
                mailbox.willStop()
                PostQuitMessage(0)
            }
            if pendingFatalFailure == nil {
                for window in Array(windows.values) { window.progressDestruction() }
            }
        }
        if !stopping, pendingFatalFailure == nil, mailbox.hasQueuedWork { needsWakeAfterUnwind = true }
    }

    private func createWindow(_ creation: Win32NativeWindowCreation) {
        guard windows[creation.key] == nil else {
            creation.reply.complete(.failure(.staleWindow))
            return
        }
        let window = Win32NativeWindowState(owner: self, creation: creation)
        windows[creation.key] = window
        guard mailbox.registerOwnedWindow(creation.key) else {
            windows.removeValue(forKey: creation.key)
            creation.reply.complete(.failure(.staleWindow))
            return
        }
        do {
            if !isWindowClassRegistered {
                try registerClass(
                    name: Win32NativeWindowState.className, procedure: Win32NativeWindowState.windowProcedure,
                    style: UINT(CS_HREDRAW | CS_VREDRAW | CS_DBLCLKS))
                isWindowClassRegistered = true
            }
            try window.create()
            creation.reply.complete(.success(window.surface))
        } catch {
            let failure = error as? NativeWindowOwnerFailure ?? .execution(String(describing: error))
            creation.snapshotSource.revoke(failure)
            creation.reply.complete(.failure(failure))
            if window.creationFailureCleanup == .retainOwner { parkForFatalExit(failure) }
            windows.removeValue(forKey: creation.key)
            mailbox.retireOwnedWindow(creation.key)
        }
    }

    private func finishDestructionAfterDispatch() {
        guard dispatchDepth == 0, !executingNativeWork else { return }
        for (key, window) in Array(windows) where window.canFinishDestruction {
            if window.finishDestructionAfterDispatch() {
                windows.removeValue(forKey: key)
                mailbox.retireOwnedWindow(key)
            }
        }
    }

    private func registerClass(name: String, procedure: WNDPROC, style: UINT) throws {
        guard let instance = GetModuleHandleW(nil) else { throw nativeFailure("GetModuleHandleW") }
        try name.withNativeWideChars { wideName in
            var windowClass = WNDCLASSEXW()
            windowClass.cbSize = UINT(MemoryLayout<WNDCLASSEXW>.size)
            windowClass.style = style
            windowClass.lpfnWndProc = procedure
            windowClass.hInstance = instance
            windowClass.hCursor = LoadCursorW(nil, UnsafePointer<WCHAR>(bitPattern: 32512))
            windowClass.hbrBackground = unsafeBitCast(GetStockObject(Int32(BLACK_BRUSH)), to: HBRUSH?.self)
            windowClass.lpszClassName = wideName
            if RegisterClassExW(&windowClass) == 0 {
                let code = GetLastError()
                if code != DWORD(ERROR_CLASS_ALREADY_EXISTS) {
                    throw NativeWindowOwnerFailure.native(operation: "RegisterClassExW", code: Int64(code))
                }
            }
        }
    }

    private static let controlClassName = "SwiftWindowsUI.NativeOwnerControl"
    private static let controlProcedure: WNDPROC = { hwnd, message, wParam, lParam in
        if message == UINT(WM_NCCREATE) {
            let creation = UnsafeMutableRawPointer(bitPattern: Int(lParam))?.assumingMemoryBound(to: CREATESTRUCTW.self)
            if let raw = creation?.pointee.lpCreateParams {
                SetWindowLongPtrW(hwnd, GWLP_USERDATA, LONG_PTR(Int(bitPattern: raw)))
            }
        }
        let value = GetWindowLongPtrW(hwnd, GWLP_USERDATA)
        guard let raw = UnsafeMutableRawPointer(bitPattern: Int(value)) else {
            return DefWindowProcW(hwnd, message, wParam, lParam)
        }
        let owner = Unmanaged<Win32NativeLoop>.fromOpaque(raw).takeUnretainedValue()
        return withExtendedLifetime(owner) {
            owner.withDispatch {
                if message == win32NativeWakeMessage {
                    owner.consumeWake()
                    return 0
                }
                if message == UINT(WM_NCDESTROY) { SetWindowLongPtrW(hwnd, GWLP_USERDATA, 0) }
                if message == UINT(WM_NCCREATE) { owner.controlWindow = hwnd }
                if message == UINT(WM_NCDESTROY) {
                    owner.controlWindow = nil
                    owner.controlWasDestroyed = true
                }
                return DefWindowProcW(hwnd, message, wParam, lParam)
            }
        }
    }
}

/// All mutable native state is confined to the owner thread. The actor's
/// Win32Window facade has a copied observation, not a reference to this object.
final class Win32NativeWindowState: NativeWindowOwnerContext {
    private unowned let owner: Win32NativeLoop
    private let creation: Win32NativeWindowCreation
    private var handle: HWND?
    private var hasBoundNativeHandle = false
    private var ownsNativeReference = false
    private var isCreated = false
    private var acceptsInteractiveInput = false
    private var closeRequestedBeforeActivation = false
    private var observedDestroy = false
    private var observedNonClientDestroy = false
    private var destroyCallReturned = false
    private var destructionResult: Win32CloseNativeResult?
    private var hasBegunQuiescence = false
    private var hasDeliveredDestroyed = false
    private var cleanupRequested = false
    private var pendingDestruction: Win32NativeDestructionRequest?
    private var attachments: [NativeWindowAttachmentID: any NativeWindowOwnerAttachment] = [:]
    private var attachmentOrder: [NativeWindowAttachmentID] = []
    private var currentSurface: NativeWindowSurface?
    private var lastGeometryFailure: NativeWindowOwnerFailure?
    private var geometryRevision: UInt64 = 0
    private var eventSequence: UInt64 = 0
    private var surfaceGeneration: UInt64 = 0
    private var appearance: SystemAppearanceSnapshot = .unavailable
    private var displayName = "no-display"
    private var refreshRate: UInt32 = 60
    private var monitorIdentity: UInt = 0
    private var lastMonitorSample: Double = -.greatestFiniteMagnitude
    private var minimized = false
    private var visible = false
    private var active = true
    private var isInSizeMove = false
    private var isInMenuLoop = false
    private var nativeModalDepth = 0
    private var isTrackingMouseLeave = false
    private var capturedButtons: UInt8 = 0
    private var isReleasingCapture = false
    private var textDecoder = Win32UTF16TextInputDecoder()
    private var isComposing = false
    private var isFullscreen = false
    private var preFullscreenStyle: DWORD = 0
    private var preFullscreenRect = RECT()
    private var isCloseEnabled = true
    private var caret: Rect?
    private var caretGeometryRevision: UInt64?
    private let imeProvider: any IMECompositionContextProvider = Win32IMECompositionContextProvider()
    private var animationInterval: UInt32?
    private var installedAnimationInterval: UInt32?
    private var prefersHighResolution = false
    private var highResolutionUnavailable = false
    private var highResolutionTimer: HANDLE?
    private var highResolutionGate: Win32NativeAnimationGate?
    private var holdsTimerResolution = false
    private var hasCloseWatchdog = false
    private var smokeAcceptedOrdinals: UInt64 = 0
    private var smokeActualResolutionOwned = false
    private var smokeTimerStateUncertain = false
    private var smokeLastTimerFlags: UInt32?
    private var smokeLastTimerInterval: UInt32?

    init(owner: Win32NativeLoop, creation: Win32NativeWindowCreation) {
        self.owner = owner
        self.creation = creation
    }

    var surface: NativeWindowSurface {
        guard let currentSurface else { preconditionFailure("Native context requires a created surface") }
        return currentSurface
    }

    var hasLiveNativeResources: Bool {
        handle != nil || ownsNativeReference || highResolutionTimer != nil || holdsTimerResolution
            || !attachments.isEmpty
    }

    /// The loop reads this only after create() and every synchronous native
    /// callback from its rollback have returned. A successful API return alone
    /// cannot retire a handle whose non-client destruction was not observed.
    var creationFailureCleanup: Win32NativeCreationCleanup {
        .afterFailure(
            didBindHandle: hasBoundNativeHandle,
            didObserveNonClientDestruction: observedNonClientDestroy,
            hasLiveNativeResources: hasLiveNativeResources)
    }

    var snapshotSource: any NativeWindowSnapshotSource { creation.snapshotSource }

    var wake: @Sendable () -> Result<Void, NativeWindowOwnerFailure> {
        let mailbox = owner.mailbox
        return { mailbox.signal() }
    }

    func attachment(for id: NativeWindowAttachmentID) -> (any NativeWindowOwnerAttachment)? { attachments[id] }

    func install(_ attachment: any NativeWindowOwnerAttachment, for id: NativeWindowAttachmentID) throws {
        guard !observedDestroy, !hasBegunQuiescence else { throw NativeWindowOwnerFailure.closing }
        guard attachments[id] == nil else { throw NativeWindowOwnerFailure.duplicateAttachment(id) }
        attachments[id] = attachment
        attachmentOrder.append(id)
    }

    func removeAttachment(for id: NativeWindowAttachmentID) -> (any NativeWindowOwnerAttachment)? {
        attachmentOrder.removeAll { $0 == id }
        return attachments.removeValue(forKey: id)
    }

    func withNativeModal<Result>(_ body: () throws -> Result) rethrows -> Result {
        nativeModalDepth += 1
        refreshAnimationTimer()
        sampleGeometry()
        emit(.geometryChanged)
        defer {
            nativeModalDepth -= 1
            refreshAnimationTimer()
            sampleGeometry()
            emit(.geometryChanged)
        }
        return try body()
    }

    func create() throws {
        guard let instance = GetModuleHandleW(nil) else { throw nativeFailure("GetModuleHandleW") }
        let style = Win32NativeWindowUtilities.windowStyle(
            titleBarVisibility: creation.titleBarVisibility, configuration: creation.configuration)
        let size = Win32NativeWindowUtilities.creationGeometry(
            logicalSize: creation.logicalClientSize, style: style, dpi: Win32NativeWindowUtilities.creationDpi())
        let raw = Unmanaged.passRetained(self).toOpaque()
        ownsNativeReference = true
        let created = Self.className.withNativeWideChars { name in
            creation.title.withNativeWideChars { title in
                CreateWindowExW(
                    0, name, title, style, CW_USEDEFAULT, CW_USEDEFAULT, size.width, size.height,
                    nil, nil, instance, raw)
            }
        }
        guard let created else {
            let failure = nativeFailure("CreateWindowExW")
            if consumeNativeReference() { Unmanaged.passUnretained(self).release() }
            throw failure
        }
        guard !observedNonClientDestroy else {
            throw NativeWindowOwnerFailure.closed
        }
        handle = created
        DragAcceptFiles(created, true)
        RegisterTouchWindow(created, 0)
        applyConfiguration()
        appearance = Win32SystemAppearanceProvider().sampleSystemAppearance()
        sampleGeometry(forceMonitor: true)
        guard lastGeometryFailure == nil, currentSurface != nil else {
            let failure = lastGeometryFailure ?? .execution("Native creation has no valid surface geometry")
            if !DestroyWindow(created) {
                let rollbackFailure = nativeFailure("DestroyWindow(failed surface creation)")
                throw NativeWindowOwnerFailure.execution(
                    "Surface creation failed: \(failure); rollback failed: \(rollbackFailure)")
            }
            throw failure
        }
        isCreated = true
        observeTimerState(force: true)
        owner.mailbox.smokeObservation?.record(
            .nativeWindowCreated, windowKey: creation.key, generation: surface.generation,
            nativeSequence: surface.geometry.nativeSequence)
        emit(.created)
    }

    func execute(_ command: any NativeWindowOwnerCommand) {
        guard command.windowKey == creation.key else {
            command.reject(.staleWindow)
            return
        }
        guard isCreated, !observedDestroy, !observedNonClientDestroy else {
            command.reject(.closed)
            return
        }
        guard !hasBegunQuiescence else {
            command.reject(.closing)
            return
        }
        sampleGeometry()
        guard !observedDestroy, !observedNonClientDestroy else {
            command.reject(.closed)
            return
        }
        if let lastGeometryFailure {
            command.reject(lastGeometryFailure)
            return
        }
        if let expected = command.expectedSurfaceGeneration, expected != surface.generation {
            command.reject(.staleSurface(expected: expected, actual: surface.generation))
            return
        }
        do {
            try command.execute(in: self)
        } catch {
            command.reject(error as? NativeWindowOwnerFailure ?? .execution(String(describing: error)))
        }
    }

    func beginDestruction(_ request: Win32NativeDestructionRequest) {
        guard request.key == creation.key, let handle else {
            request.complete(.failure(.staleWindow), beforeCompletion: { self.owner.mailbox.retireClose(request) })
            return
        }
        guard pendingDestruction == nil else {
            request.complete(.failure(.closing), beforeCompletion: { self.owner.mailbox.retireClose(request) })
            return
        }
        if let reservation = request.reservation, reservation.expectedHandle != UInt(bitPattern: handle) {
            request.complete(.failure(.staleWindow), beforeCompletion: { self.owner.mailbox.retireClose(request) })
            return
        }
        guard owner.mailbox.registerClose(request) else {
            request.complete(.failure(.closing), beforeCompletion: { self.owner.mailbox.retireClose(request) })
            return
        }
        pendingDestruction = request
        hasBegunQuiescence = true
        acceptsInteractiveInput = false
        destroyCallReturned = false
        destructionResult = nil
        creation.snapshotSource.revoke(.closing)
        let timerFailure = stopAnimationTimer()
        if hasCloseWatchdog {
            let removed = KillTimer(handle, Self.closeWatchdogID)
            hasCloseWatchdog = false
            observeTimerAPI(.killCloseWatchdog, succeeded: removed ? true : false, code: nil)
            observeTimerState()
        }
        for id in attachmentOrder { attachments[id]?.beginQuiescence() }
        if let timerFailure {
            request.complete(.failure(timerFailure), beforeCompletion: { self.owner.mailbox.retireClose(request) })
            return
        }
        progressDestruction()
    }

    func progressDestruction() {
        guard let request = pendingDestruction, !destroyCallReturned else { return }
        guard !request.isTerminal else {
            owner.mailbox.retireClose(request)
            pendingDestruction = nil
            return
        }
        guard nativeModalDepth == 0, !isInSizeMove, !isInMenuLoop else { return }
        guard attachmentOrder.allSatisfy({ attachments[$0]?.isQuiescent ?? true }) else {
            owner.mailbox.smokeObservation?.record(
                .nativeCloseAwaitingAttachments, windowKey: creation.key,
                requestID: request.reservation?.requestID,
                generation: currentSurface?.generation, nativeSequence: currentSurface?.geometry.nativeSequence,
                auxiliary: UInt64(attachmentOrder.count))
            return
        }
        guard let handle, !observedNonClientDestroy else {
            request.complete(.failure(.closed), beforeCompletion: { self.owner.mailbox.retireClose(request) })
            return
        }
        // An attachment may call COM and reenter window dispatch while
        // detaching. The owner keeps command execution excluded throughout.
        for id in Array(attachmentOrder.reversed()) {
            guard let attachment = attachments[id] else { continue }
            let result = attachment.detach()
            owner.mailbox.smokeObservation?.record(
                .nativeAttachmentDetached, windowKey: creation.key, requestID: request.reservation?.requestID,
                attachmentID: id, generation: currentSurface?.generation,
                nativeSequence: currentSurface?.geometry.nativeSequence,
                value: Int64(result.failures.count), flags: result.isDetached ? 1 : 0)
            guard result.isDetached else {
                let failure = result.failures.first ?? .execution("Native attachment did not finish detaching")
                request.complete(.failure(failure), beforeCompletion: { self.owner.mailbox.retireClose(request) })
                reportFailure(failure)
                return
            }
            _ = removeAttachment(for: id)
            if !result.failures.isEmpty {
                let failure = result.failures[0]
                request.complete(.failure(failure), beforeCompletion: { self.owner.mailbox.retireClose(request) })
                reportFailure(failure)
                return
            }
        }
        guard self.handle == handle, !observedNonClientDestroy else {
            request.complete(.failure(.staleWindow), beforeCompletion: { self.owner.mailbox.retireClose(request) })
            return
        }
        guard request.reservation == nil || isCloseEnabled else {
            request.complete(
                .failure(.execution("Native close affordance changed after actor reservation")),
                beforeCompletion: { self.owner.mailbox.retireClose(request) })
            return
        }
        guard request.claimDestruction() else { return }
        // There is no actor callout, queue drain, or native hook between this
        // exact lifetime check and DestroyWindow.
        let destroyed = DestroyWindow(handle)
        let error = destroyed ? 0 : GetLastError()
        destroyCallReturned = true
        destructionResult = destroyed ? .succeeded : .failed(error)
        if !destroyed, !observedNonClientDestroy {
            reportFailure(.native(operation: "DestroyWindow", code: Int64(error)))
        }
    }

    var canFinishDestruction: Bool {
        !hasDeliveredDestroyed && (destroyCallReturned || (observedNonClientDestroy && pendingDestruction == nil))
    }

    func finishDestructionAfterDispatch() -> Bool {
        guard canFinishDestruction else { return false }
        guard highResolutionTimer == nil, !holdsTimerResolution else { return false }
        owner.mailbox.smokeObservation?.record(
            .nativeCloseDispatchUnwound, windowKey: creation.key,
            requestID: pendingDestruction?.reservation?.requestID,
            generation: currentSurface?.generation, nativeSequence: currentSurface?.geometry.nativeSequence,
            flags: observedNonClientDestroy ? 1 : 0)
        if observedNonClientDestroy, pendingDestruction == nil, !attachments.isEmpty {
            guard attachmentOrder.allSatisfy({ attachments[$0]?.isQuiescent ?? true }) else { return false }
            for id in Array(attachmentOrder.reversed()) {
                guard let attachment = attachments[id] else { continue }
                let detached = attachment.detach()
                owner.mailbox.smokeObservation?.record(
                    .nativeAttachmentDetached, windowKey: creation.key,
                    attachmentID: id, generation: currentSurface?.generation,
                    nativeSequence: currentSurface?.geometry.nativeSequence,
                    value: Int64(detached.failures.count), flags: (detached.isDetached ? 1 : 0) | 2)
                guard detached.isDetached else {
                    reportFailure(
                        detached.failures.first ?? .execution("Unexpected destruction left a native attachment alive"))
                    return false
                }
                _ = removeAttachment(for: id)
                for failure in detached.failures { reportFailure(failure) }
            }
        }
        if observedNonClientDestroy {
            hasDeliveredDestroyed = true
            creation.snapshotSource.revoke(.closed)
            emit(.destroyed, publish: false)
        }
        if let request = pendingDestruction {
            let actual = Win32NativeCloseDestruction(
                nativeResult: destructionResult ?? .succeeded,
                didObserveNonClientDestruction: observedNonClientDestroy, didUnwindNativeDispatch: true)
            let nativeCode: Int64
            let nativeSucceeded: Bool
            switch actual.nativeResult {
            case .succeeded:
                nativeCode = 0
                nativeSucceeded = true
            case .failed(let code):
                nativeCode = Int64(code)
                nativeSucceeded = false
            }
            let receiptFlags: UInt32 =
                (actual.didObserveNonClientDestruction ? 1 : 0)
                | (actual.didUnwindNativeDispatch ? 2 : 0)
                | (nativeSucceeded ? 4 : 0)
            owner.mailbox.smokeObservation?.record(
                .nativeCloseReplyReady, windowKey: creation.key, requestID: request.reservation?.requestID,
                generation: currentSurface?.generation, nativeSequence: currentSurface?.geometry.nativeSequence,
                value: nativeCode, flags: receiptFlags)
            let delivered = request.complete(
                .success(actual),
                beforeCompletion: { self.owner.mailbox.retireClose(request) })
            owner.mailbox.smokeObservation?.record(
                .nativeCloseReplyReturned, windowKey: creation.key, requestID: request.reservation?.requestID,
                generation: currentSurface?.generation, nativeSequence: currentSurface?.geometry.nativeSequence,
                value: nativeCode, flags: receiptFlags | (delivered ? 8 : 0))
            owner.mailbox.retireClose(request)
            pendingDestruction = nil
        }
        destroyCallReturned = false
        return observedNonClientDestroy
    }

    func reportFailure(_ failure: NativeWindowOwnerFailure) {
        creation.snapshotSource.revoke(failure)
        creation.ingress.fail(failure, windowKey: creation.key)
    }

    func failOwner(_ failure: NativeWindowOwnerFailure) {
        hasBegunQuiescence = true
        acceptsInteractiveInput = false
        creation.snapshotSource.revoke(failure)
        reportFailure(failure)
    }

    private func sampleGeometry(forceMonitor: Bool = false) {
        guard let handle, !observedNonClientDestroy else { return }
        var rect = RECT()
        guard GetClientRect(handle, &rect) else {
            failGeometry(nativeFailure("GetClientRect"))
            return
        }
        var origin = POINT()
        guard ClientToScreen(handle, &origin) else {
            failGeometry(nativeFailure("ClientToScreen"))
            return
        }
        let dpi = GetDpiForWindow(handle)
        let scale = dpi == 0 ? 1 : Double(dpi) / 96
        let effectiveScale = scale.isFinite && scale > 0 ? max(1, scale) : 1
        let pixelSize = IntSize(width: rect.right - rect.left, height: rect.bottom - rect.top)
        let monitor = UInt(bitPattern: MonitorFromWindow(handle, DWORD(MONITOR_DEFAULTTONEAREST)))
        let now = PlatformClock.now()
        if forceMonitor || (monitor != monitorIdentity && now - lastMonitorSample >= 0.25) {
            let sampled = Win32NativeWindowUtilities.monitorSnapshot(hwnd: handle)
            refreshRate = sampled.refreshRate
            displayName = sampled.displayIdentity
            monitorIdentity = sampled.monitorID
            lastMonitorSample = now
        }
        if currentSurface?.descriptor.pixelSize != pixelSize || currentSurface?.descriptor.scaleFactor != effectiveScale
        {
            guard surfaceGeneration < UInt64.max else {
                failGeometry(.execution("Native surface generation exhausted"))
                return
            }
            surfaceGeneration += 1
        }
        guard geometryRevision < UInt64.max else {
            failGeometry(.execution("Native geometry revision exhausted"))
            return
        }
        geometryRevision += 1
        let geometry = NativeWindowGeometry(
            revision: geometryRevision, nativeSequence: eventSequence, clientSize: pixelSize,
            clientScreenOrigin: Point(x: Double(origin.x), y: Double(origin.y)), scaleFactor: scale,
            effectiveScaleFactor: effectiveScale, monitorRefreshRate: refreshRate,
            isMinimized: minimized, isVisible: visible, isActive: active,
            nativeModalDepth: nativeModalDepth + (isInSizeMove ? 1 : 0) + (isInMenuLoop ? 1 : 0))
        guard let opaque = NativeWindowHandle(rawPointer: UnsafeMutableRawPointer(handle)) else {
            failGeometry(.staleWindow)
            return
        }
        currentSurface = NativeWindowSurface(
            key: creation.key, generation: surfaceGeneration,
            descriptor: SurfaceDescriptor(windowHandle: opaque, pixelSize: pixelSize, scaleFactor: effectiveScale),
            geometry: geometry)
        lastGeometryFailure = nil
        if isCreated, !hasBegunQuiescence { creation.snapshotSource.publish(surface) }
    }

    private func failGeometry(_ failure: NativeWindowOwnerFailure) {
        lastGeometryFailure = failure
        creation.snapshotSource.revoke(failure)
        reportFailure(failure)
    }

    @discardableResult
    private func emit(
        _ event: Win32NativeWindowEvent, publish: Bool = true
    ) -> Result<NativeWindowSurface, NativeWindowOwnerFailure> {
        guard isCreated, let currentSurface else { return .failure(.unavailable) }
        guard eventSequence < UInt64.max else {
            let failure = NativeWindowOwnerFailure.execution("Native input sequence exhausted")
            owner.failInputIngress(failure)
            return .failure(failure)
        }
        if lastGeometryFailure != nil {
            // Keep failure/destruction observable, but never label a new input
            // or native query with geometry whose sampling failed.
            switch event {
            case .ownerFailure, .destroyed: break
            default: return .failure(lastGeometryFailure ?? .unavailable)
            }
        }
        let candidateSequence = eventSequence + 1
        var geometry = currentSurface.geometry
        geometry.nativeSequence = candidateSequence
        let surface = NativeWindowSurface(
            key: creation.key, generation: currentSurface.generation, descriptor: currentSurface.descriptor,
            geometry: geometry)
        let observation = Win32NativeWindowObservation(
            surface: surface, systemAppearance: appearance, displayIdentity: displayName,
            isInLiveResize: isInSizeMove, isFullscreen: isFullscreen)
        switch creation.ingress.enqueue(Win32NativeWindowEventRecord(observation: observation, event: event)) {
        case .failure(let failure):
            owner.failInputIngress(failure)
            return .failure(failure)
        case .success: break
        }
        // Admission precedes every producer-side sequence/snapshot commit.
        // A full queue cannot make an unreceived input look published.
        eventSequence = candidateSequence
        self.currentSurface = surface
        if publish, !hasBegunQuiescence, !observedNonClientDestroy { creation.snapshotSource.publish(surface) }
        return .success(surface)
    }

    fileprivate func validateSmokeProbe(observation: Win32NativeSmokeObservation, ordinal: UInt32) throws {
        guard owner.mailbox.smokeObservation === observation, creation.ingress.smokeObservation === observation else {
            throw NativeWindowOwnerFailure.execution("Native smoke traffic requires its exact observed owner instance")
        }
        guard pendingDestruction == nil, !hasBegunQuiescence, !observedDestroy, !observedNonClientDestroy else {
            throw NativeWindowOwnerFailure.closing
        }
        guard ordinal < 64 else {
            throw NativeWindowOwnerFailure.execution("Native smoke ordinal exceeds the fixed 64-command workload")
        }
        let bit = UInt64(1) << ordinal
        guard smokeAcceptedOrdinals & bit == 0 else {
            throw NativeWindowOwnerFailure.execution("Native smoke ordinal was already admitted for this window")
        }
    }

    fileprivate func emitSmokeProbe(
        observation: Win32NativeSmokeObservation, requestID: NativeWindowRequestID, ordinal: UInt32
    ) throws -> NativeWindowSurface {
        try validateSmokeProbe(observation: observation, ordinal: ordinal)
        let accepted = try emit(.smokeProbe(Win32NativeSmokeProbe(requestID: requestID, ordinal: ordinal))).get()
        smokeAcceptedOrdinals |= UInt64(1) << ordinal
        observation.record(
            .smokeProbeEmitted, windowKey: accepted.key, requestID: requestID,
            generation: accepted.generation, nativeSequence: accepted.geometry.nativeSequence,
            value: Int64(ordinal), auxiliary: smokeAcceptedOrdinals)
        return accepted
    }

    private func consumeNativeReference() -> Bool {
        guard ownsNativeReference else { return false }
        ownsNativeReference = false
        return true
    }

    private func handleMessage(hwnd: HWND?, message: UINT, wParam: WPARAM, lParam: LPARAM) -> LRESULT {
        if !acceptsInteractiveInput {
            switch message {
            case UINT(WM_TOUCH):
                if let touch = HTOUCHINPUT(bitPattern: Int(lParam)) { CloseTouchInputHandle(touch) }
                return 0
            case UINT(WM_DROPFILES):
                _ = Win32NativeWindowUtilities.dropPayload(wParam: wParam)
                return 0
            case UINT(WM_MOUSEMOVE), UINT(WM_MOUSELEAVE), UINT(WM_LBUTTONDOWN), UINT(WM_LBUTTONUP),
                UINT(WM_LBUTTONDBLCLK), UINT(WM_RBUTTONDOWN), UINT(WM_RBUTTONUP), UINT(WM_MBUTTONDOWN),
                UINT(WM_MBUTTONUP), UINT(WM_MOUSEWHEEL), UINT(WM_MOUSEHWHEEL), UINT(WM_KEYDOWN), UINT(WM_CHAR),
                UINT(WM_IME_STARTCOMPOSITION), UINT(WM_IME_COMPOSITION), UINT(WM_IME_ENDCOMPOSITION), UINT(WM_IME_CHAR):
                return 0
            default: break
            }
        }
        switch message {
        case UINT(WM_ERASEBKGND):
            return 1
        case UINT(WM_GETOBJECT):
            guard isCreated, !hasBegunQuiescence, !observedDestroy, handle == hwnd else { return 0 }
            sampleGeometry()
            guard lastGeometryFailure == nil else { return 0 }
            for id in Array(attachmentOrder) {
                guard let provider = attachments[id] as? any Win32NativeAccessibilityAttachment else { continue }
                let result = provider.handleGetObject(wParam: UInt(wParam), lParam: Int(lParam), in: self)
                guard !hasBegunQuiescence, !observedDestroy, handle == hwnd else { return 0 }
                if let result { return LRESULT(result) }
            }
            let result = DefWindowProcW(hwnd, message, wParam, lParam)
            return !hasBegunQuiescence && !observedDestroy && handle == hwnd ? result : 0
        case UINT(WM_SIZE):
            minimized = Int(truncatingIfNeeded: wParam) == Int(SIZE_MINIMIZED)
            sampleGeometry()
            emit(minimized ? .geometryChanged : .resized)
            return 0
        case UINT(WM_DPICHANGED):
            if let pointer = UnsafeMutableRawPointer(bitPattern: Int(lParam))?.assumingMemoryBound(to: RECT.self) {
                let rect = pointer.pointee
                SetWindowPos(
                    hwnd, nil, rect.left, rect.top, rect.right - rect.left, rect.bottom - rect.top,
                    UINT(SWP_NOACTIVATE | SWP_NOZORDER))
            }
            sampleGeometry(forceMonitor: true)
            emit(.resized)
            return 0
        case UINT(WM_GETMINMAXINFO):
            let result = DefWindowProcW(hwnd, message, wParam, lParam)
            if let info = UnsafeMutableRawPointer(bitPattern: Int(lParam))?.assumingMemoryBound(to: MINMAXINFO.self) {
                let style = Win32NativeWindowUtilities.windowStyle(
                    titleBarVisibility: creation.titleBarVisibility, configuration: creation.configuration)
                let rawDpi = hwnd.map { GetDpiForWindow($0) } ?? 0
                let dpi = rawDpi > 0 ? rawDpi : Win32NativeWindowUtilities.creationDpi()
                let pinned = creation.configuration.resizability == .fixedSize ? creation.logicalClientSize : nil
                if let minimum = creation.configuration.minimumClientSize ?? pinned {
                    let size = Win32NativeWindowUtilities.creationGeometry(logicalSize: minimum, style: style, dpi: dpi)
                    info.pointee.ptMinTrackSize = POINT(x: size.width, y: size.height)
                }
                if let maximum = creation.configuration.maximumClientSize ?? pinned {
                    let size = Win32NativeWindowUtilities.creationGeometry(logicalSize: maximum, style: style, dpi: dpi)
                    info.pointee.ptMaxTrackSize = POINT(x: size.width, y: size.height)
                }
            }
            return result
        case UINT(WM_PAINT):
            var paint = PAINTSTRUCT()
            BeginPaint(hwnd, &paint)
            EndPaint(hwnd, &paint)
            // Painting is an actor scene request. No actor renderer executes
            // in the native callback, including nested size/move paints.
            emit(.needsDisplay)
            return 0
        case UINT(WM_TIMER):
            if UINT_PTR(wParam) == Self.animationTimerID, highResolutionTimer == nil, installedAnimationInterval != nil
            {
                owner.mailbox.smokeObservation?.record(
                    .nativeAnimationMessage, windowKey: creation.key, auxiliary: 0)
                emit(.animationFrame(PlatformClock.now()))
                return 0
            }
            if UINT_PTR(wParam) == Self.closeWatchdogID, hasCloseWatchdog {
                if let handle {
                    let removed = KillTimer(handle, Self.closeWatchdogID)
                    observeTimerAPI(.killCloseWatchdog, succeeded: removed ? true : false, code: nil)
                }
                hasCloseWatchdog = false
                observeTimerState()
                requestActorClose()
                return 0
            }
            return DefWindowProcW(hwnd, message, wParam, lParam)
        case win32NativeAnimationMessage:
            guard let gate = highResolutionGate, UInt(wParam) == gate.lowWord, Int(lParam) == gate.highWord else {
                return 0
            }
            gate.consume()
            owner.mailbox.smokeObservation?.record(
                .nativeAnimationMessage, windowKey: creation.key, auxiliary: 1)
            emit(.animationFrame(PlatformClock.now()))
            return 0
        case UINT(WM_MOUSEMOVE):
            trackMouseLeave()
            sampleGeometry()
            emit(.pointer(.moved, Win32NativeWindowUtilities.point(from: lParam)))
            return 0
        case UINT(WM_MOUSELEAVE):
            isTrackingMouseLeave = false
            emit(.pointerExited)
            return 0
        case UINT(WM_LBUTTONDOWN):
            SetFocus(hwnd)
            beginCapture(.left, hwnd: hwnd)
            sampleGeometry()
            emit(.pointer(.leftDown, Win32NativeWindowUtilities.point(from: lParam)))
            return 0
        case UINT(WM_LBUTTONUP):
            endCapture(.left)
            sampleGeometry()
            emit(.pointer(.leftUp, Win32NativeWindowUtilities.point(from: lParam)))
            return 0
        case UINT(WM_LBUTTONDBLCLK):
            SetFocus(hwnd)
            beginCapture(.left, hwnd: hwnd)
            sampleGeometry()
            let point = Win32NativeWindowUtilities.point(from: lParam)
            emit(.pointer(.leftDown, point))
            emit(.doubleClick(MouseEvent(button: .left, position: point, clickCount: 2)))
            return 0
        case UINT(WM_RBUTTONDOWN):
            beginCapture(.right, hwnd: hwnd)
            sampleGeometry()
            emit(.rightClick(MouseEvent(button: .right, position: Win32NativeWindowUtilities.point(from: lParam))))
            return 0
        case UINT(WM_RBUTTONUP):
            endCapture(.right)
            return 0
        case UINT(WM_MBUTTONDOWN):
            beginCapture(.middle, hwnd: hwnd)
            sampleGeometry()
            emit(.middleButton(Win32NativeWindowUtilities.point(from: lParam), .down))
            return 0
        case UINT(WM_MBUTTONUP):
            endCapture(.middle)
            sampleGeometry()
            emit(.middleButton(Win32NativeWindowUtilities.point(from: lParam), .up))
            return 0
        case UINT(WM_CAPTURECHANGED):
            if !isReleasingCapture {
                capturedButtons = 0
                emit(.pointerCancelled)
            }
            return 0
        case UINT(WM_CANCELMODE):
            capturedButtons = 0
            releaseCapture()
            emit(.pointerCancelled)
            return DefWindowProcW(hwnd, message, wParam, lParam)
        case UINT(WM_MOUSEWHEEL), UINT(WM_MOUSEHWHEEL):
            let horizontal = message == UINT(WM_MOUSEHWHEEL) || UInt(wParam) & UInt(MK_SHIFT) != 0
            var delta = Win32NativeWindowUtilities.mouseWheelDelta(wParam: wParam, horizontal: horizontal)
            if message == UINT(WM_MOUSEHWHEEL) { delta = -delta }
            let point = Win32NativeWindowUtilities.clientPoint(fromScreenLParam: lParam, hwnd: hwnd)
            sampleGeometry()
            emit(.scroll(point, delta, horizontal ? .horizontal : .vertical))
            return 0
        case UINT(WM_KEYDOWN):
            emit(.keyDown(Win32NativeWindowUtilities.keyboardEvent(wParam: wParam, lParam: lParam)))
            return 0
        case UINT(WM_CHAR):
            if isComposing {
                textDecoder.reset()
                return 0
            }
            if let text = textDecoder.append(UInt16(truncatingIfNeeded: wParam)) { emit(.textInput(text)) }
            return 0
        case UINT(WM_KILLFOCUS):
            textDecoder.reset()
            isComposing = false
            caret = nil
            caretGeometryRevision = nil
            emit(.keyboardFocusLost)
            return 0
        case UINT(WM_DISPLAYCHANGE):
            sampleGeometry(forceMonitor: true)
            emit(.geometryChanged)
            return 0
        case UINT(WM_MOVE):
            sampleGeometry()
            emit(.geometryChanged)
            return 0
        case UINT(WM_ENTERSIZEMOVE):
            isInSizeMove = true
            refreshAnimationTimer()
            sampleGeometry()
            emit(.geometryChanged)
            return 0
        case UINT(WM_EXITSIZEMOVE):
            isInSizeMove = false
            refreshAnimationTimer()
            sampleGeometry()
            emit(.resized)
            _ = owner.mailbox.signal()
            return 0
        case UINT(WM_ENTERMENULOOP):
            isInMenuLoop = true
            refreshAnimationTimer()
            sampleGeometry()
            emit(.geometryChanged)
            return 0
        case UINT(WM_EXITMENULOOP):
            isInMenuLoop = false
            refreshAnimationTimer()
            sampleGeometry()
            emit(.geometryChanged)
            _ = owner.mailbox.signal()
            return 0
        case UINT(WM_ACTIVATEAPP):
            active = wParam != 0
            sampleGeometry()
            emit(.activeChanged(active))
            return 0
        case UINT(WM_SHOWWINDOW):
            visible = wParam != 0
            sampleGeometry()
            emit(.visibilityChanged(visible))
            return 0
        case UINT(WM_SETTINGCHANGE), UINT(WM_SYSCOLORCHANGE):
            let previous = appearance
            appearance = Win32SystemAppearanceProvider().sampleSystemAppearance()
            if message == UINT(WM_SYSCOLORCHANGE) || appearance != previous
                || Win32NativeWindowUtilities.shouldDeliverSettingChange(
                    wParam: wParam, section: Win32NativeWindowUtilities.settingChangeSection(lParam))
            {
                emit(.systemAppearanceChanged)
            }
            return 0
        case UINT(WM_SETCURSOR):
            if UInt16(UInt(truncatingIfNeeded: lParam) & 0xFFFF) == UINT16(HTCLIENT) {
                SetCursor(LoadCursorW(nil, UnsafePointer<WCHAR>(bitPattern: 32512)))
                return 1
            }
            return DefWindowProcW(hwnd, message, wParam, lParam)
        case UINT(WM_IME_SETCONTEXT):
            return DefWindowProcW(hwnd, message, wParam, Win32NativeWindowUtilities.imeAdjustedLParam(lParam))
        case UINT(WM_IME_STARTCOMPOSITION):
            isComposing = true
            textDecoder.reset()
            updateIMEPosition(queryActor: true)
            emit(.imeComposition(IMECompositionEvent(phase: .started)))
            return DefWindowProcW(hwnd, message, wParam, lParam)
        case UINT(WM_IME_COMPOSITION):
            for event in Win32NativeWindowUtilities.imeCompositionEvents(
                lParam: lParam, hwnd: hwnd, provider: imeProvider)
            {
                emit(.imeComposition(event))
            }
            updateIMEPosition(queryActor: true)
            return DefWindowProcW(hwnd, message, wParam, lParam)
        case UINT(WM_IME_ENDCOMPOSITION):
            isComposing = false
            textDecoder.reset()
            emit(.imeComposition(IMECompositionEvent(phase: .ended)))
            return DefWindowProcW(hwnd, message, wParam, lParam)
        case UINT(WM_IME_CHAR):
            if let scalar = Unicode.Scalar(UInt32(truncatingIfNeeded: wParam)) {
                emit(.imeComposition(IMECompositionEvent(phase: .committed(String(scalar)))))
            }
            return 0
        case UINT(WM_TOUCH):
            consumeTouch(hwnd: hwnd, wParam: wParam, lParam: lParam)
            return 0
        case UINT(WM_DROPFILES):
            if let payload = Win32NativeWindowUtilities.dropPayload(wParam: wParam) {
                sampleGeometry()
                emit(.filesDropped(payload))
            }
            return 0
        case UINT(WM_CLOSE):
            requestActorClose()
            return 0
        case UINT(WM_DESTROY):
            guard !observedDestroy else { return 0 }
            observedDestroy = true
            creation.snapshotSource.revoke(.closed)
            stopAnimationTimer()
            if hasCloseWatchdog, let handle {
                let removed = KillTimer(handle, Self.closeWatchdogID)
                hasCloseWatchdog = false
                observeTimerAPI(.killCloseWatchdog, succeeded: removed ? true : false, code: nil)
                observeTimerState()
            }
            if pendingDestruction == nil {
                reportFailure(.execution("Native window was destroyed outside its prepared close transaction"))
                for id in Array(attachmentOrder) { attachments[id]?.beginQuiescence() }
            }
            return 0
        case UINT(WM_NCDESTROY):
            guard ownsNativeHandle(hwnd) else { return 0 }
            observedDestroy = true
            if !cleanupRequested, let hwnd {
                cleanupRequested = true
                _ = SWU_UIAReturnRawElementProvider(UnsafeMutableRawPointer(hwnd), 0, 0, nil)
            }
            guard ownsNativeHandle(hwnd) else { return 0 }
            let result = DefWindowProcW(hwnd, message, wParam, lParam)
            guard ownsNativeHandle(hwnd) else { return result }
            stopAnimationTimer()
            guard ownsNativeHandle(hwnd) else { return result }
            if let hwnd { SetWindowLongPtrW(hwnd, GWLP_USERDATA, 0) }
            handle = nil
            observedNonClientDestroy = true
            owner.mailbox.smokeObservation?.record(
                .nativeWindowNonClientDestroyed, windowKey: creation.key,
                requestID: pendingDestruction?.reservation?.requestID,
                generation: currentSurface?.generation, nativeSequence: currentSurface?.geometry.nativeSequence)
            creation.snapshotSource.revoke(.closed)
            return result
        default:
            return DefWindowProcW(hwnd, message, wParam, lParam)
        }
    }

    /// Compare only recorded state; diagnostic classification must not perform a native ownership query.
    fileprivate func matchesRecordedMessageTarget(_ candidate: HWND) -> Bool {
        handle == candidate
    }

    private func ownsNativeHandle(_ hwnd: HWND?) -> Bool {
        guard let hwnd, handle == hwnd, ownsNativeReference, !observedNonClientDestroy else { return false }
        let expected = LONG_PTR(Int(bitPattern: Unmanaged.passUnretained(self).toOpaque()))
        return GetWindowLongPtrW(hwnd, GWLP_USERDATA) == expected
    }

    private func requestActorClose() {
        guard !hasBegunQuiescence, !observedDestroy else { return }
        if acceptsInteractiveInput { emit(.closeRequested) } else { closeRequestedBeforeActivation = true }
    }

    private func enableInteractiveInput() {
        acceptsInteractiveInput = true
        if closeRequestedBeforeActivation {
            closeRequestedBeforeActivation = false
            emit(.closeRequested)
        }
    }

    private func applyConfiguration() {
        guard let handle else { return }
        if creation.configuration.isAlwaysOnTop {
            SetWindowPos(handle, HWND(bitPattern: -1), 0, 0, 0, 0, UINT(SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE))
        }
        guard let position = creation.configuration.normalizedPosition else { return }
        var rect = RECT()
        guard GetWindowRect(handle, &rect) else { return }
        var info = MONITORINFO()
        info.cbSize = DWORD(MemoryLayout<MONITORINFO>.size)
        guard GetMonitorInfoW(MonitorFromWindow(handle, DWORD(MONITOR_DEFAULTTONEAREST)), &info) else { return }
        let normalizedX = position.x.isFinite ? min(1, max(0, position.x)) : 0.5
        let normalizedY = position.y.isFinite ? min(1, max(0, position.y)) : 0.5
        let slackX = max(0, Int64(info.rcWork.right) - Int64(info.rcWork.left) - Int64(rect.right) + Int64(rect.left))
        let slackY = max(0, Int64(info.rcWork.bottom) - Int64(info.rcWork.top) - Int64(rect.bottom) + Int64(rect.top))
        let x = Int32(clamping: Int64(info.rcWork.left) + Int64((Double(slackX) * normalizedX).rounded()))
        let y = Int32(clamping: Int64(info.rcWork.top) + Int64((Double(slackY) * normalizedY).rounded()))
        SetWindowPos(handle, nil, x, y, 0, 0, UINT(SWP_NOSIZE | SWP_NOZORDER | SWP_NOACTIVATE))
    }

    private func trackMouseLeave() {
        guard !isTrackingMouseLeave, let handle else { return }
        var tracking = TRACKMOUSEEVENT()
        tracking.cbSize = DWORD(MemoryLayout<TRACKMOUSEEVENT>.size)
        tracking.dwFlags = DWORD(TME_LEAVE)
        tracking.hwndTrack = handle
        if TrackMouseEvent(&tracking) { isTrackingMouseLeave = true }
    }

    private func beginCapture(_ button: MouseButton, hwnd: HWND?) {
        capturedButtons |= UInt8(1) << button.rawValue
        if GetCapture() != hwnd { SetCapture(hwnd) }
    }

    private func endCapture(_ button: MouseButton) {
        capturedButtons &= ~(UInt8(1) << button.rawValue)
        if capturedButtons == 0 { releaseCapture() }
    }

    private func releaseCapture() {
        guard let handle, GetCapture() == handle else { return }
        isReleasingCapture = true
        defer { isReleasingCapture = false }
        ReleaseCapture()
    }

    private func consumeTouch(hwnd: HWND?, wParam: WPARAM, lParam: LPARAM) {
        let count = UInt16(UInt(wParam) & 0xFFFF)
        guard count > 0, let touch = HTOUCHINPUT(bitPattern: Int(lParam)) else { return }
        defer { CloseTouchInputHandle(touch) }
        var inputs = [TOUCHINPUT](repeating: TOUCHINPUT(), count: Int(count))
        guard GetTouchInputInfo(touch, UINT(count), &inputs, Int32(MemoryLayout<TOUCHINPUT>.size)) else { return }
        var began: [Point] = []
        var moved: [Point] = []
        var ended: [Point] = []
        for input in inputs {
            var point = POINT(x: LONG(input.x / 100), y: LONG(input.y / 100))
            ScreenToClient(hwnd, &point)
            let value = Point(x: Double(point.x), y: Double(point.y))
            if input.dwFlags & DWORD(TOUCHEVENTF_DOWN) != 0 {
                began.append(value)
            } else if input.dwFlags & DWORD(TOUCHEVENTF_MOVE) != 0 {
                moved.append(value)
            } else if input.dwFlags & DWORD(TOUCHEVENTF_UP) != 0 {
                ended.append(value)
            }
        }
        sampleGeometry()
        if !began.isEmpty { emit(.touch(.began, began)) }
        if !moved.isEmpty { emit(.touch(.moved, moved)) }
        if !ended.isEmpty { emit(.touch(.ended, ended)) }
    }

    private func updateIMEPosition(queryActor: Bool) {
        guard let handle, isCreated, pendingDestruction == nil, !observedDestroy else { return }
        sampleGeometry()
        guard lastGeometryFailure == nil else { return }
        let captured = surface
        if queryActor {
            switch creation.caretQuery.query(captured) {
            case .success(let value): caret = value
            case .failure(let failure):
                reportFailure(failure)
                return
            }
            caretGeometryRevision = captured.generation
        }
        guard self.handle == handle, !observedDestroy, pendingDestruction == nil,
            let caret, caretGeometryRevision == surface.generation
        else { return }
        let point = Point(
            x: (caret.origin.x * captured.geometry.effectiveScaleFactor).rounded(),
            y: ((caret.origin.y + caret.size.height) * captured.geometry.effectiveScaleFactor).rounded())
        guard point.x.isFinite, point.y.isFinite,
            point.x >= Double(Int32.min), point.x <= Double(Int32.max),
            point.y >= Double(Int32.min), point.y <= Double(Int32.max)
        else {
            reportFailure(.execution("IME caret is outside representable native coordinates"))
            return
        }
        imeProvider.setCompositionWindowPosition(point, window: handle)
    }

    @discardableResult
    private func stopAnimationTimer() -> NativeWindowOwnerFailure? {
        defer { observeTimerState() }
        if let timer = highResolutionTimer {
            let removed = DeleteTimerQueueTimer(nil, timer, INVALID_HANDLE_VALUE)
            let error = removed ? 0 : GetLastError()
            observeTimerAPI(
                .deleteHighResolution, succeeded: removed ? true : false, code: removed ? nil : Int64(error))
            guard removed else {
                let failure = NativeWindowOwnerFailure.native(operation: "DeleteTimerQueueTimer", code: Int64(error))
                // The callback's context must stay alive unless the native
                // wait actually proved that the last callback returned.
                reportFailure(failure)
                return failure
            }
            highResolutionTimer = nil
            highResolutionGate = nil
        } else if installedAnimationInterval != nil, let handle {
            let removed = KillTimer(handle, Self.animationTimerID)
            // Keep the actual Boolean result without claiming ambient
            // last-error state as this operation's native failure code.
            observeTimerAPI(.killWindowTimer, succeeded: removed ? true : false, code: nil)
            if !removed, !observedDestroy {
                let failure = NativeWindowOwnerFailure.execution("KillTimer did not remove the owned animation timer")
                reportFailure(failure)
                return failure
            }
        }
        installedAnimationInterval = nil
        if holdsTimerResolution {
            let result = timeEndPeriod(1)
            observeTimerAPI(.endResolution, succeeded: result == 0, code: result == 0 ? nil : Int64(result))
            guard result == 0 else {
                let failure = NativeWindowOwnerFailure.native(operation: "timeEndPeriod", code: Int64(result))
                reportFailure(failure)
                return failure
            }
            holdsTimerResolution = false
            smokeActualResolutionOwned = false
        }
        return nil
    }

    @discardableResult
    private func refreshAnimationTimer() -> NativeWindowOwnerFailure? {
        defer { observeTimerState() }
        guard let requested = animationInterval, let handle, pendingDestruction == nil, !observedDestroy else {
            return stopAnimationTimer()
        }
        let modal = isInSizeMove || isInMenuLoop || nativeModalDepth > 0
        let interval = modal ? UInt32(max(1, USER_TIMER_MINIMUM)) : max(1, requested)
        let highResolution = prefersHighResolution && !highResolutionUnavailable && !modal
        if installedAnimationInterval == interval, (highResolutionTimer != nil) == highResolution { return nil }
        // Keep the resolution hold over a cadence/mode change. Only enabling
        // and disabling the animation driver changes the process-wide hold.
        let retainedResolutionHold = holdsTimerResolution
        holdsTimerResolution = false
        let stopFailure = stopAnimationTimer()
        holdsTimerResolution = retainedResolutionHold
        if let stopFailure { return stopFailure }
        if highResolution {
            let gate = Win32NativeAnimationGate(
                handleValue: UInt(bitPattern: handle), windowKey: creation.key,
                observation: owner.mailbox.smokeObservation)
            var timer: HANDLE?
            let created = CreateTimerQueueTimer(
                &timer, nil, win32NativeAnimationCallback,
                Unmanaged.passUnretained(gate).toOpaque(), interval, interval, DWORD(WT_EXECUTEDEFAULT))
            let error: Int64? = created ? nil : Int64(GetLastError())
            observeTimerAPI(.createHighResolution, succeeded: created ? true : false, code: error)
            if created {
                highResolutionTimer = timer
                highResolutionGate = gate
            } else {
                highResolutionUnavailable = true
            }
        }
        if highResolutionTimer == nil {
            let timer = SetTimer(handle, Self.animationTimerID, interval, nil)
            let error = timer == 0 ? GetLastError() : 0
            observeTimerAPI(.setWindowTimer, succeeded: timer != 0, code: timer == 0 ? Int64(error) : nil)
            if timer == 0 {
                let failure = NativeWindowOwnerFailure.native(operation: "SetTimer(animation)", code: Int64(error))
                _ = stopAnimationTimer()
                reportFailure(failure)
                return failure
            }
        }
        installedAnimationInterval = interval
        if !holdsTimerResolution {
            let result = timeBeginPeriod(1)
            observeTimerAPI(.beginResolution, succeeded: result == 0, code: result == 0 ? nil : Int64(result))
            if result == 0 {
                holdsTimerResolution = true
                smokeActualResolutionOwned = true
            } else {
                let failure = NativeWindowOwnerFailure.native(operation: "timeBeginPeriod", code: Int64(result))
                reportFailure(failure)
                return failure
            }
        }
        return nil
    }

    private func observeTimerAPI(
        _ operation: Win32NativeSmokeTimerOperation, succeeded: Bool, code: Int64?
    ) {
        guard let observation = owner.mailbox.smokeObservation else { return }
        if !succeeded {
            switch operation {
            case .deleteHighResolution, .killWindowTimer, .endResolution, .killCloseWatchdog:
                smokeTimerStateUncertain = true
            default: break
            }
        }
        observation.record(
            .nativeTimerAPIResult, windowKey: creation.key, generation: currentSurface?.generation,
            nativeSequence: currentSurface?.geometry.nativeSequence, value: code,
            auxiliary: operation.rawValue, flags: succeeded ? 1 : 0)
    }

    private func observeTimerState(force: Bool = false) {
        guard let observation = owner.mailbox.smokeObservation else { return }
        var flags: UInt32 = 0
        if highResolutionTimer != nil { flags |= Win32NativeSmokeTimerFlags.highResolutionInstalled }
        if installedAnimationInterval != nil, highResolutionTimer == nil {
            flags |= Win32NativeSmokeTimerFlags.windowTimerInstalled
        }
        // holdsTimerResolution is temporarily cleared during a cadence change.
        // Only successful native begin/end calls change this observed owner bit.
        if smokeActualResolutionOwned { flags |= Win32NativeSmokeTimerFlags.resolutionOwned }
        if hasCloseWatchdog { flags |= Win32NativeSmokeTimerFlags.closeWatchdogInstalled }
        if smokeTimerStateUncertain { flags |= Win32NativeSmokeTimerFlags.stateUncertain }
        guard force || smokeLastTimerFlags != flags || smokeLastTimerInterval != installedAnimationInterval else {
            return
        }
        smokeLastTimerFlags = flags
        smokeLastTimerInterval = installedAnimationInterval
        let guiThreadState: UInt64?
        if flags == 0, isCreated, !observedDestroy, !observedNonClientDestroy, !hasBegunQuiescence,
            let handle
        {
            guiThreadState = Win32NativeSmokeGUIThreadState.sample(recordedWindow: handle)
        } else {
            guiThreadState = nil
        }
        observation.record(
            .nativeTimerState, windowKey: creation.key, generation: currentSurface?.generation,
            nativeSequence: currentSurface?.geometry.nativeSequence,
            value: installedAnimationInterval.map { Int64($0) }, auxiliary: guiThreadState, flags: flags)
    }

    func executeOperation(_ operation: Win32NativeWindowOperation) throws -> Win32NativeWindowOperationResult {
        guard let handle, !observedDestroy else { throw NativeWindowOwnerFailure.closed }
        switch operation {
        case .show:
            enableInteractiveInput()
            ShowWindow(handle, SW_SHOW)
            UpdateWindow(handle)
            if !InvalidateRect(handle, nil, false) { throw nativeFailure("InvalidateRect") }
        case .activate:
            enableInteractiveInput()
            ShowWindow(handle, IsIconic(handle) ? SW_RESTORE : SW_SHOW)
            let activated = SetForegroundWindow(handle)
            owner.mailbox.smokeObservation?.recordForegroundActivationResult(
                activated, windowKey: creation.key, generation: currentSurface?.generation,
                nativeSequence: currentSurface?.geometry.nativeSequence)
            UpdateWindow(handle)
            InvalidateRect(handle, nil, false)
            return .activated(activated)
        case .invalidate:
            if !InvalidateRect(handle, nil, false) { throw nativeFailure("InvalidateRect") }
        case .requestClose:
            if !PostMessageW(handle, UINT(WM_CLOSE), 0, 0) { throw nativeFailure("PostMessageW(WM_CLOSE)") }
        case .deferredCloseWake(let nonce):
            emit(.deferredCloseWake(nonce))
        case .animationTimer(let enabled, let interval, let highResolution):
            animationInterval = enabled ? max(1, interval) : nil
            prefersHighResolution = highResolution
            if let failure = refreshAnimationTimer() { throw failure }
        case .closeButton(let enabled):
            isCloseEnabled = enabled
            // A hidden title bar has no system menu. Its policy still guards
            // native close even though there is no menu affordance to update.
            if let menu = GetSystemMenu(handle, false) {
                // WinSDK imports EnableMenuItem's BOOL result as Bool, which
                // loses its distinct previous-state and -1 failure values.
                // Read and update only the state field instead; these APIs
                // have actual boolean success results.
                var item = MENUITEMINFOW()
                item.cbSize = UINT(MemoryLayout<MENUITEMINFOW>.size)
                item.fMask = UINT(MIIM_STATE)
                guard GetMenuItemInfoW(menu, UINT(SC_CLOSE), false, &item) else {
                    throw nativeFailure("GetMenuItemInfoW(SC_CLOSE)")
                }
                item.fState = Win32NativeWindowUtilities.menuItemState(item.fState, enabled: enabled)
                guard SetMenuItemInfoW(menu, UINT(SC_CLOSE), false, &item) else {
                    throw nativeFailure("SetMenuItemInfoW(SC_CLOSE)")
                }
                if !DrawMenuBar(handle) { throw nativeFailure("DrawMenuBar") }
            }
        case .closeWatchdog(let seconds):
            guard seconds.isFinite, seconds > 0, seconds * 1000 <= Double(UINT.max) else {
                throw NativeWindowOwnerFailure.execution("Invalid native close-watchdog interval")
            }
            let timer = SetTimer(handle, Self.closeWatchdogID, UINT(max(1, (seconds * 1000).rounded())), nil)
            let error = timer == 0 ? GetLastError() : 0
            observeTimerAPI(.setCloseWatchdog, succeeded: timer != 0, code: timer == 0 ? Int64(error) : nil)
            if timer == 0 {
                observeTimerState(force: true)
                throw NativeWindowOwnerFailure.native(operation: "SetTimer(close watchdog)", code: Int64(error))
            }
            hasCloseWatchdog = true
            observeTimerState()
        case .toggleFullscreen:
            try toggleFullscreen()
        case .caret(let rect, let generation):
            guard generation == surface.generation else {
                throw NativeWindowOwnerFailure.staleSurface(expected: generation, actual: surface.generation)
            }
            caret = rect
            caretGeometryRevision = generation
            if isComposing { updateIMEPosition(queryActor: false) }
        }
        sampleGeometry()
        if let lastGeometryFailure { throw lastGeometryFailure }
        return .completed
    }

    private func toggleFullscreen() throws {
        guard let handle else { throw NativeWindowOwnerFailure.closed }
        if isFullscreen {
            SetWindowLongW(handle, GWL_STYLE, Int32(bitPattern: preFullscreenStyle))
            guard
                SetWindowPos(
                    handle, nil, preFullscreenRect.left, preFullscreenRect.top,
                    preFullscreenRect.right - preFullscreenRect.left, preFullscreenRect.bottom - preFullscreenRect.top,
                    UINT(SWP_FRAMECHANGED | SWP_NOACTIVATE | SWP_NOZORDER))
            else { throw nativeFailure("SetWindowPos(restore fullscreen)") }
            isFullscreen = false
        } else {
            preFullscreenStyle = DWORD(bitPattern: GetWindowLongW(handle, GWL_STYLE))
            guard GetWindowRect(handle, &preFullscreenRect) else { throw nativeFailure("GetWindowRect(fullscreen)") }
            var info = MONITORINFO()
            info.cbSize = DWORD(MemoryLayout<MONITORINFO>.size)
            guard GetMonitorInfoW(MonitorFromWindow(handle, DWORD(MONITOR_DEFAULTTONEAREST)), &info) else {
                throw nativeFailure("GetMonitorInfoW(fullscreen)")
            }
            SetWindowLongW(handle, GWL_STYLE, Int32(bitPattern: UInt32(WS_POPUP)) | WS_VISIBLE)
            guard
                SetWindowPos(
                    handle, nil, info.rcMonitor.left, info.rcMonitor.top,
                    info.rcMonitor.right - info.rcMonitor.left, info.rcMonitor.bottom - info.rcMonitor.top,
                    UINT(SWP_FRAMECHANGED | SWP_NOACTIVATE | SWP_NOZORDER))
            else { throw nativeFailure("SetWindowPos(fullscreen)") }
            isFullscreen = true
        }
        sampleGeometry()
        emit(.geometryChanged)
    }

    static let className = "SwiftWindowsUI.NativeOwnerWindow"
    private static let animationTimerID: UINT_PTR = 1
    private static let closeWatchdogID: UINT_PTR = 2

    static let windowProcedure: WNDPROC = { hwnd, message, wParam, lParam in
        if message == UINT(WM_NCCREATE) {
            let creation = UnsafeMutableRawPointer(bitPattern: Int(lParam))?.assumingMemoryBound(to: CREATESTRUCTW.self)
            if let raw = creation?.pointee.lpCreateParams {
                SetWindowLongPtrW(hwnd, GWLP_USERDATA, LONG_PTR(Int(bitPattern: raw)))
            }
        }
        let value = GetWindowLongPtrW(hwnd, GWLP_USERDATA)
        guard let raw = UnsafeMutableRawPointer(bitPattern: Int(value)) else {
            return DefWindowProcW(hwnd, message, wParam, lParam)
        }
        let unmanaged = Unmanaged<Win32NativeWindowState>.fromOpaque(raw)
        let window = unmanaged.takeUnretainedValue()
        return withExtendedLifetime(window) {
            window.owner.withDispatch {
                if message == UINT(WM_NCCREATE) {
                    window.handle = hwnd
                    window.hasBoundNativeHandle = hwnd != nil
                }
                let result = window.handleMessage(hwnd: hwnd, message: message, wParam: wParam, lParam: lParam)
                if message == UINT(WM_NCDESTROY), window.consumeNativeReference() { unmanaged.release() }
                return result
            }
        }
    }
}

/// Preflight before the fixture performs its real ordinal-31 provider query.
/// This does not reserve/commit an ordinal or publish an input sequence; emit
/// repeats the same checks and commits only after actual ingress admission.
package func validateNativeSmokeProbe(
    in context: any NativeWindowOwnerContext, observation: Win32NativeSmokeObservation, ordinal: UInt32
) throws {
    guard let native = context as? Win32NativeWindowState else {
        throw NativeWindowOwnerFailure.execution("Native smoke traffic requires an actual Win32 owner context")
    }
    try native.validateSmokeProbe(observation: observation, ordinal: ordinal)
}

/// Called only from the fixture's ordinary checked-Sendable owner command.
/// The real window context validates identity, lifetime and the ordinal before
/// admitting a non-coalesced record through the existing native ingress path.
package func emitNativeSmokeProbe(
    in context: any NativeWindowOwnerContext,
    observation: Win32NativeSmokeObservation,
    requestID: NativeWindowRequestID,
    ordinal: UInt32
) throws -> NativeWindowSurface {
    guard let native = context as? Win32NativeWindowState else {
        throw NativeWindowOwnerFailure.execution("Native smoke traffic requires an actual Win32 owner context")
    }
    return try native.emitSmokeProbe(observation: observation, requestID: requestID, ordinal: ordinal)
}

enum Win32NativeWindowOperation: Sendable {
    case show
    case activate
    case invalidate
    case requestClose
    case deferredCloseWake(UInt)
    case animationTimer(enabled: Bool, interval: UInt32, highResolution: Bool)
    case closeButton(Bool)
    case closeWatchdog(Double)
    case toggleFullscreen
    case caret(Rect?, generation: UInt64)
}

enum Win32NativeWindowOperationResult: Sendable {
    case completed
    case activated(Bool)
}

struct Win32NativeWindowOperationCommand: NativeWindowOwnerCommand {
    let windowKey: NativeWindowKey
    let requestID = NativeWindowRequestID()
    let operation: Win32NativeWindowOperation
    let reply: NativeWindowReply<Win32NativeWindowOperationResult>
    var commandReply: NativeWindowCommandReply { reply.commandReply }

    func execute(in context: any NativeWindowOwnerContext) throws {
        guard let native = context as? Win32NativeWindowState else {
            throw NativeWindowOwnerFailure.execution("Win32 operation requires its native owner context")
        }
        reply.complete(.success(try native.executeOperation(operation)))
    }

    func reject(_ failure: NativeWindowOwnerFailure) { reply.complete(.failure(failure)) }
}

func nativeFailure(_ operation: String) -> NativeWindowOwnerFailure {
    .native(operation: operation, code: Int64(GetLastError()))
}

extension String {
    func withNativeWideChars<Result>(_ body: (UnsafePointer<WCHAR>) throws -> Result) rethrows -> Result {
        let units = Array(utf16) + [0]
        return try units.withUnsafeBufferPointer { buffer in try body(buffer.baseAddress!) }
    }
}
