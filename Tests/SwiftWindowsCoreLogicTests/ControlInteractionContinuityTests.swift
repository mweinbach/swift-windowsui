import Foundation
import SwiftWindowsCore
import XCTest

@testable import SwiftWindowsPlatform
@testable import SwiftWindowsUI
@testable import WinSwiftUI

/// Interaction chrome across the two events that dominate any real app: a
/// click, and a `@State` change while the pointer is resting somewhere.
///
/// Every case here samples a timeline the way the audit did — ticking
/// `tickAnimations(at:)` at fixed offsets from one captured timestamp and
/// reading the node between frames — because the failures these pin are not
/// visible in an end state. Two of them settled *wrong* and stayed wrong; the
/// gallery's interaction tier renders at `t = 1e12` and by construction can
/// only capture a settled value, which is how they shipped.
@MainActor
final class ControlInteractionContinuityTests: XCTestCase {

    // MARK: - Harness

    private func findNode(_ node: ViewNode, where predicate: (ViewNode) -> Bool) -> ViewNode? {
        if predicate(node) { return node }
        for child in node.children {
            if let found = findNode(child, where: predicate) { return found }
        }
        return nil
    }

    private func absoluteFrame(of node: ViewNode) -> Rect {
        var x = node.resolvedFrame.origin.x
        var y = node.resolvedFrame.origin.y
        var ancestor = node.parent
        while let current = ancestor {
            x += current.resolvedFrame.origin.x
            y += current.resolvedFrame.origin.y
            ancestor = current.parent
        }
        return Rect(x: x, y: y, width: node.resolvedFrame.size.width, height: node.resolvedFrame.size.height)
    }

    /// Advances the runtime's animation clock by `seconds` at 60 Hz from
    /// `clock`, leaving `clock` at the new time.
    private func advance(_ runtime: RetainedViewRuntime, _ clock: inout Double, by seconds: Double) {
        let end = clock + seconds
        while clock < end {
            clock += 1.0 / 60.0
            _ = runtime.tickAnimations(at: clock)
        }
    }

    private func makeCountingButtonHost() -> (RetainedViewRuntime, ComponentHost, () -> Int) {
        let runtime = RetainedViewRuntime(root: ViewNode(frame: Rect(x: 0, y: 0, width: 400, height: 300)))
        let host = ComponentHost(runtime: runtime)
        var counter = 0
        let context = ViewBuildContext(
            canvasSizeProvider: { Size(width: 400, height: 300) },
            invalidateHandler: { [weak host] in host?.reload() }
        )
        host.setComponents {
            [
                VStack {
                    Button("Bump \(counter)") { counter += 1 }
                }
                .frame(width: 400, height: 300)
                .makeComponent(context: context)
            ]
        }
        _ = runtime.renderFrame()
        return (runtime, host, { counter })
    }

    private func button(in runtime: RetainedViewRuntime) -> ViewNode? {
        findNode(runtime.root, where: { $0.accessibilityTraits.contains(.isButton) })
    }

    /// What the interaction ramp actually moves, as one number.
    ///
    /// This file used to sample the fill's **alpha**, which worked only while
    /// a dark-appearance control face was a translucent wash (`white(0.10)`
    /// pressing to `white(0.22)`). A bordered face is opaque now — an alpha
    /// wash over a near-black page is invisible, which is why it changed — so
    /// the ramp lives in the channels.
    private func fillLevel(of node: ViewNode) -> Double {
        let fill = node.backgroundColor ?? .clear
        return Double(0.2126 * fill.red + 0.7152 * fill.green + 0.0722 * fill.blue) * Double(fill.alpha)
    }

    // MARK: - A clicked control returns to hover

    /// Release-with-no-state-change. Before the fix this measured alpha 0.220
    /// — the pressed fill — at every sample out to three seconds, with
    /// `hasActiveAnimations` false from 0.3s on: the control was left painted
    /// held-down and nothing was scheduled to leave it, because `onActivate`
    /// animated to `palette.activated`, which every appearance-resolved ramp
    /// pinned to `palette.pressed`.
    func testReleasingAButtonReturnsItToTheHoverFillItCameFrom() async {
        let (runtime, _, _) = makeCountingButtonHost()
        guard let button = button(in: runtime) else { return XCTFail("no button in tree") }
        let centre = Point(x: absoluteFrame(of: button).midX, y: absoluteFrame(of: button).midY)

        var clock = Win32Window.currentTimestampSeconds()
        runtime.pointerMoved(to: centre)
        advance(runtime, &clock, by: 0.5)
        let hoveredLevel = fillLevel(of: button)

        runtime.pointerDown(at: centre)
        advance(runtime, &clock, by: 0.3)
        let pressedLevel = fillLevel(of: button)
        XCTAssertNotEqual(
            pressedLevel, hoveredLevel, accuracy: 0.0005,
            "a press has to move the fill or there is nothing to return from")

        runtime.pointerUp(at: centre)
        for offset in [0.05, 0.1, 0.18, 0.3, 1.0, 3.0] {
            advance(runtime, &clock, by: offset)
        }
        XCTAssertEqual(
            fillLevel(of: button), hoveredLevel, accuracy: 0.001,
            "a released button sits at its hover fill — the pointer never left it")
    }

    /// Release-with-a-state-change, i.e. every counter button ever written.
    /// The action rebuilds the tree through `invalidateHandler`; before the
    /// fix the rebuilt control read the *idle* alpha 0.100 on the very next
    /// frame and held it for all forty sampled frames while `isHovered` was
    /// still true and the pointer had not moved a pixel.
    func testAButtonWhoseActionChangesStateStaysHoveredAfterTheRebuild() async {
        // The host has to be held: `invalidateHandler` captures it weakly, so
        // binding it to `_` here left the action running and *no rebuild
        // happening at all* — the test drove the click but never reached the
        // reconcile it is about.
        let (runtime, host, counter) = makeCountingButtonHost()
        defer { withExtendedLifetime(host) {} }
        guard let button = button(in: runtime) else { return XCTFail("no button in tree") }
        let centre = Point(x: absoluteFrame(of: button).midX, y: absoluteFrame(of: button).midY)

        var clock = Win32Window.currentTimestampSeconds()
        runtime.pointerMoved(to: centre)
        advance(runtime, &clock, by: 0.5)
        let hoveredAlpha = button.backgroundColor?.alpha ?? 0

        runtime.pointerDown(at: centre)
        advance(runtime, &clock, by: 0.3)
        runtime.pointerUp(at: centre)
        XCTAssertEqual(counter(), 1, "the action ran")
        XCTAssertNotNil(
            findNode(runtime.root, where: { $0.text == "Bump 1" }),
            "and the tree was actually rebuilt from it — the label carries the new state")

        // Frame by frame at 60 Hz: no frame may show the idle fill.
        for frame in 0..<40 {
            clock += 1.0 / 60.0
            _ = runtime.tickAnimations(at: clock)
            guard let live = self.button(in: runtime) else { return XCTFail("button vanished") }
            XCTAssertTrue(live === button, "frame \(frame): reconciliation kept the node's identity")
            XCTAssertTrue(live.isHovered, "frame \(frame): the pointer never moved")
            XCTAssertEqual(
                Double(live.backgroundColor?.alpha ?? 0), Double(hoveredAlpha), accuracy: 0.001,
                "frame \(frame): a rebuild must not repaint a hovered control at its idle fill")
        }
    }

    // MARK: - A rebuild does not de-hover

    /// The bare mechanism, with no click involved: hover a control, call
    /// `reload()`, and the fill has to be exactly where it was. Before the
    /// fix it dropped to idle immediately and never recovered — a pointer
    /// already inside the control makes `updateHoverTarget` return early
    /// (`guard hoveredNode !== nextHoveredNode`), so `onPointerEnter` never
    /// fires again.
    func testAPlainReloadLeavesTheHoveredControlAtItsHoverFill() async {
        let (runtime, host, _) = makeCountingButtonHost()
        guard let button = button(in: runtime) else { return XCTFail("no button in tree") }
        let centre = Point(x: absoluteFrame(of: button).midX, y: absoluteFrame(of: button).midY)

        var clock = Win32Window.currentTimestampSeconds()
        runtime.pointerMoved(to: centre)
        advance(runtime, &clock, by: 0.5)
        let hoveredColor = button.backgroundColor

        host.reload()
        XCTAssertEqual(
            button.backgroundColor, hoveredColor,
            "the restore is immediate: the chrome was already on screen, it is not re-animated")

        for offset in [0.1, 0.2, 0.3, 0.4] {
            advance(runtime, &clock, by: offset)
            XCTAssertEqual(button.backgroundColor, hoveredColor, "still hovered \(offset)s later")
        }

        // And a one-pixel move inside the same control changes nothing.
        runtime.pointerMoved(to: Point(x: centre.x + 1, y: centre.y))
        advance(runtime, &clock, by: 0.3)
        XCTAssertEqual(button.backgroundColor, hoveredColor)
    }

    /// The deeper half of the same bug: the interaction closures a build
    /// installed captured *that build's* node, and `updateNodeProperties`
    /// copied them onto the retained node, so after one rebuild every hover
    /// animated an orphan. Leaving and re-entering — the one recovery path the
    /// audit found for the un-rebuilt case — did nothing at all.
    func testHoverStillWorksAfterTheControlHasBeenRebuilt() async {
        let (runtime, host, _) = makeCountingButtonHost()
        guard let button = button(in: runtime) else { return XCTFail("no button in tree") }
        let bounds = absoluteFrame(of: button)
        let centre = Point(x: bounds.midX, y: bounds.midY)
        let idleColor = button.backgroundColor

        var clock = Win32Window.currentTimestampSeconds()
        host.reload()
        runtime.pointerMoved(to: centre)
        advance(runtime, &clock, by: 0.4)
        let hoveredColor = button.backgroundColor
        XCTAssertNotEqual(hoveredColor, idleColor, "hover has to survive a rebuild of the control")

        runtime.pointerMoved(to: Point(x: bounds.maxX + 40, y: bounds.maxY + 40))
        advance(runtime, &clock, by: 0.4)
        XCTAssertEqual(button.backgroundColor, idleColor, "and leaving has to take it back off")

        runtime.pointerMoved(to: centre)
        advance(runtime, &clock, by: 0.4)
        XCTAssertEqual(button.backgroundColor, hoveredColor, "and re-entering has to put it back")
    }

    // MARK: - One focus ring, one owner

    /// A focused control used to carry two concentric rings in two different
    /// blues on two different timelines: the runtime's hardcoded 2pt
    /// `focusEffectCommands` halo at full strength from frame zero, and the
    /// control's own appearance-resolved 4pt ring fading in behind it over
    /// 0.18s. The control's ring is the survivor.
    func testAControlWithItsOwnRingGetsNoSecondRingFromTheRuntime() async {
        let (runtime, _, _) = makeCountingButtonHost()
        guard let button = button(in: runtime) else { return XCTFail("no button in tree") }

        runtime.keyDown(KeyboardEvent(keyCode: KeyboardKey.tab.rawValue))
        XCTAssertTrue(button.isFocused)
        XCTAssertFalse(button.isFocusEffectDisabled, "not suppressed by the opt-out — suppressed by ownership")
        XCTAssertNotNil(button.interactionSurface?.focusRingColor)

        var clock = Win32Window.currentTimestampSeconds()
        advance(runtime, &clock, by: 0.4)
        XCTAssertTrue(
            button.focusEffectCommands(for: absoluteFrame(of: button), inheritedClip: nil, opacity: 1).isEmpty,
            "the node paints its own ring, so the runtime's fallback halo must stand down")
        XCTAssertGreaterThan(button.outlineColor.alpha, 0, "and the ring it does paint is on")
    }

    /// The ring grows out of the control's edge rather than cross-fading a
    /// full-width ring up from nothing — AppKit's ring is not an alpha fade.
    /// Sampled mid-tween, which is the only place the difference exists.
    func testTheFocusRingExpandsFromZeroWidthWhileItsColourFadesIn() async {
        let (runtime, _, _) = makeCountingButtonHost()
        guard let button = button(in: runtime) else { return XCTFail("no button in tree") }
        let ringWidth = button.interactionSurface?.focusRingWidth ?? 0
        XCTAssertEqual(ringWidth, MacOSControlMetrics.FocusRing.strokeWidth, accuracy: 0.001)
        XCTAssertEqual(button.outlineWidth, 0, accuracy: 0.001, "no ring at rest")

        var clock = Win32Window.currentTimestampSeconds()
        runtime.keyDown(KeyboardEvent(keyCode: KeyboardKey.tab.rawValue))

        advance(runtime, &clock, by: 0.06)
        let midWidth = button.outlineWidth
        let midAlpha = button.outlineColor.alpha
        XCTAssertGreaterThan(midWidth, 0, "the ring is on its way out of the edge")
        XCTAssertLessThan(midWidth, ringWidth, "and is not there yet")
        XCTAssertGreaterThan(midAlpha, 0)

        advance(runtime, &clock, by: 0.4)
        XCTAssertEqual(button.outlineWidth, ringWidth, accuracy: 0.001, "settled at the pinned stroke width")

        // Focus away — a click on empty canvas, since the button is the only
        // focus stop in this tree and Tab would loop straight back to it. The
        // ring retracts rather than blinking out.
        runtime.pointerDown(at: Point(x: 390, y: 290))
        runtime.pointerUp(at: Point(x: 390, y: 290))
        XCTAssertFalse(button.isFocused)
        advance(runtime, &clock, by: 0.06)
        XCTAssertLessThan(button.outlineWidth, ringWidth)
        advance(runtime, &clock, by: 0.4)
        XCTAssertEqual(button.outlineWidth, 0, accuracy: 0.001)
    }

    /// Pressing a focused control keeps its ring. The fill ramp ranks a press
    /// above focus; the ring does not — it is keyed off focus itself.
    func testPressingAFocusedControlKeepsItsFocusRing() async {
        let (runtime, _, _) = makeCountingButtonHost()
        guard let button = button(in: runtime) else { return XCTFail("no button in tree") }
        let centre = Point(x: absoluteFrame(of: button).midX, y: absoluteFrame(of: button).midY)

        var clock = Win32Window.currentTimestampSeconds()
        runtime.pointerMoved(to: centre)
        runtime.pointerDown(at: centre)
        advance(runtime, &clock, by: 0.4)

        XCTAssertTrue(button.isFocused)
        XCTAssertGreaterThan(button.outlineColor.alpha, 0, "a pressed control that is focused still shows it")
        XCTAssertEqual(
            button.outlineWidth, button.interactionSurface?.focusRingWidth ?? -1, accuracy: 0.001)
    }

    /// A focusable node that paints no ring of its own still gets the
    /// runtime's fallback halo — the suppression is ownership, not a blanket
    /// removal.
    func testAFocusableNodeWithNoRingOfItsOwnStillGetsTheRuntimeHalo() async {
        let node = ViewNode(
            frame: Rect(x: 10, y: 10, width: 40, height: 20),
            backgroundColor: .white,
            isFocusable: true
        )
        let root = ViewNode(frame: Rect(x: 0, y: 0, width: 100, height: 60), isHitTestVisible: false)
        root.addChild(node)
        let runtime = RetainedViewRuntime(root: root)
        _ = runtime.renderFrame()

        runtime.keyDown(KeyboardEvent(keyCode: KeyboardKey.tab.rawValue))
        XCTAssertTrue(node.isFocused)
        XCTAssertNil(node.interactionSurface)
        XCTAssertFalse(
            node.focusEffectCommands(for: node.frame, inheritedClip: nil, opacity: 1).isEmpty,
            "nothing else would show this node has focus")
    }

    // MARK: - Text field focus survives a rebuild

    func testAFocusedTextFieldKeepsItsRingAcrossARebuild() async {
        let runtime = RetainedViewRuntime(root: ViewNode(frame: Rect(x: 0, y: 0, width: 400, height: 300)))
        let host = ComponentHost(runtime: runtime)
        var text = "Ada"
        let context = ViewBuildContext(
            canvasSizeProvider: { Size(width: 400, height: 300) },
            invalidateHandler: { [weak host] in host?.reload() }
        )
        host.setComponents {
            [
                VStack {
                    TextField("Name", text: Binding(get: { text }, set: { text = $0 }))
                }
                .frame(width: 400, height: 300)
                .makeComponent(context: context)
            ]
        }
        _ = runtime.renderFrame()
        guard
            let field = findNode(runtime.root, where: { $0.accessibilityTraits.contains(.isTextInput) })
        else { return XCTFail("no text field in tree") }

        var clock = Win32Window.currentTimestampSeconds()
        runtime.keyDown(KeyboardEvent(keyCode: KeyboardKey.tab.rawValue))
        advance(runtime, &clock, by: 0.4)
        let focusedRing = field.outlineColor
        let focusedBorder = field.borderColor
        XCTAssertGreaterThan(focusedRing.alpha, 0)

        host.reload()
        XCTAssertEqual(field.outlineColor, focusedRing, "a rebuild does not unfocus a field")
        XCTAssertEqual(field.borderColor, focusedBorder)
    }
}
