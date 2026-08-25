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
        let resolved = RenderBackendFactoryResolution.resolve(
            factory,
            report: { reports.append($0) }
        )

        XCTAssertEqual(
            resolved.factory.factoryName, "Stub GPU", "Degraded must not silently downgrade the whole factory.")
        XCTAssertEqual(reports.count, 1, "The reduced capability belongs in the log.")
        XCTAssertFalse(resolved.resolution.isSubstituted)
        XCTAssertTrue(
            resolved.resolution.isDegradedPresentation,
            "A degraded probe — the windowed-WARP case for D3D11 — must be visible in health, not only in the log."
        )
    }

    func testUnavailableFactoriesFallBackToAPresentingSoftwareFactory() async {
        var reports: [String] = []
        let factory = StubRenderBackendFactory(
            factoryName: "Stub GPU",
            availability: .unavailable(reason: "no adapter")
        )
        let resolved = RenderBackendFactoryResolution.resolve(
            factory,
            report: { reports.append($0) }
        )

        XCTAssertEqual(resolved.factory.factoryName, SoftwareWindowRenderBackendFactory().factoryName)
        XCTAssertNotEqual(
            resolved.factory.factoryName,
            CPURenderBackendFactory().factoryName,
            "The CPU reference backend rasterizes into memory and never blits: substituting it produces a blank "
                + "window that reports itself healthy."
        )
        XCTAssertEqual(reports.count, 1)
        XCTAssertTrue(reports[0].contains("no adapter"))
        XCTAssertTrue(resolved.resolution.isSubstituted)
        XCTAssertTrue(resolved.resolution.isDegradedPresentation)
        XCTAssertEqual(resolved.resolution.requestedFactoryName, "Stub GPU")
        XCTAssertEqual(resolved.resolution.availability, .unavailable(reason: "no adapter"))
        XCTAssertEqual(resolved.resolution.requestedCapabilities, .conservative)
        XCTAssertEqual(resolved.resolution.resolvedCapabilities, .softwareWindow)
    }

    /// Device availability is not presentation capability: the CPU reference
    /// factory is always available, but it only renders into an offscreen
    /// bitmap. Selecting it for an app window must choose a real presenter.
    func testAvailableOffscreenFactoryFallsBackToARealWindowPresenter() async {
        var reports: [String] = []
        let requested = CPURenderBackendFactory()

        let resolved = RenderBackendFactoryResolution.resolve(
            requested,
            report: { reports.append($0) }
        )

        XCTAssertEqual(requested.probeAvailability(), .available)
        XCTAssertEqual(resolved.factory.factoryName, SoftwareWindowRenderBackendFactory().factoryName)
        XCTAssertEqual(resolved.resolution.availability, .available)
        XCTAssertEqual(resolved.resolution.requestedCapabilities, .cpuOffscreen)
        XCTAssertEqual(resolved.resolution.resolvedCapabilities, .softwareWindow)
        XCTAssertTrue(resolved.resolution.isSubstituted)
        XCTAssertTrue(resolved.resolution.isDegradedPresentation)
        XCTAssertEqual(reports.count, 1)
        XCTAssertTrue(reports[0].contains("offscreen"))
        XCTAssertTrue(reports[0].contains("native window"))
    }

    /// The substitution is only ever an improvement: a fallback that cannot
    /// present here is not swapped in, so the bounded attach retry reaches the
    /// observable `.presenterUnavailable` terminal state instead of a window
    /// that shows nothing while reporting a healthy presenter.
    func testAFallbackThatCannotPresentIsNeverSubstituted() async {
        var reports: [String] = []
        let factory = StubRenderBackendFactory(
            factoryName: "Stub GPU",
            availability: .unavailable(reason: "no adapter")
        )
        let fallback = StubRenderBackendFactory(
            factoryName: "Stub Fallback",
            availability: .unavailable(reason: "no presenter either")
        )
        let resolved = RenderBackendFactoryResolution.resolve(
            factory,
            fallback: fallback,
            report: { reports.append($0) }
        )

        XCTAssertEqual(resolved.factory.factoryName, "Stub GPU")
        XCTAssertFalse(resolved.resolution.isSubstituted)
        XCTAssertEqual(reports.count, 1)
        XCTAssertTrue(reports[0].contains("isPresenterUnavailable"))
    }

    /// A successful availability probe is not enough for substitution: the
    /// CPU reference renderer can create a bitmap but cannot update a window.
    func testAvailableOffscreenOnlyFallbackIsNeverSubstituted() async {
        var reports: [String] = []
        let requested = StubRenderBackendFactory(
            factoryName: "Stub GPU",
            availability: .unavailable(reason: "no adapter")
        )
        let fallback = CPURenderBackendFactory()

        let resolved = RenderBackendFactoryResolution.resolve(
            requested,
            fallback: fallback,
            report: { reports.append($0) }
        )

        XCTAssertEqual(fallback.probeAvailability(), .available)
        XCTAssertEqual(resolved.factory.factoryName, "Stub GPU")
        XCTAssertFalse(resolved.resolution.isSubstituted)
        XCTAssertEqual(resolved.resolution.requestedCapabilities, .conservative)
        XCTAssertEqual(resolved.resolution.resolvedCapabilities, .conservative)
        XCTAssertEqual(reports.count, 1)
        XCTAssertTrue(reports[0].contains("offscreen"))
        XCTAssertTrue(reports[0].contains("cannot present"))
    }

    func testAvailableFactoriesAreUsedUnchangedAndSilently() async {
        var reports: [String] = []
        let factory = StubRenderBackendFactory(factoryName: "Stub GPU", availability: .available)
        let resolved = RenderBackendFactoryResolution.resolve(
            factory,
            report: { reports.append($0) }
        )

        XCTAssertEqual(resolved.factory.factoryName, "Stub GPU")
        XCTAssertEqual(factory.capabilities, .conservative)
        XCTAssertEqual(resolved.resolution.requestedCapabilities, .conservative)
        XCTAssertEqual(resolved.resolution.resolvedCapabilities, .conservative)
        XCTAssertTrue(reports.isEmpty)
        XCTAssertFalse(resolved.resolution.isSubstituted)
        XCTAssertFalse(
            resolved.resolution.isDegradedPresentation,
            "A healthy hardware session must be distinguishable from a substituted or WARP one."
        )
    }

    /// The D3D11 probe must answer without creating a device, and on any
    /// Windows install it must find at least WARP: `unavailable` would mean
    /// the product boots onto the CPU backend on a normal machine.
    func testD3D11FactoryProbeFindsAPresentableDriver() async {
        let factory = D3D11RenderBackendFactory()
        let availability = factory.probeAvailability()
        XCTAssertTrue(
            availability.canPresent,
            "D3D11 must be presentable through hardware or WARP on a Windows machine; got \(availability)."
        )
        XCTAssertEqual(factory.capabilities, .graphicsDeviceWindow)
        XCTAssertTrue(factory.capabilities.supportsWindowPresentation)
        XCTAssertFalse(factory.capabilities.supportsOffscreenRendering)
        XCTAssertEqual(factory.capabilities.executionModel, .graphicsDevice)
    }
}
