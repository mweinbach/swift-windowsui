import SwiftWindowsCore
import XCTest

final class RetainedViewIdentityScalarHashTests: XCTestCase {
    func testScalarPathLengthDoesNotMultiplyAuthorizationChecks() {
        for repetitions in [0, 1, 10, 100] {
            let identity = RetainedViewIdentity(segments: scalarSegments(repetitions: repetitions))
            var checks = 0
            var hasher = Hasher()

            XCTAssertTrue(
                identity.checkedHash(into: &hasher) {
                    checks += 1
                    return true
                })

            XCTAssertEqual(checks, 2, "A callback-free scalar path needs entry and exit authorization")
        }
    }

    func testScalarHashRetainsOperationEntryAndExitAuthorization() {
        let identity = RetainedViewIdentity(segments: scalarSegments(repetitions: 100))
        for rejectingCheck in [1, 2] {
            var checks = 0
            var hasher = Hasher()

            XCTAssertFalse(
                identity.checkedHash(into: &hasher) {
                    checks += 1
                    return checks != rejectingCheck
                })

            XCTAssertEqual(checks, rejectingCheck)
        }
    }

    func testScalarBatchingPreservesTheExistingSeededHashSequence() {
        let scalar = scalarSegments(repetitions: 20)
        let variants = [
            RetainedViewIdentity(segments: []),
            RetainedViewIdentity(segments: scalar),
            RetainedViewIdentity(segments: scalar + [.keyed(.init(17))] + scalar),
            RetainedViewIdentity(segments: scalar + [.explicit(.init("key"))] + scalar),
            RetainedViewIdentity(segments: scalar + [.keyed(.init(RetainedViewIdentity(segments: scalar)))]),
        ]
        for identity in variants {
            let seed = Hasher()
            var actual = seed
            var expected = seed
            XCTAssertTrue(identity.checkedHash(into: &actual, isCurrent: { true }))
            expected.combine(identity.segments.count)
            for segment in identity.segments {
                switch segment {
                case .keyed(let key):
                    expected.combine(0)
                    XCTAssertTrue(key.checkedHash(into: &expected, isCurrent: { true }))
                case .explicit(let key):
                    expected.combine(1)
                    XCTAssertTrue(key.checkedHash(into: &expected, isCurrent: { true }))
                case .view, .role, .slot, .branch, .iteration, .occurrence:
                    expected.combine(2)
                    expected.combine(segment)
                }
            }

            XCTAssertEqual(actual.finalize(), expected.finalize())
        }
    }

    func testLongScalarPrefixStillChecksBeforeEnteringAnAuthoredKey() {
        let probe = ScalarHashProbe()
        let identity = RetainedViewIdentity(
            segments: scalarSegments(repetitions: 100) + [.keyed(.init(ScalarHashKey(value: 1, probe: probe)))])
        probe.begin()
        var checks = 0
        var hasher = Hasher()

        XCTAssertFalse(
            identity.checkedHash(into: &hasher) {
                checks += 1
                return checks < 2
            })

        XCTAssertEqual(checks, 2)
        XCTAssertTrue(probe.entered.isEmpty)
    }

    func testAuthoredHashRevocationStopsBeforeTheNextKeyAcrossScalarRuns() {
        let probe = ScalarHashProbe()
        let scalar = scalarSegments(repetitions: 100)
        let identity = RetainedViewIdentity(
            segments: scalar + [.keyed(.init(ScalarHashKey(value: 1, probe: probe)))]
                + scalar + [.explicit(.init(ScalarHashKey(value: 2, probe: probe)))] + scalar)
        probe.begin(revoking: 1)
        var hasher = Hasher()

        XCTAssertFalse(identity.checkedHash(into: &hasher, isCurrent: { probe.isCurrent }))

        XCTAssertEqual(probe.entered, [1])
        XCTAssertTrue(probe.enteredAfterRevocation.isEmpty)
    }

    func testNestedFrameworkBoxesKeepEveryAuthoredHashBoundary() {
        for wrapper in 0..<3 {
            let probe = ScalarHashProbe()
            let scalar = scalarSegments(repetitions: 40)
            let inner = RetainedViewIdentity(
                segments: scalar + [.keyed(.init(ScalarHashKey(value: 1, probe: probe)))]
                    + scalar + [.keyed(.init(ScalarHashKey(value: 2, probe: probe)))])
            let boxed: RetainedViewIdentity.Key
            switch wrapper {
            case 0: boxed = .init(inner)
            case 1: boxed = .init(RetainedViewIdentity.Key(inner))
            default: boxed = .init(RetainedViewIdentity.Segment.explicit(.init(inner)))
            }
            let identity = RetainedViewIdentity(
                segments: scalar + [.keyed(boxed)]
                    + scalar + [.keyed(.init(ScalarHashKey(value: 3, probe: probe)))])
            probe.begin(revoking: 1)
            var hasher = Hasher()

            XCTAssertFalse(identity.checkedHash(into: &hasher, isCurrent: { probe.isCurrent }))

            XCTAssertEqual(probe.entered, [1])
            XCTAssertTrue(probe.enteredAfterRevocation.isEmpty)
        }
    }

    private func scalarSegments(repetitions: Int) -> [RetainedViewIdentity.Segment] {
        (0..<repetitions).flatMap { value -> [RetainedViewIdentity.Segment] in
            [
                .view(ObjectIdentifier(ScalarHashMarker.self)), .role(.content), .slot(value),
                .branch(value.isMultiple(of: 2)), .iteration(value), .occurrence(value),
            ]
        }
    }
}

private enum ScalarHashMarker {}

private final class ScalarHashProbe {
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

private struct ScalarHashKey: Hashable {
    let value: Int
    let probe: ScalarHashProbe

    func hash(into hasher: inout Hasher) {
        probe.enter(value)
        hasher.combine(value)
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.value == rhs.value
    }
}
