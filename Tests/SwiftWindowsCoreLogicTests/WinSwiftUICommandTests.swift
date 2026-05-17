import Foundation
import SwiftWindowsCore
import XCTest

@testable import SwiftWindowsUI
@testable import WinSwiftUI

@MainActor
private struct PointerHandlerProbe: View {
    typealias Body = Never

    var onKeyDown: ((KeyboardEvent) -> Void)? = nil

    var body: Never {
        fatalError("PointerHandlerProbe has no body")
    }

    func makeComponent(context: ViewBuildContext) -> Component {
        Component { _ in
            let node = Controls.panel(preferredSize: Size(width: 80, height: 24))
            node.onKeyDown = onKeyDown
            return node
        }
    }
}

final class WinSwiftUICommandTests: XCTestCase {
    func testOnCopyCommandHandlesCtrlCAndPreservesOtherKeys() async {
        await MainActor.run {
            var copyCount = 0
            var forwardedKeys: [KeyboardKey?] = []
            let node = makeNode(
                PointerHandlerProbe(onKeyDown: { event in
                    forwardedKeys.append(event.key)
                })
                .onCopyCommand {
                    copyCount += 1
                }
            )

            node.onKeyDown?(KeyboardEvent(keyCode: 0x43, modifiers: [.control]))
            node.onKeyDown?(KeyboardEvent(keyCode: 0x43, modifiers: []))
            node.onKeyDown?(KeyboardEvent(keyCode: 0x44, modifiers: [.control]))

            XCTAssertEqual(copyCount, 1)
            XCTAssertEqual(forwardedKeys, [nil, nil])
        }
    }

    func testOnCutCommandHandlesCtrlXAndPreservesOtherKeys() async {
        await MainActor.run {
            var cutCount = 0
            var forwardedKeys: [KeyboardKey?] = []
            let node = makeNode(
                PointerHandlerProbe(onKeyDown: { event in
                    forwardedKeys.append(event.key)
                })
                .onCutCommand {
                    cutCount += 1
                }
            )

            node.onKeyDown?(KeyboardEvent(keyCode: 0x58, modifiers: [.control]))
            node.onKeyDown?(KeyboardEvent(keyCode: 0x58, modifiers: []))
            node.onKeyDown?(KeyboardEvent(keyCode: 0x59, modifiers: [.control]))

            XCTAssertEqual(cutCount, 1)
            XCTAssertEqual(forwardedKeys, [nil, nil])
        }
    }

    func testOnPasteCommandHandlesCtrlVAndPreservesOtherKeys() async {
        await MainActor.run {
            var pasteCount = 0
            var forwardedKeys: [KeyboardKey?] = []
            let node = makeNode(
                PointerHandlerProbe(onKeyDown: { event in
                    forwardedKeys.append(event.key)
                })
                .onPasteCommand {
                    pasteCount += 1
                }
            )

            node.onKeyDown?(KeyboardEvent(keyCode: 0x56, modifiers: [.control]))
            node.onKeyDown?(KeyboardEvent(keyCode: 0x56, modifiers: []))
            node.onKeyDown?(KeyboardEvent(keyCode: 0x57, modifiers: [.control]))

            XCTAssertEqual(pasteCount, 1)
            XCTAssertEqual(forwardedKeys, [nil, nil])
        }
    }

    func testOnSelectAllCommandHandlesCtrlAAndPreservesOtherKeys() async {
        await MainActor.run {
            var selectCount = 0
            var forwardedKeys: [KeyboardKey?] = []
            let node = makeNode(
                PointerHandlerProbe(onKeyDown: { event in
                    forwardedKeys.append(event.key)
                })
                .onSelectAllCommand {
                    selectCount += 1
                }
            )

            node.onKeyDown?(KeyboardEvent(keyCode: 0x41, modifiers: [.control]))
            node.onKeyDown?(KeyboardEvent(keyCode: 0x41, modifiers: []))
            node.onKeyDown?(KeyboardEvent(keyCode: 0x42, modifiers: [.control]))

            XCTAssertEqual(selectCount, 1)
            XCTAssertEqual(forwardedKeys, [nil, nil])
        }
    }

    func testOnUndoCommandHandlesCtrlZAndPreservesOtherKeys() async {
        await MainActor.run {
            var undoCount = 0
            var forwardedKeys: [KeyboardKey?] = []
            let node = makeNode(
                PointerHandlerProbe(onKeyDown: { event in
                    forwardedKeys.append(event.key)
                })
                .onUndoCommand {
                    undoCount += 1
                }
            )

            node.onKeyDown?(KeyboardEvent(keyCode: 0x5A, modifiers: [.control]))
            node.onKeyDown?(KeyboardEvent(keyCode: 0x5A, modifiers: [.control, .shift]))
            node.onKeyDown?(KeyboardEvent(keyCode: 0x5B, modifiers: [.control]))

            XCTAssertEqual(undoCount, 1)
            XCTAssertEqual(forwardedKeys, [nil, nil])
        }
    }

    func testOnRedoCommandHandlesCtrlShiftZAndCtrlYAndPreservesOtherKeys() async {
        await MainActor.run {
            var redoCount = 0
            var forwardedKeys: [KeyboardKey?] = []
            let node = makeNode(
                PointerHandlerProbe(onKeyDown: { event in
                    forwardedKeys.append(event.key)
                })
                .onRedoCommand {
                    redoCount += 1
                }
            )

            node.onKeyDown?(KeyboardEvent(keyCode: 0x5A, modifiers: [.control, .shift]))
            node.onKeyDown?(KeyboardEvent(keyCode: 0x59, modifiers: [.control]))
            node.onKeyDown?(KeyboardEvent(keyCode: 0x5A, modifiers: [.control]))
            node.onKeyDown?(KeyboardEvent(keyCode: 0x58, modifiers: [.control]))

            XCTAssertEqual(redoCount, 2)
            XCTAssertEqual(forwardedKeys, [nil, nil])
        }
    }

    func testOnCommandRegistersSelectorHandlerOnNode() async {
        await MainActor.run {
            var commandFired = false
            let selector = Selector("testCommand")
            let node = makeNode(
                Text("CMD")
                    .onCommand(selector) {
                        commandFired = true
                    }
            )

            XCTAssertNotNil(node.commandHandlers["testCommand"])
            node.commandHandlers["testCommand"]?()
            XCTAssertTrue(commandFired)
        }
    }
}

@MainActor
private func makeNode<V: View>(_ view: V) -> ViewNode {
    let runtime = RetainedViewRuntime(root: ViewNode())
    let context = ViewBuildContext(
        canvasSizeProvider: { Size(width: 800, height: 600) },
        invalidateHandler: {}
    )
    return view.makeComponent(context: context).makeNode(runtime: runtime)
}
