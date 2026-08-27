import SwiftWindowsCore
import SwiftWindowsGraphics
import XCTest

@testable import SwiftWindowsUI
@testable import WinSwiftUI

final class WinSwiftUIScrollObservationTests: XCTestCase {
    @MainActor
    private static func makeRuntime<V: View>(
        _ view: V
    ) -> (runtime: RetainedViewRuntime, node: ViewNode) {
        let size = Size(width: 120, height: 100)
        let runtime = RetainedViewRuntime(root: ViewNode(frame: Rect(origin: .zero, size: size)))
        let context = ViewBuildContext(canvasSizeProvider: { size }, invalidateHandler: {})
        let node = view.makeComponent(context: context).makeNode(runtime: runtime)
        node.frame = Rect(origin: .zero, size: size)
        runtime.root.addChild(node)
        return (runtime, node)
    }

    @MainActor
    private static func firstScrollNode(in root: ViewNode) -> ViewNode? {
        var pending = [root]
        while let node = pending.popLast() {
            if node.scrollAxis != nil || node.scrollContainerState != nil {
                return node
            }
            pending.append(contentsOf: node.children.reversed())
        }
        return nil
    }

    private static func redMarkerRect(in scene: GPUIScene) -> Rect? {
        guard
            let quad = scene.layers.flatMap(\.quads).first(where: {
                $0.startR == 1 && $0.startG == 0 && $0.startB == 0 && $0.startA == 1
            })
        else { return nil }
        return Rect(x: Double(quad.x), y: Double(quad.y), width: Double(quad.width), height: Double(quad.height))
    }

    func testGeometryModifierOutsideFrameObservesTheEnclosedPublicScrollView() async {
        await MainActor.run {
            var geometries: [(old: ScrollGeometry, new: ScrollGeometry)] = []
            let (runtime, node) = Self.makeRuntime(
                ScrollView(.vertical, showsIndicators: false) {
                    Text("FIRST").frame(height: 80)
                    Text("SECOND").frame(height: 80)
                    Text("THIRD").frame(height: 80)
                }
                .frame(width: 120, height: 100)
                .onScrollGeometryChange(for: ScrollGeometry.self, of: { $0 }) { old, new in
                    geometries.append((old, new))
                })
            XCTAssertNil(node.scrollAxis, "The modifier is attached outside the fixed-frame wrapper")
            XCTAssertTrue(geometries.isEmpty)
            _ = runtime.renderScene()

            XCTAssertEqual(geometries.count, 1)
            XCTAssertEqual(geometries.first?.old, geometries.first?.new)
            XCTAssertEqual(geometries.first?.new.contentOffset.y, 0)
            XCTAssertEqual(geometries.first?.new.containerSize.height, 100)
            XCTAssertEqual(geometries.first?.new.contentSize.height, 240)
            guard let scroller = Self.firstScrollNode(in: node) else {
                return XCTFail("Expected the public ScrollView to build a retained scroll node")
            }

            scroller.scrollOffset = 40
            XCTAssertEqual(geometries.count, 1)
            _ = runtime.renderFrame()
            _ = runtime.renderScene()
            XCTAssertEqual(geometries.count, 2)
            XCTAssertEqual(geometries.last?.old.contentOffset.y, 0)
            XCTAssertEqual(geometries.last?.new.contentOffset.y, 40)
        }
    }

    func testBothPublicPhaseOverloadsReceiveWheelDecelerationAndContext() async {
        await MainActor.run {
            var simplePhases: [ScrollPhase] = []
            var contextualPhases: [ScrollPhase] = []
            var contexts: [ScrollPhaseChangeContext] = []
            let (runtime, node) = Self.makeRuntime(
                ScrollView(.vertical, showsIndicators: false) {
                    Text("CONTENT").frame(height: 600)
                }
                .frame(width: 120, height: 100)
                .onScrollPhaseChange { _, new in simplePhases.append(new) }
                .onScrollPhaseChange { _, new, context in
                    contextualPhases.append(new)
                    contexts.append(context)
                })
            let clock = RuntimeTestClock()
            runtime.clock = { clock.now }
            _ = runtime.renderScene()
            XCTAssertTrue(simplePhases.isEmpty)
            XCTAssertTrue(contextualPhases.isEmpty)
            guard let scroller = Self.firstScrollNode(in: node) else {
                return XCTFail("Expected the public ScrollView to build a retained scroll node")
            }
            scroller.scrollStep = 20

            runtime.mouseWheel(at: Point(x: 30, y: 30), delta: -1, source: .precise)
            XCTAssertTrue(simplePhases.isEmpty)
            XCTAssertTrue(contextualPhases.isEmpty)
            _ = runtime.renderFrame()
            XCTAssertEqual(simplePhases, [.interacting, .decelerating])
            XCTAssertEqual(contextualPhases, simplePhases)
            XCTAssertEqual(contexts.last?.geometry.contentOffset.y, 20)
            XCTAssertEqual(contexts.last?.geometry.containerSize.height, 100)
            XCTAssertEqual(contexts.last?.velocity?.dx, 0)
            XCTAssertGreaterThan(contexts.last?.velocity?.dy ?? 0, 0)

            clock.now = 1
            _ = runtime.tickAnimations(at: clock.now)
            _ = runtime.renderScene()
            XCTAssertEqual(simplePhases, [.interacting, .decelerating, .idle])
            XCTAssertEqual(contextualPhases, simplePhases)
            XCTAssertEqual(
                Double(contexts.last?.geometry.contentOffset.y ?? -1),
                scroller.resolvedScrollOffset,
                accuracy: 0.0001)
        }
    }

    func testPublicVisibilityModifierRespondsToActualScrollViewportCrossings() async {
        await MainActor.run {
            var visibility: [Bool] = []
            let (runtime, node) = Self.makeRuntime(
                ScrollView(.vertical, showsIndicators: false) {
                    Text("BEFORE").frame(width: 100, height: 90)
                    Text("OBSERVED")
                        .frame(width: 100, height: 40)
                        .onScrollVisibilityChange(threshold: 0.5) { visibility.append($0) }
                    Text("AFTER").frame(width: 100, height: 200)
                }
                .frame(width: 120, height: 100))
            XCTAssertTrue(visibility.isEmpty)
            _ = runtime.renderScene()
            XCTAssertEqual(visibility, [false])
            guard let scroller = Self.firstScrollNode(in: node) else {
                return XCTFail("Expected the public ScrollView to build a retained scroll node")
            }

            scroller.scrollOffset = 20
            _ = runtime.renderFrame()
            _ = runtime.renderScene()
            XCTAssertEqual(visibility, [false, true])
            scroller.scrollOffset = 140
            _ = runtime.renderScene()
            XCTAssertEqual(visibility, [false, true, false])
        }
    }

    func testPublicHorizontalGeometryUsesTheHorizontalOffsetComponent() async {
        await MainActor.run {
            var xOffsets: [Double] = []
            var yOffsets: [Double] = []
            let (runtime, node) = Self.makeRuntime(
                ScrollView(.horizontal, showsIndicators: false) {
                    Text("WIDE CONTENT").frame(width: 300, height: 40)
                }
                .frame(width: 120, height: 100)
                .onScrollGeometryChange(for: ScrollGeometry.self, of: { $0 }) { _, new in
                    xOffsets.append(Double(new.contentOffset.x))
                    yOffsets.append(Double(new.contentOffset.y))
                })
            _ = runtime.renderScene()
            guard let scroller = Self.firstScrollNode(in: node) else {
                return XCTFail("Expected the public ScrollView to build a retained scroll node")
            }
            scroller.scrollStep = 20
            runtime.mouseWheel(at: Point(x: 30, y: 30), delta: -1, axis: .horizontal)
            _ = runtime.renderFrame()

            XCTAssertEqual(xOffsets, [0, 20])
            XCTAssertEqual(yOffsets, [0, 0])
        }
    }

    func testPublicScrollDisabledStillDeliversGeometryWithoutAcceptingInput() async {
        await MainActor.run {
            var geometries: [ScrollGeometry] = []
            let (runtime, node) = Self.makeRuntime(
                ScrollView(.vertical, showsIndicators: false) {
                    Text("CONTENT").frame(height: 400)
                }
                .scrollDisabled(true)
                .frame(width: 120, height: 100)
                .onScrollGeometryChange(for: ScrollGeometry.self, of: { $0 }) { _, new in
                    geometries.append(new)
                })
            _ = runtime.renderScene()
            guard let scroller = Self.firstScrollNode(in: node) else {
                return XCTFail("Disabling input must preserve the declared scroll container")
            }
            XCTAssertEqual(scroller.scrollAxis, .vertical)
            XCTAssertFalse(scroller.isScrollInputEnabled)
            XCTAssertEqual(scroller.scrollContainerState?.axis, .vertical)
            XCTAssertEqual(geometries.count, 1)
            XCTAssertEqual(geometries.first?.containerSize.height, 100)

            runtime.pointerMoved(to: Point(x: 30, y: 30))
            runtime.mouseWheel(at: Point(x: 30, y: 30), delta: -1)
            runtime.keyDown(KeyboardEvent(keyCode: KeyboardKey.downArrow.rawValue))
            _ = runtime.renderFrame()
            XCTAssertEqual(scroller.scrollOffset, 0)
            XCTAssertEqual(geometries.count, 1)
            XCTAssertEqual(geometries.last?.contentOffset.y, 0)
        }
    }

    func testPublicDisableAndReenablePreserveNonzeroGeometryPaintAndHitTestingOnBothAxes() async {
        await MainActor.run {
            for horizontal in [false, true] {
                let runtime = RetainedViewRuntime(root: ViewNode(frame: Rect(x: 0, y: 0, width: 120, height: 100)))
                let host = ComponentHost(runtime: runtime)
                let context = ViewBuildContext(
                    canvasSizeProvider: { Size(width: 120, height: 100) }, invalidateHandler: {})
                let axes: WinSwiftUI.Axis.Set = horizontal ? .horizontal : .vertical
                var disabled = false
                var proxy: ScrollViewProxy?
                var offsets: [Double] = []
                var taps = 0
                host.setComponents {
                    [
                        ScrollViewReader { reader in
                            proxy = reader
                            ScrollView(axes, showsIndicators: true) {
                                WinSwiftUI.Color.clear.frame(width: 40, height: 40)
                                WinSwiftUI.Color(red: 1, green: 0, blue: 0, alpha: 1)
                                    .frame(width: 40, height: 40)
                                    .onTapGesture { taps += 1 }
                                    .id("marker")
                                WinSwiftUI.Color.clear
                                    .frame(width: horizontal ? 400 : 40, height: horizontal ? 40 : 400)
                                    .id("after")
                            }
                            .scrollDisabled(disabled)
                            .frame(width: 120, height: 100)
                            .onScrollGeometryChange(
                                for: Double.self,
                                of: { Double(horizontal ? $0.contentOffset.x : $0.contentOffset.y) }
                            ) { _, new in offsets.append(new) }
                        }
                        .makeComponent(context: context)
                    ]
                }
                _ = runtime.renderScene()
                guard let scroller = Self.firstScrollNode(in: runtime.root) else {
                    return XCTFail("Expected a retained scroll container")
                }
                scroller.scrollOffset = 40
                let initialScene = runtime.renderScene()
                guard let marker = Self.redMarkerRect(in: initialScene),
                    let thumb = scroller.scrollIndicatorRect(in: scroller.resolvedFrame)
                else { return XCTFail("Expected the marker and the enabled scroll thumb") }
                let markerPoint = Point(x: marker.midX, y: marker.midY)
                runtime.pointerDown(at: markerPoint)
                runtime.pointerUp(at: markerPoint)
                XCTAssertEqual(taps, 1)
                XCTAssertEqual(offsets, [0, 40])

                disabled = true
                host.reload()
                XCTAssertTrue(Self.firstScrollNode(in: runtime.root) === scroller)
                let disabledScene = runtime.renderScene()
                XCTAssertEqual(scroller.scrollAxis, horizontal ? .horizontal : .vertical)
                XCTAssertFalse(scroller.isScrollInputEnabled)
                XCTAssertEqual(scroller.scrollOffset, 40)
                XCTAssertEqual(scroller.resolvedScrollOffset, 40)
                XCTAssertEqual(Self.redMarkerRect(in: disabledScene), marker)
                runtime.pointerDown(at: markerPoint)
                runtime.pointerUp(at: markerPoint)
                XCTAssertEqual(taps, 2, "Disabling scrolling does not disable the visible content's hit target")

                runtime.mouseWheel(at: markerPoint, delta: -1, axis: horizontal ? .horizontal : .vertical)
                runtime.keyDown(
                    KeyboardEvent(
                        keyCode: horizontal ? KeyboardKey.rightArrow.rawValue : KeyboardKey.downArrow.rawValue))
                let thumbPoint = Point(x: thumb.midX, y: thumb.midY)
                let dragEnd = Point(x: thumbPoint.x + 25, y: thumbPoint.y + 25)
                runtime.pointerDown(at: thumbPoint)
                runtime.pointerMoved(to: dragEnd)
                runtime.pointerUp(at: dragEnd)
                _ = runtime.renderScene()
                XCTAssertEqual(scroller.scrollOffset, 40)
                XCTAssertEqual(scroller.resolvedScrollOffset, 40)
                XCTAssertEqual(offsets, [0, 40])

                proxy?.scrollTo("after", anchor: horizontal ? .leading : .top)
                _ = runtime.renderScene()
                XCTAssertGreaterThan(scroller.scrollOffset, 40, "Programmatic scrolling still works while disabled")
                proxy?.scrollTo("marker", anchor: horizontal ? .leading : .top)
                _ = runtime.renderScene()
                XCTAssertEqual(scroller.scrollOffset, 40)

                disabled = false
                host.reload()
                let enabledScene = runtime.renderScene()
                XCTAssertTrue(Self.firstScrollNode(in: runtime.root) === scroller)
                XCTAssertTrue(scroller.isScrollInputEnabled)
                XCTAssertEqual(scroller.scrollOffset, 40)
                XCTAssertEqual(scroller.resolvedScrollOffset, 40)
                XCTAssertEqual(offsets.last, 40)
                XCTAssertEqual(Self.redMarkerRect(in: enabledScene), marker)
                runtime.pointerDown(at: markerPoint)
                runtime.pointerUp(at: markerPoint)
                XCTAssertEqual(taps, 3)
            }
        }
    }

    func testPublicScrollDisabledIsInheritedByNestedScrollViews() async {
        await MainActor.run {
            let (runtime, node) = Self.makeRuntime(
                ScrollView(.vertical, showsIndicators: false) {
                    ScrollView(.horizontal, showsIndicators: false) {
                        Text("WIDE CONTENT").frame(width: 400, height: 40)
                    }
                    .scrollDisabled(false)
                    .frame(width: 100, height: 60)
                    Text("TALL CONTENT").frame(height: 400)
                }
                .scrollDisabled(true)
                .frame(width: 120, height: 100))
            _ = runtime.renderScene()
            var pending = [node]
            var scrollers: [ViewNode] = []
            while let current = pending.popLast() {
                if current.scrollAxis != nil { scrollers.append(current) }
                pending.append(contentsOf: current.children.reversed())
            }
            XCTAssertEqual(scrollers.count, 2)
            XCTAssertTrue(scrollers.allSatisfy { !$0.isScrollInputEnabled })

            runtime.pointerMoved(to: Point(x: 30, y: 30))
            runtime.mouseWheel(at: Point(x: 30, y: 30), delta: -1, axis: .horizontal)
            runtime.mouseWheel(at: Point(x: 30, y: 30), delta: -1, axis: .vertical)
            runtime.keyDown(KeyboardEvent(keyCode: KeyboardKey.rightArrow.rawValue))
            runtime.keyDown(KeyboardEvent(keyCode: KeyboardKey.downArrow.rawValue))
            _ = runtime.renderFrame()
            XCTAssertTrue(scrollers.allSatisfy { $0.scrollOffset == 0 && $0.resolvedScrollOffset == 0 })
        }
    }

    @MainActor
    private struct StateObservingScrollView: View {
        @State var observedOffset = -1.0
        let record: (Double) -> Void

        var body: some View {
            ScrollView(.vertical, showsIndicators: false) {
                Text("OFFSET \(Int(observedOffset))").frame(height: 40)
                Text("CONTENT").frame(height: 400)
            }
            .frame(width: 120, height: 100)
            .onScrollGeometryChange(
                for: Double.self, of: { Double($0.contentOffset.y) },
                action: { _, new in
                    record(new)
                    observedOffset = new
                })
        }
    }

    func testGeometryCallbackCanUpdateStateAndRebuildWithoutDuplicateDelivery() async {
        await MainActor.run {
            let runtime = RetainedViewRuntime(root: ViewNode(frame: Rect(x: 0, y: 0, width: 120, height: 100)))
            let host = ComponentHost(runtime: runtime)
            var values: [Double] = []
            var invalidations = 0
            let view = StateObservingScrollView { values.append($0) }
            let context = ViewBuildContext(
                canvasSizeProvider: { Size(width: 120, height: 100) },
                invalidateHandler: { [weak host] in
                    invalidations += 1
                    host?.reload()
                })
            host.setComponents { [view.makeComponent(context: context)] }
            _ = runtime.renderScene()
            _ = runtime.renderScene()
            XCTAssertEqual(values, [0])
            XCTAssertEqual(view.observedOffset, 0)
            XCTAssertEqual(invalidations, 1)
            guard let scroller = Self.firstScrollNode(in: runtime.root) else {
                return XCTFail("Expected a retained scroll node after the callback rebuilt the view")
            }

            scroller.scrollStep = 20
            runtime.mouseWheel(at: Point(x: 30, y: 30), delta: -1)
            _ = runtime.renderFrame()
            _ = runtime.renderScene()
            _ = runtime.renderScene()

            XCTAssertTrue(Self.firstScrollNode(in: runtime.root) === scroller)
            XCTAssertEqual(values, [0, 20])
            XCTAssertEqual(view.observedOffset, 20)
            XCTAssertEqual(invalidations, 2)
        }
    }
}
