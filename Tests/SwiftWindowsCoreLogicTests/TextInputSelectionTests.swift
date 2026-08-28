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

            // Ctrl+arrows move between Character-based word boundaries;
            // emoji remain one grapheme, underscores stay in their word,
            // and punctuation is a boundary of its own.
            var unicodeValue = "alpha  👩🏽‍💻 café_42,終"
            let unicodeNode = makeFieldNode(
                text: Binding(get: { unicodeValue }, set: { unicodeValue = $0 })
            )
            func offset(of token: String) -> Int {
                let index = unicodeValue.range(of: token)!.lowerBound
                return unicodeValue.distance(from: unicodeValue.startIndex, to: index)
            }

            let backwardStops = [
                offset(of: "終"),
                offset(of: ","),
                offset(of: "café_42"),
                offset(of: "👩🏽‍💻"),
                0,
                0,
            ]
            for expectedOffset in backwardStops {
                unicodeNode.onKeyDown?(controlKey(KeyboardKey.leftArrow.rawValue))
                XCTAssertEqual(unicodeNode.textInputCaretOffset, expectedOffset)
                XCTAssertNil(unicodeNode.textInputSelection)
            }

            let forwardStops = [
                offset(of: "👩🏽‍💻"),
                offset(of: "café_42"),
                offset(of: ","),
                offset(of: "終"),
                unicodeValue.count,
                unicodeValue.count,
            ]
            for expectedOffset in forwardStops {
                unicodeNode.onKeyDown?(controlKey(KeyboardKey.rightArrow.rawValue))
                XCTAssertEqual(unicodeNode.textInputCaretOffset, expectedOffset)
                XCTAssertNil(unicodeNode.textInputSelection)
            }

            // Real window routing must not let an overflowing horizontal
            // viewport consume a focused editor's Ctrl+word shortcut.
            var nestedValue = "one two"
            let horizontalRuntime = RetainedViewRuntime(root: ViewNode())
            let viewportSize = Size(width: 120, height: 32)
            let fieldContext = ViewBuildContext(
                canvasSizeProvider: { viewportSize },
                invalidateHandler: {}
            )
            let nestedField = TextField(
                "VALUE",
                text: Binding(get: { nestedValue }, set: { nestedValue = $0 })
            )
            .makeComponent(context: fieldContext)
            .makeNode(runtime: horizontalRuntime)
            nestedField.preferredSize = Size(width: 260, height: 28)
            let horizontalScroll = Controls.scrollPanel(
                axis: .horizontal,
                frame: Rect(origin: .zero, size: viewportSize),
                stackLayout: .horizontal(spacing: 0),
                children: [nestedField]
            )
            horizontalRuntime.root.addChild(horizontalScroll)
            horizontalRuntime.setRootSize(IntSize(width: 120, height: 32))
            _ = horizontalRuntime.renderScene(at: 1)
            horizontalRuntime.requestFocus(nestedField)

            horizontalRuntime.keyDown(controlKey(KeyboardKey.leftArrow.rawValue))
            XCTAssertEqual(nestedField.textInputCaretOffset, 4)
            XCTAssertEqual(horizontalScroll.scrollOffset, 0)

            horizontalRuntime.keyDown(KeyboardEvent(keyCode: KeyboardKey.rightArrow.rawValue))
            XCTAssertGreaterThan(horizontalScroll.scrollOffset, 0, "ordinary arrows keep horizontal scroll behavior")
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

            node.onKeyDown?(controlKey(KeyboardKey.leftArrow.rawValue))
            XCTAssertEqual(node.textInputCaretOffset, 2)

            node.onKeyDown?(controlKey(KeyboardKey.leftArrow.rawValue))
            XCTAssertEqual(node.textInputCaretOffset, 0, "word navigation crosses hard-line whitespace")

            node.onKeyDown?(controlKey(KeyboardKey.rightArrow.rawValue))
            XCTAssertEqual(node.textInputCaretOffset, 2)
            XCTAssertEqual(value, "a\nb", "word navigation must not edit multiline text")
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

            var unicodeValue = "go 👨‍👩‍👧‍👦 café"
            var unicodeSelection: TextSelection? = TextSelection(insertionPoint: unicodeValue.endIndex)
            let unicodeNode = TextField(
                "VALUE",
                text: Binding(get: { unicodeValue }, set: { unicodeValue = $0 }),
                selection: Binding<TextSelection?>(
                    get: { unicodeSelection },
                    set: { unicodeSelection = $0 }
                )
            )
            .makeComponent(context: context)
            .makeNode(runtime: runtime)
            let finalWordIndex = unicodeValue.range(of: "café")!.lowerBound
            let emojiIndex = unicodeValue.range(of: "👨‍👩‍👧‍👦")!.lowerBound
            let finalWordOffset = unicodeValue.distance(from: unicodeValue.startIndex, to: finalWordIndex)
            let emojiOffset = unicodeValue.distance(from: unicodeValue.startIndex, to: emojiIndex)
            let controlShiftLeft = KeyboardEvent(
                keyCode: KeyboardKey.leftArrow.rawValue,
                modifiers: [.control, .shift]
            )
            let controlShiftRight = KeyboardEvent(
                keyCode: KeyboardKey.rightArrow.rawValue,
                modifiers: [.control, .shift]
            )

            unicodeNode.onKeyDown?(controlShiftLeft)
            XCTAssertEqual(
                unicodeNode.textInputSelection,
                RetainedTextSelection(indices: .range(finalWordOffset..<unicodeValue.count), affinity: .upstream)
            )
            XCTAssertEqual(unicodeSelection?.affinity, .upstream)

            unicodeNode.onKeyDown?(controlShiftLeft)
            XCTAssertEqual(
                unicodeNode.textInputSelection,
                RetainedTextSelection(indices: .range(emojiOffset..<unicodeValue.count), affinity: .upstream)
            )
            guard case .selection(let wordRange) = unicodeSelection?.indices else {
                XCTFail("Expected Ctrl+Shift word selection to update the bound range")
                return
            }
            XCTAssertEqual(
                unicodeValue.distance(from: unicodeValue.startIndex, to: wordRange.lowerBound),
                emojiOffset
            )
            XCTAssertEqual(
                unicodeValue.distance(from: unicodeValue.startIndex, to: wordRange.upperBound),
                unicodeValue.count
            )

            unicodeNode.onKeyDown?(controlShiftRight)
            XCTAssertEqual(unicodeNode.textInputCaretOffset, finalWordOffset)

            unicodeNode.onKeyDown?(controlShiftRight)
            XCTAssertEqual(unicodeNode.textInputCaretOffset, unicodeValue.count)
            XCTAssertTrue(unicodeSelection?.isInsertion ?? false)
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

            XCTAssertEqual(node.children.count, 1)
            guard let viewport = node.children.first else {
                XCTFail("The multiline editor must retain its viewport")
                return
            }
            XCTAssertEqual(viewport.scrollAxis, .vertical)
            XCTAssertTrue(viewport.clipsToBounds)
            XCTAssertEqual(viewport.children.count, 1)
            guard let content = viewport.children.first else {
                XCTFail("The viewport must retain its text content")
                return
            }
            let fragments = content.children.filter { $0.text?.isEmpty == false }
            let highlights = content.children.filter { $0.text == nil && $0.backgroundColor != nil }
            XCTAssertEqual(fragments.map(\.text), ["ab", "cd"])
            XCTAssertEqual(highlights.count, 2)
            XCTAssertEqual(node.textInputSelection?.indices, .range(0..<5))
            for fragment in fragments {
                XCTAssertFalse(fragment.isHidden)
                XCTAssertNil(fragment.backgroundColor, "Selection must not split or reshape either line")
                let highlight = highlights.first { abs($0.frame.minY - fragment.frame.minY) < 0.001 }
                XCTAssertNotNil(highlight, "Each selected line must have its own background")
                guard let highlight else { continue }
                XCTAssertFalse(highlight.isHidden)
                XCTAssertEqual(highlight.frame.minX, fragment.frame.minX, accuracy: 0.001)
                XCTAssertGreaterThanOrEqual(highlight.frame.maxX + 0.001, fragment.frame.maxX)
                XCTAssertEqual(highlight.frame.height, fragment.frame.height, accuracy: 0.001)
                XCTAssertGreaterThan(highlight.frame.width, 0)
            }
            XCTAssertEqual(value, "ab\ncd", "Select-all must not alter the text binding")
        }
    }
}
