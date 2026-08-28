import SwiftWindowsCore
@preconcurrency import XCTest

@testable import SwiftWindowsUI
@testable import WinSwiftUI

private enum FrameSizingInputKind {
    case editor
    case verticalField
    case horizontalField
    case secureField
}

@MainActor
private func frameSizingInput(_ kind: FrameSizingInputKind) -> AnyView {
    switch kind {
    case .editor:
        return AnyView(TextEditor(text: .constant("Short text")).controlSize(.regular))
    case .verticalField:
        return AnyView(TextField("Notes", text: .constant("Short text"), axis: .vertical).controlSize(.regular))
    case .horizontalField:
        return AnyView(TextField("Value", text: .constant("Short text")).controlSize(.regular))
    case .secureField:
        return AnyView(SecureField("Password", text: .constant("Short text")).controlSize(.regular))
    }
}

@MainActor
private final class FrameSizingWidth {
    var value = 300.0
}

@MainActor
private final class EditorFrameSizingFixture {
    let runtime: RetainedViewRuntime
    let host: ComponentHost

    init(_ content: @escaping @MainActor () -> AnyView) {
        let runtime = RetainedViewRuntime(
            root: ViewNode(frame: Rect(x: 31, y: 47, width: 700, height: 480)))
        self.runtime = runtime
        let host = ComponentHost(runtime: runtime)
        self.host = host
        let context = ViewBuildContext(canvasSizeProvider: { Size(width: 700, height: 480) }, invalidateHandler: {})
        host.setComponents {
            [VStack(alignment: .leading, spacing: 0) { content() }.makeComponent(context: context)]
        }
    }

    func input() throws -> ViewNode {
        var pending = [runtime.root]
        while let node = pending.popLast() {
            if node.accessibilityTraits.contains(.isTextInput) { return node }
            pending.append(contentsOf: node.children)
        }
        return try XCTUnwrap(Optional<ViewNode>.none, "The public input must be mounted")
    }

    func viewport(of input: ViewNode) throws -> ViewNode {
        try XCTUnwrap(input.children.first { $0.scrollAxis == .vertical })
    }

    func frame(of node: ViewNode) throws -> Rect {
        try XCTUnwrap(runtime.resolvedLayoutFrame(of: node))
    }

    func wrapper(of input: ViewNode, size: Size) throws -> ViewNode {
        var ancestor = input.parent
        while let node = ancestor {
            if node.preferredSize == size, node.forwardsStackMainAxisProposal { return node }
            ancestor = node.parent
        }
        return try XCTUnwrap(Optional<ViewNode>.none, "The explicit public frame must be mounted")
    }
}

@MainActor
private func assertFrameSizingRect(
    _ actual: Rect, equals expected: Rect, file: StaticString = #filePath, line: UInt = #line
) {
    XCTAssertEqual(actual.minX, expected.minX, accuracy: 0.001, file: file, line: line)
    XCTAssertEqual(actual.minY, expected.minY, accuracy: 0.001, file: file, line: line)
    XCTAssertEqual(actual.width, expected.width, accuracy: 0.001, file: file, line: line)
    XCTAssertEqual(actual.height, expected.height, accuracy: 0.001, file: file, line: line)
}

@MainActor
private func assertFrameSizingViewport(
    _ fixture: EditorFrameSizingFixture, input: ViewNode, file: StaticString = #filePath, line: UInt = #line
) throws {
    let padding = try XCTUnwrap(input.layoutMode.stackLayout, file: file, line: line).padding
    let expected = try fixture.frame(of: input).inset(by: padding)
    let actual = try fixture.frame(of: fixture.viewport(of: input))
    assertFrameSizingRect(actual, equals: expected, file: file, line: line)
}

final class TextEditorFrameSizingTests: XCTestCase {
    func testMultilineInputsFillTheExplicitFrameInsideTheirDeclaredPadding() async throws {
        try await MainActor.run {
            let size = Size(width: 300, height: 140)
            for kind in [FrameSizingInputKind.editor, .verticalField] {
                let fixture = EditorFrameSizingFixture {
                    AnyView(frameSizingInput(kind).frame(width: size.width, height: size.height))
                }
                let input = try fixture.input()
                let wrapper = try fixture.wrapper(of: input, size: size)
                let wrapperFrame = try fixture.frame(of: wrapper)
                XCTAssertEqual(wrapperFrame.size, size)
                XCTAssertEqual(input.preferredSize, Size(width: 260, height: 120))
                assertFrameSizingRect(try fixture.frame(of: input), equals: wrapperFrame)
                try assertFrameSizingViewport(fixture, input: input)
            }
        }
    }

    func testEditorPreservesItsIdealSizeAndRespectsFrameAndFixedSizeAxes() async throws {
        try await MainActor.run {
            let ideal = Size(width: 260, height: 120)
            let cases: [(String, AnyView, Size)] = [
                ("unframed", frameSizingInput(.editor), ideal),
                ("width only", AnyView(frameSizingInput(.editor).frame(width: 300)), Size(width: 300, height: 120)),
                ("height only", AnyView(frameSizingInput(.editor).frame(height: 140)), Size(width: 260, height: 140)),
                ("fixed both", AnyView(frameSizingInput(.editor).fixedSize().frame(width: 300, height: 140)), ideal),
                (
                    "fixed horizontal",
                    AnyView(
                        frameSizingInput(.editor).fixedSize(horizontal: true, vertical: false)
                            .frame(width: 300, height: 140)),
                    Size(width: 260, height: 140)
                ),
                (
                    "fixed vertical",
                    AnyView(
                        frameSizingInput(.editor).fixedSize(horizontal: false, vertical: true)
                            .frame(width: 300, height: 140)),
                    Size(width: 300, height: 120)
                ),
            ]
            for (name, view, expected) in cases {
                let fixture = EditorFrameSizingFixture { view }
                let input = try fixture.input()
                XCTAssertEqual(input.preferredSize, ideal, name)
                XCTAssertEqual(try fixture.frame(of: input).size, expected, name)
                try assertFrameSizingViewport(fixture, input: input)
            }
        }
    }

    func testNarrowResizeKeepsTheInputAndViewportAtTheRequestedWrapWidth() async throws {
        try await MainActor.run {
            let width = FrameSizingWidth()
            let fixture = EditorFrameSizingFixture {
                AnyView(frameSizingInput(.editor).id("sized-editor").frame(width: width.value, height: 140))
            }
            let input = try fixture.input()
            let viewport = try fixture.viewport(of: input)
            let padding = try XCTUnwrap(input.layoutMode.stackLayout).padding
            XCTAssertEqual(try fixture.frame(of: input).size, Size(width: 300, height: 140))
            try assertFrameSizingViewport(fixture, input: input)

            // The viewport excludes the declared bezel padding; the editor
            // additionally reserves 1.5 points for its insertion indicator.
            width.value = 44 + 1.5 + padding.leading + padding.trailing
            fixture.host.reload()

            XCTAssertTrue(try fixture.input() === input)
            XCTAssertTrue(try fixture.viewport(of: input) === viewport)
            XCTAssertEqual(try fixture.frame(of: input).size, Size(width: width.value, height: 140))
            XCTAssertEqual(try fixture.frame(of: viewport).width - 1.5, 44, accuracy: 0.001)
            XCTAssertEqual(input.preferredSize, Size(width: 260, height: 120))
            try assertFrameSizingViewport(fixture, input: input)
        }
    }

    func testHorizontalAndSecureInputsKeepTheirUnframedSizeInsideALargerFrame() async throws {
        try await MainActor.run {
            for kind in [FrameSizingInputKind.horizontalField, .secureField] {
                let baseline = EditorFrameSizingFixture { frameSizingInput(kind) }
                let baselineInput = try baseline.input()
                let ideal = try XCTUnwrap(baselineInput.preferredSize)
                XCTAssertEqual(ideal.width, 220)
                XCTAssertEqual(try baseline.frame(of: baselineInput).size, ideal)

                let framed = EditorFrameSizingFixture {
                    AnyView(frameSizingInput(kind).frame(width: 300, height: 140))
                }
                let input = try framed.input()
                let wrapper = try framed.wrapper(of: input, size: Size(width: 300, height: 140))
                XCTAssertEqual(try framed.frame(of: wrapper).size, Size(width: 300, height: 140))
                XCTAssertEqual(input.preferredSize, ideal)
                XCTAssertEqual(try framed.frame(of: input).size, ideal)
                XCTAssertFalse(input.children.contains { $0.scrollAxis == .vertical })
            }
        }
    }
}
