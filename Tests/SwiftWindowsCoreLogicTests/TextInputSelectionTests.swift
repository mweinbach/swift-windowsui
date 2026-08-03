import Foundation

import SwiftWindowsCore

import XCTest

@testable import SwiftWindowsUI
@testable import WinSwiftUI

@MainActor
private final class FakeClipboard: TextInputClipboard {
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
private func makeFieldNode(
    text: Binding<String>,
    onInvalidate: @escaping () -> Void = {}
) -> ViewNode {
    let runtime = RetainedViewRuntime(root: ViewNode())
    let context = ViewBuildContext(
        canvasSizeProvider: { Size(width: 800, height: 600) },
        invalidateHandler: onInvalidate
    )
    return TextField("VALUE", text: text).makeComponent(context: context).makeNode(runtime: runtime)
}

private func shiftKey(_ key: KeyboardKey) -> KeyboardEvent {
    KeyboardEvent(keyCode: key.rawValue, modifiers: [.shift])
}

private func controlKey(_ keyCode: UInt32) -> KeyboardEvent {
    KeyboardEvent(keyCode: keyCode, modifiers: [.control])
}

final class TextInputSelectionTests: XCTestCase {
    func testShiftArrowsExtendUnboundSelectionAroundAnchor() async {
        await MainActor.run {
            var value = "hello"
            let node = makeFieldNode(
                text: Binding(get: { value }, set: { value = $0 })
            )

            XCTAssertEqual(node.textInputCaretOffset, 5)
            XCTAssertNil(node.textInputSelection)

            node.onKeyDown?(shiftKey(.leftArrow))
            node.onKeyDown?(shiftKey(.leftArrow))

            XCTAssertEqual(node.textInputCaretOffset, 3)
            XCTAssertEqual(
                node.textInputSelection,
                RetainedTextSelection(indices: .range(3..<5), affinity: .upstream)
            )

            node.onKeyDown?(shiftKey(.rightArrow))

            XCTAssertEqual(node.textInputCaretOffset, 4)
            XCTAssertEqual(
                node.textInputSelection,
                RetainedTextSelection(indices: .range(4..<5), affinity: .upstream)
            )
        }
    }

    func testShiftHomeAndEndExtendSelectionToTextEdges() async {
        await MainActor.run {
            var value = "hello"
            let node = makeFieldNode(
                text: Binding(get: { value }, set: { value = $0 })
            )

            node.onKeyDown?(shiftKey(.home))

            XCTAssertEqual(node.textInputCaretOffset, 0)
            XCTAssertEqual(
                node.textInputSelection,
                RetainedTextSelection(indices: .range(0..<5), affinity: .upstream)
            )

            // Extending back to the anchor collapses to an insertion point.
            node.onKeyDown?(shiftKey(.end))

            XCTAssertEqual(node.textInputCaretOffset, 5)
            XCTAssertNil(node.textInputSelection)
        }
    }

    func testSelectAllThenPlainArrowsCollapseSelection() async {
        await MainActor.run {
            var value = "hello"
            let node = makeFieldNode(
                text: Binding(get: { value }, set: { value = $0 })
            )

            node.onKeyDown?(controlKey(0x41))  // Ctrl+A

            XCTAssertEqual(node.textInputCaretOffset, 5)
            XCTAssertEqual(
                node.textInputSelection,
                RetainedTextSelection(indices: .range(0..<5), affinity: .downstream)
            )

            node.onKeyDown?(KeyboardEvent(keyCode: KeyboardKey.leftArrow.rawValue))

            XCTAssertEqual(node.textInputCaretOffset, 0)
            XCTAssertNil(node.textInputSelection)

            node.onKeyDown?(controlKey(0x41))
            node.onKeyDown?(KeyboardEvent(keyCode: KeyboardKey.rightArrow.rawValue))

            XCTAssertEqual(node.textInputCaretOffset, 5)
            XCTAssertNil(node.textInputSelection)
        }
    }

    func testBackspaceAndTypingReplaceUnboundSelection() async {
        await MainActor.run {
            var value = "abc"
            var invalidations = 0
            let node = makeFieldNode(
                text: Binding(get: { value }, set: { value = $0 }),
                onInvalidate: { invalidations += 1 }
            )

            node.onKeyDown?(controlKey(0x41))
            node.onKeyDown?(KeyboardEvent(keyCode: 0x5A))  // type "z" over selection

            XCTAssertEqual(value, "z")
            XCTAssertEqual(node.textInputCaretOffset, 1)
            XCTAssertNil(node.textInputSelection)

            node.onKeyDown?(controlKey(0x41))
            node.onKeyDown?(KeyboardEvent(keyCode: KeyboardKey.backspace.rawValue))

            XCTAssertEqual(value, "")
            XCTAssertEqual(node.textInputCaretOffset, 0)
            XCTAssertNil(node.textInputSelection)
            XCTAssertEqual(invalidations, 2)
        }
    }

    func testCopyCutPasteRoundTripThroughInjectedClipboard() async {
        await MainActor.run {
            let clipboard = FakeClipboard()
            TextInputClipboardProvider.current = clipboard

            var value = "hello world"
            var invalidations = 0
            let node = makeFieldNode(
                text: Binding(get: { value }, set: { value = $0 }),
                onInvalidate: { invalidations += 1 }
            )

            for _ in 0..<5 {
                node.onKeyDown?(shiftKey(.leftArrow))
            }
            XCTAssertEqual(
                node.textInputSelection,
                RetainedTextSelection(indices: .range(6..<11), affinity: .upstream)
            )

            node.onKeyDown?(controlKey(0x43))  // Ctrl+C

            XCTAssertEqual(clipboard.stored, "world")
            XCTAssertEqual(value, "hello world")
            XCTAssertEqual(invalidations, 0)

            node.onKeyDown?(controlKey(0x58))  // Ctrl+X

            XCTAssertEqual(clipboard.stored, "world")
            XCTAssertEqual(clipboard.copyCount, 2)
            XCTAssertEqual(value, "hello ")
            XCTAssertEqual(node.textInputCaretOffset, 6)
            XCTAssertNil(node.textInputSelection)
            XCTAssertEqual(invalidations, 1)

            node.onKeyDown?(controlKey(0x56))  // Ctrl+V

            XCTAssertEqual(value, "hello world")
            XCTAssertEqual(node.textInputCaretOffset, 11)
            XCTAssertEqual(invalidations, 2)
        }
    }

    func testSingleLinePasteStripsNewlinesAndReplacesSelection() async {
        await MainActor.run {
            let clipboard = FakeClipboard()
            clipboard.stored = "q\nz"
            TextInputClipboardProvider.current = clipboard

            var value = "ab"
            let node = makeFieldNode(
                text: Binding(get: { value }, set: { value = $0 })
            )

            node.onKeyDown?(controlKey(0x41))
            node.onKeyDown?(controlKey(0x56))

            XCTAssertEqual(value, "q")
            XCTAssertEqual(node.textInputCaretOffset, 1)
        }
    }

    func testTextEditorPastePreservesNewlines() async {
        await MainActor.run {
            let clipboard = FakeClipboard()
            clipboard.stored = "a\r\nb"
            TextInputClipboardProvider.current = clipboard

            var value = ""
            let runtime = RetainedViewRuntime(root: ViewNode())
            let context = ViewBuildContext(
                canvasSizeProvider: { Size(width: 800, height: 600) },
                invalidateHandler: {}
            )
            let node = TextEditor(text: Binding(get: { value }, set: { value = $0 }))
                .makeComponent(context: context)
                .makeNode(runtime: runtime)

            node.onKeyDown?(controlKey(0x56))

            XCTAssertEqual(value, "a\nb")
            XCTAssertEqual(node.textInputCaretOffset, 3)
        }
    }

    func testSecureFieldMasksContentAndDisablesCopyAndCut() async {
        await MainActor.run {
            let clipboard = FakeClipboard()
            TextInputClipboardProvider.current = clipboard

            var value = "secret"
            let runtime = RetainedViewRuntime(root: ViewNode())
            let context = ViewBuildContext(
                canvasSizeProvider: { Size(width: 800, height: 600) },
                invalidateHandler: {}
            )
            let node = SecureField("PASSWORD", text: Binding(get: { value }, set: { value = $0 }))
                .makeComponent(context: context)
                .makeNode(runtime: runtime)

            XCTAssertEqual(node.children[0].text, "••••••")

            node.onKeyDown?(controlKey(0x41))
            XCTAssertEqual(
                node.textInputSelection,
                RetainedTextSelection(indices: .range(0..<6), affinity: .downstream)
            )

            node.onKeyDown?(controlKey(0x43))  // copy is disabled
            node.onKeyDown?(controlKey(0x58))  // cut is disabled

            XCTAssertEqual(clipboard.copyCount, 0)
            XCTAssertNil(clipboard.stored)
            XCTAssertEqual(value, "secret")

            // Paste remains allowed and replaces the selection.
            clipboard.stored = "9"
            node.onKeyDown?(controlKey(0x56))

            XCTAssertEqual(value, "9")
            XCTAssertEqual(node.textInputCaretOffset, 1)
        }
    }

    func testShiftExtensionAndSelectAllWriteSelectionBinding() async {
        await MainActor.run {
            var value = "abcd"
            var selection: TextSelection? = TextSelection(
                insertionPoint: value.index(value.startIndex, offsetBy: 2)
            )
            let runtime = RetainedViewRuntime(root: ViewNode())
            let context = ViewBuildContext(
                canvasSizeProvider: { Size(width: 800, height: 600) },
                invalidateHandler: {}
            )
            let node = TextField(
                "VALUE",
                text: Binding(get: { value }, set: { value = $0 }),
                selection: Binding<TextSelection?>(get: { selection }, set: { selection = $0 })
            )
            .makeComponent(context: context)
            .makeNode(runtime: runtime)

            node.onKeyDown?(shiftKey(.rightArrow))

            XCTAssertEqual(node.textInputCaretOffset, 3)
            XCTAssertEqual(
                node.textInputSelection,
                RetainedTextSelection(indices: .range(2..<3), affinity: .downstream)
            )
            guard case .selection(let extendedRange) = selection?.indices else {
                XCTFail("Expected range selection in binding")
                return
            }
            XCTAssertEqual(value.distance(from: value.startIndex, to: extendedRange.lowerBound), 2)
            XCTAssertEqual(value.distance(from: value.startIndex, to: extendedRange.upperBound), 3)
            XCTAssertEqual(selection?.affinity, .downstream)

            node.onKeyDown?(shiftKey(.leftArrow))

            XCTAssertEqual(node.textInputCaretOffset, 2)
            XCTAssertTrue(selection?.isInsertion ?? false)

            node.onKeyDown?(controlKey(0x41))

            guard case .selection(let selectAllRange) = selection?.indices else {
                XCTFail("Expected select-all range in binding")
                return
            }
            XCTAssertEqual(value.distance(from: value.startIndex, to: selectAllRange.lowerBound), 0)
            XCTAssertEqual(value.distance(from: value.startIndex, to: selectAllRange.upperBound), 4)
        }
    }

    func testFocusedLayoutPaintsCaretAndSelectionHighlight() async {
        await MainActor.run {
            var value = "abc"
            let node = makeFieldNode(
                text: Binding(get: { value }, set: { value = $0 })
            )

            XCTAssertEqual(node.children.count, 1)
            XCTAssertFalse(node.children[0].isHidden)

            // Unfocused layout keeps the plain label child only.
            node.onLayout?(Rect(x: 0, y: 0, width: 200, height: 30))
            XCTAssertEqual(node.children.count, 1)

            // Focus paints a caret segment alongside the text.
            node.isFocused = true
            node.onFocusEnter?()

            XCTAssertEqual(node.children.count, 2)
            XCTAssertTrue(node.children[0].isHidden)
            let caretRow = node.children[1]
            let caretNode = caretRow.children.first { $0.preferredSize?.width == 1.5 }
            XCTAssertNotNil(caretNode)
            XCTAssertNotNil(caretNode?.backgroundColor)

            // Select-all paints a tinted highlight segment over the text.
            node.onKeyDown?(controlKey(0x41))

            XCTAssertEqual(node.children.count, 2)
            let highlightRow = node.children[1]
            let highlightNode = highlightRow.children.first { $0.backgroundColor != nil && $0.text == "abc" }
            XCTAssertNotNil(highlightNode)

            // Collapsing the selection and dropping focus restores the plain label.
            node.isFocused = false
            node.onKeyDown?(KeyboardEvent(keyCode: KeyboardKey.leftArrow.rawValue))

            XCTAssertNil(node.textInputSelection)
            XCTAssertEqual(node.children.count, 1)
            XCTAssertFalse(node.children[0].isHidden)
        }
    }

    func testMultilineChromeBuildsPerLineHighlightRows() async {
        await MainActor.run {
            var value = "ab\ncd"
            let runtime = RetainedViewRuntime(root: ViewNode())
            let context = ViewBuildContext(
                canvasSizeProvider: { Size(width: 800, height: 600) },
                invalidateHandler: {}
            )
            let node = TextEditor(text: Binding(get: { value }, set: { value = $0 }))
                .makeComponent(context: context)
                .makeNode(runtime: runtime)

            node.onKeyDown?(controlKey(0x41))

            XCTAssertEqual(node.children.count, 2)
            let container = node.children[1]
            XCTAssertEqual(container.children.count, 2)
            for row in container.children {
                XCTAssertTrue(row.children.contains { $0.backgroundColor != nil })
            }
        }
    }
}
