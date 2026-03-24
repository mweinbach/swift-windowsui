import XCTest
@testable import SwiftWindowsRendererD3D11

final class GlyphPipelineTests: XCTestCase {
    func testGlyphShadersCompile() async throws {
        try await MainActor.run {
            try GlyphPipeline.validateShadersForTesting()
        }
    }

    func testShaderSourceIsNonEmpty() async {
        let source = await MainActor.run { GlyphPipelineResources.vertexShaderSource }
        XCTAssertFalse(source.isEmpty)
    }

    func testEntryPointNames() async {
        await MainActor.run {
            XCTAssertEqual(GlyphPipelineResources.vertexShaderEntryPoint, "vsMain")
            XCTAssertEqual(GlyphPipelineResources.pixelShaderEntryPoint, "psMain")
        }
    }
}
