import Foundation
import SwiftWindowsCore
import XCTest

@testable import WinSwiftUI

/// Pure local interpolation contracts, not measured native SwiftUI timing parity.
/// Authored bodies use the typed public protocols without asserting that concrete
/// builder or primitive Body types match SwiftUI's implementation types.
@MainActor
final class KeyframeTimelineTests: XCTestCase {
    func testEmptyTimelinePreservesAnOrdinaryRoot() async {
        let initial = KeyframeTestRoot(x: 3, y: 7, label: "unchanged")
        let timeline = KeyframeTimeline(initialValue: initial) {}

        XCTAssertEqual(timeline.duration, 0)
        XCTAssertEqual(timeline.value(time: -2), initial)
        XCTAssertEqual(timeline.value(time: 0), initial)
        XCTAssertEqual(timeline.value(time: 10), initial)
        XCTAssertEqual(timeline.value(progress: 0.5), initial)
    }

    func testScalarLinearTimelineClampsFiniteTimeAndProgress() async {
        let timeline = KeyframeTimeline(initialValue: 2.0) {
            LinearKeyframe(10.0, duration: 4)
        }

        XCTAssertEqual(timeline.duration, 4)
        XCTAssertEqual(timeline.value(time: -10), 2)
        XCTAssertEqual(timeline.value(time: 0), 2)
        XCTAssertEqual(timeline.value(time: 1), 4, accuracy: 1e-12)
        XCTAssertEqual(timeline.value(time: 2), 6, accuracy: 1e-12)
        XCTAssertEqual(timeline.value(time: 4), 10)
        XCTAssertEqual(timeline.value(time: 10), 10)
        XCTAssertEqual(timeline.value(progress: -1), 2)
        XCTAssertEqual(timeline.value(progress: 0.25), 4, accuracy: 1e-12)
        XCTAssertEqual(timeline.value(progress: 2), 10)
    }

    func testScalarBuilderSequencesForLoopsAndBothConditionalBranches() async {
        for useFirstBranch in [true, false] {
            let timeline = KeyframeTimeline(initialValue: 0.0) {
                for target in [2.0, 4.0] {
                    LinearKeyframe(target, duration: 1)
                }
                if useFirstBranch {
                    LinearKeyframe(6.0, duration: 1)
                } else {
                    LinearKeyframe(10.0, duration: 1)
                }
            }

            XCTAssertEqual(timeline.duration, 3)
            XCTAssertEqual(timeline.value(time: 0.5), 1, accuracy: 1e-12)
            XCTAssertEqual(timeline.value(time: 1.5), 3, accuracy: 1e-12)
            XCTAssertEqual(timeline.value(time: 2.5), useFirstBranch ? 5 : 7, accuracy: 1e-12)
            XCTAssertEqual(timeline.value(time: 3), useFirstBranch ? 6 : 10)

            let emptyBranch = KeyframeTimeline(initialValue: 9.0) {
                if useFirstBranch {
                } else {
                    MoveKeyframe(11.0)
                }
            }
            XCTAssertEqual(emptyBranch.duration, 0)
            XCTAssertEqual(emptyBranch.value(time: 0), useFirstBranch ? 9 : 11)
        }
    }

    func testWritableTracksUseMaximumDurationAndHoldShorterTracks() async {
        for useFirstBranch in [true, false] {
            let initial = KeyframeTestRoot(x: 0, y: 10, label: "preserved")
            let timeline = KeyframeTimeline(initialValue: initial) {
                KeyframeTrack(\.x) {
                    LinearKeyframe(4.0, duration: 1)
                }
                KeyframeTrack(\KeyframeTestRoot.y) {
                    for target in [12.0, 14.0] {
                        LinearKeyframe(target, duration: 1)
                    }
                    if useFirstBranch {
                        LinearKeyframe(16.0, duration: 1)
                    } else {
                        LinearKeyframe(20.0, duration: 1)
                    }
                }
            }

            let sample = timeline.value(time: 2.5)
            XCTAssertEqual(timeline.duration, 3)
            XCTAssertEqual(sample.x, 4)
            XCTAssertEqual(sample.y, useFirstBranch ? 15 : 17, accuracy: 1e-12)
            XCTAssertEqual(sample.label, "preserved")
            XCTAssertEqual(timeline.value(time: 10).x, 4)
        }
    }

    func testLastDuplicateTrackWinsIncludingAfterItsShorterDuration() async {
        let last: KeyframeTrack<KeyframeTestRoot, Double, LinearKeyframe<Double>> =
            KeyframeTrack(\KeyframeTestRoot.x) {
                LinearKeyframe(20.0, duration: 1)
            }
        let timeline = KeyframeTimeline(initialValue: KeyframeTestRoot(x: 0, y: 7, label: "same")) {
            KeyframeTrack(\KeyframeTestRoot.x) {
                LinearKeyframe(100.0, duration: 4)
            }
            last
        }

        XCTAssertEqual(timeline.duration, 4)
        XCTAssertEqual(timeline.value(time: 0.5).x, 10, accuracy: 1e-12)
        XCTAssertEqual(timeline.value(time: 2).x, 20)
        XCTAssertEqual(timeline.value(time: 4).x, 20)
        XCTAssertEqual(timeline.value(time: 2).y, 7)
    }

    func testCustomTypedKeyframesAndTrackContentBodiesAreExpanded() async {
        let timeline = KeyframeTimeline(initialValue: KeyframeTestRoot(x: 0, y: 10, label: "ordinary")) {
            KeyframeForwardingFrames(frames: KeyframeAuthoredFrames())
        }

        XCTAssertEqual(timeline.duration, 2)
        XCTAssertEqual(timeline.value(time: 0.5).x, 1, accuracy: 1e-12)
        XCTAssertEqual(timeline.value(time: 1).x, 6)
        XCTAssertEqual(timeline.value(time: 1.5).x, 8, accuracy: 1e-12)
        XCTAssertEqual(timeline.value(time: 1.5).y, 13, accuracy: 1e-12)
        XCTAssertEqual(timeline.value(time: 2).label, "ordinary")
    }

    func testFloatPointSizeRectAndAngleAdaptersInterpolate() async {
        let initial = KeyframeGeometryRoot(
            scalar: 2,
            point: Point(x: 2, y: 4),
            size: Size(width: 10, height: 20),
            rect: Rect(x: 2, y: 4, width: 10, height: 20),
            angle: .radians(0.5))
        let timeline = KeyframeTimeline(initialValue: initial) {
            KeyframeTrack(\KeyframeGeometryRoot.scalar) {
                LinearKeyframe(Float(6), duration: 2)
            }
            KeyframeTrack(\KeyframeGeometryRoot.point) {
                LinearKeyframe(Point(x: 6, y: 12), duration: 2)
            }
            KeyframeTrack(\KeyframeGeometryRoot.size) {
                LinearKeyframe(Size(width: 30, height: 60), duration: 2)
            }
            KeyframeTrack(\KeyframeGeometryRoot.rect) {
                LinearKeyframe(Rect(x: 6, y: 12, width: 30, height: 60), duration: 2)
            }
            KeyframeTrack(\KeyframeGeometryRoot.angle) {
                LinearKeyframe(Angle.radians(1.5), duration: 2)
            }
        }

        let midpoint = timeline.value(time: 1)
        XCTAssertEqual(midpoint.scalar, 4, accuracy: 1e-6)
        XCTAssertEqual(midpoint.point, Point(x: 4, y: 8))
        XCTAssertEqual(midpoint.size, Size(width: 20, height: 40))
        XCTAssertEqual(midpoint.rect, Rect(x: 4, y: 8, width: 20, height: 40))
        XCTAssertEqual(midpoint.angle.radians, 1, accuracy: 1e-12)
    }

    func testMoveSegmentsApplyAtTheExactRightBoundary() async {
        let timeline = KeyframeTimeline(initialValue: 0.0) {
            MoveKeyframe(2.0)
            LinearKeyframe(6.0, duration: 2)
            MoveKeyframe(10.0)
            LinearKeyframe(14.0, duration: 2)
        }

        XCTAssertEqual(timeline.duration, 4)
        XCTAssertEqual(timeline.value(time: -1), 2)
        XCTAssertEqual(timeline.value(time: 0), 2)
        XCTAssertEqual(timeline.value(time: 1), 4, accuracy: 1e-12)
        XCTAssertEqual(timeline.value(time: 2 - 1e-6), 6 - 2e-6, accuracy: 1e-10)
        XCTAssertEqual(timeline.value(time: 2), 10)
        XCTAssertEqual(timeline.value(time: 3), 12, accuracy: 1e-12)
        XCTAssertEqual(timeline.value(time: 4), 14)
    }

    func testZeroDurationLinearCubicAndMoveSegmentsJumpInOrder() async throws {
        let timeline = KeyframeTimeline(initialValue: -1.0) {
            LinearKeyframe(2.0, duration: 0)
            CubicKeyframe(3.0, duration: 0, startVelocity: 10, endVelocity: 20)
            MoveKeyframe(4.0)
        }

        XCTAssertEqual(timeline.duration, 0)
        XCTAssertEqual(timeline.value(time: 0), 4)
        XCTAssertEqual(timeline.value(time: 1), 4)
        XCTAssertEqual(timeline.value(progress: 0.5), 4)
        let sample = try XCTUnwrap(timeline.sample(time: 0, isCurrent: { true }))
        XCTAssertEqual(try XCTUnwrap(sample.velocities[\Double.self] as? Double), 0)
    }

    func testExplicitCubicVelocitiesUseHermiteInterpolation() async throws {
        let timeline = KeyframeTimeline(initialValue: 2.0) {
            CubicKeyframe(10.0, duration: 2, startVelocity: 3, endVelocity: -1)
        }

        // At u = 1/2, Hermite weights are 1/2, 1/8, 1/2, -1/8.
        XCTAssertEqual(timeline.value(time: 1), 7, accuracy: 1e-12)
        XCTAssertEqual(timeline.value(time: 0), 2)
        XCTAssertEqual(timeline.value(time: 2), 10)
        XCTAssertEqual(try scalarVelocity(timeline, time: 0), 3, accuracy: 1e-12)
        XCTAssertEqual(try scalarVelocity(timeline, time: 1), 5.5, accuracy: 1e-12)
        XCTAssertEqual(try scalarVelocity(timeline, time: 2), -1, accuracy: 1e-12)
        XCTAssertEqual(try scalarVelocity(timeline, time: 3), 0)
    }

    func testAdjacentAutomaticCubicsUseContinuousNonuniformCatmullVelocity() async throws {
        let timeline = KeyframeTimeline(initialValue: 0.0) {
            CubicKeyframe(4.0, duration: 1)
            CubicKeyframe(10.0, duration: 2)
        }
        // Weighted neighboring secants: (2/3)*4 + (1/3)*3 = 11/3.
        let tangent = 11.0 / 3.0
        let epsilon = 1e-6

        XCTAssertEqual(timeline.value(time: 0.5), 37.0 / 24.0, accuracy: 1e-12)
        XCTAssertEqual(timeline.value(time: 2), 95.0 / 12.0, accuracy: 1e-12)
        XCTAssertEqual(timeline.value(time: 1), 4)
        XCTAssertEqual(try scalarVelocity(timeline, time: 1), tangent, accuracy: 1e-12)
        XCTAssertEqual(try scalarVelocity(timeline, time: 1 - epsilon), tangent, accuracy: 1e-4)
        XCTAssertEqual(try scalarVelocity(timeline, time: 1 + epsilon), tangent, accuracy: 1e-4)
        XCTAssertEqual(try scalarVelocity(timeline, time: 0), 0)
        XCTAssertEqual(try scalarVelocity(timeline, time: 3), 0)
    }

    func testAnExplicitCubicJoinVelocityIsInheritedByItsAutomaticNeighbor() async throws {
        let timeline = KeyframeTimeline(initialValue: 0.0) {
            CubicKeyframe(4.0, duration: 1, endVelocity: 2)
            CubicKeyframe(10.0, duration: 2)
        }

        XCTAssertEqual(try scalarVelocity(timeline, time: 1), 2, accuracy: 1e-12)
        XCTAssertEqual(try scalarVelocity(timeline, time: 1 - 1e-6), 2, accuracy: 1e-4)
        XCTAssertEqual(try scalarVelocity(timeline, time: 1 + 1e-6), 2, accuracy: 1e-4)
        XCTAssertEqual(timeline.value(time: 2), 7.5, accuracy: 1e-12)
    }

    func testCubicInheritsPreviousLinearVelocityAndMeetsNextLinearSlope() async throws {
        let timeline = KeyframeTimeline(initialValue: 0.0) {
            LinearKeyframe(4.0, duration: 2)
            CubicKeyframe(10.0, duration: 2)
            LinearKeyframe(14.0, duration: 1)
        }

        XCTAssertEqual(try scalarVelocity(timeline, time: 2), 2, accuracy: 1e-12)
        XCTAssertEqual(timeline.value(time: 3), 6.5, accuracy: 1e-12)
        XCTAssertEqual(try scalarVelocity(timeline, time: 4 - 1e-6), 4, accuracy: 1e-4)
        XCTAssertEqual(try scalarVelocity(timeline, time: 4), 4, accuracy: 1e-12)
        XCTAssertEqual(timeline.value(time: 4), 10)
    }

    func testCriticalSpringMatchesAnalyticPositionAndExplicitStartVelocity() async throws {
        let timeline = KeyframeTimeline(initialValue: 2.0) {
            SpringKeyframe(
                7.0, duration: 0.2, spring: Spring(response: 1, dampingRatio: 1), startVelocity: 3)
        }
        let omega = 2 * Double.pi
        let time = 0.1
        let displacement = -5.0
        let coefficient = 3 + omega * displacement
        let decay = exp(-omega * time)
        let expectedValue = 7 + (displacement + coefficient * time) * decay
        let expectedVelocity = (3 - omega * coefficient * time) * decay

        XCTAssertEqual(timeline.duration, 0.2)
        XCTAssertEqual(timeline.value(time: 0), 2)
        XCTAssertEqual(try scalarVelocity(timeline, time: 0), 3, accuracy: 1e-12)
        XCTAssertEqual(timeline.value(time: time), expectedValue, accuracy: 1e-10)
        XCTAssertEqual(try scalarVelocity(timeline, time: time), expectedVelocity, accuracy: 1e-10)
        XCTAssertLessThan(timeline.value(time: 0.2), 7)
    }

    func testUnderdampedSpringMatchesAnalyticResponseAndCanOvershoot() async throws {
        let damping = 0.4
        let omega = 2 * Double.pi
        let dampedOmega = omega * sqrt(1 - damping * damping)
        let timeline = KeyframeTimeline(initialValue: 0.0) {
            SpringKeyframe(1.0, duration: 1, spring: Spring(response: 1, dampingRatio: damping))
        }
        let time = 0.2
        let decay = exp(-damping * omega * time)
        let expectedValue =
            1 - decay * (cos(dampedOmega * time) + damping * omega / dampedOmega * sin(dampedOmega * time))
        let expectedVelocity = decay * omega * omega / dampedOmega * sin(dampedOmega * time)
        let peakTime = Double.pi / dampedOmega

        XCTAssertEqual(timeline.value(time: time), expectedValue, accuracy: 1e-10)
        XCTAssertEqual(try scalarVelocity(timeline, time: time), expectedVelocity, accuracy: 1e-10)
        XCTAssertGreaterThan(timeline.value(time: peakTime), 1)
        XCTAssertEqual(
            timeline.value(time: peakTime),
            1 + exp(-damping * Double.pi / sqrt(1 - damping * damping)), accuracy: 1e-10)
    }

    func testOverdampedSpringMatchesAnalyticResponseAndRemainsMonotonic() async throws {
        let omega = 2 * Double.pi
        let damping = 2.0
        let root = sqrt(damping * damping - 1)
        let slow = -omega * (damping - root)
        let fast = -omega * (damping + root)
        let first = fast / (slow - fast)
        let second = -slow / (slow - fast)
        let timeline = KeyframeTimeline(initialValue: 0.0) {
            SpringKeyframe(1.0, duration: 1, spring: Spring(response: 1, dampingRatio: damping))
        }
        let time = 0.2
        let expectedValue = 1 + first * exp(slow * time) + second * exp(fast * time)
        let expectedVelocity = first * slow * exp(slow * time) + second * fast * exp(fast * time)

        XCTAssertEqual(timeline.value(time: time), expectedValue, accuracy: 1e-10)
        XCTAssertEqual(try scalarVelocity(timeline, time: time), expectedVelocity, accuracy: 1e-10)
        var previous = 0.0
        for sampleTime in [0.0, 0.1, 0.2, 0.5, 1] {
            let value = timeline.value(time: sampleTime)
            XCTAssertGreaterThanOrEqual(value, previous - 1e-12)
            XCTAssertLessThan(value, 1)
            previous = value
        }
    }

    func testShortSpringHandsItsPhysicalEndpointToTheFollowingSegment() async {
        let springDuration = 0.05
        let timeline = KeyframeTimeline(initialValue: 0.0) {
            SpringKeyframe(
                10.0, duration: springDuration, spring: Spring(response: 1, dampingRatio: 1))
            LinearKeyframe(20.0, duration: 0.5)
        }
        let omega = 2 * Double.pi
        let endpoint = 10 * (1 - (1 + omega * springDuration) * exp(-omega * springDuration))
        let epsilon = 1e-7

        XCTAssertEqual(timeline.duration, 0.55, accuracy: 1e-12)
        XCTAssertLessThan(endpoint, 1)
        XCTAssertEqual(timeline.value(time: springDuration), endpoint, accuracy: 1e-10)
        XCTAssertEqual(timeline.value(time: springDuration - epsilon), endpoint, accuracy: 1e-4)
        XCTAssertEqual(timeline.value(time: springDuration + epsilon), endpoint, accuracy: 1e-4)
        XCTAssertEqual(timeline.value(time: springDuration + 0.25), (endpoint + 20) / 2, accuracy: 1e-10)
        XCTAssertEqual(timeline.value(time: 1), 20)
    }

    func testAutomaticSpringDurationUsesAFiniteRepeatableLocalSettlingEnvelope() async {
        // The envelope tolerance is this implementation's contract, not a
        // measured native duration or a claim that the endpoint is snapped.
        for damping in [0.5, 1.0, 2.0] {
            let spring = Spring(response: 0.6, dampingRatio: damping)
            let first = KeyframeTimeline(initialValue: 0.0) {
                SpringKeyframe(4.0, spring: spring)
            }
            let second = KeyframeTimeline(initialValue: 0.0) {
                SpringKeyframe(4.0, spring: spring)
            }
            let endpoint = first.value(time: first.duration)

            XCTAssertTrue(first.duration.isFinite)
            XCTAssertGreaterThan(first.duration, 0)
            XCTAssertEqual(first.duration, second.duration, accuracy: 1e-12)
            XCTAssertEqual(endpoint, 4, accuracy: 0.004_001)
            XCTAssertEqual(first.value(time: first.duration + 1), endpoint, accuracy: 1e-12)
            XCTAssertEqual(first.value(progress: 1), endpoint, accuracy: 1e-12)
        }
    }

    func testInheritedVelocityUsesAnimatableDataAndExplicitTypedVelocityWins() async throws {
        let initial = KeyframeGeometryRoot(
            scalar: 0, point: .zero, size: .zero, rect: .zero, angle: .zero)
        let inherited = AnimatablePair<Double, Double>(3, -2)
        let velocities: KeyframeVelocityMap = [\KeyframeGeometryRoot.point: inherited]
        let implicitFrames = KeyframeTrack(\KeyframeGeometryRoot.point) {
            CubicKeyframe(Point(x: 4, y: 8), duration: 1, endVelocity: .zero)
        }
        let explicitFrames = KeyframeTrack(\KeyframeGeometryRoot.point) {
            SpringKeyframe(
                Point(x: 4, y: 8), duration: 0.2,
                spring: Spring(response: 1, dampingRatio: 1), startVelocity: Point(x: 7, y: 11))
        }
        let implicitTimeline = try XCTUnwrap(
            KeyframeTimeline(
                initialValue: initial, initialVelocities: velocities, frames: implicitFrames, isCurrent: { true }))
        let explicitTimeline = try XCTUnwrap(
            KeyframeTimeline(
                initialValue: initial, initialVelocities: velocities, frames: explicitFrames, isCurrent: { true }))
        let implicitSample = try XCTUnwrap(implicitTimeline.sample(time: 0, isCurrent: { true }))
        let explicitSample = try XCTUnwrap(explicitTimeline.sample(time: 0, isCurrent: { true }))
        let implicitVelocity = try XCTUnwrap(
            implicitSample.velocities[\KeyframeGeometryRoot.point] as? Point.AnimatableData)
        let explicitVelocity = try XCTUnwrap(
            explicitSample.velocities[\KeyframeGeometryRoot.point] as? Point.AnimatableData)

        XCTAssertEqual(implicitVelocity.first, 3)
        XCTAssertEqual(implicitVelocity.second, -2)
        XCTAssertEqual(explicitVelocity.first, 7)
        XCTAssertEqual(explicitVelocity.second, 11)
        XCTAssertEqual(implicitTimeline.value(time: 0.5).point, Point(x: 2.375, y: 3.75))
    }

    func testZeroDurationSpringPreservesInitialValueAndIncomingVelocity() async throws {
        let frames = KeyframeTrack(\Double.self) {
            SpringKeyframe(8.0, duration: 0, spring: Spring(response: 1, dampingRatio: 1))
        }
        let timeline = try XCTUnwrap(
            KeyframeTimeline(
                initialValue: 2.0, initialVelocities: [\Double.self: 7.0],
                frames: frames, isCurrent: { true }))

        XCTAssertEqual(timeline.duration, 0)
        XCTAssertEqual(timeline.value(time: 0), 2)
        XCTAssertEqual(timeline.value(time: 1), 2)
        XCTAssertEqual(try scalarVelocity(timeline, time: 0), 7)
        XCTAssertEqual(try scalarVelocity(timeline, time: 1), 0)
    }

    func testRevokedCustomKeyframesBodyPreventsTheNextBodyCallback() async {
        let probe = KeyframeCallbackProbe()
        let frames = keyframeTestFrames {
            KeyframeProbedFrames(
                frames: KeyframeTrack(\KeyframeTestRoot.x) { LinearKeyframe(1.0, duration: 1) },
                probe: probe, event: "first.body")
            KeyframeProbedFrames(
                frames: KeyframeTrack(\KeyframeTestRoot.y) { LinearKeyframe(2.0, duration: 1) },
                probe: probe, event: "second.body")
        }
        let initial = KeyframeTestRoot(x: 0, y: 0, label: "root")
        probe.isCurrent = false
        let alreadyRevoked = KeyframeTimeline(
            initialValue: initial, initialVelocities: [:], frames: frames, isCurrent: { probe.isCurrent })
        XCTAssertNil(alreadyRevoked)
        XCTAssertTrue(probe.events.isEmpty)

        probe.arm("first.body")
        let cancelled = KeyframeTimeline(
            initialValue: initial, initialVelocities: [:], frames: frames, isCurrent: { probe.isCurrent })

        XCTAssertNil(cancelled)
        XCTAssertEqual(probe.events, ["first.body"])
        assertStoppedAtCancellation(probe, event: "first.body")
    }

    func testRevokedCustomTrackContentBodyPreventsTheNextSegmentBody() async {
        let probe = KeyframeCallbackProbe()
        let frames = KeyframeTrack(\Double.self) {
            KeyframeProbedContent(
                content: LinearKeyframe(1.0, duration: 1), probe: probe, event: "first.segment.body")
            KeyframeProbedContent(
                content: LinearKeyframe(2.0, duration: 1), probe: probe, event: "second.segment.body")
        }
        probe.arm("first.segment.body")

        let timeline = KeyframeTimeline(
            initialValue: 0.0, initialVelocities: [:], frames: frames, isCurrent: { probe.isCurrent })

        XCTAssertNil(timeline)
        XCTAssertEqual(probe.events, ["first.segment.body"])
        assertStoppedAtCancellation(probe, event: "first.segment.body")
    }

    func testCompilationCancellationDuringDataAndVectorCallbacksStopsImmediately() async {
        for event in ["data.get", "zero", "subtract", "magnitude", "scale", "add"] {
            let probe = KeyframeCallbackProbe()
            KeyframeProbedVector.zeroProbe = probe
            defer { KeyframeProbedVector.zeroProbe = nil }
            assertCompilationCancellation(
                initial: KeyframeProbedValue(number: 0, probe: probe),
                target: KeyframeProbedValue(number: 1, probe: probe), probe: probe, event: event)
            // The framework's pair composition must also stop between its
            // first and second authored component operations.
            assertCompilationCancellation(
                initial: KeyframeProbedPairValue(first: 0, second: 0, probe: probe),
                target: KeyframeProbedPairValue(first: 1, second: 2, probe: probe), probe: probe, event: event)
        }
    }

    func testSamplingCancellationDuringVectorOrDataWriteStopsAtThatCallback() async throws {
        for (event, time) in [
            ("subtract", 0.25), ("scale", 0.25), ("add", 0.25), ("data.set", 0.25), ("zero", 2.0),
        ] {
            let probe = KeyframeCallbackProbe()
            KeyframeProbedVector.zeroProbe = probe
            defer { KeyframeProbedVector.zeroProbe = nil }
            try assertSamplingCancellation(
                initial: KeyframeProbedValue(number: 0, probe: probe),
                target: KeyframeProbedValue(number: 1, probe: probe), probe: probe, event: event, time: time)
            try assertSamplingCancellation(
                initial: KeyframeProbedPairValue(first: 0, second: 0, probe: probe),
                target: KeyframeProbedPairValue(first: 1, second: 2, probe: probe), probe: probe,
                event: event, time: time)
        }
    }

    func testKeyPathGetterAndSetterCancellationPreventTheNextPropertyCallback() async throws {
        for event in ["first.get", "first.set"] {
            let probe = KeyframeCallbackProbe()
            let initial = KeyframeProbedRoot(probe: probe, first: 0, second: 0)
            let frames = keyframeTestFrames {
                KeyframeTrack(\KeyframeProbedRoot.first) { LinearKeyframe(1.0, duration: 1) }
                KeyframeTrack(\KeyframeProbedRoot.second) { LinearKeyframe(2.0, duration: 1) }
            }

            if event == "first.get" {
                probe.arm(event)
                let timeline = KeyframeTimeline(
                    initialValue: initial, initialVelocities: [:], frames: frames, isCurrent: { probe.isCurrent })
                XCTAssertNil(timeline)
            } else {
                let timeline = try XCTUnwrap(
                    KeyframeTimeline(
                        initialValue: initial, initialVelocities: [:], frames: frames, isCurrent: { probe.isCurrent }))
                probe.arm(event)
                XCTAssertNil(timeline.sample(time: 0.5, isCurrent: { probe.isCurrent }))
            }

            // A writable key path may perform accessor work inside the same
            // entered operation, but it must not enter the following track.
            XCTAssertFalse(probe.events.contains("second.get"))
            XCTAssertFalse(probe.events.contains("second.set"))
            assertStoppedAtCancellation(probe, event: event)
        }
    }

    private func assertCompilationCancellation<Value: Animatable>(
        initial: Value, target: Value, probe: KeyframeCallbackProbe, event: String,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        let frames = KeyframeTrack(\Value.self) {
            SpringKeyframe(target, spring: Spring(response: 0.5, dampingRatio: 0.6))
        }
        probe.arm(event)
        let timeline = KeyframeTimeline(
            initialValue: initial, initialVelocities: [:], frames: frames, isCurrent: { probe.isCurrent })

        XCTAssertNil(timeline, "Compilation must stop when \(event) revokes authority.", file: file, line: line)
        assertStoppedAtCancellation(probe, event: event, file: file, line: line)
    }

    private func assertSamplingCancellation<Value: Animatable>(
        initial: Value, target: Value, probe: KeyframeCallbackProbe, event: String, time: Double,
        file: StaticString = #filePath, line: UInt = #line
    ) throws {
        let frames = KeyframeTrack(\Value.self) { LinearKeyframe(target, duration: 1) }
        probe.arm(nil)
        let timeline = try XCTUnwrap(
            KeyframeTimeline(
                initialValue: initial, initialVelocities: [:], frames: frames, isCurrent: { probe.isCurrent }),
            file: file, line: line)
        probe.arm(event)

        XCTAssertNil(
            timeline.sample(time: time, isCurrent: { probe.isCurrent }),
            "Sampling must stop when \(event) revokes authority.", file: file, line: line)
        assertStoppedAtCancellation(probe, event: event, file: file, line: line)
        let previousEvents = probe.events
        XCTAssertNil(timeline.sample(time: time, isCurrent: { probe.isCurrent }), file: file, line: line)
        XCTAssertEqual(
            probe.events, previousEvents, "A revoked entry must perform no further authored callback.",
            file: file, line: line)
    }

    private func scalarVelocity(
        _ timeline: KeyframeTimeline<Double>, time: Double,
        file: StaticString = #filePath, line: UInt = #line
    ) throws -> Double {
        let sample = try XCTUnwrap(timeline.sample(time: time, isCurrent: { true }), file: file, line: line)
        return try XCTUnwrap(sample.velocities[\Double.self] as? Double, file: file, line: line)
    }

    private func assertStoppedAtCancellation(
        _ probe: KeyframeCallbackProbe, event: String,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        XCTAssertFalse(probe.isCurrent, "The intended callback was not entered: \(event).", file: file, line: line)
        XCTAssertEqual(
            probe.events.last, event, "No subsequent framework callback is permitted.", file: file, line: line)
        XCTAssertEqual(probe.events.filter { $0 == event }.count, 1, file: file, line: line)
        XCTAssertEqual(probe.cancellationIndex, probe.events.count - 1, file: file, line: line)
    }
}

// These roots deliberately do not conform to Animatable.
private struct KeyframeTestRoot: Equatable {
    var x: Double
    var y: Double
    var label: String
}

private struct KeyframeGeometryRoot {
    var scalar: Float
    var point: Point
    var size: Size
    var rect: Rect
    var angle: Angle
}

private struct KeyframeAuthoredContent: KeyframeTrackContent {
    typealias Value = Double

    var body: some KeyframeTrackContent<Double> {
        LinearKeyframe(2.0, duration: 1)
        MoveKeyframe(6.0)
        LinearKeyframe(10.0, duration: 1)
    }
}

private struct KeyframeAuthoredFrames: Keyframes {
    typealias Value = KeyframeTestRoot

    var body: some Keyframes<KeyframeTestRoot> {
        KeyframeTrack(\KeyframeTestRoot.x) { KeyframeAuthoredContent() }
        KeyframeTrack(\KeyframeTestRoot.y) { LinearKeyframe(14.0, duration: 2) }
    }
}

private struct KeyframeForwardingFrames<Frames: Keyframes>: Keyframes {
    typealias Value = Frames.Value
    let frames: Frames

    var body: Frames { return frames }
}

@MainActor
private func keyframeTestFrames<Root, Frames: Keyframes>(
    @KeyframesBuilder<Root> _ content: () -> Frames
) -> Frames where Frames.Value == Root {
    content()
}

@MainActor
private final class KeyframeCallbackProbe {
    var isCurrent = true
    var events: [String] = []
    var cancellationIndex: Int?
    private var cancellationEvent: String?

    func arm(_ event: String?) {
        events = []
        isCurrent = true
        cancellationIndex = nil
        cancellationEvent = event
    }

    func record(_ event: String) {
        events.append(event)
        if event == cancellationEvent {
            isCurrent = false
            if cancellationIndex == nil {
                cancellationIndex = events.count - 1
            }
        }
    }
}

// Protocol hooks are nonisolated. Every test enters them synchronously on the
// main actor; capture only immutable probe references when checking that actor.
private func keyframeRecord(_ event: String, probe: KeyframeCallbackProbe?) {
    MainActor.assumeIsolated { [probe, event] in probe?.record(event) }
}

private struct KeyframeProbedFrames<Frames: Keyframes>: Keyframes {
    typealias Value = Frames.Value
    let frames: Frames
    let probe: KeyframeCallbackProbe
    let event: String

    var body: Frames {
        keyframeRecord(event, probe: probe)
        return frames
    }
}

private struct KeyframeProbedContent<Content: KeyframeTrackContent>: KeyframeTrackContent {
    typealias Value = Content.Value
    let content: Content
    let probe: KeyframeCallbackProbe
    let event: String

    var body: Content {
        keyframeRecord(event, probe: probe)
        return content
    }
}

private struct KeyframeProbedVector: VectorArithmetic, Sendable {
    var number: Double
    let probe: KeyframeCallbackProbe?

    // A zero has no operand from which to obtain a probe. Its test-only scope
    // is actor-isolated and cleared with defer before each test iteration ends.
    @MainActor static var zeroProbe: KeyframeCallbackProbe?

    static var zero: Self {
        let probe = MainActor.assumeIsolated { zeroProbe }
        keyframeRecord("zero", probe: probe)
        return Self(number: 0, probe: probe)
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.number == rhs.number
    }

    static func + (lhs: Self, rhs: Self) -> Self {
        let probe = lhs.probe ?? rhs.probe
        keyframeRecord("add", probe: probe)
        return Self(number: lhs.number + rhs.number, probe: probe)
    }

    static func - (lhs: Self, rhs: Self) -> Self {
        let probe = lhs.probe ?? rhs.probe
        keyframeRecord("subtract", probe: probe)
        return Self(number: lhs.number - rhs.number, probe: probe)
    }

    mutating func scale(by rhs: Double) {
        keyframeRecord("scale", probe: probe)
        number *= rhs
    }

    var magnitudeSquared: Double {
        keyframeRecord("magnitude", probe: probe)
        return number * number
    }
}

private struct KeyframeProbedValue: Animatable {
    var number: Double
    let probe: KeyframeCallbackProbe

    var animatableData: KeyframeProbedVector {
        get {
            keyframeRecord("data.get", probe: probe)
            return KeyframeProbedVector(number: number, probe: probe)
        }
        set {
            keyframeRecord("data.set", probe: probe)
            number = newValue.number
        }
    }
}

private struct KeyframeProbedPairValue: Animatable {
    var first: Double
    var second: Double
    let probe: KeyframeCallbackProbe

    var animatableData: AnimatablePair<KeyframeProbedValue, KeyframeProbedValue> {
        get {
            keyframeRecord("data.get", probe: probe)
            return AnimatablePair(
                KeyframeProbedVector(number: first, probe: probe),
                KeyframeProbedVector(number: second, probe: probe))
        }
        set {
            keyframeRecord("data.set", probe: probe)
            first = newValue.first.number
            second = newValue.second.number
        }
    }
}

private struct KeyframeProbedRoot {
    let probe: KeyframeCallbackProbe
    private var firstStorage: Double
    private var secondStorage: Double

    init(probe: KeyframeCallbackProbe, first: Double, second: Double) {
        self.probe = probe
        self.firstStorage = first
        self.secondStorage = second
    }

    var first: Double {
        get {
            keyframeRecord("first.get", probe: probe)
            return firstStorage
        }
        set {
            keyframeRecord("first.set", probe: probe)
            firstStorage = newValue
        }
    }

    var second: Double {
        get {
            keyframeRecord("second.get", probe: probe)
            return secondStorage
        }
        set {
            keyframeRecord("second.set", probe: probe)
            secondStorage = newValue
        }
    }
}
