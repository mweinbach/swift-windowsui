import SwiftWindowsCore
import XCTest

final class RetainedViewIdentityScalarEqualityTests: XCTestCase {
    func testMatchingScalarPathsUseConstantAuthorizationChecks() {
        for repetitions in [0, 1, 10, 100] {
            let left = RetainedViewIdentity(segments: scalarSegments(repetitions: repetitions))
            let right = RetainedViewIdentity(segments: scalarSegments(repetitions: repetitions))
            var prefixChecks = 0
            var equalityChecks = 0

            XCTAssertEqual(
                left.checkedHasPrefix(right) {
                    prefixChecks += 1
                    return true
                }, true)
            XCTAssertEqual(
                left.checkedEquals(right) {
                    equalityChecks += 1
                    return true
                }, true)

            XCTAssertEqual(prefixChecks, 2)
            XCTAssertEqual(equalityChecks, 3)
        }
    }

    func testEveryScalarFamilyPreservesEqualityAndPrefixSemantics() {
        let variants: [RetainedViewIdentity.Segment] = [
            .view(ObjectIdentifier(ScalarEqualityFirstMarker.self)),
            .view(ObjectIdentifier(ScalarEqualitySecondMarker.self)),
            .role(.content), .role(.label), .slot(0), .slot(1), .branch(false), .branch(true),
            .iteration(0), .iteration(1), .occurrence(0), .occurrence(1),
        ]
        for leftSegment in variants {
            for rightSegment in variants {
                let left = RetainedViewIdentity(segments: [leftSegment])
                let right = RetainedViewIdentity(segments: [rightSegment])
                let extended = left.appending(.slot(77))

                XCTAssertEqual(left.checkedEquals(right, isCurrent: { true }), left == right)
                XCTAssertEqual(left.checkedHasPrefix(right, isCurrent: { true }), left == right)
                XCTAssertEqual(extended.checkedHasPrefix(right, isCurrent: { true }), left == right)
                XCTAssertEqual(left.checkedHasPrefix(extended, isCurrent: { true }), false)
            }
        }
    }

    func testScalarMismatchChecksCurrentnessBeforeReturningFalse() {
        let common = scalarSegments(repetitions: 100)
        let left = RetainedViewIdentity(segments: common + [.slot(1)])
        let right = RetainedViewIdentity(segments: common + [.slot(2)])
        for revokeAtExit in [false, true] {
            var prefixChecks = 0
            var equalityChecks = 0

            let prefix = left.checkedHasPrefix(right) {
                prefixChecks += 1
                return !revokeAtExit || prefixChecks < 2
            }
            let equality = left.checkedEquals(right) {
                equalityChecks += 1
                return !revokeAtExit || equalityChecks < 3
            }

            XCTAssertEqual(prefix, revokeAtExit ? nil : false)
            XCTAssertEqual(equality, revokeAtExit ? nil : false)
            XCTAssertEqual(prefixChecks, 2)
            XCTAssertEqual(equalityChecks, 3)
        }
    }

    func testLengthMismatchDoesNotEnterAuthoredEquality() {
        let probe = ScalarEqualityProbe()
        let short = identity(firstValue: 1, probe: probe)
        let long = identity(firstValue: 1, probe: probe).appending(.slot(99))
        probe.begin()

        XCTAssertEqual(short.checkedEquals(long, isCurrent: { probe.isCurrent }), false)
        XCTAssertEqual(long.checkedEquals(short, isCurrent: { probe.isCurrent }), false)
        XCTAssertEqual(short.checkedHasPrefix(long, isCurrent: { probe.isCurrent }), false)
        XCTAssertNil(short.checkedEquals(long, isCurrent: { false }))
        XCTAssertNil(short.checkedHasPrefix(long, isCurrent: { false }))
        XCTAssertTrue(probe.entered.isEmpty)
    }

    func testScalarMismatchDoesNotEnterLaterAuthoredEquality() {
        let probe = ScalarEqualityProbe()
        let common = scalarSegments(repetitions: 100)
        let key = RetainedViewIdentity.Key(ScalarEqualityKey(value: 1, probe: probe))
        let left = RetainedViewIdentity(segments: common + [.slot(1), .keyed(key)])
        let right = RetainedViewIdentity(segments: common + [.slot(2), .keyed(key)])
        probe.begin()

        XCTAssertEqual(left.checkedEquals(right, isCurrent: { probe.isCurrent }), false)
        XCTAssertEqual(left.checkedHasPrefix(right, isCurrent: { probe.isCurrent }), false)
        XCTAssertTrue(probe.entered.isEmpty)
    }

    func testAuthoredEqualityRevocationRejectsEqualAndUnequalResultsBeforeTheNextKey() {
        for firstValue in [1, 9] {
            let probe = ScalarEqualityProbe()
            let left = identity(firstValue: 1, probe: probe)
            let right = identity(firstValue: firstValue, probe: probe)
            probe.begin(revoking: 1)

            XCTAssertNil(left.checkedEquals(right, isCurrent: { probe.isCurrent }))
            XCTAssertEqual(probe.entered, [1])
            XCTAssertTrue(probe.enteredAfterRevocation.isEmpty)
            probe.begin(revoking: 1)

            XCTAssertNil(left.checkedHasPrefix(right, isCurrent: { probe.isCurrent }))
            XCTAssertEqual(probe.entered, [1])
            XCTAssertTrue(probe.enteredAfterRevocation.isEmpty)
        }
    }

    func testNestedFrameworkBoxesPreserveAuthoredEqualityBoundaries() {
        for wrapper in 0..<3 {
            for firstValue in [1, 9] {
                let probe = ScalarEqualityProbe()
                let left = wrappedIdentity(wrapper, firstValue: 1, probe: probe)
                let right = wrappedIdentity(wrapper, firstValue: firstValue, probe: probe)
                probe.begin(revoking: 1)

                XCTAssertNil(left.checkedEquals(right, isCurrent: { probe.isCurrent }))
                XCTAssertEqual(probe.entered, [1])
                XCTAssertTrue(probe.enteredAfterRevocation.isEmpty)
                probe.begin(revoking: 1)

                XCTAssertNil(left.checkedHasPrefix(right, isCurrent: { probe.isCurrent }))
                XCTAssertEqual(probe.entered, [1])
                XCTAssertTrue(probe.enteredAfterRevocation.isEmpty)
            }
        }
    }

    func testScalarRunsStillCheckBeforeEnteringAnAuthoredComparison() {
        let probe = ScalarEqualityProbe()
        let left = identity(firstValue: 1, probe: probe)
        let right = identity(firstValue: 1, probe: probe)
        probe.begin()
        var prefixChecks = 0
        var equalityChecks = 0

        XCTAssertNil(
            left.checkedHasPrefix(right) {
                prefixChecks += 1
                return prefixChecks < 2
            })
        XCTAssertNil(
            left.checkedEquals(right) {
                equalityChecks += 1
                return equalityChecks < 3
            })

        XCTAssertEqual(prefixChecks, 2)
        XCTAssertEqual(equalityChecks, 3)
        XCTAssertTrue(probe.entered.isEmpty)
    }

    func testSuccessfulPrefixDoesNotCompareAnAuthoredSuffix() {
        let probe = ScalarEqualityProbe()
        let common = scalarSegments(repetitions: 100)
        let left = RetainedViewIdentity(
            segments: common + [.keyed(.init(ScalarEqualityKey(value: 1, probe: probe)))]
                + common + [.keyed(.init(ScalarEqualityKey(value: 2, probe: probe)))])
        let prefix = RetainedViewIdentity(
            segments: common + [.keyed(.init(ScalarEqualityKey(value: 1, probe: probe)))])
        probe.begin()

        XCTAssertEqual(left.checkedHasPrefix(prefix, isCurrent: { probe.isCurrent }), true)
        XCTAssertEqual(probe.entered, [1])
        XCTAssertTrue(probe.enteredAfterRevocation.isEmpty)
    }

    private func identity(firstValue: Int, probe: ScalarEqualityProbe) -> RetainedViewIdentity {
        let scalar = scalarSegments(repetitions: 30)
        return RetainedViewIdentity(
            segments: scalar + [.keyed(.init(ScalarEqualityKey(value: firstValue, probe: probe)))]
                + scalar + [.explicit(.init(ScalarEqualityKey(value: 2, probe: probe)))] + scalar)
    }

    private func wrappedIdentity(
        _ wrapper: Int, firstValue: Int, probe: ScalarEqualityProbe
    ) -> RetainedViewIdentity {
        let inner = identity(firstValue: firstValue, probe: probe)
        let key: RetainedViewIdentity.Key
        switch wrapper {
        case 0: key = .init(inner)
        case 1: key = .init(RetainedViewIdentity.Key(inner))
        default: key = .init(RetainedViewIdentity.Segment.explicit(.init(inner)))
        }
        return RetainedViewIdentity(
            segments: scalarSegments(repetitions: 20) + [.keyed(key)]
                + [.keyed(.init(ScalarEqualityKey(value: 3, probe: probe)))])
    }

    private func scalarSegments(repetitions: Int) -> [RetainedViewIdentity.Segment] {
        (0..<repetitions).flatMap { value -> [RetainedViewIdentity.Segment] in
            [
                .view(ObjectIdentifier(ScalarEqualityFirstMarker.self)), .role(.content), .slot(value),
                .branch(value.isMultiple(of: 2)), .iteration(value), .occurrence(value),
            ]
        }
    }
}

private enum ScalarEqualityFirstMarker {}
private enum ScalarEqualitySecondMarker {}

private final class ScalarEqualityProbe {
    private(set) var isCurrent = true
    private(set) var entered: [Int] = []
    private(set) var enteredAfterRevocation: [Int] = []
    private var revoking: Int?

    func begin(revoking: Int? = nil) {
        isCurrent = true
        entered = []
        enteredAfterRevocation = []
        self.revoking = revoking
    }

    func enter(_ value: Int) {
        entered.append(value)
        if !isCurrent { enteredAfterRevocation.append(value) }
        if value == revoking { isCurrent = false }
    }
}

private struct ScalarEqualityKey: Hashable {
    let value: Int
    let probe: ScalarEqualityProbe

    func hash(into hasher: inout Hasher) {
        hasher.combine(value)
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.probe.enter(lhs.value)
        return lhs.value == rhs.value
    }
}
