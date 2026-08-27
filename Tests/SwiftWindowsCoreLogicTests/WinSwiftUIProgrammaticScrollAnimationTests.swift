import SwiftWindowsCore
import SwiftWindowsGraphics
import XCTest

@testable import SwiftWindowsUI
@testable import WinSwiftUI

final class WinSwiftUIProgrammaticScrollAnimationTests: XCTestCase {
    @MainActor
    private final class RecordingState {
        var proxy: ScrollViewProxy?
        var disabled = false
        var offsets: [Double] = []
        var phases: [ScrollPhase] = []
    }

    @MainActor
    private struct Fixture {
        let runtime: RetainedViewRuntime
        let host: ComponentHost
        let scroller: ViewNode
        let proxy: ScrollViewProxy
        let clock: RuntimeTestClock
        let state: RecordingState

        func render(at time: Double) -> GPUIScene {
            clock.now = time
            _ = runtime.tickAnimations(at: time)
            return runtime.renderScene()
        }
    }

    @MainActor
    private static func makeFixture(
        renderFirst: Bool = true,
        requestBeforeAttachment: (@MainActor (ScrollViewProxy) -> Void)? = nil
    ) throws -> Fixture {
        let runtime = RetainedViewRuntime(root: ViewNode(frame: Rect(x: 0, y: 0, width: 120, height: 100)))
        let host = ComponentHost(runtime: runtime)
        let clock = RuntimeTestClock()
        runtime.clock = { clock.now }
        let state = RecordingState()
        let context = ViewBuildContext(
            canvasSizeProvider: { Size(width: 120, height: 100) }, invalidateHandler: {})
        host.setComponents {
            [
                ScrollViewReader { proxy in
                    state.proxy = proxy
                    let _ = requestBeforeAttachment?(proxy)
                    ScrollView(.vertical, showsIndicators: false) {
                        WinSwiftUI.Color.clear.frame(width: 80, height: 80).id("top")
                        WinSwiftUI.Color(red: 1, green: 0, blue: 0, alpha: 1)
                            .frame(width: 80, height: 10)
                            .id("marker")
                        WinSwiftUI.Color.clear.frame(width: 80, height: 400)
                    }
                    .scrollDisabled(state.disabled)
                    .frame(width: 120, height: 100)
                    .onScrollGeometryChange(for: Double.self, of: { Double($0.contentOffset.y) }) { _, new in
                        state.offsets.append(new)
                    }
                    .onScrollPhaseChange { _, new in state.phases.append(new) }
                }
                .makeComponent(context: context)
            ]
        }
        var pending = [runtime.root]
        var scroller: ViewNode?
        while let node = pending.popLast() {
            if node.scrollAxis != nil {
                scroller = node
                break
            }
            pending.append(contentsOf: node.children.reversed())
        }
        let fixture = Fixture(
            runtime: runtime,
            host: host,
            scroller: try XCTUnwrap(scroller),
            proxy: try XCTUnwrap(state.proxy),
            clock: clock,
            state: state)
        if renderFirst { _ = runtime.renderScene() }
        return fixture
    }

    @MainActor
    private static func assertPresentedOffset(
        _ expected: Double,
        in fixture: Fixture,
        scene: GPUIScene,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(fixture.scroller.resolvedScrollOffset, expected, accuracy: 0.0001, file: file, line: line)
        XCTAssertEqual(fixture.state.offsets.last ?? -1, expected, accuracy: 0.0001, file: file, line: line)
        guard
            let marker = scene.layers.flatMap(\.quads).first(where: {
                $0.startR == 1 && $0.startG == 0 && $0.startB == 0 && $0.startA == 1
            })
        else {
            return XCTFail("Expected the red marker to remain visible", file: file, line: line)
        }
        XCTAssertEqual(Double(marker.y), 80 - expected, accuracy: 0.001, file: file, line: line)
    }

    func testAuthoredLinearDurationDrivesPublicGeometryPaintAndPhases() async throws {
        try await MainActor.run {
            let fixture = try Self.makeFixture()
            withAnimation(.linear(duration: 0.6)) {
                fixture.proxy.scrollTo("marker", anchor: .top)
            }
            XCTAssertEqual(fixture.scroller.scrollOffset, 80)
            Self.assertPresentedOffset(0, in: fixture, scene: fixture.render(at: 0))
            XCTAssertEqual(fixture.state.phases, [.animating])

            for (time, offset) in [(0.15, 20.0), (0.3, 40.0), (0.6, 80.0)] {
                Self.assertPresentedOffset(offset, in: fixture, scene: fixture.render(at: time))
            }
            XCTAssertEqual(fixture.state.offsets.count, 4)
            XCTAssertEqual(fixture.state.phases, [.animating, .idle])
            _ = fixture.render(at: 1)
            XCTAssertEqual(fixture.state.offsets.count, 4)
            XCTAssertEqual(fixture.state.phases, [.animating, .idle])
        }
    }

    func testRequestBeforeAttachmentAndLayoutRetainsItsAnimationAfterTheScopeExits() async throws {
        try await MainActor.run {
            let fixture = try Self.makeFixture(renderFirst: false) { proxy in
                withAnimation(.linear(duration: 0.6)) {
                    proxy.scrollTo("marker", anchor: .top)
                }
            }
            XCTAssertTrue(fixture.state.offsets.isEmpty)
            XCTAssertTrue(fixture.state.phases.isEmpty)

            Self.assertPresentedOffset(0, in: fixture, scene: fixture.render(at: 0))
            XCTAssertEqual(fixture.state.phases, [.animating])
            Self.assertPresentedOffset(40, in: fixture, scene: fixture.render(at: 0.3))
            Self.assertPresentedOffset(80, in: fixture, scene: fixture.render(at: 0.6))
            XCTAssertEqual(fixture.state.phases, [.animating, .idle])
        }
    }

    func testExplicitNilAndDisabledTransactionsOverrideAmbientAnimationIncludingDeferredRequests() async throws {
        try await MainActor.run {
            for deferred in [false, true] {
                for disablesAnimations in [false, true] {
                    let request: @MainActor (ScrollViewProxy) -> Void = { proxy in
                        withAnimation(.linear(duration: 0.6)) {
                            if disablesAnimations {
                                var transaction = Transaction(animation: .linear(duration: 0.6))
                                transaction.disablesAnimations = true
                                withTransaction(transaction) {
                                    proxy.scrollTo("marker", anchor: .top)
                                }
                            } else {
                                withAnimation(nil) {
                                    proxy.scrollTo("marker", anchor: .top)
                                }
                            }
                        }
                    }
                    let fixture = try Self.makeFixture(
                        renderFirst: !deferred,
                        requestBeforeAttachment: deferred ? request : nil)
                    if !deferred { request(fixture.proxy) }

                    let scene = withAnimation(.linear(duration: 2)) {
                        fixture.render(at: 0)
                    }
                    Self.assertPresentedOffset(80, in: fixture, scene: scene)
                    XCTAssertEqual(fixture.scroller.scrollOffset, 80)
                    XCTAssertFalse(fixture.state.phases.contains(.animating))
                    let count = fixture.state.offsets.count
                    Self.assertPresentedOffset(80, in: fixture, scene: fixture.render(at: 0.3))
                    XCTAssertEqual(fixture.state.offsets.count, count)
                    XCTAssertFalse(fixture.state.phases.contains(.animating))
                }
            }
        }
    }

    func testProgrammaticTweenContinuesAcrossPublicDisableAndReenable() async throws {
        try await MainActor.run {
            let fixture = try Self.makeFixture()
            withAnimation(.linear(duration: 0.6)) {
                fixture.proxy.scrollTo("marker", anchor: .top)
            }
            _ = fixture.render(at: 0)
            Self.assertPresentedOffset(20, in: fixture, scene: fixture.render(at: 0.15))

            fixture.state.disabled = true
            fixture.host.reload()
            Self.assertPresentedOffset(20, in: fixture, scene: fixture.render(at: 0.15))
            XCTAssertFalse(fixture.scroller.isScrollInputEnabled)
            Self.assertPresentedOffset(40, in: fixture, scene: fixture.render(at: 0.3))
            XCTAssertEqual(fixture.state.phases, [.animating])

            fixture.state.disabled = false
            fixture.host.reload()
            Self.assertPresentedOffset(40, in: fixture, scene: fixture.render(at: 0.3))
            XCTAssertTrue(fixture.scroller.isScrollInputEnabled)
            Self.assertPresentedOffset(80, in: fixture, scene: fixture.render(at: 0.6))
            XCTAssertEqual(fixture.state.offsets.count, 4)
            XCTAssertEqual(fixture.state.phases, [.animating, .idle])
        }
    }

    func testRetargetingStartsFromTheCurrentlyPaintedOffsetWithoutAJump() async throws {
        try await MainActor.run {
            let fixture = try Self.makeFixture()
            withAnimation(.linear(duration: 0.6)) {
                fixture.proxy.scrollTo("marker", anchor: .top)
            }
            _ = fixture.render(at: 0)
            Self.assertPresentedOffset(40, in: fixture, scene: fixture.render(at: 0.3))
            let countBeforeRetarget = fixture.state.offsets.count

            withAnimation(.linear(duration: 0.6)) {
                fixture.proxy.scrollTo("top", anchor: .top)
            }
            XCTAssertEqual(fixture.scroller.scrollOffset, 0)
            Self.assertPresentedOffset(40, in: fixture, scene: fixture.render(at: 0.3))
            XCTAssertEqual(fixture.state.offsets.count, countBeforeRetarget)
            Self.assertPresentedOffset(20, in: fixture, scene: fixture.render(at: 0.6))
            Self.assertPresentedOffset(0, in: fixture, scene: fixture.render(at: 0.9))
            XCTAssertEqual(fixture.state.phases.last, .idle)
        }
    }

    func testUserInputInterruptsProgrammaticMotionAndRemovalStopsFurtherDelivery() async throws {
        try await MainActor.run {
            for useKeyboard in [false, true] {
                let fixture = try Self.makeFixture()
                fixture.scroller.scrollStep = 20
                withAnimation(.linear(duration: 0.6)) {
                    fixture.proxy.scrollTo("marker", anchor: .top)
                }
                _ = fixture.render(at: 0)
                Self.assertPresentedOffset(40, in: fixture, scene: fixture.render(at: 0.3))
                fixture.runtime.pointerMoved(to: Point(x: 30, y: 30))
                if useKeyboard {
                    fixture.runtime.keyDown(KeyboardEvent(keyCode: KeyboardKey.downArrow.rawValue))
                } else {
                    fixture.runtime.mouseWheel(at: Point(x: 30, y: 30), delta: -1)
                }

                Self.assertPresentedOffset(60, in: fixture, scene: fixture.render(at: 1))
                XCTAssertEqual(fixture.scroller.scrollOffset, 60, accuracy: 0.0001)
                XCTAssertEqual(fixture.state.phases.last, .idle)
                let count = fixture.state.offsets.count
                Self.assertPresentedOffset(60, in: fixture, scene: fixture.render(at: 2))
                XCTAssertEqual(fixture.state.offsets.count, count, "The cancelled target of 80 cannot resume")
            }

            let removed = try Self.makeFixture()
            withAnimation(.linear(duration: 0.6)) {
                removed.proxy.scrollTo("marker", anchor: .top)
            }
            _ = removed.render(at: 0)
            _ = removed.render(at: 0.3)
            let offsetsBeforeRemoval = removed.state.offsets
            let phasesBeforeRemoval = removed.state.phases
            removed.runtime.root.removeAllChildren()
            _ = removed.render(at: 1)
            _ = removed.render(at: 2)
            XCTAssertEqual(removed.state.offsets, offsetsBeforeRemoval)
            XCTAssertEqual(removed.state.phases, phasesBeforeRemoval)
            XCTAssertFalse(removed.runtime.hasActiveAnimations)
        }
    }
}
