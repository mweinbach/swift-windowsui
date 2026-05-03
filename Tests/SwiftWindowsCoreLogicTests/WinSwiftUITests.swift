import XCTest
import SwiftWindowsCore
import SwiftWindowsGraphics
@testable import SwiftWindowsUI
@testable import WinSwiftUI

final class WinSwiftUITests: XCTestCase {
    func testTextMapsToLabelNode() async {
        await MainActor.run {
            let node = makeNode(
                Text("HELLO")
                    .font(.system(size: 2.4, weight: .bold))
                    .foregroundColor(Color(red: 0.2, green: 0.4, blue: 0.6, alpha: 1))
                    .multilineTextAlignment(.leading)
                    .lineLimit(1)
            )

            XCTAssertEqual(node.text, "HELLO")
            XCTAssertEqual(node.textStyle.scale, 2.4)
            XCTAssertEqual(node.textStyle.weight, .bold)
            XCTAssertEqual(node.textStyle.color, Color(red: 0.2, green: 0.4, blue: 0.6, alpha: 1))
            XCTAssertEqual(node.textStyle.alignment, .leading)
            XCTAssertEqual(node.textStyle.maximumNumberOfLines, 1)
        }
    }

    func testVStackMapsToVerticalStackPanel() async {
        await MainActor.run {
            let node = makeNode(
                VStack(alignment: .leading, spacing: 12) {
                    Text("ONE")
                    Text("TWO")
                }
            )

            guard case .stack(let stackLayout) = node.layoutMode else {
                return XCTFail("Expected stack layout")
            }

            XCTAssertEqual(stackLayout, .vertical(spacing: 12, alignment: .leading))
            XCTAssertEqual(node.children.count, 2)
            XCTAssertEqual(node.children[0].text, "ONE")
            XCTAssertEqual(node.children[1].text, "TWO")
        }
    }

    func testButtonRunsActionAndInvalidates() async {
        await MainActor.run {
            var didRunAction = false
            var didInvalidate = false

            let node = makeNode(
                Button("GO") {
                    didRunAction = true
                },
                onInvalidate: {
                    didInvalidate = true
                }
            )

            XCTAssertTrue(node.isFocusable)
            node.onActivate?()
            XCTAssertTrue(didRunAction)
            XCTAssertTrue(didInvalidate)
        }
    }

    func testToggleUsesBindingAndInvalidates() async {
        await MainActor.run {
            var isOn = false
            var didInvalidate = false

            let node = makeNode(
                Toggle("POWER", isOn: Binding(get: { isOn }, set: { isOn = $0 })),
                onInvalidate: {
                    didInvalidate = true
                }
            )

            XCTAssertEqual(node.children.count, 2)
            let switchNode = node.children[1]
            XCTAssertTrue(switchNode.isFocusable)

            switchNode.onActivate?()

            XCTAssertTrue(isOn)
            XCTAssertTrue(didInvalidate)
        }
    }

    func testSliderUpdatesBindingFromDrag() async {
        await MainActor.run {
            var value = 0.25
            var invalidationCount = 0

            let node = makeNode(
                Slider(value: Binding(get: { value }, set: { value = $0 }), in: 0...1),
                onInvalidate: {
                    invalidationCount += 1
                }
            )

            XCTAssertTrue(node.isFocusable)
            node.onDragStart?(Point(x: 0, y: 0))
            node.onDragChange?(Point(x: 91, y: 0), Point(x: 91, y: 0))

            XCTAssertEqual(value, 0.75, accuracy: 0.01)
            XCTAssertEqual(invalidationCount, 1)
        }
    }

    func testProgressViewMapsToProgressBar() async {
        await MainActor.run {
            let node = makeNode(ProgressView(value: 0.4, total: 1.0))

            XCTAssertEqual(node.children.count, 2)
            XCTAssertEqual(node.children[0].frame.size.width, 200)
            XCTAssertEqual(node.children[1].frame.size.width, 80)
            XCTAssertFalse(node.isHitTestVisible)
        }
    }

    func testTagModifierSetsSelectionTag() async {
        await MainActor.run {
            let node = makeNode(Text("TAGGED").tag(7))

            XCTAssertEqual(node.nodeTag, "7")
            XCTAssertEqual(node.text, "TAGGED")
        }
    }

    func testPickerUsesTaggedTextOptionsAndBinding() async {
        await MainActor.run {
            var selection = 1
            var didInvalidate = false

            let node = makeNode(
                Picker("MODE", selection: Binding(get: { selection }, set: { selection = $0 })) {
                    Text("Layout").tag(0)
                    Text("Input").tag(1)
                    Text("Render").tag(2)
                },
                onInvalidate: {
                    didInvalidate = true
                }
            )

            XCTAssertEqual(node.children.count, 2)
            XCTAssertEqual(node.children[0].text, "MODE")

            let dropdown = node.children[1]
            XCTAssertTrue(dropdown.isFocusable)
            XCTAssertEqual(dropdown.children[0].children.first?.text, "Input")

            let optionsList = dropdown.children[1]
            XCTAssertTrue(optionsList.isHidden)
            dropdown.onActivate?()
            XCTAssertFalse(optionsList.isHidden)

            optionsList.children[2].onActivate?()
            XCTAssertEqual(selection, 2)
            XCTAssertTrue(didInvalidate)
            XCTAssertTrue(optionsList.isHidden)
        }
    }

    func testScrollViewConfiguresScrollChrome() async {
        await MainActor.run {
            let node = makeNode(
                ScrollView(.vertical, style: ScrollViewStyle(spacing: 6, scrollStep: 24)) {
                    Text("ONE")
                    Text("TWO")
                    Text("THREE")
                }
            )

            XCTAssertEqual(node.scrollAxis, .vertical)
            XCTAssertEqual(node.scrollStep, 24)
            XCTAssertTrue(node.showsScrollIndicator)
            XCTAssertTrue(node.clipsToBounds)
            XCTAssertEqual(node.children.count, 3)
        }
    }

    func testGeometryReaderAndZStackUseBuildContextSizing() async {
        await MainActor.run {
            let runtime = RetainedViewRuntime(root: ViewNode())
            let rootSize = Size(width: 320, height: 180)
            let context = ViewBuildContext(canvasSizeProvider: { rootSize }, invalidateHandler: {})
            let root = ZStack(alignment: .center) {
                GeometryReader { proxy in
                    Text("\(Int(proxy.size.width)) X \(Int(proxy.size.height))")
                        .frame(width: 80, height: 24)
                }
            }
            let node = root.makeComponent(context: context).makeNode(runtime: runtime)

            runtime.root.addChild(node)
            runtime.setRootSize(IntSize(width: 320, height: 180))
            let frame = runtime.renderFrame()

            XCTAssertEqual(node.children.count, 1)
            XCTAssertEqual(node.children[0].children.count, 1)
            XCTAssertEqual(node.children[0].children[0].text, "320 X 180")

            let bitmapRect = frame.commands.compactMap { command -> Rect? in
                guard case .drawBitmap(let drawBitmap) = command else {
                    return nil
                }

                return drawBitmap.rect
            }.first

            guard let bitmapRect else {
                return XCTFail("Expected a bitmap text draw command")
            }

            XCTAssertGreaterThan(bitmapRect.size.width, 0)
            XCTAssertGreaterThan(bitmapRect.size.height, 0)
        }
    }

    func testObservedObjectProjectedBindingFeedsToggle() async {
        await MainActor.run {
            final class SettingsModel: ObservableObject {
                @Published var enabled = false
            }

            struct SettingsView: View {
                @ObservedObject var model: SettingsModel

                var body: some View {
                    Toggle("ENABLED", isOn: $model.enabled)
                }
            }

            let model = SettingsModel()
            var didInvalidate = false
            let node = makeNode(
                SettingsView(model: model),
                onInvalidate: {
                    didInvalidate = true
                }
            )

            node.children[1].onActivate?()

            XCTAssertTrue(model.enabled)
            XCTAssertTrue(didInvalidate)
        }
    }

    func testObservedObjectMutationTriggersInvalidation() async {
        await MainActor.run {
            final class CounterModel: ObservableObject {
                @Published var value = 0
            }

            struct CounterView: View {
                @ObservedObject var model: CounterModel

                var body: some View {
                    Text("\(model.value)")
                }
            }

            let model = CounterModel()
            var invalidationCount = 0
            let context = ViewBuildContext(
                canvasSizeProvider: { Size(width: 320, height: 180) },
                invalidateHandler: {},
                observedObjectHandler: { object in
                    _ = ObservableObjectCenter.shared.addObserver(for: object) {
                        invalidationCount += 1
                    }
                }
            )

            _ = CounterView(model: model).makeComponent(context: context)
            model.value = 1

            XCTAssertEqual(invalidationCount, 1)
        }
    }

}

@MainActor
private func makeNode<V: View>(
    _ view: V,
    size: Size = Size(width: 800, height: 600),
    onInvalidate: @escaping () -> Void = {}
) -> ViewNode {
    let runtime = RetainedViewRuntime(root: ViewNode())
    let context = ViewBuildContext(canvasSizeProvider: { size }, invalidateHandler: onInvalidate)
    return view.makeComponent(context: context).makeNode(runtime: runtime)
}
