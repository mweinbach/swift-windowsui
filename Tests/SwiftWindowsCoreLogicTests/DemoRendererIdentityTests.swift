import SwiftWindowsCore
import XCTest

@testable import SwiftWindowsDemo
@testable import SwiftWindowsUI
@testable import WinSwiftUI

/// The product's selected engine must be the one its dashboard reports. This
/// identity crosses the shared-demo boundary as pure Swift data, so the demo
/// never needs to import a concrete renderer to describe the active engine.
@MainActor
final class DemoRendererIdentityTests: XCTestCase {
    private func snapshotRoot(
        model: DemoDashboardModel,
        size: IntSize = IntSize(width: 1280, height: 720)
    ) -> ViewNode {
        WinSwiftUIRendererSnapshotter.snapshot(
            of: DemoRootView(model: model),
            size: size,
            displayScale: 1,
            colorScheme: .dark
        ).runtime.root
    }

    private func containsText(_ text: String, in root: ViewNode) -> Bool {
        var pending = [root]
        while let node = pending.popLast() {
            if node.text == text {
                return true
            }
            pending.append(contentsOf: node.children)
        }
        return false
    }

    func testDirect3D11RemainsTheUnchangedDefaultIdentity() async {
        let identity = DemoRendererIdentity.direct3D11
        let model = DemoDashboardModel()

        XCTAssertEqual(identity.displayName, "D3D11")
        XCTAssertEqual(identity.readyEvent, "D3D11 ready")
        XCTAssertEqual(identity.componentDescription, "D3D11 batch pipeline")
        XCTAssertEqual(model.rendererIdentity, identity)
        XCTAssertEqual(
            model.recentEvents,
            ["System ready", "D3D11 ready", "Window toolkit active"]
        )
        XCTAssertEqual(model.components, DemoComponent.defaults)
        XCTAssertEqual(model.selectedComponentID, DemoComponent.defaults.first?.id)
    }

    func testSoftwareIdentityReplacesEveryBackendSpecificModelSurface() async {
        let model = DemoDashboardModel(rendererIdentity: .software)

        XCTAssertEqual(model.rendererIdentity.displayName, "Software")
        XCTAssertEqual(model.rendererIdentity.readyEvent, "Software ready")
        XCTAssertEqual(
            model.recentEvents,
            ["System ready", "Software ready", "Window toolkit active"]
        )
        XCTAssertEqual(model.components.first?.name, "Render host")
        XCTAssertEqual(model.components.first?.detail, "Software CPU presentation pipeline")
        XCTAssertEqual(model.components.dropFirst(), DemoComponent.defaults.dropFirst())
        XCTAssertFalse(model.recentEvents.contains { $0.contains("D3D11") })
        XCTAssertFalse(model.components.contains { $0.detail.contains("D3D11") })
    }

    func testNativeSwiftUIIdentityKeepsTheSharedMacOSDemoHonest() async {
        let model = DemoDashboardModel(rendererIdentity: .nativeSwiftUI)

        XCTAssertEqual(model.rendererIdentity.displayName, "SwiftUI")
        XCTAssertEqual(model.recentEvents[1], "SwiftUI ready")
        XCTAssertEqual(model.components.first?.detail, "Native SwiftUI presentation pipeline")
        XCTAssertEqual(model.selectedComponentID, 1)
    }

    func testFutureRendererCanInjectItsOwnPureSwiftIdentity() async {
        let identity = DemoRendererIdentity(
            displayName: "Metal",
            componentDescription: "Metal scene presentation pipeline"
        )
        let model = DemoDashboardModel(rendererIdentity: identity)

        XCTAssertEqual(model.rendererIdentity, identity)
        XCTAssertEqual(model.recentEvents[1], "Metal ready")
        XCTAssertEqual(model.components.first?.detail, "Metal scene presentation pipeline")
    }

    func testToolbarAndRecentEventsRenderTheSelectedEngine() async {
        let softwareRoot = snapshotRoot(model: DemoDashboardModel(rendererIdentity: .software))
        XCTAssertTrue(containsText("Software", in: softwareRoot))
        XCTAssertTrue(containsText("Software ready", in: softwareRoot))
        XCTAssertFalse(containsText("D3D11", in: softwareRoot))
        XCTAssertFalse(containsText("D3D11 ready", in: softwareRoot))

        let defaultRoot = snapshotRoot(model: DemoDashboardModel())
        XCTAssertTrue(containsText("D3D11", in: defaultRoot))
        XCTAssertTrue(containsText("D3D11 ready", in: defaultRoot))
    }

    func testSelectedDataComponentAndSearchDescribeTheActualEngine() async {
        let model = DemoDashboardModel(rendererIdentity: .software)
        model.selectedScreen = .data

        let root = snapshotRoot(model: model)
        XCTAssertTrue(containsText("Software CPU presentation pipeline", in: root))
        XCTAssertFalse(containsText("D3D11 batch pipeline", in: root))

        model.componentFilter = "software presentation"
        XCTAssertEqual(model.filteredComponents.map(\.id), [1])

        model.componentFilter = "d3d11"
        XCTAssertTrue(model.filteredComponents.isEmpty)
    }

    func testRestartPreservesInjectedRendererComponentIdentity() async {
        let model = DemoDashboardModel(rendererIdentity: .software)
        guard let renderHost = model.components.first else {
            return XCTFail("the dashboard should expose its active render host")
        }

        let restarted = renderHost.restarted()

        XCTAssertEqual(restarted.detail, model.rendererIdentity.componentDescription)
        XCTAssertLessThan(restarted.load, renderHost.load)
    }
}
