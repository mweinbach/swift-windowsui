import Foundation
import SwiftWindowsCore
import XCTest

@testable import SwiftWindowsUI
@testable import WinSwiftUI

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

final class WinSwiftUIPickerTests: XCTestCase {
    func testPhotosPickerRendersAsButtonWithDefaultLabel() async {
        await MainActor.run {
            let picker = PhotosPicker()
            let node = makeNode(picker)
            XCTAssertFalse(node.children.isEmpty)
            XCTAssertTrue(allTexts(in: node).contains("Photos"))
        }
    }

    func testPhotosPickerSingleSelectionInitRendersButton() async {
        await MainActor.run {
            var selected: PhotosPickerItem? = nil
            let binding = Binding<PhotosPickerItem?>(
                get: { selected },
                set: { selected = $0 }
            )
            let picker = PhotosPicker(selection: binding)
            let node = makeNode(picker)
            XCTAssertFalse(node.children.isEmpty)
            XCTAssertTrue(allTexts(in: node).contains("Photos"))
        }
    }

    func testPhotosPickerMultipleSelectionsInitRendersButton() async {
        await MainActor.run {
            var selected: [PhotosPickerItem] = []
            let binding = Binding<[PhotosPickerItem]>(
                get: { selected },
                set: { selected = $0 }
            )
            let picker = PhotosPicker(selections: binding)
            let node = makeNode(picker)
            XCTAssertFalse(node.children.isEmpty)
            XCTAssertTrue(allTexts(in: node).contains("Photos"))
        }
    }

    func testPhotosPickerItemStoresFileURL() async {
        await MainActor.run {
            let url = URL(fileURLWithPath: "C:\\test.jpg")
            let item = PhotosPickerItem(fileURL: url)
            XCTAssertEqual(item.fileURL, url)
        }
    }

    func testImagePickerRendersAsButtonWithDefaultLabel() async {
        await MainActor.run {
            let picker = ImagePicker()
            let node = makeNode(picker)
            XCTAssertFalse(node.children.isEmpty)
            XCTAssertTrue(allTexts(in: node).contains("Choose Photo"))
        }
    }

    func testImagePickerSelectionInitRendersButton() async {
        await MainActor.run {
            var selected: URL? = nil
            let binding = Binding<URL?>(
                get: { selected },
                set: { selected = $0 }
            )
            let picker = ImagePicker(selection: binding)
            let node = makeNode(picker)
            XCTAssertFalse(node.children.isEmpty)
            XCTAssertTrue(allTexts(in: node).contains("Choose Photo"))
        }
    }
}
