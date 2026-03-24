import XCTest
@testable import SwiftWindowsRendererD3D11

final class ShadowPipelineTests: XCTestCase {
    func testShadowShadersCompile() throws {
        try ShadowPipeline.validateShadersForTesting()
    }

    func testShaderSourceIsNonEmpty() {
        XCTAssertFalse(ShadowPipeline.shaderSource.isEmpty)
    }

    func testEntryPointNames() {
        XCTAssertEqual(ShadowPipeline.vertexShaderEntryPoint, "vsMain")
        XCTAssertEqual(ShadowPipeline.pixelShaderEntryPoint, "psMain")
    }
}
