import Foundation

import SwiftWindowsCore
import SwiftWindowsGraphics

#if os(Windows)
    import WinSDK
#endif

// MARK: - Software presentation (the GPU-less window path)
//
// `CPUBatchRenderer` rasterizes a `GPUIScene` into memory and stops there,
// which is exactly right for `swift-windowsui-snapshot` and the cross-backend
// parity suite and exactly wrong for a window: a host that attaches it reports
// a ready presenter, a healthy backend and no failure — while the window shows
// nothing. That combination is the one outcome the presentation policy must
// make impossible, because a blank window that reports healthy is
// indistinguishable from a hang.
//
// This file is the missing half: the seam that turns the software rasterizer
// into an actual presenter by blitting each rasterized frame into the window's
// client area with `StretchDIBits`. It lives in the host layer because
// `SwiftWindowsGraphics` is renderer-neutral *and* platform-free by contract —
// no GDI, no Win32, no D3D11 there.
//
// The structural guarantee this buys: the fallback backend either puts pixels
// on the screen or throws. There is no third outcome where it silently
// succeeds at nothing, so a machine with no usable GPU either gets a real
// software-rendered window or reaches the observable
// `.presenterUnavailable` terminal state.

/// Copies a rasterized frame into a window's client area.
///
/// Injectable so the host seams can be driven headlessly: the production
/// implementation needs a live HWND, and tests need to assert *what* reached
/// the screen without one.
@MainActor
protocol WindowBitmapPresenter {
    func present(_ bitmap: BitmapSurface, to windowHandle: NativeWindowHandle, clientSize: IntSize) throws
}

enum SoftwarePresentationError: Error, CustomStringConvertible {
    case missingWindowHandle
    case unusableDeviceContext
    case blitFailed
    case nothingRendered
    case unsupportedPlatform

    var description: String {
        switch self {
        case .missingWindowHandle:
            return "Software presentation has no window to blit into."
        case .unusableDeviceContext:
            return "GetDC returned no device context for the presentation window."
        case .blitFailed:
            return "StretchDIBits copied no scan lines into the window."
        case .nothingRendered:
            return "Software presentation was asked to present before anything was rasterized."
        case .unsupportedPlatform:
            return "Software window presentation requires Windows (GDI)."
        }
    }
}

extension SoftwarePresentationError: ClassifiedPresentationFailure {
    /// Nothing here is a lost device or a bad scene: a window we cannot blit
    /// into is a capability this process does not have, and retrying it every
    /// backoff window buys nothing.
    var presentationFailureKind: PresentationFailureKind {
        switch self {
        case .missingWindowHandle, .unsupportedPlatform:
            return .permanent
        case .unusableDeviceContext, .blitFailed, .nothingRendered:
            return .transient
        }
    }
}

#if os(Windows)
    /// Blits a straight-alpha BGRA surface into the window's client area.
    ///
    /// `BI_RGB` at 32 bits per pixel is byte-for-byte the rasterizer's BGRA
    /// layout with the alpha byte ignored, which is the right reading: the
    /// scene's clear colour is opaque, so the composited frame is opaque.
    @MainActor
    struct GDIWindowBitmapPresenter: WindowBitmapPresenter {
        func present(_ bitmap: BitmapSurface, to windowHandle: NativeWindowHandle, clientSize: IntSize) throws {
            try bitmap.validate()

            guard let hwnd = unsafeBitCast(windowHandle.rawPointer, to: HWND?.self) else {
                throw SoftwarePresentationError.missingWindowHandle
            }
            guard let dc = GetDC(hwnd) else {
                throw SoftwarePresentationError.unusableDeviceContext
            }
            defer { _ = ReleaseDC(hwnd, dc) }

            var info = BITMAPINFO()
            info.bmiHeader.biSize = DWORD(MemoryLayout<BITMAPINFOHEADER>.size)
            info.bmiHeader.biWidth = LONG(bitmap.width)
            // Negative height: the rasterizer writes row 0 at the top, and a
            // DIB's default origin is the bottom-left. Without the sign the
            // whole window presents upside down.
            info.bmiHeader.biHeight = LONG(-bitmap.height)
            info.bmiHeader.biPlanes = 1
            info.bmiHeader.biBitCount = 32
            info.bmiHeader.biCompression = DWORD(BI_RGB)

            // The window and the raster are the same size on every normal
            // frame; COLORONCOLOR keeps the odd mismatched frame (a resize
            // that has not reached the rasterizer yet) cheap and predictable
            // instead of pulling in the halftone brush origin.
            SetStretchBltMode(dc, COLORONCOLOR)

            // The rasterizer's stride is exactly `width * 4`, which is always
            // DWORD-aligned, so its buffer is already a valid DIB.
            let copiedScanLines = bitmap.pixels.withUnsafeBytes { raw -> Int32 in
                Int32(
                    StretchDIBits(
                        dc,
                        0,
                        0,
                        max(1, clientSize.width),
                        max(1, clientSize.height),
                        0,
                        0,
                        bitmap.width,
                        bitmap.height,
                        raw.baseAddress,
                        &info,
                        UINT(DIB_RGB_COLORS),
                        DWORD(SRCCOPY)
                    )
                )
            }

            guard copiedScanLines != 0 else {
                throw SoftwarePresentationError.blitFailed
            }
        }
    }
#endif

/// Stand-in on platforms with no GDI. It exists so the software factory has
/// one shape everywhere and reports its own unavailability honestly instead
/// of silently rendering into a void.
@MainActor
struct UnavailableWindowBitmapPresenter: WindowBitmapPresenter {
    func present(_ bitmap: BitmapSurface, to windowHandle: NativeWindowHandle, clientSize: IntSize) throws {
        throw SoftwarePresentationError.unsupportedPlatform
    }
}

/// A software backend that rasterizes on the CPU and then actually puts the
/// result on screen.
///
/// Conforms to both backend protocols, like `CPUBatchRenderer`, so it can
/// serve the scene path and the frame path — the fallback factory has to fill
/// both slots the host asks for.
@MainActor
final class SoftwareWindowRenderBackend: BatchRenderBackend, RenderBackend {
    private let rasterizer = CPUBatchRenderer()
    private let presenter: any WindowBitmapPresenter
    private var windowHandle: NativeWindowHandle?
    private var currentSize: IntSize = .zero

    /// Number of frames that actually reached the window. Tests assert on it;
    /// the host never reads it.
    private(set) var presentedFrameCount = 0

    init(presenter: (any WindowBitmapPresenter)? = nil) {
        self.presenter = presenter ?? Self.defaultPresenter()
    }

    static func defaultPresenter() -> any WindowBitmapPresenter {
        #if os(Windows)
            return GDIWindowBitmapPresenter()
        #else
            return UnavailableWindowBitmapPresenter()
        #endif
    }

    var backendDisplayName: String { "CPU SOFTWARE" }

    /// No device and no swap chain: never occluded, never owing a repaint.
    /// Stated rather than inherited because conforming to both backend
    /// protocols would otherwise pick up two identical defaults and satisfy
    /// neither.
    var presentationState: PresentationState { PresentationState() }

    /// A `BitBlt` to a device context does not wait for vblank, so there is no
    /// pacing bargain here to lose — and nothing for the watchdog to rescue.
    /// Stated rather than inherited, same as above.
    var presentPacing: PresentPacingStatus { PresentPacingStatus() }

    func setDisplayFrameInterval(_ seconds: Double) {}

    /// No watchdog, so no memory to seed. Stated rather than inherited, same
    /// as above.
    func adoptRememberedSelfPacing() {}

    /// The last frame handed to the presenter, kept for the same reason
    /// `CPUBatchRenderer` keeps one: snapshot tooling and pixel assertions.
    var lastRenderedBitmap: BitmapSurface? { rasterizer.lastRenderedBitmap }

    func attach(to surface: SurfaceDescriptor) throws {
        guard let nativeWindowHandle = surface.windowHandle,
            nativeWindowHandle.rawPointer != nil
        else {
            throw SoftwarePresentationError.missingWindowHandle
        }
        try rasterizer.attach(to: surface)
        windowHandle = nativeWindowHandle
        currentSize = surface.pixelSize
    }

    func resize(to size: IntSize) throws {
        try rasterizer.resize(to: size)
        currentSize = size
    }

    func detach() {
        rasterizer.detach()
        windowHandle = nil
        currentSize = .zero
    }

    func bindResources(for scene: GPUIScene) {
        rasterizer.bindResources(for: scene)
    }

    func render(scene: GPUIScene) throws {
        try rasterizer.render(scene: scene)
        try presentLastRasterizedFrame()
    }

    func render(frame: RenderFrame) throws {
        try rasterizer.render(frame: frame)
        try presentLastRasterizedFrame()
    }

    private func presentLastRasterizedFrame() throws {
        guard let windowHandle else {
            throw SoftwarePresentationError.missingWindowHandle
        }
        guard let bitmap = rasterizer.lastRenderedBitmap else {
            throw SoftwarePresentationError.nothingRendered
        }
        try presenter.present(bitmap, to: windowHandle, clientSize: currentSize)
        presentedFrameCount += 1
    }
}

/// The fallback factory a composition root drops to when the app's preferred
/// factory reports it cannot present on this machine.
///
/// Unlike `CPURenderBackendFactory` — whose backends rasterize into memory and
/// are the parity suite's reference, not a presenter — every backend this
/// factory produces blits to the HWND it was attached to.
@MainActor
public struct SoftwareWindowRenderBackendFactory: RenderBackendFactory {
    public init() {}

    public var factoryName: String { "CPU Software" }

    public var capabilities: RenderBackendCapabilities { .softwareWindow }

    public func makeRenderBackend() -> any RenderBackend {
        SoftwareWindowRenderBackend()
    }

    public func makeBatchRenderBackend() -> (any BatchRenderBackend)? {
        SoftwareWindowRenderBackend()
    }

    /// GDI is part of the OS: where this target runs at all, the software
    /// presenter runs. Elsewhere it says so, and the composition root keeps
    /// the requested factory rather than substituting a backend that cannot
    /// present either.
    public func probeAvailability() -> RenderBackendAvailability {
        #if os(Windows)
            return .degraded(
                reason: "Presenting through the CPU rasterizer and a GDI blit; no GPU backend is usable here."
            )
        #else
            return .unavailable(reason: "Software window presentation requires Windows (GDI).")
        #endif
    }
}
