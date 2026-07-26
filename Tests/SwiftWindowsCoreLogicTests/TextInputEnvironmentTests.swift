import Foundation

import SwiftWindowsCore

import XCTest

@testable import SwiftWindowsUI
@testable import WinSwiftUI

@MainActor
private final class FakeEnvironmentClipboard: TextInputClipboard {
    var stored: String?
    var copyCount = 0

    func copyString(_ text: String) {
        stored = text
        copyCount += 1
    }

    func pasteString() -> String? {
        stored
    }
}

@MainActor
private func makeContext(clipboard: (any TextInputClipboard)? = nil) -> ViewBuildContext {
    let context = ViewBuildContext(
        canvasSizeProvider: { Size(width: 800, height: 600) },
        invalidateHandler: {}
    )
    guard let clipboard else {
        return context
    }
    return context.withEnvironmentValue(\.textInputClipboard, clipboard)
}

private func controlKey(_ keyCode: UInt32) -> KeyboardEvent {
    KeyboardEvent(keyCode: keyCode, modifiers: [.control])
}

final class TextInputEnvironmentTests: XCTestCase {
    func testEnvironmentClipboardTakesPrecedenceOverStaticProvider() async {
        await MainActor.run {
            let staticClipboard = FakeEnvironmentClipboard()
            TextInputClipboardProvider.current = staticClipboard
            let environmentClipboard = FakeEnvironmentClipboard()

            var value = "hello"
            let runtime = RetainedViewRuntime(root: ViewNode())
            let node = TextField("VALUE", text: Binding(get: { value }, set: { value = $0 }))
                .makeComponent(context: makeContext(clipboard: environmentClipboard))
                .makeNode(runtime: runtime)

            node.onKeyDown?(controlKey(0x41))  // Ctrl+A
            node.onKeyDown?(controlKey(0x43))  // Ctrl+C

            XCTAssertEqual(environmentClipboard.stored, "hello")
            XCTAssertEqual(environmentClipboard.copyCount, 1)
            XCTAssertEqual(staticClipboard.copyCount, 0)
            XCTAssertNil(staticClipboard.stored)

            environmentClipboard.stored = "xy"
            node.onKeyDown?(controlKey(0x56))  // Ctrl+V pastes over the selection

            XCTAssertEqual(value, "xy")
            XCTAssertEqual(node.textInputCaretOffset, 2)
        }
    }

    func testEnvironmentModifierInjectsClipboard() async {
        await MainActor.run {
            let staticClipboard = FakeEnvironmentClipboard()
            TextInputClipboardProvider.current = staticClipboard
            let environmentClipboard = FakeEnvironmentClipboard()

            var value = "hello"
            let runtime = RetainedViewRuntime(root: ViewNode())
            let node = TextField("VALUE", text: Binding(get: { value }, set: { value = $0 }))
                .environment(\.textInputClipboard, environmentClipboard)
                .makeComponent(context: makeContext())
                .makeNode(runtime: runtime)

            node.onKeyDown?(controlKey(0x41))  // Ctrl+A
            node.onKeyDown?(controlKey(0x58))  // Ctrl+X

            XCTAssertEqual(environmentClipboard.stored, "hello")
            XCTAssertEqual(environmentClipboard.copyCount, 1)
            XCTAssertEqual(staticClipboard.copyCount, 0)
            XCTAssertEqual(value, "")
            XCTAssertEqual(node.textInputCaretOffset, 0)
        }
    }

    func testStaticProviderRemainsFallbackWhenEnvironmentUnset() async {
        await MainActor.run {
            let staticClipboard = FakeEnvironmentClipboard()
            TextInputClipboardProvider.current = staticClipboard

            var value = "abc"
            let runtime = RetainedViewRuntime(root: ViewNode())
            let node = TextField("VALUE", text: Binding(get: { value }, set: { value = $0 }))
                .makeComponent(context: makeContext())
                .makeNode(runtime: runtime)

            node.onKeyDown?(controlKey(0x41))  // Ctrl+A
            node.onKeyDown?(controlKey(0x43))  // Ctrl+C

            XCTAssertEqual(staticClipboard.stored, "abc")
            XCTAssertEqual(staticClipboard.copyCount, 1)

            staticClipboard.stored = "z"
            node.onKeyDown?(controlKey(0x56))  // Ctrl+V

            XCTAssertEqual(value, "z")
            XCTAssertEqual(node.textInputCaretOffset, 1)
        }
    }

    func testEnvironmentClipboardAppliesToTextEditor() async {
        await MainActor.run {
            let environmentClipboard = FakeEnvironmentClipboard()
            environmentClipboard.stored = "a\r\nb"

            var value = ""
            let runtime = RetainedViewRuntime(root: ViewNode())
            let node = TextEditor(text: Binding(get: { value }, set: { value = $0 }))
                .makeComponent(context: makeContext(clipboard: environmentClipboard))
                .makeNode(runtime: runtime)

            node.onKeyDown?(controlKey(0x56))  // Ctrl+V

            XCTAssertEqual(value, "a\nb")
            XCTAssertEqual(node.textInputCaretOffset, 3)
        }
    }
}
