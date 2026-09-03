import SwiftWindowsCore
@preconcurrency import XCTest

@testable import SwiftWindowsUI
@testable import WinSwiftUI

@MainActor
final class ViewThatFitsTabTransparencyTests: XCTestCase {
    func testTabPageIdentityStaysPhysicalWhileCrossfadeConfigurationReachesNestedSelection() async throws {
        var selection = 0
        var rootBuilds = 0
        let host = MountedOnChangeTestHost {
            rootBuilds += 1
            return AnyView(
                TabView(selection: Binding(get: { selection }, set: { selection = $0 })) {
                    ViewThatFits(in: .horizontal) {
                        ViewThatFits(in: .horizontal) {
                            Text("FIRST PAGE")
                        }
                    }
                    .tag(0)
                    .tabItem { Text("FIRST TAB") }
                    ViewThatFits(in: .horizontal) {
                        ViewThatFits(in: .horizontal) {
                            Text("SECOND PAGE")
                        }
                    }
                    .tag(1)
                    .tabItem { Text("SECOND TAB") }
                })
        }
        defer { host.close() }

        host.render()
        XCTAssertEqual(selection, 0)
        XCTAssertEqual(rootBuilds, 1)
        let originalPage = try tabTransparencyPage(in: host, index: 0, text: "FIRST PAGE")

        let secondButtons = tabTransparencyDescendants(host.runtime.root).filter { node in
            node.isButton && tabTransparencyDescendants(node).contains { $0.text == "SECOND TAB" }
        }
        XCTAssertEqual(secondButtons.count, 1)
        let secondButton = try XCTUnwrap(secondButtons.first)
        let activateSecondTab = try XCTUnwrap(secondButton.onActivate)
        activateSecondTab()
        XCTAssertEqual(selection, 1)
        XCTAssertEqual(rootBuilds, 2)

        host.render()
        XCTAssertEqual(selection, 1)
        XCTAssertEqual(rootBuilds, 2)
        let incomingPage = try tabTransparencyPage(in: host, index: 1, text: "SECOND PAGE")
        XCTAssertFalse(incomingPage === originalPage)
        XCTAssertFalse(tabTransparencyDescendants(host.runtime.root).contains { $0 === originalPage })
        XCTAssertNil(host.coordinator.latestInstallationError)
        // These assertions cover configuration and the current physical tree,
        // not animated opacity samples or removal-overlay completion.
    }
}

@MainActor
private func tabTransparencyPage(
    in host: MountedOnChangeTestHost, index: Int, text: String,
    file: StaticString = #filePath, line: UInt = #line
) throws -> ViewNode {
    let pages = tabTransparencyDescendants(host.runtime.root).filter {
        $0.nodeTag?.hasPrefix("tabview-page:") == true
    }
    XCTAssertEqual(pages.count, 1, file: file, line: line)
    let page = try XCTUnwrap(pages.first, file: file, line: line)
    XCTAssertEqual(page.nodeTag, "tabview-page:\(index)", file: file, line: line)
    XCTAssertEqual(page.selectedContentRole, .viewThatFits, file: file, line: line)
    XCTAssertEqual(page.transition, .identity, file: file, line: line)
    XCTAssertNil(page.implicitReconcileAnimation, file: file, line: line)
    XCTAssertEqual(page.children.count, 1, file: file, line: line)

    let nestedBoundary = try XCTUnwrap(page.children.first, file: file, line: line)
    XCTAssertTrue(nestedBoundary.parent === page, file: file, line: line)
    XCTAssertEqual(nestedBoundary.selectedContentRole, .viewThatFits, file: file, line: line)
    XCTAssertNil(nestedBoundary.nodeTag, file: file, line: line)
    XCTAssertEqual(nestedBoundary.transition, .identity, file: file, line: line)
    XCTAssertNil(nestedBoundary.implicitReconcileAnimation, file: file, line: line)
    XCTAssertEqual(nestedBoundary.children.count, 1, file: file, line: line)

    let leaf = try XCTUnwrap(nestedBoundary.children.first, file: file, line: line)
    XCTAssertTrue(leaf.parent === nestedBoundary, file: file, line: line)
    XCTAssertNil(leaf.selectedContentRole, file: file, line: line)
    XCTAssertNil(leaf.nodeTag, file: file, line: line)
    XCTAssertEqual(leaf.text, text, file: file, line: line)
    XCTAssertEqual(leaf.transition, RetainedTransition(kind: .opacity), file: file, line: line)
    XCTAssertEqual(
        leaf.implicitReconcileAnimation, AnimationTransaction(duration: 0.25, easing: .easeInOut),
        file: file, line: line)
    return page
}

@MainActor
private func tabTransparencyDescendants(_ node: ViewNode) -> [ViewNode] {
    [node] + node.children.flatMap(tabTransparencyDescendants)
}
