import SwiftWindowsCore
import XCTest

/// Checked operations preserve the ordinary typed Key equivalence relation.
/// Their hash encoding may differ from synthesized Hashable, but equal keys
/// still need equal checked hashes when they use the same Hasher seed.
final class RetainedViewIdentityErasedKeyTests: XCTestCase {
    func testErasedOptionalSegmentMatchesOrdinaryEqualityInBothDirections() throws {
        let value = RetainedViewIdentity.Key(AnyHashable(RetainedViewIdentity.Segment.slot(7)))
        let optional = RetainedViewIdentity.Key(
            AnyHashable(Optional.some(RetainedViewIdentity.Segment.slot(7))))

        XCTAssertNotEqual(value, optional)
        try assertCheckedEqualityMatchesOrdinary(value, optional)
        try assertCheckedEqualityMatchesOrdinary(optional, value)
    }

    func testErasedFrameworkWrapperEqualityPreservesOrdinaryEquivalenceLaws() throws {
        for group in frameworkGroups() {
            var checked = Array(repeating: Array(repeating: false, count: group.count), count: group.count)
            for left in group.indices {
                for right in group.indices {
                    checked[left][right] = try assertCheckedEqualityMatchesOrdinary(
                        group[left].key, group[right].key, "\(group[left].label) / \(group[right].label)")
                }
            }

            for left in group.indices {
                XCTAssertTrue(checked[left][left], group[left].label)
                for middle in group.indices {
                    XCTAssertEqual(checked[left][middle], checked[middle][left], "Symmetry")
                    for right in group.indices where checked[left][middle] && checked[middle][right] {
                        XCTAssertTrue(
                            checked[left][right],
                            "Transitivity: \(group[left].label), \(group[middle].label), \(group[right].label)")
                    }
                }
            }
        }
    }

    func testOrdinarilyEqualErasedWrapperKeysHaveEqualCheckedHashes() throws {
        for group in frameworkGroups() {
            for left in group.indices {
                for right in group.indices where right > left && group[left].key == group[right].key {
                    try assertEqualCheckedHashes(
                        group[left].key, group[right].key, "\(group[left].label) / \(group[right].label)")
                }
            }
        }
    }

    func testNestedOptionalNilShapesFollowOrdinaryEquality() throws {
        try assertNilShapes(RetainedViewIdentity(segments: [.slot(7)]))
        try assertNilShapes(RetainedViewIdentity.Key(7))
        try assertNilShapes(RetainedViewIdentity.Segment.slot(7))
    }

    func testNumericErasureCanonicalizesWithoutErasingDeclaredKeyTypes() throws {
        let erasedSmall = RetainedViewIdentity.Key(AnyHashable(Int8(7)))
        let erasedWide = RetainedViewIdentity.Key(AnyHashable(Int64(7)))
        let erasedFloating = RetainedViewIdentity.Key(AnyHashable(Double(7)))
        XCTAssertEqual(erasedSmall, erasedWide)
        XCTAssertEqual(erasedWide, erasedFloating)
        try assertCheckedEqualityMatchesOrdinary(erasedSmall, erasedWide)
        try assertCheckedEqualityMatchesOrdinary(erasedWide, erasedFloating)
        try assertEqualCheckedHashes(erasedSmall, erasedWide)
        try assertEqualCheckedHashes(erasedWide, erasedFloating)

        let small = RetainedViewIdentity.Key(Int8(7))
        let wide = RetainedViewIdentity.Key(Int64(7))
        XCTAssertNotEqual(small, wide)
        XCTAssertNotEqual(small, erasedSmall)
        try assertCheckedEqualityMatchesOrdinary(small, wide)
        try assertCheckedEqualityMatchesOrdinary(small, erasedSmall)

        let segment = RetainedViewIdentity.Segment.slot(7)
        let declaredSegment = RetainedViewIdentity.Key(segment)
        let declaredOptional = RetainedViewIdentity.Key(Optional.some(segment))
        XCTAssertNotEqual(declaredSegment, declaredOptional)
        try assertCheckedEqualityMatchesOrdinary(declaredSegment, declaredOptional)
    }

    func testRejectedCheckedOperationsDoNotEnterErasedCallbacks() {
        for framework in ErasedKeyFramework.allCases {
            for optional in [false, true] {
                let events = ErasedKeyEvents()
                let left = callbackIdentity(framework, optional: optional, events: events)
                let right = callbackIdentity(framework, optional: optional, events: events)
                events.begin(isCurrent: false)
                var hasher = Hasher()

                XCTAssertFalse(left.checkedHash(into: &hasher, isCurrent: { events.isCurrent }))
                XCTAssertNil(left.checkedEquals(right, isCurrent: { events.isCurrent }))
                XCTAssertTrue(events.calls.isEmpty)
            }
        }
    }

    func testRevocationStopsAtTheErasedOperationBoundaryBeforeTheOuterSibling() {
        for framework in ErasedKeyFramework.allCases {
            for optional in [false, true] {
                let events = ErasedKeyEvents()
                let left = callbackIdentity(framework, optional: optional, events: events)
                // Independent construction prevents Array equality's shared
                // storage shortcut from suppressing the authored comparison.
                let equal = callbackIdentity(framework, optional: optional, events: events)
                let unequal = callbackIdentity(framework, optional: optional, events: events, firstValue: 9)
                events.begin(revokingAt: 1)
                var hasher = Hasher()

                XCTAssertFalse(left.checkedHash(into: &hasher, isCurrent: { events.isCurrent }))
                XCTAssertEqual(events.calls.first, .init(operation: .hash, value: 1))
                XCTAssertFalse(events.calls.contains { $0.value == 3 })
                if optional {
                    // This known Optional composite finishes its ordinary
                    // hash call, which visits both inner keys before returning.
                    XCTAssertTrue(events.calls.contains(.init(operation: .hash, value: 2)))
                } else {
                    XCTAssertEqual(events.calls.count, 1)
                }

                for right in [equal, unequal] {
                    events.begin(revokingAt: 1)

                    XCTAssertNil(left.checkedEquals(right, isCurrent: { events.isCurrent }))
                    XCTAssertEqual(events.calls.first, .init(operation: .equality, value: 1))
                    XCTAssertFalse(events.calls.contains { $0.value == 3 })
                    if !optional { XCTAssertEqual(events.calls.count, 1) }
                }
                // Optional/opaque composites are one entered Hashable call:
                // inner key 2 may run before that call returns. The checked
                // operation must reject before entering the outer sibling 3.
            }
        }
    }

    private func frameworkGroups() -> [[ErasedKeySample]] {
        [
            erasedSamples(
                RetainedViewIdentity(segments: [.role(.content), .keyed(.init(7)), .occurrence(0)]),
                name: "identity"),
            erasedSamples(RetainedViewIdentity.Key(7), name: "key"),
            erasedSamples(RetainedViewIdentity.Segment.slot(7), name: "segment"),
        ]
    }

    private func erasedSamples<Value: Hashable>(_ value: Value, name: String) -> [ErasedKeySample] {
        let box = AnyHashable(value)
        let some = AnyHashable(Optional<Value>.some(value))
        let nestedSome = AnyHashable(Optional<Value?>.some(.some(value)))
        let samples: [(String, AnyHashable)] = [
            ("native", box),
            ("same box", box),
            ("reboxed", AnyHashable(box)),
            ("some", some),
            ("same optional box", some),
            ("nested some", nestedSome),
            ("same nested box", nestedSome),
            ("none", AnyHashable(Optional<Value>.none)),
            ("nested none", AnyHashable(Optional<Value?>.none)),
            ("some none", AnyHashable(Optional<Value?>.some(.none))),
        ]
        // Every outer Key deliberately has declared type AnyHashable. A
        // direct Key<Value> comparison would hide the erased-base discrepancy
        // behind its legitimate declared-type mismatch.
        return samples.map { ErasedKeySample(label: "\(name): \($0.0)", key: .init($0.1)) }
    }

    private func assertNilShapes<Value: Hashable>(
        _ value: Value, file: StaticString = #filePath, line: UInt = #line
    ) throws {
        let none = RetainedViewIdentity.Key(AnyHashable(Optional<Value?>.none))
        let someNil = RetainedViewIdentity.Key(AnyHashable(Optional<Value?>.some(.none)))
        let someSome = RetainedViewIdentity.Key(AnyHashable(Optional<Value?>.some(.some(value))))
        XCTAssertNotEqual(none, someNil, file: file, line: line)
        XCTAssertNotEqual(someNil, someSome, file: file, line: line)
        try assertCheckedEqualityMatchesOrdinary(none, someNil, file: file, line: line)
        try assertCheckedEqualityMatchesOrdinary(someNil, none, file: file, line: line)
        try assertCheckedEqualityMatchesOrdinary(someNil, someSome, file: file, line: line)
    }

    @discardableResult
    private func assertCheckedEqualityMatchesOrdinary(
        _ left: RetainedViewIdentity.Key, _ right: RetainedViewIdentity.Key, _ context: String = "",
        file: StaticString = #filePath, line: UInt = #line
    ) throws -> Bool {
        let ordinary = left == right
        let checked = try XCTUnwrap(left.checkedEquals(right, isCurrent: { true }), context, file: file, line: line)
        XCTAssertEqual(checked, ordinary, context, file: file, line: line)
        return checked
    }

    private func assertEqualCheckedHashes(
        _ left: RetainedViewIdentity.Key, _ right: RetainedViewIdentity.Key, _ context: String = "",
        file: StaticString = #filePath, line: UInt = #line
    ) throws {
        XCTAssertEqual(left, right, context, file: file, line: line)
        let seed = Hasher()
        var leftHasher = seed
        var rightHasher = seed
        XCTAssertTrue(left.checkedHash(into: &leftHasher, isCurrent: { true }), context, file: file, line: line)
        XCTAssertTrue(right.checkedHash(into: &rightHasher, isCurrent: { true }), context, file: file, line: line)
        XCTAssertEqual(leftHasher.finalize(), rightHasher.finalize(), context, file: file, line: line)
    }

    private func callbackIdentity(
        _ framework: ErasedKeyFramework, optional: Bool, events: ErasedKeyEvents, firstValue: Int = 1
    ) -> RetainedViewIdentity {
        let inner = RetainedViewIdentity(
            segments: [
                .keyed(.init(ErasedKeyCallback(value: firstValue, events: events))),
                .keyed(.init(ErasedKeyCallback(value: 2, events: events))),
            ])
        let wrapped: RetainedViewIdentity.Key
        switch framework {
        case .identity:
            wrapped = callbackWrapper(inner, optional: optional)
        case .key:
            wrapped = callbackWrapper(RetainedViewIdentity.Key(inner), optional: optional)
        case .segment:
            wrapped = callbackWrapper(RetainedViewIdentity.Segment.explicit(.init(inner)), optional: optional)
        }
        return RetainedViewIdentity(
            segments: [.keyed(wrapped), .keyed(.init(ErasedKeyCallback(value: 3, events: events)))])
    }

    private func callbackWrapper<Value: Hashable>(_ value: Value, optional: Bool) -> RetainedViewIdentity.Key {
        optional ? .init(AnyHashable(Optional<Value>.some(value))) : .init(AnyHashable(value))
    }
}

private struct ErasedKeySample {
    let label: String
    let key: RetainedViewIdentity.Key
}

private enum ErasedKeyFramework: CaseIterable {
    case identity, key, segment
}

private struct ErasedKeyCall: Equatable {
    enum Operation { case hash, equality }
    let operation: Operation
    let value: Int
}

private final class ErasedKeyEvents {
    private(set) var calls: [ErasedKeyCall] = []
    private(set) var isCurrent = true
    private var revokingValue: Int?

    func begin(isCurrent: Bool = true, revokingAt value: Int? = nil) {
        calls = []
        self.isCurrent = isCurrent
        revokingValue = value
    }

    func record(_ operation: ErasedKeyCall.Operation, value: Int) {
        calls.append(.init(operation: operation, value: value))
        if value == revokingValue { isCurrent = false }
    }
}

private struct ErasedKeyCallback: Hashable {
    let value: Int
    let events: ErasedKeyEvents

    func hash(into hasher: inout Hasher) {
        events.record(.hash, value: value)
        hasher.combine(value)
    }

    static func == (left: Self, right: Self) -> Bool {
        left.events.record(.equality, value: left.value)
        return left.value == right.value
    }
}
