import Foundation
import SwiftWindowsCore
import XCTest

@testable import SwiftWindowsPlatform
@testable import SwiftWindowsUI
@testable import WinSwiftUI

/// The text caret blinks.
///
/// Before this there was no blink machinery anywhere in the stack — grepping
/// `blink` across Sources returned nothing. Measured: focus a `TextField`,
/// then tick at 0.1s intervals for two seconds; `tickAnimations` returned
/// false on every single tick, `hasActiveAnimations` was false throughout, and
/// the caret's alpha never moved off its build value. A steady caret is one of
/// the fastest tells that a text field is not a real system control.
@MainActor
final class CaretBlinkTests: XCTestCase {

    private func findNode(_ node: ViewNode, where predicate: (ViewNode) -> Bool) -> ViewNode? {
        if predicate(node) { return node }
        for child in node.children {
            if let found = findNode(child, where: predicate) { return found }
        }
        return nil
    }

    private struct FieldHarness {
        let runtime: RetainedViewRuntime
        let host: ComponentHost
        let caret: () -> ViewNode?
    }

    private func makeFocusedField() -> FieldHarness {
        let runtime = RetainedViewRuntime(root: ViewNode(frame: Rect(x: 0, y: 0, width: 400, height: 300)))
        let host = ComponentHost(runtime: runtime)
        var text = "Ada"
        let context = ViewBuildContext(
            canvasSizeProvider: { Size(width: 400, height: 300) },
            invalidateHandler: { [weak host] in host?.reload() }
        )
        host.setComponents {
            [
                VStack {
                    TextField("Name", text: Binding(get: { text }, set: { text = $0 }))
                }
                .frame(width: 400, height: 300)
                .makeComponent(context: context)
            ]
        }
        _ = runtime.renderFrame()
        runtime.keyDown(KeyboardEvent(keyCode: KeyboardKey.tab.rawValue))
        _ = runtime.renderFrame()
        return FieldHarness(
            runtime: runtime,
            host: host,
            caret: { self.findNode(runtime.root, where: { $0.isTextInputCaret }) }
        )
    }

    func testAFocusedFieldHasACaretThatTheRuntimeKnowsToBlink() async {
        let harness = makeFocusedField()
        XCTAssertNotNil(harness.caret(), "focusing the field puts an insertion indicator in the tree")
        XCTAssertTrue(
            harness.runtime.hasActiveAnimations,
            "the blink has no settled state, so it has to hold the animation gate open — "
                + "without it the host switches its timer off and the caret freezes mid-phase")
    }

    /// The phase itself, sampled across two full cycles: on, off, on again.
    func testTheCaretGoesOffAndComesBackOnTheDocumentedPhase() async {
        let harness = makeFocusedField()
        guard let caret = harness.caret() else { return XCTFail("no caret") }

        let start = Win32Window.currentTimestampSeconds()
        _ = harness.runtime.tickAnimations(at: start)
        XCTAssertEqual(caret.opacity, 1, accuracy: 0.001, "a fresh caret is on")

        func opacity(at offset: Double) -> Double {
            _ = harness.runtime.tickAnimations(at: start + offset)
            return caret.opacity
        }

        XCTAssertEqual(opacity(at: 0.2), 1, accuracy: 0.001, "on for the first half-second")
        XCTAssertEqual(opacity(at: 0.45), 0.5, accuracy: 0.05, "fading out at the edge, not stepping")
        XCTAssertEqual(opacity(at: 0.7), 0, accuracy: 0.001, "off for the second half-second")
        XCTAssertEqual(opacity(at: 0.95), 0.5, accuracy: 0.05, "and fading back in")
        XCTAssertEqual(opacity(at: 1.2), 1, accuracy: 0.001, "on again one period later")
    }

    /// Typing restarts the cycle at fully on — macOS does the same, because a
    /// caret that blinked out on the keystroke that moved it would be
    /// unreadable exactly when it matters.
    func testAKeystrokeResetsTheBlinkToFullyOn() async {
        let harness = makeFocusedField()
        guard let caret = harness.caret() else { return XCTFail("no caret") }

        let start = Win32Window.currentTimestampSeconds()
        _ = harness.runtime.tickAnimations(at: start)
        _ = harness.runtime.tickAnimations(at: start + 0.7)
        XCTAssertEqual(caret.opacity, 0, accuracy: 0.001, "mid-off phase")

        harness.runtime.keyDown(KeyboardEvent(keyCode: KeyboardKey.rightArrow.rawValue))
        XCTAssertEqual(caret.opacity, 1, accuracy: 0.001, "the keystroke brings it straight back")

        _ = harness.runtime.tickAnimations(at: start + 0.75)
        _ = harness.runtime.tickAnimations(at: start + 0.95)
        XCTAssertEqual(caret.opacity, 1, accuracy: 0.001, "and the new cycle starts from there")
    }

    /// An unfocused tree has no caret, so nothing holds the animation gate.
    func testAnUnfocusedFieldBlinksNothingAndParksTheDriver() async {
        let harness = makeFocusedField()
        XCTAssertNotNil(harness.caret())

        harness.runtime.pointerDown(at: Point(x: 395, y: 295))
        harness.runtime.pointerUp(at: Point(x: 395, y: 295))
        _ = harness.runtime.renderFrame()

        XCTAssertNil(harness.caret(), "an unfocused field shows no insertion indicator")
        var clock = Win32Window.currentTimestampSeconds()
        for _ in 0..<40 {
            clock += 1.0 / 60.0
            _ = harness.runtime.tickAnimations(at: clock)
        }
        XCTAssertFalse(harness.runtime.hasActiveAnimations, "and the driver goes back to sleep")
    }

    /// The phase function itself, independent of any tree.
    func testTheBlinkPhaseIsHalfOnHalfOffWithRamps() async {
        XCTAssertEqual(RetainedViewRuntime.caretBlinkOnDuration, 0.5, accuracy: 0.0001)
        XCTAssertEqual(RetainedViewRuntime.caretBlinkOffDuration, 0.5, accuracy: 0.0001)
        XCTAssertEqual(RetainedViewRuntime.caretBlinkFadeDuration, 0.1, accuracy: 0.0001)
        XCTAssertEqual(RetainedViewRuntime.caretBlinkOpacity(atElapsed: 0), 1, accuracy: 0.0001)
        XCTAssertEqual(RetainedViewRuntime.caretBlinkOpacity(atElapsed: 0.45), 0.5, accuracy: 0.0001)
        XCTAssertEqual(RetainedViewRuntime.caretBlinkOpacity(atElapsed: 0.5), 0, accuracy: 0.0001)
        XCTAssertEqual(RetainedViewRuntime.caretBlinkOpacity(atElapsed: 0.95), 0.5, accuracy: 0.0001)
        // And it repeats: a full period later everything is where it started.
        XCTAssertEqual(RetainedViewRuntime.caretBlinkOpacity(atElapsed: 1.45), 0.5, accuracy: 0.0001)
    }
}
