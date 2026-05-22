import Foundation
import SwiftWindowsCore
import SwiftWindowsGraphics
import SwiftWindowsPlatform
import XCTest

@testable import SwiftWindowsUI
@testable import WinSwiftUI

/// Pins the contract for ScenePaintMetrics — apps observe the GPU
/// promotion rate via this struct, so changes that shift paths between
/// CPU and GPU paths must keep the counters honest.
@MainActor
final class ScenePaintMetricsTests: XCTestCase {

    private func snapshot<V: View>(_ view: V) -> WinSwiftUIRenderSnapshot {
        WinSwiftUIRendererSnapshotter.snapshot(
            of: view, size: IntSize(width: 240, height: 160), displayScale: 1, clearColor: .black)
    }

    func testGpuPromotionRateIs100PercentForAllAxisAlignedScene() async {
        await MainActor.run {
            // A scene made entirely of axis-aligned shape fills.
            // Everything must promote to the GPU.
            let view = VStack(spacing: 8) {
                Rectangle().fill(.red).frame(width: 60, height: 30)
                RoundedRectangle(cornerRadius: 4).fill(.green).frame(width: 60, height: 30)
                Rectangle().fill(.blue).frame(width: 60, height: 30)
            }
            .frame(width: 200, height: 120)

            let snap = snapshot(view)
            let metrics = snap.scene.paintMetrics
            // Pure shapes route through QuadPrimitive directly (not
            // PathPrimitive), so the *tessellator* may not see anything.
            // In that case the promotion rate is 1.0 by definition (no
            // demoted paths).
            XCTAssertEqual(
                metrics.gpuPromotionRate, 1.0, accuracy: 0.001,
                "All-axis-aligned scene should report 100% GPU promotion (no paths fell to CPU)")
            XCTAssertEqual(metrics.pathsRasterizedOnCPU, 0)
        }
    }

    func testGpuPromotionRateDropsWhenConcavePolygonFillsAppear() async {
        await MainActor.run {
            // Convex polygons (incl. curved-but-convex fills) now ride
            // the GPU via fan triangulation. To verify the CPU
            // fallback metrics still trip we need a concave shape —
            // here an arrowhead with one inward notch.
            let view = Canvas { ctx, size in
                var path = Path()
                path.moveTo(Point(x: 10, y: 10))
                path.lineTo(Point(x: 80, y: 10))
                path.lineTo(Point(x: 50, y: 40))  // notch — concave point
                path.lineTo(Point(x: 80, y: 70))
                path.lineTo(Point(x: 10, y: 70))
                path.close()
                ctx.fill(path, with: .color(Color(red: 0, green: 0, blue: 1, alpha: 1)))
            }
            .frame(width: 200, height: 160)

            let snap = snapshot(view)
            let metrics = snap.scene.paintMetrics
            XCTAssertEqual(
                metrics.pathsRasterizedOnCPU, 1,
                "Concave polygon must still fall through to CPU rasterization")
            XCTAssertEqual(metrics.pathsPromotedToGPU, 0)
            XCTAssertLessThan(
                metrics.gpuPromotionRate, 1.0,
                "Promotion rate should drop below 100% when any path falls to CPU"
            )
        }
    }

    func testGpuPromotionRateIs100PercentForAxisAlignedCanvasStroke() async {
        await MainActor.run {
            // Horizontal stroke — tessellator promotes to one quad.
            let view = Canvas { ctx, size in
                var path = Path()
                path.moveTo(Point(x: 10, y: 50))
                path.lineTo(Point(x: 100, y: 50))
                ctx.stroke(
                    path, with: .color(Color(red: 0, green: 0, blue: 1, alpha: 1)),
                    lineWidth: 3)
            }
            .frame(width: 200, height: 160)

            let snap = snapshot(view)
            let metrics = snap.scene.paintMetrics
            XCTAssertGreaterThanOrEqual(
                metrics.pathsPromotedToGPU, 1,
                "Horizontal stroke must take the GPU promotion path")
            XCTAssertEqual(metrics.pathsRasterizedOnCPU, 0)
            XCTAssertEqual(
                metrics.quadInstancesFromPromotedPaths, 1,
                "One axis-aligned segment should emit exactly one quad"
            )
        }
    }

    func testRendererHealthSnapshotExposesPaintMetrics() async {
        await MainActor.run {
            let batchRenderer = FakeBatchRenderBackend()
            let frameRenderer = FakeRenderBackend()
            let surface = SurfaceDescriptor(
                windowHandle: NativeWindowHandle(rawPointer: UnsafeMutableRawPointer(bitPattern: 0x1))!,
                pixelSize: IntSize(width: 200, height: 120),
                scaleFactor: 1.0
            )
            let config = WindowGroupConfiguration(
                title: "Test", size: surface.pixelSize, clearColor: .black, content: []
            )
            let host = WinSwiftUIWindowHost(
                configuration: config,
                renderer: frameRenderer,
                batchRenderer: batchRenderer,
                surfaceDescriptorProvider: { _ in surface }
            )
            let fakeWindow = Win32Window(title: "Test", clientSize: surface.pixelSize)
            host.windowDidCreate(fakeWindow)

            let snap = host.rendererHealthSnapshot
            // No paths in the empty test scene means promotion rate is
            // 1.0 by the "nothing to demote" convention.
            XCTAssertEqual(snap.lastScenePaintMetrics.gpuPromotionRate, 1.0, accuracy: 0.001)
            XCTAssertEqual(snap.lastScenePaintMetrics.pathsRasterizedOnCPU, 0)
        }
    }
}
