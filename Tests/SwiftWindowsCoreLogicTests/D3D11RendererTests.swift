import XCTest
@testable import SwiftWindowsRendererD3D11

final class D3D11RendererTests: XCTestCase {
    func testShaderSourceCompiles() async throws {
        try await MainActor.run {
            try D3D11Renderer.validateShaderSourceForTesting()
        }
    }
}
