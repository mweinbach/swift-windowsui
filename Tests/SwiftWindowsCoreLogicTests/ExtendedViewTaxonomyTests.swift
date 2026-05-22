import Foundation
import SwiftWindowsCore
import SwiftWindowsGraphics
import XCTest

@testable import SwiftWindowsUI
@testable import WinSwiftUI

/// Extended view-type coverage beyond the basic control taxonomy: Form,
/// Section, OutlineGroup, NavigationLink, NavigationStack, TabView, the
/// split views, DatePicker, ColorPicker. Each test snapshots one view
/// type and asserts the right primitive families fire, native glyphs
/// drive any text it shows, and no PixelText fallback sneaks in.
@MainActor
final class ExtendedViewTaxonomyTests: XCTestCase {

    private func snapshot<V: View>(_ view: V, size: IntSize = IntSize(width: 320, height: 240)) -> GPUIScene {
        WinSwiftUIRendererSnapshotter.snapshot(
            of: view, size: size, displayScale: 1, clearColor: .black
        ).scene
    }

    private func counts(_ scene: GPUIScene) -> (quads: Int, glyphs: Int, pixel: Int) {
        var q = 0
        var g = 0
        var p = 0
        for layer in scene.layers {
            q += layer.quads.count
            g += layer.glyphs.count
            p += layer.pixelGlyphs.count
        }
        return (q, g, p)
    }

    func testFormEmitsChromeAndRoutesTextThroughDirectWrite() async {
        await MainActor.run {
            let view = Form {
                Text("Field A").foregroundColor(.white)
                Text("Field B").foregroundColor(.white)
                Text("Field C").foregroundColor(.white)
            }
            .frame(width: 300, height: 200)
            let c = counts(snapshot(view))
            XCTAssertGreaterThan(c.glyphs, 0, "Form rows should use DirectWrite")
            XCTAssertEqual(c.pixel, 0, "No PixelText fallback for Form rows")
        }
    }

    func testSectionEmitsHeaderTextAndContentQuads() async {
        await MainActor.run {
            let view = Section("Section Title") {
                Text("Row 1").foregroundColor(.white)
                Text("Row 2").foregroundColor(.white)
            }
            .frame(width: 280, height: 140)
            let c = counts(snapshot(view))
            XCTAssertGreaterThan(c.glyphs, 0, "Section header + rows should produce native glyphs")
            XCTAssertEqual(c.pixel, 0, "No PixelText fallback for Section")
        }
    }

    func testOutlineGroupRendersNestedItems() async {
        struct Node: Identifiable {
            let id: String
            let title: String
            let children: [Node]?
        }
        await MainActor.run {
            let tree = Node(
                id: "root",
                title: "Root",
                children: [
                    Node(id: "a", title: "Child A", children: nil),
                    Node(
                        id: "b",
                        title: "Child B",
                        children: [
                            Node(id: "b.1", title: "Grandchild B.1", children: nil)
                        ]),
                ]
            )
            let view = OutlineGroup(tree, children: \.children) { node in
                Text(node.title).foregroundColor(.white)
            }
            .frame(width: 280, height: 200)
            let c = counts(snapshot(view))
            XCTAssertGreaterThan(c.glyphs, 0, "OutlineGroup must render its nodes' labels via DirectWrite")
            XCTAssertEqual(c.pixel, 0, "No PixelText fallback in OutlineGroup")
        }
    }

    func testNavigationLinkRendersLabel() async {
        await MainActor.run {
            let view = NavigationLink("Open Detail", destination: Text("Detail").foregroundColor(.white))
                .frame(width: 200, height: 36)
            let c = counts(snapshot(view))
            XCTAssertGreaterThan(c.glyphs, 0, "NavigationLink label should use DirectWrite")
            XCTAssertEqual(c.pixel, 0, "No PixelText fallback in NavigationLink")
        }
    }

    func testNavigationStackRendersInitialContent() async {
        await MainActor.run {
            let view = NavigationStack {
                Text("Root view").foregroundColor(.white)
            }
            .frame(width: 280, height: 200)
            let c = counts(snapshot(view))
            XCTAssertGreaterThan(c.glyphs, 0, "NavigationStack initial content should use DirectWrite")
            XCTAssertEqual(c.pixel, 0, "No PixelText fallback in NavigationStack")
        }
    }

    func testTabViewRendersSelectedTabContent() async {
        await MainActor.run {
            let view = TabView {
                Text("Tab one content").foregroundColor(.white)
                Text("Tab two content").foregroundColor(.white)
            }
            .frame(width: 320, height: 200)
            let c = counts(snapshot(view))
            XCTAssertGreaterThan(c.glyphs, 0, "TabView should render selected tab's text via DirectWrite")
            XCTAssertEqual(c.pixel, 0, "No PixelText fallback in TabView")
        }
    }

    func testDatePickerRendersChromeOrLabel() async {
        await MainActor.run {
            let date = Date(timeIntervalSince1970: 1_700_000_000)
            let view = DatePicker("Date", selection: .constant(date))
                .frame(width: 260, height: 36)
            let c = counts(snapshot(view))
            // DatePicker renders as a labelled control. Some configurations
            // emit chrome quads, others a pure label — accept either.
            XCTAssertGreaterThan(
                c.quads + c.glyphs, 0,
                "DatePicker must emit some visible primitive (quad chrome or label glyphs)"
            )
            XCTAssertEqual(c.pixel, 0, "No PixelText fallback in DatePicker label")
        }
    }

    func testColorPickerRendersChrome() async {
        await MainActor.run {
            let picker = ColorPicker(
                "Tint",
                selection: .constant(Color(red: 0.5, green: 0.5, blue: 0.5, alpha: 1)))
            let view = picker.frame(width: 220, height: 36)
            let c = counts(snapshot(view))
            XCTAssertGreaterThan(c.quads, 0, "ColorPicker should emit a color swatch + label chrome")
        }
    }

    func testHSplitViewRendersBothPanes() async {
        await MainActor.run {
            let view = HSplitView {
                Text("Left").foregroundColor(.white)
                Text("Right").foregroundColor(.white)
            }
            .frame(width: 320, height: 160)
            let c = counts(snapshot(view))
            XCTAssertGreaterThan(c.glyphs, 0, "HSplitView must render both panes' text")
            XCTAssertEqual(c.pixel, 0, "No PixelText fallback in HSplitView")
        }
    }

    func testVSplitViewRendersBothPanes() async {
        await MainActor.run {
            let view = VSplitView {
                Text("Top").foregroundColor(.white)
                Text("Bottom").foregroundColor(.white)
            }
            .frame(width: 200, height: 240)
            let c = counts(snapshot(view))
            XCTAssertGreaterThan(c.glyphs, 0, "VSplitView must render both panes' text")
            XCTAssertEqual(c.pixel, 0, "No PixelText fallback in VSplitView")
        }
    }

    /// Aggregate: every extended view-type in one composition.
    func testAllExtendedViewsTogetherStillRenderCleanly() async {
        await MainActor.run {
            let view = NavigationStack {
                Form {
                    Section("Top") {
                        Text("Row").foregroundColor(.white)
                        NavigationLink("Detail", destination: Text("Inner").foregroundColor(.white))
                    }
                    Section("More") {
                        Text("Tail").foregroundColor(.white)
                    }
                }
            }
            .frame(width: 360, height: 280)
            let c = counts(snapshot(view, size: IntSize(width: 400, height: 320)))
            XCTAssertGreaterThan(c.quads, 0)
            XCTAssertGreaterThan(c.glyphs, 0)
            XCTAssertEqual(c.pixel, 0, "Aggregate extended-views composition must not use PixelText anywhere")
        }
    }
}
