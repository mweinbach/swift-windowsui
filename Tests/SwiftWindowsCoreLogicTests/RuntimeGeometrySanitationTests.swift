import Foundation

import SwiftWindowsCore

import SwiftWindowsGraphics

import SwiftWindowsLayout

import SwiftWindowsPlatform

import XCTest

@testable import SwiftWindowsUI

/// The runtime is the last layer that can keep non-finite geometry, degenerate
/// containers and pathological trees out of the scene contract. Below it,
/// `Int(_: Float)` traps on NaN and ±∞ — a process kill, not an error the
/// host's renderer fallback can absorb — and a recursive traversal that runs
/// out of stack takes the process with it.
final class RuntimeGeometrySanitationTests: XCTestCase {

    // MARK: - Non-finite geometry

    /// `.frame(maxWidth: .infinity)` reaching `preferredSize`, and a NaN from a
    /// division by a collapsed extent, both have to resolve to finite geometry
    /// — and must not take unrelated siblings down with them.
    func testNonFiniteLayoutGeometryIsClampedAndSiblingsStillRender() async {
        await MainActor.run {
            let malformed = ViewNode(
                frame: Rect(x: 0, y: 0, width: 40, height: 40),
                backgroundColor: Color(red: 1, green: 0, blue: 0, alpha: 1),
                preferredSize: Size(width: .infinity, height: .nan)
            )
            let sibling = ViewNode(
                frame: Rect(x: 0, y: 120, width: 40, height: 40),
                backgroundColor: Color(red: 0, green: 1, blue: 0, alpha: 1)
            )
            let root = ViewNode(frame: Rect(x: 0, y: 0, width: 200, height: 200), isHitTestVisible: false)
            root.addChild(malformed)
            root.addChild(sibling)

            let runtime = RetainedViewRuntime(root: root)
            let scene = runtime.renderScene()

            XCTAssertTrue(malformed.resolvedFrame.size.width.isFinite)
            XCTAssertTrue(malformed.resolvedFrame.size.height.isFinite)
            XCTAssertGreaterThanOrEqual(malformed.resolvedFrame.size.height, 0)
            XCTAssertTrue(sceneFieldsAreFinite(scene))
            XCTAssertTrue(
                sceneQuads(scene).contains { $0.startG == 1 && $0.startR == 0 },
                "an unrelated sibling must still render next to malformed geometry")
        }
    }

    /// A NaN scroll offset used to poison every descendant origin, which made
    /// every clip intersection empty and blanked the window with nothing
    /// logged.
    func testNonFiniteScrollOffsetDoesNotBlankTheSubtree() async {
        await MainActor.run {
            let content = ViewNode(
                frame: Rect(x: 0, y: 0, width: 100, height: 400),
                backgroundColor: Color(red: 0, green: 0, blue: 1, alpha: 1)
            )
            let scroller = ViewNode(
                frame: Rect(x: 0, y: 0, width: 100, height: 100),
                clipsToBounds: true,
                scrollAxis: .vertical
            )
            scroller.addChild(content)
            let root = ViewNode(frame: Rect(x: 0, y: 0, width: 200, height: 200), isHitTestVisible: false)
            root.addChild(scroller)

            let runtime = RetainedViewRuntime(root: root)
            _ = runtime.renderScene()

            scroller.scrollOffset = .nan
            let scene = runtime.renderScene()

            XCTAssertTrue(scroller.resolvedScrollOffset.isFinite)
            XCTAssertTrue(sceneFieldsAreFinite(scene))
            XCTAssertTrue(
                sceneQuads(scene).contains { $0.startB == 1 && $0.startR == 0 },
                "scrolled content must survive a NaN offset")
        }
    }

    // MARK: - Scroll offset composition

    /// Both `layoutSubtree` exits compose the presented offset the same way.
    /// The full-relayout exit used to drop `scrollOvershoot`, so an async image
    /// finishing mid rubber-band snapped the list back for one frame.
    func testRubberBandOvershootSurvivesALayoutInvalidation() async {
        await MainActor.run {
            let content = ViewNode(
                frame: Rect(x: 0, y: 0, width: 100, height: 400), backgroundColor: .white)
            let scroller = ViewNode(
                frame: Rect(x: 0, y: 0, width: 100, height: 100),
                clipsToBounds: true,
                scrollAxis: .vertical,
                scrollOffset: 10_000
            )
            scroller.addChild(content)
            let root = ViewNode(frame: Rect(x: 0, y: 0, width: 200, height: 200), isHitTestVisible: false)
            root.addChild(scroller)

            let runtime = RetainedViewRuntime(root: root)
            _ = runtime.renderScene()
            let clampedOffset = scroller.resolvedScrollOffset
            XCTAssertGreaterThan(clampedOffset, 0, "the scroller must be pinned at its bottom edge")

            // The rubber-band spring writes `scrollOvershoot` directly; it has
            // no `didSet`, which is exactly why the full-relayout exit dropping
            // it stayed hidden. An async image finishing on a visible row is
            // the `.layout` invalidation that lands on top of it. Only the
            // cross-axis size changes, so the scrollable extent — and therefore
            // the clamp — is unchanged.
            scroller.scrollOvershoot = 24
            content.preferredSize = Size(width: 90, height: 400)
            _ = runtime.renderScene()

            XCTAssertEqual(
                scroller.resolvedScrollOffset, clampedOffset + 24, accuracy: 0.001,
                "a relayout must not drop the rubber-band overshoot for a frame")

            // And the cache-hit exit composes it identically.
            scroller.scrollOffset = scroller.scrollOffset
            _ = runtime.renderScene()
            XCTAssertEqual(
                scroller.resolvedScrollOffset, clampedOffset + 24, accuracy: 0.001,
                "both layoutSubtree exits must compose the same presented offset")
        }
    }

    // MARK: - Per-corner radii on the frame path

    /// `FillRectCommand` carries only a uniform radius, so the frame path has
    /// to degrade per-corner radii to `maxRadius` the way ScenePainter does for
    /// its own uniform-radius consumers. Reading `cornerRadius` alone turned a
    /// rounded joined control square on renderer fallback.
    func testFramePathDegradesPerCornerRadiiToMaxRadius() async {
        await MainActor.run {
            let node = ViewNode(
                frame: Rect(x: 0, y: 0, width: 80, height: 32),
                backgroundColor: .white,
                cornerRadius: 0
            )
            node.cornerRadii = RetainedCornerRadii(topLeft: 8, bottomLeft: 8)
            let root = ViewNode(frame: Rect(x: 0, y: 0, width: 200, height: 200), isHitTestVisible: false)
            root.addChild(node)

            let frame = RetainedViewRuntime(root: root).renderFrame()
            let radii = fillCommands(frame).map(\.cornerRadius)
            XCTAssertTrue(
                radii.contains(8),
                "per-corner radii must degrade to maxRadius, not collapse to zero")
        }
    }

    // MARK: - Zero-size containers

    /// A container whose resolved extent collapses to zero paints none of its
    /// own decoration but must not drop its subtree — and the two paint paths
    /// have to agree about that, because the host swaps between them silently.
    func testZeroWidthContainerStillPaintsItsSizedChildOnBothPaths() async {
        await MainActor.run {
            let child = ViewNode(
                frame: Rect(x: 0, y: 0, width: 80, height: 20),
                backgroundColor: Color(red: 0, green: 1, blue: 1, alpha: 1),
                text: "AB"
            )
            let collapsed = ViewNode(frame: Rect(x: 0, y: 0, width: 0, height: 0))
            collapsed.layoutConstraints = LayoutConstraints(maxWidth: 0)
            collapsed.addChild(child)
            let root = ViewNode(frame: Rect(x: 0, y: 0, width: 200, height: 200), isHitTestVisible: false)
            root.addChild(collapsed)

            let runtime = RetainedViewRuntime(root: root)
            let scene = runtime.renderScene()
            XCTAssertEqual(collapsed.resolvedFrame.size.width, 0, accuracy: 0.001)
            XCTAssertGreaterThan(child.resolvedFrame.size.width, 0)
            XCTAssertTrue(
                sceneQuads(scene).contains { isCyan($0) },
                "the scene path must still paint the sized child of a collapsed container")
            XCTAssertFalse(
                sceneGlyphs(scene).isEmpty,
                "the child's glyphs must survive the collapsed parent")

            let frame = runtime.renderFrame()
            XCTAssertTrue(
                fillCommands(frame).contains { isCyan($0.color) },
                "the frame path must paint the same child")
        }
    }

    // MARK: - Shrink floors

    /// `shrinkMainSizes` indexes its `floors` array per child. It used to be
    /// handed whatever the caller's own squeeze test produced — an empty array
    /// whenever the two float comparisons disagreed, which is an
    /// index-out-of-range trap.
    func testSqueezedStackWithoutShrinkFloorsDoesNotTrap() async {
        await MainActor.run {
            var children: [ViewNode] = []
            for index in 0..<4 {
                let shade = Float(index) / 4
                let color = Color(red: shade, green: 0, blue: 0, alpha: 1)
                children.append(
                    ViewNode(
                        frame: Rect(x: 0, y: 0, width: 60, height: 60),
                        backgroundColor: color,
                        preferredSize: Size(width: 60, height: 60)
                    )
                )
            }
            let root = ViewNode(
                frame: Rect(x: 0, y: 0, width: 100, height: 50),
                layoutMode: .stack(.vertical(spacing: 0, alignment: .leading)),
                isHitTestVisible: false,
                children: children
            )

            let scene = RetainedViewRuntime(root: root).renderScene()
            XCTAssertTrue(sceneFieldsAreFinite(scene))
            for child in children {
                XCTAssertGreaterThanOrEqual(child.resolvedFrame.size.height, 0)
            }
        }
    }

    // MARK: - Traversal depth

    /// Layout, prepaint and the frame-path command walk are explicit
    /// worklists and measurement is a narrow recursion; a pathological tree
    /// must produce a truncated picture and a diagnostic, not an access
    /// violation.
    func testVeryDeepTreeRendersInsteadOfOverflowingTheStack() async {
        await MainActor.run {
            // A lowered cap, so the *branch* is exercised cheaply on a 1,200-
            // deep chain. That the stack can actually reach the production cap
            // is a separate claim, and `TraversalStackHeadroomTests` makes it
            // head-on.
            let productionCap = ViewNode.maximumTraversalDepth
            ViewNode.maximumTraversalDepth = 8
            defer { ViewNode.maximumTraversalDepth = productionCap }

            let (root, runtime) = makeDeepChain(depth: 1_200)
            let before = ViewNode.traversalDepthOverflowCount

            let scene = runtime.renderScene()
            XCTAssertGreaterThan(
                ViewNode.traversalDepthOverflowCount, before,
                "the depth cap must have reported the truncation")
            XCTAssertTrue(sceneFieldsAreFinite(scene))

            let afterScene = ViewNode.traversalDepthOverflowCount
            _ = runtime.renderFrame()
            XCTAssertGreaterThan(
                ViewNode.traversalDepthOverflowCount, afterScene,
                "the frame path must be capped the same way the scene path is")
            XCTAssertLessThanOrEqual(ViewNode.maxObservedTraversalDepth, productionCap)
            _ = root
        }
    }
}

@MainActor
private func sceneQuads(_ scene: GPUIScene) -> [QuadPrimitive] {
    scene.layers.flatMap(\.quads)
}

@MainActor
private func sceneGlyphs(_ scene: GPUIScene) -> [GlyphPrimitive] {
    scene.layers.flatMap { $0.glyphs + $0.pixelGlyphs }
}

@MainActor
private func fillCommands(_ frame: RenderFrame) -> [FillRectCommand] {
    frame.commands.compactMap { command in
        guard case .fillRect(let fill) = command else { return nil }
        return fill
    }
}

@MainActor
private func isCyan(_ quad: QuadPrimitive) -> Bool {
    quad.startR == 0 && quad.startG == 1 && quad.startB == 1
}

@MainActor
private func isCyan(_ color: Color) -> Bool {
    color.red == 0 && color.green == 1 && color.blue == 1
}

@MainActor
private func sceneFieldsAreFinite(_ scene: GPUIScene) -> Bool {
    for quad in sceneQuads(scene) {
        var fields: [Float] = []
        fields.append(quad.x)
        fields.append(quad.y)
        fields.append(quad.width)
        fields.append(quad.height)
        fields.append(quad.cornerRadius)
        fields.append(quad.clipX)
        fields.append(quad.clipY)
        fields.append(quad.clipWidth)
        fields.append(quad.clipHeight)
        fields.append(quad.blurRadius)
        fields.append(quad.clipCornerRadius)
        if fields.contains(where: { !$0.isFinite }) {
            return false
        }
    }
    for glyph in sceneGlyphs(scene) where !glyph.screenX.isFinite || !glyph.screenY.isFinite {
        return false
    }
    return true
}

@MainActor
private func makeDeepChain(depth: Int) -> (ViewNode, RetainedViewRuntime) {
    let root = ViewNode(frame: Rect(x: 0, y: 0, width: 200, height: 200), isHitTestVisible: false)
    let runtime = RetainedViewRuntime(root: root)
    var deepest = root
    for _ in 0..<depth {
        let next = ViewNode(frame: Rect(x: 0, y: 0, width: 10, height: 10))
        deepest.addChild(next)
        deepest = next
    }
    return (root, runtime)
}
