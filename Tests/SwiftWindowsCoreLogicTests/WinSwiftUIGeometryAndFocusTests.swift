import Foundation
import SwiftWindowsCore
import XCTest

@testable import SwiftWindowsUI
@testable import WinSwiftUI

final class WinSwiftUIGeometryAndFocusTests: XCTestCase {
    func testTimelineViewRendersContentWithCurrentDate() async {
        await MainActor.run {
            let node = makeNode(
                TimelineView(.everyMinute) { context in
                    Text("DATE: \(context.date.timeIntervalSince1970)")
                }
            )
            XCTAssertTrue(allTexts(in: node).contains(where: { $0.hasPrefix("DATE: ") }))
        }
    }

    func testAnimationTimelineViewRendersContentWithAnimationSchedule() async {
        await MainActor.run {
            let node = makeNode(
                AnimationTimelineView(.animation) { context in
                    Text("ANIMATED: \(context.cadence == .live ? "LIVE" : "OTHER")")
                }
            )
            XCTAssertTrue(allTexts(in: node).contains("ANIMATED: LIVE"))
        }
    }

    func testGeometryGroupMapsToRetainedNodeFlag() async {
        await MainActor.run {
            let node = makeNode(
                Text("GROUPED")
                    .geometryGroup()
            )
            XCTAssertTrue(node.isGeometryGroup)
        }
    }

    func testInspectorColumnWidthMapsToRetainedNodeProperty() async {
        await MainActor.run {
            let node = makeNode(
                Text("INSPECTOR")
                    .inspectorColumnWidth(240)
            )
            XCTAssertEqual(node.inspectorColumnWidth, 240)
        }
    }

    func testInspectorColumnWidthFractionMapsToRetainedNodeProperty() async {
        await MainActor.run {
            let node = makeNode(
                Text("INSPECTOR")
                    .inspectorColumnWidthFraction(0.3)
            )
            XCTAssertEqual(node.inspectorColumnWidthFraction, 0.3)
        }
    }

    func testInspectorColumnWidthMinMapsToRetainedNodeProperty() async {
        await MainActor.run {
            let node = makeNode(
                Text("INSPECTOR")
                    .inspectorColumnWidthMin(120)
            )
            XCTAssertEqual(node.inspectorColumnWidthMin, 120)
        }
    }

    func testFocusSectionMapsToRetainedNodeFlag() async {
        await MainActor.run {
            let node = makeNode(
                Text("SECTION")
                    .focusSection()
            )
            XCTAssertTrue(node.isFocusSection)
        }
    }

    func testFocusScopeMapsToRetainedNodeFlagAndNamespace() async {
        await MainActor.run {
            let ns = Namespace().wrappedValue
            let node = makeNode(
                Text("SCOPE")
                    .focusScope(ns)
            )
            XCTAssertTrue(node.isFocusSection)
            XCTAssertEqual(node.focusNamespace, ns)
        }
    }

    func testFocusDestinationMapsToRetainedNodeFlag() async {
        await MainActor.run {
            let node = makeNode(
                Text("DESTINATION")
                    .focusDestination()
            )
            XCTAssertTrue(node.isFocusDestination)
        }
    }

    func testPrefersDefaultFocusMapsToRetainedNodeProperties() async {
        await MainActor.run {
            let ns = Namespace().wrappedValue
            let node = makeNode(
                Text("PREFERS")
                    .prefersDefaultFocus(true, in: ns)
            )
            XCTAssertTrue(node.prefersDefaultFocus)
            XCTAssertEqual(node.focusNamespace, ns)
        }
    }

    func testDefaultFocusMapsToRetainedNodeProperties() async {
        await MainActor.run {
            let ns = Namespace().wrappedValue
            let focusState = FocusState<Bool>(wrappedValue: true)
            let node = makeNode(
                Text("DEFAULT")
                    .defaultFocus(focusState.projectedValue, in: ns)
            )
            XCTAssertTrue(node.isFocusable)
            XCTAssertTrue(node.isHitTestVisible)
            XCTAssertEqual(node.focusNamespace, ns)
        }
    }

    func testFileDialogCustomizationIDMapsToRetainedNodeProperty() async {
        await MainActor.run {
            let node = makeNode(
                Text("DIALOG")
                    .fileDialogCustomizationID("com.example.export")
            )
            XCTAssertEqual(node.fileDialogCustomizationID, "com.example.export")
        }
    }

    func testFileDialogConfirmationLabelMapsToRetainedNodeProperty() async {
        await MainActor.run {
            let node = makeNode(
                Text("DIALOG")
                    .fileDialogConfirmationLabel(Text("Confirm Save"))
            )
            XCTAssertEqual(node.fileDialogConfirmationLabel, "Confirm Save")
        }
    }

    func testFileDialogDefaultDirectoryMapsToRetainedNodeProperty() async {
        await MainActor.run {
            let url = URL(fileURLWithPath: "C:\\Users\\Documents")
            let node = makeNode(
                Text("DIALOG")
                    .fileDialogDefaultDirectory(url)
            )
            XCTAssertEqual(node.fileDialogDefaultDirectory, url)
        }
    }

    func testFileDialogMessageMapsToRetainedNodeProperty() async {
        await MainActor.run {
            let node = makeNode(
                Text("DIALOG")
                    .fileDialogMessage(Text("Select a file to import"))
            )
            XCTAssertEqual(node.fileDialogMessage, "Select a file to import")
        }
    }

    func testOnOpenURLProvidesHandledActionInEnvironment() async {
        await MainActor.run {
            var receivedURL: URL?
            struct OpenURLReaderView: View {
                @Environment(\.openURL) var openURL
                var body: some View {
                    Button("OPEN") {
                        openURL(URL(string: "https://example.com")!)
                    }
                }
            }

            let node = makeNode(
                OpenURLReaderView()
                    .onOpenURL { url in
                        receivedURL = url
                    }
            )
            node.onActivate?()
            XCTAssertEqual(receivedURL, URL(string: "https://example.com")!)
        }
    }

    func testTouchBarModifierDoesNotBreakViewRendering() async {
        await MainActor.run {
            let node = makeNode(
                Text("TOUCH")
                    .touchBar {
                        Button("TB") {}
                    }
            )
            XCTAssertEqual(node.text, "TOUCH")
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

@MainActor
private func allTexts(in node: ViewNode) -> [String] {
    var texts: [String] = []
    if let text = node.text {
        texts.append(text)
    }
    for child in node.children {
        texts.append(contentsOf: allTexts(in: child))
    }
    return texts
}
