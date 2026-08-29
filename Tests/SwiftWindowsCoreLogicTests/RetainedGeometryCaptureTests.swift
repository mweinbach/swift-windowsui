import Foundation
import SwiftWindowsCore
import SwiftWindowsGraphics
@preconcurrency import XCTest

@testable import SwiftWindowsUI
@testable import WinSwiftUI

@MainActor
private final class GeometryCaptureWorkProbe {
    var measures = 0
    var layouts = 0
    var rasterizations = 0
    var commandAttempts = 0

    var counts: [Int] { [measures, layouts, rasterizations, commandAttempts] }
}

@MainActor
final class RetainedGeometryCaptureTests: XCTestCase {
    override func tearDown() async throws {
        await MainActor.run {
            NativeTextRenderer.resetTestingOverrides()
            NativeFontAvailability.resetTestingOverrides()
            NativeFontAvailability.resetProbeCacheForTesting()
            TextRasterCache.restoreSharedForTesting()
            SystemUIFontFace.resetAvailabilityCacheForTesting()
        }
    }

    private func installSyntheticText(_ probe: GeometryCaptureWorkProbe) {
        NativeTextRenderer.resetTestingOverrides()
        NativeFontAvailability.resetTestingOverrides()
        NativeFontAvailability.resetProbeCacheForTesting()
        SystemUIFontFace.resetAvailabilityCacheForTesting()
        SystemUIFontFace.availabilityOverrideForTesting = false
        NativeFontAvailability.testingOverrides.hasGlyph = { _, _ in true }
        NativeTextRenderer.testingOverrides.measure = { _, _, _, _ in
            probe.measures += 1
            return Size(width: 24, height: 14)
        }
        NativeTextRenderer.testingOverrides.layout = { _, _, _, _ in
            probe.layouts += 1
            return nil
        }
        NativeTextRenderer.testingOverrides.appendCommands = { _, _, _, _, _, _ in
            probe.commandAttempts += 1
            return false
        }
        NativeTextRenderer.testingOverrides.rasterize = { _, _, _ in
            probe.rasterizations += 1
            return BitmapSurface(
                width: 2, height: 2, bytesPerRow: 8,
                pixels: Data([255, 255, 255, 255, 0, 0, 0, 0, 0, 0, 0, 0, 255, 255, 255, 255]),
                format: .bgra8Premultiplied)
        }
        TextRasterCache.installForTesting(TextRasterCache(maxEntryCount: 32, maxMemoryBytes: 4096))
    }

    private func syntheticSnapshot(
        geometryDiagnostics: Bool?, probe: GeometryCaptureWorkProbe,
        text: String = "Geometry capture fixture"
    ) -> WinSwiftUIRenderSnapshot {
        installSyntheticText(probe)
        let view = VStack(spacing: 4) {
            Text(text).font(.system(size: 17))
            Rectangle().fill(WinSwiftUI.Color.white).frame(width: 24, height: 8)
        }
        .frame(width: 96, height: 64)
        if let geometryDiagnostics {
            return WinSwiftUIRendererSnapshotter.snapshot(
                of: view, size: IntSize(width: 96, height: 64), timestamp: 5_000,
                geometryDiagnostics: geometryDiagnostics)
        }
        return WinSwiftUIRendererSnapshotter.snapshot(
            of: view, size: IntSize(width: 96, height: 64), timestamp: 5_000)
    }

    private func makeRetainedRuntime(children: [ViewNode]) -> RetainedViewRuntime {
        let runtime = RetainedViewRuntime(
            root: ViewNode(
                frame: Rect(x: 0, y: 0, width: 160, height: 80),
                isHitTestVisible: false, children: children))
        runtime.clock = { 5_000 }
        return runtime
    }

    private func runtimeCounters(_ runtime: RetainedViewRuntime) -> [UInt64] {
        [
            runtime.layoutPassID, runtime.contentRevision,
            UInt64(runtime.sceneRebuildCount), UInt64(runtime.geometryReaderResolveCount),
        ]
    }

    private func captured(
        _ result: RetainedSceneGeometryDiagnostic?,
        file: StaticString = #filePath, line: UInt = #line
    ) throws -> RetainedSceneGeometryDiagnostic {
        let result = try XCTUnwrap(result, file: file, line: line)
        XCTAssertEqual(result.status, .captured, file: file, line: line)
        XCTAssertNil(result.reason, file: file, line: line)
        XCTAssertEqual(result.phase, "paintedSceneBeforeEndRenderPass", file: file, line: line)
        XCTAssertNotNil(result.layoutPassID, file: file, line: line)
        XCTAssertNotNil(result.contentRevisionBeforePublish, file: file, line: line)
        return result
    }

    private func unavailable(
        _ result: RetainedSceneGeometryDiagnostic?, reason: String,
        file: StaticString = #filePath, line: UInt = #line
    ) throws {
        let result = try XCTUnwrap(result, file: file, line: line)
        XCTAssertEqual(result.status, .unavailable, file: file, line: line)
        XCTAssertEqual(result.reason, reason, file: file, line: line)
        XCTAssertTrue(result.nodes.isEmpty, "A failure cannot export a visited prefix.", file: file, line: line)
    }

    func testDefaultAndExplicitlyDisabledCaptureAreEquivalent() async {
        let defaultProbe = GeometryCaptureWorkProbe()
        let normal = syntheticSnapshot(geometryDiagnostics: nil, probe: defaultProbe)
        let disabledProbe = GeometryCaptureWorkProbe()
        let disabled = syntheticSnapshot(geometryDiagnostics: false, probe: disabledProbe)

        XCTAssertNil(normal.sceneGeometryDiagnostic)
        XCTAssertNil(disabled.sceneGeometryDiagnostic)
        XCTAssertEqual(disabled.scene, normal.scene)
        XCTAssertEqual(runtimeCounters(disabled.runtime), runtimeCounters(normal.runtime))
        XCTAssertEqual(disabledProbe.counts, defaultProbe.counts)
        XCTAssertGreaterThan(defaultProbe.measures, 0)
        XCTAssertEqual(
            GPUIRawSceneRasterizer.rasterize(disabled.scene, size: disabled.size).pixels,
            GPUIRawSceneRasterizer.rasterize(normal.scene, size: normal.size).pixels)
    }

    func testEnabledCapturePreservesPixelsAndMeasurementWork() async throws {
        let normalProbe = GeometryCaptureWorkProbe()
        let normal = syntheticSnapshot(geometryDiagnostics: nil, probe: normalProbe)
        let enabledProbe = GeometryCaptureWorkProbe()
        let enabled = syntheticSnapshot(geometryDiagnostics: true, probe: enabledProbe)
        let result = try captured(enabled.sceneGeometryDiagnostic)

        XCTAssertEqual(enabled.scene, normal.scene)
        XCTAssertEqual(enabledProbe.counts, normalProbe.counts)
        XCTAssertGreaterThan(enabledProbe.measures, 0)
        XCTAssertEqual(runtimeCounters(enabled.runtime), runtimeCounters(normal.runtime))
        XCTAssertLessThan(try XCTUnwrap(result.layoutPassID), enabled.runtime.layoutPassID)
        XCTAssertLessThan(
            try XCTUnwrap(result.contentRevisionBeforePublish), enabled.runtime.contentRevision)
        XCTAssertEqual(
            GPUIRawSceneRasterizer.rasterize(enabled.scene, size: enabled.size).pixels,
            GPUIRawSceneRasterizer.rasterize(normal.scene, size: normal.size).pixels)
        XCTAssertEqual(result.nodes.first?.path, [])
        XCTAssertNil(result.nodes.first?.parentPath)
        let text = try XCTUnwrap(result.nodes.first { $0.text == "Geometry capture fixture" })
        let style = try XCTUnwrap(text.requestedTextStyle)
        XCTAssertEqual(style.nativeFontSize, 17)
        XCTAssertFalse(style.fontFamily.isEmpty)
        XCTAssertFalse(style.isItalic)
        XCTAssertFalse(style.hasSpans)
        XCTAssertEqual(style.insets.count, 4)
        XCTAssertTrue(style.insets.allSatisfy(\.isFinite))
        XCTAssertEqual(text.resolvedFrame.count, 4)
        XCTAssertEqual(text.resolvedContentSize.count, 2)
        XCTAssertTrue(text.resolvedFrame.allSatisfy(\.isFinite))
        let measurements = result.nodes.compactMap(\.measurement)
        XCTAssertFalse(measurements.isEmpty, "The fixture must exercise stored measurement metadata.")
        for measurement in measurements {
            XCTAssertEqual(measurement.constraints.count, 4)
            XCTAssertEqual(measurement.unbounded.count, 4)
            XCTAssertEqual(measurement.displayScale, 1)
            for index in 0..<4 {
                if measurement.unbounded[index] {
                    XCTAssertTrue(index == 1 || index == 3)
                    XCTAssertNil(measurement.constraints[index])
                } else {
                    XCTAssertTrue(try XCTUnwrap(measurement.constraints[index]).isFinite)
                }
            }
        }
    }

    func testReadingCompletedCaptureAddsNoLayoutOrMeasurement() async throws {
        let probe = GeometryCaptureWorkProbe()
        let snapshot = syntheticSnapshot(geometryDiagnostics: true, probe: probe)
        let original = try captured(snapshot.sceneGeometryDiagnostic)
        var layoutCalls = 0
        snapshot.runtime.root.onLayout = { _ in layoutCalls += 1 }
        let work = probe.counts
        let counters = runtimeCounters(snapshot.runtime)

        for _ in 0..<8 {
            XCTAssertEqual(snapshot.sceneGeometryDiagnostic, original)
            XCTAssertEqual(snapshot.sceneGeometryDiagnostic?.nodes, original.nodes)
        }

        XCTAssertEqual(probe.counts, work)
        XCTAssertEqual(runtimeCounters(snapshot.runtime), counters)
        XCTAssertEqual(layoutCalls, 0)
    }

    func testFirstSceneCapturePrecedesDeferredScrollMutationAndAuxiliaryRender() async throws {
        let marker = ViewNode(
            frame: Rect(x: 0, y: 20, width: 40, height: 8), backgroundColor: .white)
        let content = ViewNode(
            frame: Rect(x: 0, y: 0, width: 80, height: 400), children: [marker])
        let scroller = ViewNode(
            frame: Rect(x: 10, y: 10, width: 80, height: 80),
            clipsToBounds: true, scrollAxis: .vertical, children: [content])
        let runtime = makeRetainedRuntime(children: [scroller])
        let firstRequest = runtime.requestSceneGeometryDiagnostic()
        var auxiliaryRequest: RetainedSceneGeometryDiagnosticRequest?
        var callbackScene: GPUIScene?
        var deliveries = 0
        scroller.observeScrollGeometry(
            of: { $0.contentSize.height },
            action: { [weak runtime, weak content, weak marker] _, _ in
                deliveries += 1
                guard deliveries == 1, let runtime, let content, let marker else { return }
                // Existing scroll delivery runs after endRenderPass, without a new test seam.
                XCTAssertEqual(firstRequest.result?.status, .captured)
                let next = runtime.requestSceneGeometryDiagnostic()
                auxiliaryRequest = next
                XCTAssertNil(next.result, "The first request must be cleared before deferred callbacks.")
                content.frame.size.height = 600
                marker.frame.origin.x = 12
                callbackScene = runtime.renderScene(at: 5_001)
            }
        )

        let firstScene = runtime.renderScene(at: 5_000)
        let first = try captured(firstRequest.result)
        try unavailable(auxiliaryRequest?.result, reason: "noFreshScene")
        let firstContent = try XCTUnwrap(first.nodes.first { $0.path == [0, 0] })
        let firstMarker = try XCTUnwrap(first.nodes.first { $0.path == [0, 0, 0] })

        XCTAssertEqual(deliveries, 1, "Observer delivery cannot recursively refresh layout.")
        XCTAssertEqual(try XCTUnwrap(callbackScene), firstScene)
        XCTAssertEqual(firstContent.resolvedFrame, [0, 0, 80, 400])
        XCTAssertEqual(firstMarker.resolvedFrame, [0, 20, 40, 8])
        XCTAssertEqual(content.frame.size.height, 600)
        XCTAssertEqual(marker.frame.origin.x, 12)
        XCTAssertEqual(content.resolvedFrame.size.height, 400)
        XCTAssertEqual(marker.resolvedFrame.origin.x, 0)
        let paintedMarker = try XCTUnwrap(
            firstScene.layers.flatMap(\.quads).first { $0.width == 40 && $0.height == 8 })
        XCTAssertEqual(Double(paintedMarker.x), 10)
        XCTAssertEqual(Double(paintedMarker.y), 30)

        // Snapshotter's auxiliary frame runs after observer delivery and settles the mutation.
        _ = runtime.renderFrame(at: 5_002)
        XCTAssertEqual(content.resolvedFrame.size.height, 600)
        XCTAssertEqual(marker.resolvedFrame.origin.x, 12)
        XCTAssertLessThan(try XCTUnwrap(first.layoutPassID), runtime.layoutPassID)
        XCTAssertEqual(firstRequest.result, first)
        let laterRequest = runtime.requestSceneGeometryDiagnostic()
        _ = runtime.renderScene(at: 5_003)
        let later = try captured(laterRequest.result)
        let laterMarker = try XCTUnwrap(later.nodes.first { $0.path == [0, 0, 0] })
        XCTAssertEqual(laterMarker.resolvedFrame, [12, 20, 40, 8])
        XCTAssertLessThan(try XCTUnwrap(first.layoutPassID), try XCTUnwrap(later.layoutPassID))
        try unavailable(auxiliaryRequest?.result, reason: "noFreshScene")
        XCTAssertEqual(firstRequest.result, first, "Later rendering cannot rewrite the first-scene value.")
    }

    func testCachedSceneConsumesRequestWithoutForcingFreshWork() async throws {
        let marker = ViewNode(frame: Rect(x: 4, y: 6, width: 20, height: 12), backgroundColor: .white)
        let runtime = makeRetainedRuntime(children: [marker])
        var layoutCalls = 0
        marker.onLayout = { _ in layoutCalls += 1 }
        let first = runtime.renderScene(at: 5_000)
        let counters = runtimeCounters(runtime)
        let calls = layoutCalls
        let request = runtime.requestSceneGeometryDiagnostic()

        XCTAssertNil(request.result)
        XCTAssertEqual(runtimeCounters(runtime), counters)
        XCTAssertEqual(runtime.renderScene(at: 5_001), first)
        try unavailable(request.result, reason: "noFreshScene")
        XCTAssertEqual(runtimeCounters(runtime), counters)
        XCTAssertEqual(layoutCalls, calls)
        marker.backgroundColor = .black
        let fresh = runtime.requestSceneGeometryDiagnostic()
        _ = runtime.renderScene(at: 5_002)
        _ = try captured(fresh.result)
        try unavailable(request.result, reason: "noFreshScene")
    }

    func testPacedEarlyReturnConsumesRequestWithoutRefreshingLayout() async throws {
        let marker = ViewNode(frame: Rect(x: 0, y: 0, width: 20, height: 12), backgroundColor: .white)
        let runtime = makeRetainedRuntime(children: [marker])
        runtime.minimumFrameInterval = 1.0 / 60.0
        let first = runtime.renderScene(at: 1.0)
        marker.backgroundColor = .black
        let counters = runtimeCounters(runtime)
        let request = runtime.requestSceneGeometryDiagnostic()

        XCTAssertEqual(runtime.renderScene(at: 1.005), first)
        try unavailable(request.result, reason: "noFreshScene")
        XCTAssertEqual(runtimeCounters(runtime), counters)
        XCTAssertTrue(runtime.isDirty)
        let fresh = runtime.requestSceneGeometryDiagnostic()
        _ = runtime.renderScene(at: 1.020)
        _ = try captured(fresh.result)
        try unavailable(request.result, reason: "noFreshScene")
    }

    func testFrameRenderConsumesArmedSceneRequest() async throws {
        let runtime = makeRetainedRuntime(children: [
            ViewNode(frame: Rect(x: 0, y: 0, width: 20, height: 12), backgroundColor: .white)
        ])
        let request = runtime.requestSceneGeometryDiagnostic()
        _ = runtime.renderFrame(at: 5_000)
        try unavailable(request.result, reason: "frameRender")
        let fresh = runtime.requestSceneGeometryDiagnostic()
        _ = runtime.renderScene(at: 5_001)
        _ = try captured(fresh.result)
        try unavailable(request.result, reason: "frameRender")
    }

    func testNestedSceneOrFrameCannotSupplyTheOuterCapture() async throws {
        for usesScene in [true, false] {
            let trigger = ViewNode(frame: Rect(x: 0, y: 0, width: 20, height: 12), backgroundColor: .white)
            let runtime = makeRetainedRuntime(children: [trigger])
            var nestedCalls = 0
            trigger.onAppear = { [weak runtime] in
                guard let runtime, nestedCalls == 0 else { return }
                nestedCalls += 1
                if usesScene {
                    _ = runtime.renderScene(at: 5_000)
                } else {
                    _ = runtime.renderFrame(at: 5_000)
                }
            }
            let request = runtime.requestSceneGeometryDiagnostic()
            _ = runtime.renderScene(at: 5_000)
            XCTAssertEqual(nestedCalls, 1)
            try unavailable(request.result, reason: "nestedRender")
            trigger.backgroundColor = .black
            let next = runtime.requestSceneGeometryDiagnostic()
            _ = runtime.renderScene(at: 5_001)
            _ = try captured(next.result)
            try unavailable(request.result, reason: "nestedRender")
        }
    }

    func testRequestDuringRenderIsUnavailableAndDoesNotLeakToTheNextPass() async throws {
        let trigger = ViewNode(frame: Rect(x: 0, y: 0, width: 20, height: 12), backgroundColor: .white)
        let runtime = makeRetainedRuntime(children: [trigger])
        var rejected: RetainedSceneGeometryDiagnosticRequest?
        trigger.onAppear = { [weak runtime] in
            rejected = runtime?.requestSceneGeometryDiagnostic()
        }
        _ = runtime.renderScene(at: 5_000)
        try unavailable(rejected?.result, reason: "requestDuringRender")
        trigger.backgroundColor = .black
        let next = runtime.requestSceneGeometryDiagnostic()
        _ = runtime.renderScene(at: 5_001)
        _ = try captured(next.result)
        try unavailable(rejected?.result, reason: "requestDuringRender")
    }

    func testOverlappingRequestsRejectBothWithoutDoingWork() async throws {
        let runtime = makeRetainedRuntime(children: [])
        let counters = runtimeCounters(runtime)
        let first = runtime.requestSceneGeometryDiagnostic()
        XCTAssertNil(first.result)
        let second = runtime.requestSceneGeometryDiagnostic()
        try unavailable(first.result, reason: "overlappingRequest")
        try unavailable(second.result, reason: "overlappingRequest")
        XCTAssertEqual(runtimeCounters(runtime), counters)
        let next = runtime.requestSceneGeometryDiagnostic()
        XCTAssertNil(next.result)
        _ = runtime.renderScene(at: 5_000)
        _ = try captured(next.result)
    }

    func testPendingLayoutDuringPaintRejectsTheWholeCapture() async throws {
        let marker = ViewNode(frame: Rect(x: 0, y: 0, width: 20, height: 12), backgroundColor: .white)
        let trigger = ViewNode(frame: Rect(x: 40, y: 0, width: 20, height: 12))
        var mutations = 0
        trigger.canvasDraw = { _, _ in
            guard mutations == 0 else { return }
            mutations += 1
            marker.frame.size.width = 30
        }
        let runtime = makeRetainedRuntime(children: [marker, trigger])
        let request = runtime.requestSceneGeometryDiagnostic()
        _ = runtime.renderScene(at: 5_000)
        XCTAssertEqual(mutations, 1)
        try unavailable(request.result, reason: "layoutUnavailable")
        let next = runtime.requestSceneGeometryDiagnostic()
        _ = runtime.renderScene(at: 5_001)
        let result = try captured(next.result)
        XCTAssertTrue(result.nodes.contains { $0.path == [1] && $0.hasCanvas })
    }

    func testNonfiniteStoredGeometryRejectsTheWholeCapture() async throws {
        let marker = ViewNode(frame: Rect(x: 0, y: 0, width: 20, height: 12), backgroundColor: .white)
        let trigger = ViewNode(frame: Rect(x: 40, y: 0, width: 20, height: 12))
        var corrupted = false
        trigger.canvasDraw = { _, _ in
            guard !corrupted else { return }
            corrupted = true
            // The earlier sibling has already painted. Corrupt stored diagnostic input only.
            marker.resolvedFrame.origin.x = .nan
        }
        let runtime = makeRetainedRuntime(children: [marker, trigger])
        let request = runtime.requestSceneGeometryDiagnostic()
        _ = runtime.renderScene(at: 5_000)
        XCTAssertTrue(corrupted)
        try unavailable(request.result, reason: "invalidStoredGeometry")
    }

    func testFixedNodeLimitRejectsWholeOverflowWithoutChangingTheScene() async throws {
        XCTAssertEqual(RetainedSceneGeometryLimits.maxNodes, 128)
        XCTAssertEqual(RetainedSceneGeometryLimits.maxDepth, 32)
        XCTAssertEqual(RetainedSceneGeometryLimits.maxPaths, 256)
        XCTAssertEqual(RetainedSceneGeometryLimits.maxPathElements, 4096)
        XCTAssertEqual(RetainedSceneGeometryLimits.maxSidecarBytes, 262_144)
        for children in [RetainedSceneGeometryLimits.maxNodes - 1, RetainedSceneGeometryLimits.maxNodes] {
            @MainActor
            func makeRuntime() -> RetainedViewRuntime {
                makeRetainedRuntime(
                    children: (0..<children).map { index in
                        ViewNode(
                            frame: Rect(x: Double(index), y: 0, width: 1, height: 1), backgroundColor: .white)
                    })
            }
            let baseline = makeRuntime()
            let normal = baseline.renderScene(at: 5_000)
            let enabled = makeRuntime()
            let request = enabled.requestSceneGeometryDiagnostic()
            XCTAssertEqual(enabled.renderScene(at: 5_000), normal)
            XCTAssertEqual(runtimeCounters(enabled), runtimeCounters(baseline))
            if children + 1 == RetainedSceneGeometryLimits.maxNodes {
                XCTAssertEqual(try captured(request.result).nodes.count, RetainedSceneGeometryLimits.maxNodes)
            } else {
                try unavailable(request.result, reason: "nodeLimitExceeded")
            }
        }
    }

    func testDepthLimitAcceptsBoundaryAndRejectsWholeOverflow() async throws {
        for depth in [RetainedSceneGeometryLimits.maxDepth, RetainedSceneGeometryLimits.maxDepth + 1] {
            let root = ViewNode(frame: Rect(x: 0, y: 0, width: 20, height: 20))
            var parent = root
            for _ in 0..<depth {
                let child = ViewNode(frame: Rect(x: 0, y: 0, width: 20, height: 20))
                parent.addChild(child)
                parent = child
            }
            let runtime = RetainedViewRuntime(root: root)
            let request = runtime.requestSceneGeometryDiagnostic()
            _ = runtime.renderScene(at: 5_000)
            if depth == RetainedSceneGeometryLimits.maxDepth {
                let result = try captured(request.result)
                XCTAssertEqual(result.nodes.count, depth + 1)
                XCTAssertEqual(result.nodes.last?.path.count, depth)
            } else {
                try unavailable(request.result, reason: "depthLimitExceeded")
            }
        }
    }

    func testOverLimitTextPayloadCannotExportAVisitedNodePrefix() async throws {
        let probe = GeometryCaptureWorkProbe()
        let snapshot = syntheticSnapshot(
            geometryDiagnostics: true, probe: probe,
            text: String(repeating: "x", count: RetainedSceneGeometryLimits.maxSidecarBytes + 1))
        try unavailable(snapshot.sceneGeometryDiagnostic, reason: "sidecarLimitExceeded")
        XCTAssertGreaterThan(probe.measures, 0)
    }

    private func diagnosticPath(elementCount: Int = 2, x: Double = 0) -> PathPrimitive {
        let elements = (0..<elementCount).map { index -> SwiftWindowsCore.PathElement in
            let point = Point(x: x + Double(index % 2), y: 1 + Double(index % 2))
            return index == 0 ? .moveTo(point) : .lineTo(point)
        }
        return PathPrimitive(
            elements: elements, bounds: Rect(x: x, y: 0, width: 2, height: 3),
            strokeColor: .white, lineWidth: 1)
    }

    private func storedPathScene(_ paths: [PathPrimitive]) -> GPUIScene {
        var scene = GPUIScene()
        // The existing hand-built initializer preserves exact counts and malformed stored values.
        scene.installHandBuiltLayers([
            GPUILayer(
                paths: paths,
                paintOperations: [GPUIPaintOperation(kind: .path, startIndex: 0, count: paths.count)])
        ])
        scene.finish()
        return scene
    }

    func testPathInventoryAccepts256PathsAndRejectsOverflowBeforeCopying() async throws {
        let limit = RetainedSceneGeometryLimits.maxPaths
        for count in [limit - 1, limit, limit + 1] {
            let scene = storedPathScene(Array(repeating: diagnosticPath(), count: count))
            let inventory = SnapshotSceneGeometryDiagnostics.pathInventory(scene: scene)
            let paths = try XCTUnwrap(inventory.object["paths"] as? [[String: Any]])
            XCTAssertEqual(inventory.object["storedPathCount"] as? Int, count)
            if count <= limit {
                XCTAssertEqual(inventory.object["status"] as? String, "captured")
                XCTAssertTrue(inventory.issues.isEmpty)
                XCTAssertEqual(inventory.object["walkComplete"] as? Bool, true)
                XCTAssertEqual(inventory.object["presentedPathCount"] as? Int, count)
                XCTAssertEqual(inventory.object["copiedPathCount"] as? Int, count)
                XCTAssertEqual(paths.count, count)
            } else {
                XCTAssertEqual(inventory.object["status"] as? String, "unavailable")
                XCTAssertEqual(inventory.issues, ["path-count-limit"])
                XCTAssertEqual(inventory.object["walkComplete"] as? Bool, false)
                XCTAssertTrue(inventory.object["presentedPathCount"] is NSNull)
                XCTAssertEqual(inventory.object["copiedPathCount"] as? Int, 0)
                XCTAssertEqual(inventory.object["copiedElementCount"] as? Int, 0)
                XCTAssertTrue(paths.isEmpty)
            }
        }
    }

    func testPathElementBudgetIsSharedAcrossPresentedPaths() async throws {
        let limit = RetainedSceneGeometryLimits.maxPathElements
        let half = limit / 2
        for total in [limit - 1, limit, limit + 1] {
            let scene = storedPathScene([
                diagnosticPath(elementCount: half), diagnosticPath(elementCount: total - half),
            ])
            let inventory = SnapshotSceneGeometryDiagnostics.pathInventory(scene: scene)
            XCTAssertEqual(inventory.object["storedPathCount"] as? Int, 2)
            if total <= limit {
                XCTAssertEqual(inventory.object["status"] as? String, "captured")
                XCTAssertTrue(inventory.issues.isEmpty)
                XCTAssertEqual(inventory.object["copiedElementCount"] as? Int, total)
                XCTAssertEqual(inventory.object["presentedPathCount"] as? Int, 2)
            } else {
                XCTAssertEqual(inventory.object["status"] as? String, "unavailable")
                XCTAssertEqual(inventory.issues, ["path-element-limit"])
                XCTAssertEqual(inventory.object["copiedElementCount"] as? Int, half)
                XCTAssertEqual(inventory.object["copiedPathCount"] as? Int, 1)
                XCTAssertEqual(inventory.object["walkComplete"] as? Bool, false)
                XCTAssertTrue(inventory.object["presentedPathCount"] is NSNull)
            }
        }
        let oversized = SnapshotSceneGeometryDiagnostics.pathInventory(
            scene: storedPathScene([diagnosticPath(elementCount: limit + 1)]))
        XCTAssertEqual(oversized.issues, ["path-element-limit"])
        XCTAssertEqual(oversized.object["copiedElementCount"] as? Int, 0)
        XCTAssertEqual(oversized.object["copiedPathCount"] as? Int, 0)
    }

    func testEncodedSidecarAcceptsExactByteLimitAndRejectsOneExtraByte() async throws {
        let limit = RetainedSceneGeometryLimits.maxSidecarBytes
        let overhead = try SnapshotSceneGeometryDiagnostics.encodeSidecar(["payload": ""]).count
        for byteCount in [limit - 1, limit] {
            let data = try SnapshotSceneGeometryDiagnostics.encodeSidecar([
                "payload": String(repeating: "a", count: byteCount - overhead)
            ])
            XCTAssertEqual(data.count, byteCount)
        }
        do {
            _ = try SnapshotSceneGeometryDiagnostics.encodeSidecar([
                "payload": String(repeating: "a", count: limit + 1 - overhead)
            ])
            XCTFail("A sidecar one byte over the fixed limit must be rejected.")
        } catch SnapshotSceneGeometryDiagnostics.EncodingError.sidecarTooLarge {
            // The byte limit has its own error, distinct from invalid JSON input.
        } catch {
            XCTFail("Unexpected sidecar error: \(error)")
        }
    }

    func testPathReferencesStaySceneLocalWhenCoordinatesChange() async throws {
        var records: [[String: Any]] = []
        for x in [1.0, 13.0] {
            let inventory = SnapshotSceneGeometryDiagnostics.pathInventory(
                scene: storedPathScene([diagnosticPath(x: x)]))
            XCTAssertTrue(inventory.issues.isEmpty)
            XCTAssertEqual(inventory.object["scope"] as? String, "top-level-presented-path-primitives")
            XCTAssertEqual(
                inventory.object["referenceScope"] as? String, "scene-local-only-not-cross-variant-identity")
            XCTAssertEqual(inventory.object["canvasOwnership"] as? String, "unobserved")
            XCTAssertEqual(inventory.object["coordinateSpace"] as? String, "captured-scene")
            let paths = try XCTUnwrap(inventory.object["paths"] as? [[String: Any]])
            XCTAssertEqual(paths.count, 1)
            let path = try XCTUnwrap(paths.first)
            XCTAssertEqual(path["layerIndex"] as? Int, 0)
            XCTAssertEqual(path["primitiveIndex"] as? Int, 0)
            XCTAssertEqual(path["presentationOrdinal"] as? Int, 0)
            XCTAssertEqual(path["bounds"] as? [Double], [x, 0, 2, 3])
            let elements = try XCTUnwrap(path["elements"] as? [[String: Any]])
            XCTAssertEqual(elements.first?["point"] as? [Double], [x, 1])
            records.append(path)
        }
        XCTAssertNotEqual(records[0]["bounds"] as? [Double], records[1]["bounds"] as? [Double])
    }

    func testNonfiniteStoredPathDataCannotBeReportedAsComplete() async throws {
        var path = diagnosticPath()
        path.elements[0] = .moveTo(Point(x: .nan, y: 1))
        // addPath sanitizes input; this existing fixture API deliberately bypasses that step.
        let scene = storedPathScene([path])
        guard case .moveTo(let firstPoint) = scene.layers[0].paths[0].elements[0] else {
            return XCTFail("The malformed fixture must reach the inventory unchanged.")
        }
        XCTAssertTrue(firstPoint.x.isNaN)
        let inventory = SnapshotSceneGeometryDiagnostics.pathInventory(scene: scene)
        XCTAssertEqual(inventory.object["status"] as? String, "unavailable")
        XCTAssertEqual(inventory.issues, ["nonfinite-path-data"])
        XCTAssertEqual(inventory.object["storedPathCount"] as? Int, 1)
        XCTAssertEqual(inventory.object["copiedPathCount"] as? Int, 0)
        XCTAssertEqual(inventory.object["walkComplete"] as? Bool, false)
        XCTAssertTrue(inventory.object["presentedPathCount"] is NSNull)
    }

    func testUnexpectedPathGradientsKeepCoordinateCoverageUnavailable() async throws {
        let gradient = SwiftWindowsGraphics.LinearGradient(
            startColor: .white, endColor: .black, axis: .horizontal)
        for usesFill in [true, false] {
            var path = diagnosticPath()
            if usesFill {
                path.fillGradient = gradient
            } else {
                path.strokeGradient = gradient
            }
            let inventory = SnapshotSceneGeometryDiagnostics.pathInventory(scene: storedPathScene([path]))
            XCTAssertEqual(inventory.object["status"] as? String, "unavailable")
            XCTAssertEqual(inventory.issues, ["gradient-coordinate-space-unavailable"])
            XCTAssertEqual(inventory.object["copiedPathCount"] as? Int, 1)
            let paths = try XCTUnwrap(inventory.object["paths"] as? [[String: Any]])
            let record = try XCTUnwrap(paths.first)
            let marker = try XCTUnwrap(record[usesFill ? "fillGradient" : "strokeGradient"] as? [String: Any])
            XCTAssertEqual(marker["status"] as? String, "unavailable")
            XCTAssertEqual(marker["reason"] as? String, "gradient-coordinate-space-not-exported")
        }
    }

    func testChildRenderPassCannotBorrowTopLevelPathCoverage() async throws {
        let child = storedPathScene([diagnosticPath(x: 13)])
        var outer = storedPathScene([diagnosticPath(x: 1)])
        let passID = outer.registerImageRenderPass(child, size: IntSize(width: 16, height: 16))
        outer.addImage(ImagePrimitive(screenX: 0, screenY: 0, screenW: 16, screenH: 16, textureID: passID))
        outer.finish()
        let inventory = SnapshotSceneGeometryDiagnostics.pathInventory(scene: outer)
        XCTAssertEqual(inventory.object["status"] as? String, "unavailable")
        XCTAssertEqual(inventory.issues, ["child-render-pass-path-coverage-unavailable"])
        XCTAssertEqual(inventory.object["childRenderPassCount"] as? Int, 1)
        XCTAssertEqual(inventory.object["storedPathCount"] as? Int, 1)
        XCTAssertEqual(inventory.object["copiedPathCount"] as? Int, 1)
        let paths = try XCTUnwrap(inventory.object["paths"] as? [[String: Any]])
        XCTAssertEqual(paths.count, 1)
        XCTAssertEqual(paths.first?["bounds"] as? [Double], [1, 0, 2, 3])
    }
}
