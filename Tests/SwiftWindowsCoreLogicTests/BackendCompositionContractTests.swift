import SwiftWindowsCore
import SwiftWindowsGraphics
import SwiftWindowsPlatform
import WinSwiftUI
import XCTest

/// Phase 8 modularization: the WinSwiftUI facade is renderer-neutral.
///
/// `WinSwiftUI.App.renderBackendFactory()` defaults to the software presenter
/// that ships with the facade; the D3D11 GPU factory is injected by the app
/// composition root (the `swift-windowsui` executable, see `AppEntry.swift`).
/// These tests pin the seam: the default must never name a concrete GPU
/// backend, it must be able to actually present (a default that only
/// rasterizes into memory opens a blank window that reports itself healthy),
/// and custom factory injection — the mechanism tests and non-D3D11 consumers
/// rely on — must keep working without linking `SwiftWindowsRendererD3D11`.
@MainActor
final class BackendCompositionContractTests: XCTestCase {

    private struct NeutralProbeApp: App {
        var body: Never { fatalError("probe app is never booted") }
    }

    private struct HeadlessProbeFactory: RenderBackendFactory {
        var factoryName: String { "Headless Probe" }

        func makeRenderBackend() -> any RenderBackend {
            FakeRenderBackend()
        }

        func makeBatchRenderBackend() -> (any BatchRenderBackend)? {
            nil
        }
    }

    private struct HeadlessProbePlatformFactory: PlatformHostFactory {
        var platformName: String { "Independent Platform Probe" }

        func makeWindow(configuration: PlatformWindowConfiguration) throws -> any PlatformWindow {
            try Win32PlatformHostFactory().makeWindow(configuration: configuration)
        }

        func start(window: any PlatformWindow) throws {}

        func runEventLoop() throws -> Int32 {
            0
        }

        func terminateEventLoop() {}
    }

    private struct InjectedProbeApp: App {
        var body: Never { fatalError("probe app is never booted") }

        static func renderBackendFactory() -> RenderBackendFactory {
            HeadlessProbeFactory()
        }

        static func platformHostFactory() -> any PlatformHostFactory {
            HeadlessProbePlatformFactory()
        }
    }

    func testDefaultRenderBackendFactoryIsBackendNeutral() async {
        let factory = NeutralProbeApp.renderBackendFactory()

        // The facade default is the software presenter; pinning by name keeps
        // the assertion free of any D3D11 symbol so this test target would
        // compile even without SwiftWindowsRendererD3D11.
        XCTAssertEqual(factory.factoryName, SoftwareWindowRenderBackendFactory().factoryName)
        XCTAssertEqual(NeutralProbeApp.platformHostFactory().platformName, Win32PlatformHostFactory().platformName)
    }

    func testDefaultRenderBackendFactoryCanActuallyPresent() async {
        let factory = NeutralProbeApp.renderBackendFactory()

        XCTAssertTrue(
            factory.probeAvailability().canPresent,
            "A default that cannot present opens a window that shows nothing while reporting itself healthy."
        )
        XCTAssertNotEqual(
            factory.factoryName,
            CPURenderBackendFactory().factoryName,
            "The CPU reference backend rasterizes into memory and never blits to an HWND."
        )

        // Scene/batch remains the default presentation shape even for the
        // backend-neutral default.
        XCTAssertNotNil(factory.makeBatchRenderBackend())
    }

    func testCustomFactoryInjectionRemainsSupported() async {
        let factory = InjectedProbeApp.renderBackendFactory()

        XCTAssertEqual(factory.factoryName, "Headless Probe")
        XCTAssertNil(factory.makeBatchRenderBackend())
        XCTAssertEqual(InjectedProbeApp.platformHostFactory().platformName, "Independent Platform Probe")
    }
}
