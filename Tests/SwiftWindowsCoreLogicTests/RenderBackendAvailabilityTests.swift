import SwiftWindowsCore
import SwiftWindowsGraphics
import SwiftWindowsRendererD3D11

@preconcurrency import XCTest

@testable import WinSwiftUI

// WS-10: a factory is asked whether this machine can present with it *before*
// a window exists. Discovering it at `attach` instead leaves the window on
// screen with nothing in it and no presenter ever attached — the blank-window
// state that used to be indistinguishable from a hang.

@MainActor
private struct StubRenderBackendFactory: RenderBackendFactory {
    let factoryName: String
    let availability: RenderBackendAvailability

    func makeRenderBackend() -> any RenderBackend {
        CPURenderBackendFactory().makeRenderBackend()
    }

    func makeBatchRenderBackend() -> (any BatchRenderBackend)? {
        CPURenderBackendFactory().makeBatchRenderBackend()
    }

    func probeAvailability() -> RenderBackendAvailability {
        availability
    }
}

@MainActor
final class RenderBackendAvailabilityTests: XCTestCase {
    func testFactoriesWithoutADeviceAreAlwaysAvailable() async {
        XCTAssertEqual(CPURenderBackendFactory().probeAvailability(), .available)
        XCTAssertTrue(RenderBackendAvailability.available.canPresent)
        XCTAssertNil(RenderBackendAvailability.available.reason)
    }

    func testDegradedFactoriesStillPresent() async {
        let degraded = RenderBackendAvailability.degraded(reason: "software rasterizer")
        XCTAssertTrue(degraded.canPresent, "A slow window is a better answer than no window.")
        XCTAssertEqual(degraded.reason, "software rasterizer")

        var reports: [String] = []
        let factory = StubRenderBackendFactory(factoryName: "Stub GPU", availability: degraded)
        let resolved = RenderBackendFactoryResolution.presentableFactory(
            factory,
            report: { reports.append($0) }
        )

        XCTAssertEqual(resolved.factoryName, "Stub GPU", "Degraded must not silently downgrade the whole factory.")
        XCTAssertEqual(reports.count, 1, "The reduced capability belongs in the log.")
    }

    func testUnavailableFactoriesFallBackToTheCPUFactory() async {
        var reports: [String] = []
        let factory = StubRenderBackendFactory(
            factoryName: "Stub GPU",
            availability: .unavailable(reason: "no adapter")
        )
        let resolved = RenderBackendFactoryResolution.presentableFactory(
            factory,
            report: { reports.append($0) }
        )

        XCTAssertEqual(resolved.factoryName, "CPU Reference")
        XCTAssertEqual(reports.count, 1)
        XCTAssertTrue(reports[0].contains("no adapter"))
    }

    func testAvailableFactoriesAreUsedUnchangedAndSilently() async {
        var reports: [String] = []
        let factory = StubRenderBackendFactory(factoryName: "Stub GPU", availability: .available)
        let resolved = RenderBackendFactoryResolution.presentableFactory(
            factory,
            report: { reports.append($0) }
        )

        XCTAssertEqual(resolved.factoryName, "Stub GPU")
        XCTAssertTrue(reports.isEmpty)
    }

    /// The D3D11 probe must answer without creating a device, and on any
    /// Windows install it must find at least WARP: `unavailable` would mean
    /// the product boots onto the CPU backend on a normal machine.
    func testD3D11FactoryProbeFindsAPresentableDriver() async {
        let availability = D3D11RenderBackendFactory().probeAvailability()
        XCTAssertTrue(
            availability.canPresent,
            "D3D11 must be presentable through hardware or WARP on a Windows machine; got \(availability)."
        )
    }
}
