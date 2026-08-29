import XCTest

@testable import SwiftWindowsCore
@testable import SwiftWindowsPlatform
@testable import SwiftWindowsUI
@testable import WinSwiftUI

private func uiaGeometry(
    origin: Point = Point(x: 100, y: -40), scale: Double = 1.5, revision: UInt64 = 7
) -> NativeWindowGeometry {
    NativeWindowGeometry(
        revision: revision, nativeSequence: 19, clientSize: IntSize(width: 300, height: 150),
        clientScreenOrigin: origin, scaleFactor: scale, effectiveScaleFactor: scale,
        monitorRefreshRate: 60, isMinimized: false, isVisible: true, isActive: true)
}

@MainActor
final class UIANativeGeometryProjectionTests: XCTestCase {
    private func makeRuntime() -> RetainedViewRuntime {
        let root = ViewNode(frame: Rect(x: 0, y: 0, width: 200, height: 100))
        root.resolvedFrame = root.frame
        let button = ViewNode(frame: Rect(x: 10.25, y: 12.25, width: 40.5, height: 20.5))
        button.resolvedFrame = button.frame
        button.accessibilityLabel = "Before"
        button.accessibilityTraits = .isButton
        root.addChild(button)
        return RetainedViewRuntime(root: root)
    }

    func testMappingRoundsEndpointsBeforeAddingScreenOrigin() async {
        let geometry = uiaGeometry()
        XCTAssertEqual(
            geometry.clientRectToScreen(Rect(x: -1, y: -0.2, width: 2, height: 1)),
            Rect(x: 98, y: -40, width: 4, height: 1))
        XCTAssertEqual(
            geometry.clientRectToScreen(Rect(x: 0.2, y: 0.2, width: 1, height: 1)),
            Rect(x: 100, y: -40, width: 2, height: 2))
    }

    func testGeometryOverrideBypassesLegacyMapperAndKeepsFreshProjection() async throws {
        let runtime = makeRuntime()
        var legacyMappings = 0
        let source = RuntimeUIAElementTreeSource(runtime: runtime) { bounds in
            legacyMappings += 1
            return bounds
        }
        let legacy = source.uiaElementSnapshots()
        let readsAfterLegacy = legacyMappings
        XCTAssertEqual(readsAfterLegacy, legacy.count + 1)
        let geometry = uiaGeometry()
        let first = try source.uiaElementSnapshots(geometry: geometry)
        XCTAssertEqual(legacyMappings, readsAfterLegacy)
        XCTAssertEqual(first.map(\.id), legacy.map(\.id))
        XCTAssertEqual(first.map(\.bounds), try legacy.map { try XCTUnwrap(geometry.clientRectToScreen($0.bounds)) })

        runtime.root.children[0].accessibilityLabel = "After"
        let second = try source.uiaElementSnapshots(geometry: geometry)
        XCTAssertEqual(second.last?.name, "After")
        XCTAssertEqual(second.map(\.id), first.map(\.id))
        XCTAssertEqual(first.last?.name, "Before")
        XCTAssertEqual(legacyMappings, readsAfterLegacy)
        withExtendedLifetime(runtime) {}
    }

    func testInvalidPublishedGeometryThrowsWithoutUsingLegacyMapper() async throws {
        let runtime = makeRuntime()
        var legacyMappings = 0
        let source = RuntimeUIAElementTreeSource(runtime: runtime) { bounds in
            legacyMappings += 1
            return bounds
        }
        XCTAssertThrowsError(try source.uiaElementSnapshots(geometry: uiaGeometry(scale: 0))) {
            XCTAssertEqual($0 as? UIAProviderRequestFailure, .invalidGeometry)
        }
        XCTAssertThrowsError(try source.uiaElementSnapshots(geometry: uiaGeometry(scale: .infinity))) {
            XCTAssertEqual($0 as? UIAProviderRequestFailure, .invalidGeometry)
        }
        XCTAssertEqual(legacyMappings, 0)
        withExtendedLifetime(runtime) {}
    }

    func testMissingRuntimeStillReturnsEmptyLiveProjection() async throws {
        var runtime: RetainedViewRuntime? = makeRuntime()
        let source = RuntimeUIAElementTreeSource(runtime: try XCTUnwrap(runtime))
        runtime = nil
        XCTAssertTrue(try source.uiaElementSnapshots(geometry: uiaGeometry()).isEmpty)
    }

    func testGeometryValuesRemainIndependentAcrossSendableTransfer() async {
        let original = uiaGeometry()
        var changed = original
        changed.clientScreenOrigin = Point(x: 500, y: 600)
        changed.revision = 8
        let copied = await Task.detached { original }.value
        XCTAssertEqual(copied.revision, 7)
        XCTAssertEqual(copied.clientScreenOrigin, Point(x: 100, y: -40))
        XCTAssertEqual(changed.revision, 8)
    }
}
