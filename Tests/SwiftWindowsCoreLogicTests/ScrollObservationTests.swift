import SwiftWindowsCore
import SwiftWindowsGraphics
import SwiftWindowsLayout
import XCTest

@testable import SwiftWindowsUI

final class ScrollObservationTests: XCTestCase {
    func testGeometrySanitizesNonfiniteInsetsAndNaturalContentExtents() async {
        await MainActor.run {
            let scroller = ViewNode(
                frame: Rect(x: 0, y: 0, width: 100, height: 80),
                clipsToBounds: true,
                layoutMode: .stack(
                    .vertical(padding: EdgeInsets(top: .infinity, leading: .nan, bottom: 0, trailing: 0))),
                scrollAxis: .vertical,
                children: [ViewNode(preferredSize: Size(width: 40, height: 30))])
            let runtime = RetainedViewRuntime(root: scroller)
            var values: [RetainedScrollGeometry] = []
            scroller.observeScrollGeometry(of: { $0 }) { _, new in values.append(new) }

            _ = runtime.renderFrame()
            _ = runtime.renderScene()
            guard let geometry = values.first else { return XCTFail("Expected resolved scroll geometry") }
            let coordinates = [
                geometry.contentOffset.x, geometry.contentOffset.y,
                geometry.contentSize.width, geometry.contentSize.height,
                geometry.contentInsets.top, geometry.contentInsets.leading,
                geometry.contentInsets.bottom, geometry.contentInsets.trailing,
                geometry.containerSize.width, geometry.containerSize.height,
            ]
            XCTAssertTrue(coordinates.allSatisfy(\.isFinite))
            XCTAssertTrue(coordinates.allSatisfy { abs($0) <= Double(GPUISceneLimits.maxCoordinate) })
            XCTAssertEqual(geometry.contentInsets.leading, 0)
            XCTAssertEqual(geometry.contentInsets.top, Double(GPUISceneLimits.maxCoordinate))
            XCTAssertEqual(geometry.contentOffset.y, -geometry.contentInsets.top)
            XCTAssertEqual(values.count, 1, "Invalid margins must not turn Equatable deduplication into a loop")
        }
    }

    @MainActor
    private static func makeScrollRuntime(
        contentHeight: Double = 1_200
    ) -> (runtime: RetainedViewRuntime, scroller: ViewNode, content: ViewNode, clock: RuntimeTestClock) {
        let marker = ViewNode(
            frame: Rect(x: 0, y: 20, width: 40, height: 8), backgroundColor: .white)
        let content = ViewNode(
            frame: Rect(x: 0, y: 0, width: 80, height: contentHeight), children: [marker])
        let scroller = ViewNode(
            frame: Rect(x: 10, y: 10, width: 80, height: 80),
            clipsToBounds: true,
            scrollAxis: .vertical,
            scrollStep: 20,
            children: [content])
        let runtime = RetainedViewRuntime(
            root: ViewNode(
                frame: Rect(x: 0, y: 0, width: 100, height: 100),
                isHitTestVisible: false,
                children: [scroller]))
        let clock = RuntimeTestClock()
        runtime.clock = { clock.now }
        return (runtime, scroller, content, clock)
    }

    @MainActor
    private static func rebuiltScroller(matching scroller: ViewNode) -> ViewNode {
        ViewNode(
            frame: scroller.frame,
            clipsToBounds: true,
            scrollAxis: .vertical,
            scrollStep: scroller.scrollStep,
            children: [ViewNode(frame: Rect(x: 0, y: 0, width: 80, height: 1_200))])
    }

    func testGeometryInitialDeliveryUsesResolvedLayoutAndDeduplicatesBothRenderPaths() async {
        await MainActor.run {
            let (runtime, scroller, content, _) = Self.makeScrollRuntime()
            var values: [(old: RetainedScrollGeometry, new: RetainedScrollGeometry)] = []
            scroller.observeScrollGeometry(of: { $0 }) { old, new in
                values.append((old, new))
            }

            XCTAssertTrue(values.isEmpty, "Registration must not sample unresolved layout")
            _ = runtime.renderFrame()
            XCTAssertEqual(values.count, 1)
            XCTAssertEqual(values.first?.old, values.first?.new)
            XCTAssertEqual(values.first?.new.contentOffset, .zero)
            XCTAssertEqual(values.first?.new.containerSize, Size(width: 80, height: 80))
            XCTAssertEqual(values.first?.new.contentSize, Size(width: 80, height: 1_200))
            XCTAssertEqual(values.first?.new.contentInsets, .zero)

            _ = runtime.renderFrame()
            _ = runtime.renderScene()
            _ = runtime.renderScene()
            XCTAssertEqual(values.count, 1)

            content.frame.size.height = 1_600
            _ = runtime.renderScene()
            XCTAssertEqual(values.count, 2)
            XCTAssertEqual(values.last?.old.contentSize.height, 1_200)
            XCTAssertEqual(values.last?.new.contentSize.height, 1_600)

            scroller.frame.size.height = 60
            _ = runtime.renderFrame()
            XCTAssertEqual(values.count, 3)
            XCTAssertEqual(values.last?.old.containerSize.height, 80)
            XCTAssertEqual(values.last?.new.containerSize.height, 60)
        }
    }

    func testGeometryActionsCompareTheTransformedValueInsteadOfRawGeometry() async {
        await MainActor.run {
            let (runtime, scroller, _, _) = Self.makeScrollRuntime()
            var values: [(old: Int, new: Int)] = []
            scroller.observeScrollGeometry(of: { Int($0.contentOffset.y / 25) }) { old, new in
                values.append((old, new))
            }
            _ = runtime.renderScene()

            scroller.scrollOffset = 10
            _ = runtime.renderFrame()
            XCTAssertEqual(values.count, 1)

            scroller.scrollOffset = 30
            _ = runtime.renderScene()
            scroller.scrollOffset = 20
            _ = runtime.renderFrame()
            _ = runtime.renderScene()

            XCTAssertEqual(values.map { $0.old }, [0, 0, 1])
            XCTAssertEqual(values.map { $0.new }, [0, 1, 0])
        }
    }

    func testOptionalGeometryProjectionStoresAndDeduplicatesNil() async {
        await MainActor.run {
            let (runtime, scroller, _, _) = Self.makeScrollRuntime()
            var values: [(old: Double?, new: Double?)] = []
            scroller.observeScrollGeometry(of: { geometry -> Double? in
                geometry.contentOffset.y >= 20 ? geometry.contentOffset.y : nil
            }) { old, new in
                values.append((old, new))
            }

            _ = runtime.renderScene()
            _ = runtime.renderFrame()
            scroller.scrollOffset = 10
            _ = runtime.renderScene()
            XCTAssertEqual(values.count, 1, "A stored nil projection is still an initialized observation")
            XCTAssertEqual(values.map { $0.old }, [nil])
            XCTAssertEqual(values.map { $0.new }, [nil])

            scroller.scrollOffset = 20
            _ = runtime.renderFrame()
            scroller.scrollOffset = 0
            _ = runtime.renderScene()
            _ = runtime.renderFrame()
            XCTAssertEqual(values.map { $0.old }, [nil, nil, 20])
            XCTAssertEqual(values.map { $0.new }, [nil, 20, nil])
        }
    }

    func testRemovingTheScrollAxisClearsAWrapperObserversSourceHistoryAndPendingPhases() async {
        await MainActor.run {
            let (runtime, scroller, _, clock) = Self.makeScrollRuntime()
            scroller.scrollOffset = 40
            var offsets: [(old: Double, new: Double)] = []
            var phases: [RetainedScrollPhase] = []
            runtime.root.observeScrollGeometry(of: { $0.contentOffset.y }) { old, new in
                offsets.append((old, new))
            }
            runtime.root.observeScrollPhase { _, new, _ in phases.append(new) }
            _ = runtime.renderScene()
            guard let storage = runtime.root.scrollObserverStorage else {
                return XCTFail("Expected the wrapper to own observer storage")
            }
            XCTAssertTrue(storage.source === scroller)
            XCTAssertNotNil(storage.geometry.first?.previousValue)

            runtime.mouseWheel(at: Point(x: 30, y: 30), delta: -1, source: .precise)
            XCTAssertFalse(storage.phaseChanges.isEmpty)
            scroller.scrollAxis = nil
            _ = runtime.renderFrame()
            XCTAssertNil(scroller.scrollContainerState)
            XCTAssertNil(storage.source)
            XCTAssertNil(storage.geometry.first?.previousValue)
            XCTAssertTrue(storage.phaseChanges.isEmpty)
            XCTAssertEqual(storage.currentPhase, .idle)
            XCTAssertEqual(offsets.map { $0.new }, [40])
            XCTAssertTrue(phases.isEmpty)

            clock.now = 1
            _ = runtime.tickAnimations(at: clock.now)
            scroller.scrollOffset = 80
            _ = runtime.renderScene()
            XCTAssertEqual(offsets.map { $0.new }, [40])
            XCTAssertTrue(phases.isEmpty)

            scroller.scrollAxis = .vertical
            _ = runtime.renderFrame()
            XCTAssertTrue(storage.source === scroller)
            XCTAssertEqual(offsets.map { $0.old }, [40, 80])
            XCTAssertEqual(offsets.map { $0.new }, [40, 80])
            XCTAssertTrue(phases.isEmpty)
        }
    }

    func testGeometryReportsTheClampedOffsetForAnOutOfRangeLogicalRequest() async {
        await MainActor.run {
            let (runtime, scroller, _, _) = Self.makeScrollRuntime(contentHeight: 400)
            var offsets: [Double] = []
            scroller.observeScrollGeometry(of: { $0.contentOffset.y }) { _, new in offsets.append(new) }
            _ = runtime.renderScene()

            scroller.scrollOffset = 10_000
            _ = runtime.renderFrame()
            XCTAssertEqual(offsets, [0, 320])
            scroller.scrollOffset = -50
            _ = runtime.renderScene()
            XCTAssertEqual(offsets, [0, 320, 0])
        }
    }

    func testGeometryTracksPaintedKeyboardOffsetsInsteadOfTheImmediateTarget() async {
        await MainActor.run {
            let (runtime, scroller, _, clock) = Self.makeScrollRuntime()
            var offsets: [Double] = []
            scroller.observeScrollGeometry(of: { $0.contentOffset.y }) { _, new in offsets.append(new) }
            _ = runtime.renderScene()

            runtime.pointerMoved(to: Point(x: 30, y: 30))
            runtime.keyDown(KeyboardEvent(keyCode: KeyboardKey.downArrow.rawValue))
            XCTAssertEqual(scroller.scrollOffset, 20)
            XCTAssertEqual(offsets, [0], "Input handlers do not deliver observation actions")
            _ = runtime.renderScene()
            XCTAssertEqual(offsets, [0], "The first animated frame still paints the original offset")

            for time in [0.055, 0.11, 0.22] {
                clock.now = time
                _ = runtime.tickAnimations(at: time)
                let scene = runtime.renderScene()
                guard let offset = offsets.last, let marker = scene.layers.flatMap(\.quads).first else {
                    return XCTFail("Expected both the observed offset and the painted marker")
                }
                XCTAssertEqual(offset, scroller.resolvedScrollOffset, accuracy: 0.0001)
                XCTAssertEqual(Double(marker.y), 30 - offset, accuracy: 0.001)
            }
            guard offsets.count == 4 else {
                return XCTFail("Expected one initial sample and one sample for each animation frame")
            }
            XCTAssertEqual(offsets.last ?? -1, 20, accuracy: 0.0001)
            XCTAssertLessThan(offsets[1], offsets[2])
            XCTAssertLessThan(offsets[2], offsets[3])
        }
    }

    func testGeometryIncludesRubberBandOvershootUntilThePaintedContentSettles() async {
        await MainActor.run {
            let (runtime, scroller, _, clock) = Self.makeScrollRuntime()
            var offsets: [Double] = []
            scroller.observeScrollGeometry(of: { $0.contentOffset.y }) { _, new in offsets.append(new) }
            _ = runtime.renderScene()

            runtime.mouseWheel(at: Point(x: 30, y: 30), delta: 3)
            XCTAssertEqual(scroller.scrollOffset, 0)
            XCTAssertLessThan(scroller.scrollOvershoot, 0)
            for time in [0.0, 0.05, 0.1, 1.0] {
                clock.now = time
                _ = runtime.tickAnimations(at: time)
                let scene = runtime.renderScene()
                guard let offset = offsets.last, let marker = scene.layers.flatMap(\.quads).first else {
                    return XCTFail("Expected a visible marker throughout the rubber-band return")
                }
                XCTAssertEqual(offset, scroller.scrollOvershoot, accuracy: 0.0001)
                XCTAssertEqual(Double(marker.y), 30 - offset, accuracy: 0.001)
            }
            XCTAssertTrue(offsets.contains { $0 < 0 })
            XCTAssertEqual(offsets.last ?? -1, 0, accuracy: 0.0001)
            let count = offsets.count
            _ = runtime.renderScene()
            XCTAssertEqual(offsets.count, count)
        }
    }

    func testHorizontalGeometryReportsHorizontalOffsetAndStackContentInsets() async {
        await MainActor.run {
            let padding = EdgeInsets(top: 5, leading: 7, bottom: 11, trailing: 13)
            let scroller = ViewNode(
                frame: Rect(x: 0, y: 0, width: 100, height: 80),
                clipsToBounds: true,
                layoutMode: .stack(.horizontal(padding: padding)),
                scrollAxis: .horizontal,
                scrollOffset: 30,
                children: [ViewNode(preferredSize: Size(width: 240, height: 30))])
            let runtime = RetainedViewRuntime(root: scroller)
            var geometries: [RetainedScrollGeometry] = []
            scroller.observeScrollGeometry(of: { $0 }) { _, new in geometries.append(new) }

            _ = runtime.renderScene()
            XCTAssertEqual(geometries.count, 1)
            XCTAssertEqual(geometries.first?.contentOffset, Point(x: 23, y: -5))
            XCTAssertEqual(geometries.first?.contentInsets, padding)
            XCTAssertEqual(geometries.first?.contentSize, Size(width: 240, height: 30))
            XCTAssertEqual(geometries.first?.containerSize, Size(width: 100, height: 80))

            scroller.scrollOffset = 50
            _ = runtime.renderFrame()
            XCTAssertEqual(geometries.last?.contentOffset, Point(x: 43, y: -5))
        }
    }

    func testGeometryPreservesContentSizeWhenContentIsShorterThanTheContainer() async {
        await MainActor.run {
            let scroller = ViewNode(
                frame: Rect(x: 0, y: 0, width: 80, height: 80),
                clipsToBounds: true,
                scrollAxis: .vertical,
                children: [ViewNode(frame: Rect(x: 0, y: 0, width: 30, height: 20))])
            let runtime = RetainedViewRuntime(root: scroller)
            var geometries: [RetainedScrollGeometry] = []
            scroller.observeScrollGeometry(of: { $0 }) { _, new in geometries.append(new) }

            _ = runtime.renderScene()
            XCTAssertEqual(geometries.first?.contentSize, Size(width: 30, height: 20))
            XCTAssertEqual(geometries.first?.containerSize, Size(width: 80, height: 80))

            scroller.removeAllChildren()
            _ = runtime.renderFrame()
            XCTAssertEqual(geometries.count, 2)
            XCTAssertEqual(geometries.last?.contentSize, .zero)
            XCTAssertEqual(geometries.last?.containerSize, Size(width: 80, height: 80))
        }
    }

    func testGeometryOwnerSelectsItsFirstEnclosedScrollViewAndNestedOwnersStayIndependent() async {
        await MainActor.run {
            let (runtime, outer, content, _) = Self.makeScrollRuntime()
            let inner = ViewNode(
                frame: Rect(x: 0, y: 0, width: 40, height: 40),
                clipsToBounds: true,
                scrollAxis: .vertical,
                scrollOffset: 10,
                children: [ViewNode(frame: Rect(x: 0, y: 0, width: 40, height: 400))])
            content.addChild(inner)
            let sibling = Self.rebuiltScroller(matching: outer)
            runtime.root.addChild(sibling)
            var wrapperOffsets: [Double] = []
            var outerOffsets: [Double] = []
            var innerOffsets: [Double] = []
            runtime.root.observeScrollGeometry(of: { $0.contentOffset.y }) { _, new in
                wrapperOffsets.append(new)
            }
            outer.observeScrollGeometry(of: { $0.contentOffset.y }) { _, new in outerOffsets.append(new) }
            inner.observeScrollGeometry(of: { $0.contentOffset.y }) { _, new in innerOffsets.append(new) }
            _ = runtime.renderScene()

            inner.scrollOffset = 30
            sibling.scrollOffset = 50
            _ = runtime.renderFrame()
            XCTAssertEqual(wrapperOffsets, [0])
            XCTAssertEqual(outerOffsets, [0])
            XCTAssertEqual(innerOffsets, [10, 30])

            outer.scrollOffset = 25
            _ = runtime.renderScene()
            XCTAssertEqual(wrapperOffsets, [0, 25])
            XCTAssertEqual(outerOffsets, [0, 25])
            XCTAssertEqual(innerOffsets, [10, 30])
        }
    }

    func testGeometryOwnerWithoutAnEnclosedScrollViewDoesNotObserveItsAncestor() async {
        await MainActor.run {
            let (runtime, scroller, content, _) = Self.makeScrollRuntime()
            var calls = 0
            content.observeScrollGeometry(of: { $0.contentOffset }) { _, _ in calls += 1 }
            _ = runtime.renderScene()
            scroller.scrollOffset = 20
            _ = runtime.renderFrame()
            XCTAssertEqual(calls, 0)
        }
    }

    func testNotchedWheelQueuesInteractingThenIdleUntilTheNextRenderedFrame() async {
        await MainActor.run {
            let (runtime, scroller, _, _) = Self.makeScrollRuntime()
            var events: [(old: RetainedScrollPhase, new: RetainedScrollPhase)] = []
            var contexts: [RetainedScrollPhaseChangeContext] = []
            scroller.observeScrollPhase { old, new, context in
                events.append((old, new))
                contexts.append(context)
            }
            _ = runtime.renderFrame()
            XCTAssertTrue(events.isEmpty, "An initial idle sample is not a phase change")

            runtime.mouseWheel(at: Point(x: 30, y: 30), delta: -1)
            XCTAssertTrue(events.isEmpty)
            _ = runtime.renderFrame()
            XCTAssertEqual(events.map { $0.old }, [.idle, .interacting])
            XCTAssertEqual(events.map { $0.new }, [.interacting, .idle])
            XCTAssertEqual(contexts.last?.geometry.contentOffset, Point(x: 0, y: 20))
            _ = runtime.renderScene()
            _ = runtime.renderFrame()
            XCTAssertEqual(events.count, 2)
        }
    }

    func testRepeatedWheelEventsKeepTheUnpresentedPhaseQueueBounded() async {
        await MainActor.run {
            let (runtime, scroller, _, _) = Self.makeScrollRuntime(contentHeight: 20_000)
            var events: [(old: RetainedScrollPhase, new: RetainedScrollPhase)] = []
            scroller.observeScrollPhase { old, new, _ in events.append((old, new)) }
            _ = runtime.renderScene()
            guard let storage = scroller.scrollObserverStorage else {
                return XCTFail("Expected phase observer storage")
            }

            var maximumQueuedPhases = 0
            for _ in 0..<512 {
                runtime.mouseWheel(at: Point(x: 30, y: 30), delta: -1)
                maximumQueuedPhases = max(maximumQueuedPhases, storage.phaseChanges.count)
            }
            XCTAssertTrue(events.isEmpty)
            XCTAssertLessThanOrEqual(maximumQueuedPhases, 5)
            XCTAssertEqual(scroller.scrollOffset, 10_240)

            _ = runtime.renderFrame()
            XCTAssertEqual(events.map { $0.old }, [.idle, .interacting])
            XCTAssertEqual(events.map { $0.new }, [.interacting, .idle])
            XCTAssertTrue(storage.phaseChanges.isEmpty)
        }
    }

    func testPreciseWheelReportsDecelerationGeometryAndIdleAtRest() async {
        await MainActor.run {
            let (runtime, scroller, _, clock) = Self.makeScrollRuntime()
            var phases: [RetainedScrollPhase] = []
            var contexts: [RetainedScrollPhaseChangeContext] = []
            var offsets: [Double] = []
            scroller.observeScrollGeometry(of: { $0.contentOffset.y }) { _, new in offsets.append(new) }
            scroller.observeScrollPhase { _, new, context in
                phases.append(new)
                contexts.append(context)
            }
            _ = runtime.renderScene()

            runtime.mouseWheel(at: Point(x: 30, y: 30), delta: -3, source: .precise)
            XCTAssertTrue(phases.isEmpty)
            _ = runtime.renderScene()
            XCTAssertEqual(phases, [.interacting, .decelerating])
            XCTAssertEqual(offsets, [0, 60])
            XCTAssertGreaterThan(contexts.last?.velocity?.y ?? 0, 0)

            clock.now = 0.5
            _ = runtime.tickAnimations(at: clock.now)
            _ = runtime.renderFrame()
            XCTAssertGreaterThan(offsets.last ?? 0, 60)
            XCTAssertEqual(offsets.last ?? -1, scroller.resolvedScrollOffset, accuracy: 0.0001)

            clock.now = 1
            _ = runtime.tickAnimations(at: clock.now)
            _ = runtime.renderScene()
            XCTAssertEqual(phases, [.interacting, .decelerating, .idle])
            XCTAssertEqual(
                contexts.last?.geometry.contentOffset.y ?? -1, scroller.resolvedScrollOffset, accuracy: 0.0001)
            XCTAssertFalse(runtime.hasActiveAnimations)
            let count = offsets.count
            _ = runtime.renderScene()
            XCTAssertEqual(offsets.count, count)
            XCTAssertEqual(phases.count, 3)
        }
    }

    func testKeyboardPhaseStaysAnimatingUntilThePresentedTweenFinishes() async {
        await MainActor.run {
            let (runtime, scroller, _, clock) = Self.makeScrollRuntime()
            var phases: [RetainedScrollPhase] = []
            scroller.observeScrollPhase { _, new, _ in phases.append(new) }
            _ = runtime.renderScene()
            runtime.pointerMoved(to: Point(x: 30, y: 30))
            runtime.keyDown(KeyboardEvent(keyCode: KeyboardKey.downArrow.rawValue))
            XCTAssertTrue(phases.isEmpty)
            _ = runtime.renderScene()
            XCTAssertEqual(phases, [.animating])

            clock.now = 0.11
            _ = runtime.tickAnimations(at: clock.now)
            _ = runtime.renderFrame()
            XCTAssertEqual(phases, [.animating])

            clock.now = 0.22
            _ = runtime.tickAnimations(at: clock.now)
            _ = runtime.renderScene()
            XCTAssertEqual(phases, [.animating, .idle])
        }
    }

    func testDisablingInputMidKeyboardTweenFreezesThePaintedAndObservedOffset() async {
        await MainActor.run {
            let (runtime, scroller, _, clock) = Self.makeScrollRuntime()
            var offsets: [Double] = []
            scroller.observeScrollGeometry(of: { $0.contentOffset.y }) { _, new in offsets.append(new) }
            _ = runtime.renderScene()
            runtime.pointerMoved(to: Point(x: 30, y: 30))
            runtime.keyDown(KeyboardEvent(keyCode: KeyboardKey.downArrow.rawValue))
            clock.now = 0.055
            _ = runtime.tickAnimations(at: clock.now)
            _ = runtime.renderScene()
            let presented = scroller.resolvedScrollOffset
            XCTAssertGreaterThan(presented, 0)
            XCTAssertLessThan(presented, 20)
            XCTAssertEqual(scroller.scrollOffset, 20)

            scroller.isScrollInputEnabled = false
            let scene = runtime.renderScene()
            XCTAssertEqual(scroller.scrollAxis, .vertical)
            XCTAssertEqual(scroller.scrollOffset, presented, accuracy: 0.0001)
            XCTAssertEqual(scroller.scrollPresentedDelta, 0)
            XCTAssertEqual(scroller.resolvedScrollOffset, presented, accuracy: 0.0001)
            XCTAssertEqual(offsets.last ?? -1, presented, accuracy: 0.0001)
            guard let marker = scene.layers.flatMap(\.quads).first else {
                return XCTFail("Expected the frozen marker to remain visible")
            }
            XCTAssertEqual(Double(marker.y), 30 - presented, accuracy: 0.001)

            runtime.mouseWheel(at: Point(x: 30, y: 30), delta: -1)
            runtime.keyDown(KeyboardEvent(keyCode: KeyboardKey.downArrow.rawValue))
            clock.now = 1
            _ = runtime.tickAnimations(at: clock.now)
            _ = runtime.renderFrame()
            XCTAssertEqual(scroller.scrollOffset, presented, accuracy: 0.0001)
            XCTAssertEqual(scroller.resolvedScrollOffset, presented, accuracy: 0.0001)
            XCTAssertEqual(offsets.last ?? -1, presented, accuracy: 0.0001)
            XCTAssertFalse(runtime.hasActiveAnimations)
        }
    }

    func testIndicatorDragReportsTrackingInteractingAndIdleInOrder() async {
        await MainActor.run {
            let (runtime, scroller, _, _) = Self.makeScrollRuntime()
            scroller.showsScrollIndicator = true
            var phases: [RetainedScrollPhase] = []
            scroller.observeScrollPhase { _, new, _ in phases.append(new) }
            _ = runtime.renderFrame()
            guard let thumb = scroller.scrollIndicatorRect(in: scroller.frame) else {
                return XCTFail("Expected a scroll thumb")
            }
            let start = Point(x: thumb.midX, y: thumb.midY)
            let end = Point(x: start.x, y: start.y + 20)
            runtime.pointerDown(at: start)
            _ = runtime.renderFrame()
            XCTAssertEqual(phases, [.tracking])

            runtime.pointerMoved(to: end)
            runtime.pointerUp(at: end)
            _ = runtime.renderScene()
            XCTAssertGreaterThan(scroller.scrollOffset, 0)
            XCTAssertEqual(phases, [.tracking, .interacting, .idle])
        }
    }

    func testCancelledIndicatorDragReturnsToIdle() async {
        await MainActor.run {
            let (runtime, scroller, _, _) = Self.makeScrollRuntime()
            scroller.showsScrollIndicator = true
            var phases: [RetainedScrollPhase] = []
            scroller.observeScrollPhase { _, new, _ in phases.append(new) }
            _ = runtime.renderScene()
            guard let thumb = scroller.scrollIndicatorRect(in: scroller.frame) else {
                return XCTFail("Expected a scroll thumb")
            }
            let point = Point(x: thumb.midX, y: thumb.midY)
            runtime.pointerDown(at: point)
            runtime.pointerMoved(to: Point(x: point.x, y: point.y + 10))
            runtime.pointerCancelled()
            _ = runtime.renderFrame()
            XCTAssertEqual(phases, [.tracking, .interacting, .idle])
        }
    }

    func testReconciliationPreservesEachGeometryObserverHistoryAndReplacesItsAction() async {
        await MainActor.run {
            let (runtime, scroller, _, _) = Self.makeScrollRuntime()
            var oldValues: [Double] = []
            var newFirst: [(old: Double, new: Double)] = []
            var newSecond: [(old: Double, new: Double)] = []
            scroller.observeScrollGeometry(of: { $0.contentOffset.y }) { _, new in oldValues.append(new) }
            scroller.observeScrollGeometry(of: { $0.contentOffset.y * 2 }) { _, new in oldValues.append(new) }
            _ = runtime.renderScene()
            scroller.scrollOffset = 20
            _ = runtime.renderScene()
            XCTAssertEqual(oldValues, [0, 0, 20, 40])

            let rebuilt = Self.rebuiltScroller(matching: scroller)
            rebuilt.observeScrollGeometry(of: { $0.contentOffset.y }) { old, new in newFirst.append((old, new)) }
            rebuilt.observeScrollGeometry(of: { $0.contentOffset.y * 2 }) { old, new in newSecond.append((old, new)) }
            ComponentHost.adopt(source: rebuilt, into: scroller)
            _ = runtime.renderFrame()
            XCTAssertTrue(newFirst.isEmpty)
            XCTAssertTrue(newSecond.isEmpty)
            XCTAssertEqual(scroller.scrollOffset, 20)

            scroller.scrollOffset = 40
            _ = runtime.renderScene()
            XCTAssertEqual(oldValues, [0, 0, 20, 40])
            XCTAssertEqual(newFirst.map { $0.old }, [20])
            XCTAssertEqual(newFirst.map { $0.new }, [40])
            XCTAssertEqual(newSecond.map { $0.old }, [40])
            XCTAssertEqual(newSecond.map { $0.new }, [80])
        }
    }

    func testReconciliationRefreshesPhaseAndVisibilityActionsWithoutInitialDuplicates() async {
        await MainActor.run {
            let (runtime, scroller, _, _) = Self.makeScrollRuntime()
            var oldPhases: [RetainedScrollPhase] = []
            var newPhases: [RetainedScrollPhase] = []
            var oldVisibility: [Bool] = []
            var newVisibility: [Bool] = []
            scroller.observeScrollPhase { _, new, _ in oldPhases.append(new) }
            scroller.observeScrollVisibility { oldVisibility.append($0) }
            _ = runtime.renderScene()
            runtime.mouseWheel(at: Point(x: 30, y: 30), delta: -1)
            _ = runtime.renderScene()
            XCTAssertEqual(oldVisibility, [true])
            XCTAssertEqual(oldPhases, [.interacting, .idle])

            let rebuilt = Self.rebuiltScroller(matching: scroller)
            rebuilt.observeScrollPhase { _, new, _ in newPhases.append(new) }
            rebuilt.observeScrollVisibility { newVisibility.append($0) }
            ComponentHost.adopt(source: rebuilt, into: scroller)
            _ = runtime.renderFrame()
            XCTAssertTrue(newPhases.isEmpty)
            XCTAssertTrue(newVisibility.isEmpty)

            runtime.mouseWheel(at: Point(x: 30, y: 30), delta: -1)
            _ = runtime.renderScene()
            XCTAssertEqual(newPhases, [.interacting, .idle])
            scroller.isHidden = true
            _ = runtime.renderFrame()
            XCTAssertEqual(newVisibility, [false])
            XCTAssertEqual(oldVisibility, [true])
            XCTAssertEqual(oldPhases, [.interacting, .idle])
        }
    }

    func testReconciliationReplacesTheTransformWhileKeepingThePreviousTransformedValue() async {
        await MainActor.run {
            let (runtime, scroller, _, _) = Self.makeScrollRuntime()
            var oldValues: [Double] = []
            var newValues: [(old: Double, new: Double)] = []
            scroller.observeScrollGeometry(of: { $0.contentOffset.y }) { _, new in oldValues.append(new) }
            _ = runtime.renderScene()
            scroller.scrollOffset = 20
            _ = runtime.renderScene()

            let rebuilt = Self.rebuiltScroller(matching: scroller)
            rebuilt.observeScrollGeometry(of: { $0.contentOffset.y + 100 }) { old, new in
                newValues.append((old, new))
            }
            ComponentHost.adopt(source: rebuilt, into: scroller)
            _ = runtime.renderFrame()

            XCTAssertEqual(oldValues, [0, 20])
            XCTAssertEqual(newValues.map { $0.old }, [20])
            XCTAssertEqual(newValues.map { $0.new }, [120])
        }
    }

    func testVisibilityThresholdCrossingsUseTheFractionInsideTheScrollViewport() async {
        await MainActor.run {
            let (runtime, scroller, content, _) = Self.makeScrollRuntime()
            let row = ViewNode(frame: Rect(x: 0, y: 70, width: 40, height: 40), backgroundColor: .white)
            content.addChild(row)
            var visibility: [Bool] = []
            row.observeScrollVisibility { visibility.append($0) }
            XCTAssertTrue(visibility.isEmpty)
            _ = runtime.renderScene()
            XCTAssertEqual(visibility, [false], "Only one quarter of the row is inside the viewport")

            scroller.scrollOffset = 10
            _ = runtime.renderFrame()
            XCTAssertEqual(visibility, [false, true], "The default threshold includes exactly one half")
            scroller.scrollOffset = 50
            _ = runtime.renderScene()
            XCTAssertEqual(visibility, [false, true], "Movement inside the same threshold does not repeat callbacks")
            scroller.scrollOffset = 110
            _ = runtime.renderFrame()
            XCTAssertEqual(visibility, [false, true, false])
        }
    }

    func testZeroVisibilityThresholdStillRequiresPositiveVisibleArea() async {
        await MainActor.run {
            let (runtime, scroller, content, _) = Self.makeScrollRuntime()
            let row = ViewNode(frame: Rect(x: 0, y: 80, width: 40, height: 40))
            content.addChild(row)
            var visibility: [Bool] = []
            row.observeScrollVisibility(threshold: 0) { visibility.append($0) }
            _ = runtime.renderScene()
            scroller.scrollOffset = 1
            _ = runtime.renderFrame()
            scroller.scrollOffset = 0
            _ = runtime.renderScene()
            XCTAssertEqual(visibility, [false, true, false])
        }
    }

    func testVisibilityDuringKeyboardAnimationUsesThePaintedViewport() async {
        await MainActor.run {
            let (runtime, scroller, content, clock) = Self.makeScrollRuntime()
            let row = ViewNode(frame: Rect(x: 0, y: 70, width: 40, height: 40))
            content.addChild(row)
            var visibility: [Bool] = []
            row.observeScrollVisibility { visibility.append($0) }
            _ = runtime.renderScene()

            runtime.pointerMoved(to: Point(x: 30, y: 30))
            runtime.keyDown(KeyboardEvent(keyCode: KeyboardKey.downArrow.rawValue))
            _ = runtime.renderFrame()
            XCTAssertEqual(scroller.scrollOffset, 20)
            XCTAssertEqual(scroller.resolvedScrollOffset, 0, accuracy: 0.0001)
            XCTAssertEqual(visibility, [false], "The logical target must not make a still-clipped row visible")

            clock.now = 0.22
            _ = runtime.tickAnimations(at: clock.now)
            _ = runtime.renderScene()
            XCTAssertEqual(visibility, [false, true])
        }
    }

    func testVisibilityIntersectsAncestorClipsAndTheRootSurface() async {
        await MainActor.run {
            let row = ViewNode(frame: Rect(x: 30, y: 0, width: 40, height: 40))
            let content = ViewNode(frame: Rect(x: 0, y: 0, width: 100, height: 400), children: [row])
            let scroller = ViewNode(
                frame: Rect(x: 0, y: 0, width: 100, height: 80),
                clipsToBounds: true,
                scrollAxis: .vertical,
                children: [content])
            let clip = ViewNode(
                frame: Rect(x: 0, y: 0, width: 50, height: 100), clipsToBounds: true, children: [scroller])
            let root = ViewNode(frame: Rect(x: 0, y: 0, width: 100, height: 100), children: [clip])
            let runtime = RetainedViewRuntime(root: root)
            var visibility: [Bool] = []
            row.observeScrollVisibility(threshold: 0.6) { visibility.append($0) }
            _ = runtime.renderScene()
            XCTAssertEqual(visibility, [false], "The non-scroll ancestor clips half the row")

            clip.clipsToBounds = false
            _ = runtime.renderFrame()
            XCTAssertEqual(visibility, [false, true])
            root.frame.size.width = 50
            _ = runtime.renderScene()
            XCTAssertEqual(visibility, [false, true, false], "The root surface also limits visible area")
        }
    }

    func testRotatedAndScaledVisibilityUsesPolygonAreaInsteadOfItsBoundingBox() async {
        await MainActor.run {
            let (runtime, _, content, _) = Self.makeScrollRuntime()
            let row = ViewNode(
                frame: Rect(x: 80, y: 80, width: 20, height: 20),
                backgroundColor: .white,
                transform: Transform2D(scaleX: 2, scaleY: 2, rotation: Double.pi / 4))
            content.addChild(row)
            var visibility: [Bool] = []
            row.observeScrollVisibility(threshold: 0.05) { visibility.append($0) }

            // The viewport contains only a corner triangle of this diamond:
            // about 2.1% of its area. Bounding-box intersection would report 10.4%.
            _ = runtime.renderScene()
            XCTAssertEqual(visibility, [false])

            row.frame.origin = Point(x: 60, y: 60)
            _ = runtime.renderFrame()
            XCTAssertEqual(visibility, [false, true])
        }
    }

    func testZeroSizedVisibilityOwnerDoesNotBecomeVisibleUntilItHasArea() async {
        await MainActor.run {
            let (runtime, _, content, _) = Self.makeScrollRuntime()
            let row = ViewNode(frame: Rect(x: 0, y: 0, width: 0, height: 40))
            content.addChild(row)
            var visibility: [Bool] = []
            row.observeScrollVisibility(threshold: 0) { visibility.append($0) }
            _ = runtime.renderScene()
            XCTAssertEqual(visibility, [false])
            row.frame.size.width = 40
            _ = runtime.renderFrame()
            XCTAssertEqual(visibility, [false, true])
        }
    }

    func testHiddenScrollViewSuppressesGeometryWhileVisibilityChangesOnce() async {
        await MainActor.run {
            let (runtime, scroller, _, _) = Self.makeScrollRuntime()
            var offsets: [Double] = []
            var visibility: [Bool] = []
            scroller.observeScrollGeometry(of: { $0.contentOffset.y }) { _, new in offsets.append(new) }
            scroller.observeScrollVisibility { visibility.append($0) }
            _ = runtime.renderScene()

            scroller.isHidden = true
            scroller.scrollOffset = 20
            _ = runtime.renderFrame()
            _ = runtime.renderScene()
            XCTAssertEqual(offsets, [0])
            XCTAssertEqual(visibility, [true, false])

            scroller.isHidden = false
            _ = runtime.renderFrame()
            XCTAssertEqual(offsets, [0, 20])
            XCTAssertEqual(visibility, [true, false, true])
        }
    }

    func testDetachedObserverReceivesNoQueuedInputOrLaterAnimationCallbacks() async {
        await MainActor.run {
            let (runtime, scroller, _, clock) = Self.makeScrollRuntime()
            var offsets: [Double] = []
            var phases: [RetainedScrollPhase] = []
            var visibility: [Bool] = []
            scroller.observeScrollGeometry(of: { $0.contentOffset.y }) { _, new in offsets.append(new) }
            scroller.observeScrollPhase { _, new, _ in phases.append(new) }
            scroller.observeScrollVisibility { visibility.append($0) }
            _ = runtime.renderScene()

            runtime.mouseWheel(at: Point(x: 30, y: 30), delta: -3, source: .precise)
            runtime.root.removeChild(at: 0)
            _ = runtime.renderFrame()
            clock.now = 1
            _ = runtime.tickAnimations(at: clock.now)
            scroller.scrollOffset = 200
            _ = runtime.renderScene()

            XCTAssertEqual(offsets, [0])
            XCTAssertTrue(phases.isEmpty)
            XCTAssertEqual(visibility, [true])
        }
    }

    func testOrdinaryNodesDoNotAllocateScrollContainerOrObserverStorage() async {
        await MainActor.run {
            let ordinary = ViewNode(frame: Rect(x: 0, y: 0, width: 80, height: 80))
            let runtime = RetainedViewRuntime(root: ordinary)
            XCTAssertNil(ordinary.scrollContainerState)
            XCTAssertNil(ordinary.scrollObserverStorage)

            _ = runtime.renderFrame()
            _ = runtime.renderScene()
            ordinary.scrollAxis = nil
            ComponentHost.adopt(source: ViewNode(frame: ordinary.frame), into: ordinary)
            XCTAssertNil(ordinary.scrollContainerState)
            XCTAssertNil(ordinary.scrollObserverStorage)

            let scroller = ViewNode(scrollAxis: .vertical)
            XCTAssertNotNil(scroller.scrollContainerState)
            XCTAssertNil(scroller.scrollObserverStorage)
            XCTAssertNil(ordinary.scrollContainerState)
            XCTAssertNil(ordinary.scrollObserverStorage)
        }
    }

    func testDetachmentResetsObserverSourceHistoryAndPendingPhases() async {
        await MainActor.run {
            let (runtime, scroller, _, clock) = Self.makeScrollRuntime()
            var geometryCalls = 0
            var phaseCalls = 0
            scroller.observeScrollGeometry(of: { $0.contentOffset }) { _, _ in geometryCalls += 1 }
            scroller.observeScrollPhase { _, _, _ in phaseCalls += 1 }
            _ = runtime.renderScene()
            guard let storage = scroller.scrollObserverStorage else {
                return XCTFail("Expected attached observer storage")
            }
            XCTAssertTrue(storage.source === scroller)
            XCTAssertNotNil(storage.geometry.first?.previousValue)

            runtime.mouseWheel(at: Point(x: 30, y: 30), delta: -1, source: .precise)
            XCTAssertFalse(storage.phaseChanges.isEmpty)
            runtime.root.removeChild(at: 0)
            XCTAssertNil(storage.source)
            XCTAssertEqual(storage.currentPhase, .idle)
            XCTAssertTrue(storage.phaseChanges.isEmpty)
            XCTAssertNil(storage.geometry.first?.previousValue)

            scroller.scrollOffset = 100
            clock.now = 1
            _ = runtime.tickAnimations(at: clock.now)
            _ = runtime.renderFrame()
            XCTAssertEqual(geometryCalls, 1)
            XCTAssertEqual(phaseCalls, 0)
        }
    }

    func testObservationCallbackCanRemoveAnotherPendingObserver() async {
        await MainActor.run {
            let (runtime, first, _, _) = Self.makeScrollRuntime()
            let second = Self.rebuiltScroller(matching: first)
            runtime.root.addChild(second)
            var calls: [String] = []
            first.observeScrollGeometry(of: { $0.contentOffset }) { [weak runtime] _, _ in
                calls.append("first")
                if let runtime, runtime.root.children.count > 1 {
                    runtime.root.removeChild(at: 1)
                }
            }
            second.observeScrollGeometry(of: { $0.contentOffset }) { _, _ in calls.append("second") }

            _ = runtime.renderScene()
            _ = runtime.renderFrame()
            XCTAssertEqual(calls, ["first"], "Removed nodes cannot receive callbacks from an earlier traversal")
        }
    }

    func testDetachAndReattachDuringCallbackDropsTheOldQueuedSample() async {
        await MainActor.run {
            let (runtime, first, _, _) = Self.makeScrollRuntime()
            let second = Self.rebuiltScroller(matching: first)
            runtime.root.addChild(second)
            var firstCalls = 0
            var secondValues: [(old: Double, new: Double)] = []
            first.observeScrollGeometry(of: { $0.contentOffset.y }) { [weak runtime, weak second] _, _ in
                firstCalls += 1
                guard firstCalls == 1, let runtime, let second else { return }
                runtime.root.removeChild(at: 1)
                runtime.root.addChild(second)
            }
            second.observeScrollGeometry(of: { $0.contentOffset.y }) { old, new in
                secondValues.append((old, new))
            }

            _ = runtime.renderScene()
            XCTAssertEqual(firstCalls, 1)
            XCTAssertTrue(secondValues.isEmpty, "Reattaching does not revive a sample queued before detachment")
            XCTAssertTrue(runtime.root.children.last === second)

            _ = runtime.renderFrame()
            _ = runtime.renderScene()
            XCTAssertEqual(firstCalls, 1)
            XCTAssertEqual(secondValues.map { $0.old }, [0])
            XCTAssertEqual(secondValues.map { $0.new }, [0])
        }
    }

    func testObservationCallbackCanChangeOffsetAndRenderWithoutRecursiveDelivery() async {
        await MainActor.run {
            let (runtime, scroller, _, _) = Self.makeScrollRuntime()
            var offsets: [Double] = []
            var callbackDepth = 0
            var maximumDepth = 0
            scroller.observeScrollGeometry(of: { $0.contentOffset.y }) { [weak runtime, weak scroller] _, new in
                callbackDepth += 1
                maximumDepth = max(maximumDepth, callbackDepth)
                defer { callbackDepth -= 1 }
                offsets.append(new)
                if offsets.count == 1, let runtime, let scroller {
                    scroller.scrollOffset = 40
                    _ = runtime.renderScene()
                }
            }

            _ = runtime.renderScene()
            _ = runtime.renderScene()
            _ = runtime.renderFrame()
            XCTAssertEqual(maximumDepth, 1)
            XCTAssertEqual(offsets, [0, 40])
        }
    }

    func testCrossRenderPathCallbackLeavesMutationForTheNextExternalRender() async {
        await MainActor.run {
            for sceneFirst in [true, false] {
                let (runtime, scroller, _, _) = Self.makeScrollRuntime()
                var offsets: [Double] = []
                var callbackDepth = 0
                var maximumDepth = 0
                scroller.observeScrollGeometry(of: { $0.contentOffset.y }) { [weak runtime, weak scroller] _, new in
                    callbackDepth += 1
                    maximumDepth = max(maximumDepth, callbackDepth)
                    defer { callbackDepth -= 1 }
                    offsets.append(new)
                    if offsets.count == 1, let runtime, let scroller {
                        scroller.scrollOffset = 40
                        if sceneFirst {
                            _ = runtime.renderFrame()
                        } else {
                            _ = runtime.renderScene()
                        }
                    }
                }

                if sceneFirst {
                    _ = runtime.renderScene()
                } else {
                    _ = runtime.renderFrame()
                }
                XCTAssertEqual(offsets, [0], "A nested render never recursively delivers observation actions")

                // Reuse the path that painted inside the callback. A clean
                // cache return here must not swallow the pending value of 40.
                if sceneFirst {
                    _ = runtime.renderFrame()
                    _ = runtime.renderFrame()
                } else {
                    _ = runtime.renderScene()
                    _ = runtime.renderScene()
                }
                XCTAssertEqual(maximumDepth, 1)
                XCTAssertEqual(offsets, [0, 40])
            }
        }
    }

    func testGeometryCallbackRebuildCanRemoveAnotherObserverOnTheSameOwner() async {
        await MainActor.run {
            let (runtime, scroller, _, _) = Self.makeScrollRuntime()
            var calls: [String] = []
            scroller.observeScrollGeometry(of: { $0.contentOffset.y }) { [weak scroller] _, _ in
                calls.append("old A")
                guard let scroller else { return }
                let replacement = Self.rebuiltScroller(matching: scroller)
                replacement.observeScrollGeometry(of: { $0.contentOffset.y }) { _, _ in
                    calls.append("new A")
                }
                ComponentHost.adopt(source: replacement, into: scroller)
            }
            scroller.observeScrollGeometry(of: { $0.contentOffset.y + 10 }) { _, _ in
                calls.append("removed B")
            }

            _ = runtime.renderScene()
            XCTAssertEqual(calls, ["old A"])
            _ = runtime.renderFrame()
            _ = runtime.renderScene()
            XCTAssertEqual(
                calls, ["old A"], "The completed A sample survives; removed B never receives its queued sample")
        }
    }

    func testGeometryCallbackRebuildRetriesUndeliveredObserverWithItsFreshTransformAndAction() async {
        await MainActor.run {
            let (runtime, scroller, _, _) = Self.makeScrollRuntime()
            var oldACalls = 0
            var newACalls = 0
            var oldBCalls = 0
            var newBValues: [(old: Double, new: Double)] = []
            scroller.observeScrollGeometry(of: { $0.contentOffset.y }) { [weak scroller] _, _ in
                oldACalls += 1
                guard let scroller else { return }
                let replacement = Self.rebuiltScroller(matching: scroller)
                replacement.observeScrollGeometry(of: { $0.contentOffset.y }) { _, _ in newACalls += 1 }
                replacement.observeScrollGeometry(of: { $0.contentOffset.y + 100 }) { old, new in
                    newBValues.append((old, new))
                }
                ComponentHost.adopt(source: replacement, into: scroller)
            }
            scroller.observeScrollGeometry(of: { $0.contentOffset.y + 10 }) { _, _ in oldBCalls += 1 }

            _ = runtime.renderScene()
            XCTAssertEqual(oldACalls, 1)
            XCTAssertEqual(oldBCalls, 0)
            XCTAssertTrue(newBValues.isEmpty, "A replacement callback waits for the next completed render")

            _ = runtime.renderFrame()
            _ = runtime.renderScene()
            XCTAssertEqual(oldACalls, 1)
            XCTAssertEqual(newACalls, 0)
            XCTAssertEqual(oldBCalls, 0)
            XCTAssertEqual(newBValues.map { $0.old }, [100], "B's cancelled value of 10 was never delivered")
            XCTAssertEqual(newBValues.map { $0.new }, [100])
        }
    }

    func testGeometryCallbackRebuildAddsObserversOnlyForTheNextRender() async {
        await MainActor.run {
            let (runtime, scroller, _, _) = Self.makeScrollRuntime()
            var calls: [String] = []
            scroller.observeScrollGeometry(of: { $0.contentOffset.y }) { [weak scroller] _, _ in
                calls.append("old A")
                guard let scroller else { return }
                let replacement = Self.rebuiltScroller(matching: scroller)
                replacement.observeScrollGeometry(of: { $0.contentOffset.y }) { _, _ in calls.append("new A") }
                replacement.observeScrollGeometry(of: { $0.contentOffset.y + 10 }) { _, _ in calls.append("new B") }
                replacement.observeScrollGeometry(of: { $0.contentOffset.y + 20 }) { _, _ in calls.append("new C") }
                ComponentHost.adopt(source: replacement, into: scroller)
            }
            scroller.observeScrollGeometry(of: { $0.contentOffset.y + 10 }) { _, _ in calls.append("old B") }

            _ = runtime.renderScene()
            XCTAssertEqual(calls, ["old A"])
            _ = runtime.renderFrame()
            XCTAssertEqual(calls, ["old A", "new B", "new C"])
            _ = runtime.renderScene()
            XCTAssertEqual(calls, ["old A", "new B", "new C"])
        }
    }

    func testVisibilityCallbackRebuildRetriesAnUndeliveredValueWithTheLatestAction() async {
        await MainActor.run {
            let (runtime, scroller, _, _) = Self.makeScrollRuntime()
            var oldA: [Bool] = []
            var oldB: [Bool] = []
            var newA: [Bool] = []
            var newB: [Bool] = []
            scroller.observeScrollVisibility { [weak scroller] visible in
                oldA.append(visible)
                guard let scroller else { return }
                let replacement = Self.rebuiltScroller(matching: scroller)
                replacement.observeScrollVisibility { newA.append($0) }
                replacement.observeScrollVisibility { newB.append($0) }
                ComponentHost.adopt(source: replacement, into: scroller)
            }
            scroller.observeScrollVisibility { oldB.append($0) }

            _ = runtime.renderScene()
            XCTAssertEqual(oldA, [true])
            XCTAssertTrue(oldB.isEmpty)
            XCTAssertTrue(newA.isEmpty)
            XCTAssertTrue(newB.isEmpty)

            _ = runtime.renderFrame()
            _ = runtime.renderScene()
            XCTAssertEqual(oldA, [true])
            XCTAssertTrue(oldB.isEmpty)
            XCTAssertTrue(newA.isEmpty, "A's delivered visibility value survives reconciliation")
            XCTAssertEqual(newB, [true], "B's cancelled initial visibility still needs to reach its new action")
        }
    }

    func testPhaseCallbackRebuildPreservesUndeliveredEventsForTheLatestRegisteredActions() async {
        await MainActor.run {
            let (runtime, scroller, _, _) = Self.makeScrollRuntime()
            var oldA: [RetainedScrollPhase] = []
            var oldB: [RetainedScrollPhase] = []
            var newA: [RetainedScrollPhase] = []
            var newB: [(old: RetainedScrollPhase, new: RetainedScrollPhase, offset: Double)] = []
            scroller.observeScrollPhase { [weak scroller] _, new, _ in
                oldA.append(new)
                guard let scroller else { return }
                let replacement = Self.rebuiltScroller(matching: scroller)
                replacement.observeScrollPhase { _, new, _ in newA.append(new) }
                replacement.observeScrollPhase { old, new, context in
                    newB.append((old, new, context.geometry.contentOffset.y))
                }
                ComponentHost.adopt(source: replacement, into: scroller)
            }
            scroller.observeScrollPhase { _, new, _ in oldB.append(new) }
            _ = runtime.renderScene()
            runtime.mouseWheel(at: Point(x: 30, y: 30), delta: -1)

            _ = runtime.renderFrame()
            XCTAssertEqual(oldA, [.interacting])
            XCTAssertTrue(oldB.isEmpty)
            XCTAssertTrue(newA.isEmpty)
            XCTAssertTrue(newB.isEmpty)

            _ = runtime.renderScene()
            _ = runtime.renderFrame()
            XCTAssertEqual(oldA, [.interacting])
            XCTAssertTrue(oldB.isEmpty)
            XCTAssertEqual(newA, [.idle])
            XCTAssertEqual(newB.map { $0.old }, [.idle, .interacting])
            XCTAssertEqual(newB.map { $0.new }, [.interacting, .idle])
            XCTAssertEqual(newB.map { $0.offset }, [0, 20], "Deferred phases retain their event-time geometry")
        }
    }

    func testPhaseCallbackRebuildDropsEventsForARemovedRegistration() async {
        await MainActor.run {
            let (runtime, scroller, _, _) = Self.makeScrollRuntime()
            var oldA: [RetainedScrollPhase] = []
            var removedB: [RetainedScrollPhase] = []
            var newA: [RetainedScrollPhase] = []
            scroller.observeScrollPhase { [weak scroller] _, new, _ in
                oldA.append(new)
                guard let scroller else { return }
                let replacement = Self.rebuiltScroller(matching: scroller)
                replacement.observeScrollPhase { _, new, _ in newA.append(new) }
                ComponentHost.adopt(source: replacement, into: scroller)
            }
            scroller.observeScrollPhase { _, new, _ in removedB.append(new) }
            _ = runtime.renderScene()
            runtime.mouseWheel(at: Point(x: 30, y: 30), delta: -1)

            _ = runtime.renderFrame()
            XCTAssertEqual(oldA, [.interacting])
            XCTAssertTrue(removedB.isEmpty)
            XCTAssertTrue(newA.isEmpty)

            _ = runtime.renderScene()
            XCTAssertEqual(newA, [.idle])
            runtime.mouseWheel(at: Point(x: 30, y: 30), delta: -1)
            _ = runtime.renderFrame()
            XCTAssertEqual(oldA, [.interacting])
            XCTAssertEqual(newA, [.idle, .interacting, .idle])
            XCTAssertTrue(removedB.isEmpty)
        }
    }

    func testWrapperObserverDropsSampleFromAScrollSourceDetachedAndReattachedDuringDelivery() async {
        await MainActor.run {
            let (runtime, first, _, _) = Self.makeScrollRuntime()
            let source = Self.rebuiltScroller(matching: first)
            let wrapper = ViewNode(
                frame: Rect(x: 0, y: 0, width: 100, height: 100), children: [source])
            runtime.root.addChild(wrapper)
            var firstCalls = 0
            var values: [(old: Double, new: Double)] = []
            first.observeScrollGeometry(of: { $0.contentOffset.y }) { [weak wrapper, weak source] _, _ in
                firstCalls += 1
                guard firstCalls == 1, let wrapper, let source else { return }
                wrapper.removeChild(at: 0)
                source.scrollOffset = 40
                wrapper.addChild(source)
            }
            wrapper.observeScrollGeometry(of: { $0.contentOffset.y }) { old, new in
                values.append((old, new))
            }
            XCTAssertNil(source.scrollObserverStorage, "Only the enclosing wrapper owns an observation")

            _ = runtime.renderScene()
            XCTAssertEqual(firstCalls, 1)
            XCTAssertTrue(values.isEmpty, "Reattaching the source must not revive its old queued geometry")
            XCTAssertEqual(source.scrollOffset, 40)
            XCTAssertNil(source.scrollObserverStorage)

            _ = runtime.renderFrame()
            _ = runtime.renderScene()
            XCTAssertEqual(firstCalls, 1)
            XCTAssertEqual(values.map { $0.old }, [40])
            XCTAssertEqual(values.map { $0.new }, [40])
        }
    }
}
