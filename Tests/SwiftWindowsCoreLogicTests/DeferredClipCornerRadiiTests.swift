import Foundation
import SwiftWindowsCore
import SwiftWindowsGraphics
import XCTest

@testable import SwiftWindowsUI

@MainActor
private func deferredSubtreePayloads(
    of runtime: RetainedViewRuntime
) -> [DeferredSubtreePayload] {
    runtime.currentPrepaintState.deferredDraws.compactMap { draw in
        if case .subtree(let payload) = draw.payload {
            return payload
        }
        return nil
    }
}

/// Pins per-corner clip radii propagation into DEFERRED subtree payloads.
/// `DeferredSubtreePayload` now carries `inheritedClipCornerRadius` /
/// `inheritedClipCornerRadii` (mirroring the main paint traversal in
/// ScenePainter), so deferred content (overlays, deferred caches) resolves
/// the same per-corner clip rounding as inline children instead of
/// dropping to the uniform-zero fallback.
final class DeferredClipCornerRadiiTests: XCTestCase {

    func testDeferredPayloadCarriesInheritedPerCornerClipRadii() async {
        await MainActor.run {
            let deferred = ViewNode(
                frame: Rect(x: 0, y: 0, width: 100, height: 40),
                backgroundColor: Color(red: 1, green: 0, blue: 0, alpha: 1),
                paintsInDeferredPhase: true
            )
            let root = ViewNode(
                frame: Rect(x: 0, y: 0, width: 200, height: 40),
                cornerRadii: RetainedCornerRadii(topLeft: 10, bottomLeft: 10),
                clipsToBounds: true,
                children: [deferred]
            )
            let runtime = RetainedViewRuntime(root: root)
            _ = runtime.renderScene()

            let payloads = deferredSubtreePayloads(of: runtime)
            XCTAssertEqual(payloads.count, 1)
            XCTAssertEqual(
                payloads[0].inheritedClipCornerRadius, 10, accuracy: 0.001,
                "scalar fallback carries the largest inherited clip radius")
            XCTAssertEqual(
                payloads[0].inheritedClipCornerRadii,
                RetainedCornerRadii(topLeft: 10, bottomLeft: 10),
                "deferred payload must carry the per-corner clip radii")
        }
    }

    func testDeferredPayloadCarriesUniformClipCornerRadius() async {
        await MainActor.run {
            let deferred = ViewNode(
                frame: Rect(x: 0, y: 0, width: 100, height: 40),
                backgroundColor: Color(red: 1, green: 0, blue: 0, alpha: 1),
                paintsInDeferredPhase: true
            )
            let root = ViewNode(
                frame: Rect(x: 0, y: 0, width: 200, height: 40),
                cornerRadius: 12,
                clipsToBounds: true,
                children: [deferred]
            )
            let runtime = RetainedViewRuntime(root: root)
            _ = runtime.renderScene()

            let payloads = deferredSubtreePayloads(of: runtime)
            XCTAssertEqual(payloads.count, 1)
            XCTAssertEqual(payloads[0].inheritedClipCornerRadius, 12, accuracy: 0.001)
            XCTAssertNil(
                payloads[0].inheritedClipCornerRadii,
                "uniform-radius clips keep the nil per-corner path (historic behaviour)")
        }
    }

    func testDeferredPayloadWithoutClippingAncestorCarriesNoRadii() async {
        await MainActor.run {
            let deferred = ViewNode(
                frame: Rect(x: 0, y: 0, width: 100, height: 40),
                backgroundColor: Color(red: 1, green: 0, blue: 0, alpha: 1),
                paintsInDeferredPhase: true
            )
            let root = ViewNode(
                frame: Rect(x: 0, y: 0, width: 200, height: 40),
                cornerRadius: 12,
                clipsToBounds: false,
                children: [deferred]
            )
            let runtime = RetainedViewRuntime(root: root)
            _ = runtime.renderScene()

            let payloads = deferredSubtreePayloads(of: runtime)
            XCTAssertEqual(payloads.count, 1)
            XCTAssertEqual(payloads[0].inheritedClipCornerRadius, 0, accuracy: 0.001)
            XCTAssertNil(payloads[0].inheritedClipCornerRadii)
        }
    }

    func testDeferredSubtreeQuadsResolvePerCornerClipRadius() async {
        await MainActor.run {
            // Parent rounded on the left side only (joined-control shape);
            // both children paint in the deferred phase.
            let leftDeferred = ViewNode(
                frame: Rect(x: 0, y: 0, width: 100, height: 40),
                backgroundColor: Color(red: 1, green: 0, blue: 0, alpha: 1),
                paintsInDeferredPhase: true
            )
            let rightDeferred = ViewNode(
                frame: Rect(x: 100, y: 0, width: 100, height: 40),
                backgroundColor: Color(red: 0, green: 1, blue: 0, alpha: 1),
                paintsInDeferredPhase: true
            )
            let root = ViewNode(
                frame: Rect(x: 0, y: 0, width: 200, height: 40),
                cornerRadii: RetainedCornerRadii(topLeft: 10, bottomLeft: 10),
                clipsToBounds: true,
                children: [leftDeferred, rightDeferred]
            )
            let runtime = RetainedViewRuntime(root: root)
            let scene = runtime.renderScene()

            let quads = scene.layers[0].quads
            XCTAssertEqual(quads.count, 2)
            XCTAssertEqual(
                quads[0].clipCornerRadius, 10, accuracy: 0.001,
                "deferred left child reaches the rounded left corners and keeps that radius")
            XCTAssertEqual(
                quads[1].clipCornerRadius, 0, accuracy: 0.001,
                "deferred right child reaches only square corners and stays square")
        }
    }

    func testDeferredSubtreeUniformClipRasterizesIdenticallyToInlineChild() async {
        await MainActor.run {
            // A uniform-radius clip must produce byte-identical pixels for
            // deferred and inline children — the deferred path only threads
            // state, it must not change at-rest rendering.
            @MainActor
            func scenePixels(deferred: Bool) -> Data {
                let child = ViewNode(
                    frame: Rect(x: 0, y: 0, width: 100, height: 40),
                    backgroundColor: Color(red: 0, green: 0, blue: 1, alpha: 1),
                    paintsInDeferredPhase: deferred
                )
                let root = ViewNode(
                    frame: Rect(x: 0, y: 0, width: 100, height: 40),
                    cornerRadius: 10,
                    clipsToBounds: true,
                    children: [child]
                )
                let runtime = RetainedViewRuntime(root: root)
                return GPUIRawSceneRasterizer.rasterize(
                    runtime.renderScene(),
                    size: IntSize(width: 100, height: 40)
                ).pixels
            }

            XCTAssertEqual(scenePixels(deferred: true), scenePixels(deferred: false))
        }
    }
}
