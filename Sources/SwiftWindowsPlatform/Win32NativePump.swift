import Dispatch
import Foundation
import SwiftWindowsCore
import Synchronization
import WinSDK

/// The operating-system thread has actually terminated and its handle has
/// been joined. Posting WM_QUIT, or returning from a window callback, is not
/// this acknowledgement.
package struct Win32NativePumpExit: Equatable, Sendable {
    package let exitCode: Int32
    package let joined: Bool
}

package struct Win32NativeWindowObservation: Sendable {
    package let surface: NativeWindowSurface
    package let systemAppearance: SystemAppearanceSnapshot
    package let displayIdentity: String
    package let isInLiveResize: Bool
    package let isFullscreen: Bool
}

package enum Win32NativeWindowEvent: Sendable {
    case created
    case geometryChanged
    case resized
    case needsDisplay
    case animationFrame(Double)
    case pointer(Win32CapturedPointerInput.Kind, Point)
    case pointerExited
    case pointerCancelled
    case scroll(Point, Double, PlatformScrollAxis)
    case rightClick(MouseEvent)
    case doubleClick(MouseEvent)
    case middleButton(Point, PlatformPointerPhase)
    case keyDown(KeyboardEvent)
    case textInput(String)
    case keyboardFocusLost
    case activeChanged(Bool)
    case visibilityChanged(Bool)
    case systemAppearanceChanged
    case imeComposition(IMECompositionEvent)
    case touch(PlatformTouchPhase, [Point])
    case filesDropped(FileDropPayload)
    case closeRequested
    case deferredCloseWake(UInt)
    case smokeProbe(Win32NativeSmokeProbe)
    case destroyed
    case ownerFailure(NativeWindowOwnerFailure)
}

package struct Win32NativeWindowEventRecord: Sendable {
    package let observation: Win32NativeWindowObservation
    package let event: Win32NativeWindowEvent
}

/// Used only by the native owner for a synchronous IME query. The actor body
/// flushes already-copied input and returns a value; it must never wait for a
/// native command or call a native facade's synchronous result API.
final class Win32NativeCaretQuery: Sendable {
    private let receive: @MainActor @Sendable (NativeWindowSurface) -> Result<Rect?, NativeWindowOwnerFailure>

    init(receive: @escaping @MainActor @Sendable (NativeWindowSurface) -> Result<Rect?, NativeWindowOwnerFailure>) {
        self.receive = receive
    }

    func query(_ surface: NativeWindowSurface) -> Result<Rect?, NativeWindowOwnerFailure> {
        let result = Win32NativeCaretReplyCell()
        Task { @MainActor [receive] in
            result.complete(receive(surface))
        }
        return result.wait()
    }
}

private final class Win32NativeCaretReplyCell: Sendable {
    private let result = Mutex<Result<Rect?, NativeWindowOwnerFailure>?>(nil)
    private let completed = DispatchSemaphore(value: 0)

    func complete(_ value: Result<Rect?, NativeWindowOwnerFailure>) {
        let claimed = result.withLock { stored in
            guard stored == nil else { return false }
            stored = value
            return true
        }
        if claimed { completed.signal() }
    }

    func wait() -> Result<Rect?, NativeWindowOwnerFailure> {
        completed.wait()
        return result.withLock { $0 ?? .failure(.unavailable) }
    }
}

final class Win32NativeSnapshotSource: NativeWindowSnapshotSource {
    private let value = Mutex<Result<NativeWindowSurface, NativeWindowOwnerFailure>>(.failure(.unavailable))

    func snapshot() -> Result<NativeWindowSurface, NativeWindowOwnerFailure> {
        value.withLock { $0 }
    }

    func publish(_ surface: NativeWindowSurface) {
        value.withLock { $0 = .success(surface) }
    }

    func revoke(_ failure: NativeWindowOwnerFailure) {
        value.withLock { $0 = .failure(failure) }
    }
}

struct Win32NativeWindowCreation: Sendable {
    let key: NativeWindowKey
    let title: String
    let logicalClientSize: IntSize
    let titleBarVisibility: WindowTitleBarVisibility
    let configuration: Win32WindowConfiguration
    let ingress: Win32NativeEventIngress
    let snapshotSource: Win32NativeSnapshotSource
    let caretQuery: Win32NativeCaretQuery
    let reply: NativeWindowReply<NativeWindowSurface>
}

/// The transport owns no HWND state and no UI object. Only this mailbox and
/// copied values cross CreateThread; Win32NativeLoop is constructed there.
public final class Win32NativePump: NativeWindowCommandSink {
    private let mailbox: Win32NativePumpMailbox

    public init() { mailbox = Win32NativePumpMailbox() }

    package init(observation: Win32NativeSmokeObservation?) {
        mailbox = Win32NativePumpMailbox(observation: observation)
    }

    package var smokeObservation: Win32NativeSmokeObservation? { mailbox.smokeObservation }

    /// Passive instantaneous queue state. It never submits a native command,
    /// flushes ingress or waits for either executor to make progress.
    package var smokeQueueSnapshot: Win32NativeSmokePumpSnapshot { mailbox.smokeQueueSnapshot }

    package func start() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            let reply = NativeWindowReply<Void> { result in
                continuation.resume(with: result.mapError { $0 as any Error })
            }
            guard mailbox.requestStart(reply) else { return }
            let context = Unmanaged.passRetained(mailbox).toOpaque()
            var threadID: DWORD = 0
            guard let thread = CreateThread(nil, 0, win32NativeThreadProcedure, context, 0, &threadID) else {
                let code = GetLastError()
                Unmanaged<Win32NativePumpMailbox>.fromOpaque(context).release()
                mailbox.didFailToStart(.native(operation: "CreateThread", code: Int64(code)))
                return
            }

            // Waiting occurs on a worker, never on MainActor or the window
            // owner. This joins the actual thread, including its final ARC
            // releases, rather than trusting an early "about to exit" event.
            let handleValue = UInt(bitPattern: thread)
            let ownerThreadID = threadID
            let mailbox = self.mailbox
            let observation = mailbox.smokeObservation
            DispatchQueue.global(qos: .utility).async {
                guard let handle = HANDLE(bitPattern: handleValue) else {
                    observation?.record(.nativeJoinFailed, auxiliary: 0)
                    mailbox.didJoin(.failure(.unavailable))
                    return
                }
                let waitResult = WaitForSingleObject(handle, INFINITE)
                if waitResult != DWORD(WAIT_OBJECT_0) {
                    let code = waitResult == DWORD(WAIT_FAILED) ? GetLastError() : waitResult
                    CloseHandle(handle)
                    observation?.record(.nativeJoinFailed, value: Int64(code), auxiliary: 0)
                    mailbox.didJoin(.failure(.native(operation: "WaitForSingleObject", code: Int64(code))))
                    return
                }
                observation?.record(.nativeThreadTerminated, auxiliary: UInt64(ownerThreadID))
                var exitCode: DWORD = 0
                let readExit = GetExitCodeThread(handle, &exitCode)
                let readError = readExit ? 0 : GetLastError()
                let closedHandle = CloseHandle(handle)
                let closeError = closedHandle ? 0 : GetLastError()
                if !readExit {
                    observation?.record(.nativeJoinFailed, value: Int64(readError), auxiliary: 1)
                    mailbox.didJoin(.failure(.native(operation: "GetExitCodeThread", code: Int64(readError))))
                } else if !closedHandle {
                    observation?.record(.nativeJoinFailed, value: Int64(closeError), auxiliary: 2)
                    mailbox.didJoin(.failure(.native(operation: "CloseHandle(thread)", code: Int64(closeError))))
                } else {
                    observation?.record(
                        .nativeThreadJoined, value: Int64(Int32(bitPattern: exitCode)),
                        auxiliary: UInt64(ownerThreadID), flags: 1)
                    mailbox.didJoin(.success(Win32NativePumpExit(exitCode: Int32(bitPattern: exitCode), joined: true)))
                }
            }
        }
    }

    package func stop() async throws -> Win32NativePumpExit {
        try await withCheckedThrowingContinuation { continuation in
            let reply = NativeWindowReply<Win32NativePumpExit> { result in
                continuation.resume(with: result.mapError { $0 as any Error })
            }
            mailbox.requestStop(reply)
        }
    }

    @discardableResult
    public func submit(_ command: any NativeWindowOwnerCommand) -> NativeWindowSubmission {
        mailbox.submit(.command(command))
    }

    func createWindow(_ creation: Win32NativeWindowCreation) {
        _ = mailbox.submit(.create(creation))
    }

    func completeClose(
        _ reservation: Win32NativeCloseReservation,
        reply: NativeWindowReply<Win32NativeCloseDestruction>
    ) {
        _ = mailbox.submit(.close(Win32NativeDestructionRequest(reservation: reservation, reply: reply)))
    }

    func discardWindow(
        key: NativeWindowKey,
        reply: NativeWindowReply<Win32NativeCloseDestruction>
    ) {
        _ = mailbox.submit(.close(Win32NativeDestructionRequest(key: key, reply: reply)))
    }
}

/// Failure can be delivered by a foreign callback's failed wake. The native
/// owner checks the same terminal bit before any subsequent DestroyWindow.
/// No native resource is released from the callback thread.
final class Win32NativeDestructionRequest: Sendable {
    private enum Phase: Sendable {
        case waiting
        case committing
        case finished
    }
    let key: NativeWindowKey
    let reservation: Win32NativeCloseReservation?
    let reply: NativeWindowReply<Win32NativeCloseDestruction>
    private let phase = Mutex(Phase.waiting)

    init(reservation: Win32NativeCloseReservation, reply: NativeWindowReply<Win32NativeCloseDestruction>) {
        key = reservation.windowKey
        self.reservation = reservation
        self.reply = reply
    }

    init(key: NativeWindowKey, reply: NativeWindowReply<Win32NativeCloseDestruction>) {
        self.key = key
        reservation = nil
        self.reply = reply
    }

    var isTerminal: Bool {
        phase.withLock {
            if case .finished = $0 { return true }
            return false
        }
    }

    /// Arbitrates with a failed foreign-thread drain wake. Once this claim
    /// wins, only the actual native result may finish the request.
    func claimDestruction() -> Bool {
        phase.withLock { value in
            guard case .waiting = value else { return false }
            value = .committing
            return true
        }
    }

    /// Queue may hold its lock while claiming Phase and then Reply; Phase is
    /// released before Reply is entered. No callback or mailbox reentry occurs
    /// here. A caller must retain the request and delivery until after Queue
    /// unlocks, and retire a winning reservation before invoking its callback.
    func prepareCompletion(
        _ result: Result<Win32NativeCloseDestruction, NativeWindowOwnerFailure>
    ) -> (didClaim: Bool, delivery: NativeWindowReplyDelivery?) {
        let claimed = phase.withLock { value in
            if case .finished = value { return false }
            if case .committing = value, case .failure = result { return false }
            value = .finished
            return true
        }
        guard claimed else { return (false, nil) }
        return (true, reply.prepareCompletion(result))
    }

    @discardableResult
    func complete(
        _ result: Result<Win32NativeCloseDestruction, NativeWindowOwnerFailure>,
        beforeCompletion: () -> Void = {}
    ) -> Bool {
        let prepared = prepareCompletion(result)
        guard prepared.didClaim else { return false }
        // Retire mailbox reservations before arbitrary completion code can
        // reenter. A failure that lost to native commit never runs this hook.
        beforeCompletion()
        return prepared.delivery?.deliver() ?? false
    }
}

enum Win32NativePumpWork: Sendable {
    case create(Win32NativeWindowCreation)
    case command(any NativeWindowOwnerCommand)
    case close(Win32NativeDestructionRequest)
    case stop
}

let win32NativeWakeMessage = UINT(WM_APP + 0x121)

private func win32NativeThreadProcedure(_ raw: UnsafeMutableRawPointer?) -> DWORD {
    guard let raw else { return DWORD(ERROR_INVALID_PARAMETER) }
    let mailbox = Unmanaged<Win32NativePumpMailbox>.fromOpaque(raw).takeRetainedValue()
    mailbox.smokeObservation?.record(.nativeThreadEntered)
    let owner = Win32NativeLoop(mailbox: mailbox)
    return owner.run()
}
