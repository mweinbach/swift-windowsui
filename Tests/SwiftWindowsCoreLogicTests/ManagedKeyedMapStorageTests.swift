@preconcurrency import XCTest

@testable import WinSwiftUI

@MainActor
final class ManagedKeyedMapStorageTests: XCTestCase {
    func testReplacementKeepsStoredKeyAndDefersValueCleanupThroughFinalAdmission() async {
        let events = ManagedMapStorageEvents()
        var map = makeMap([(0, 0, "old")], events: events)
        weak var storedKey = map.keys.first
        let query = ManagedMapStorageKey(value: 0, bucket: 0, events: events)
        weak var oldValue = map[query]
        events.clear()
        events.revokeOnValueRelease = "old"
        var cleanupMap: ManagedKeyedMap<ManagedMapStorageKey, Int> = [:]
        var cleanupResult: Bool?
        events.onValueRelease = { [weak events] label in
            guard label == "old", let events else { return }
            cleanupResult = cleanupMap.setValue(17, for: query, isCurrent: { events.isCurrent })
        }

        let result = map.setValue(ManagedMapStorageValue("new", events: events), for: query) {
            events.admissionChecks.append(storedKey != nil && oldValue != nil)
            return events.isCurrent
        }

        XCTAssertTrue(result, "The final admission check precedes deferred payload cleanup")
        XCTAssertFalse(events.isCurrent, "The caller must still recheck after the helper releases its pins")
        XCTAssertFalse(events.admissionChecks.isEmpty)
        XCTAssertTrue(events.admissionChecks.allSatisfy { $0 })
        XCTAssertEqual(events.valueReleases, ["old"])
        XCTAssertEqual(cleanupResult, false)
        XCTAssertTrue(cleanupMap.isEmpty)
        XCTAssertNil(oldValue)
        XCTAssertTrue(map.keys.first === storedKey, "An equal query must not replace the stored key object")
        XCTAssertEqual(map[query]?.label, "new")
        XCTAssertEqual(map.count, 1)
        events.onValueRelease = nil
    }

    func testRemovalPinsDepartingKeyAndValueWithAndWithoutCollisionSurvivors() async {
        for hasSurvivor in [false, true] {
            let events = ManagedMapStorageEvents()
            let entries = hasSurvivor ? [(0, 0, "old"), (1, 0, "survivor")] : [(0, 0, "old")]
            var map = makeMap(entries, events: events)
            weak var storedKey = map.keys.first(where: { $0.value == 0 })
            let query = ManagedMapStorageKey(value: 0, bucket: 0, events: events)
            weak var oldValue = map[query]
            events.clear()
            events.revokeOnValueRelease = "old"

            // removeValue(forKey:) returns and therefore separately pins its old
            // value. Direct setValue(nil) exercises the publication lifetime.
            let result = map.setValue(nil, for: query) {
                events.admissionChecks.append(storedKey != nil && oldValue != nil)
                return events.isCurrent
            }

            XCTAssertTrue(result)
            XCTAssertFalse(events.isCurrent)
            XCTAssertFalse(events.admissionChecks.isEmpty)
            XCTAssertTrue(events.admissionChecks.allSatisfy { $0 })
            XCTAssertEqual(events.valueReleases, ["old"])
            XCTAssertEqual(events.keyReleases, [0])
            XCTAssertNil(storedKey, "Only the equal query, not the departing stored key, remains owned")
            XCTAssertNil(oldValue)
            XCTAssertEqual(map.count, hasSurvivor ? 1 : 0)
            XCTAssertEqual(map.values.map(\.label), hasSurvivor ? ["survivor"] : [])
        }
    }

    func testSuccessfulWritesPreserveIndependentCallerSnapshots() async {
        let events = ManagedMapStorageEvents()
        var original = makeMap([(0, 0, "zero"), (1, 0, "one"), (2, 2, "two")], events: events)
        var candidate = original
        var sibling = original
        let zero = ManagedMapStorageKey(value: 0, bucket: 0, events: events)
        let one = ManagedMapStorageKey(value: 1, bucket: 0, events: events)
        let two = ManagedMapStorageKey(value: 2, bucket: 2, events: events)
        let three = ManagedMapStorageKey(value: 3, bucket: 3, events: events)
        events.clear()

        XCTAssertTrue(candidate.setValue(nil, for: zero, isCurrent: { events.isCurrent }))
        XCTAssertTrue(
            candidate.setValue(ManagedMapStorageValue("changed", events: events), for: one) { events.isCurrent })
        XCTAssertTrue(
            candidate.setValue(ManagedMapStorageValue("three", events: events), for: three) { events.isCurrent })
        XCTAssertEqual(original.count, 3)
        XCTAssertEqual(sibling.count, 3)
        XCTAssertEqual(candidate.count, 3)
        XCTAssertEqual(original.values.map(\.label).sorted(), ["one", "two", "zero"])
        XCTAssertEqual(sibling.values.map(\.label).sorted(), ["one", "two", "zero"])
        XCTAssertEqual(candidate.values.map(\.label).sorted(), ["changed", "three", "two"])
        XCTAssertNil(candidate[zero])
        XCTAssertNil(original[three])
        XCTAssertTrue(original[two] === candidate[two])
        XCTAssertTrue(events.valueReleases.isEmpty)

        original.removeAll()
        XCTAssertTrue(events.valueReleases.isEmpty, "The sibling copy still owns every original value")
        sibling.removeAll()
        XCTAssertEqual(events.valueReleases.sorted(), ["one", "zero"])
        XCTAssertEqual(candidate[two]?.label, "two")
        candidate.removeAll()
        XCTAssertEqual(events.valueReleases.sorted(), ["changed", "one", "three", "two", "zero"])
    }

    func testDistinctBucketGrowthOnlyHashesIncomingKeysAndKeepsSurvivingPayloads() async {
        let events = ManagedMapStorageEvents()
        var map: ManagedKeyedMap<ManagedMapStorageKey, ManagedMapStorageValue> = [:]
        let count = 4_096
        for value in 0..<count {
            let key = ManagedMapStorageKey(value: value, bucket: value, events: events)
            XCTAssertTrue(
                map.setValue(ManagedMapStorageValue(String(value), events: events), for: key) { events.isCurrent })
        }

        XCTAssertEqual(map.count, count)
        XCTAssertEqual(events.hashes, Array(0..<count), "Dictionary growth must not rehash stored authored keys")
        XCTAssertTrue(events.keyReleases.isEmpty)
        XCTAssertTrue(events.valueReleases.isEmpty)
        XCTAssertEqual(Set(map.values.map(\.label)), Set((0..<count).map(String.init)))
        map.removeAll()
        XCTAssertEqual(events.valueReleases.count, count)
        XCTAssertEqual(Set(events.valueReleases), Set((0..<count).map(String.init)))
    }

    @inline(never)
    private func makeMap(
        _ entries: [(Int, Int, String)], events: ManagedMapStorageEvents
    ) -> ManagedKeyedMap<ManagedMapStorageKey, ManagedMapStorageValue> {
        var map: ManagedKeyedMap<ManagedMapStorageKey, ManagedMapStorageValue> = [:]
        for (value, bucket, label) in entries {
            let key = ManagedMapStorageKey(value: value, bucket: bucket, events: events)
            map[key] = ManagedMapStorageValue(label, events: events)
        }
        return map
    }
}

@MainActor
private final class ManagedMapStorageEvents {
    var isCurrent = true
    var hashes: [Int] = []
    var keyReleases: [Int] = []
    var valueReleases: [String] = []
    var admissionChecks: [Bool] = []
    var revokeOnValueRelease: String?
    var onValueRelease: (@MainActor (String) -> Void)?

    func clear() {
        hashes.removeAll()
        keyReleases.removeAll()
        valueReleases.removeAll()
        admissionChecks.removeAll()
    }

    func releasedValue(_ label: String) {
        valueReleases.append(label)
        if revokeOnValueRelease == label { isCurrent = false }
        onValueRelease?(label)
    }
}

// The fixtures enter all authored key operations from their main-actor tests.
// The native bucket hash is selected separately so collisions are deliberate.
private final class ManagedMapStorageKey: ManagedKeyedIdentity {
    let value: Int
    let bucket: Int
    let events: ManagedMapStorageEvents

    init(value: Int, bucket: Int, events: ManagedMapStorageEvents) {
        self.value = value
        self.bucket = bucket
        self.events = events
    }

    static func == (lhs: ManagedMapStorageKey, rhs: ManagedMapStorageKey) -> Bool {
        lhs.value == rhs.value && lhs.bucket == rhs.bucket
    }

    func hash(into hasher: inout Hasher) {
        MainActor.assumeIsolated { [events, value] in events.hashes.append(value) }
        hasher.combine(bucket)
    }

    func checkedHash(into hasher: inout Hasher, isCurrent: () -> Bool) -> Bool {
        guard isCurrent() else { return false }
        hash(into: &hasher)
        return isCurrent()
    }

    func checkedEquals(_ other: ManagedMapStorageKey, isCurrent: () -> Bool) -> Bool? {
        guard isCurrent() else { return nil }
        let equal = self == other
        return isCurrent() ? equal : nil
    }

    deinit { MainActor.assumeIsolated { [events, value] in events.keyReleases.append(value) } }
}

@MainActor
private final class ManagedMapStorageValue {
    let label: String
    let events: ManagedMapStorageEvents

    init(_ label: String, events: ManagedMapStorageEvents) {
        self.label = label
        self.events = events
    }

    isolated deinit { events.releasedValue(label) }
}
