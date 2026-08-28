import Foundation
import SwiftWindowsCore
import SwiftWindowsGraphics
import XCTest

@testable import SwiftWindowsRendererD3D11
@testable import SwiftWindowsUI
@testable import WinSwiftUI

/// Public Shape fills carry their own rule into both paint producers. These
/// tests cover direct leaves and supported rectangular clipping, not arbitrary
/// clip paths, antialiasing switches, or native SwiftUI pixel parity. Generic
/// path gradients retain the existing first-stop fallback. TrimmedShape and
/// AnyShape wrapping InsetShape or arc-based shapes are deliberately excluded.
@MainActor
final class ShapeFillRuleTests: XCTestCase {
    private static let size = IntSize(width: 64, height: 64)
    private static let white = Color(red: 1, green: 1, blue: 1, alpha: 1)
    private static let red = Color(red: 1, green: 0, blue: 0, alpha: 1)
    private static let blue = Color(red: 0, green: 0, blue: 1, alpha: 1)
    private static let halfRed = Color(red: 1, green: 0, blue: 0, alpha: 0.5)
    private static let choices: [PathFillRule?] = [nil, .nonZero, .evenOdd]

    private struct CompoundShape: InsettableShape {
        var reverseInner = false
        var closesSubpaths = true

        func path(in rect: Rect) -> Path {
            func point(_ x: Double, _ y: Double) -> Point {
                Point(x: rect.minX + x * rect.width, y: rect.minY + y * rect.height)
            }
            var path = Path()
            path.moveTo(point(0.125, 0.125))
            path.lineTo(point(0.875, 0.125))
            path.lineTo(point(0.875, 0.875))
            path.lineTo(point(0.125, 0.875))
            if closesSubpaths { path.close() }

            // An asymmetric inner contour makes a missing rotation observable.
            path.moveTo(point(0.375, 0.25))
            if reverseInner {
                path.lineTo(point(0.375, 0.625))
                path.lineTo(point(0.6875, 0.625))
                path.lineTo(point(0.6875, 0.25))
            } else {
                path.lineTo(point(0.6875, 0.25))
                path.lineTo(point(0.6875, 0.625))
                path.lineTo(point(0.375, 0.625))
            }
            if closesSubpaths { path.close() }
            return path
        }
    }

    private struct TestShapeStyle: ShapeStyle {
        let retainedForegroundStyle: ForegroundStyle
    }

    private struct CrossingStrokeShape: Shape {
        func path(in rect: Rect) -> Path {
            func point(_ x: Double, _ y: Double) -> Point {
                Point(x: rect.minX + x * rect.width, y: rect.minY + y * rect.height)
            }
            var path = Path()
            path.moveTo(point(0.125, 0.125))
            path.lineTo(point(0.875, 0.875))
            path.lineTo(point(0.125, 0.875))
            path.lineTo(point(0.875, 0.125))
            return path
        }
    }

    func testCompoundFillRuleCoverage() async throws {
        for reverseInner in [false, true] {
            var closedPixels: [BitmapSurface] = []
            for rule in Self.choices {
                let closed = snapshot(
                    filledShape(rule: rule, shape: CompoundShape(reverseInner: reverseInner))
                        .frame(width: 64, height: 64))
                let open = snapshot(
                    filledShape(
                        rule: rule,
                        shape: CompoundShape(reverseInner: reverseInner, closesSubpaths: false)
                    )
                    .frame(width: 64, height: 64))
                let expectedRule = rule ?? .nonZero
                let holeAlpha = reverseInner || expectedRule == .evenOdd ? 0 : 255
                for result in [closed, open] {
                    try assertActualRule(result, expected: expectedRule)
                    assertRingAndHole(raster(result), ringAlpha: 255, holeAlpha: holeAlpha)
                }
                let closedBitmap = raster(closed)
                XCTAssertEqual(raster(open).pixels, closedBitmap.pixels, "each open contour closes implicitly")
                closedPixels.append(closedBitmap)
            }
            XCTAssertEqual(closedPixels[0].pixels, closedPixels[1].pixels, "default is non-zero")
            if reverseInner {
                XCTAssertEqual(closedPixels[1].pixels, closedPixels[2].pixels)
            } else {
                XCTAssertNotEqual(closedPixels[1].pixels, closedPixels[2].pixels)
            }
        }
    }

    func testInheritedAndExplicitFillOverloads() async throws {
        for rule in [PathFillRule.nonZero, .evenOdd] {
            let style = FillStyle(eoFill: rule == .evenOdd)
            let explicit = snapshot(
                CompoundShape().fill(Self.red, style: style).frame(width: 64, height: 64))
            let expected = raster(explicit)
            let variants = [
                snapshot(
                    AnyShape(CompoundShape()).fill(Self.red, style: style)
                        .foregroundStyle(Self.blue).frame(width: 64, height: 64)),
                snapshot(
                    CompoundShape().fill(ForegroundStyle.color(Self.red), style: style)
                        .frame(width: 64, height: 64)),
                snapshot(
                    CompoundShape().fill(TestShapeStyle(retainedForegroundStyle: .color(Self.red)), style: style)
                        .frame(width: 64, height: 64)),
                snapshot(
                    VStack(spacing: 0) {
                        CompoundShape().fill(style: style).frame(width: 64, height: 64)
                    }
                    .foregroundStyle(Self.red)),
                snapshot(
                    VStack(spacing: 0) {
                        CompoundShape().fill(style: style)
                            .foregroundStyle(Self.red).frame(width: 64, height: 64)
                    }
                    .foregroundStyle(Self.blue)),
            ]
            for result in [explicit] + variants {
                try assertActualRule(result, expected: rule)
                XCTAssertEqual(try pathNode(in: result.runtime.root).clipFillStyle?.eoFill, rule == .evenOdd)
                let bitmap = raster(result)
                assertRingAndHole(bitmap, ringAlpha: 255, holeAlpha: rule == .evenOdd ? 0 : 255)
                XCTAssertEqual(pixel(bitmap, x: 12, y: 32).red, 255)
                XCTAssertEqual(pixel(bitmap, x: 12, y: 32).blue, 0)
                XCTAssertEqual(bitmap.pixels, expected.pixels)
            }
        }
        let inheritedDefault = snapshot(
            AnyShape(CompoundShape()).foregroundStyle(Self.red).frame(width: 64, height: 64))
        try assertActualRule(inheritedDefault, expected: .nonZero)
        XCTAssertNil(try pathNode(in: inheritedDefault.runtime.root).clipFillStyle)
        assertRingAndHole(raster(inheritedDefault), ringAlpha: 255, holeAlpha: 255)
    }

    func testDirectInsetPreservesFillRule() async throws {
        for rule in Self.choices {
            let inset = InsetShape(CompoundShape(), amount: 8)
            let filled: InsetShape<CompoundShape>
            if let rule {
                filled = inset.fill(Self.white, style: FillStyle(eoFill: rule == .evenOdd))
            } else {
                filled = inset.fill(Self.white)
            }
            // Fill the direct inset, not AnyShape(InsetShape(...)), whose
            // wrapper metadata has a separate, deliberately untested defect.
            let result = snapshot(filled.frame(width: 64, height: 64))
            try assertActualRule(result, expected: rule ?? .nonZero)
            let path = try XCTUnwrap(result.scene.layers.flatMap(\.paths).first)
            XCTAssertEqual(path.bounds, Rect(x: 14, y: 14, width: 36, height: 36))
            let bitmap = raster(result)
            XCTAssertEqual(pixel(bitmap, x: 16, y: 32).alpha, 255)
            XCTAssertEqual(pixel(bitmap, x: 48, y: 32).alpha, 255)
            XCTAssertEqual(pixel(bitmap, x: 34, y: 28).alpha, rule == .evenOdd ? 0 : 255)
            XCTAssertEqual(pixel(bitmap, x: 10, y: 32).alpha, 0, "inset changes the actual footprint")
        }
    }

    func testPlacementOpacityAndRectClipPreserveHole() async throws {
        for rule in [PathFillRule.nonZero, .evenOdd] {
            let placed = snapshot(
                filledShape(rule: rule, color: Color(red: 1, green: 0, blue: 0, alpha: 0.8))
                    .offset(x: 8, y: 4).opacity(0.5).frame(width: 64, height: 64))
            try assertActualRule(placed, expected: rule)
            let placedPath = try XCTUnwrap(placed.scene.layers.flatMap(\.paths).first)
            XCTAssertEqual(placedPath.fillColor.alpha, 0.4, accuracy: 0.0001)
            let placedPixels = raster(placed)
            XCTAssertEqual(pixel(placedPixels, x: 20, y: 36).alpha, 102, accuracy: 1)
            XCTAssertEqual(pixel(placedPixels, x: 42, y: 32).alpha, rule == .evenOdd ? 0 : 102, accuracy: 1)
            XCTAssertEqual(pixel(placedPixels, x: 12, y: 36).alpha, 0)

            let scaled = snapshot(
                filledShape(rule: rule).scaleEffect(0.5).frame(width: 64, height: 64),
                displayScale: 1.5)
            try assertActualRule(scaled, expected: rule)
            let scaledPixels = raster(scaled)
            XCTAssertEqual(scaledPixels.width, 96)
            XCTAssertEqual(pixel(scaledPixels, x: 33, y: 48).alpha, 255)
            XCTAssertEqual(pixel(scaledPixels, x: 50, y: 45).alpha, rule == .evenOdd ? 0 : 255)
            XCTAssertEqual(pixel(scaledPixels, x: 24, y: 48).alpha, 0)

            let rotated = snapshot(
                filledShape(rule: rule).rotationEffect(.degrees(90)).frame(width: 64, height: 64))
            try assertActualRule(rotated, expected: rule)
            let rotatedPixels = raster(rotated)
            // (26, 18) moves to (46, 26); the asymmetric hole must move too.
            XCTAssertEqual(pixel(rotatedPixels, x: 46, y: 26).alpha, rule == .evenOdd ? 0 : 255)
            XCTAssertEqual(pixel(rotatedPixels, x: 26, y: 18).alpha, 255)
            // Frame rule preservation is checked above, without asserting
            // rotation pixel parity for the existing axis-aligned frame path.

            let clipped = clippedSnapshot(rule: rule, color: Self.white)
            try assertActualRule(clipped, expected: rule)
            XCTAssertEqual(
                try XCTUnwrap(clipped.scene.layers.flatMap(\.paths).first).clipBounds,
                Rect(x: 32, y: 0, width: 32, height: 64))
            assertClippedCoverage(raster(clipped), rule: rule, alpha: 255)
            let unclipped = snapshot(
                filledShape(rule: rule).scaleEffect(x: 2, y: 1)
                    .frame(width: 32, height: 64)
                    .frame(width: 64, height: 64, alignment: .trailing))
            try assertActualRule(unclipped, expected: rule)
            XCTAssertEqual(pixel(raster(unclipped), x: 28, y: 32).alpha, 255, "the clip removes real paint overflow")
        }
    }

    func testAncestorClipStyleDoesNotChangeFillRule() async throws {
        let cases: [(ancestorEO: Bool, child: PathFillRule?)] = [
            (true, nil), (true, .nonZero), (false, .evenOdd),
        ]
        for entry in cases {
            let result = snapshot(
                VStack(spacing: 0) {
                    filledShape(rule: entry.child).frame(width: 64, height: 64)
                }
                .clipShape(Rectangle(), style: FillStyle(eoFill: entry.ancestorEO))
                .frame(width: 64, height: 64))
            let leaf = try pathNode(in: result.runtime.root)
            let clipNodes = descendants(of: result.runtime.root).filter { $0.clipsToBounds }
            XCTAssertEqual(clipNodes.count, 1)
            let ancestor = try XCTUnwrap(clipNodes.first)
            XCTAssertFalse(ancestor === leaf)
            XCTAssertEqual(ancestor.clipFillStyle?.eoFill, entry.ancestorEO)
            if let child = entry.child {
                XCTAssertEqual(leaf.clipFillStyle?.eoFill, child == .evenOdd)
            } else {
                XCTAssertNil(leaf.clipFillStyle)
            }
            let expected = entry.child ?? .nonZero
            try assertActualRule(result, expected: expected)
            XCTAssertEqual(
                try XCTUnwrap(result.scene.layers.flatMap(\.paths).first).clipBounds,
                Rect(x: 0, y: 0, width: 64, height: 64))
            assertRingAndHole(raster(result), ringAlpha: 255, holeAlpha: expected == .evenOdd ? 0 : 255)
        }
    }

    func testMountedRuleAlternationRepaintsReusedNode() async throws {
        let runtime = RetainedViewRuntime(clearColor: .clear, root: ViewNode())
        runtime.setRootSize(Self.size)
        let host = ComponentHost(runtime: runtime)
        let context = ViewBuildContext(
            canvasSizeProvider: { Size(width: 64, height: 64) }, invalidateHandler: {})
        var currentRule: PathFillRule? = .nonZero
        var currentColor = Self.red
        host.setComponents {
            [
                self.inheritedShape(rule: currentRule)
                    .foregroundStyle(currentColor).frame(width: 64, height: 64)
                    .makeComponent(context: context)
            ]
        }
        let original = try pathNode(in: runtime.root)
        let states: [(PathFillRule?, Color)] = [
            (.nonZero, Self.red), (.evenOdd, Self.blue), (.nonZero, Self.red),
            (.evenOdd, Self.blue), (nil, Self.red),
        ]
        var bitmaps: [BitmapSurface] = []
        for (index, state) in states.enumerated() {
            currentRule = state.0
            currentColor = state.1
            host.reload()
            let scene = runtime.renderScene(at: Double(index))
            let frame = runtime.renderFrame(at: Double(index))
            let result = WinSwiftUIRenderSnapshot(
                runtime: runtime, frame: frame, scene: scene, size: Self.size, displayScale: 1)
            let current = try pathNode(in: runtime.root)
            XCTAssertTrue(current === original, "retain the path leaf, not merely its frame wrapper")
            if let rule = currentRule {
                XCTAssertEqual(current.clipFillStyle?.eoFill, rule == .evenOdd)
            } else {
                XCTAssertNil(current.clipFillStyle, "returning to default must clear old local metadata")
            }
            XCTAssertEqual(current.backgroundColor, currentColor)
            try assertActualRule(result, expected: currentRule ?? .nonZero)
            let bitmap = raster(result)
            assertRingAndHole(bitmap, ringAlpha: 255, holeAlpha: currentRule == .evenOdd ? 0 : 255)
            XCTAssertEqual(pixel(bitmap, x: 12, y: 32).red, currentColor == Self.red ? 255 : 0)
            XCTAssertEqual(pixel(bitmap, x: 12, y: 32).blue, currentColor == Self.blue ? 255 : 0)
            bitmaps.append(bitmap)
        }
        XCTAssertEqual(bitmaps[0].pixels, bitmaps[2].pixels)
        XCTAssertEqual(bitmaps[1].pixels, bitmaps[3].pixels)
        XCTAssertEqual(bitmaps[0].pixels, bitmaps[4].pixels)
        XCTAssertNotEqual(bitmaps[0].pixels, bitmaps[1].pixels)
    }

    func testFrameBridgeAndBitmapFallbackPreserveRule() async throws {
        for rule in [PathFillRule.nonZero, .evenOdd] {
            let result = clippedSnapshot(rule: rule, color: Self.halfRed)
            try assertActualRule(result, expected: rule)
            let command = try XCTUnwrap(fills(in: result.frame).first)
            let expectedClip = Rect(x: 32, y: 0, width: 32, height: 64)
            XCTAssertEqual(command.fillRule, rule)
            XCTAssertEqual(command.clipRect, expectedClip)
            let bridged = GPUIScene(from: result.frame, surfaceSize: Size(width: 64, height: 64))
            let bridgedPaths = bridged.layers.flatMap(\.paths)
            XCTAssertEqual(bridgedPaths.count, 1)
            XCTAssertEqual(try XCTUnwrap(bridgedPaths.first).fillRule, rule)
            XCTAssertEqual(try XCTUnwrap(bridgedPaths.first).clipBounds, expectedClip)

            let degraded = FramePathDegradation.degradingPathsToBitmaps(in: result.frame)
            XCTAssertTrue(fills(in: degraded).isEmpty)
            let bitmaps = bitmapCommands(in: degraded)
            XCTAssertEqual(bitmaps.count, 1)
            let bitmapCommand = try XCTUnwrap(bitmaps.first)
            XCTAssertEqual(bitmapCommand.rect, Rect(x: 32, y: 8, width: 32, height: 48))
            XCTAssertEqual(bitmapCommand.clipRect, expectedClip)
            XCTAssertEqual(bitmapCommand.bitmap.width, 32)
            XCTAssertEqual(bitmapCommand.bitmap.height, 48)
            let surfaces = [
                raster(result),
                GPUIRawSceneRasterizer.rasterize(result.frame, size: Self.size),
                GPUIRawSceneRasterizer.rasterize(bridged, size: Self.size),
                GPUIRawSceneRasterizer.rasterize(degraded, size: Self.size),
            ]
            for surface in surfaces {
                assertClippedCoverage(surface, rule: rule, alpha: 128)
                XCTAssertEqual(pixel(surface, x: 62, y: 32).red, 255)
                XCTAssertEqual(pixel(surface, x: 62, y: 32).blue, 0)
                XCTAssertEqual(surface.pixels, surfaces[0].pixels)
            }
        }
    }

    func testGradientFirstStopFallbackPreservesRule() async throws {
        let gradient = WinSwiftUI.LinearGradient(
            colors: [Self.halfRed, Self.blue], startPoint: .leading, endPoint: .trailing)
        for rule in [PathFillRule.nonZero, .evenOdd] {
            let style = FillStyle(eoFill: rule == .evenOdd)
            let explicit = snapshot(
                CompoundShape().fill(gradient, style: style).frame(width: 64, height: 64))
            let inherited = snapshot(
                VStack(spacing: 0) {
                    CompoundShape().fill(style: style).frame(width: 64, height: 64)
                }
                .foregroundStyle(gradient))
            for result in [explicit, inherited] {
                try assertActualRule(result, expected: rule)
                XCTAssertNotNil(try pathNode(in: result.runtime.root).backgroundGradient)
                let path = try XCTUnwrap(result.scene.layers.flatMap(\.paths).first)
                XCTAssertNil(path.fillGradient, "this slice does not add generic Shape gradient fidelity")
                XCTAssertEqual(path.fillColor, Self.halfRed)
                XCTAssertEqual(try XCTUnwrap(fills(in: result.frame).first).color, Self.halfRed)
                for bitmap in [raster(result), GPUIRawSceneRasterizer.rasterize(result.frame, size: Self.size)] {
                    assertRingAndHole(bitmap, ringAlpha: 128, holeAlpha: rule == .evenOdd ? 0 : 128)
                    for x in [12, 52] {
                        XCTAssertEqual(pixel(bitmap, x: x, y: 32).red, 255)
                        XCTAssertEqual(pixel(bitmap, x: x, y: 32).blue, 0)
                    }
                }
            }
            XCTAssertEqual(raster(explicit).pixels, raster(inherited).pixels)
        }
    }

    func testSimpleQuadAndStrokeControlsRemainUnchanged() async throws {
        let baseline = snapshot(Rectangle().fill(Self.white).frame(width: 64, height: 64))
        let baselinePixels = raster(baseline)
        var strokePixels: [BitmapSurface] = []
        for rule in [PathFillRule.nonZero, .evenOdd] {
            let style = FillStyle(eoFill: rule == .evenOdd)
            let simple = snapshot(Rectangle().fill(Self.white, style: style).frame(width: 64, height: 64))
            XCTAssertTrue(simple.scene.layers.flatMap(\.paths).isEmpty)
            XCTAssertEqual(simple.scene.layers.flatMap(\.quads).count, 1)
            XCTAssertEqual(simple.scene.paintMetrics.pathsRasterizedOnCPU, 0)
            XCTAssertTrue(fills(in: simple.frame).isEmpty)
            XCTAssertEqual(raster(simple).pixels, baselinePixels.pixels)
            XCTAssertEqual(pixel(raster(simple), x: 32, y: 32).alpha, 255)

            // A connected translucent bevel join rejects the whole quad
            // route. Isolated diagonals would promote to rotated quads and
            // blend their overlap twice, so they cannot serve this control.
            let stroke = snapshot(
                AnyShape(CrossingStrokeShape())
                    .stroke(Self.halfRed, style: StrokeStyle(lineWidth: 4, lineJoin: .bevel))
                    .fill(Color.clear, style: style).frame(width: 64, height: 64))
            let strokeNode = try pathNode(in: stroke.runtime.root)
            XCTAssertEqual(strokeNode.clipFillStyle?.eoFill, rule == .evenOdd)
            XCTAssertEqual(strokeNode.borderStrokeStyle?.lineJoin, .bevel)
            XCTAssertTrue(fills(in: stroke.frame).isEmpty)
            let strokeCommands = stroke.frame.commands.filter {
                if case .strokePath = $0 { return true }
                return false
            }
            XCTAssertEqual(strokeCommands.count, 1)
            let paths = stroke.scene.layers.flatMap(\.paths)
            XCTAssertEqual(paths.count, 1)
            let strokePath = try XCTUnwrap(paths.first)
            XCTAssertEqual(strokePath.fillRule, .nonZero, "stroke outlines keep their own union rule")
            XCTAssertEqual(strokePath.lineJoin, .bevel)
            XCTAssertEqual(strokePath.strokeColor.alpha, 0.5)
            XCTAssertEqual(strokePath.elements.count, 4, "the original connected path survives fallback")
            XCTAssertTrue(stroke.scene.layers.flatMap(\.quads).isEmpty)
            let bitmap = raster(stroke)
            for surface in [bitmap, GPUIRawSceneRasterizer.rasterize(stroke.frame, size: Self.size)] {
                XCTAssertEqual(pixel(surface, x: 20, y: 20).alpha, 128, accuracy: 1)
                XCTAssertEqual(pixel(surface, x: 44, y: 20).alpha, 128, accuracy: 1)
                XCTAssertEqual(pixel(surface, x: 32, y: 32).alpha, 128, accuracy: 1, "crossing coverage is a union")
                XCTAssertEqual(pixel(surface, x: 20, y: 32).alpha, 0)
                XCTAssertEqual(pixel(surface, x: 4, y: 32).alpha, 0)
            }
            strokePixels.append(bitmap)
        }
        XCTAssertEqual(strokePixels[0].pixels, strokePixels[1].pixels)
    }

    func testPublicShapeWARPAlternationMatchesCPU() async throws {
        let renderer = D3D11BatchRenderer()
        defer { renderer.detach() }
        try renderer.attachOffscreen(size: Self.size, driver: .warpFirst)
        XCTAssertEqual(
            renderer.backendDiagnostics?.adapterIsSoftware, true,
            "this test requires software-adapter WARP, not hardware fallback")
        XCTAssertEqual(renderer.pathCacheEntryCountForTesting, 0)
        XCTAssertEqual(renderer.pathCacheMisses, 0)
        XCTAssertEqual(renderer.pathCacheHits, 0)
        let rules: [PathFillRule] = [.nonZero, .evenOdd, .nonZero, .evenOdd]
        for (index, rule) in rules.enumerated() {
            let result = snapshot(filledShape(rule: rule).frame(width: 64, height: 64))
            try assertActualRule(result, expected: rule)
            renderer.bindResources(for: result.scene)
            try renderer.render(scene: result.scene)
            let actual = try renderer.readOffscreenPixels()
            let expected = raster(result)
            XCTAssertEqual(actual.width, expected.width)
            XCTAssertEqual(actual.height, expected.height)
            let report = comparePixels(
                actual.premultipliedAlpha(), expected.premultipliedAlpha(), tolerance: 4)
            XCTAssertGreaterThan(
                report.matchRatio, 0.995,
                "public Shape mismatch: ratio=\(report.matchRatio), maxDelta=\(report.maxChannelDelta)")
            for bitmap in [actual, expected] {
                assertRingAndHole(bitmap, ringAlpha: 255, holeAlpha: rule == .evenOdd ? 0 : 255)
            }
            XCTAssertEqual(renderer.pathCacheMisses, UInt64(min(index + 1, 2)))
            XCTAssertEqual(renderer.pathCacheHits, UInt64(max(index - 1, 0)))
            XCTAssertEqual(renderer.pathCacheEntryCountForTesting, min(index + 1, 2))
        }
        XCTAssertGreaterThan(renderer.largestPathRasterPixelsForTesting, 0)
        XCTAssertLessThanOrEqual(renderer.largestPathRasterPixelsForTesting, 48 * 48)
    }

    private func filledShape(
        rule: PathFillRule?, shape: CompoundShape? = nil, color: Color = .white
    ) -> AnyShape {
        let erased = AnyShape(shape ?? CompoundShape())
        if let rule {
            return erased.fill(color, style: FillStyle(eoFill: rule == .evenOdd))
        }
        return erased.fill(color)
    }

    private func inheritedShape(rule: PathFillRule?) -> AnyShape {
        let shape = AnyShape(CompoundShape())
        if let rule { return shape.fill(style: FillStyle(eoFill: rule == .evenOdd)) }
        return shape
    }

    private func snapshot<V: View>(_ view: V, displayScale: Double = 1) -> WinSwiftUIRenderSnapshot {
        WinSwiftUIRendererSnapshotter.snapshot(
            of: view, size: Self.size, displayScale: displayScale, clearColor: .clear)
    }

    private func clippedSnapshot(rule: PathFillRule, color: Color) -> WinSwiftUIRenderSnapshot {
        // A 32-wide layout at x=32 has a 64-wide painted shape centred at
        // x=48. Its outer contour spans x=24...72, so the viewport cuts real
        // overflow; nested frame sizes alone would shrink the child instead.
        snapshot(
            filledShape(rule: rule, color: color).scaleEffect(x: 2, y: 1)
                .frame(width: 32, height: 64)
                .clipped()
                .frame(width: 64, height: 64, alignment: .trailing))
    }

    private func raster(_ snapshot: WinSwiftUIRenderSnapshot) -> BitmapSurface {
        GPUIRawSceneRasterizer.rasterize(
            snapshot.scene,
            size: IntSize(
                width: Int32(Double(snapshot.size.width) * snapshot.displayScale),
                height: Int32(Double(snapshot.size.height) * snapshot.displayScale)))
    }

    private func descendants(of root: ViewNode) -> [ViewNode] {
        [root] + root.children.flatMap { descendants(of: $0) }
    }

    private func pathNode(
        in root: ViewNode, file: StaticString = #filePath, line: UInt = #line
    ) throws -> ViewNode {
        let nodes = descendants(of: root).filter { $0.backgroundPath != nil }
        XCTAssertEqual(nodes.count, 1, file: file, line: line)
        return try XCTUnwrap(nodes.first, file: file, line: line)
    }

    private func fills(in frame: RenderFrame) -> [FillPathCommand] {
        frame.commands.compactMap {
            guard case .fillPath(let fill) = $0 else { return nil }
            return fill
        }
    }

    private func bitmapCommands(in frame: RenderFrame) -> [DrawBitmapCommand] {
        frame.commands.compactMap {
            guard case .drawBitmap(let bitmap) = $0 else { return nil }
            return bitmap
        }
    }

    private func assertActualRule(
        _ snapshot: WinSwiftUIRenderSnapshot, expected: PathFillRule,
        file: StaticString = #filePath, line: UInt = #line
    ) throws {
        let paths = snapshot.scene.layers.flatMap(\.paths)
        XCTAssertEqual(paths.count, 1, file: file, line: line)
        XCTAssertEqual(try XCTUnwrap(paths.first, file: file, line: line).fillRule, expected, file: file, line: line)
        XCTAssertTrue(snapshot.scene.layers.flatMap(\.quads).isEmpty, file: file, line: line)
        XCTAssertEqual(snapshot.scene.paintMetrics.pathsRasterizedOnCPU, 1, file: file, line: line)
        XCTAssertEqual(snapshot.scene.paintMetrics.pathsPromotedToGPU, 0, file: file, line: line)
        XCTAssertEqual(snapshot.scene.paintMetrics.quadInstancesFromPromotedPaths, 0, file: file, line: line)
        XCTAssertTrue(snapshot.scene.validate().isEmpty, file: file, line: line)
        let commands = fills(in: snapshot.frame)
        XCTAssertEqual(commands.count, 1, file: file, line: line)
        XCTAssertEqual(try XCTUnwrap(commands.first, file: file, line: line).fillRule, expected, file: file, line: line)
    }

    private func assertRingAndHole(
        _ bitmap: BitmapSurface, ringAlpha: Int, holeAlpha: Int,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        for point in [(12, 32), (52, 32), (32, 12), (32, 52)] {
            XCTAssertEqual(pixel(bitmap, x: point.0, y: point.1).alpha, ringAlpha, accuracy: 1, file: file, line: line)
        }
        XCTAssertEqual(pixel(bitmap, x: 34, y: 28).alpha, holeAlpha, accuracy: 1, file: file, line: line)
        XCTAssertEqual(pixel(bitmap, x: 4, y: 32).alpha, 0, file: file, line: line)
    }

    private func assertClippedCoverage(
        _ bitmap: BitmapSurface, rule: PathFillRule, alpha: Int,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        XCTAssertEqual(pixel(bitmap, x: 28, y: 32).alpha, 0, "the left ring is clipped", file: file, line: line)
        XCTAssertEqual(pixel(bitmap, x: 36, y: 32).alpha, alpha, accuracy: 1, file: file, line: line)
        XCTAssertEqual(pixel(bitmap, x: 62, y: 32).alpha, alpha, accuracy: 1, file: file, line: line)
        XCTAssertEqual(pixel(bitmap, x: 48, y: 12).alpha, alpha, accuracy: 1, file: file, line: line)
        XCTAssertEqual(
            pixel(bitmap, x: 54, y: 28).alpha, rule == .evenOdd ? 0 : alpha, accuracy: 1, file: file, line: line)
        XCTAssertEqual(pixel(bitmap, x: 4, y: 32).alpha, 0, file: file, line: line)
    }

    private func pixel(
        _ bitmap: BitmapSurface, x: Int, y: Int,
        file: StaticString = #filePath, line: UInt = #line
    ) -> (red: Int, green: Int, blue: Int, alpha: Int) {
        guard x >= 0, y >= 0, x < Int(bitmap.width), y < Int(bitmap.height) else {
            XCTFail("sample lies outside the bitmap", file: file, line: line)
            return (0, 0, 0, 0)
        }
        let offset = y * Int(bitmap.bytesPerRow) + x * 4
        guard offset + 3 < bitmap.pixels.count else {
            XCTFail("sample lies outside the pixel buffer", file: file, line: line)
            return (0, 0, 0, 0)
        }
        return (
            red: Int(bitmap.pixels[offset + 2]), green: Int(bitmap.pixels[offset + 1]),
            blue: Int(bitmap.pixels[offset]), alpha: Int(bitmap.pixels[offset + 3])
        )
    }
}
