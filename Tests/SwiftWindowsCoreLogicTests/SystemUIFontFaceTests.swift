import Foundation
import SwiftWindowsCore
import SwiftWindowsGraphics
import XCTest

@testable import SwiftWindowsUI
@testable import WinSwiftUI

/// The UI face this stack sets text in, and the optical size it picks per run.
///
/// Windows 11 ships Segoe UI Variable in three optical cuts and uses them for
/// all system UI; Windows 10 has only classic Segoe UI. These tests pin the
/// selection rule, the all-or-nothing fallback, and — the part that cannot be
/// asserted from a table — that DirectWrite really does resolve the families
/// this stack asks for, including their weights. See `docs/Typography.md`.
@MainActor
final class SystemUIFontFaceTests: XCTestCase {

    override func tearDown() async throws {
        await MainActor.run { SystemUIFontFace.resetAvailabilityCacheForTesting() }
    }

    private func style(family: String, size: Double, weight: TextWeight = .regular, italic: Bool = false)
        -> PixelTextStyle
    {
        var style = PixelTextStyle(
            color: .white,
            scale: 2,
            alignment: .leading,
            verticalAlignment: .top,
            letterSpacing: 1,
            lineSpacing: 0,
            insets: .zero,
            fontFamily: family,
            nativeFontSize: size,
            weight: weight,
            lineBreakMode: .truncateTail,
            maximumNumberOfLines: 1
        )
        style.isItalic = italic
        return style
    }

    /// Total ink of a rasterized run — the only cross-face observable that
    /// does not depend on knowing a face's outlines.
    private func inkMass(_ text: String, _ style: PixelTextStyle, scaleFactor: Double = 4) -> Int? {
        guard let bitmap = DirectWriteTextRenderer.rasterize(text, style: style, scaleFactor: scaleFactor) else {
            return nil
        }
        let width = Int(bitmap.width)
        let height = Int(bitmap.height)
        let stride = Int(bitmap.bytesPerRow)
        let bytes = [UInt8](bitmap.pixels)
        var total = 0
        for y in 0..<height {
            for x in 0..<width {
                let offset = y * stride + x * 4
                guard offset + 3 < bytes.count else { continue }
                total += Int(max(bytes[offset], max(bytes[offset + 1], bytes[offset + 2])))
            }
        }
        return total
    }

    // MARK: - Family existence

    /// `CreateTextFormat` returns `S_OK` for families that are not installed
    /// and substitutes silently, so the stack cannot use it to decide whether
    /// a face is there. `FindFamilyName` against the system collection can.
    func testFontFamilyInstallationIsAnsweredFromTheSystemCollection() async {
        await MainActor.run {
            guard let classicInstalled = DirectWriteTextRenderer.isFontFamilyInstalled("Segoe UI") else {
                XCTFail("DirectWrite must be available in the test host")
                return
            }
            XCTAssertTrue(classicInstalled, "Segoe UI ships with every supported Windows version")
            XCTAssertEqual(
                DirectWriteTextRenderer.isFontFamilyInstalled("Nonexistent Face 8f3c2a"), false,
                "a family nobody has installed must answer false, not the S_OK CreateTextFormat would give")
            XCTAssertEqual(
                DirectWriteTextRenderer.isFontFamilyInstalled(""), false,
                "the empty family name is not a family")
        }
    }

    // MARK: - The optical size ramp

    func testOpticalSizeFollowsPointSize() async {
        await MainActor.run {
            XCTAssertEqual(SystemUIFontFace.opticalSize(forPointSize: 8), .small)
            XCTAssertEqual(SystemUIFontFace.opticalSize(forPointSize: 10), .small, "caption/footnote")
            XCTAssertEqual(SystemUIFontFace.opticalSize(forPointSize: 11), .small, "subheadline")
            XCTAssertEqual(SystemUIFontFace.opticalSize(forPointSize: 11.99), .small)
            XCTAssertEqual(SystemUIFontFace.opticalSize(forPointSize: 12), .text, "callout")
            XCTAssertEqual(SystemUIFontFace.opticalSize(forPointSize: 13), .text, "body and headline")
            XCTAssertEqual(SystemUIFontFace.opticalSize(forPointSize: 17), .text, "title2")
            XCTAssertEqual(SystemUIFontFace.opticalSize(forPointSize: 19.99), .text)
            XCTAssertEqual(SystemUIFontFace.opticalSize(forPointSize: 20), .display)
            XCTAssertEqual(SystemUIFontFace.opticalSize(forPointSize: 22), .display, "title")
            XCTAssertEqual(SystemUIFontFace.opticalSize(forPointSize: 26), .display, "largeTitle")
        }
    }

    /// A caller that has lost its point size gets the body cut, not a headline
    /// one — a NaN size must not silently set an app in Display.
    func testDegeneratePointSizesFallBackToTheBodyOpticalSize() async {
        await MainActor.run {
            XCTAssertEqual(SystemUIFontFace.opticalSize(forPointSize: .nan), .text)
            XCTAssertEqual(SystemUIFontFace.opticalSize(forPointSize: .infinity), .text)
            XCTAssertEqual(SystemUIFontFace.opticalSize(forPointSize: 0), .text)
            XCTAssertEqual(SystemUIFontFace.opticalSize(forPointSize: -12), .text)
        }
    }

    // MARK: - Fallback

    func testWindowsTenFallsBackToClassicSegoeUIAtEverySize() async {
        await MainActor.run {
            SystemUIFontFace.availabilityOverrideForTesting = false
            for size: Double in [8, 10, 12, 13, 17, 20, 26, 48] {
                XCTAssertEqual(
                    SystemUIFontFace.family(forPointSize: size), "Segoe UI",
                    "\(size)pt: without the variable face every size is the classic face")
            }
        }
    }

    func testWindowsElevenUsesTheVariableFaceAtTheRightOpticalSize() async {
        await MainActor.run {
            SystemUIFontFace.availabilityOverrideForTesting = true
            XCTAssertEqual(SystemUIFontFace.family(forPointSize: 10), "Segoe UI Variable Small")
            XCTAssertEqual(SystemUIFontFace.family(forPointSize: 13), "Segoe UI Variable Text")
            XCTAssertEqual(SystemUIFontFace.family(forPointSize: 26), "Segoe UI Variable Display")
        }
    }

    /// All three cuts or none. A window whose captions were Segoe UI Variable
    /// Small and whose headlines were classic Segoe UI would be mixing two
    /// type designs, which is worse than either used consistently.
    func testTheVariableFaceIsAdoptedOnlyWhenEveryOpticalSizeIsInstalled() async {
        await MainActor.run {
            SystemUIFontFace.resetAvailabilityCacheForTesting()
            let installed = SystemUIFontFace.OpticalSize.allCases.map {
                DirectWriteTextRenderer.isFontFamilyInstalled(SystemUIFontFace.family(for: $0)) ?? false
            }
            XCTAssertEqual(
                SystemUIFontFace.isVariableFaceAvailable, installed.allSatisfy { $0 },
                "adoption must be the conjunction over every optical size")
        }
    }

    func testAvailabilityIsProbedOnceAndMemoized() async {
        await MainActor.run {
            SystemUIFontFace.resetAvailabilityCacheForTesting()
            XCTAssertFalse(SystemUIFontFace.hasProbedAvailabilityForTesting)
            let first = SystemUIFontFace.isVariableFaceAvailable
            XCTAssertTrue(
                SystemUIFontFace.hasProbedAvailabilityForTesting,
                "the answer must be cached: it is read once per Text in every rebuilt body")
            XCTAssertEqual(SystemUIFontFace.isVariableFaceAvailable, first)
        }
    }

    // MARK: - Font -> family

    func testFontDesignsResolveThroughTheUIFaceOnlyForUIDesigns() async {
        await MainActor.run {
            SystemUIFontFace.availabilityOverrideForTesting = true
            XCTAssertEqual(Font.system(size: 13).resolvedFamily, "Segoe UI Variable Text")
            XCTAssertEqual(Font.system(size: 26).resolvedFamily, "Segoe UI Variable Display")
            XCTAssertEqual(Font.system(size: 10).resolvedFamily, "Segoe UI Variable Small")
            XCTAssertEqual(Font.system(size: 13, design: .rounded).resolvedFamily, "Segoe UI Variable Text")
            XCTAssertEqual(Font.system(size: 13, design: .serif).resolvedFamily, "Georgia")
            XCTAssertEqual(Font.system(size: 13, design: .monospaced).resolvedFamily, "Cascadia Mono")
            XCTAssertEqual(
                Font.custom("Comic Sans MS", size: 13).resolvedFamily, "Comic Sans MS",
                "an app that named a family keeps it")
        }
    }

    /// The type ramp must not be flattened onto one cut: a caption, a body
    /// line and a title in the same window are three different families.
    func testTheTypeRampSpansAllThreeOpticalSizes() async {
        await MainActor.run {
            SystemUIFontFace.availabilityOverrideForTesting = true
            let families = Set(
                [Font.caption, Font.body, Font.largeTitle].map(\.resolvedFamily))
            XCTAssertEqual(
                families.count, 3,
                "caption, body and largeTitle must land in three optical cuts, got \(families.sorted())")
        }
    }

    // MARK: - What DirectWrite actually does with those names

    /// The names above are only useful if DirectWrite resolves weights inside
    /// them. Segoe UI Variable is one variable font exposed as several
    /// families, and if its weight axis did not reach the family this stack
    /// asks for, every bold label in the app would silently render regular.
    func testTheVariableFaceResolvesItsWeightAxis() async throws {
        try await MainActor.run {
            try XCTSkipUnless(
                SystemUIFontFace.isVariableFaceAvailable, "Segoe UI Variable is not installed on this host")
            for optical in SystemUIFontFace.OpticalSize.allCases {
                let family = SystemUIFontFace.family(for: optical)
                guard
                    let regular = inkMass("Handgloves", style(family: family, size: 13, weight: .regular)),
                    let semibold = inkMass("Handgloves", style(family: family, size: 13, weight: .semibold)),
                    let bold = inkMass("Handgloves", style(family: family, size: 13, weight: .bold))
                else {
                    XCTFail("\(family): DirectWrite must rasterize every weight")
                    return
                }
                XCTAssertGreaterThan(
                    semibold, Int(Double(regular) * 1.05),
                    "\(family): semibold must carry visibly more ink than regular")
                XCTAssertGreaterThan(
                    bold, Int(Double(semibold) * 1.05),
                    "\(family): bold must carry visibly more ink than semibold")
            }
        }
    }

    /// Segoe UI Variable has no italic outlines — Windows itself synthesizes
    /// an oblique for it. Pinned because the failure is silent: an italic run
    /// that resolved to the upright face would simply stop being italic.
    func testItalicStillChangesTheRasterInTheVariableFace() async throws {
        try await MainActor.run {
            try XCTSkipUnless(
                SystemUIFontFace.isVariableFaceAvailable, "Segoe UI Variable is not installed on this host")
            for optical in SystemUIFontFace.OpticalSize.allCases {
                let family = SystemUIFontFace.family(for: optical)
                guard
                    let upright = inkMass("Handgloves", style(family: family, size: 13)),
                    let italic = inkMass("Handgloves", style(family: family, size: 13, italic: true))
                else {
                    XCTFail("\(family): DirectWrite must rasterize both slopes")
                    return
                }
                XCTAssertNotEqual(upright, italic, "\(family): italic must reach the rasterizer")
            }
        }
    }

    /// The optical cuts are different type designs, not aliases: they differ
    /// in fitting, which is the whole reason to pick between them.
    func testTheOpticalCutsAreActuallyDifferentDesigns() async throws {
        try await MainActor.run {
            try XCTSkipUnless(
                SystemUIFontFace.isVariableFaceAvailable, "Segoe UI Variable is not installed on this host")
            let sample = "The quick brown fox jumps over the lazy dog"
            let widths = SystemUIFontFace.OpticalSize.allCases.map { optical -> Double in
                DirectWriteTextRenderer.measure(
                    sample, style: style(family: SystemUIFontFace.family(for: optical), size: 13), scaleFactor: 1
                )?.width ?? 0
            }
            XCTAssertEqual(widths.count, 3)
            XCTAssertGreaterThan(
                widths[0], widths[1],
                "Small is fitted looser than Text — that is what makes a 10pt caption legible")
            XCTAssertGreaterThan(
                widths[1], widths[2],
                "Text is fitted looser than Display — that is what makes a 26pt title hold together")
        }
    }
}
