import SwiftWindowsCore
import SwiftWindowsLayout
import XCTest

@testable import SwiftWindowsUI
@testable import WinSwiftUI

final class AbsoluteLayoutSizingTests: XCTestCase {
    func testAbsoluteIdealFitsNarrowAndWideProposals() async {
        await MainActor.run {
            let cases: [(IntSize, Size)] = [
                (IntSize(width: 220, height: 60), Size(width: 220, height: 60)),
                (IntSize(width: 340, height: 120), Size(width: 280, height: 90)),
            ]
            for (rootSize, expected) in cases {
                let node = ViewNode(preferredSize: Size(width: 280, height: 90))
                let runtime = absoluteSizingRuntime(child: node, size: rootSize)
                defer { runtime.root.removeAllChildren() }

                _ = runtime.renderFrame()

                XCTAssertEqual(node.resolvedFrame.size, expected)
                XCTAssertEqual(node.preferredSize, Size(width: 280, height: 90))
                XCTAssertEqual(node.frame, .zero)
                XCTAssertTrue(node.fixedPreferredSizeAxes.isEmpty)
            }
        }
    }

    func testAbsoluteGreedyIdealKeepsAcceptedMeasurementAndPlacement() async {
        await MainActor.run {
            let child = ViewNode(preferredSize: Size(width: 200, height: 28))
            child.layoutFillAxes = .both
            let container = ViewNode(
                layoutConstraints: LayoutConstraints(maxWidth: 340, maxHeight: 80),
                children: [child])

            // Only the child supplies this measured extent. A sized or greedy
            // parent would conceal a fold that restores the child's ideal.
            XCTAssertEqual(container.frame, .zero)
            XCTAssertNil(container.preferredSize)
            XCTAssertNil(container.fixedSizeAxes)
            XCTAssertTrue(container.layoutFillAxes.isEmpty)
            XCTAssertEqual(container.layoutConstraints?.minWidth, 0)
            XCTAssertEqual(container.layoutConstraints?.minHeight, 0)
            XCTAssertEqual(container.intrinsicContentSize(), Size(width: 340, height: 80))

            let runtime = absoluteSizingRuntime(
                child: container, size: IntSize(width: 340, height: 80))
            defer { runtime.root.removeAllChildren() }
            _ = runtime.renderFrame()

            XCTAssertEqual(container.resolvedFrame.size, Size(width: 340, height: 80))
            XCTAssertEqual(child.resolvedFrame.size, Size(width: 340, height: 80))
            XCTAssertEqual(child.preferredSize, Size(width: 200, height: 28))
            XCTAssertEqual(container.frame, .zero)
        }
    }

    func testAbsoluteOriginReducesProposalWithoutMovingChild() async {
        await MainActor.run {
            let node = ViewNode(
                frame: Rect(x: 30, y: 10, width: 0, height: 0),
                preferredSize: Size(width: 280, height: 90))
            let runtime = absoluteSizingRuntime(child: node, size: IntSize(width: 220, height: 60))
            defer { runtime.root.removeAllChildren() }

            _ = runtime.renderFrame()

            XCTAssertEqual(node.resolvedFrame, Rect(x: 30, y: 10, width: 190, height: 50))
            XCTAssertEqual(node.resolvedFrame.maxX, 220, accuracy: 0.001)
            XCTAssertEqual(node.resolvedFrame.maxY, 60, accuracy: 0.001)
            XCTAssertEqual(node.frame, Rect(x: 30, y: 10, width: 0, height: 0))
            XCTAssertEqual(node.preferredSize, Size(width: 280, height: 90))
        }
    }

    func testUnconstrainedAbsoluteMeasurementKeepsFiniteIdeal() async {
        await MainActor.run {
            for fillAxes in [LayoutFillAxes(), .both] {
                let child = ViewNode(preferredSize: Size(width: 280, height: 90))
                child.layoutFillAxes = fillAxes
                let container = ViewNode(children: [child])

                let measured = container.intrinsicContentSize()

                XCTAssertEqual(measured, Size(width: 280, height: 90))
                XCTAssertTrue(measured.width.isFinite)
                XCTAssertTrue(measured.height.isFinite)
                XCTAssertEqual(child.intrinsicContentSize(), Size(width: 280, height: 90))
                XCTAssertNil(container.layoutConstraints)
                XCTAssertEqual(container.frame, .zero)
            }
        }
    }

    func testAbsoluteIdealHonorsLocalMinimumAndMaximum() async {
        await MainActor.run {
            let cases: [(LayoutConstraints, Size)] = [
                (LayoutConstraints(maxWidth: 180, maxHeight: 40), Size(width: 180, height: 40)),
                (LayoutConstraints(minWidth: 260, minHeight: 80), Size(width: 260, height: 80)),
            ]
            for (constraints, expected) in cases {
                let node = ViewNode(
                    preferredSize: Size(width: 280, height: 90), layoutConstraints: constraints)
                let runtime = absoluteSizingRuntime(child: node, size: IntSize(width: 220, height: 60))
                defer { runtime.root.removeAllChildren() }

                _ = runtime.renderFrame()

                XCTAssertEqual(node.resolvedFrame.size, expected)
                XCTAssertEqual(node.preferredSize, Size(width: 280, height: 90))
                XCTAssertTrue(node.fixedPreferredSizeAxes.isEmpty)
            }
        }
    }

    func testRawAuthoredFrameKeepsExistingAbsoluteSizePolicy() async {
        await MainActor.run {
            let cases: [(Rect, Size?, Rect)] = [
                (
                    Rect(x: 7, y: 9, width: 300, height: 70), nil,
                    Rect(x: 7, y: 9, width: 300, height: 70)
                ),
                (
                    Rect(x: 7, y: 9, width: 300, height: 70), Size(width: 280, height: 90),
                    Rect(x: 7, y: 9, width: 280, height: 90)
                ),
                (
                    Rect(x: 0, y: 0, width: 0, height: 70), Size(width: 280, height: 90),
                    Rect(x: 0, y: 0, width: 220, height: 90)
                ),
            ]
            for (authoredFrame, preference, expected) in cases {
                let node = ViewNode(frame: authoredFrame, preferredSize: preference)
                let runtime = absoluteSizingRuntime(child: node, size: IntSize(width: 220, height: 50))
                defer { runtime.root.removeAllChildren() }

                _ = runtime.renderFrame()

                // A positive raw axis preserves the legacy preferred-before-raw
                // policy. The raw-zero width in the final row remains an ideal.
                XCTAssertEqual(node.resolvedFrame, expected)
                XCTAssertEqual(node.frame, authoredFrame)
                XCTAssertEqual(node.preferredSize, preference)
            }

            let marked = ViewNode(preferredSize: Size(width: 280, height: 90))
            marked.fixedPreferredSizeAxes = .horizontalOnly
            let runtime = absoluteSizingRuntime(child: marked, size: IntSize(width: 220, height: 50))
            defer { runtime.root.removeAllChildren() }
            _ = runtime.renderFrame()
            XCTAssertEqual(marked.resolvedFrame.size, Size(width: 280, height: 50))
        }
    }

    func testFixedFacadeFrameKeepsWidthLargerThanProposal() async {
        await MainActor.run {
            let fixture = absoluteSizingViewFixture(
                Rectangle().frame(width: 300, height: 30),
                rootSize: IntSize(width: 220, height: 50))
            defer { fixture.runtime.root.removeAllChildren() }

            _ = fixture.runtime.renderFrame()

            XCTAssertEqual(fixture.node.resolvedFrame.size, Size(width: 300, height: 30))
            XCTAssertEqual(fixture.node.preferredSize, Size(width: 300, height: 30))
            XCTAssertEqual(fixture.node.frame, .zero)
            XCTAssertEqual(fixture.node.fixedPreferredSizeAxes, .both)
            XCTAssertEqual(fixture.node.children.count, 1)
            guard let content = fixture.node.children.first else {
                return XCTFail("Expected the existing fixed-frame content child")
            }
            XCTAssertEqual(content.resolvedFrame.size, Size(width: 300, height: 30))
        }
    }

    func testFixedFacadeAxesLeaveOmittedDimensionsMeasured() async {
        await MainActor.run {
            let cases: [(AnyView, LayoutFillAxes, Size, Size)] = [
                (
                    AnyView(Rectangle().frame(width: 30, height: 24).frame(width: 300)),
                    .horizontalOnly, Size(width: 300, height: 24), Size(width: 300, height: 0)
                ),
                (
                    AnyView(Rectangle().frame(width: 30, height: 24).frame(height: 70)),
                    .verticalOnly, Size(width: 30, height: 70), Size(width: 0, height: 70)
                ),
            ]
            for (view, expectedAxes, expectedSize, preference) in cases {
                let fixture = absoluteSizingViewFixture(view, rootSize: IntSize(width: 220, height: 60))
                defer { fixture.runtime.root.removeAllChildren() }

                _ = fixture.runtime.renderFrame()

                XCTAssertEqual(fixture.node.resolvedFrame.size, expectedSize)
                XCTAssertEqual(fixture.node.preferredSize, preference)
                XCTAssertEqual(fixture.node.fixedPreferredSizeAxes, expectedAxes)
                XCTAssertEqual(fixture.node.children.count, 1)
                guard let innerFrame = fixture.node.children.first else {
                    return XCTFail("Expected the existing nested fixed frame")
                }
                XCTAssertEqual(innerFrame.preferredSize, Size(width: 30, height: 24))
                XCTAssertEqual(innerFrame.resolvedFrame.size, Size(width: 30, height: 24))
                XCTAssertEqual(innerFrame.fixedPreferredSizeAxes, .both)
            }
        }
    }

    func testFixedSizeOverflowIsNotReclampedByAbsolutePlacement() async {
        await MainActor.run {
            let cases: [(FixedSizeAxes, Size)] = [
                (FixedSizeAxes(horizontal: true, vertical: false), Size(width: 280, height: 60)),
                (FixedSizeAxes(horizontal: true, vertical: true), Size(width: 280, height: 90)),
            ]
            for (axes, expected) in cases {
                let node = ViewNode(preferredSize: Size(width: 280, height: 90), fixedSizeAxes: axes)
                let runtime = absoluteSizingRuntime(child: node, size: IntSize(width: 220, height: 60))
                defer { runtime.root.removeAllChildren() }

                _ = runtime.renderFrame()

                XCTAssertEqual(node.resolvedFrame.size, expected)
                XCTAssertEqual(node.preferredSize, Size(width: 280, height: 90))
                XCTAssertTrue(node.fixedPreferredSizeAxes.isEmpty)
            }
        }
    }

    func testCustomAbsolutePlacementKeepsCallbackRectangle() async {
        await MainActor.run {
            let child = ViewNode(preferredSize: Size(width: 280, height: 90))
            child.fixedPreferredSizeAxes = .both
            let root = ViewNode(children: [child])
            var callbackCount = 0
            root.absoluteChildFrame = { _, _ in
                callbackCount += 1
                return Rect(x: 12, y: 13, width: 77, height: 88)
            }
            let runtime = RetainedViewRuntime(root: root)
            runtime.setRootSize(IntSize(width: 220, height: 60))
            defer {
                root.absoluteChildFrame = nil
                root.removeAllChildren()
            }

            _ = runtime.renderFrame()

            XCTAssertGreaterThan(callbackCount, 0)
            XCTAssertEqual(child.resolvedFrame, Rect(x: 12, y: 13, width: 77, height: 88))
            XCTAssertEqual(child.preferredSize, Size(width: 280, height: 90))
            XCTAssertEqual(child.fixedPreferredSizeAxes, .both)
        }
    }

    func testBareHiddenLabelSliderAcceptsFiniteAbsoluteWidths() async {
        await MainActor.run {
            for width in [Int32(120), Int32(340)] {
                let fixture = absoluteSizingViewFixture(
                    Slider(value: .constant(0.5)).labelsHidden(),
                    rootSize: IntSize(width: width, height: 60))
                defer { fixture.runtime.root.removeAllChildren() }

                _ = fixture.runtime.renderFrame()

                XCTAssertTrue(fixture.runtime.root.children.first === fixture.node)
                XCTAssertEqual(fixture.runtime.root.children.count, 1)
                XCTAssertTrue(fixture.node.accessibilityPrefersSliderBehavior == true)
                XCTAssertEqual(fixture.node.preferredSize, Size(width: 200, height: 28))
                XCTAssertEqual(fixture.node.resolvedFrame.width, Double(width), accuracy: 0.001)
                XCTAssertEqual(fixture.node.resolvedFrame.height, 28, accuracy: 0.001)
                XCTAssertEqual(fixture.node.frame, .zero)
                XCTAssertTrue(fixture.node.fixedPreferredSizeAxes.isEmpty)
                XCTAssertEqual(fixture.node.children.count, 3)
            }
        }
    }

    func testContainerRelativeFrameKeepsConcreteRequestedAxes() async {
        await MainActor.run {
            let fixture = absoluteSizingViewFixture(
                Rectangle().frame(width: 30, height: 24).containerRelativeFrame(.horizontal),
                rootSize: IntSize(width: 220, height: 60),
                canvasSize: Size(width: 300, height: 100))
            defer { fixture.runtime.root.removeAllChildren() }

            _ = fixture.runtime.renderFrame()

            XCTAssertEqual(fixture.runtime.root.frame.size, Size(width: 220, height: 60))
            XCTAssertEqual(fixture.node.resolvedFrame.size, Size(width: 300, height: 24))
            XCTAssertEqual(fixture.node.preferredSize, Size(width: 300, height: 0))
            XCTAssertEqual(fixture.node.fixedPreferredSizeAxes, .horizontalOnly)
            XCTAssertEqual(fixture.node.children.count, 1)
            guard let content = fixture.node.children.first else {
                return XCTFail("Expected the existing container-relative content child")
            }
            XCTAssertEqual(content.resolvedFrame.size, Size(width: 30, height: 24))
        }
    }

    func testFixedPreferredIntentReconcilesAndClearsOnTheSameNode() async {
        await MainActor.run {
            let runtime = RetainedViewRuntime(root: ViewNode())
            let host = ComponentHost(runtime: runtime)
            var axes = LayoutFillAxes.both
            host.setComponents {
                [
                    Component(key: "absolute-sizing-intent") { _ in
                        let node = ViewNode(preferredSize: Size(width: 280, height: 90))
                        node.fixedPreferredSizeAxes = axes
                        node.explicitFrameFillAxes = .both
                        node.forwardsStackMainAxisProposal = true
                        return node
                    }
                ]
            }
            defer { host.setComponents { [] } }
            runtime.setRootSize(IntSize(width: 220, height: 60))
            _ = runtime.renderFrame()
            guard let retained = runtime.root.children.first else {
                return XCTFail("Expected a keyed retained sizing node")
            }
            XCTAssertEqual(retained.resolvedFrame.size, Size(width: 280, height: 90))
            XCTAssertEqual(retained.fixedPreferredSizeAxes, .both)

            let phases: [(LayoutFillAxes, Size)] = [
                (LayoutFillAxes(), Size(width: 220, height: 60)),
                (.horizontalOnly, Size(width: 280, height: 60)),
                (.verticalOnly, Size(width: 220, height: 90)),
                (LayoutFillAxes(), Size(width: 220, height: 60)),
            ]
            for (nextAxes, expected) in phases {
                axes = nextAxes
                host.reload()
                _ = runtime.renderFrame()

                XCTAssertTrue(runtime.root.children.first === retained)
                XCTAssertEqual(runtime.root.children.count, 1)
                XCTAssertEqual(retained.fixedPreferredSizeAxes, nextAxes)
                XCTAssertEqual(retained.resolvedFrame.size, expected)
                XCTAssertEqual(retained.preferredSize, Size(width: 280, height: 90))
                XCTAssertEqual(retained.explicitFrameFillAxes, .both)
                XCTAssertTrue(retained.forwardsStackMainAxisProposal)
            }

            // This separate node proves the marker setter invalidates cached
            // geometry without a reload, changed preference, or other setter.
            let direct = ViewNode(preferredSize: Size(width: 280, height: 90))
            let directRuntime = absoluteSizingRuntime(
                child: direct, size: IntSize(width: 220, height: 60))
            defer { directRuntime.root.removeAllChildren() }
            _ = directRuntime.renderFrame()
            XCTAssertTrue(directRuntime.dirtyFlags.isEmpty)
            XCTAssertEqual(direct.resolvedFrame.size, Size(width: 220, height: 60))

            direct.fixedPreferredSizeAxes = .horizontalOnly
            XCTAssertTrue(directRuntime.dirtyFlags.contains(.layout))
            XCTAssertEqual(direct.preferredSize, Size(width: 280, height: 90))
            _ = directRuntime.renderFrame()
            XCTAssertEqual(direct.resolvedFrame.size, Size(width: 280, height: 60))
            XCTAssertTrue(directRuntime.dirtyFlags.isEmpty)

            direct.fixedPreferredSizeAxes = .horizontalOnly
            XCTAssertTrue(directRuntime.dirtyFlags.isEmpty)

            direct.fixedPreferredSizeAxes = LayoutFillAxes()
            XCTAssertTrue(directRuntime.dirtyFlags.contains(.layout))
            XCTAssertEqual(direct.preferredSize, Size(width: 280, height: 90))
            _ = directRuntime.renderFrame()
            XCTAssertEqual(direct.resolvedFrame.size, Size(width: 220, height: 60))
            XCTAssertTrue(directRuntime.dirtyFlags.isEmpty)

            direct.fixedPreferredSizeAxes = LayoutFillAxes()
            XCTAssertTrue(directRuntime.dirtyFlags.isEmpty)
        }
    }

    func testAnimatedFixedPreferenceUsesCurrentInterpolatedAbsoluteExtent() async {
        await MainActor.run {
            let runtime = RetainedViewRuntime(root: ViewNode())
            let host = ComponentHost(runtime: runtime)
            let context = ViewBuildContext(
                canvasSizeProvider: { Size(width: 120, height: 60) }, invalidateHandler: {})
            let clock = RuntimeTestClock()
            clock.now = 10
            runtime.clock = { clock.now }
            var width = 100.0
            host.setComponents {
                var component = Rectangle()
                    .frame(width: width, height: 24)
                    .animation(.linear(duration: 1), value: width)
                    .makeComponent(context: context)
                component.key = "absolute-sizing-animation"
                return [component]
            }
            defer { host.setComponents { [] } }
            runtime.setRootSize(IntSize(width: 120, height: 60))
            _ = runtime.renderFrame()
            guard let retained = runtime.root.children.first else {
                return XCTFail("Expected the animated fixed-frame wrapper")
            }
            XCTAssertEqual(retained.resolvedFrame.size, Size(width: 100, height: 24))

            width = 200
            host.reload()
            guard let animation = retained.animationStates[.preferredWidth] else {
                return XCTFail("Expected the existing preferred-width animation channel")
            }
            XCTAssertEqual(animation.startValue, 100, accuracy: 0.001)
            XCTAssertEqual(animation.endValue, 200, accuracy: 0.001)
            XCTAssertEqual(animation.startTime, 10, accuracy: 0.001)
            XCTAssertEqual(animation.duration, 1, accuracy: 0.001)

            clock.now = 10.5
            _ = runtime.tickAnimations(at: clock.now)
            _ = runtime.renderFrame()
            XCTAssertTrue(runtime.root.children.first === retained)
            XCTAssertEqual(retained.preferredSize, Size(width: 150, height: 24))
            XCTAssertEqual(retained.resolvedFrame.size, Size(width: 150, height: 24))
            XCTAssertEqual(retained.fixedPreferredSizeAxes, .both)
            guard let content = retained.children.first else {
                return XCTFail("Expected the animated wrapper's existing content child")
            }
            XCTAssertEqual(content.resolvedFrame.size, Size(width: 150, height: 24))

            host.reload()
            _ = runtime.renderFrame()
            XCTAssertTrue(runtime.root.children.first === retained)
            XCTAssertEqual(retained.animationStates[.preferredWidth]?.startTime, animation.startTime)
            XCTAssertEqual(retained.preferredSize, Size(width: 150, height: 24))
            XCTAssertEqual(retained.resolvedFrame.size, Size(width: 150, height: 24))

            clock.now = 11
            _ = runtime.tickAnimations(at: clock.now)
            _ = runtime.renderFrame()
            XCTAssertEqual(retained.preferredSize, Size(width: 200, height: 24))
            XCTAssertEqual(retained.resolvedFrame.size, Size(width: 200, height: 24))
            XCTAssertFalse(runtime.hasActiveAnimations)
        }
    }
}

@MainActor
private func absoluteSizingRuntime(child: ViewNode, size: IntSize) -> RetainedViewRuntime {
    let runtime = RetainedViewRuntime(root: ViewNode(children: [child]))
    runtime.setRootSize(size)
    return runtime
}

@MainActor
private func absoluteSizingViewFixture<Content: View>(
    _ view: Content, rootSize: IntSize, canvasSize: Size? = nil
) -> (runtime: RetainedViewRuntime, node: ViewNode) {
    let runtime = RetainedViewRuntime(root: ViewNode())
    let size = canvasSize ?? Size(width: Double(rootSize.width), height: Double(rootSize.height))
    let context = ViewBuildContext(canvasSizeProvider: { size }, invalidateHandler: {})
    let node = view.makeComponent(context: context).makeNode(runtime: runtime)
    runtime.root.addChild(node)
    runtime.setRootSize(rootSize)
    return (runtime, node)
}
