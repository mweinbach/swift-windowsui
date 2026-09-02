import Foundation
import SwiftWindowsCore
import SwiftWindowsGraphics
@preconcurrency import XCTest

@testable import SwiftWindowsUI
@testable import WinSwiftUI

/// Circular interaction geometry only. Visual clips, continuous corners,
/// partial-trim hit geometry and inherited container geometry remain separate.
@MainActor
final class WinSwiftUIUnevenRoundedRectangleContentShapeTests: XCTestCase {
    private static let size = Size(width: 120, height: 80)
    private static let bounds = Rect(origin: .zero, size: size)
    private static let red = Color(red: 1, green: 0, blue: 0, alpha: 1)

    func testOneRoundedCornerLeavesTheOtherThreeCornersInteractive() async {
        let style = RetainedContentShapeStyle.unevenRoundedRectangle(
            RetainedCornerRadii(bottomRight: 20))

        for point in [Point(x: 1, y: 1), Point(x: 119, y: 1), Point(x: 1, y: 79)] {
            XCTAssertTrue(style.contains(point, in: Self.bounds))
        }
        XCTAssertFalse(style.contains(Point(x: 119, y: 79), in: Self.bounds))
        XCTAssertTrue(style.contains(Point(x: 100, y: 60), in: Self.bounds))
        XCTAssertTrue(style.contains(Point(x: 60, y: 40), in: Self.bounds))
    }

    func testFourDifferentRadiiUseTheirTranslatedPhysicalCorners() async {
        let rect = Rect(x: 10, y: 20, width: 120, height: 80)
        let style = RetainedContentShapeStyle.unevenRoundedRectangle(
            RetainedCornerRadii(topLeft: 6, topRight: 14, bottomRight: 18, bottomLeft: 10))
        let inside = [
            Point(x: 12, y: 24), Point(x: 126, y: 30),
            Point(x: 124, y: 91), Point(x: 14, y: 95),
        ]
        let outside = [
            Point(x: 10.5, y: 20.5), Point(x: 129.5, y: 20.5),
            Point(x: 129.5, y: 99.5), Point(x: 10.5, y: 99.5),
        ]
        for point in inside { XCTAssertTrue(style.contains(point, in: rect)) }
        for point in outside { XCTAssertFalse(style.contains(point, in: rect)) }

        // Three units from a square corner are inside radius 6 or 10, but
        // outside radius 14 or 18. A maximum-radius fallback fails this split.
        XCTAssertTrue(style.contains(Point(x: 13, y: 23), in: rect))
        XCTAssertFalse(style.contains(Point(x: 127, y: 23), in: rect))
        XCTAssertFalse(style.contains(Point(x: 127, y: 97), in: rect))
        XCTAssertTrue(style.contains(Point(x: 13, y: 97), in: rect))
    }

    func testEqualFiniteRadiiExactlyMatchTheExistingUniformPredicate() async {
        let rectangles = [
            Self.bounds,
            Rect(x: -13.25, y: 7.5, width: 31.5, height: 75.25),
        ]
        let fractions = [-0.01, 0, 0.001, 0.1, 0.25, 0.5, 0.75, 0.9, 0.999, 1, 1.01]
        let radii = [-4.0, 0, 0.125, 3.25, 20, 40, 400, Double.greatestFiniteMagnitude]
        for rect in rectangles {
            for radius in radii {
                let uniform = RetainedContentShapeStyle.roundedRectangle(radius)
                let uneven = RetainedContentShapeStyle.unevenRoundedRectangle(
                    RetainedCornerRadii(uniform: radius))
                for x in fractions {
                    for y in fractions {
                        let point = Point(
                            x: rect.minX + x * rect.size.width,
                            y: rect.minY + y * rect.size.height)
                        XCTAssertEqual(uneven.contains(point, in: rect), uniform.contains(point, in: rect))
                    }
                }
            }
        }
    }

    func testArcBoundaryAndHalfOpenFrameEdgesKeepTheExistingPolicy() async {
        let rect = Rect(x: 10, y: 20, width: 120, height: 80)
        let style = RetainedContentShapeStyle.unevenRoundedRectangle(RetainedCornerRadii(topLeft: 5))

        // Relative to center (15,25), (-3,-4) lies exactly on radius 5.
        XCTAssertTrue(style.contains(Point(x: 12, y: 21), in: rect))
        XCTAssertFalse(style.contains(Point(x: 11.99, y: 21), in: rect))
        XCTAssertTrue(style.contains(Point(x: 12.01, y: 21), in: rect))
        XCTAssertTrue(style.contains(Point(x: 15, y: 20), in: rect))
        XCTAssertTrue(style.contains(Point(x: 10, y: 25), in: rect))
        XCTAssertFalse(style.contains(Point(x: 130, y: 60), in: rect))
        XCTAssertFalse(style.contains(Point(x: 70, y: 100), in: rect))
        XCTAssertFalse(style.contains(Point(x: 9.99, y: 60), in: rect))
        XCTAssertFalse(style.contains(Point(x: 70, y: 19.99), in: rect))

        for size in [
            Size(width: 0, height: 80), Size(width: 120, height: 0),
            Size(width: 0, height: 0), Size(width: -10, height: 80), Size(width: 120, height: -10),
        ] {
            let empty = Rect(origin: Point(x: 10, y: 20), size: size)
            XCTAssertFalse(style.contains(Point(x: 10, y: 20), in: empty))
            XCTAssertFalse(style.contains(Point(x: 11, y: 21), in: empty))
        }
    }

    func testInvalidAndOversizedRadiiClampEachCornerIndependently() async {
        let rect = Rect(x: 0, y: 0, width: 80, height: 40)
        let invalid = RetainedContentShapeStyle.unevenRoundedRectangle(
            RetainedCornerRadii(topLeft: .nan, topRight: -3, bottomRight: .infinity, bottomLeft: -.infinity))

        // Match max(0,radius) followed by the existing half-extent cap:
        // NaN, negative and -infinity are square; +infinity caps at 20.
        XCTAssertTrue(invalid.contains(Point(x: 1, y: 1), in: rect))
        XCTAssertTrue(invalid.contains(Point(x: 79, y: 1), in: rect))
        XCTAssertTrue(invalid.contains(Point(x: 1, y: 39), in: rect))
        XCTAssertFalse(invalid.contains(Point(x: 79, y: 39), in: rect))
        XCTAssertTrue(invalid.contains(Point(x: 60, y: 20), in: rect))

        let oversized = RetainedContentShapeStyle.unevenRoundedRectangle(
            RetainedCornerRadii(topLeft: 400, topRight: 3, bottomRight: 0, bottomLeft: 7))
        XCTAssertFalse(oversized.contains(Point(x: 1, y: 1), in: rect))
        XCTAssertTrue(oversized.contains(Point(x: 79, y: 1), in: rect))
        XCTAssertTrue(oversized.contains(Point(x: 79, y: 39), in: rect))
        XCTAssertFalse(oversized.contains(Point(x: 1, y: 39), in: rect))

        // Mutable public radius fields bypass the initializer's zero clamp.
        var radii = RectangleCornerRadii()
        radii.topLeading = .nan
        radii.topTrailing = -3
        radii.bottomTrailing = .infinity
        radii.bottomLeading = -.infinity
        var actions = 0
        let fixture = makeFixture(
            Rectangle().contentShape(UnevenRoundedRectangle(cornerRadii: radii, style: .circular))
                .onTapGesture { actions += 1 })
        for point in [Point(x: 1, y: 1), Point(x: 119, y: 1), Point(x: 1, y: 79)] {
            click(fixture.runtime, at: point)
        }
        XCTAssertEqual(actions, 3)
        click(fixture.runtime, at: Point(x: 119, y: 79))
        XCTAssertEqual(actions, 3)
    }

    func testVisualEffectRadiusRemainsAnExplicitCompatibilityMaximum() async {
        let smallRect = Rect(x: 0, y: 0, width: 8, height: 6)
        let style = RetainedContentShapeStyle.unevenRoundedRectangle(
            RetainedCornerRadii(topLeft: 4, topRight: 14, bottomRight: 18, bottomLeft: 10))

        XCTAssertEqual(style.visualCornerRadius(in: smallRect), 18)
        XCTAssertEqual(
            RetainedContentShapeStyle.unevenRoundedRectangle(
                RetainedCornerRadii(topLeft: .nan, topRight: -1, bottomRight: -.infinity, bottomLeft: 7)
            ).visualCornerRadius(in: smallRect), 7)
        XCTAssertEqual(
            RetainedContentShapeStyle.unevenRoundedRectangle(RetainedCornerRadii(bottomRight: .infinity))
                .visualCornerRadius(in: smallRect), .infinity)
    }

    func testPublicContentShapeRoutesRealPointerActionsWithoutChangingTheirOrder() async {
        var actions: [String] = []
        let fixture = makeFixture(
            Rectangle()
                .contentShape(UnevenRoundedRectangle(bottomTrailingRadius: 20, style: .circular))
                .onTapGesture { actions.append("inner") }
                .onTapGesture { actions.append("outer") })

        XCTAssertEqual(fixture.node.resolvedFrame, Self.bounds)
        click(fixture.runtime, at: Point(x: 119, y: 79))
        XCTAssertTrue(actions.isEmpty)
        for point in [Point(x: 1, y: 1), Point(x: 119, y: 1), Point(x: 1, y: 79), Point(x: 60, y: 40)] {
            click(fixture.runtime, at: point)
        }
        XCTAssertEqual(actions, ["inner", "outer", "inner", "outer", "inner", "outer", "inner", "outer"])
    }

    func testOneLogicalShapeUsesEachActualEnvironmentDirection() async {
        let shape = UnevenRoundedRectangle(topLeadingRadius: 20, style: .circular)
        assertDirectionalActions(shape)
    }

    func testDoubleErasurePreservesLogicalCornersAcrossTwoBuildContexts() async {
        let wrapped = AnyShape(AnyShape(UnevenRoundedRectangle(topLeadingRadius: 20, style: .circular)))
        // Construct once, then build the same erased value in each direction.
        assertDirectionalActions(wrapped)
        XCTAssertEqual(
            wrapped.retainedContentShapeStyle,
            .unevenRoundedRectangle(RetainedCornerRadii(topLeft: 20)))
    }

    func testLiveRebuildChangesDirectionRadiiAndActionOnTheSameOwner() async throws {
        let runtime = RetainedViewRuntime(root: ViewNode(frame: Self.bounds, isHitTestVisible: false))
        let host = ComponentHost(runtime: runtime)
        let context = ViewBuildContext(canvasSizeProvider: { Self.size }, invalidateHandler: {})
        var direction = LayoutDirection.leftToRight
        var radii = RectangleCornerRadii(topLeading: 20)
        var version = 1
        var actions: [Int] = []
        host.setComponents {
            let actionVersion = version
            let shape = AnyShape(AnyShape(UnevenRoundedRectangle(cornerRadii: radii, style: .circular)))
            return [
                Rectangle().frame(width: 120, height: 80)
                    .contentShape(shape)
                    .environment(\.layoutDirection, direction)
                    .onTapGesture { actions.append(actionVersion) }
                    .makeComponent(context: context)
            ]
        }
        _ = runtime.renderScene()
        let owner = try XCTUnwrap(runtime.root.children.first)
        XCTAssertEqual(owner.resolvedFrame, Self.bounds)
        click(runtime, at: Point(x: 1, y: 1))
        click(runtime, at: Point(x: 119, y: 1))
        XCTAssertEqual(actions, [1])

        direction = .rightToLeft
        radii = RectangleCornerRadii(topLeading: 30)
        version = 2
        host.reload()
        _ = runtime.renderScene()
        XCTAssertTrue(runtime.root.children.first === owner)
        XCTAssertEqual(owner.contentShapes.map(\.style), [.unevenRoundedRectangle(RetainedCornerRadii(topRight: 30))])
        click(runtime, at: Point(x: 119, y: 1))
        XCTAssertEqual(actions, [1])
        click(runtime, at: Point(x: 1, y: 1))
        XCTAssertEqual(actions, [1, 2])

        direction = .leftToRight
        radii = RectangleCornerRadii(bottomTrailing: 24)
        version = 3
        host.reload()
        _ = runtime.renderScene()
        XCTAssertTrue(runtime.root.children.first === owner)
        XCTAssertEqual(
            owner.contentShapes.map(\.style), [.unevenRoundedRectangle(RetainedCornerRadii(bottomRight: 24))])
        click(runtime, at: Point(x: 119, y: 79))
        XCTAssertEqual(actions, [1, 2])
        click(runtime, at: Point(x: 119, y: 1))
        XCTAssertEqual(actions, [1, 2, 3])
    }

    func testKindsFlagsAndLastInteractionShapeKeepTheirExistingPrecedence() async {
        let shape = UnevenRoundedRectangle(topLeadingRadius: 20, style: .circular)
        var actions = 0
        let fixture = makeFixture(
            Rectangle()
                .contentShape(.interaction, Circle())
                .contentShape([.interaction, .hoverEffect], shape, eoFill: true, mask: true)
                .contentShape(.focusEffect, Capsule())
                .containerShape(AnyShape(AnyShape(shape)))
                .environment(\.layoutDirection, .rightToLeft)
                .onTapGesture { actions += 1 })
        let expectedStyle = RetainedContentShapeStyle.unevenRoundedRectangle(RetainedCornerRadii(topRight: 20))

        XCTAssertEqual(
            fixture.node.contentShapes,
            [
                RetainedContentShape(kinds: .interaction, style: .ellipse),
                RetainedContentShape(
                    kinds: [.interaction, .hoverEffect], style: expectedStyle, eoFill: true, mask: true),
                RetainedContentShape(kinds: .focusEffect, style: .capsule),
                RetainedContentShape(kinds: .container, style: expectedStyle),
            ])
        // The first ellipse would reject this corner. The last interaction
        // shape accepts it; later focus/container entries must not replace it.
        click(fixture.runtime, at: Point(x: 1, y: 1))
        XCTAssertEqual(actions, 1)
        click(fixture.runtime, at: Point(x: 119, y: 1))
        XCTAssertEqual(actions, 1)
        click(fixture.runtime, at: Point(x: 60, y: 40))
        XCTAssertEqual(actions, 2)
    }

    func testInsetTrimAndContainerCarryDescriptorsWithoutClaimingNewGeometry() async {
        let shape = UnevenRoundedRectangle(
            topLeadingRadius: 8, bottomLeadingRadius: 10,
            bottomTrailingRadius: 12, topTrailingRadius: 14, style: .circular)
        let wrapped = AnyShape(AnyShape(shape.inset(by: 3).trim(from: 0.25, to: 0.75)))
        let fixture = makeFixture(
            Rectangle().contentShape(wrapped).containerShape(wrapped)
                .environment(\.layoutDirection, .rightToLeft))
        let style = RetainedContentShapeStyle.unevenRoundedRectangle(
            RetainedCornerRadii(topLeft: 11, topRight: 5, bottomRight: 7, bottomLeft: 9))

        XCTAssertEqual(
            fixture.node.contentShapes,
            [
                RetainedContentShape(kinds: .interaction, style: style),
                RetainedContentShape(kinds: .container, style: style),
            ])
        XCTAssertEqual(
            wrapped.retainedContentShapeStyle,
            .unevenRoundedRectangle(RetainedCornerRadii(topLeft: 5, topRight: 11, bottomRight: 9, bottomLeft: 7)))
        guard case .roundedRectangle(let clipRadius) = wrapped.retainedClipShapeStyle else {
            return XCTFail("The existing scalar clip descriptor must remain unchanged")
        }
        XCTAssertEqual(clipRadius, 11)
        // Only metadata transport is asserted. These wrappers still do not
        // supply a partial-path hit region or inherited container geometry.
    }

    func testPassiveButtonLabelCannotBypassItsOwnersUnevenContentShape() async throws {
        var actions = 0
        let fixture = makeFixture(
            Button {
                actions += 1
            } label: {
                Rectangle().frame(width: 120, height: 80).allowsHitTesting(true)
            }
            .buttonStyle(.plain)
            .contentShape(UnevenRoundedRectangle(bottomTrailingRadius: 20, style: .circular)))
        let label = try XCTUnwrap(
            firstNode(in: fixture.node) {
                $0 !== fixture.node && $0.isHitTestVisible && $0.onActivate == nil
            })
        XCTAssertNotNil(fixture.node.onActivate)
        XCTAssertFalse(label.isFocusable)
        XCTAssertNil(label.onPointerUpInside)
        let labelFrame = absoluteFrame(of: label)
        XCTAssertTrue(labelFrame.contains(Point(x: 1, y: 1)))
        XCTAssertTrue(labelFrame.contains(Point(x: 119, y: 79)))

        click(fixture.runtime, at: Point(x: 119, y: 79))
        XCTAssertEqual(actions, 0)
        click(fixture.runtime, at: Point(x: 1, y: 1))
        XCTAssertEqual(actions, 1)
        XCTAssertTrue(fixture.runtime.focusedNode === fixture.node)
        click(fixture.runtime, at: Point(x: 60, y: 40))
        XCTAssertEqual(actions, 2)
    }

    func testInteractionShapeLeavesSceneGeometryOrderingAndPixelsUnchanged() async throws {
        let shape = UnevenRoundedRectangle(bottomTrailingRadius: 20, style: .circular)
        let plain = makeFixture(shape.fill(Self.red))
        let interactive = makeFixture(shape.fill(Self.red).contentShape(shape).onTapGesture {})
        let pixelSize = IntSize(width: 120, height: 80)

        XCTAssertFalse(plain.scene.paintRecords.isEmpty)
        XCTAssertEqual(interactive.node.cornerRadii, plain.node.cornerRadii)
        XCTAssertEqual(interactive.node.cornerRadius, plain.node.cornerRadius)
        XCTAssertEqual(interactive.node.clipsToBounds, plain.node.clipsToBounds)
        XCTAssertEqual(interactive.node.backgroundPath, plain.node.backgroundPath)
        XCTAssertEqual(interactive.scene, plain.scene)
        XCTAssertEqual(Array(interactive.scene.presentationOrder()), Array(plain.scene.presentationOrder()))
        XCTAssertEqual(interactive.scene.layers.flatMap(\.quads), plain.scene.layers.flatMap(\.quads))
        let reference = GPUIRawSceneRasterizer.rasterize(plain.scene, size: pixelSize)
        let result = GPUIRawSceneRasterizer.rasterize(interactive.scene, size: pixelSize)
        XCTAssertEqual(result.pixels, reference.pixels)
        for (x, y, painted) in [(2, 2, true), (60, 40, true), (118, 78, false)] {
            let color = try XCTUnwrap(result.colorAt(x: x, y: y))
            XCTAssertEqual(color.red, painted ? 1 : 0, accuracy: 1.0 / 255)
            XCTAssertEqual(color.green, 0, accuracy: 1.0 / 255)
            XCTAssertEqual(color.blue, 0, accuracy: 1.0 / 255)
            XCTAssertEqual(color.alpha, painted ? 1 : 0, accuracy: 1.0 / 255)
        }
    }

    func testContentMetadataDoesNotRetainOrInvokeAnAuthoredPathCallback() async {
        let counts = PathCounts()
        let weakProbe = WeakPathProbe()
        var actions = 0
        let view = makeCallbackContentView(counts: counts, weakProbe: weakProbe) { actions += 1 }

        XCTAssertNil(weakProbe.value, "The modifier must keep a value descriptor, not the erased authored shape")
        XCTAssertEqual(counts.pathCalls, 0)
        let fixture = makeFixture(view)
        XCTAssertEqual(fixture.node.contentShapes, [RetainedContentShape(kinds: .interaction, style: .rectangle)])
        click(fixture.runtime, at: Point(x: 1, y: 1))
        click(fixture.runtime, at: Point(x: 119, y: 79))
        _ = fixture.runtime.renderScene()
        XCTAssertEqual(actions, 2)
        XCTAssertEqual(counts.pathCalls, 0)
        XCTAssertNil(weakProbe.value)
    }

    private struct Fixture {
        let runtime: RetainedViewRuntime
        let node: ViewNode
        let scene: GPUIScene
    }

    private func makeFixture<V: View>(_ view: V) -> Fixture {
        let root = ViewNode(frame: Self.bounds, isHitTestVisible: false)
        let runtime = RetainedViewRuntime(clearColor: .clear, root: root)
        let context = ViewBuildContext(canvasSizeProvider: { Self.size }, invalidateHandler: {})
        let node = view.makeComponent(context: context).makeNode(runtime: runtime)
        node.frame = Self.bounds
        root.addChild(node)
        return Fixture(runtime: runtime, node: node, scene: runtime.renderScene())
    }

    private func click(_ runtime: RetainedViewRuntime, at point: Point) {
        runtime.pointerDown(at: point)
        runtime.pointerUp(at: point)
    }

    private func assertDirectionalActions<S: Shape>(
        _ shape: S, file: StaticString = #filePath, line: UInt = #line
    ) {
        for direction in [LayoutDirection.leftToRight, .rightToLeft] {
            var actions = 0
            let fixture = makeFixture(
                Rectangle().contentShape(shape)
                    .environment(\.layoutDirection, direction)
                    .onTapGesture { actions += 1 })
            let isRTL = direction == .rightToLeft
            let expected = RetainedCornerRadii(topLeft: isRTL ? 0 : 20, topRight: isRTL ? 20 : 0)
            XCTAssertEqual(
                fixture.node.contentShapes,
                [RetainedContentShape(kinds: .interaction, style: .unevenRoundedRectangle(expected))],
                file: file, line: line)
            XCTAssertEqual(fixture.node.resolvedFrame, Self.bounds, file: file, line: line)
            click(fixture.runtime, at: Point(x: 1, y: 1))
            XCTAssertEqual(actions, isRTL ? 1 : 0, file: file, line: line)
            click(fixture.runtime, at: Point(x: 119, y: 1))
            XCTAssertEqual(actions, 1, file: file, line: line)
            click(fixture.runtime, at: Point(x: 60, y: 40))
            XCTAssertEqual(actions, 2, file: file, line: line)
        }
    }

    private func firstNode(in node: ViewNode, where predicate: (ViewNode) -> Bool) -> ViewNode? {
        if predicate(node) { return node }
        for child in node.children {
            if let match = firstNode(in: child, where: predicate) { return match }
        }
        return nil
    }

    private func absoluteFrame(of node: ViewNode) -> Rect {
        var frame = node.resolvedFrame
        var ancestor = node.parent
        while let current = ancestor {
            frame.origin.x += current.resolvedFrame.origin.x
            frame.origin.y += current.resolvedFrame.origin.y
            ancestor = current.parent
        }
        return frame
    }

    @MainActor
    private final class PathCounts {
        var pathCalls = 0
    }

    @MainActor
    private final class PathProbe {
        let counts: PathCounts
        init(counts: PathCounts) { self.counts = counts }
    }

    @MainActor
    private final class WeakPathProbe {
        weak var value: PathProbe?
    }

    private struct CallbackShape: Shape {
        let probe: PathProbe

        func path(in rect: Rect) -> Path {
            probe.counts.pathCalls += 1
            var path = Path()
            path.addRect(rect)
            return path
        }
    }

    private func makeCallbackContentView(
        counts: PathCounts, weakProbe: WeakPathProbe, action: @escaping @MainActor () -> Void
    ) -> AnyView {
        let probe = PathProbe(counts: counts)
        weakProbe.value = probe
        let shape = AnyShape(AnyShape(CallbackShape(probe: probe)))
        return AnyView(Rectangle().contentShape(shape).onTapGesture { action() })
    }
}
