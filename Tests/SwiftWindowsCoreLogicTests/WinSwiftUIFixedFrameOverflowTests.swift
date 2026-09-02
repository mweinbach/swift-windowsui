import Foundation
import SwiftWindowsCore
import SwiftWindowsGraphics
import SwiftWindowsLayout
@preconcurrency import XCTest

@testable import SwiftWindowsUI
@testable import WinSwiftUI

/// Analytic layout and retained-scene regressions. These are not captured
/// macOS pixels or a claim about every ordinary stack's overflow behavior.
@MainActor
final class WinSwiftUIFixedFrameOverflowTests: XCTestCase {
    private static let uneven = UnevenRoundedRectangle(
        topLeadingRadius: 40, bottomLeadingRadius: 0,
        bottomTrailingRadius: 8, topTrailingRadius: 4, style: .circular)

    func testBottomAlignedCropKeepsTheOriginalUnevenClipBounds() async throws {
        let result = snapshot(
            Rectangle().fill(Color.white).frame(width: 100, height: 100)
                .clipShape(Self.uneven)
                .frame(width: 100, height: 96, alignment: .bottomLeading)
                .clipped(),
            size: IntSize(width: 104, height: 100))
        let crop = try firstChild(of: result.runtime.root)
        let frame = try firstChild(of: crop)
        let clip = try firstChild(of: frame)
        let inner = try firstChild(of: clip)
        XCTAssertEqual(crop.resolvedFrame, Rect(x: 0, y: 0, width: 100, height: 96))
        XCTAssertEqual(frame.resolvedFrame, Rect(x: 0, y: 0, width: 100, height: 96))
        XCTAssertEqual(clip.resolvedFrame, Rect(x: 0, y: -4, width: 100, height: 100))
        XCTAssertEqual(inner.resolvedFrame, Rect(x: 0, y: 0, width: 100, height: 100))
        XCTAssertEqual(inner.preferredSize, Size(width: 100, height: 100))
        XCTAssertTrue(crop.forwardsChildSize)
        XCTAssertTrue(clip.forwardsChildSize)
        assertClip(
            try whiteQuad(in: result.scene),
            shape: Rect(x: 0, y: -4, width: 100, height: 100),
            rejection: Rect(x: 0, y: 0, width: 100, height: 96), radii: (40, 4, 8, 0))
        XCTAssertTrue(result.scene.imageRenderPasses.isEmpty)
        let surface = raster(result)
        // This sample is inside the translated original arc but outside the
        // incorrectly reanchored arc, even before antialiasing is considered.
        XCTAssertEqual(alpha(surface, x: 8, y: 13), 255)
        XCTAssertEqual(alpha(surface, x: 4, y: 8), 0)
        XCTAssertEqual(alpha(surface, x: 1, y: 94), 255)
        XCTAssertEqual(alpha(surface, x: 50, y: 96), 0)
        XCTAssertFalse(result.runtime.hasPendingLayout)
    }

    func testThinTopAlignedCropDoesNotShrinkTheRoundedOwner() async throws {
        let result = snapshot(
            Rectangle().fill(Color.white).frame(width: 100, height: 100)
                .clipShape(Self.uneven)
                .frame(width: 100, height: 4, alignment: .topLeading)
                .clipped(),
            size: IntSize(width: 104, height: 8))
        let crop = try firstChild(of: result.runtime.root)
        let frame = try firstChild(of: crop)
        let clip = try firstChild(of: frame)
        XCTAssertEqual(crop.resolvedFrame.size, Size(width: 100, height: 4))
        XCTAssertEqual(clip.resolvedFrame, Rect(x: 0, y: 0, width: 100, height: 100))
        assertClip(
            try whiteQuad(in: result.scene),
            shape: Rect(x: 0, y: 0, width: 100, height: 100),
            rejection: Rect(x: 0, y: 0, width: 100, height: 4), radii: (40, 4, 8, 0))
        let surface = raster(result)
        XCTAssertEqual(alpha(surface, x: 2, y: 1), 0)
        XCTAssertEqual(alpha(surface, x: 60, y: 1), 255)
        XCTAssertEqual(alpha(surface, x: 60, y: 4), 0)
        XCTAssertTrue(result.scene.imageRenderPasses.isEmpty)
    }

    func testCenteredOnePixelCropKeepsOriginalUniformCornerCoverage() async throws {
        let result = snapshot(
            Rectangle().fill(Color.white).frame(width: 20, height: 20)
                .clipShape(RoundedRectangle(cornerRadius: 5, style: .circular))
                .frame(width: 18, height: 18, alignment: .center)
                .frame(width: 1, height: 1, alignment: .topLeading)
                .clipped()
                .padding(1),
            size: IntSize(width: 3, height: 3))
        let padding = try firstChild(of: result.runtime.root)
        let crop = try firstChild(of: padding)
        let one = try firstChild(of: crop)
        let eighteen = try firstChild(of: one)
        let clip = try firstChild(of: eighteen)
        XCTAssertEqual(crop.resolvedFrame, Rect(x: 1, y: 1, width: 1, height: 1))
        XCTAssertEqual(one.resolvedFrame, Rect(x: 0, y: 0, width: 1, height: 1))
        XCTAssertEqual(eighteen.resolvedFrame, Rect(x: 0, y: 0, width: 18, height: 18))
        XCTAssertEqual(clip.resolvedFrame, Rect(x: -1, y: -1, width: 20, height: 20))
        assertClip(
            try whiteQuad(in: result.scene), shape: Rect(x: 0, y: 0, width: 20, height: 20),
            rejection: Rect(x: 1, y: 1, width: 1, height: 1), radii: (5, 5, 5, 5))
        let surface = raster(result)
        // The original shape origin is even and the crop origin is odd on
        // both axes. Circle distance on that screen-aligned derivative quad
        // gives coverage about 0.537893, independently quantized to 137/255.
        XCTAssertEqual(alpha(surface, x: 1, y: 1), 137)
        for point in [(0, 1), (2, 1), (1, 0), (1, 2)] {
            XCTAssertEqual(alpha(surface, x: point.0, y: point.1), 0)
        }
        XCTAssertTrue(result.scene.imageRenderPasses.isEmpty)
    }

    func testAllNineFrameAlignmentsPermitNegativeOverflowOffsets() async throws {
        let cases: [(Alignment, Point)] = [
            (.topLeading, Point(x: 0, y: 0)),
            (.top, Point(x: -20, y: 0)),
            (.topTrailing, Point(x: -40, y: 0)),
            (.leading, Point(x: 0, y: -30)),
            (.center, Point(x: -20, y: -30)),
            (.trailing, Point(x: -40, y: -30)),
            (.bottomLeading, Point(x: 0, y: -60)),
            (.bottom, Point(x: -20, y: -60)),
            (.bottomTrailing, Point(x: -40, y: -60)),
        ]
        for (alignment, origin) in cases {
            let result = snapshot(
                Rectangle().frame(width: 100, height: 100)
                    .frame(width: 60, height: 40, alignment: alignment))
            let outer = try firstChild(of: result.runtime.root)
            let inner = try firstChild(of: outer)
            XCTAssertEqual(outer.resolvedFrame.size, Size(width: 60, height: 40))
            XCTAssertEqual(inner.resolvedFrame, Rect(origin: origin, size: Size(width: 100, height: 100)))
            XCTAssertEqual(try firstChild(of: inner).resolvedFrame.size, Size(width: 100, height: 100))
            XCTAssertEqual(inner.preferredSize, Size(width: 100, height: 100))
            XCTAssertEqual(inner.frame, .zero)
        }
    }

    func testSemanticHorizontalAlignmentResolvesEachInheritedDirection() async throws {
        for direction in [LayoutDirection.leftToRight, .rightToLeft, .leftToRight] {
            for leading in [true, false] {
                let result = snapshot(
                    Rectangle().frame(width: 100, height: 100)
                        .frame(
                            width: 60, height: 40,
                            alignment: leading ? .bottomLeading : .bottomTrailing
                        )
                        .environment(\.layoutDirection, direction))
                let outer = try firstChild(of: result.runtime.root)
                let inner = try firstChild(of: outer)
                let physicalLeft = leading == (direction == .leftToRight)
                XCTAssertEqual(
                    inner.resolvedFrame,
                    Rect(x: physicalLeft ? 0 : -40, y: -60, width: 100, height: 100))
            }
        }
    }

    func testWidthOnlyAndHeightOnlyFramesLeaveTheOtherAxisMeasured() async throws {
        let cases: [(AnyView, Size, Rect)] = [
            (
                AnyView(Rectangle().frame(width: 80, height: 30).frame(width: 40)),
                Size(width: 40, height: 30), Rect(x: -20, y: 0, width: 80, height: 30)
            ),
            (
                AnyView(Rectangle().frame(width: 80, height: 30).frame(height: 15)),
                Size(width: 80, height: 15), Rect(x: 0, y: -7.5, width: 80, height: 30)
            ),
        ]
        for (view, size, innerRect) in cases {
            let result = snapshot(view)
            let outer = try firstChild(of: result.runtime.root)
            XCTAssertEqual(outer.resolvedFrame.size, size)
            XCTAssertEqual(try firstChild(of: outer).resolvedFrame, innerRect)
        }
    }

    func testFlexibleChildrenStillAcceptTheActualFixedFrameProposal() async throws {
        let cases = [AnyView(Rectangle()), AnyView(Color.white), AnyView(Capsule())]
        for view in cases {
            let result = snapshot(view.frame(width: 100, height: 4))
            let outer = try firstChild(of: result.runtime.root)
            let child = try firstChild(of: outer)
            XCTAssertEqual(outer.resolvedFrame.size, Size(width: 100, height: 4))
            XCTAssertEqual(child.resolvedFrame, Rect(x: 0, y: 0, width: 100, height: 4))
            XCTAssertNil(child.preferredSize)
        }
    }

    func testIntrinsicBitmapKeepsItsSizeInsideALargerFixedFrame() async throws {
        let bitmap = BitmapSurface(
            width: 2, height: 2, bytesPerRow: 8, pixels: Data(repeating: 255, count: 16))
        let result = snapshot(Image(bitmap: bitmap).frame(width: 10, height: 8))
        let outer = try firstChild(of: result.runtime.root)
        let child = try firstChild(of: outer)
        XCTAssertEqual(child.resolvedFrame, Rect(x: 4, y: 3, width: 2, height: 2))
        XCTAssertEqual(child.preferredSize, Size(width: 2, height: 2))
        XCTAssertTrue(child.layoutFillAxes.isEmpty)
    }

    func testEachPublicClipWrapperPreservesItsAcceptedChildSize() async throws {
        let fixed = Rectangle().frame(width: 100, height: 100)
        let cases = [
            AnyView(fixed.clipped()),
            AnyView(fixed.cornerRadius(5)),
            AnyView(fixed.clipShape(Rectangle())),
        ]
        for view in cases {
            let result = snapshot(view.frame(width: 60, height: 40, alignment: .bottomTrailing))
            let outer = try firstChild(of: result.runtime.root)
            let clip = try firstChild(of: outer)
            let inner = try firstChild(of: clip)
            XCTAssertTrue(clip.forwardsChildSize)
            XCTAssertTrue(clip.clipsToBounds)
            XCTAssertNil(clip.preferredSize)
            XCTAssertTrue(clip.fixedPreferredSizeAxes.isEmpty)
            XCTAssertEqual(clip.resolvedFrame, Rect(x: -40, y: -60, width: 100, height: 100))
            XCTAssertEqual(inner.resolvedFrame, Rect(x: 0, y: 0, width: 100, height: 100))
        }
    }

    func testTransparentClipsTrackLiveDimensionsOnTheSameWrappers() async throws {
        let runtime = RetainedViewRuntime(clearColor: .clear, root: ViewNode())
        runtime.setRootSize(IntSize(width: 120, height: 120))
        let host = ComponentHost(runtime: runtime)
        let context = ViewBuildContext(
            canvasSizeProvider: { Size(width: 120, height: 120) }, invalidateHandler: {})
        var width = 100.0
        var height = 100.0
        host.setComponents {
            [
                Rectangle().fill(Color.white).frame(width: width, height: height)
                    .clipShape(Self.uneven)
                    .frame(width: 60, height: 40, alignment: .bottomTrailing)
                    .clipped().makeComponent(context: context)
            ]
        }
        defer { host.setComponents { [] } }
        _ = runtime.renderScene()
        let crop = try firstChild(of: runtime.root)
        let frame = try firstChild(of: crop)
        let clip = try firstChild(of: frame)
        let inner = try firstChild(of: clip)
        for dimensions in [(100.0, 100.0), (80.0, 90.0), (120.0, 110.0), (100.0, 100.0)] {
            width = dimensions.0
            height = dimensions.1
            host.reload()
            let scene = runtime.renderScene()
            XCTAssertTrue(try firstChild(of: runtime.root) === crop)
            XCTAssertTrue(try firstChild(of: frame) === clip)
            XCTAssertTrue(try firstChild(of: clip) === inner)
            XCTAssertNil(clip.preferredSize)
            XCTAssertEqual(clip.resolvedFrame, Rect(x: 60 - width, y: 40 - height, width: width, height: height))
            XCTAssertEqual(inner.resolvedFrame, Rect(x: 0, y: 0, width: width, height: height))
            assertClip(
                try whiteQuad(in: scene),
                shape: Rect(x: 60 - width, y: 40 - height, width: width, height: height),
                rejection: Rect(x: 0, y: 0, width: 60, height: 40), radii: (40, 4, 8, 0))
            XCTAssertFalse(runtime.hasPendingLayout)
        }
    }

    func testAnimatedFixedPreferenceDoesNotLeaveCopiedClipDimensions() async throws {
        let runtime = RetainedViewRuntime(clearColor: .clear, root: ViewNode())
        runtime.setRootSize(IntSize(width: 120, height: 120))
        let host = ComponentHost(runtime: runtime)
        let context = ViewBuildContext(
            canvasSizeProvider: { Size(width: 120, height: 120) }, invalidateHandler: {})
        let clock = OverflowClock()
        runtime.clock = { clock.now }
        var width = 100.0
        host.setComponents {
            [
                Rectangle().fill(Color.white).frame(width: width, height: 100)
                    .animation(.linear(duration: 1), value: width)
                    .clipShape(Self.uneven)
                    .frame(width: 80, height: 96, alignment: .bottomTrailing)
                    .clipped().makeComponent(context: context)
            ]
        }
        defer { host.setComponents { [] } }
        _ = runtime.renderScene()
        let crop = try firstChild(of: runtime.root)
        let outer = try firstChild(of: crop)
        let clip = try firstChild(of: outer)
        let inner = try firstChild(of: clip)
        width = 140
        host.reload()
        let animation = try XCTUnwrap(inner.animationStates[.preferredWidth])
        XCTAssertEqual(animation.startValue, 100)
        XCTAssertEqual(animation.endValue, 140)
        XCTAssertEqual(animation.startTime, 10)
        clock.now = 10.5
        _ = runtime.tickAnimations(at: clock.now)
        let scene = runtime.renderScene()
        XCTAssertTrue(try firstChild(of: clip) === inner)
        XCTAssertNil(clip.preferredSize)
        XCTAssertEqual(inner.preferredSize, Size(width: 120, height: 100))
        XCTAssertEqual(inner.resolvedFrame.size, Size(width: 120, height: 100))
        XCTAssertEqual(clip.resolvedFrame, Rect(x: -40, y: -4, width: 120, height: 100))
        assertClip(
            try whiteQuad(in: scene), shape: Rect(x: -40, y: -4, width: 120, height: 100),
            rejection: Rect(x: 0, y: 0, width: 80, height: 96), radii: (40, 4, 8, 0))
        clock.now = 11
        _ = runtime.tickAnimations(at: clock.now)
        _ = runtime.renderScene()
        XCTAssertEqual(clip.resolvedFrame, Rect(x: -60, y: -4, width: 140, height: 100))
        XCTAssertFalse(runtime.hasActiveAnimations)
    }

    func testTransparentFlagReconcilesAndClearsOnTheSameNode() async throws {
        let runtime = RetainedViewRuntime(root: ViewNode())
        runtime.setRootSize(IntSize(width: 40, height: 30))
        let host = ComponentHost(runtime: runtime)
        var transparent = false
        host.setComponents {
            [
                Component(key: "fixed-frame-transparent-flag") { _ in
                    self.clippingStack(transparent: transparent)
                }
            ]
        }
        defer { host.setComponents { [] } }
        _ = runtime.renderFrame()
        let retained = try firstChild(of: runtime.root)
        XCTAssertEqual(retained.resolvedFrame.size, Size(width: 40, height: 30))
        for value in [true, false, true, false] {
            transparent = value
            host.reload()
            _ = runtime.renderFrame()
            XCTAssertTrue(try firstChild(of: runtime.root) === retained)
            XCTAssertEqual(retained.forwardsChildSize, value)
            XCTAssertEqual(
                retained.resolvedFrame.size,
                value ? Size(width: 100, height: 100) : Size(width: 40, height: 30))
        }
    }

    func testTransparentFlagInvalidatesCachedLayoutOnlyWhenItChanges() async {
        let node = clippingStack(transparent: false)
        let runtime = RetainedViewRuntime(root: ViewNode(children: [node]))
        runtime.setRootSize(IntSize(width: 40, height: 30))
        defer { runtime.root.removeAllChildren() }
        _ = runtime.renderFrame()
        XCTAssertTrue(runtime.dirtyFlags.isEmpty)
        XCTAssertEqual(node.resolvedFrame.size, Size(width: 40, height: 30))
        node.forwardsChildSize = true
        XCTAssertTrue(runtime.dirtyFlags.contains(.layout))
        _ = runtime.renderFrame()
        XCTAssertEqual(node.resolvedFrame.size, Size(width: 100, height: 100))
        XCTAssertTrue(runtime.dirtyFlags.isEmpty)
        node.forwardsChildSize = true
        XCTAssertTrue(runtime.dirtyFlags.isEmpty)
        node.forwardsChildSize = false
        XCTAssertTrue(runtime.dirtyFlags.contains(.layout))
        _ = runtime.renderFrame()
        XCTAssertEqual(node.resolvedFrame.size, Size(width: 40, height: 30))
        XCTAssertTrue(runtime.dirtyFlags.isEmpty)
    }

    func testOrdinaryClippingStackStillAbsorbsItsAssignedCompression() async throws {
        let node = clippingStack(transparent: false)
        let runtime = RetainedViewRuntime(root: ViewNode(children: [node]))
        runtime.setRootSize(IntSize(width: 100, height: 4))
        defer { runtime.root.removeAllChildren() }
        _ = runtime.renderFrame()
        XCTAssertFalse(node.forwardsChildSize)
        XCTAssertEqual(node.resolvedFrame.size, Size(width: 100, height: 4))
        XCTAssertEqual(try firstChild(of: node).resolvedFrame, Rect(x: 0, y: 0, width: 100, height: 4))
    }

    func testOrdinaryPreferredStackChildrenStillShrinkProportionally() async {
        for axis in [StackAxis.vertical, .horizontal] {
            let preferred = axis == .vertical ? Size(width: 100, height: 60) : Size(width: 60, height: 100)
            let children = [ViewNode(preferredSize: preferred), ViewNode(preferredSize: preferred)]
            let node = ViewNode(
                layoutMode: .stack(StackLayout(axis: axis, alignment: .stretch)), children: children)
            let runtime = RetainedViewRuntime(root: ViewNode(children: [node]))
            runtime.setRootSize(axis == .vertical ? IntSize(width: 100, height: 60) : IntSize(width: 60, height: 100))
            defer { runtime.root.removeAllChildren() }
            _ = runtime.renderFrame()
            for child in children {
                XCTAssertTrue(child.fixedPreferredSizeAxes.isEmpty)
                XCTAssertEqual(
                    child.resolvedFrame.size,
                    axis == .vertical ? Size(width: 100, height: 30) : Size(width: 30, height: 100))
            }
            XCTAssertEqual(
                children[1].resolvedFrame.origin,
                axis == .vertical ? Point(x: 0, y: 30) : Point(x: 30, y: 0))
        }
    }

    func testContainerRelativeFixedContentAlsoPreservesItsDeclaredExtent() async throws {
        let result = snapshot(
            Rectangle().containerRelativeFrame([.horizontal, .vertical]) { _, _ in 100 }
                .clipShape(Rectangle())
                .frame(width: 60, height: 40, alignment: .bottomTrailing))
        let outer = try firstChild(of: result.runtime.root)
        let clip = try firstChild(of: outer)
        let relative = try firstChild(of: clip)
        XCTAssertEqual(relative.fixedPreferredSizeAxes, .both)
        XCTAssertEqual(relative.preferredSize, Size(width: 100, height: 100))
        XCTAssertEqual(clip.resolvedFrame, Rect(x: -40, y: -60, width: 100, height: 100))
        XCTAssertEqual(relative.resolvedFrame.size, Size(width: 100, height: 100))
    }

    func testFixedDimensionsOfferAValidContentProposalBelowAMinimum() async throws {
        let result = snapshot(Rectangle().frame(width: 80, height: 30))
        let frame = try firstChild(of: result.runtime.root)
        let content = try firstChild(of: frame)
        frame.layoutConstraints = LayoutConstraints(minWidth: 120, minHeight: 90)
        XCTAssertEqual(frame.intrinsicContentSize(), Size(width: 80, height: 30))
        let proposal = try XCTUnwrap(content.cachedMeasureKey).constraints
        XCTAssertEqual(proposal.maxWidth, 80)
        XCTAssertEqual(proposal.maxHeight, 30)
        XCTAssertLessThanOrEqual(proposal.minWidth, proposal.maxWidth)
        XCTAssertLessThanOrEqual(proposal.minHeight, proposal.maxHeight)
    }

    func testInvalidMarkedPreferencesKeepTheExistingUnmarkedPolicy() async {
        for extent in [0.0, -1.0, Double.infinity, -Double.infinity, Double.nan] {
            let plain = ViewNode(preferredSize: Size(width: extent, height: 20))
            let marked = ViewNode(preferredSize: Size(width: extent, height: 20))
            marked.fixedPreferredSizeAxes = .horizontalOnly
            for node in [plain, marked] {
                node.layoutConstraints = LayoutConstraints(maxWidth: 40, maxHeight: 30)
            }
            XCTAssertEqual(marked.intrinsicContentSize(), plain.intrinsicContentSize())
        }
    }

    func testTransparentFlagDoesNotBypassAnExplicitLocalSizePolicy() async {
        let policies: [@MainActor (ViewNode) -> Void] = [
            { $0.preferredSize = Size(width: 30, height: 20) },
            { $0.frame = Rect(x: 0, y: 0, width: 30, height: 20) },
            { $0.layoutConstraints = LayoutConstraints(maxWidth: 30, maxHeight: 20) },
            { $0.layoutFillAxes = .both },
        ]
        for policy in policies {
            var sizes: [Size] = []
            var childFrames: [Rect] = []
            for transparent in [false, true] {
                let node = clippingStack(transparent: transparent)
                policy(node)
                let runtime = RetainedViewRuntime(root: ViewNode(children: [node]))
                runtime.setRootSize(IntSize(width: 40, height: 30))
                _ = runtime.renderFrame()
                sizes.append(node.resolvedFrame.size)
                childFrames.append(node.children[0].resolvedFrame)
                runtime.root.removeAllChildren()
            }
            XCTAssertEqual(sizes[0], sizes[1])
            XCTAssertEqual(childFrames[0], childFrames[1])
        }
    }

    func testTransparentFlagDoesNotAdmitHiddenOrMultipleChildren() async {
        for hidden in [false, true] {
            var results: [(Size, [Rect])] = []
            for transparent in [false, true] {
                let node = clippingStack(transparent: transparent)
                if hidden {
                    node.children[0].isHidden = true
                } else {
                    let second = ViewNode(preferredSize: Size(width: 100, height: 100))
                    second.fixedPreferredSizeAxes = .both
                    node.addChild(second)
                }
                let runtime = RetainedViewRuntime(root: ViewNode(children: [node]))
                runtime.setRootSize(IntSize(width: 40, height: 30))
                _ = runtime.renderFrame()
                results.append((node.resolvedFrame.size, node.children.map(\.resolvedFrame)))
                runtime.root.removeAllChildren()
            }
            XCTAssertEqual(results[0].0, results[1].0)
            XCTAssertEqual(results[0].1, results[1].1)
        }
    }

    func testTransparentFlagDoesNotAdmitDifferentContainerLayouts() async {
        let layouts: [ViewLayoutMode] = [
            .absolute,
            .stack(.horizontal()),
            .stack(.vertical(padding: EdgeInsets(top: 2, leading: 2, bottom: 2, trailing: 2))),
            .stack(.vertical(spacing: 5)),
            .stack(.vertical(distribution: .fillEqually)),
        ]
        for layout in layouts {
            var results: [(Size, Rect)] = []
            for transparent in [false, true] {
                let node = clippingStack(transparent: transparent)
                node.layoutMode = layout
                let runtime = RetainedViewRuntime(root: ViewNode(children: [node]))
                runtime.setRootSize(IntSize(width: 40, height: 30))
                _ = runtime.renderFrame()
                results.append((node.resolvedFrame.size, node.children[0].resolvedFrame))
                runtime.root.removeAllChildren()
            }
            XCTAssertEqual(results[0].0, results[1].0)
            XCTAssertEqual(results[0].1, results[1].1)
        }
    }

    func testWrappingTextMeasuresAtTheInnerFixedWidthBeforeOverflowPlacement() async throws {
        let text = Text("Several words wrap using the width declared by the inner frame.")
        let standalone = snapshot(text.frame(width: 120))
        let nested = snapshot(text.frame(width: 120).frame(width: 60))
        let baseline = try firstChild(of: standalone.runtime.root)
        let outer = try firstChild(of: nested.runtime.root)
        let inner = try firstChild(of: outer)
        let content = try firstChild(of: inner)
        XCTAssertEqual(inner.resolvedFrame.width, 120)
        XCTAssertEqual(inner.resolvedFrame.origin.x, -30)
        XCTAssertEqual(inner.resolvedFrame.height, baseline.resolvedFrame.height)
        XCTAssertEqual(outer.resolvedFrame.height, baseline.resolvedFrame.height)
        XCTAssertEqual(try XCTUnwrap(content.cachedMeasureKey).constraints.maxWidth, 120)
        XCTAssertGreaterThan(baseline.resolvedFrame.height, 0)
    }

    func testTransparentFlagAddsNoReferenceBearingSourcePayload() async {
        let node = ViewNode()
        let before = node.retainedSourcePayloadFields
        node.forwardsChildSize = true
        XCTAssertEqual(node.retainedSourcePayloadFields, before)
        XCTAssertFalse(node.retainedSourcePayloadFields.contains(\.forwardsChildSize))
        node.forwardsChildSize = false
        XCTAssertEqual(node.retainedSourcePayloadFields, before)
    }

    private func snapshot<Content: View>(
        _ content: Content, size: IntSize = IntSize(width: 200, height: 200)
    ) -> WinSwiftUIRenderSnapshot {
        WinSwiftUIRendererSnapshotter.snapshot(
            of: content, size: size, displayScale: 1, colorScheme: .dark, clearColor: .clear)
    }

    private func firstChild(
        of node: ViewNode, file: StaticString = #filePath, line: UInt = #line
    ) throws -> ViewNode {
        XCTAssertEqual(node.children.count, 1, file: file, line: line)
        return try XCTUnwrap(node.children.first, file: file, line: line)
    }

    private func whiteQuad(
        in scene: GPUIScene, file: StaticString = #filePath, line: UInt = #line
    ) throws -> QuadPrimitive {
        let quads = scene.layers.flatMap(\.quads).filter {
            $0.startR == 1 && $0.startG == 1 && $0.startB == 1 && $0.startA == 1
        }
        XCTAssertEqual(quads.count, 1, file: file, line: line)
        return try XCTUnwrap(quads.first, file: file, line: line)
    }

    private func assertClip(
        _ quad: QuadPrimitive, shape: Rect, rejection: Rect,
        radii: (Double, Double, Double, Double),
        file: StaticString = #filePath, line: UInt = #line
    ) {
        XCTAssertEqual(quad.clipShapeBounds, shape, file: file, line: line)
        XCTAssertEqual(quad.clipX, Float(rejection.origin.x), file: file, line: line)
        XCTAssertEqual(quad.clipY, Float(rejection.origin.y), file: file, line: line)
        XCTAssertEqual(quad.clipWidth, Float(rejection.width), file: file, line: line)
        XCTAssertEqual(quad.clipHeight, Float(rejection.height), file: file, line: line)
        XCTAssertEqual(quad.clipCornerRadiusTopLeft, Float(radii.0), file: file, line: line)
        XCTAssertEqual(quad.clipCornerRadiusTopRight, Float(radii.1), file: file, line: line)
        XCTAssertEqual(quad.clipCornerRadiusBottomRight, Float(radii.2), file: file, line: line)
        XCTAssertEqual(quad.clipCornerRadiusBottomLeft, Float(radii.3), file: file, line: line)
    }

    private func raster(_ snapshot: WinSwiftUIRenderSnapshot) -> BitmapSurface {
        GPUIRawSceneRasterizer.rasterize(snapshot.scene, size: snapshot.size)
    }

    private func alpha(_ surface: BitmapSurface, x: Int, y: Int) -> UInt8 {
        surface.pixels[y * Int(surface.bytesPerRow) + x * 4 + 3]
    }

    private func clippingStack(transparent: Bool) -> ViewNode {
        let content = ViewNode(preferredSize: Size(width: 100, height: 100))
        content.fixedPreferredSizeAxes = .both
        let node = ViewNode(
            clipsToBounds: true, layoutMode: .stack(.vertical(alignment: .stretch)), children: [content])
        node.forwardsChildSize = transparent
        return node
    }

    private final class OverflowClock { var now = 10.0 }
}
