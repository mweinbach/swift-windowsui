import Foundation
import SwiftWindowsCore
@preconcurrency import XCTest

@testable import SwiftWindowsUI
@testable import WinSwiftUI

private struct MultiDatePickerBindingDocument {
    var dates: Set<DateComponents>
}

@MainActor
final class MultiDatePickerMountedTests: XCTestCase {
    func testClockIsReadOncePerMountedOccurrenceAndAgainOnlyAfterReplacement() async throws {
        let selection = MultiDatePickerTestSelection()
        var clockReads = 0
        var clockDate = multiDatePickerDate(2024, 1, 15)
        var unrelated = "Before"
        var generation = 0
        let host = multiDatePickerHost {
            AnyView(
                VStack {
                    Text(unrelated)
                    multiDatePickerView(
                        selection: selection.binding,
                        now: {
                            clockReads += 1
                            return clockDate
                        }
                    ).id(generation)
                })
        }
        defer { host.close() }
        host.render()
        XCTAssertEqual(clockReads, 1)
        XCTAssertEqual(try multiDatePickerTitle(in: host), "January 2024")
        unrelated = "After"
        clockDate = multiDatePickerDate(2025, 3, 15)
        host.reload()
        host.render()
        XCTAssertEqual(clockReads, 1)
        XCTAssertEqual(try multiDatePickerTitle(in: host), "January 2024")
        try multiDatePickerActivate(.nextMonth, in: host)
        host.reload()
        XCTAssertEqual(clockReads, 1)
        XCTAssertEqual(try multiDatePickerTitle(in: host), "February 2024")

        generation = 1
        host.reload()
        host.render()
        XCTAssertEqual(clockReads, 2)
        XCTAssertEqual(try multiDatePickerTitle(in: host), "March 2025")
        XCTAssertTrue(selection.writes.isEmpty)
        XCTAssertNil(host.coordinator.latestInstallationError)
    }

    func testSiblingPickersKeepIndependentBrowsedMonths() async throws {
        let left = MultiDatePickerTestSelection()
        let right = MultiDatePickerTestSelection()
        let host = multiDatePickerHost(size: Size(width: 900, height: 500)) {
            AnyView(
                HStack {
                    multiDatePickerView("Left dates", selection: left.binding)
                    multiDatePickerView("Right dates", selection: right.binding)
                })
        }
        defer { host.close() }
        host.render()
        try multiDatePickerActivate(.nextMonth, label: "Left dates", in: host)
        try multiDatePickerActivate(.nextMonth, label: "Left dates", in: host)
        try multiDatePickerActivate(.previousMonth, label: "Right dates", in: host)
        XCTAssertEqual(try multiDatePickerTitle(label: "Left dates", in: host), "April 2024")
        XCTAssertEqual(try multiDatePickerTitle(label: "Right dates", in: host), "January 2024")
        try multiDatePickerActivate(.day(multiDatePickerDate(2024, 4, 10)), label: "Left dates", in: host)
        XCTAssertEqual(left.value, [DateComponents(year: 2024, month: 4, day: 10)])
        XCTAssertTrue(right.value.isEmpty)
        XCTAssertEqual(try multiDatePickerTitle(label: "Right dates", in: host), "January 2024")
        XCTAssertNil(host.coordinator.latestInstallationError)
    }

    func testPrebuiltSourceInTwoHostsHasSeparateClockAndBrowsingState() async throws {
        let selection = MultiDatePickerTestSelection()
        var clockReads = 0
        let prebuilt = multiDatePickerView(
            selection: selection.binding,
            now: {
                clockReads += 1
                return multiDatePickerDate(2024, clockReads == 1 ? 1 : 5, 15)
            })
        let first = multiDatePickerHost { prebuilt }
        let second = multiDatePickerHost { prebuilt }
        defer {
            first.close()
            second.close()
        }
        first.render()
        second.render()
        XCTAssertEqual(clockReads, 2)
        XCTAssertEqual(try multiDatePickerTitle(in: first), "January 2024")
        XCTAssertEqual(try multiDatePickerTitle(in: second), "May 2024")
        try multiDatePickerActivate(.nextMonth, in: first)
        try multiDatePickerActivate(.previousMonth, in: second)
        XCTAssertEqual(try multiDatePickerTitle(in: first), "February 2024")
        XCTAssertEqual(try multiDatePickerTitle(in: second), "April 2024")
        first.close()
        second.reload()
        second.render()
        XCTAssertEqual(clockReads, 2)
        XCTAssertEqual(try multiDatePickerTitle(in: second), "April 2024")
        XCTAssertTrue(selection.writes.isEmpty)
        XCTAssertNil(second.coordinator.latestInstallationError)
    }

    func testSelectionAndUnrelatedRebuildsDoNotRecenterTheBrowsedMonth() async throws {
        let selection = MultiDatePickerTestSelection()
        var unrelated = "Before"
        let host = multiDatePickerHost {
            AnyView(
                VStack {
                    Text(unrelated)
                    multiDatePickerView(selection: selection.binding, now: { multiDatePickerDate(2024, 1, 15) })
                })
        }
        defer { host.close() }
        host.render()
        try multiDatePickerActivate(.nextMonth, in: host)
        selection.value = [DateComponents(year: 2024, month: 6, day: 1)]
        unrelated = "After"
        host.reload()
        host.render()
        XCTAssertEqual(try multiDatePickerTitle(in: host), "February 2024")
        XCTAssertTrue(selection.writes.isEmpty)
        try multiDatePickerActivate(.day(multiDatePickerDate(2024, 2, 20)), in: host)
        XCTAssertEqual(
            selection.value,
            [
                DateComponents(year: 2024, month: 6, day: 1), DateComponents(year: 2024, month: 2, day: 20),
            ])
        XCTAssertEqual(try multiDatePickerTitle(in: host), "February 2024")
        selection.value = []
        host.reload()
        host.render()
        XCTAssertEqual(try multiDatePickerTitle(in: host), "February 2024")
        XCTAssertFalse(
            try multiDatePickerNode(.day(multiDatePickerDate(2024, 2, 20)), in: host)
                .accessibilityTraits.contains(.isSelected))
        XCTAssertNil(host.coordinator.latestInstallationError)
    }

    func testKeyedReorderPreservesMonthsAndReplacementResetsOnlyItsOccurrence() async throws {
        var order = [1, 2]
        var firstGeneration = 0
        var clockReads = 0
        let host = multiDatePickerHost(size: Size(width: 900, height: 500)) {
            AnyView(
                HStack {
                    ForEach(order, id: \.self) { identifier in
                        multiDatePickerView(
                            "Dates \(identifier)", selection: .constant([]),
                            now: {
                                clockReads += 1
                                return multiDatePickerDate(2024, 1, 15)
                            }
                        ).id("\(identifier)-\(identifier == 1 ? firstGeneration : 0)")
                    }
                })
        }
        defer { host.close() }
        host.render()
        XCTAssertEqual(clockReads, 2)
        try multiDatePickerActivate(.nextMonth, label: "Dates 1", in: host)
        try multiDatePickerActivate(.nextMonth, label: "Dates 2", in: host)
        try multiDatePickerActivate(.nextMonth, label: "Dates 2", in: host)
        order.reverse()
        host.reload()
        host.render()
        XCTAssertEqual(clockReads, 2)
        XCTAssertEqual(try multiDatePickerTitle(label: "Dates 1", in: host), "February 2024")
        XCTAssertEqual(try multiDatePickerTitle(label: "Dates 2", in: host), "March 2024")
        firstGeneration = 1
        host.reload()
        host.render()
        XCTAssertEqual(clockReads, 3)
        XCTAssertEqual(try multiDatePickerTitle(label: "Dates 1", in: host), "January 2024")
        XCTAssertEqual(try multiDatePickerTitle(label: "Dates 2", in: host), "March 2024")
        XCTAssertNil(host.coordinator.latestInstallationError)
    }

    func testReplacedActionsCannotReadOrWriteEvenWhenLogicalOwnerSurvives() async throws {
        let selection = MultiDatePickerTestSelection()
        var locale = Locale(identifier: "en_US_POSIX")
        let host = multiDatePickerHost {
            multiDatePickerView(selection: selection.binding, locale: locale)
        }
        defer { host.close() }
        host.render()
        let surface = try multiDatePickerSurface(in: host)
        let identity = surface.retainedViewIdentity
        let oldMetadata = surface.retainedPreferenceValues
        let oldDay = try XCTUnwrap(multiDatePickerNode(.day(multiDatePickerDate(2024, 2, 20)), in: host).onActivate)
        let oldMonth = try XCTUnwrap(multiDatePickerNode(.nextMonth, in: host).onActivate)
        locale = Locale(identifier: "fr_FR")
        host.reload()
        host.render()
        let current = try multiDatePickerSurface(in: host)
        XCTAssertEqual(current.retainedViewIdentity, identity)
        XCTAssertFalse(oldMetadata.isEmpty)
        for (key, marker) in oldMetadata {
            let adopted = try XCTUnwrap(current.retainedPreferenceValues[key])
            XCTAssertFalse((marker as AnyObject) === (adopted as AnyObject))
        }
        let reads = selection.reads
        var reloads = 0
        host.componentHost.onReloadCompleted = { reloads += 1 }
        oldDay()
        oldMonth()
        XCTAssertEqual(selection.reads, reads)
        XCTAssertTrue(selection.writes.isEmpty)
        XCTAssertEqual(reloads, 0)
        XCTAssertTrue(try multiDatePickerTitle(in: host).contains("février"))
        try multiDatePickerActivate(.day(multiDatePickerDate(2024, 2, 20)), in: host)
        XCTAssertEqual(selection.value, [DateComponents(year: 2024, month: 2, day: 20)])
        XCTAssertEqual(selection.writes.count, 1)
    }

    func testRemovedClosedAndReinsertedOccurrencesNeverReviveEscapedActions() async throws {
        let selection = MultiDatePickerTestSelection()
        var shown = true
        var clockReads = 0
        var builds = 0
        let host = multiDatePickerHost {
            builds += 1
            return shown
                ? multiDatePickerView(
                    selection: selection.binding,
                    now: {
                        clockReads += 1
                        return multiDatePickerDate(2024, 1, 15)
                    })
                : AnyView(Text("Removed"))
        }
        defer { host.close() }
        host.render()
        try multiDatePickerActivate(.nextMonth, in: host)
        let oldMonth = try XCTUnwrap(multiDatePickerNode(.nextMonth, in: host).onActivate)
        let oldDay = try XCTUnwrap(multiDatePickerNode(.day(multiDatePickerDate(2024, 2, 20)), in: host).onActivate)
        shown = false
        host.reload()
        let removedReads = selection.reads
        let removedBuilds = builds
        oldDay()
        oldMonth()
        XCTAssertEqual(selection.reads, removedReads)
        XCTAssertEqual(builds, removedBuilds)
        shown = true
        host.reload()
        host.render()
        XCTAssertEqual(clockReads, 2)
        XCTAssertEqual(try multiDatePickerTitle(in: host), "January 2024")
        let reinsertedReads = selection.reads
        oldDay()
        oldMonth()
        XCTAssertEqual(selection.reads, reinsertedReads)
        XCTAssertEqual(try multiDatePickerTitle(in: host), "January 2024")
        let currentDay = try XCTUnwrap(multiDatePickerNode(.day(multiDatePickerDate(2024, 1, 20)), in: host).onActivate)
        host.close()
        let closedReads = selection.reads
        let closedBuilds = builds
        currentDay()
        oldMonth()
        XCTAssertEqual(selection.reads, closedReads)
        XCTAssertEqual(builds, closedBuilds)
        XCTAssertTrue(selection.writes.isEmpty)
    }

    func testRejectedCandidatesAndHiddenAncestorsDoNotAdmitActions() async throws {
        let selection = MultiDatePickerTestSelection()
        var candidates: [ViewNode] = []
        var outerBuilds = 0
        var clockReads = 0
        let host = multiDatePickerHost(size: Size(width: 80, height: 500)) {
            outerBuilds += 1
            return AnyView(
                GeometryReader { _ in
                    ViewThatFits(in: .horizontal) {
                        MultiDatePickerCapturedCandidate(
                            content: multiDatePickerView(
                                selection: selection.binding,
                                now: {
                                    clockReads += 1
                                    return multiDatePickerDate(2024, 2, 15)
                                }), capture: { candidates.append($0) })
                        Text("Fallback").frame(width: 60, height: 20)
                    }
                })
        }
        defer { host.close() }
        host.render()
        XCTAssertTrue(multiDatePickerDescendants(host.runtime.root).contains { $0.text == "Fallback" })
        let candidate = try XCTUnwrap(candidates.first)
        let rejectedNext = try XCTUnwrap(
            multiDatePickerDescendants(candidate).first {
                $0.nodeTag == MultiDatePickerNodeID.nextMonth.nodeTag
            }?.onActivate)
        let rejectedDay = try XCTUnwrap(
            multiDatePickerDescendants(candidate).first {
                $0.nodeTag == MultiDatePickerNodeID.day(multiDatePickerDate(2024, 2, 20)).nodeTag
            }?.onActivate)
        let rejectedReads = selection.reads
        rejectedNext()
        rejectedDay()
        XCTAssertEqual(selection.reads, rejectedReads)
        let beforeResize = outerBuilds
        host.runtime.setRootSize(IntSize(width: 600, height: 500))
        host.render()
        XCTAssertEqual(outerBuilds, beforeResize)
        XCTAssertEqual(try multiDatePickerTitle(in: host), "February 2024")
        let surface = try multiDatePickerSurface(in: host)
        let liveNext = try XCTUnwrap(multiDatePickerNode(.nextMonth, in: host).onActivate)
        let liveDay = try XCTUnwrap(multiDatePickerNode(.day(multiDatePickerDate(2024, 2, 20)), in: host).onActivate)
        let hiddenAncestor = try XCTUnwrap(surface.parent)
        hiddenAncestor.isHidden = true
        host.render()
        let hiddenReads = selection.reads
        liveNext()
        liveDay()
        XCTAssertEqual(selection.reads, hiddenReads)
        XCTAssertTrue(selection.writes.isEmpty)
        hiddenAncestor.isHidden = false
        host.render()
        XCTAssertEqual(try multiDatePickerTitle(in: host), "February 2024")
        liveNext()
        host.render()
        XCTAssertEqual(try multiDatePickerTitle(in: host), "March 2024")
        let admittedReads = selection.reads
        rejectedDay()
        rejectedNext()
        XCTAssertEqual(selection.reads, admittedReads)
        XCTAssertEqual(try multiDatePickerTitle(in: host), "March 2024")

        let admittedClockReads = clockReads
        let admittedNext = try XCTUnwrap(multiDatePickerNode(.nextMonth, in: host).onActivate)
        let admittedDay = try XCTUnwrap(
            multiDatePickerNode(.day(multiDatePickerDate(2024, 3, 20)), in: host).onActivate)
        let beforeNarrowing = outerBuilds
        host.runtime.setRootSize(IntSize(width: 80, height: 500))
        host.render()
        let narrowed = multiDatePickerDescendants(host.runtime.root)
        XCTAssertTrue(narrowed.contains { $0.text == "Fallback" })
        XCTAssertFalse(narrowed.contains { $0.nodeTag == MultiDatePickerNodeID.surface.nodeTag })
        let narrowedReads = selection.reads
        admittedDay()
        admittedNext()
        XCTAssertEqual(selection.reads, narrowedReads)
        XCTAssertTrue(selection.writes.isEmpty)
        XCTAssertEqual(clockReads, admittedClockReads)
        XCTAssertEqual(outerBuilds, beforeNarrowing)
        host.runtime.setRootSize(IntSize(width: 600, height: 500))
        host.render()
        XCTAssertEqual(try multiDatePickerTitle(in: host), "March 2024")
        XCTAssertEqual(clockReads, admittedClockReads)
        let restoredReads = selection.reads
        admittedDay()
        admittedNext()
        XCTAssertEqual(selection.reads, restoredReads)
        try multiDatePickerActivate(.nextMonth, in: host)
        XCTAssertEqual(try multiDatePickerTitle(in: host), "April 2024")
    }

    func testGetterReentryRevokesThePendingActionAfterCloseBrowseOrConfigurationChange() async throws {
        for change in ["close", "month", "disabled", "calendar"] {
            let selection = MultiDatePickerTestSelection()
            var disabled = false
            var calendar = multiDatePickerCalendar()
            let host = multiDatePickerHost {
                AnyView(multiDatePickerView(selection: selection.binding, calendar: calendar).disabled(disabled))
            }
            defer {
                selection.onRead = nil
                host.close()
            }
            host.render()
            let oldDay = try XCTUnwrap(multiDatePickerNode(.day(multiDatePickerDate(2024, 2, 20)), in: host).onActivate)
            let oldMonth = try XCTUnwrap(multiDatePickerNode(.nextMonth, in: host).onActivate)
            selection.onRead = { [weak host] in
                selection.onRead = nil
                switch change {
                case "close":
                    host?.close()
                case "month":
                    oldMonth()
                case "disabled":
                    disabled = true
                    host?.reload()
                default:
                    calendar = multiDatePickerCalendar(.buddhist)
                    host?.reload()
                }
            }
            oldDay()
            host.render()
            XCTAssertTrue(selection.writes.isEmpty, "A getter publishing \(change) must revoke its old action")
            XCTAssertTrue(selection.value.isEmpty)
            XCTAssertEqual(host.isClosed, change == "close")
            if !host.isClosed {
                let title = try multiDatePickerTitle(in: host)
                if change == "month" {
                    XCTAssertEqual(title, "March 2024")
                } else if change == "calendar" {
                    XCTAssertTrue(title.contains("2567"))
                } else {
                    XCTAssertEqual(title, "February 2024")
                    XCTAssertNil(try multiDatePickerNode(.day(multiDatePickerDate(2024, 2, 20)), in: host).onActivate)
                }
            }
            let settledReads = selection.reads
            oldDay()
            oldMonth()
            XCTAssertEqual(selection.reads, settledReads)
            XCTAssertTrue(selection.writes.isEmpty)
            XCTAssertNil(host.coordinator.latestInstallationError)
        }
    }

    func testProjectedBindingSecondGetterCanRevokeTheBaseSetter() async throws {
        var document = MultiDatePickerBindingDocument(dates: [])
        var reads = 0
        var writes = 0
        var onRead: (@MainActor () -> Void)?
        let binding = Binding<MultiDatePickerBindingDocument>(
            get: {
                reads += 1
                onRead?()
                return document
            },
            set: {
                writes += 1
                document = $0
            })
        let host = multiDatePickerHost { multiDatePickerView(selection: binding.dates) }
        defer {
            onRead = nil
            host.close()
        }
        host.render()
        let action = try XCTUnwrap(multiDatePickerNode(.day(multiDatePickerDate(2024, 2, 20)), in: host).onActivate)
        let initialReads = reads
        var actionReads = 0
        onRead = { [weak host] in
            actionReads += 1
            if actionReads == 2 {
                onRead = nil
                host?.close()
            }
        }
        action()
        XCTAssertEqual(actionReads, 2, "The adapter consults the base value again while forwarding a write")
        XCTAssertEqual(reads, initialReads + 2)
        XCTAssertTrue(host.isClosed)
        XCTAssertEqual(writes, 0)
        XCTAssertTrue(document.dates.isEmpty)
    }

    func testSetterReloadOrClosureDoesNotCauseAnObsoleteSecondInvalidation() async throws {
        for closes in [false, true] {
            let selection = MultiDatePickerTestSelection()
            var builds = 0
            let host = multiDatePickerHost {
                builds += 1
                return multiDatePickerView(selection: selection.binding)
            }
            defer {
                selection.onWrite = nil
                host.close()
            }
            host.render()
            let action = try XCTUnwrap(multiDatePickerNode(.day(multiDatePickerDate(2024, 2, 20)), in: host).onActivate)
            let initialBuilds = builds
            selection.onWrite = { [weak host] in
                selection.onWrite = nil
                if closes {
                    host?.close()
                } else {
                    host?.reload()
                }
            }
            action()
            host.render()
            XCTAssertEqual(selection.writes, [[DateComponents(year: 2024, month: 2, day: 20)]])
            XCTAssertEqual(builds, initialBuilds + (closes ? 0 : 1))
            XCTAssertEqual(host.isClosed, closes)
            if !closes {
                XCTAssertTrue(
                    try multiDatePickerNode(.day(multiDatePickerDate(2024, 2, 20)), in: host)
                        .accessibilityTraits.contains(.isSelected))
            }
            XCTAssertNil(host.coordinator.latestInstallationError)
        }
    }
}
