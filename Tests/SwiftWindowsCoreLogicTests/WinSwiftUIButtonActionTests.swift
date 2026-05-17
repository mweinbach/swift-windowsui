import Foundation
import SwiftWindowsCore
import XCTest

@testable import SwiftWindowsPlatform
@testable import SwiftWindowsUI
@testable import WinSwiftUI

final class WinSwiftUIButtonActionTests: XCTestCase {
    func testImportButtonRendersAsButtonWithDefaultLabel() async {
        await MainActor.run {
            let button = ImportButton(supportedContentTypes: [UTType.plainText]) { _ in }
            let context = ViewBuildContext(
                canvasSizeProvider: { Size(width: 200, height: 400) },
                invalidateHandler: {}
            )
            let runtime = RetainedViewRuntime(root: ViewNode())
            let component = button.makeComponent(context: context)
            let node = component.makeNode(runtime: runtime)
            XCTAssertFalse(node.children.isEmpty)
            XCTAssertTrue(allTexts(in: node).contains("Import"))
        }
    }

    func testExportButtonRendersAsButtonWithDefaultLabel() async {
        await MainActor.run {
            let button = ExportButton(item: "test")
            let context = ViewBuildContext(
                canvasSizeProvider: { Size(width: 200, height: 400) },
                invalidateHandler: {}
            )
            let runtime = RetainedViewRuntime(root: ViewNode())
            let component = button.makeComponent(context: context)
            let node = component.makeNode(runtime: runtime)
            XCTAssertFalse(node.children.isEmpty)
            XCTAssertTrue(allTexts(in: node).contains("Export"))
        }
    }

    func testDeleteButtonRendersAsButtonWithDefaultLabel() async {
        await MainActor.run {
            let button = DeleteButton(item: URL(fileURLWithPath: "C:\\test.txt"))
            let context = ViewBuildContext(
                canvasSizeProvider: { Size(width: 200, height: 400) },
                invalidateHandler: {}
            )
            let runtime = RetainedViewRuntime(root: ViewNode())
            let component = button.makeComponent(context: context)
            let node = component.makeNode(runtime: runtime)
            XCTAssertFalse(node.children.isEmpty)
            XCTAssertTrue(allTexts(in: node).contains("Delete"))
        }
    }

    func testDeleteButtonWithNonURLItemsDoesNotCrash() async {
        await MainActor.run {
            let button = DeleteButton(items: ["not a url"])
            let context = ViewBuildContext(
                canvasSizeProvider: { Size(width: 200, height: 400) },
                invalidateHandler: {}
            )
            let runtime = RetainedViewRuntime(root: ViewNode())
            let component = button.makeComponent(context: context)
            let node = component.makeNode(runtime: runtime)
            node.onActivate?()
        }
    }

    func testExportButtonCopiesItemsToClipboardOnActivate() async {
        await MainActor.run {
            let button = ExportButton(item: "clipboard test")
            let context = ViewBuildContext(
                canvasSizeProvider: { Size(width: 200, height: 400) },
                invalidateHandler: {}
            )
            let runtime = RetainedViewRuntime(root: ViewNode())
            let component = button.makeComponent(context: context)
            let node = component.makeNode(runtime: runtime)
            node.onActivate?()
            let pasted = ClipboardManager.pasteItems(for: [UTType.plainText])
            XCTAssertTrue(pasted.contains(where: { ($0 as? String) == "clipboard test" }))
        }
    }
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
