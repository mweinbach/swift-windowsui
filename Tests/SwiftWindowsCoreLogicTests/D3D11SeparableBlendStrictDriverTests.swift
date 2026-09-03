import SwiftWindowsCore
import SwiftWindowsGraphics
import WinSDK
import XCTest

@testable import SwiftWindowsRendererD3D11

/// Frozen after the initial implementation and reuse tests, before adding the
/// strict test renderer's device-loss refusal. Normal recovery is unchanged.
@MainActor
final class D3D11SeparableBlendStrictDriverTests: XCTestCase {
    func testStrictWARPDeviceLossThrowsAndDetachesWithoutRecreation() async throws {
        let renderer = D3D11BatchKernel()
        defer { renderer.detach() }
        try renderer.attachOffscreenWARPForTesting(size: IntSize(width: 8, height: 6))
        guard renderer.backendDiagnostics?.adapterIsSoftware == true else {
            throw BatchRendererError(
                operation: "Validate strict WARP recovery test device", hresult: HRESULT(bitPattern: 0x8000_4005))
        }
        XCTAssertTrue(renderer.isAttached)
        XCTAssertGreaterThan(renderer.liveCOMObjectCountForTesting, 0)

        // The existing seam simulates the same recovery entry point used by
        // offscreen Flush when GetDeviceRemovedReason reports device loss.
        XCTAssertThrowsError(try renderer.simulateDeviceLossForTesting()) { error in
            XCTAssertEqual((error as? BatchRendererError)?.operation, "SimulatedDeviceLoss")
            XCTAssertEqual((error as? BatchRendererError)?.presentationFailureKind, .deviceLost)
            XCTAssertEqual(PresentationFailureKind.classifying(error), .deviceLost)
        }
        XCTAssertFalse(renderer.isAttached)
        XCTAssertEqual(renderer.liveCOMObjectCountForTesting, 0)
    }
}
