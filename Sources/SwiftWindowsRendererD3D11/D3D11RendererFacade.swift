import SwiftWindowsCore
import SwiftWindowsGraphics

/// MainActor compatibility surface for the existing frame backend API.
/// Native presentation constructs its own kernel on its owning thread;
/// this facade never transfers its mutable COM owner between executors.
@MainActor
public final class D3D11Renderer: RenderBackend {
    private let kernel: D3D11FrameKernel

    public init(configuration: D3D11RendererConfiguration = D3D11RendererConfiguration()) {
        kernel = D3D11FrameKernel(configuration: configuration)
    }

    public var isAttached: Bool { kernel.isAttached }
    public var isDirect2DEnabled: Bool { kernel.isDirect2DEnabled }
    public var backendDisplayName: String { kernel.backendDisplayName }
    public var backendStatusDescription: String { kernel.backendStatusDescription }
    public var presentationState: PresentationState { kernel.presentationState }
    public var presentPacing: PresentPacingStatus { kernel.presentPacing }

    public var vsyncEnabled: Bool {
        get { kernel.vsyncEnabled }
        set { kernel.vsyncEnabled = newValue }
    }

    public func attach(to surface: SurfaceDescriptor) throws {
        try kernel.attach(to: surface)
    }

    public func resize(to size: IntSize) throws {
        try kernel.resize(to: size)
    }

    public func render(frame: RenderFrame) throws {
        try kernel.render(frame: frame)
    }

    public func detach() {
        kernel.detach()
    }

    public func setDisplayFrameInterval(_ seconds: Double) {
        kernel.setDisplayFrameInterval(seconds)
    }

    public func adoptRememberedSelfPacing() {
        kernel.adoptRememberedSelfPacing()
    }

    var deviceGeneration: UInt64 { kernel.deviceGeneration }

    var deviceLostBackoffHandler: (Double) -> Void {
        get { kernel.deviceLostBackoffHandler }
        set { kernel.deviceLostBackoffHandler = newValue }
    }

    func simulateDeviceLossForTesting() throws {
        try kernel.simulateDeviceLossForTesting()
    }

    static func validateShaderSourceForTesting() throws {
        try D3D11FrameKernel.validateShaderSourceForTesting()
    }

    static func validateDirect2DInteropForTesting() throws {
        try D3D11FrameKernel.validateDirect2DInteropForTesting()
    }
}
