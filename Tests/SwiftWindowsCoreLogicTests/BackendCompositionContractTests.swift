import SwiftWindowsGraphics
import WinSwiftUI
import XCTest

/// Phase 8 modularization: the WinSwiftUI facade is renderer-neutral.
///
/// `WinSwiftUI.App.renderBackendFactory()` defaults to the portable CPU
/// reference factory from `SwiftWindowsGraphics`; the D3D11 GPU factory is
/// injected by the app composition root (the `swift-windowsui` executable,
/// see `AppEntry.swift`). These tests pin the seam: the default must never
/// name a concrete GPU backend, and custom factory injection — the mechanism
/// tests and non-D3D11 consumers rely on — must keep working without linking
/// `SwiftWindowsRendererD3D11`.
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

    private struct InjectedProbeApp: App {
        var body: Never { fatalError("probe app is never booted") }

        static func renderBackendFactory() -> RenderBackendFactory {
            HeadlessProbeFactory()
        }
    }

    func testDefaultRenderBackendFactoryIsBackendNeutral() async {
        let factory = NeutralProbeApp.renderBackendFactory()

        // The facade default is the portable CPU reference backend; pinning
        // by name keeps the assertion free of any D3D11 symbol so this test
        // target would compile even without SwiftWindowsRendererD3D11.
        XCTAssertEqual(factory.factoryName, CPURenderBackendFactory().factoryName)
    }

    func testDefaultRenderBackendFactoryProducesWorkingCPUBackends() async {
        let factory = NeutralProbeApp.renderBackendFactory()

        let frameBackend = factory.makeRenderBackend()
        let referenceName = CPURenderBackendFactory().makeRenderBackend().backendDisplayName
        XCTAssertEqual(frameBackend.backendDisplayName, referenceName)

        // Scene/batch remains the default presentation shape even for the
        // backend-neutral default: the CPU factory offers a batch backend.
        XCTAssertNotNil(factory.makeBatchRenderBackend())
    }

    func testCustomFactoryInjectionRemainsSupported() async {
        let factory = InjectedProbeApp.renderBackendFactory()

        XCTAssertEqual(factory.factoryName, "Headless Probe")
        XCTAssertNil(factory.makeBatchRenderBackend())
    }
}
