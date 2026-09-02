import SwiftWindowsCore
import SwiftWindowsGraphics

/// A configuration value. Both kernels are constructed only when the native
/// window owner calls makeBackend; no MainActor renderer is captured here.
public struct D3D11NativePresentationBackendFactory: NativePresentationBackendFactory {
    public let frameConfiguration: D3D11RendererConfiguration

    public init(frameConfiguration: D3D11RendererConfiguration = D3D11RendererConfiguration()) {
        self.frameConfiguration = frameConfiguration
    }

    public var factoryName: String { "D3D11 GPU" }
    public var capabilities: RenderBackendCapabilities { .graphicsDeviceWindow }

    public func makeBackend() -> any NativePresentationBackend {
        D3D11NativePresentationBackend(frameConfiguration: frameConfiguration)
    }
}

private enum D3D11NativePresentationError: Error, ClassifiedPresentationFailure {
    case pathNotAttached(NativePresentationPath)

    var presentationFailureKind: PresentationFailureKind { .transient }
}

/// Owns the same kernels used by the actor compatibility facades, on the HWND
/// owner instead. Selecting one path first releases both paths' resources.
/// Inactive kernels never keep a second flip-model swap chain on the HWND.
private final class D3D11NativePresentationBackend: NativePresentationBackend, NativeDisplayAcquisitionBackend {
    private let frame: D3D11FrameKernel
    private let batch: D3D11BatchKernel
    private var selectedPath: NativePresentationPath?
    private var configuration = NativePresentationConfiguration()
    private var configurationResult = NativePresentationConfigurationResult()
    private var adoptedFramePacing = false
    private var adoptedBatchPacing = false
    private var lastBindSeconds: Double?

    init(frameConfiguration: D3D11RendererConfiguration) {
        frame = D3D11FrameKernel(configuration: frameConfiguration, usesCapturedSurfaceScale: true)
        batch = D3D11BatchKernel()
    }

    func beginDisplayAcquisition(_ context: NativeDisplayAcquisition.Context) -> Bool {
        batch.beginDisplayAcquisition(context)
    }

    func endDisplayAcquisition(_ context: NativeDisplayAcquisition.Context) {
        batch.endDisplayAcquisition(context)
    }

    func attach(to surface: SurfaceDescriptor, path: NativePresentationPath) throws {
        _ = detach()
        selectedPath = path
        do {
            switch path {
            case .scene: try batch.attach(to: surface)
            case .frame: try frame.attach(to: surface)
            }
            apply(configuration)
        } catch {
            // isAttached is set only after every allocation succeeds. A
            // failure before that point still owns partial native resources.
            _ = detach()
            throw error
        }
    }

    func resize(to surface: SurfaceDescriptor) throws {
        lastBindSeconds = nil
        switch selectedPath {
        case .scene:
            guard batch.isAttached else { throw D3D11NativePresentationError.pathNotAttached(.scene) }
            try batch.resize(to: surface.pixelSize)
            batch.rebindDisplayAcquisitionSurface()
        case .frame:
            guard frame.isAttached else { throw D3D11NativePresentationError.pathNotAttached(.frame) }
            try frame.resize(to: surface)
        case nil:
            throw D3D11NativePresentationError.pathNotAttached(.scene)
        }
    }

    func render(scene: GPUIScene) throws {
        lastBindSeconds = nil
        guard selectedPath == .scene, batch.isAttached else {
            throw D3D11NativePresentationError.pathNotAttached(.scene)
        }
        let started = PlatformClock.now()
        batch.bindResources(for: scene)
        lastBindSeconds = PlatformClock.now() - started
        batch.displayAcquisitionWillRender()
        try batch.render(scene: scene)
    }

    func render(frame: RenderFrame) throws {
        lastBindSeconds = nil
        guard selectedPath == .frame, self.frame.isAttached else {
            throw D3D11NativePresentationError.pathNotAttached(.frame)
        }
        batch.invalidateDisplayAcquisition(.unsupportedFramePath)
        try self.frame.render(frame: frame)
    }

    @discardableResult
    func configure(_ update: NativePresentationConfiguration) -> NativePresentationConfigurationResult {
        configuration.merge(update)
        apply(update)
        return configurationResult
    }

    private func apply(_ update: NativePresentationConfiguration) {
        configurationResult = NativePresentationConfigurationResult()
        if let interval = update.displayFrameInterval {
            frame.setDisplayFrameInterval(interval)
            batch.setDisplayFrameInterval(interval)
        }
        if let enabled = update.presentsWithVSync {
            frame.vsyncEnabled = enabled
            let batchAccepted = batch.setPresentsWithVSync(enabled)
            configurationResult.presentsWithVSyncAccepted = selectedPath == .frame ? true : batchAccepted
        }
        if let enabled = update.capturesPresentedFrames {
            let accepted = batch.setCapturesPresentedFrames(enabled)
            configurationResult.capturesPresentedFramesAccepted = selectedPath == .scene ? accepted : false
        }
        if let enabled = update.gpuFrameTimingEnabled {
            let accepted = batch.setGPUFrameTimingEnabled(enabled)
            configurationResult.gpuFrameTimingEnabledAccepted = selectedPath == .scene ? accepted : false
        }
        if update.adoptRememberedSelfPacing {
            if !adoptedFramePacing {
                frame.adoptRememberedSelfPacing()
                adoptedFramePacing = true
            }
            if !adoptedBatchPacing {
                batch.adoptRememberedSelfPacing()
                adoptedBatchPacing = true
            }
        }
    }

    func takeSnapshot() -> NativePresentationSnapshot {
        // These are bounded native query reads. They never run in an actor
        // property getter, and old device results retain their issuing IDs.
        let completedTimings = batch.takeCompletedGPUFrameTimings()
        let capturedFrame = batch.takeCapturedPresentedFrame()
        switch selectedPath {
        case .scene:
            return NativePresentationSnapshot(
                path: .scene, isAttached: batch.isAttached,
                backendDisplayName: batch.backendDisplayName,
                backendStatusDescription: batch.isAttached ? "D3D11 BATCH ACTIVE" : "D3D11 BATCH DETACHED",
                presentationState: batch.presentationState, presentPacing: batch.presentPacing,
                backendDiagnostics: batch.backendDiagnostics,
                lastFrameSubmission: batch.lastFrameSubmission,
                gpuFrameTimingDiagnostics: batch.gpuFrameTimingDiagnostics,
                completedGPUFrameTimings: completedTimings, capturedPresentedFrame: capturedFrame,
                configurationResult: configurationResult, bindSeconds: lastBindSeconds)
        case .frame:
            return NativePresentationSnapshot(
                path: .frame, isAttached: frame.isAttached,
                backendDisplayName: frame.backendDisplayName,
                backendStatusDescription: frame.backendStatusDescription,
                presentationState: frame.presentationState, presentPacing: frame.presentPacing,
                lastFrameSubmission: frame.lastFrameSubmission,
                completedGPUFrameTimings: completedTimings, capturedPresentedFrame: capturedFrame,
                configurationResult: configurationResult)
        case nil:
            return NativePresentationSnapshot(
                isAttached: false, backendDisplayName: "D3D11 GPU",
                backendStatusDescription: "D3D11 DETACHED", completedGPUFrameTimings: completedTimings,
                capturedPresentedFrame: capturedFrame, configurationResult: configurationResult)
        }
    }

    func detach() -> NativeWindowAttachmentDetachResult {
        // Both releases are owner-confined and complete before the HWND owner
        // receives its acknowledgement. No lock spans ClearState/Flush/Release.
        batch.detach()
        frame.detach()
        lastBindSeconds = nil
        return NativeWindowAttachmentDetachResult(isDetached: !batch.isAttached && !frame.isAttached)
    }
}
