import Foundation
import SwiftWindowsCore
import SwiftWindowsGraphics
import XCTest

@testable import SwiftWindowsUI
@testable import WinSwiftUI

/// Locks the CPU rasterizer's pixel output for a representative scene
/// against a precomputed content hash. This is the closest verifiable
/// "match a reference" we can build without a macOS environment: the
/// hash anchors the current rendering, and any future change to the
/// rasterizer, scene painter, fonts, or shape primitives that affects
/// visible pixels trips this test.
///
/// Updating a baseline:
/// 1. Make the visual change.
/// 2. Run this test, capture the new hash from the failure message.
/// 3. Replace the corresponding `goldenHash` constant.
/// 4. Note the visual change in the commit message so reviewers can
///    confirm the new look is intentional.
@MainActor
final class VisualBaselineRegressionTests: XCTestCase {

    /// FNV-1a 64-bit, applied byte-by-byte to the pixel buffer. Fast,
    /// deterministic, no third-party dependency, and good enough for
    /// "did anything change" — collisions are vanishingly unlikely for
    /// scenes of this size.
    private func contentHash(of pixels: Data) -> UInt64 {
        let prime: UInt64 = 0x100_0000_01b3
        let offsetBasis: UInt64 = 0xcbf2_9ce4_8422_2325
        var hash = offsetBasis
        pixels.withUnsafeBytes { raw in
            for byte in raw {
                hash ^= UInt64(byte)
                hash = hash &* prime
            }
        }
        return hash
    }

    private func renderShapeGridScene() -> BitmapSurface {
        let view = ZStack {
            Rectangle()
                .fill(Color(red: 1, green: 0, blue: 0, alpha: 1))
                .frame(width: 40, height: 40)
                .offset(x: -60, y: -40)
            Rectangle()
                .fill(Color(red: 0, green: 1, blue: 0, alpha: 1))
                .frame(width: 40, height: 40)
                .offset(x: 0, y: -40)
            Rectangle()
                .fill(Color(red: 0, green: 0, blue: 1, alpha: 1))
                .frame(width: 40, height: 40)
                .offset(x: 60, y: -40)
            Rectangle()
                .fill(Color(red: 1, green: 1, blue: 1, alpha: 1))
                .frame(width: 40, height: 40)
                .offset(x: 0, y: 40)
        }
        .frame(width: 200, height: 200)

        let size = IntSize(width: 200, height: 200)
        let scene = WinSwiftUIRendererSnapshotter.snapshot(
            of: view, size: size, displayScale: 1, clearColor: Color(red: 0, green: 0, blue: 0, alpha: 1)
        ).scene
        return GPUIRawSceneRasterizer.rasterize(scene, size: size)
    }

    func testShapeGridSceneMatchesLockedVisualBaseline() async {
        await MainActor.run {
            let bitmap = renderShapeGridScene()
            let hash = contentHash(of: bitmap.pixels)
            // Golden hash: regenerate via the steps in this file's header
            // comment if a visual change is intentional. Otherwise, a
            // hash drift means the rendering pipeline produces different
            // pixels than the last reviewed baseline.
            let goldenHash: UInt64 = 0xFA5C_A9ED_4D36_C725
            XCTAssertEqual(
                hash, goldenHash,
                String(
                    format:
                        "Shape grid pixel hash drifted. Was 0x%016llX, expected 0x%016llX. "
                        + "If the visual change is intentional, update the goldenHash constant.",
                    hash, goldenHash
                )
            )
        }
    }

    func testHashFunctionIsDeterministicAcrossInvocations() async {
        await MainActor.run {
            let bytes = Data((0..<256).map { UInt8($0) })
            let h1 = contentHash(of: bytes)
            let h2 = contentHash(of: bytes)
            XCTAssertEqual(h1, h2, "FNV-1a must produce identical output for identical input")
        }
    }

    func testHashDistinguishesDifferentInputs() async {
        await MainActor.run {
            var bytes = Data(repeating: 0xAB, count: 256)
            let h1 = contentHash(of: bytes)
            bytes[128] = 0xCD
            let h2 = contentHash(of: bytes)
            XCTAssertNotEqual(h1, h2, "Single-byte change must produce a different hash")
        }
    }
}
