import Foundation
import SwiftWindowsCore
import SwiftWindowsGraphics
import XCTest

@testable import SwiftWindowsUI

// These fixtures exercise the existing Windows stack and production limits;
// they do not change stack size or skip accepted depths.
@MainActor
final class CanvasSymbolMixedDepthTests: XCTestCase {
    private let blue = Color(red: 0, green: 0, blue: 1, alpha: 1)
    private let targetSize = IntSize(width: 32, height: 32)

    private func assertUnchangedSourceLimits(file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(GPUISceneLimits.maxImageRenderPassDepth, 32, file: file, line: line)
        XCTAssertEqual(GPUISceneLimits.maxImageRenderPassCount, 1_024, file: file, line: line)
        XCTAssertEqual(GPUISceneLimits.maxImageRenderPassPixels, 4_194_304, file: file, line: line)
        XCTAssertEqual(GPUISceneLimits.maxImageRenderPassTotalPixels, 16_777_216, file: file, line: line)
    }

    private func paint(_ symbol: CanvasSymbolSource, extent: Double) -> GPUIScene {
        let runtime = RetainedViewRuntime(clearColor: .clear)
        runtime.setRootSize(targetSize)
        let canvas = UI.canvas(frame: Rect(x: 0, y: 0, width: 32, height: 32)) { context, _ in
            context.draw(symbol, in: Rect(x: 8, y: 8, width: extent, height: extent))
        }.makeNode(runtime: runtime)
        runtime.root.addChild(canvas)
        return runtime.renderScene()
    }

    // Test inspection is iterative so the helper adds no recursive stack
    // pressure and includes every retained source namespace exactly once.
    private func namespaces(in scene: GPUIScene) -> [(scene: GPUIScene, depth: Int)] {
        var pending: [(scene: GPUIScene, depth: Int)] = [(scene, 0)]
        var result: [(scene: GPUIScene, depth: Int)] = []
        while let current = pending.popLast() {
            result.append(current)
            pending.append(contentsOf: current.scene.imageRenderPasses.map { ($0.scene, current.depth + 1) })
        }
        return result
    }

    private func pixel(_ surface: BitmapSurface, x: Int, y: Int) -> [UInt8] {
        let premultiplied = surface.premultipliedAlpha()
        let offset = y * Int(premultiplied.bytesPerRow) + x * 4
        return Array(premultiplied.pixels[offset..<(offset + 4)])
    }

    func testMaximumDepthAlternatingSymbolAndColorSourcesKeepsTheVisibleLeaf() async throws {
        assertUnchangedSourceLimits()
        var sourcePaints = 0
        let bounds = Rect(x: 0, y: 0, width: 2, height: 2)
        func source(pairsRemaining: Int) -> CanvasSymbolSource? {
            CanvasSymbolSource(displayScale: 1) { runtime in
                let canvas = UI.canvas(frame: bounds) { context, _ in
                    sourcePaints += 1
                    if pairsRemaining == 1 {
                        context.fill(bounds, with: .color(self.blue))
                    } else if let child = source(pairsRemaining: pairsRemaining - 1) {
                        context.draw(child, in: bounds)
                    } else {
                        XCTFail("A tiny fixture symbol must be accepted")
                    }
                }.makeNode(runtime: runtime)
                canvas.colorEffects = [.brightness(0)]
                return canvas
            }
        }

        // Each symbol contributes its own source plus one color source.
        // Sixteen pairs therefore reach the advertised depth of 32 exactly.
        let first = try XCTUnwrap(source(pairsRemaining: 16))
        let rejectionsBefore = CanvasSymbolSource.rejectionCount
        let scene = paint(first, extent: 2)
        let graph = namespaces(in: scene)
        let passes = graph.flatMap { $0.scene.imageRenderPasses }
        XCTAssertEqual(sourcePaints, 16)
        XCTAssertEqual(CanvasSymbolSource.rejectionCount, rejectionsBefore)
        XCTAssertTrue(scene.validate().isEmpty)
        XCTAssertEqual(graph.map { $0.depth }.max(), 32)
        XCTAssertEqual(passes.count, 32)
        XCTAssertTrue(graph.allSatisfy { $0.scene.imageResources.isEmpty }, "Mixed sources must remain scene-backed")
        for (index, pass) in passes.enumerated() {
            let expectedEffects: [SceneColorEffect] = index.isMultiple(of: 2) ? [] : [.brightness(0)]
            XCTAssertEqual(pass.colorEffects, expectedEffects)
            XCTAssertEqual(pass.size, IntSize(width: 2, height: 2))
        }
        let sourcePixels = passes.reduce(Int64(0)) { $0 + Int64($1.size.width) * Int64($1.size.height) }
        XCTAssertEqual(sourcePixels, 128, "The maximum-depth fixture needs only 32 four-pixel sources")
        let pixels = GPUIRawSceneRasterizer.rasterize(scene, size: targetSize)
        XCTAssertEqual(pixel(pixels, x: 8, y: 8), [255, 0, 0, 255])
        XCTAssertEqual(pixel(pixels, x: 7, y: 8), [0, 0, 0, 0])
    }

    func testMaximumSymbolDepthWithAGroupAtEveryLevelKeepsTheVisibleLeaf() async throws {
        assertUnchangedSourceLimits()
        var sourcePaints = 0
        var groupCount = 0
        let bounds = Rect(x: 0, y: 0, width: 2, height: 2)
        func source(levelsRemaining: Int) -> CanvasSymbolSource? {
            CanvasSymbolSource(displayScale: 1) { runtime in
                groupCount += 1
                let canvas = UI.canvas(frame: bounds) { context, _ in
                    sourcePaints += 1
                    if levelsRemaining == 1 {
                        context.fill(bounds, with: .color(self.blue))
                    } else if let child = source(levelsRemaining: levelsRemaining - 1) {
                        context.draw(child, in: bounds)
                    } else {
                        XCTFail("A tiny fixture symbol must be accepted")
                    }
                }.makeNode(runtime: runtime)
                // The group must wrap the Canvas child. A drawingGroup on
                // the Canvas itself does not isolate its own draw callback.
                return ViewNode(frame: bounds, drawingGroup: RetainedDrawingGroup(), children: [canvas])
            }
        }

        let first = try XCTUnwrap(source(levelsRemaining: 32))
        let rejectionsBefore = CanvasSymbolSource.rejectionCount
        let scene = paint(first, extent: 2)
        XCTAssertEqual(groupCount, 32)
        XCTAssertEqual(sourcePaints, 32, "Groups must not reduce the accepted symbol recursion depth")
        XCTAssertEqual(CanvasSymbolSource.rejectionCount, rejectionsBefore)
        XCTAssertTrue(scene.validate().isEmpty)
        let graph = namespaces(in: scene)
        let passes = graph.flatMap { $0.scene.imageRenderPasses }
        // Each group bakes its child's symbol only after that symbol has
        // completed. The 32 recording frames overlap even though the final
        // graph retains just the outer source and its four-pixel bitmap.
        XCTAssertEqual(passes.count, 1)
        XCTAssertEqual(try XCTUnwrap(passes.first).size, IntSize(width: 2, height: 2))
        let bitmaps = graph.flatMap { $0.scene.imageResources }.map(\.bitmap)
        XCTAssertEqual(bitmaps.count, 1)
        XCTAssertEqual(try XCTUnwrap(bitmaps.first).width, 2)
        XCTAssertEqual(try XCTUnwrap(bitmaps.first).height, 2)
        XCTAssertEqual(graph.reduce(0) { $0 + $1.scene.paintMetrics.compositingGroupsRasterized }, 1)
        let pixels = GPUIRawSceneRasterizer.rasterize(scene, size: targetSize)
        XCTAssertEqual(pixel(pixels, x: 8, y: 8), [255, 0, 0, 255])
        XCTAssertEqual(pixel(pixels, x: 7, y: 8), [0, 0, 0, 0])
    }

    func testMaximumSymbolDepthWithBlurAndGroupsAtEveryLevelKeepsBlueCoverage() async throws {
        for isolatesInGroup in [false, true] {
            assertUnchangedSourceLimits()
            var sourcePaints = 0
            var blurCount = 0
            let bounds = Rect(x: 0, y: 0, width: 8, height: 8)
            func source(levelsRemaining: Int) -> CanvasSymbolSource? {
                CanvasSymbolSource(displayScale: 1) { runtime in
                    blurCount += 1
                    let canvas = UI.canvas(frame: bounds) { context, _ in
                        sourcePaints += 1
                        if levelsRemaining == 1 {
                            context.fill(bounds, with: .color(self.blue))
                        } else if let child = source(levelsRemaining: levelsRemaining - 1) {
                            context.draw(child, in: bounds)
                        } else {
                            XCTFail("A tiny fixture symbol must be accepted")
                        }
                    }.makeNode(runtime: runtime)
                    let blurred = ViewNode(frame: bounds, contentBlurRadius: 1, children: [canvas])
                    // The combined case retains both kinds of CPU isolation
                    // while entering every accepted symbol depth.
                    return isolatesInGroup
                        ? ViewNode(frame: bounds, drawingGroup: RetainedDrawingGroup(), children: [blurred]) : blurred
                }
            }

            let first = try XCTUnwrap(source(levelsRemaining: 32))
            let rejectionsBefore = CanvasSymbolSource.rejectionCount
            let scene = paint(first, extent: 8)
            XCTAssertEqual(blurCount, 32)
            XCTAssertEqual(sourcePaints, 32, "Blur recording frames must not reduce accepted symbol depth")
            XCTAssertEqual(CanvasSymbolSource.rejectionCount, rejectionsBefore)
            XCTAssertTrue(scene.validate().isEmpty)
            let graph = namespaces(in: scene)
            let passes = graph.flatMap { $0.scene.imageRenderPasses }
            XCTAssertEqual(passes.count, 1)
            XCTAssertEqual(graph.flatMap { $0.scene.imageResources }.count, 1)
            XCTAssertEqual(graph.reduce(0) { $0 + $1.scene.paintMetrics.contentBlurPasses }, isolatesInGroup ? 0 : 1)
            XCTAssertEqual(
                graph.reduce(0) { $0 + $1.scene.paintMetrics.compositingGroupsRasterized }, isolatesInGroup ? 1 : 0)
            let outerSource = try XCTUnwrap(passes.first)
            // Each CPU blur has its own 8x8 frame and one-pixel margin; even
            // alignment padding keeps every source far below the pixel budget.
            XCTAssertLessThanOrEqual(outerSource.size.width, 12)
            XCTAssertLessThanOrEqual(outerSource.size.height, 12)
            let pixels = GPUIRawSceneRasterizer.rasterize(scene, size: targetSize)
            let center = pixel(pixels, x: 12, y: 12)
            // Repeated blur legitimately changes alpha. Pure blue must still be
            // visible, without depending on a tolerance or a particular kernel.
            XCTAssertGreaterThan(center[3], 0)
            XCTAssertEqual(center[0], center[3])
            XCTAssertEqual(center[1], 0)
            XCTAssertEqual(center[2], 0)
            XCTAssertEqual(pixel(pixels, x: 0, y: 0), [0, 0, 0, 0])
        }
    }
}
