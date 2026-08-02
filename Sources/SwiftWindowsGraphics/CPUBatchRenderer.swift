import Foundation
import SwiftWindowsCore

// MARK: - CPUBatchRenderer

/// A pure-software ``BatchRenderBackend`` implementation that rasterizes
/// ``GPUIScene`` using the CPU.  This is useful as:
///
/// 1. A **reference renderer** for pixel-perfect comparison against GPU backends
///    (e.g. D3D11BatchRenderer).  Any pixel diff between CPU and GPU output
///    indicates a bug in one of them — the claim is only worth what
///    `CrossBackendPixelParityTests` measures, and it holds because
///    `GPUIQuadCoverage`, `drawShadow` and `drawMaterialQuad` are
///    transcriptions of the shipping HLSL rather than paraphrases of it
///    (see `docs/GPURenderingPipeline.md` § 7a). The known residual is
///    texture filtering: the GPU samples glyphs and images through a
///    linear sampler, the rasterizer picks the nearest texel.
///
/// 2. A **headless / CI backend** that does not need a GPU, HWND, or windowing
///    system.  It can render off-screen to a ``BitmapSurface`` for testing.
///
/// 3. A **fallback backend** on platforms where GPU APIs are unavailable.
///
/// The renderer uses ``GPUIRawSceneRasterizer`` internally and stores the
/// last-rendered bitmap in ``lastRenderedBitmap`` for inspection.
///
/// Conforms to both ``BatchRenderBackend`` and ``RenderBackend`` so it can
/// serve as a complete software renderer for either the scene or frame path.
@MainActor
public final class CPUBatchRenderer: BatchRenderBackend, RenderBackend {
    public var backendDisplayName: String { "CPU REFERENCE" }

    /// A software rasterizer owns no device and presents to no swap chain,
    /// so it is never occluded and never owes a repaint. Stated explicitly
    /// because conforming to both backend protocols would otherwise inherit
    /// two identical defaults and satisfy neither.
    public var presentationState: PresentationState { PresentationState() }

    /// The most recently rendered frame, available after a successful
    /// ``render(scene:)`` call.  Tests and visual tooling read this to
    /// compare against GPU output.
    public private(set) var lastRenderedBitmap: BitmapSurface?

    /// The surface size last seen via ``attach(to:)`` or ``resize(to:)``.
    private var currentSize: IntSize = .zero

    public init() {}

    public func attach(to surface: SurfaceDescriptor) throws {
        currentSize = surface.pixelSize
    }

    public func resize(to size: IntSize) throws {
        currentSize = size
    }

    /// No platform resources to release; drops the retained frame so a
    /// detached renderer holds nothing and re-attaches from a clean state.
    public func detach() {
        currentSize = .zero
        lastRenderedBitmap = nil
    }

    public func bindResources(for scene: GPUIScene) {
        // CPU rasterizer reads atlas and image data directly from the scene;
        // no GPU resource binding is required.
    }

    public func render(scene: GPUIScene) throws {
        guard currentSize.width > 0, currentSize.height > 0 else {
            throw CPUBatchRendererError.invalidSize(currentSize)
        }

        let bitmap = GPUIRawSceneRasterizer.rasterize(scene, size: currentSize)
        lastRenderedBitmap = bitmap
    }

    public func render(frame: RenderFrame) throws {
        guard currentSize.width > 0, currentSize.height > 0 else {
            throw CPUBatchRendererError.invalidSize(currentSize)
        }

        let surfaceSize = Size(width: Double(currentSize.width), height: Double(currentSize.height))
        let scene = GPUIScene(from: frame, surfaceSize: surfaceSize)
        let bitmap = GPUIRawSceneRasterizer.rasterize(scene, size: currentSize)
        lastRenderedBitmap = bitmap
    }
}

// MARK: - Errors

public enum CPUBatchRendererError: Error, CustomStringConvertible {
    case invalidSize(IntSize)

    public var description: String {
        switch self {
        case .invalidSize(let size):
            return "CPUBatchRenderer cannot render to size \(size.width)×\(size.height)"
        }
    }
}
