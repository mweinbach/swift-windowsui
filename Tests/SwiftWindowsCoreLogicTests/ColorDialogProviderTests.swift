import Foundation
import SwiftWindowsCore
import XCTest

@testable import SwiftWindowsPlatform
@testable import SwiftWindowsUI
@testable import WinSwiftUI

final class ColorDialogProviderTests: XCTestCase {
    @MainActor
    private final class FakeColorDialogProvider: ColorDialogProvider {
        var result: Color?
        private(set) var requests: [Color] = []

        func chooseColor(initial: Color) -> Color? {
            requests.append(initial)
            return result
        }
    }

    @MainActor
    private static func makeContext() -> ViewBuildContext {
        ViewBuildContext(
            canvasSizeProvider: { Size(width: 200, height: 200) },
            invalidateHandler: {}
        )
    }

    @MainActor
    private static func firstActivatableNode(_ node: ViewNode) -> ViewNode? {
        if node.onActivate != nil {
            return node
        }
        for child in node.children {
            if let found = firstActivatableNode(child) {
                return found
            }
        }
        return nil
    }

    @MainActor
    private static func withFakeProvider(result: Color?, _ body: (FakeColorDialogProvider) -> Void) {
        let fake = FakeColorDialogProvider()
        fake.result = result
        let original = ColorDialogManager.provider
        ColorDialogManager.provider = fake
        defer { ColorDialogManager.provider = original }
        body(fake)
    }

    func testManagerPassesThroughToInjectedProvider() async {
        await MainActor.run {
            let chosen = Color(red: 0.25, green: 0.5, blue: 0.75, alpha: 1)
            Self.withFakeProvider(result: chosen) { fake in
                let initial = Color(red: 1, green: 0, blue: 0, alpha: 1)
                XCTAssertEqual(ColorDialogManager.chooseColor(initial: initial), chosen)
                XCTAssertEqual(fake.requests, [initial])
            }
        }
    }

    func testColorPickerNativeOptInOpensDialogAndAppliesChoice() async {
        await MainActor.run {
            let chosen = Color(red: 0.1, green: 0.2, blue: 0.3, alpha: 1)
            Self.withFakeProvider(result: chosen) { fake in
                var selection = Color(red: 0.9, green: 0.8, blue: 0.7, alpha: 1)
                let binding = Binding(get: { selection }, set: { selection = $0 })
                let view = ColorPicker("Pick a color", selection: binding)
                    .environment(\.colorPickerUsesNativeDialog, true)

                let runtime = RetainedViewRuntime(root: ViewNode())
                let host = ComponentHost(runtime: runtime)
                host.setContent(view.makeComponent(context: Self.makeContext()))

                guard let node = Self.firstActivatableNode(runtime.root) else {
                    XCTFail("expected ColorPicker to build an activatable node")
                    return
                }
                node.onActivate?()

                XCTAssertEqual(fake.requests.count, 1)
                XCTAssertEqual(selection, chosen)
            }
        }
    }

    func testColorPickerNativeOptInCancelLeavesSelectionUntouched() async {
        await MainActor.run {
            Self.withFakeProvider(result: nil) { fake in
                let original = Color(red: 0.9, green: 0.8, blue: 0.7, alpha: 1)
                var selection = original
                let binding = Binding(get: { selection }, set: { selection = $0 })
                let view = ColorPicker("Pick a color", selection: binding)
                    .environment(\.colorPickerUsesNativeDialog, true)

                let runtime = RetainedViewRuntime(root: ViewNode())
                let host = ComponentHost(runtime: runtime)
                host.setContent(view.makeComponent(context: Self.makeContext()))

                guard let node = Self.firstActivatableNode(runtime.root) else {
                    XCTFail("expected ColorPicker to build an activatable node")
                    return
                }
                node.onActivate?()

                XCTAssertEqual(fake.requests.count, 1)
                XCTAssertEqual(selection, original)
            }
        }
    }

    func testColorPickerDefaultKeepsPaletteAndDoesNotOpenDialog() async {
        await MainActor.run {
            Self.withFakeProvider(result: Color(red: 0.1, green: 0.2, blue: 0.3, alpha: 1)) { fake in
                var selection = Color(red: 0.9, green: 0.8, blue: 0.7, alpha: 1)
                let binding = Binding(get: { selection }, set: { selection = $0 })
                let view = ColorPicker("Pick a color", selection: binding)

                let runtime = RetainedViewRuntime(root: ViewNode())
                let host = ComponentHost(runtime: runtime)
                host.setContent(view.makeComponent(context: Self.makeContext()))

                guard let node = Self.firstActivatableNode(runtime.root) else {
                    XCTFail("expected ColorPicker to build an activatable node")
                    return
                }
                node.onActivate?()

                XCTAssertEqual(fake.requests.count, 0, "default activation must stay on the retained palette")
            }
        }
    }
}
