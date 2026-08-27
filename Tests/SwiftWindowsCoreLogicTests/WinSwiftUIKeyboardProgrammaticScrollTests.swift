import SwiftWindowsCore
import SwiftWindowsGraphics
import XCTest

@testable import SwiftWindowsUI
@testable import WinSwiftUI

final class WinSwiftUIKeyboardProgrammaticScrollTests: XCTestCase {
    func testKeyboardButtonActivationAnimatesAndUnrelatedKeysDoNotCancelTheScroll() async throws {
        try await MainActor.run {
            for activationKey in [KeyboardKey.enter, .space] {
                let runtime = RetainedViewRuntime(root: ViewNode(frame: Rect(x: 0, y: 0, width: 120, height: 100)))
                let clock = RuntimeTestClock()
                runtime.clock = { clock.now }
                let context = ViewBuildContext(
                    canvasSizeProvider: { Size(width: 120, height: 100) }, invalidateHandler: {})
                var activations = 0
                var offsets: [Double] = []
                var phases: [ScrollPhase] = []
                let node = ScrollViewReader { proxy in
                    ScrollView(.vertical, showsIndicators: false) {
                        Button("GO") {
                            activations += 1
                            withAnimation(.linear(duration: 0.6)) {
                                proxy.scrollTo("marker", anchor: .top)
                            }
                        }
                        .frame(width: 80, height: 30)
                        WinSwiftUI.Color.clear.frame(width: 80, height: 50)
                        WinSwiftUI.Color(red: 1, green: 0, blue: 0, alpha: 1)
                            .frame(width: 80, height: 10)
                            .id("marker")
                        WinSwiftUI.Color.clear.frame(width: 80, height: 400)
                    }
                    .frame(width: 120, height: 100)
                    .onScrollGeometryChange(for: Double.self, of: { Double($0.contentOffset.y) }) { _, new in
                        offsets.append(new)
                    }
                    .onScrollPhaseChange { _, new in phases.append(new) }
                }
                .makeComponent(context: context)
                .makeNode(runtime: runtime)
                node.frame = Rect(x: 0, y: 0, width: 120, height: 100)
                runtime.root.addChild(node)
                _ = runtime.renderScene()

                var pending = [node]
                var scroller: ViewNode?
                var button: ViewNode?
                while let current = pending.popLast() {
                    if current.scrollAxis != nil { scroller = current }
                    if current.isFocusable, current.onActivate != nil { button = current }
                    pending.append(contentsOf: current.children.reversed())
                }
                let retainedScroll = try XCTUnwrap(scroller)
                runtime.requestFocus(try XCTUnwrap(button))
                runtime.keyDown(KeyboardEvent(keyCode: activationKey.rawValue))
                _ = runtime.renderScene()
                XCTAssertEqual(activations, 1)
                XCTAssertEqual(retainedScroll.scrollOffset, 80, accuracy: 0.0001)
                XCTAssertEqual(retainedScroll.resolvedScrollOffset, 0, accuracy: 0.0001)
                XCTAssertEqual(offsets, [0])
                XCTAssertEqual(phases, [.animating])

                for (time, expectedOffset) in [(0.3, 40.0), (0.45, 60.0), (0.6, 80.0)] {
                    clock.now = time
                    _ = runtime.tickAnimations(at: time)
                    let scene = runtime.renderScene()
                    XCTAssertEqual(retainedScroll.resolvedScrollOffset, expectedOffset, accuracy: 0.0001)
                    XCTAssertEqual(offsets.last ?? -1, expectedOffset, accuracy: 0.0001)
                    let markerY = scene.layers.flatMap(\.quads).first {
                        $0.startR == 1 && $0.startG == 0 && $0.startB == 0 && $0.startA == 1
                    }.map { Double($0.y) }
                    XCTAssertEqual(markerY ?? -1, 80 - expectedOffset, accuracy: 0.001)

                    if time == 0.3 {
                        // Backspace and a cross-axis arrow reach the runtime's
                        // recognized-key path, but neither scrolls this viewport.
                        for keyCode in [UInt32(0x41), KeyboardKey.backspace.rawValue, KeyboardKey.rightArrow.rawValue] {
                            runtime.keyDown(KeyboardEvent(keyCode: keyCode))
                            _ = runtime.renderScene()
                            XCTAssertEqual(retainedScroll.resolvedScrollOffset, 40, accuracy: 0.0001)
                            XCTAssertEqual(phases, [.animating])
                        }
                    }
                }
                XCTAssertEqual(activations, 1)
                XCTAssertEqual(phases, [.animating, .idle])
            }
        }
    }
}
