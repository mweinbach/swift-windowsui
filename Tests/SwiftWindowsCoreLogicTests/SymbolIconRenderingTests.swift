import SwiftWindowsCore
import SwiftWindowsGraphics
import SwiftWindowsLayout
import XCTest

@testable import SwiftWindowsUI
@testable import WinSwiftUI

/// Symbol icon rendering: icons must paint through the native font
/// rasterization path (or the drawn vector fallback) and never through the
/// pixel-font fallback, which can only show a crude 5x7 pattern or '?'.
final class SymbolIconRenderingTests: XCTestCase {
    override func tearDown() async throws {
        await MainActor.run {
            NativeFontAvailability.resetTestingOverrides()
        }
        try await super.tearDown()
    }

    // MARK: - Native bitmap path

    func testCoreIconsRasterizeNativeBitmaps() async throws {
        try await MainActor.run {
            // Codepoints verified present in both Segoe Fluent Icons and
            // Segoe MDL2 Assets on this machine. (.sparkle, U+EAAC, is not in
            // either icon font and intentionally renders via the drawn
            // vector path — see testEverySymbolHasExactlyOnePaintPath.)
            let coreSymbols: [SymbolIcon] = [
                .search, .checkmark, .settings, .chevronDown, .chevronUp,
                .chevronLeft, .chevronRight, .plus, .minus, .xmark,
            ]
            for symbol in coreSymbols {
                let tint = Color(red: 0.9, green: 0.4, blue: 0.2, alpha: 1)
                let node = Controls.icon(
                    symbol, preferredSize: Size(width: 24, height: 24), color: tint, scale: 1.9)

                let bitmap = try XCTUnwrap(
                    node.bitmapSurface, "\(symbol) must rasterize through the native font path")
                XCTAssertNil(node.canvasDraw, "\(symbol) must not take the vector fallback")
                XCTAssertGreaterThan(bitmap.width, 0)
                XCTAssertGreaterThan(bitmap.height, 0)
                XCTAssertTrue(
                    bitmap.pixels.contains { $0 != 0 },
                    "\(symbol) bitmap must contain visible pixels")

                // The glyph text is preserved as metadata for measurement,
                // accessibility folding, and existing callers.
                XCTAssertEqual(node.text, symbol.rawValue)
                XCTAssertEqual(node.textStyle.fontFamily, "Segoe Fluent Icons")
                XCTAssertEqual(node.textStyle.color, tint)
                XCTAssertEqual(node.textStyle.scale, 1.9)
                XCTAssertEqual(node.preferredSize, Size(width: 24, height: 24))
                XCTAssertTrue(node.isAccessibilityHidden)
            }
        }
    }

    func testIconDefaultsToFontSquareWhenPreferredSizeMissing() async {
        await MainActor.run {
            let node = Controls.icon(.search, scale: 1.9)
            // scale 1.9 -> nativeFontPixelSize = 1.9 * 6 + 8 = 19.4
            XCTAssertEqual(node.preferredSize?.width ?? 0, 19.4, accuracy: 0.001)
            XCTAssertEqual(node.preferredSize?.height ?? 0, 19.4, accuracy: 0.001)
        }
    }

    func testIconScenePaintEmitsImageAndNoPixelGlyphs() async throws {
        try await MainActor.run {
            let root = Controls.panel(
                frame: Rect(x: 0, y: 0, width: 40, height: 40),
                children: [
                    Controls.icon(.search, frame: Rect(x: 8, y: 8, width: 24, height: 24))
                ]
            )

            let scene = ScenePainter.paint(
                root: root, clearColor: .black, surfaceSize: Size(width: 40, height: 40))

            let images = scene.layers.flatMap(\.images)
            let pixelGlyphs = scene.layers.flatMap(\.pixelGlyphs)
            XCTAssertEqual(images.count, 1, "icon must paint as a rasterized image primitive")
            XCTAssertTrue(pixelGlyphs.isEmpty, "icon glyph must never reach the pixel-font fallback")
        }
    }

    /// The icon bitmap is sized from the glyph's own measurement, so it
    /// must preserve that glyph rather than substituting a text ellipsis.
    /// Fractional DPI makes a measurement/raster rounding disagreement
    /// visible at the native size used by a 12-point SwiftUI symbol.
    func testFractionalScaleIconsPreserveTheirNativeGlyphRaster() async throws {
        try await MainActor.run {
            for symbol: SymbolIcon in [.layout, .search, .settings, .split] {
                for displayScale in [1.0, 1.25, 1.5, 1.75, 2.0] {
                    let node = Controls.icon(
                        symbol, preferredSize: Size(width: 14.4, height: 14.4),
                        scale: 1.2, displayScale: displayScale)
                    let actual = try XCTUnwrap(node.bitmapSurface)
                    var rasterStyle = node.textStyle
                    rasterStyle.insets = .zero
                    rasterStyle.fontFamily = try XCTUnwrap(
                        NativeFontAvailability.resolvedFontFamily(
                            for: symbol.character, preferred: SymbolIcon.fontFamilyFallbacks))
                    let measured = try XCTUnwrap(
                        NativeTextRenderer.measure(symbol.rawValue, style: rasterStyle, scaleFactor: displayScale))
                    let roundTrip = NativeTextRenderer.layout(
                        symbol.rawValue, style: rasterStyle, scaleFactor: displayScale, maxWidth: measured.width)

                    rasterStyle.lineBreakMode = .clip
                    let untrimmed = try XCTUnwrap(
                        NativeTextRenderer.rasterize(symbol.rawValue, style: rasterStyle, scaleFactor: displayScale))
                    XCTAssertEqual(actual.width, untrimmed.width)
                    XCTAssertEqual(actual.height, untrimmed.height)
                    XCTAssertTrue(
                        actual.pixels == untrimmed.pixels,
                        "\(symbol) at \(displayScale)x changed its glyph while rasterizing its measured size "
                            + "\(measured); constrained lines: \(roundTrip?.lines.map(\.text) ?? [])")
                }
            }
        }
    }

    // MARK: - Font fallback chain

    func testFontAvailabilityProbeUsesInstalledFallbackOrVectorRendering() async throws {
        try await MainActor.run {
            NativeFontAvailability.resetTestingOverrides()
            NativeFontAvailability.resetProbeCacheForTesting()
            defer {
                NativeFontAvailability.resetTestingOverrides()
                NativeFontAvailability.resetProbeCacheForTesting()
            }

            // Server 2022 can provide MDL2 Assets without Fluent Icons. Probe
            // this host rather than requiring the developer's installed fonts.
            let symbol: SymbolIcon = .search
            let families = SymbolIcon.fontFamilyFallbacks
            let installedFamilies = families.filter {
                NativeFontAvailability.hasGlyph(symbol.character, fontFamily: $0)
            }
            let selectedFamily = NativeFontAvailability.resolvedFontFamily(
                for: symbol.character, preferred: families)
            XCTAssertEqual(selectedFamily, installedFamilies.first)
            XCTAssertFalse(
                NativeFontAvailability.hasGlyph(symbol.character, fontFamily: "Definitely Not A Font XYZ"))

            let node = Controls.icon(
                symbol, frame: Rect(x: 8, y: 8, width: 24, height: 24),
                preferredSize: Size(width: 24, height: 24), displayScale: 1)
            if let selectedFamily {
                let bitmap = try XCTUnwrap(node.bitmapSurface, "The selected installed font must render the icon")
                XCTAssertNil(node.canvasDraw)
                XCTAssertTrue(bitmap.pixels.contains { $0 != 0 })

                var rasterStyle = node.textStyle
                rasterStyle.fontFamily = selectedFamily
                rasterStyle.insets = .zero
                rasterStyle.lineBreakMode = .clip
                let expected = try XCTUnwrap(
                    NativeTextRenderer.rasterize(symbol.rawValue, style: rasterStyle, scaleFactor: 1))
                XCTAssertEqual(bitmap.width, expected.width)
                XCTAssertEqual(bitmap.height, expected.height)
                XCTAssertTrue(bitmap.pixels == expected.pixels, "The icon must use the selected fallback font")
            } else {
                XCTAssertNil(node.bitmapSurface)
                XCTAssertNotNil(node.canvasDraw, "No installed icon glyph must select the drawn vector fallback")
            }

            let root = Controls.panel(frame: Rect(x: 0, y: 0, width: 40, height: 40), children: [node])
            let scene = ScenePainter.paint(
                root: root, clearColor: .black, surfaceSize: Size(width: 40, height: 40))
            XCTAssertTrue(scene.layers.flatMap(\.pixelGlyphs).isEmpty)
            if selectedFamily != nil {
                XCTAssertEqual(scene.layers.flatMap(\.images).count, 1)
            } else {
                XCTAssertFalse(scene.layers.flatMap(\.paths).isEmpty && scene.layers.flatMap(\.quads).isEmpty)
            }
        }
    }

    func testFontFallbackChainPreservesPreferenceOrder() async {
        await MainActor.run {
            defer { NativeFontAvailability.resetTestingOverrides() }
            let fluent = "Segoe Fluent Icons"
            let mdl2 = "Segoe MDL2 Assets"
            let missing = "Definitely Not A Font XYZ"
            let scenarios: [(available: [String], preferred: [String], expected: String?)] = [
                ([fluent, mdl2], [fluent, mdl2], fluent),
                ([fluent, mdl2], [mdl2, fluent], mdl2),
                ([mdl2], [fluent, mdl2], mdl2),
                ([fluent], [mdl2, fluent], fluent),
                ([mdl2], [missing, mdl2], mdl2),
                ([], [fluent, mdl2], nil),
                ([fluent, mdl2], [missing, "Another Missing Font"], nil),
                ([fluent, mdl2], [], nil),
            ]
            for scenario in scenarios {
                NativeFontAvailability.testingOverrides.hasGlyph = { character, family in
                    character == "\u{E721}" && scenario.available.contains(family)
                }
                XCTAssertEqual(
                    NativeFontAvailability.resolvedFontFamily(for: "\u{E721}", preferred: scenario.preferred),
                    scenario.expected,
                    "Available families: \(scenario.available); requested order: \(scenario.preferred)")
            }

            // Installed-family availability does not imply glyph coverage.
            XCTAssertNil(
                NativeFontAvailability.resolvedFontFamily(
                    for: "\u{E000}", preferred: [fluent, mdl2]))
        }
    }

    // MARK: - Vector fallback

    func testVectorFallbackWhenNoIconFontIsAvailable() async throws {
        try await MainActor.run {
            NativeFontAvailability.testingOverrides.hasGlyph = { _, _ in false }
            defer { NativeFontAvailability.resetTestingOverrides() }

            let tint = Color(red: 1, green: 1, blue: 1, alpha: 1)
            let node = Controls.icon(
                .checkmark, frame: Rect(x: 8, y: 8, width: 24, height: 24), color: tint)

            XCTAssertNil(node.bitmapSurface, "no font -> no rasterized bitmap")
            XCTAssertNotNil(node.canvasDraw, "no font -> drawn vector fallback")

            let root = Controls.panel(frame: Rect(x: 0, y: 0, width: 40, height: 40), children: [node])
            let scene = ScenePainter.paint(
                root: root, clearColor: .black, surfaceSize: Size(width: 40, height: 40))

            let paths = scene.layers.flatMap(\.paths)
            let quads = scene.layers.flatMap(\.quads)
            let pixelGlyphs = scene.layers.flatMap(\.pixelGlyphs)
            XCTAssertFalse(
                paths.isEmpty && quads.isEmpty,
                "vector fallback must emit path or tessellated quad primitives")
            XCTAssertTrue(pixelGlyphs.isEmpty, "vector fallback must not paint '?' pixel glyphs")
        }
    }

    func testEverySymbolHasExactlyOnePaintPath() async {
        await MainActor.run {
            for symbol in SymbolIcon.allCases {
                let node = Controls.icon(symbol, preferredSize: Size(width: 24, height: 24))
                XCTAssertTrue(
                    (node.bitmapSurface != nil) != (node.canvasDraw != nil),
                    "\(symbol) must paint through exactly one of bitmap/vector")
            }
        }
    }

    func testVectorRendererCoversEverySymbol() async throws {
        try await MainActor.run {
            let tint = Color(red: 1, green: 1, blue: 1, alpha: 1)
            for symbol in SymbolIcon.allCases {
                var context = CanvasGraphicsContext()
                SymbolIconVectorRenderer.draw(
                    symbol, in: Size(width: 24, height: 24), color: tint, into: &context)
                XCTAssertFalse(
                    context.operations.isEmpty,
                    "\(symbol) must have a drawn vector representation")
            }
        }
    }

    // MARK: - Symbol name resolution

    func testSymbolNameResolutionCoversToolkitAndDemoUsage() async {
        await MainActor.run {
            // Every systemName referenced from Sources/ (WinSwiftUI internals)
            // and the shared demo must resolve to a real icon.
            let expected: [String: SymbolIcon] = [
                "magnifyingglass": .search,
                "rectangle.3.group": .layout,
                "keyboard": .keyboard,
                "sparkles": .sparkle,
                "switch.2": .settings,
                "gear": .settings,
                "gearshape": .settings,
                "slider.horizontal.3": .settings,
                "doc.text": .document,
                "info.circle": .info,
                "waveform.path.ecg": .activity,
                "chart.bar": .activity,
                "bolt.fill": .lightning,
                "textformat": .document,
                "rectangle.split.3x1": .split,
                "square.and.arrow.up": .arrowUp,
                "square.and.arrow.down": .arrowDown,
                "doc.on.clipboard": .document,
                "doc.on.doc": .document,
                "trash": .trash,
                "play.circle": .play,
                "play.rectangle": .play,
                "camera": .camera,
                "globe": .globe,
                "map": .mapPin,
                // Most common SF Symbols used by apps.
                "person": .person,
                "person.fill": .person,
                "house": .house,
                "star": .star,
                "star.fill": .starFill,
                "heart": .heart,
                "heart.fill": .heartFill,
                "bell": .bell,
                "pencil": .pencil,
                "play": .play,
                "pause": .pause,
                "xmark": .xmark,
                "plus": .plus,
                "minus": .minus,
                "arrow.left": .arrowLeft,
                "arrow.right": .arrowRight,
                "arrow.up": .arrowUp,
                "arrow.down": .arrowDown,
                "chevron.left": .chevronLeft,
                "chevron.right": .chevronRight,
                "chevron.up": .chevronUp,
                "chevron.down": .chevronDown,
                "ellipsis": .ellipsis,
                "checkmark": .checkmark,
                "folder": .folder,
            ]
            for (name, icon) in expected {
                XCTAssertEqual(resolvedSymbolIcon(for: name), icon, "systemName '\(name)'")
            }
        }
    }

    func testSymbolNameResolutionDeliberateDefaults() async {
        await MainActor.run {
            // Names with no reasonable Segoe equivalent stay on the sparkle
            // catch-all by design (they must never crash or show '?').
            let deliberateDefaults = [
                "scissors", "bag", "cart", "tag", "eye", "cube",
                "lightbulb", "livephoto", "visionpro", "photo",
            ]
            for name in deliberateDefaults {
                XCTAssertEqual(resolvedSymbolIcon(for: name), .sparkle, "systemName '\(name)'")
            }
        }
    }

    func testSymbolFillVariantResolvesFilledGlyphs() async {
        await MainActor.run {
            XCTAssertEqual(resolvedSymbolIcon(for: "star", variants: .fill), .starFill)
            XCTAssertEqual(resolvedSymbolIcon(for: "heart", variants: .fill), .heartFill)
            XCTAssertEqual(resolvedSymbolIcon(for: "star.fill"), .starFill)
        }
    }
}
