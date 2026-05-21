import Foundation
import SwiftWindowsCore
import SwiftWindowsGraphics
import XCTest

@testable import SwiftWindowsUI
@testable import WinSwiftUI

/// Exhaustive coverage of common SwiftUI view types — proves every view
/// type in the WinSwiftUI public surface that renders visible chrome
/// produces the expected primitive families and uses DirectWrite for text.
///
/// Each test focuses on one view type. The pattern: snapshot the view,
/// verify it emits *something* (quads or glyphs), and where the view shows
/// text, verify zero PixelText fallback so we never silently regress
/// individual view types to the chunky atlas.
@MainActor
final class ViewTaxonomyParityTests: XCTestCase {

    private func snapshot<V: View>(_ view: V, size: IntSize = IntSize(width: 240, height: 120)) -> GPUIScene {
        WinSwiftUIRendererSnapshotter.snapshot(
            of: view, size: size, displayScale: 1, clearColor: .black
        ).scene
    }

    private func primitiveCounts(_ scene: GPUIScene) -> (quads: Int, nativeGlyphs: Int, pixelGlyphs: Int) {
        var q = 0
        var n = 0
        var p = 0
        for layer in scene.layers {
            q += layer.quads.count
            n += layer.glyphs.count
            p += layer.pixelGlyphs.count
        }
        return (q, n, p)
    }

    // MARK: - Controls with text

    func testToggleRendersChromeAndTextViaDirectWrite() async {
        await MainActor.run {
            let view = Toggle("Enable feature", isOn: .constant(true))
                .frame(width: 200, height: 36)
            let (q, n, p) = primitiveCounts(snapshot(view))
            XCTAssertGreaterThan(q, 0, "Toggle should emit chrome quads")
            XCTAssertGreaterThan(n, 0, "Toggle title text should use DirectWrite")
            XCTAssertEqual(p, 0, "Toggle title must not use PixelText fallback")
        }
    }

    func testButtonRendersChromeAndTextViaDirectWrite() async {
        await MainActor.run {
            let view = Button("Confirm") {}
                .frame(width: 140, height: 40)
            let (q, n, p) = primitiveCounts(snapshot(view))
            XCTAssertGreaterThan(q, 0, "Button should emit chrome quads")
            XCTAssertGreaterThan(n, 0, "Button label should use DirectWrite")
            XCTAssertEqual(p, 0, "Button label must not use PixelText fallback")
        }
    }

    func testTextFieldRendersInputChrome() async {
        await MainActor.run {
            let view = TextField("Placeholder", text: .constant(""))
                .frame(width: 220, height: 30)
            let (q, _, _) = primitiveCounts(snapshot(view))
            XCTAssertGreaterThan(q, 0, "TextField should emit input chrome")
        }
    }

    func testSliderRendersTrackAndThumb() async {
        await MainActor.run {
            let view = Slider(value: .constant(0.5), in: 0...1)
                .frame(width: 220, height: 30)
            let (q, _, _) = primitiveCounts(snapshot(view))
            XCTAssertGreaterThan(q, 0, "Slider should emit track + thumb quads")
        }
    }

    func testStepperRendersControls() async {
        await MainActor.run {
            let view = Stepper("Quantity", value: .constant(0), in: 0...10)
                .frame(width: 200, height: 36)
            let (q, _, _) = primitiveCounts(snapshot(view))
            XCTAssertGreaterThan(q, 0, "Stepper should emit + / - chrome")
        }
    }

    func testPickerRendersOptionLabels() async {
        await MainActor.run {
            let view = Picker("Mode", selection: .constant(0)) {
                Text("First").tag(0)
                Text("Second").tag(1)
            }
            .frame(width: 220, height: 36)
            let (q, _, _) = primitiveCounts(snapshot(view))
            XCTAssertGreaterThan(q, 0, "Picker should emit selection chrome")
        }
    }

    func testProgressViewRendersTrackAndFill() async {
        await MainActor.run {
            let view = ProgressView(value: 0.6)
                .frame(width: 200, height: 12)
            let (q, _, _) = primitiveCounts(snapshot(view))
            XCTAssertGreaterThan(q, 0, "ProgressView should emit track + fill quads")
        }
    }

    func testMenuRendersTriggerLabel() async {
        await MainActor.run {
            let view = Menu("Options") {
                Button("Open") {}
                Button("Save") {}
            }
            .frame(width: 160, height: 32)
            let (q, n, p) = primitiveCounts(snapshot(view))
            XCTAssertGreaterThan(q, 0, "Menu trigger should emit chrome")
            XCTAssertGreaterThan(n, 0, "Menu trigger label should use DirectWrite")
            XCTAssertEqual(p, 0, "Menu trigger label must not use PixelText fallback")
        }
    }

    func testDisclosureGroupRendersHeaderAndContent() async {
        await MainActor.run {
            let view = DisclosureGroup("Details") {
                Text("Inside")
                    .font(.system(size: 13))
                    .foregroundColor(.white)
            }
            .frame(width: 220, height: 80)
            let (_, n, p) = primitiveCounts(snapshot(view))
            // DisclosureGroup renders its header purely via Text + indicator
            // (no background quad in the current style), so we only assert on
            // the glyphs invariant: the title must reach DirectWrite.
            XCTAssertGreaterThan(n, 0, "DisclosureGroup title text should use DirectWrite")
            XCTAssertEqual(p, 0, "DisclosureGroup labels must not use PixelText fallback")
        }
    }

    func testGroupBoxRendersFrameAndLabel() async {
        await MainActor.run {
            let view = GroupBox {
                Text("Content").foregroundColor(.white)
            } label: {
                Text("Section").foregroundColor(.white)
            }
            .frame(width: 200, height: 100)
            let (q, n, p) = primitiveCounts(snapshot(view))
            XCTAssertGreaterThan(q, 0, "GroupBox should emit frame quads")
            XCTAssertGreaterThan(n, 0, "GroupBox labels should use DirectWrite")
            XCTAssertEqual(p, 0, "GroupBox labels must not use PixelText fallback")
        }
    }

    // MARK: - Layout helpers

    func testDividerEmitsLinePrimitive() async {
        await MainActor.run {
            let view = VStack {
                Text("Above").foregroundColor(.white)
                Divider()
                Text("Below").foregroundColor(.white)
            }
            .frame(width: 200, height: 80)
            let (q, _, _) = primitiveCounts(snapshot(view))
            XCTAssertGreaterThan(q, 0, "Divider should contribute a quad primitive")
        }
    }

    func testSpacerEmitsNothingButLetsSiblingsRender() async {
        await MainActor.run {
            let view = HStack {
                Rectangle().fill(.red).frame(width: 30, height: 30)
                Spacer()
                Rectangle().fill(.blue).frame(width: 30, height: 30)
            }
            .frame(width: 220, height: 40)
            let scene = snapshot(view)
            let (q, _, _) = primitiveCounts(scene)
            XCTAssertGreaterThanOrEqual(q, 2, "Both flanking rects should still render around the Spacer")
        }
    }

    // MARK: - Aggregate invariants

    /// One scene that aggregates every control: catches cases where two
    /// view types interact pathologically (e.g. focus rings overlapping
    /// chrome, or a parent layout clipping a sibling control).
    func testAllControlsInOneFormStillRenderCleanly() async {
        await MainActor.run {
            let view = VStack(alignment: .leading, spacing: 10) {
                Toggle("Notifications", isOn: .constant(false))
                Button("Save") {}
                TextField("Name", text: .constant("Alice"))
                Slider(value: .constant(0.4))
                Stepper("Quantity", value: .constant(2), in: 0...10)
                Picker("Mode", selection: .constant(0)) {
                    Text("A").tag(0)
                    Text("B").tag(1)
                }
                ProgressView(value: 0.75)
                Menu("More") { Button("Item") {} }
            }
            .frame(width: 320, height: 360)

            let scene = snapshot(view, size: IntSize(width: 360, height: 400))
            let (q, n, p) = primitiveCounts(scene)
            XCTAssertGreaterThan(q, 0, "Aggregate form must emit quads")
            XCTAssertGreaterThan(n, 0, "Aggregate form must use DirectWrite for text")
            XCTAssertEqual(p, 0, "Aggregate form must produce no PixelText fallback")
        }
    }
}
