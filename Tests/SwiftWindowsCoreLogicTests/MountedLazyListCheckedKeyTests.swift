import SwiftWindowsCore
@preconcurrency import XCTest

@testable import SwiftWindowsUI
@testable import WinSwiftUI

@MainActor
final class MountedLazyListCheckedKeyTests: XCTestCase {
    func testRejectedIdentityOperationsDoNotEnterAnyAuthoredKey() async {
        let events = MountedCheckedKeyEvents()
        let value = identity([1, 2], events: events)
        events.begin()
        events.isCurrent = false
        var hasher = Hasher()

        XCTAssertFalse(value.checkedHash(into: &hasher, isCurrent: { events.isCurrent }))
        XCTAssertNil(value.checkedEquals(value, isCurrent: { events.isCurrent }))
        XCTAssertNil(value.checkedHasPrefix(value, isCurrent: { events.isCurrent }))
        XCTAssertTrue(events.callbacks.isEmpty)
    }

    func testCheckedHashStopsImmediatelyAfterTheRejectingAuthoredSegment() async {
        let events = MountedCheckedKeyEvents()
        let value = identity([1, 2, 3], events: events)
        events.begin(rejecting: "hash:1")
        var hasher = Hasher()

        XCTAssertFalse(value.checkedHash(into: &hasher, isCurrent: { events.isCurrent }))

        XCTAssertEqual(events.callbacks, ["hash:1"])
        XCTAssertTrue(events.callbacksAfterRejection.isEmpty)
    }

    func testCheckedEqualityRejectsBothEqualAndUnequalCallbackResults() async {
        for first in [1, 9] {
            let events = MountedCheckedKeyEvents()
            let left = identity([1, 2], events: events)
            let right = identity([first, 2], events: events)
            let rejection = "equal:1:\(first)"
            events.begin(rejecting: rejection)

            XCTAssertNil(left.checkedEquals(right, isCurrent: { events.isCurrent }))

            XCTAssertEqual(events.callbacks, [rejection])
            XCTAssertTrue(events.callbacksAfterRejection.isEmpty)
        }
    }

    func testCheckedPrefixRejectsBeforeComparingTheNextAuthoredSegment() async {
        for first in [1, 9] {
            let events = MountedCheckedKeyEvents()
            let value = identity([1, 2, 3], events: events)
            let prefix = identity([first, 2], events: events)
            let rejection = "equal:1:\(first)"
            events.begin(rejecting: rejection)

            XCTAssertNil(value.checkedHasPrefix(prefix, isCurrent: { events.isCurrent }))

            XCTAssertEqual(events.callbacks, [rejection])
            XCTAssertTrue(events.callbacksAfterRejection.isEmpty)
        }
    }

    func testSuccessfulPrefixDoesNotVisitKeysBeyondThePrefix() async {
        let events = MountedCheckedKeyEvents()
        let value = identity([1, 2, 3], events: events)
        let prefix = identity([1, 2], events: events)
        events.begin()

        XCTAssertEqual(value.checkedHasPrefix(prefix, isCurrent: { events.isCurrent }), true)

        XCTAssertEqual(events.callbacks, ["equal:1:1", "equal:2:2"])
        events.begin()
        XCTAssertEqual(prefix.checkedHasPrefix(value, isCurrent: { events.isCurrent }), false)
        XCTAssertEqual(value.checkedEquals(prefix, isCurrent: { events.isCurrent }), false)
        XCTAssertTrue(events.callbacks.isEmpty, "Structural length mismatches require no authored equality")
    }

    func testCheckedEqualityPreservesTypedAndStructuralIdentity() async {
        let events = MountedCheckedKeyEvents()
        let key = authoredKey(7, events: events)
        let value = RetainedViewIdentity(segments: [.keyed(key), .occurrence(0)])
        let otherType = RetainedViewIdentity.Key(
            MountedCheckedCollisionKey<MountedCheckedOtherDomain>(value: 7, events: events))
        let variants = [
            RetainedViewIdentity(segments: [.explicit(key), .occurrence(0)]),
            RetainedViewIdentity(segments: [.keyed(key), .occurrence(1)]),
            RetainedViewIdentity(segments: [.keyed(otherType), .occurrence(0)]),
        ]

        for other in variants {
            events.begin()
            XCTAssertEqual(value.checkedEquals(other, isCurrent: { events.isCurrent }), false)
            XCTAssertTrue(events.isCurrent)
        }
        events.begin()
        XCTAssertEqual(
            RetainedViewIdentity.Key(Int8(7)).checkedEquals(
                RetainedViewIdentity.Key(Int64(7)), isCurrent: { events.isCurrent }), false)
        XCTAssertTrue(events.callbacks.isEmpty)
    }

    func testNestedFrameworkKeysStopHashingInsideTheWrappedIdentity() async {
        for wrapper in MountedCheckedFrameworkWrapper.allCases {
            let events = MountedCheckedKeyEvents()
            let value = wrappedIdentity(wrapper, events: events)
            events.begin(rejecting: "hash:1")
            var hasher = Hasher()

            XCTAssertFalse(value.checkedHash(into: &hasher, isCurrent: { events.isCurrent }), "\(wrapper)")

            XCTAssertEqual(events.callbacks, ["hash:1"], "\(wrapper)")
            XCTAssertTrue(events.callbacksAfterRejection.isEmpty, "\(wrapper)")
        }
    }

    func testNestedFrameworkKeysStopEqualityInsideTheWrappedIdentity() async {
        for wrapper in MountedCheckedFrameworkWrapper.allCases {
            let events = MountedCheckedKeyEvents()
            let left = wrappedIdentity(wrapper, events: events)
            let right = wrappedIdentity(wrapper, events: events)
            events.begin(rejecting: "equal:1:1")

            XCTAssertNil(left.checkedEquals(right, isCurrent: { events.isCurrent }), "\(wrapper)")

            XCTAssertEqual(events.callbacks, ["equal:1:1"], "\(wrapper)")
            XCTAssertTrue(events.callbacksAfterRejection.isEmpty, "\(wrapper)")
        }
    }

    func testNestedFrameworkKeysStopPrefixComparisonInsideTheWrappedIdentity() async {
        for wrapper in MountedCheckedFrameworkWrapper.allCases {
            let events = MountedCheckedKeyEvents()
            let prefix = wrappedIdentity(wrapper, events: events)
            let value = wrappedIdentity(wrapper, events: events).appending(.keyed(authoredKey(4, events: events)))
            events.begin(rejecting: "equal:1:1")

            XCTAssertNil(value.checkedHasPrefix(prefix, isCurrent: { events.isCurrent }), "\(wrapper)")

            XCTAssertEqual(events.callbacks, ["equal:1:1"], "\(wrapper)")
            XCTAssertTrue(events.callbacksAfterRejection.isEmpty, "\(wrapper)")
        }
    }

    func testRejectedMapOperationsDoNotHashTheirRequestedKey() async {
        let events = MountedCheckedKeyEvents()
        let keys = (0..<3).map { identity([$0], events: events) }
        var values = map(keys)
        events.begin()
        events.isCurrent = false

        XCTAssertNil(values[keys[0], while: { events.isCurrent }])
        XCTAssertFalse(values.setValue(99, for: keys[0], isCurrent: { events.isCurrent }))
        values[keys[1], while: { events.isCurrent }] = nil
        XCTAssertNil(values.removeValue(forKey: keys[2], while: { events.isCurrent }))

        XCTAssertTrue(events.callbacks.isEmpty)
        XCTAssertEqual(values.count, 3)
        XCTAssertEqual(values.values.sorted(), [0, 1, 2])
    }

    func testCollisionLookupStopsBeforeTheNextStoredKey() async {
        let events = MountedCheckedKeyEvents()
        let keys = (0..<4).map { identity([$0], events: events) }
        let values = map(keys)
        events.begin(rejecting: "equal:0:3")

        XCTAssertNil(values[keys[3], while: { events.isCurrent }])

        XCTAssertEqual(events.callbacks, ["hash:3", "equal:0:3"])
        XCTAssertTrue(events.callbacksAfterRejection.isEmpty)
        XCTAssertEqual(values.values.sorted(), [0, 1, 2, 3])
        events.begin()
        XCTAssertEqual(values[keys[3]], 3, "An ordinary lookup still resolves the later colliding key")
    }

    func testCollisionUpdateAndInsertionCannotPublishAfterAnEqualityRejects() async {
        for requested in [3, 99] {
            let events = MountedCheckedKeyEvents()
            let keys = (0..<4).map { identity([$0], events: events) }
            var values = map(keys)
            let query = identity([requested], events: events)
            events.begin(rejecting: "equal:0:\(requested)")

            XCTAssertFalse(values.setValue(100, for: query, isCurrent: { events.isCurrent }))

            XCTAssertEqual(events.callbacks, ["hash:\(requested)", "equal:0:\(requested)"])
            XCTAssertTrue(events.callbacksAfterRejection.isEmpty)
            XCTAssertEqual(values.count, 4)
            XCTAssertEqual(values.values.sorted(), [0, 1, 2, 3])
            events.begin()
            XCTAssertEqual(values[keys[3]], 3)
            XCTAssertNil(values[identity([99], events: events)])
        }
    }

    func testGuardedSubscriptRejectsBeforeTheSecondRequestedKeyIsHashed() async {
        let events = MountedCheckedKeyEvents()
        let key = identity([1, 2], events: events)
        var values: ManagedKeyedMap<RetainedViewIdentity, Int> = [key: 7]
        events.begin(rejecting: "hash:1")

        values[key, while: { events.isCurrent }] = 8

        XCTAssertEqual(events.callbacks, ["hash:1"])
        XCTAssertTrue(events.callbacksAfterRejection.isEmpty)
        XCTAssertEqual(values.values, [7])
    }

    func testCollisionLookupStopsWithinTheStoredMultiKeyIdentity() async {
        let events = MountedCheckedKeyEvents()
        let keys = [identity([1, 10], events: events), identity([1, 11], events: events)]
        let values = map(keys)
        let query = identity([1, 99], events: events)
        events.begin(rejecting: "equal:1:1")

        XCTAssertNil(values[query, while: { events.isCurrent }])

        XCTAssertEqual(events.callbacks, ["hash:1", "hash:99", "equal:1:1"])
        XCTAssertTrue(events.callbacksAfterRejection.isEmpty)
    }

    func testCollisionRemovalDoesNotRehashSurvivorsAfterRejection() async {
        let events = MountedCheckedKeyEvents()
        let keys = (0..<64).map { identity([$0], events: events) }
        var values = map(keys)
        events.begin(rejecting: "equal:0:63")

        XCTAssertNil(values.removeValue(forKey: keys[63], while: { events.isCurrent }))

        XCTAssertEqual(events.callbacks, ["hash:63", "equal:0:63"])
        XCTAssertTrue(events.callbacksAfterRejection.isEmpty)
        XCTAssertEqual(values.count, 64)
        XCTAssertEqual(values.values.sorted(), Array(0..<64))
    }

    func testExtraCollidingKeyCannotModifyEitherCleanupSnapshotAfterInvalidation() async {
        let events = MountedCheckedKeyEvents()
        let keys = (0..<32).map { identity([$0], events: events) }
        let published = map(keys)
        var candidate = published
        var cleanupCandidate = published
        var cleanupReceipts: [Bool] = []
        var cleanupWrites: [Bool] = []
        var extraKey: RetainedViewIdentity.Key? = .init(
            MountedCheckedReleasedKey(value: 100) {
                cleanupReceipts.append(events.isCurrent)
                cleanupWrites.append(
                    cleanupCandidate.setValue(999, for: keys[31], isCurrent: { events.isCurrent }))
            })
        XCTAssertNotNil(extraKey)
        events.begin(rejecting: "equal:0:31")
        events.onRejection = { extraKey = nil }

        // Key zero is an unrelated stored key visited by collision resolution,
        // not the requested departing key. Its callback revokes this cleanup.
        XCTAssertFalse(candidate.setValue(nil, for: keys[31], isCurrent: { events.isCurrent }))

        XCTAssertEqual(events.callbacks, ["hash:31", "equal:0:31"])
        XCTAssertTrue(events.callbacksAfterRejection.isEmpty)
        XCTAssertNil(extraKey)
        XCTAssertEqual(cleanupReceipts, [false], "Arbitrary key cleanup observes the revoked receipt")
        XCTAssertEqual(cleanupWrites, [false], "Cleanup cannot publish a replacement through an expired map operation")
        XCTAssertEqual(cleanupCandidate.values.sorted(), Array(0..<32))
        XCTAssertEqual(candidate.count, 32)
        XCTAssertEqual(candidate.values.sorted(), Array(0..<32))
        XCTAssertEqual(published.count, 32)
        XCTAssertEqual(published.values.sorted(), Array(0..<32))
    }

    func testSuccessfulCollisionRemovalDoesNotRehashOtherAuthoredKeys() async {
        let events = MountedCheckedKeyEvents()
        let keys = (0..<64).map { identity([$0], events: events) }
        var values = map(keys)
        events.begin()

        XCTAssertEqual(values.removeValue(forKey: keys[0], while: { events.isCurrent }), 0)

        XCTAssertFalse(events.callbacks.isEmpty)
        XCTAssertTrue(
            events.callbacks.allSatisfy { $0 == "hash:0" || $0 == "equal:0:0" },
            "Removing one bucket entry must not invoke Hashable on a surviving key")
        XCTAssertEqual(values.count, 63)
        XCTAssertEqual(values.values.sorted(), Array(1..<64))
        events.begin()
        XCTAssertNil(values[keys[0]])
        XCTAssertEqual(values[keys[63]], 63)
    }

    func testCollisionBucketGrowthDoesNotRehashStoredAuthoredKeys() async {
        let events = MountedCheckedKeyEvents()
        let keys = (0..<64).map { identity([$0], events: events) }
        var values = map(keys)
        let incoming = identity([64], events: events)
        events.begin()

        XCTAssertTrue(values.setValue(64, for: incoming, isCurrent: { events.isCurrent }))

        XCTAssertEqual(events.callbacks, ["hash:64"] + (0..<64).map { "equal:\($0):64" })
        XCTAssertEqual(values.count, 65)
        XCTAssertEqual(values.values.sorted(), Array(0..<65))
    }

    func testQualifiedKeysKeepTypedDuplicateOccurrencesAcrossReorderAndNewTokens() async throws {
        let events = MountedCheckedKeyEvents()
        let first = authoredKey(1, events: events)
        let second = authoredKey(2, events: events)
        let otherType = RetainedViewIdentity.Key(
            MountedCheckedCollisionKey<MountedCheckedOtherDomain>(value: 1, events: events))
        let source = RetainedLazyListDataSource<RetainedViewIdentity.Key, Int>()
        let replacement = RetainedLazyListDataSource<RetainedViewIdentity.Key, Int>()
        var factories = 0
        defer {
            source.close()
            replacement.close()
        }
        XCTAssertTrue(
            source.replaceData([first, first, second, otherType], id: \.self) { _ in
                factories += 1
                return 0
            })
        let original = try XCTUnwrap(source.metadata).rows
        XCTAssertEqual(original.map(\.occurrence), [0, 1, 0, 0])
        var values: ManagedKeyedMap<LazyListQualifiedKey, Int> = [:]
        for (index, row) in original.enumerated() { values[LazyListQualifiedKey(row)] = index }
        XCTAssertEqual(values.count, 4)

        XCTAssertTrue(
            replacement.replaceData([otherType, second, first, first], id: \.self) { _ in
                factories += 1
                return 0
            })
        let reordered = try XCTUnwrap(replacement.metadata).rows
        XCTAssertEqual(reordered.map(\.occurrence), [0, 0, 0, 1])
        events.begin()

        XCTAssertEqual(reordered.map { values[LazyListQualifiedKey($0), while: { events.isCurrent }] }, [3, 2, 0, 1])

        XCTAssertEqual(factories, 0, "Logical key checks must not materialize any row")
        XCTAssertTrue(events.isCurrent)
        let originalTokens = Set(original.map(\.token))
        XCTAssertTrue(reordered.allSatisfy { !originalTokens.contains($0.token) })
        XCTAssertEqual(values.removeValue(forKey: LazyListQualifiedKey(reordered[3])), 1)
        XCTAssertEqual(values[LazyListQualifiedKey(reordered[2])], 0)
        XCTAssertEqual(values[LazyListQualifiedKey(reordered[0])], 3)
        XCTAssertEqual(values.count, 3)
    }

    private func authoredKey(_ value: Int, events: MountedCheckedKeyEvents) -> RetainedViewIdentity.Key {
        RetainedViewIdentity.Key(MountedCheckedCollisionKey<MountedCheckedFirstDomain>(value: value, events: events))
    }

    private func identity(_ values: [Int], events: MountedCheckedKeyEvents) -> RetainedViewIdentity {
        RetainedViewIdentity(segments: values.map { .keyed(authoredKey($0, events: events)) })
    }

    private func map(_ keys: [RetainedViewIdentity]) -> ManagedKeyedMap<RetainedViewIdentity, Int> {
        var result: ManagedKeyedMap<RetainedViewIdentity, Int> = [:]
        for (index, key) in keys.enumerated() { result[key] = index }
        return result
    }

    private func wrappedIdentity(
        _ wrapper: MountedCheckedFrameworkWrapper, events: MountedCheckedKeyEvents
    ) -> RetainedViewIdentity {
        let inner = identity([1, 2], events: events)
        let key: RetainedViewIdentity.Key
        switch wrapper {
        case .identity:
            key = .init(inner)
        case .key:
            key = .init(RetainedViewIdentity.Key(inner))
        case .segment:
            key = .init(RetainedViewIdentity.Segment.explicit(.init(inner)))
        case .recursive:
            key = .init(
                RetainedViewIdentity.Key(
                    RetainedViewIdentity.Segment.keyed(
                        .init(RetainedViewIdentity(segments: [.explicit(.init(inner))])))))
        }
        return RetainedViewIdentity(segments: [.keyed(key), .keyed(authoredKey(3, events: events))])
    }
}

@MainActor
private final class MountedCheckedKeyEvents {
    var isCurrent = true
    var onRejection: (@MainActor () -> Void)?
    private(set) var callbacks: [String] = []
    private(set) var callbacksAfterRejection: [String] = []
    private var rejecting: String?

    func begin(rejecting: String? = nil) {
        isCurrent = true
        callbacks = []
        callbacksAfterRejection = []
        onRejection = nil
        self.rejecting = rejecting
    }

    func record(_ callback: String) {
        callbacks.append(callback)
        if !isCurrent { callbacksAfterRejection.append(callback) }
        if callback == rejecting {
            isCurrent = false
            let cleanup = onRejection
            onRejection = nil
            cleanup?()
        }
    }
}

// Only these main-actor tests invoke the nonisolated Hashable witnesses. Every
// value in one declared domain deliberately hashes to the same bucket.
private struct MountedCheckedCollisionKey<Domain>: Hashable {
    let value: Int
    let events: MountedCheckedKeyEvents

    static func == (lhs: Self, rhs: Self) -> Bool {
        MainActor.assumeIsolated { lhs.events.record("equal:\(lhs.value):\(rhs.value)") }
        return lhs.value == rhs.value
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(0)
        MainActor.assumeIsolated { events.record("hash:\(value)") }
    }
}

private final class MountedCheckedReleasedKey: Hashable {
    let value: Int
    let onRelease: @MainActor () -> Void

    init(value: Int, onRelease: @escaping @MainActor () -> Void) {
        self.value = value
        self.onRelease = onRelease
    }

    static func == (lhs: MountedCheckedReleasedKey, rhs: MountedCheckedReleasedKey) -> Bool {
        lhs.value == rhs.value
    }

    func hash(into hasher: inout Hasher) { hasher.combine(value) }

    deinit { MainActor.assumeIsolated { [onRelease] in onRelease() } }
}

private enum MountedCheckedFirstDomain {}
private enum MountedCheckedOtherDomain {}

private enum MountedCheckedFrameworkWrapper: CaseIterable {
    case identity
    case key
    case segment
    case recursive
}
