import Foundation
import Synchronization

/// Identifies one native window lifetime, independently of a reusable OS handle.
public struct NativeWindowKey: Hashable, Sendable {
    public let windowID: UUID
    public let lifetimeID: UUID

    public init(windowID: UUID = UUID(), lifetimeID: UUID = UUID()) {
        self.windowID = windowID
        self.lifetimeID = lifetimeID
    }
}

public struct NativeWindowRequestID: Hashable, Sendable {
    public let rawValue: UUID

    public init(_ rawValue: UUID = UUID()) {
        self.rawValue = rawValue
    }
}

public struct NativeWindowAttachmentID: Hashable, Sendable {
    public let rawValue: UUID

    public init(_ rawValue: UUID = UUID()) {
        self.rawValue = rawValue
    }
}

/// Native geometry captured by the window owner, before sending work to the UI
/// actor. An external COM callback reads the most recently published revision;
/// it never waits for the native thread, which may itself be inside a COM call.
/// This is a published native observation, not a promise to sample the OS again
/// for every accessibility query.
public struct NativeWindowGeometry: Equatable, Sendable {
    public var revision: UInt64
    public var nativeSequence: UInt64
    public var clientSize: IntSize
    public var clientScreenOrigin: Point
    public var scaleFactor: Double
    public var effectiveScaleFactor: Double
    public var monitorRefreshRate: UInt32
    public var isMinimized: Bool
    public var isVisible: Bool
    public var isActive: Bool
    public var nativeModalDepth: Int

    public init(
        revision: UInt64, nativeSequence: UInt64, clientSize: IntSize,
        clientScreenOrigin: Point, scaleFactor: Double, effectiveScaleFactor: Double,
        monitorRefreshRate: UInt32, isMinimized: Bool, isVisible: Bool,
        isActive: Bool, nativeModalDepth: Int = 0
    ) {
        self.revision = revision
        self.nativeSequence = nativeSequence
        self.clientSize = clientSize
        self.clientScreenOrigin = clientScreenOrigin
        self.scaleFactor = scaleFactor
        self.effectiveScaleFactor = effectiveScaleFactor
        self.monitorRefreshRate = monitorRefreshRate
        self.isMinimized = isMinimized
        self.isVisible = isVisible
        self.isActive = isActive
        self.nativeModalDepth = nativeModalDepth
    }

    /// Matches the native mapper's endpoint rounding for representable Win32
    /// coordinates. Invalid geometry is explicit rather than a fabricated rect.
    public func clientRectToScreen(_ rect: Rect) -> Rect? {
        let left = (rect.origin.x * effectiveScaleFactor).rounded()
        let top = (rect.origin.y * effectiveScaleFactor).rounded()
        let right = ((rect.origin.x + rect.size.width) * effectiveScaleFactor).rounded()
        let bottom = ((rect.origin.y + rect.size.height) * effectiveScaleFactor).rounded()
        let coordinates = [left, top, right, bottom, clientScreenOrigin.x, clientScreenOrigin.y]
        guard effectiveScaleFactor.isFinite, effectiveScaleFactor > 0,
            clientScreenOrigin.x.rounded() == clientScreenOrigin.x,
            clientScreenOrigin.y.rounded() == clientScreenOrigin.y,
            coordinates.allSatisfy({ $0.isFinite && $0 >= Double(Int32.min) && $0 <= Double(Int32.max) })
        else { return nil }
        let screenLeft = left + clientScreenOrigin.x
        let screenTop = top + clientScreenOrigin.y
        let screenRight = right + clientScreenOrigin.x
        let screenBottom = bottom + clientScreenOrigin.y
        guard
            [screenLeft, screenTop, screenRight, screenBottom].allSatisfy({
                $0 >= Double(Int32.min) && $0 <= Double(Int32.max)
            })
        else { return nil }
        return Rect(
            origin: Point(x: screenLeft, y: screenTop),
            size: Size(width: screenRight - screenLeft, height: screenBottom - screenTop)
        )
    }
}

/// A surface generation changes when native size or scale invalidates commands
/// prepared for an earlier surface. It is separate from the HWND lifetime key.
public struct NativeWindowSurface: Equatable, Sendable {
    public let key: NativeWindowKey
    public let generation: UInt64
    public let descriptor: SurfaceDescriptor
    public let geometry: NativeWindowGeometry

    public init(
        key: NativeWindowKey, generation: UInt64, descriptor: SurfaceDescriptor,
        geometry: NativeWindowGeometry
    ) {
        self.key = key
        self.generation = generation
        self.descriptor = descriptor
        self.geometry = geometry
    }
}

/// Transport failures are distinct from a renderer's or UI action's result.
/// Native failures retain the API name and its real signed/unsigned code.
public enum NativeWindowOwnerFailure: Error, Equatable, Sendable {
    case unavailable
    case closed
    case closing
    case ownerStopped
    case staleWindow
    case staleSurface(expected: UInt64, actual: UInt64)
    case duplicateAttachment(NativeWindowAttachmentID)
    case missingAttachment(NativeWindowAttachmentID)
    /// A bounded transport refused new work. The limit describes that
    /// transport's accounting, not an operating-system memory allocation.
    case capacityExceeded(resource: String, limit: Int)
    case postFailed(code: UInt32)
    case native(operation: String, code: Int64)
    case execution(String)
}

/// Reads the owner's published immutable surface without calling the OS or
/// waiting for the native loop. Implementations must not hold their lock while
/// releasing an attachment, running a callback, or calling the UI actor.
public protocol NativeWindowSnapshotSource: Sendable {
    func snapshot() -> Result<NativeWindowSurface, NativeWindowOwnerFailure>
}

/// A claimed reply whose callback has not necessarily been delivered. The
/// native mailbox retains these values until it has released its queue lock.
/// Delivery has its own one-shot claim, so copying a reference cannot invoke
/// the callback twice. Neither lock spans a callback or its captured releases.
package final class NativeWindowReplyDelivery: Sendable {
    private let callback: Mutex<(@Sendable () -> Void)?>

    fileprivate init(_ callback: @escaping @Sendable () -> Void) {
        self.callback = Mutex(callback)
    }

    @discardableResult
    package func deliver() -> Bool {
        let completedCallback = callback.withLock { stored in
            let taken = stored
            stored = nil
            return taken
        }
        guard let completedCallback else { return false }
        completedCallback()
        return true
    }
}

/// The queue's failure authority for a command. Construction accepts only a
/// real Core reply; callers cannot install arbitrary claim logic. The stored
/// closures retain that reply, so identity cannot be reused while this value
/// is being compared with another admission.
public final class NativeWindowCommandReply: Sendable {
    package let identity: ObjectIdentifier
    private let completed: @Sendable () -> Bool
    private let prepare: @Sendable (NativeWindowOwnerFailure) -> NativeWindowReplyDelivery?

    public init<Value: Sendable>(_ reply: NativeWindowReply<Value>) {
        identity = ObjectIdentifier(reply)
        completed = { reply.isCompleted }
        prepare = { reply.prepareCompletion(.failure($0)) }
    }

    package var isCompleted: Bool { completed() }

    package func prepareFailure(_ failure: NativeWindowOwnerFailure) -> NativeWindowReplyDelivery? {
        prepare(failure)
    }

    @discardableResult
    public func reject(_ failure: NativeWindowOwnerFailure) -> Bool {
        guard let delivery = prepareFailure(failure) else { return false }
        return delivery.deliver()
    }
}

/// One terminal reply. A terminal claim takes the callback under a short lock;
/// delivery invokes it after unlocking. Claiming a reply does not prove callback
/// delivery, actor consumption, or native thread termination.
public final class NativeWindowReply<Value: Sendable>: Sendable {
    private let callback: Mutex<(@Sendable (Result<Value, NativeWindowOwnerFailure>) -> Void)?>

    public init(_ callback: @escaping @Sendable (Result<Value, NativeWindowOwnerFailure>) -> Void) {
        self.callback = Mutex(callback)
    }

    public var commandReply: NativeWindowCommandReply { NativeWindowCommandReply(self) }

    package var isCompleted: Bool { callback.withLock { $0 == nil } }

    /// The queue may call this while holding Queue -> Reply locks. Reply never
    /// enters Queue while locked. The returned delivery retains the callback
    /// before the stored reference is cleared, so its captures survive until
    /// the caller invokes or releases the delivery outside both locks.
    package func prepareCompletion(
        _ result: Result<Value, NativeWindowOwnerFailure>
    ) -> NativeWindowReplyDelivery? {
        let completedCallback = callback.withLock { stored in
            let taken = stored
            stored = nil
            return taken
        }
        guard let completedCallback else { return nil }
        return NativeWindowReplyDelivery { completedCallback(result) }
    }

    @discardableResult
    public func complete(_ result: Result<Value, NativeWindowOwnerFailure>) -> Bool {
        guard let delivery = prepareCompletion(result) else { return false }
        return delivery.deliver()
    }
}

public struct NativeWindowAttachmentDetachResult: Equatable, Sendable {
    public let isDetached: Bool
    public let failures: [NativeWindowOwnerFailure]

    public init(isDetached: Bool, failures: [NativeWindowOwnerFailure] = []) {
        self.isDetached = isDetached
        self.failures = failures
    }
}

/// Native resources are intentionally not Sendable. A factory creates them on
/// the native owner, every operation stays there, and that owner releases them.
/// Quiescence stops new admission; drain includes the complete native callback,
/// not merely the actor portion of a synchronous accessibility request.
public protocol NativeWindowOwnerAttachment: AnyObject {
    func beginQuiescence()
    var isQuiescent: Bool { get }
    func detach() -> NativeWindowAttachmentDetachResult
}

extension NativeWindowOwnerAttachment {
    public func beginQuiescence() {}
    public var isQuiescent: Bool { true }
}

public protocol NativeWindowOwnerAttachmentFactory: Sendable {
    var attachmentID: NativeWindowAttachmentID { get }
    func makeAttachment(in context: any NativeWindowOwnerContext) throws -> any NativeWindowOwnerAttachment
}

/// Available only while executing on the native owner. No context or resource
/// obtained from it may be captured by an actor task. The wake is the exception:
/// it is an owned, nonblocking signal used when an admitted callback drains.
public protocol NativeWindowOwnerContext: AnyObject {
    var surface: NativeWindowSurface { get }
    var snapshotSource: any NativeWindowSnapshotSource { get }
    var wake: @Sendable () -> Result<Void, NativeWindowOwnerFailure> { get }

    func attachment(for id: NativeWindowAttachmentID) -> (any NativeWindowOwnerAttachment)?
    func install(_ attachment: any NativeWindowOwnerAttachment, for id: NativeWindowAttachmentID) throws
    func removeAttachment(for id: NativeWindowAttachmentID) -> (any NativeWindowOwnerAttachment)?
    func withNativeModal<Result>(_ body: () throws -> Result) rethrows -> Result
}

/// A value command owns its reply and all inputs. Admission is not success:
/// execute must complete the real result. Queued failures claim the Core reply
/// before delivery; execution-error and direct-sink paths may call reject
/// outside locks. Commands must not call or synchronously wait for the actor.
/// The only N-to-A waits are explicit query transactions whose actor body
/// cannot require any native progress.
///
/// Each command exposes the same stable Core reply that receives its execution
/// result. The queue reads this capability before locking and claims queued
/// failures through it before running any callback. Queue-rejection cleanup
/// belongs in that reply's callback; a custom reject implementation is only an
/// execution-error or direct-sink hook, not a queued-rejection hook.
public protocol NativeWindowOwnerCommand: Sendable {
    var windowKey: NativeWindowKey { get }
    var requestID: NativeWindowRequestID { get }
    var commandReply: NativeWindowCommandReply { get }
    var expectedSurfaceGeneration: UInt64? { get }
    func execute(in context: any NativeWindowOwnerContext) throws
    func reject(_ failure: NativeWindowOwnerFailure)
}

extension NativeWindowOwnerCommand {
    public var expectedSurfaceGeneration: UInt64? { nil }

    public func reject(_ failure: NativeWindowOwnerFailure) {
        commandReply.reject(failure)
    }
}

public enum NativeWindowSubmission: Equatable, Sendable {
    case accepted
    case rejected(NativeWindowOwnerFailure)
}

public protocol NativeWindowCommandSink: Sendable {
    @discardableResult
    func submit(_ command: any NativeWindowOwnerCommand) -> NativeWindowSubmission
}
