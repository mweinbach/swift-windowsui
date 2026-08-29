import SwiftWindowsCore
import Synchronization

/// The native owner keeps both paths, but only one may own the window's swap chain.
public enum NativePresentationPath: String, Equatable, Sendable {
    case scene
    case frame
}

/// Optional requests leave the corresponding setting unchanged. The adoption
/// request seeds an observed pacing verdict; it does not claim a new measurement.
public struct NativePresentationConfiguration: Equatable, Sendable {
    public var displayFrameInterval: Double?
    public var presentsWithVSync: Bool?
    public var capturesPresentedFrames: Bool?
    public var gpuFrameTimingEnabled: Bool?
    public var adoptRememberedSelfPacing: Bool

    public init(
        displayFrameInterval: Double? = nil,
        presentsWithVSync: Bool? = nil,
        capturesPresentedFrames: Bool? = nil,
        gpuFrameTimingEnabled: Bool? = nil,
        adoptRememberedSelfPacing: Bool = false
    ) {
        self.displayFrameInterval = displayFrameInterval
        self.presentsWithVSync = presentsWithVSync
        self.capturesPresentedFrames = capturesPresentedFrames
        self.gpuFrameTimingEnabled = gpuFrameTimingEnabled
        self.adoptRememberedSelfPacing = adoptRememberedSelfPacing
    }

    /// Retains requested settings for a later path switch or device attachment.
    public mutating func merge(_ update: Self) {
        if let value = update.displayFrameInterval { displayFrameInterval = value }
        if let value = update.presentsWithVSync { presentsWithVSync = value }
        if let value = update.capturesPresentedFrames { capturesPresentedFrames = value }
        if let value = update.gpuFrameTimingEnabled { gpuFrameTimingEnabled = value }
        adoptRememberedSelfPacing = adoptRememberedSelfPacing || update.adoptRememberedSelfPacing
    }
}

/// The native setters' actual return values. Nil means the setting was not
/// requested; false means the selected path did not honour that request.
public struct NativePresentationConfigurationResult: Equatable, Sendable {
    public var presentsWithVSyncAccepted: Bool?
    public var capturesPresentedFramesAccepted: Bool?
    public var gpuFrameTimingEnabledAccepted: Bool?

    public init(
        presentsWithVSyncAccepted: Bool? = nil,
        capturesPresentedFramesAccepted: Bool? = nil,
        gpuFrameTimingEnabledAccepted: Bool? = nil
    ) {
        self.presentsWithVSyncAccepted = presentsWithVSyncAccepted
        self.capturesPresentedFramesAccepted = capturesPresentedFramesAccepted
        self.gpuFrameTimingEnabledAccepted = gpuFrameTimingEnabledAccepted
    }
}

/// A completed native observation. Captured pixels and GPU query results are
/// consumed once on the owner. A submitted frame is still not display completion.
public struct NativePresentationSnapshot: Equatable, Sendable {
    public var path: NativePresentationPath?
    public var isAttached: Bool
    public var backendDisplayName: String
    public var backendStatusDescription: String
    public var presentationState: PresentationState
    public var presentPacing: PresentPacingStatus
    public var backendDiagnostics: BatchBackendDiagnostics?
    public var lastFrameSubmission: BackendFrameSubmission?
    public var gpuFrameTimingDiagnostics: GPUFrameTimingDiagnostics?
    public var completedGPUFrameTimings: [GPUFrameTimingResult]
    public var capturedPresentedFrame: BitmapSurface?
    public var configurationResult: NativePresentationConfigurationResult
    /// Native resource-binding time for the last scene attempt, when measured.
    public var bindSeconds: Double?

    public init(
        path: NativePresentationPath? = nil,
        isAttached: Bool,
        backendDisplayName: String,
        backendStatusDescription: String,
        presentationState: PresentationState = PresentationState(),
        presentPacing: PresentPacingStatus = PresentPacingStatus(),
        backendDiagnostics: BatchBackendDiagnostics? = nil,
        lastFrameSubmission: BackendFrameSubmission? = nil,
        gpuFrameTimingDiagnostics: GPUFrameTimingDiagnostics? = nil,
        completedGPUFrameTimings: [GPUFrameTimingResult] = [],
        capturedPresentedFrame: BitmapSurface? = nil,
        configurationResult: NativePresentationConfigurationResult = NativePresentationConfigurationResult(),
        bindSeconds: Double? = nil
    ) {
        self.path = path
        self.isAttached = isAttached
        self.backendDisplayName = backendDisplayName
        self.backendStatusDescription = backendStatusDescription
        self.presentationState = presentationState
        self.presentPacing = presentPacing
        self.backendDiagnostics = backendDiagnostics
        self.lastFrameSubmission = lastFrameSubmission
        self.gpuFrameTimingDiagnostics = gpuFrameTimingDiagnostics
        self.completedGPUFrameTimings = completedGPUFrameTimings
        self.capturedPresentedFrame = capturedPresentedFrame
        self.configurationResult = configurationResult
        self.bindSeconds = bindSeconds
    }
}

/// Native resources are created and remain on one native owner. This is not an
/// actor backend and is deliberately not Sendable. Every operation, including
/// reads that poll native query objects, runs on that same owner.
public protocol NativePresentationBackend: AnyObject {
    func attach(to surface: SurfaceDescriptor, path: NativePresentationPath) throws
    func resize(to surface: SurfaceDescriptor) throws
    func render(scene: GPUIScene) throws
    func render(frame: RenderFrame) throws
    @discardableResult
    func configure(_ configuration: NativePresentationConfiguration) -> NativePresentationConfigurationResult
    func takeSnapshot() -> NativePresentationSnapshot
    func detach() -> NativeWindowAttachmentDetachResult
}

/// Carries configuration, never a renderer instance or a UI actor object. The
/// native owner calls makeBackend; constructing a factory performs no native work.
public protocol NativePresentationBackendFactory: Sendable {
    var factoryName: String { get }
    var capabilities: RenderBackendCapabilities { get }
    func makeBackend() -> any NativePresentationBackend
}

public enum NativePresentationOperationKind: String, Equatable, Sendable {
    case install
    case attach
    case resize
    case renderScene
    case renderFrame
    case configure
    case poll
    case detach
}

public enum NativePresentationOperation: Sendable {
    case install(
        factory: any NativePresentationBackendFactory,
        path: NativePresentationPath,
        configuration: NativePresentationConfiguration
    )
    case attach(path: NativePresentationPath)
    case resize
    case renderScene(GPUIScene)
    case renderFrame(RenderFrame)
    case configure(NativePresentationConfiguration)
    case poll
    case detach(removeAttachment: Bool)

    public var kind: NativePresentationOperationKind {
        switch self {
        case .install: return .install
        case .attach: return .attach
        case .resize: return .resize
        case .renderScene: return .renderScene
        case .renderFrame: return .renderFrame
        case .configure: return .configure
        case .poll: return .poll
        case .detach: return .detach
        }
    }

    fileprivate var requiresSurfaceGeneration: Bool {
        switch self {
        case .install, .attach, .resize, .renderScene, .renderFrame: return true
        case .configure, .poll, .detach: return false
        }
    }
}

/// Retains the concrete error, including a backend's HRESULT and classification.
/// Transport rejection stays in NativeWindowReply's outer failure instead.
public struct NativePresentationFailure: Error, ClassifiedPresentationFailure, CustomStringConvertible, Sendable {
    public let underlyingError: any Error
    public let cleanupResult: NativeWindowAttachmentDetachResult?

    public init(_ underlyingError: any Error) {
        if let attachmentError = underlyingError as? NativePresentationAttachmentError,
            case .attachFailed(let primary, let cleanup) = attachmentError
        {
            self.underlyingError = primary
            self.cleanupResult = cleanup
        } else {
            self.underlyingError = underlyingError
            self.cleanupResult = nil
        }
    }

    public var presentationFailureKind: PresentationFailureKind {
        PresentationFailureKind.classifying(underlyingError)
    }

    public var description: String {
        let primary = String(describing: underlyingError)
        guard let cleanupResult else { return primary }
        return "\(primary) Native cleanup: \(cleanupResult)."
    }
}

public struct NativePresentationReceipt: Sendable {
    public let requestID: NativeWindowRequestID
    public let attachmentID: NativeWindowAttachmentID
    public let surface: NativeWindowSurface
    public let operation: NativePresentationOperationKind
    public let isAttachmentInstalled: Bool
    public let snapshot: NativePresentationSnapshot
    public let failure: NativePresentationFailure?
    public let startedAtSeconds: Double
    public let completedAtSeconds: Double

    public var bindSeconds: Double? { operation == .renderScene ? snapshot.bindSeconds : nil }

    public init(
        requestID: NativeWindowRequestID, attachmentID: NativeWindowAttachmentID,
        surface: NativeWindowSurface, operation: NativePresentationOperationKind,
        isAttachmentInstalled: Bool, snapshot: NativePresentationSnapshot,
        failure: NativePresentationFailure? = nil,
        startedAtSeconds: Double, completedAtSeconds: Double
    ) {
        self.requestID = requestID
        self.attachmentID = attachmentID
        self.surface = surface
        self.operation = operation
        self.isAttachmentInstalled = isAttachmentInstalled
        self.snapshot = snapshot
        self.failure = failure
        self.startedAtSeconds = startedAtSeconds
        self.completedAtSeconds = completedAtSeconds
    }
}

public struct NativePresentationTeardownReceipt: Equatable, Sendable {
    public let windowKey: NativeWindowKey
    public let attachmentID: NativeWindowAttachmentID
    public let completedAtSeconds: Double
    public let result: NativeWindowAttachmentDetachResult
    public let snapshot: NativePresentationSnapshot
}

/// Final owner teardown cannot wait for a UI callback. The owner publishes this
/// value before returning its detach acknowledgement; the UI takes it once after
/// the native close acknowledgement. No resource or actor reference is stored.
public final class NativePresentationTeardownStore: Sendable {
    private let latest = Mutex<NativePresentationTeardownReceipt?>(nil)

    public init() {}

    public func takeReceipt() -> NativePresentationTeardownReceipt? {
        latest.withLock { value in
            let taken = value
            value = nil
            return taken
        }
    }

    fileprivate func publish(_ receipt: NativePresentationTeardownReceipt) {
        let previous = latest.withLock { value in
            let previous = value
            value = receipt
            return previous
        }
        withExtendedLifetime(previous) {}
    }
}

/// A renderer owns no synchronous actor callback. The reply completes after
/// native execution; a UI consumer schedules its actor handling independently.
/// For attach/resize/render, a missing or stale surface generation is rejected
/// before the backend is touched. Detach instead follows the lifetime key.
public struct NativePresentationCommand: NativeWindowOwnerCommand {
    public let windowKey: NativeWindowKey
    public let requestID: NativeWindowRequestID
    public let expectedSurfaceGeneration: UInt64?
    public let attachmentID: NativeWindowAttachmentID
    public let operation: NativePresentationOperation
    public let reply: NativeWindowReply<NativePresentationReceipt>
    public let teardownStore: NativePresentationTeardownStore?
    public var commandReply: NativeWindowCommandReply { reply.commandReply }

    public init(
        windowKey: NativeWindowKey, attachmentID: NativeWindowAttachmentID,
        expectedSurfaceGeneration: UInt64?, requestID: NativeWindowRequestID = NativeWindowRequestID(),
        operation: NativePresentationOperation, reply: NativeWindowReply<NativePresentationReceipt>,
        teardownStore: NativePresentationTeardownStore? = nil
    ) {
        self.windowKey = windowKey
        self.attachmentID = attachmentID
        self.expectedSurfaceGeneration = expectedSurfaceGeneration
        self.requestID = requestID
        self.operation = operation
        self.reply = reply
        self.teardownStore = teardownStore
    }

    public func reject(_ failure: NativeWindowOwnerFailure) {
        reply.complete(.failure(failure))
    }

    public func execute(in context: any NativeWindowOwnerContext) throws {
        let startedAtSeconds = PlatformClock.now()
        let surface = context.surface
        guard surface.key == windowKey else { throw NativeWindowOwnerFailure.staleWindow }
        if operation.requiresSurfaceGeneration, expectedSurfaceGeneration == nil {
            throw NativeWindowOwnerFailure.execution("Presentation work requires a captured surface generation.")
        }
        if let expectedSurfaceGeneration, expectedSurfaceGeneration != surface.generation {
            throw NativeWindowOwnerFailure.staleSurface(
                expected: expectedSurfaceGeneration, actual: surface.generation)
        }

        let attachment: NativePresentationAttachment
        if case .install(let factory, _, _) = operation {
            guard context.attachment(for: attachmentID) == nil else {
                throw NativeWindowOwnerFailure.duplicateAttachment(attachmentID)
            }
            let builder = NativePresentationAttachmentFactory(
                attachmentID: attachmentID, factory: factory, teardownStore: teardownStore)
            guard let built = try builder.makeAttachment(in: context) as? NativePresentationAttachment else {
                throw NativeWindowOwnerFailure.execution("Native presentation factory returned a different attachment.")
            }
            // Install before the first native call: reentrant close sees the
            // attachment's active operation and cannot destroy its surface.
            try context.install(built, for: attachmentID)
            attachment = built
        } else {
            guard let existing = context.attachment(for: attachmentID) as? NativePresentationAttachment else {
                throw NativeWindowOwnerFailure.missingAttachment(attachmentID)
            }
            attachment = existing
        }

        let failure = try attachment.perform(operation, on: surface)
        // Snapshot polling is native work too. Keep the attachment registered
        // until that work has left its quiescence gate.
        var snapshot = attachment.takeSnapshot()
        if operation.kind == .renderScene || operation.kind == .renderFrame, !attachment.didInvokeRenderer {
            // A path/lifecycle precondition can fail before the backend's
            // render method resets its attempt data. Do not attribute the
            // preceding frame's submission, pixels or counters to this request.
            snapshot.lastFrameSubmission = BackendFrameSubmission(outcome: .skipped, gpuTimingStatus: .notIssued)
            snapshot.bindSeconds = nil
            snapshot.capturedPresentedFrame = nil
            if var diagnostics = snapshot.backendDiagnostics {
                diagnostics.lastSubmitSeconds = 0
                diagnostics.lastPresentSeconds = 0
                diagnostics.lastDrawCallCount = 0
                diagnostics.lastDrawnInstanceCount = 0
                snapshot.backendDiagnostics = diagnostics
            }
        }
        var isInstalled = true
        if case .detach(let remove) = operation, remove, failure == nil {
            _ = context.removeAttachment(for: attachmentID)
            isInstalled = false
        }
        let completedAtSeconds = PlatformClock.now()
        reply.complete(
            .success(
                NativePresentationReceipt(
                    requestID: requestID, attachmentID: attachmentID,
                    surface: surface, operation: operation.kind,
                    isAttachmentInstalled: isInstalled, snapshot: snapshot, failure: failure,
                    startedAtSeconds: startedAtSeconds, completedAtSeconds: completedAtSeconds)))
    }
}

private struct NativePresentationAttachmentFactory: NativeWindowOwnerAttachmentFactory {
    let attachmentID: NativeWindowAttachmentID
    let factory: any NativePresentationBackendFactory
    let teardownStore: NativePresentationTeardownStore?

    func makeAttachment(in context: any NativeWindowOwnerContext) throws -> any NativeWindowOwnerAttachment {
        NativePresentationAttachment(
            windowKey: context.surface.key, attachmentID: attachmentID,
            factory: factory, wake: context.wake, teardownStore: teardownStore)
    }
}

private enum NativePresentationAttachmentError: Error, ClassifiedPresentationFailure {
    case noAttachedSurface
    case pathMismatch(expected: NativePresentationPath, actual: NativePresentationPath?)
    case detachFailed(NativeWindowAttachmentDetachResult)
    case attachFailed(primary: any Error, cleanup: NativeWindowAttachmentDetachResult)

    var presentationFailureKind: PresentationFailureKind {
        if case .attachFailed(let primary, _) = self { return PresentationFailureKind.classifying(primary) }
        return .transient
    }
}

/// The owner stores this object. It never appears in a Sendable payload.
private final class NativePresentationAttachment: NativeWindowOwnerAttachment {
    private let windowKey: NativeWindowKey
    private let attachmentID: NativeWindowAttachmentID
    private let factory: any NativePresentationBackendFactory
    private var backend: (any NativePresentationBackend)?
    private let wake: @Sendable () -> Result<Void, NativeWindowOwnerFailure>
    private let teardownStore: NativePresentationTeardownStore?
    private var attachedSurface: NativeWindowSurface?
    private var path: NativePresentationPath?
    private var isExecuting = false
    private var isQuiescing = false
    private(set) var didInvokeRenderer = false

    init(
        windowKey: NativeWindowKey, attachmentID: NativeWindowAttachmentID,
        factory: any NativePresentationBackendFactory,
        wake: @escaping @Sendable () -> Result<Void, NativeWindowOwnerFailure>,
        teardownStore: NativePresentationTeardownStore?
    ) {
        self.windowKey = windowKey
        self.attachmentID = attachmentID
        self.factory = factory
        self.wake = wake
        self.teardownStore = teardownStore
    }

    func beginQuiescence() { isQuiescing = true }
    var isQuiescent: Bool { !isExecuting }

    func detach() -> NativeWindowAttachmentDetachResult {
        guard !isExecuting else {
            return NativeWindowAttachmentDetachResult(isDetached: false, failures: [.closing])
        }
        isExecuting = true
        defer { finishExecution() }
        let result = backend?.detach() ?? NativeWindowAttachmentDetachResult(isDetached: true)
        if result.isDetached {
            attachedSurface = nil
            path = nil
        }
        // detach has invalidated the queries, so this drains their terminal
        // values without touching a released native context.
        let snapshot = backendSnapshot()
        teardownStore?.publish(
            NativePresentationTeardownReceipt(
                windowKey: windowKey, attachmentID: attachmentID,
                completedAtSeconds: PlatformClock.now(), result: result, snapshot: snapshot))
        return result
    }

    func perform(_ operation: NativePresentationOperation, on surface: NativeWindowSurface) throws
        -> NativePresentationFailure?
    {
        guard surface.key == windowKey else { throw NativeWindowOwnerFailure.staleWindow }
        guard !isExecuting else {
            throw NativeWindowOwnerFailure.execution("Native presentation execution cannot reenter.")
        }
        if isQuiescing, operation.kind != .detach { throw NativeWindowOwnerFailure.closing }

        // An accepted resize updates the attachment lease. Rendering cannot
        // use an older buffer size merely because the HWND itself still lives.
        switch operation {
        case .renderScene, .renderFrame:
            if let attachedSurface, attachedSurface.key != surface.key {
                throw NativeWindowOwnerFailure.staleWindow
            }
            if let attachedSurface, attachedSurface.generation != surface.generation {
                throw NativeWindowOwnerFailure.staleSurface(
                    expected: attachedSurface.generation, actual: surface.generation)
            }
        default: break
        }

        isExecuting = true
        defer { finishExecution() }
        didInvokeRenderer = false
        if backend == nil {
            guard case .install = operation else {
                throw NativeWindowOwnerFailure.execution("The native presentation backend has not been constructed.")
            }
            // The attachment and its active-operation gate already exist in
            // the owner. Even a custom constructor that calls native APIs is
            // therefore covered by the close/drain lease.
            backend = factory.makeBackend()
            if isQuiescing { throw NativeWindowOwnerFailure.closing }
        }
        guard let backend else {
            throw NativeWindowOwnerFailure.execution("Native presentation construction returned no backend.")
        }
        do {
            switch operation {
            case .install(_, let requestedPath, let configuration):
                backend.configure(configuration)
                try attach(path: requestedPath, surface: surface)
            case .attach(let requestedPath):
                try attach(path: requestedPath, surface: surface)
            case .resize:
                guard attachedSurface != nil else { throw NativePresentationAttachmentError.noAttachedSurface }
                try backend.resize(to: surface.descriptor)
                attachedSurface = surface
            case .renderScene(let scene):
                guard attachedSurface != nil else { throw NativePresentationAttachmentError.noAttachedSurface }
                guard path == .scene else {
                    throw NativePresentationAttachmentError.pathMismatch(expected: .scene, actual: path)
                }
                didInvokeRenderer = true
                try backend.render(scene: scene)
            case .renderFrame(let frame):
                guard attachedSurface != nil else { throw NativePresentationAttachmentError.noAttachedSurface }
                guard path == .frame else {
                    throw NativePresentationAttachmentError.pathMismatch(expected: .frame, actual: path)
                }
                didInvokeRenderer = true
                try backend.render(frame: frame)
            case .configure(let configuration):
                backend.configure(configuration)
            case .poll:
                break
            case .detach:
                let result = backend.detach()
                if result.isDetached {
                    attachedSurface = nil
                    path = nil
                }
                guard result.isDetached, result.failures.isEmpty else {
                    throw NativePresentationAttachmentError.detachFailed(result)
                }
            }
            return nil
        } catch {
            return NativePresentationFailure(error)
        }
    }

    func takeSnapshot() -> NativePresentationSnapshot {
        // Polling can call a native query object. Keep the same reentry gate
        // until all such reads finish, not only until render returns.
        precondition(!isExecuting)
        isExecuting = true
        defer { finishExecution() }
        return backendSnapshot()
    }

    private func attach(path requestedPath: NativePresentationPath, surface: NativeWindowSurface) throws {
        guard let backend else { throw NativePresentationAttachmentError.noAttachedSurface }
        let detached = backend.detach()
        guard detached.isDetached, detached.failures.isEmpty else {
            throw NativePresentationAttachmentError.detachFailed(detached)
        }
        attachedSurface = nil
        path = nil
        do {
            try backend.attach(to: surface.descriptor, path: requestedPath)
            attachedSurface = surface
            path = requestedPath
        } catch {
            // attach may allocate resources before isAttached becomes true.
            // Always release that partial state, while retaining the installed
            // attachment so the host can try its other renderer path.
            let detached = backend.detach()
            guard detached.isDetached, detached.failures.isEmpty else {
                throw NativePresentationAttachmentError.attachFailed(primary: error, cleanup: detached)
            }
            throw error
        }
    }

    private func backendSnapshot() -> NativePresentationSnapshot {
        backend?.takeSnapshot()
            ?? NativePresentationSnapshot(
                isAttached: false, backendDisplayName: factory.factoryName,
                backendStatusDescription: "NATIVE PRESENTER NOT CONSTRUCTED")
    }

    private func finishExecution() {
        isExecuting = false
        if isQuiescing { _ = wake() }
    }
}
