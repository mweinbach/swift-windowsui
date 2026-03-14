import XCTest
import SwiftWindowsCore
import SwiftWindowsGraphics
import SwiftWindowsScene

final class SceneTests: XCTestCase {
    func testSceneFrameBuildsRenderCommandsFromNodes() {
        let node = SolidRectNode(
            rect: Rect(x: 12, y: 18, width: 40, height: 24),
            color: Color(red: 0.2, green: 0.4, blue: 0.6, alpha: 1),
            cornerRadius: 6
        )
        let scene = Scene(clearColor: .white, nodes: [.solidRect(node)])

        XCTAssertEqual(
            scene.frame,
            RenderFrame(
                clearColor: .white,
                commands: [
                    .fillRect(
                        FillRectCommand(
                            rect: node.rect,
                            color: node.color,
                            cornerRadius: node.cornerRadius
                        )
                    )
                ]
            )
        )
    }
}
