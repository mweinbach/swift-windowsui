import Foundation
import SwiftWindowsCore
import SwiftWindowsGraphics
import XCTest

@testable import SwiftWindowsUI
@testable import WinSwiftUI

@MainActor
final class BitmapFontAttributionViewTests: XCTestCase {
    override func tearDown() async throws {
        await MainActor.run {
            NativeTextRenderer.resetTestingOverrides()
            NativeFontAvailability.resetTestingOverrides()
            NativeFontAvailability.resetProbeCacheForTesting()
            TextRasterCache.restoreSharedForTesting()
            SystemUIFontFace.resetAvailabilityCacheForTesting()
        }
    }

    private func installSyntheticFonts(rasterized: @escaping () -> Void = {}) {
        SystemUIFontFace.availabilityOverrideForTesting = false
        NativeFontAvailability.testingOverrides.hasGlyph = { _, _ in true }
        NativeTextRenderer.testingOverrides.measure = { _, _, _, _ in Size(width: 24, height: 14) }
        NativeTextRenderer.testingOverrides.layout = { _, _, _, _ in nil }
        NativeTextRenderer.testingOverrides.appendCommands = { _, _, _, _, _, _ in false }
        NativeTextRenderer.testingOverrides.rasterize = { _, _, _ in
            rasterized()
            return BitmapSurface(
                width: 2, height: 2, bytesPerRow: 8,
                pixels: Data([255, 255, 255, 255, 0, 0, 0, 0, 0, 0, 0, 0, 255, 255, 255, 255]),
                format: .bgra8Premultiplied
            )
        }
        TextRasterCache.installForTesting(TextRasterCache(maxEntryCount: 32, maxMemoryBytes: 4096))
    }

    private func context(_ session: NativeBitmapFontAttributionSession?) -> ViewBuildContext {
        var values = EnvironmentValues()
        values.bitmapFontAttribution = session
        let capturedValues = values
        return ViewBuildContext(
            canvasSizeProvider: { Size(width: 320, height: 240) },
            invalidateHandler: {},
            environmentValuesProvider: { capturedValues }
        )
    }

    func testOnlyTwoPublicFixtureIdentifiersAreAuthorized() async {
        XCTAssertEqual(NativeBitmapFontFixture(rawValue: "symbol-palette"), .symbolPalette)
        XCTAssertEqual(NativeBitmapFontFixture(rawValue: "stepper"), .stepper)
        XCTAssertNil(NativeBitmapFontFixture(rawValue: "secure-field"))
        XCTAssertNil(NativeBitmapFontFixture(rawValue: "typography-scale"))
        XCTAssertNil(NativeBitmapFontFixture(rawValue: "tab-view"))
    }

    func testInheritedEnvironmentLinkDoesNotRetainOwner() async {
        var owner: NativeBitmapFontAttributionSession? = NativeBitmapFontAttributionSession(fixture: .symbolPalette)
        weak var weakOwner = owner
        let inherited = context(owner).withEnvironmentValue(\.isEnabled, false)
        XCTAssertTrue(inherited.bitmapFontAttribution === owner)
        owner = nil
        XCTAssertNil(weakOwner)
        XCTAssertNil(inherited.bitmapFontAttribution)
        XCTAssertNil(context(nil).bitmapFontAttribution)
    }

    func testImageForwardingSurvivesEnvironmentModifiers() async {
        installSyntheticFonts()
        let session = NativeBitmapFontAttributionSession(fixture: .symbolPalette)
        defer { session.close() }
        let component = Image(systemName: "folder.fill")
            .font(.title2)
            .foregroundColor(.blue)
            .padding(3)
            .environment(\.isEnabled, false)
            .makeComponent(context: context(session))
        _ = component.makeNode(runtime: RetainedViewRuntime())

        let report = session.finish(scene: GPUIScene())
        XCTAssertTrue(report.observations.contains { $0.role == "folder" && $0.outcome == "bitmap-accepted" })
        XCTAssertTrue(report.faces.isEmpty, "A testing override must never impersonate a native face")
    }

    func testStepperForwardsBothButtonContexts() async {
        installSyntheticFonts()
        let session = NativeBitmapFontAttributionSession(fixture: .stepper)
        defer { session.close() }
        let component = Stepper(value: .constant(5), in: 0...10) { Text("Count: 5") }
            .makeComponent(context: context(session))
        _ = component.makeNode(runtime: RetainedViewRuntime())
        let report = session.finish(scene: GPUIScene())
        let accepted = Set(report.observations.filter { $0.outcome == "bitmap-accepted" }.map(\.role))
        XCTAssertEqual(accepted, Set(["increment", "decrement"]))
        XCTAssertEqual(report.coverage.atlasGlyphs, "not-instrumented")
    }

    func testUnrelatedSymbolCannotObtainFixtureObserver() async {
        installSyntheticFonts()
        let session = NativeBitmapFontAttributionSession(fixture: .stepper)
        defer { session.close() }
        _ = Image(systemName: "folder.fill").makeComponent(context: context(session))
            .makeNode(runtime: RetainedViewRuntime())
        XCTAssertTrue(session.finish(scene: GPUIScene()).observations.isEmpty)
    }

    func testSecureFieldAndOrdinaryTextNeverObtainBitmapObserver() async throws {
        installSyntheticFonts()
        let secret = "private-password-78419"
        let session = NativeBitmapFontAttributionSession(fixture: .symbolPalette)
        defer { session.close() }
        let view = VStack {
            SecureField("Password", text: .constant(secret))
            Text(secret)
        }
        _ = view.makeComponent(context: context(session)).makeNode(runtime: RetainedViewRuntime())
        let report = session.finish(scene: GPUIScene())
        XCTAssertTrue(report.observations.isEmpty)
        XCTAssertTrue(report.faces.isEmpty)
        let encoded = String(decoding: try JSONEncoder().encode(report), as: UTF8.self)
        XCTAssertFalse(encoded.contains(secret))
        XCTAssertFalse(encoded.contains("Password"))
        XCTAssertFalse(encoded.contains("glyphIndices"))
        XCTAssertFalse(encoded.contains("textPosition"))
    }

    func testOldCacheHitDoesNotRerasterizeOrInventOwnership() async {
        var calls = 0
        installSyntheticFonts { calls += 1 }
        let first = Controls.icon(.folder)
        let session = NativeBitmapFontAttributionSession(fixture: .symbolPalette)
        defer { session.close() }
        let second = Controls.icon(.folder, bitmapFontAttribution: session)
        XCTAssertEqual(calls, 1)
        XCTAssertEqual(first.bitmapSurface?.contentKey, second.bitmapSurface?.contentKey)
        let report = session.finish(scene: GPUIScene())
        XCTAssertTrue(report.observations.contains { $0.outcome == "bitmap-cache-hit-unobserved" })
        XCTAssertTrue(report.faces.isEmpty)
    }

    func testSameSessionCacheReuseDoesNotRerasterize() async {
        var calls = 0
        installSyntheticFonts { calls += 1 }
        let session = NativeBitmapFontAttributionSession(fixture: .symbolPalette)
        defer { session.close() }
        _ = Controls.icon(.folder, bitmapFontAttribution: session)
        _ = Controls.icon(.folder, bitmapFontAttribution: session)
        XCTAssertEqual(calls, 1)
        let report = session.finish(scene: GPUIScene())
        XCTAssertTrue(
            report.observations.contains {
                $0.outcome == "bitmap-cache-hit-known" && $0.backend == "testing-override" && $0.faceIDs.isEmpty
            })
    }

    func testSnapshotEndsCaptureAndRetainedStepperKeepsOwnerWeak() async {
        installSyntheticFonts()
        var session: NativeBitmapFontAttributionSession? = NativeBitmapFontAttributionSession(fixture: .stepper)
        weak var weakSession = session
        let snapshot = WinSwiftUIRendererSnapshotter.snapshot(
            of: Stepper(value: .constant(5), in: 0...10) { Text("Count: 5") }.frame(width: 150, height: 40),
            size: IntSize(width: 160, height: 50), bitmapFontAttribution: session
        )
        XCTAssertNil(session?.observation(for: .chevronUp), "Snapshot completion must leave capture stopped")
        let report = session?.finish(scene: snapshot.scene)
        XCTAssertTrue(report?.observations.contains { $0.outcome == "scene-referenced" } == true)
        session = nil
        // Stepper actions retain their build context, so keeping this runtime
        // alive exercises the environment provider's weak owner link.
        XCTAssertNil(weakSession, "Retained Stepper contexts must not retain the diagnostic owner")
        XCTAssertFalse(snapshot.scene.imageResources.isEmpty)
    }

    func testDiagnosticsDoNotChangeSyntheticRetainedPixelsOrRasterCount() async {
        var calls = 0
        installSyntheticFonts { calls += 1 }
        let view = HStack {
            Image(systemName: "folder.fill").frame(width: 20, height: 20)
            Image(systemName: "globe").frame(width: 20, height: 20)
        }
        let off = WinSwiftUIRendererSnapshotter.snapshot(of: view, size: IntSize(width: 60, height: 40))
        let offCalls = calls
        TextRasterCache.installForTesting(TextRasterCache(maxEntryCount: 32, maxMemoryBytes: 4096))
        calls = 0
        let session = NativeBitmapFontAttributionSession(fixture: .symbolPalette)
        defer { session.close() }
        let on = WinSwiftUIRendererSnapshotter.snapshot(
            of: view, size: IntSize(width: 60, height: 40), bitmapFontAttribution: session)
        XCTAssertEqual(calls, offCalls)
        XCTAssertGreaterThan(calls, 0)
        let offPixels = GPUIRawSceneRasterizer.rasterize(off.scene, size: off.size).pixels
        let onPixels = GPUIRawSceneRasterizer.rasterize(on.scene, size: on.size).pixels
        XCTAssertEqual(onPixels, offPixels)
        let report = session.finish(scene: on.scene)
        XCTAssertEqual(report.qualification, "unqualified")
        XCTAssertEqual(report.coverage.atlasGlyphs, "not-instrumented")
    }
}
