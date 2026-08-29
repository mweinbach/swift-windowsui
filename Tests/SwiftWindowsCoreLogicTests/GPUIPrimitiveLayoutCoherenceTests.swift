import SwiftWindowsGraphics
import XCTest

/// Renderer-neutral contract checks (Phase 8): the `SwiftWindowsGraphics`
/// primitive structs are uploaded verbatim into D3D11 structured buffers, so
/// each field's byte offset must match the HLSL instance-struct layout it is
/// consumed with:
///
/// - `QuadPrimitive`   ↔ `QuadInstance`   in `BatchShaders.swift`
/// - `GlyphPrimitive`  ↔ `GlyphInstance`  in `GlyphPipeline.swift`
/// - `ShadowPrimitive` ↔ `ShadowInstance` in `BatchShaders.swift`
/// - `ImagePrimitive`  ↔ `ImageInstance`  in `BatchShaders.swift`
///
/// The CPU rasterizer (`CPUBatchRenderer`, `GPUIRawSceneRasterizer`) reads the
/// same Swift structs directly, so keeping the field order pinned here keeps
/// all three consumers in sync. `D3D11BatchRendererTests` already pins the
/// strides; these tests pin the individual field offsets so a reordered or
/// inserted field fails loudly instead of corrupting GPU reads.
///
/// `PathPrimitive` is intentionally not pinned: it is CPU-rasterized and
/// tessellated to quads before reaching D3D11, so it has no GPU layout.
final class GPUIPrimitiveLayoutCoherenceTests: XCTestCase {

    // MARK: - QuadPrimitive ↔ QuadInstance (144 bytes, 36 x Float)

    func testQuadPrimitiveFieldOffsetsMatchQuadInstance() async {
        XCTAssertEqual(MemoryLayout<QuadPrimitive>.offset(of: \.x), 0)
        XCTAssertEqual(MemoryLayout<QuadPrimitive>.offset(of: \.y), 4)
        XCTAssertEqual(MemoryLayout<QuadPrimitive>.offset(of: \.width), 8)
        XCTAssertEqual(MemoryLayout<QuadPrimitive>.offset(of: \.height), 12)
        XCTAssertEqual(MemoryLayout<QuadPrimitive>.offset(of: \.cornerRadius), 16)
        XCTAssertEqual(MemoryLayout<QuadPrimitive>.offset(of: \.startR), 20)
        XCTAssertEqual(MemoryLayout<QuadPrimitive>.offset(of: \.startG), 24)
        XCTAssertEqual(MemoryLayout<QuadPrimitive>.offset(of: \.startB), 28)
        XCTAssertEqual(MemoryLayout<QuadPrimitive>.offset(of: \.startA), 32)
        XCTAssertEqual(MemoryLayout<QuadPrimitive>.offset(of: \.endR), 36)
        XCTAssertEqual(MemoryLayout<QuadPrimitive>.offset(of: \.endG), 40)
        XCTAssertEqual(MemoryLayout<QuadPrimitive>.offset(of: \.endB), 44)
        XCTAssertEqual(MemoryLayout<QuadPrimitive>.offset(of: \.endA), 48)
        XCTAssertEqual(MemoryLayout<QuadPrimitive>.offset(of: \.gradientAxis), 52)
        XCTAssertEqual(MemoryLayout<QuadPrimitive>.offset(of: \.clipX), 56)
        XCTAssertEqual(MemoryLayout<QuadPrimitive>.offset(of: \.clipY), 60)
        XCTAssertEqual(MemoryLayout<QuadPrimitive>.offset(of: \.clipWidth), 64)
        XCTAssertEqual(MemoryLayout<QuadPrimitive>.offset(of: \.clipHeight), 68)
        XCTAssertEqual(MemoryLayout<QuadPrimitive>.offset(of: \.effectType), 72)
        XCTAssertEqual(MemoryLayout<QuadPrimitive>.offset(of: \.effectIntensity), 76)
        XCTAssertEqual(MemoryLayout<QuadPrimitive>.offset(of: \.blurRadius), 80)
        XCTAssertEqual(MemoryLayout<QuadPrimitive>.offset(of: \.blurOpaque), 84)
        XCTAssertEqual(MemoryLayout<QuadPrimitive>.offset(of: \.effectParam1), 88)
        XCTAssertEqual(MemoryLayout<QuadPrimitive>.offset(of: \.effectParam2), 92)
        XCTAssertEqual(MemoryLayout<QuadPrimitive>.offset(of: \.effectParam3), 96)
        XCTAssertEqual(MemoryLayout<QuadPrimitive>.offset(of: \.effectParam4), 100)
        XCTAssertEqual(MemoryLayout<QuadPrimitive>.offset(of: \.clipCornerRadius), 104)
        XCTAssertEqual(MemoryLayout<QuadPrimitive>.offset(of: \.blendMode), 108)
        XCTAssertEqual(MemoryLayout<QuadPrimitive>.offset(of: \.rotationRadians), 112)
        XCTAssertEqual(MemoryLayout<QuadPrimitive>.offset(of: \.cornerRadiusTopLeft), 116)
        XCTAssertEqual(MemoryLayout<QuadPrimitive>.offset(of: \.cornerRadiusTopRight), 120)
        XCTAssertEqual(MemoryLayout<QuadPrimitive>.offset(of: \.cornerRadiusBottomRight), 124)
        XCTAssertEqual(MemoryLayout<QuadPrimitive>.offset(of: \.cornerRadiusBottomLeft), 128)
        XCTAssertEqual(MemoryLayout<QuadPrimitive>.offset(of: \._reserved0), 132)
        XCTAssertEqual(MemoryLayout<QuadPrimitive>.offset(of: \._reserved1), 136)
        XCTAssertEqual(MemoryLayout<QuadPrimitive>.offset(of: \._reserved2), 140)
        XCTAssertEqual(MemoryLayout<QuadPrimitive>.stride, 144)
        XCTAssertEqual(MemoryLayout<QuadPrimitive>.stride % 16, 0)
    }

    // MARK: - GlyphPrimitive ↔ GlyphInstance (80 bytes, 20 x Float)

    func testGlyphPrimitiveFieldOffsetsMatchGlyphInstance() async {
        XCTAssertEqual(MemoryLayout<GlyphPrimitive>.offset(of: \.screenX), 0)
        XCTAssertEqual(MemoryLayout<GlyphPrimitive>.offset(of: \.screenY), 4)
        XCTAssertEqual(MemoryLayout<GlyphPrimitive>.offset(of: \.screenW), 8)
        XCTAssertEqual(MemoryLayout<GlyphPrimitive>.offset(of: \.screenH), 12)
        XCTAssertEqual(MemoryLayout<GlyphPrimitive>.offset(of: \.atlasU0), 16)
        XCTAssertEqual(MemoryLayout<GlyphPrimitive>.offset(of: \.atlasV0), 20)
        XCTAssertEqual(MemoryLayout<GlyphPrimitive>.offset(of: \.atlasU1), 24)
        XCTAssertEqual(MemoryLayout<GlyphPrimitive>.offset(of: \.atlasV1), 28)
        XCTAssertEqual(MemoryLayout<GlyphPrimitive>.offset(of: \.colorR), 32)
        XCTAssertEqual(MemoryLayout<GlyphPrimitive>.offset(of: \.colorG), 36)
        XCTAssertEqual(MemoryLayout<GlyphPrimitive>.offset(of: \.colorB), 40)
        XCTAssertEqual(MemoryLayout<GlyphPrimitive>.offset(of: \.colorA), 44)
        XCTAssertEqual(MemoryLayout<GlyphPrimitive>.offset(of: \.clipX), 48)
        XCTAssertEqual(MemoryLayout<GlyphPrimitive>.offset(of: \.clipY), 52)
        XCTAssertEqual(MemoryLayout<GlyphPrimitive>.offset(of: \.clipWidth), 56)
        XCTAssertEqual(MemoryLayout<GlyphPrimitive>.offset(of: \.clipHeight), 60)
        XCTAssertEqual(MemoryLayout<GlyphPrimitive>.offset(of: \.clipCornerRadius), 64)
        XCTAssertEqual(MemoryLayout<GlyphPrimitive>.offset(of: \.rotationRadians), 68)
        XCTAssertEqual(MemoryLayout<GlyphPrimitive>.offset(of: \._pad1), 72)
        XCTAssertEqual(MemoryLayout<GlyphPrimitive>.offset(of: \._pad2), 76)
        XCTAssertEqual(MemoryLayout<GlyphPrimitive>.stride, 80)
        XCTAssertEqual(MemoryLayout<GlyphPrimitive>.stride % 16, 0)
    }

    // MARK: - ShadowPrimitive ↔ ShadowInstance (80 bytes, 20 x Float)

    func testShadowPrimitiveFieldOffsetsMatchShadowInstance() async {
        XCTAssertEqual(MemoryLayout<ShadowPrimitive>.offset(of: \.x), 0)
        XCTAssertEqual(MemoryLayout<ShadowPrimitive>.offset(of: \.y), 4)
        XCTAssertEqual(MemoryLayout<ShadowPrimitive>.offset(of: \.width), 8)
        XCTAssertEqual(MemoryLayout<ShadowPrimitive>.offset(of: \.height), 12)
        XCTAssertEqual(MemoryLayout<ShadowPrimitive>.offset(of: \.cornerRadius), 16)
        XCTAssertEqual(MemoryLayout<ShadowPrimitive>.offset(of: \.colorR), 20)
        XCTAssertEqual(MemoryLayout<ShadowPrimitive>.offset(of: \.colorG), 24)
        XCTAssertEqual(MemoryLayout<ShadowPrimitive>.offset(of: \.colorB), 28)
        XCTAssertEqual(MemoryLayout<ShadowPrimitive>.offset(of: \.colorA), 32)
        XCTAssertEqual(MemoryLayout<ShadowPrimitive>.offset(of: \.blurRadius), 36)
        XCTAssertEqual(MemoryLayout<ShadowPrimitive>.offset(of: \.offsetX), 40)
        XCTAssertEqual(MemoryLayout<ShadowPrimitive>.offset(of: \.offsetY), 44)
        XCTAssertEqual(MemoryLayout<ShadowPrimitive>.offset(of: \.clipX), 48)
        XCTAssertEqual(MemoryLayout<ShadowPrimitive>.offset(of: \.clipY), 52)
        XCTAssertEqual(MemoryLayout<ShadowPrimitive>.offset(of: \.clipWidth), 56)
        XCTAssertEqual(MemoryLayout<ShadowPrimitive>.offset(of: \.clipHeight), 60)
        XCTAssertEqual(MemoryLayout<ShadowPrimitive>.offset(of: \.clipCornerRadius), 64)
        XCTAssertEqual(MemoryLayout<ShadowPrimitive>.offset(of: \.rotationRadians), 68)
        XCTAssertEqual(MemoryLayout<ShadowPrimitive>.offset(of: \._pad1), 72)
        XCTAssertEqual(MemoryLayout<ShadowPrimitive>.offset(of: \._pad2), 76)
        XCTAssertEqual(MemoryLayout<ShadowPrimitive>.stride, 80)
        XCTAssertEqual(MemoryLayout<ShadowPrimitive>.stride % 16, 0)
    }

    // MARK: - ImagePrimitive ↔ ImageInstance (128 bytes; textureID/samplingKind are Int32 ↔ HLSL int)

    func testImagePrimitiveFieldOffsetsMatchImageInstance() async {
        XCTAssertEqual(MemoryLayout<ImagePrimitive>.offset(of: \.screenX), 0)
        XCTAssertEqual(MemoryLayout<ImagePrimitive>.offset(of: \.screenY), 4)
        XCTAssertEqual(MemoryLayout<ImagePrimitive>.offset(of: \.screenW), 8)
        XCTAssertEqual(MemoryLayout<ImagePrimitive>.offset(of: \.screenH), 12)
        XCTAssertEqual(MemoryLayout<ImagePrimitive>.offset(of: \.uvX), 16)
        XCTAssertEqual(MemoryLayout<ImagePrimitive>.offset(of: \.uvY), 20)
        XCTAssertEqual(MemoryLayout<ImagePrimitive>.offset(of: \.uvW), 24)
        XCTAssertEqual(MemoryLayout<ImagePrimitive>.offset(of: \.uvH), 28)
        XCTAssertEqual(MemoryLayout<ImagePrimitive>.offset(of: \.opacity), 32)
        XCTAssertEqual(MemoryLayout<ImagePrimitive>.offset(of: \.clipX), 36)
        XCTAssertEqual(MemoryLayout<ImagePrimitive>.offset(of: \.clipY), 40)
        XCTAssertEqual(MemoryLayout<ImagePrimitive>.offset(of: \.clipWidth), 44)
        XCTAssertEqual(MemoryLayout<ImagePrimitive>.offset(of: \.clipHeight), 48)
        XCTAssertEqual(MemoryLayout<ImagePrimitive>.offset(of: \.textureID), 52)
        XCTAssertEqual(MemoryLayout<ImagePrimitive>.offset(of: \.clipCornerRadius), 56)
        XCTAssertEqual(MemoryLayout<ImagePrimitive>.offset(of: \.rotationRadians), 60)
        XCTAssertEqual(MemoryLayout<ImagePrimitive>.offset(of: \.affineA), 64)
        XCTAssertEqual(MemoryLayout<ImagePrimitive>.offset(of: \.affineB), 68)
        XCTAssertEqual(MemoryLayout<ImagePrimitive>.offset(of: \.affineC), 72)
        XCTAssertEqual(MemoryLayout<ImagePrimitive>.offset(of: \.affineD), 76)
        XCTAssertEqual(MemoryLayout<ImagePrimitive>.offset(of: \.sourceCapLeft), 80)
        XCTAssertEqual(MemoryLayout<ImagePrimitive>.offset(of: \.sourceCapTop), 84)
        XCTAssertEqual(MemoryLayout<ImagePrimitive>.offset(of: \.sourceCapRight), 88)
        XCTAssertEqual(MemoryLayout<ImagePrimitive>.offset(of: \.sourceCapBottom), 92)
        XCTAssertEqual(MemoryLayout<ImagePrimitive>.offset(of: \.destinationCapLeft), 96)
        XCTAssertEqual(MemoryLayout<ImagePrimitive>.offset(of: \.destinationCapTop), 100)
        XCTAssertEqual(MemoryLayout<ImagePrimitive>.offset(of: \.destinationCapRight), 104)
        XCTAssertEqual(MemoryLayout<ImagePrimitive>.offset(of: \.destinationCapBottom), 108)
        XCTAssertEqual(MemoryLayout<ImagePrimitive>.offset(of: \.centerRepeatX), 112)
        XCTAssertEqual(MemoryLayout<ImagePrimitive>.offset(of: \.centerRepeatY), 116)
        XCTAssertEqual(MemoryLayout<ImagePrimitive>.offset(of: \.samplingKind), 120)
        XCTAssertEqual(MemoryLayout<ImagePrimitive>.offset(of: \.samplingPadding), 124)
        XCTAssertEqual(MemoryLayout<ImagePrimitive>.stride, 128)
        XCTAssertEqual(MemoryLayout<ImagePrimitive>.stride % 16, 0)
    }

    // MARK: - byteSize conveniences agree with the pinned layouts

    func testByteSizeMatchesPinnedStride() async {
        XCTAssertEqual(QuadPrimitive.byteSize, MemoryLayout<QuadPrimitive>.stride)
        XCTAssertEqual(GlyphPrimitive.byteSize, MemoryLayout<GlyphPrimitive>.stride)
        XCTAssertEqual(ShadowPrimitive.byteSize, MemoryLayout<ShadowPrimitive>.stride)
        XCTAssertEqual(ImagePrimitive.byteSize, MemoryLayout<ImagePrimitive>.stride)
    }
}
