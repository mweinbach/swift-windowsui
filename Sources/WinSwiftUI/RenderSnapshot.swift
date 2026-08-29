import Foundation
import SwiftWindowsCore
import SwiftWindowsGraphics
import SwiftWindowsUI

@MainActor
public struct WinSwiftUIRenderSnapshot {
    public var runtime: RetainedViewRuntime
    public var frame: RenderFrame
    public var scene: GPUIScene
    public var size: IntSize
    public var displayScale: Double
    package var sceneGeometryDiagnostic: RetainedSceneGeometryDiagnostic? = nil

    public init(
        runtime: RetainedViewRuntime,
        frame: RenderFrame,
        scene: GPUIScene,
        size: IntSize,
        displayScale: Double
    ) {
        self.runtime = runtime
        self.frame = frame
        self.scene = scene
        self.size = size
        self.displayScale = displayScale
    }
}
@MainActor
public enum WinSwiftUIRendererSnapshotter {
    /// - Parameters:
    ///   - colorScheme: the appearance the snapshot window is in. This is
    ///     the *window's* appearance, as `NSWindow.effectiveAppearance` is
    ///     on macOS: it seeds the root environment and picks the backdrop.
    ///     A fixed navy clear colour meant a light-mode render still had a
    ///     dark page behind it.
    ///   - clearColor: overrides the appearance's window background.
    public static func snapshot<V: View>(
        of view: V,
        size: IntSize = IntSize(width: 1280, height: 720),
        displayScale: Double = 1,
        colorScheme: ColorScheme = .dark,
        clearColor: Color? = nil,
        timestamp: Double = 0
    ) -> WinSwiftUIRenderSnapshot {
        snapshot(
            of: view, size: size, displayScale: displayScale, colorScheme: colorScheme,
            clearColor: clearColor, timestamp: timestamp, bitmapFontAttribution: nil
        )
    }

    /// Explicit diagnostic overload. The caller owns/seals the session and
    /// must not treat its bitmap observations as atlas or pixel qualification.
    public static func snapshot<V: View>(
        of view: V,
        size: IntSize = IntSize(width: 1280, height: 720),
        displayScale: Double = 1,
        colorScheme: ColorScheme = .dark,
        clearColor: Color? = nil,
        timestamp: Double = 0,
        bitmapFontAttribution: NativeBitmapFontAttributionSession?
    ) -> WinSwiftUIRenderSnapshot {
        snapshotImpl(
            of: view, size: size, displayScale: displayScale, colorScheme: colorScheme,
            clearColor: clearColor, timestamp: timestamp, bitmapFontAttribution: bitmapFontAttribution,
            geometryDiagnostics: false
        )
    }

    /// Package-only gallery diagnostic. Public/default snapshot behavior stays unchanged.
    package static func snapshot<V: View>(
        of view: V,
        size: IntSize = IntSize(width: 1280, height: 720),
        displayScale: Double = 1,
        colorScheme: ColorScheme = .dark,
        clearColor: Color? = nil,
        timestamp: Double = 0,
        geometryDiagnostics: Bool
    ) -> WinSwiftUIRenderSnapshot {
        snapshotImpl(
            of: view, size: size, displayScale: displayScale, colorScheme: colorScheme,
            clearColor: clearColor, timestamp: timestamp, bitmapFontAttribution: nil,
            geometryDiagnostics: geometryDiagnostics
        )
    }

    private static func snapshotImpl<V: View>(
        of view: V, size: IntSize, displayScale: Double, colorScheme: ColorScheme,
        clearColor: Color?, timestamp: Double, bitmapFontAttribution: NativeBitmapFontAttributionSession?,
        geometryDiagnostics: Bool
    ) -> WinSwiftUIRenderSnapshot {
        let palette = ControlPalette.resolve(colorScheme: colorScheme)
        let resolvedClearColor = clearColor ?? palette.windowBackground
        let runtime = RetainedViewRuntime(
            clearColor: resolvedClearColor, root: ViewNode(), displayScale: displayScale)
        runtime.setRootSize(size)
        // Icons rasterize eagerly at build time; point them at this render's
        // scale (1 for the deterministic screenshot path), then restore.
        let previousIconDisplayScale = NativeTextRenderer.defaultIconDisplayScale
        NativeTextRenderer.defaultIconDisplayScale = displayScale
        defer { NativeTextRenderer.defaultIconDisplayScale = previousIconDisplayScale }

        // The provider can outlive this call through retained components; it
        // captures only a weak link, never the diagnostic owner itself.
        let attributionLink = bitmapFontAttribution.map(BitmapFontAttributionLink.init)
        let context = ViewBuildContext(
            canvasSizeProvider: {
                Size(width: Double(size.width), height: Double(size.height))
            },
            invalidateHandler: {},
            environmentValuesProvider: {
                var values = EnvironmentValues(
                    colorScheme: colorScheme,
                    displayScale: displayScale,
                    pixelLength: displayScale > 0 ? 1 / displayScale : 1
                )
                if let attributionLink {
                    values.bitmapFontAttributionLink = attributionLink
                }
                return values
            }
        )
        let component = view.makeComponent(context: context)
        let host = ComponentHost(runtime: runtime)
        host.setContent(component)

        let geometryRequest = geometryDiagnostics ? runtime.requestSceneGeometryDiagnostic() : nil
        let scene = runtime.renderScene(at: timestamp)
        // This value was copied inside the first paint, before deferred callbacks and the auxiliary frame.
        let sceneGeometryDiagnostic = geometryRequest?.result
        // Icon rasters are made during node construction. Auxiliary frame
        // rendering must not contribute new receipts to the selected scene.
        bitmapFontAttribution?.stopRecording()
        let frame = runtime.renderFrame(at: timestamp)
        var snapshot = WinSwiftUIRenderSnapshot(
            runtime: runtime,
            frame: frame,
            scene: scene,
            size: size,
            displayScale: displayScale
        )
        snapshot.sceneGeometryDiagnostic = sceneGeometryDiagnostic
        return snapshot
    }
}

// These helpers inspect owned scene values only; they never render or measure.
package struct SnapshotSceneGeometryPathInventory {
    package let object: [String: Any]
    package let issues: [String]
}

package enum SnapshotSceneGeometryDiagnostics {
    package enum EncodingError: Error {
        case sidecarTooLarge
    }

    private enum ValueError: Error {
        case nonfinite
    }

    package static func encodeSidecar(_ object: [String: Any]) throws -> Data {
        let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        guard data.count <= RetainedSceneGeometryLimits.maxSidecarBytes else {
            throw EncodingError.sidecarTooLarge
        }
        return data
    }

    package static func pathInventory(scene: GPUIScene) -> SnapshotSceneGeometryPathInventory {
        let storedCount = scene.layers.reduce(0) { $0 + $1.paths.count }
        var records: [[String: Any]] = []
        var issues: [String] = []
        var copiedElements = 0
        var presentationOrdinal = 0
        var references = Set<String>()
        var walkComplete = true

        if storedCount > RetainedSceneGeometryLimits.maxPaths {
            issues.append("path-count-limit")
            walkComplete = false
        } else {
            presentation: for run in scene.presentationOrder() {
                guard run.kind == .path else {
                    presentationOrdinal += run.range.count
                    continue
                }
                for index in run.range {
                    guard records.count < RetainedSceneGeometryLimits.maxPaths else {
                        issues.append("path-count-limit")
                        walkComplete = false
                        break presentation
                    }
                    guard
                        case .path(let path)? = scene.primitive(
                            kind: .path, inLayer: run.layerIndex, at: index)
                    else {
                        issues.append("path-reference-unavailable")
                        walkComplete = false
                        break presentation
                    }
                    guard path.elements.count <= RetainedSceneGeometryLimits.maxPathElements - copiedElements else {
                        issues.append("path-element-limit")
                        walkComplete = false
                        break presentation
                    }
                    let reference = "\(run.layerIndex):\(index)"
                    if !references.insert(reference).inserted {
                        issues.append("duplicate-path-reference")
                    }
                    if path.fillGradient != nil || path.strokeGradient != nil,
                        !issues.contains("gradient-coordinate-space-unavailable")
                    {
                        // Gradient endpoints are internal to Graphics. These
                        // two fixtures author solid paths; unexpected gradients
                        // stay incomplete instead of inventing their placement.
                        issues.append("gradient-coordinate-space-unavailable")
                    }
                    do {
                        var record = try pathObject(path)
                        record["layerIndex"] = run.layerIndex
                        record["primitiveIndex"] = index
                        record["presentationOrdinal"] = presentationOrdinal
                        records.append(record)
                        copiedElements += path.elements.count
                        presentationOrdinal += 1
                    } catch {
                        issues.append("nonfinite-path-data")
                        walkComplete = false
                        break presentation
                    }
                }
            }
        }
        if walkComplete, references.count != storedCount {
            issues.append("stored-paths-not-fully-presented")
        }
        if !scene.imageRenderPasses.isEmpty {
            issues.append("child-render-pass-path-coverage-unavailable")
        }

        let presentedCount: Any
        if walkComplete {
            presentedCount = records.count
        } else {
            presentedCount = NSNull()
        }
        return SnapshotSceneGeometryPathInventory(
            object: [
                "status": issues.isEmpty ? "captured" : "unavailable",
                "issues": issues,
                "scope": "top-level-presented-path-primitives",
                "referenceScope": "scene-local-only-not-cross-variant-identity",
                "canvasOwnership": "unobserved",
                "coordinateSpace": "captured-scene",
                "pointEncoding": "[x,y]",
                "rectangleEncoding": "[x,y,width,height]",
                "angleUnits": "radians",
                "walkComplete": walkComplete,
                "storedPathCount": storedCount,
                "presentedPathCount": presentedCount,
                "copiedPathCount": records.count,
                "copiedElementCount": copiedElements,
                "sceneLayerCount": scene.layers.count,
                "scenePrimitiveCount": scene.primitiveCount,
                "childRenderPassCount": scene.imageRenderPasses.count,
                "pathsRasterizedOnCPU": scene.paintMetrics.pathsRasterizedOnCPU,
                "pathsPromotedToGPU": scene.paintMetrics.pathsPromotedToGPU,
                "paths": records,
            ],
            issues: issues
        )
    }

    private static func pathObject(_ path: PathPrimitive) throws -> [String: Any] {
        let cap: String
        switch path.lineCap {
        case .butt: cap = "butt"
        case .round: cap = "round"
        case .square: cap = "square"
        }
        let join: String
        switch path.lineJoin {
        case .miter: join = "miter"
        case .round: join = "round"
        case .bevel: join = "bevel"
        }
        let clip: Any
        if let bounds = path.clipBounds {
            clip = try rectangle(bounds)
        } else {
            clip = NSNull()
        }
        return [
            "kind": "path",
            "elements": try path.elements.map { try elementObject($0) },
            "bounds": try rectangle(path.bounds),
            "fillColor": try color(path.fillColor),
            "fillGradient": gradientMarker(path.fillGradient != nil),
            "fillRule": path.fillRule == .evenOdd ? "evenOdd" : "nonZero",
            "strokeColor": try color(path.strokeColor),
            "strokeGradient": gradientMarker(path.strokeGradient != nil),
            "lineWidth": try finite(path.lineWidth),
            "lineCap": cap,
            "lineJoin": join,
            "miterLimit": try finite(path.miterLimit),
            "clipBounds": clip,
            "clipCornerRadius": try finite(path.clipCornerRadius),
        ]
    }

    private static func elementObject(_ element: SwiftWindowsCore.PathElement) throws -> [String: Any] {
        switch element {
        case .moveTo(let value):
            return ["kind": "moveTo", "point": try point(value)]
        case .lineTo(let value):
            return ["kind": "lineTo", "point": try point(value)]
        case .quadraticCurveTo(let control, let end):
            return ["kind": "quadraticCurveTo", "control": try point(control), "end": try point(end)]
        case .cubicCurveTo(let control1, let control2, let end):
            return [
                "kind": "cubicCurveTo", "control1": try point(control1),
                "control2": try point(control2), "end": try point(end),
            ]
        case .arc(let center, let radius, let startAngle, let endAngle, let clockwise):
            return [
                "kind": "arc", "center": try point(center), "radius": try finite(radius),
                "startAngle": try finite(startAngle), "endAngle": try finite(endAngle), "clockwise": clockwise,
            ]
        case .close:
            return ["kind": "close"]
        }
    }

    private static func gradientMarker(_ present: Bool) -> Any {
        if present {
            return ["status": "unavailable", "reason": "gradient-coordinate-space-not-exported"]
        }
        return NSNull()
    }

    private static func point(_ value: SwiftWindowsCore.Point) throws -> [Double] {
        [try finite(value.x), try finite(value.y)]
    }

    private static func rectangle(_ value: SwiftWindowsCore.Rect) throws -> [Double] {
        [
            try finite(value.origin.x), try finite(value.origin.y),
            try finite(value.size.width), try finite(value.size.height),
        ]
    }

    private static func color(_ value: SwiftWindowsCore.Color) throws -> [Double] {
        [
            try finite(Double(value.red)), try finite(Double(value.green)),
            try finite(Double(value.blue)), try finite(Double(value.alpha)),
        ]
    }

    private static func finite(_ value: Double) throws -> Double {
        guard value.isFinite else { throw ValueError.nonfinite }
        return value
    }
}
