import Foundation
import SwiftWindowsCore
@preconcurrency import XCTest

@testable import SwiftWindowsUI
@testable import WinSwiftUI

@MainActor
final class GraphicalDatePickerMountedTests: XCTestCase {
    func testMonthBrowsingSurvivesUnrelatedRebuild() async throws {
        let initial = mountedCalendarDate(2024, 1, 15)
        var selected = initial
        var unrelated = "Before"
        let binding = Binding<Date>(get: { selected }, set: { selected = $0 })
        let host = MountedOnChangeTestHost(size: Size(width: 700, height: 500)) {
            AnyView(
                VStack {
                    Text(unrelated)
                    mountedCalendarPicker("Start", selection: binding)
                })
        }
        defer { host.close() }
        try activateMountedCalendar(.nextMonth, label: "Start", host: host)
        XCTAssertEqual(try mountedCalendarTitle(label: "Start", host: host), "February 2024")

        unrelated = "After"
        host.reload()
        host.render()
        XCTAssertEqual(try mountedCalendarTitle(label: "Start", host: host), "February 2024")
        XCTAssertEqual(selected, initial)
        XCTAssertNil(host.coordinator.latestInstallationError)
    }

    func testSiblingPickersKeepIndependentBrowsedMonths() async throws {
        let initial = mountedCalendarDate(2024, 1, 15)
        var leftDate = initial
        var rightDate = initial
        let left = Binding<Date>(get: { leftDate }, set: { leftDate = $0 })
        let right = Binding<Date>(get: { rightDate }, set: { rightDate = $0 })
        let host = MountedOnChangeTestHost(size: Size(width: 900, height: 500)) {
            AnyView(
                HStack {
                    mountedCalendarPicker("Left", selection: left)
                    mountedCalendarPicker("Right", selection: right)
                })
        }
        defer { host.close() }
        try activateMountedCalendar(.nextMonth, label: "Left", host: host)
        try activateMountedCalendar(.nextMonth, label: "Left", host: host)
        try activateMountedCalendar(.previousMonth, label: "Right", host: host)

        XCTAssertEqual(try mountedCalendarTitle(label: "Left", host: host), "March 2024")
        XCTAssertEqual(try mountedCalendarTitle(label: "Right", host: host), "December 2023")
        XCTAssertEqual(leftDate, initial)
        XCTAssertEqual(rightDate, initial)
        XCTAssertNil(host.coordinator.latestInstallationError)
    }

    func testPrebuiltPickerInTwoHostsDoesNotShareBrowseState() async throws {
        let initial = mountedCalendarDate(2024, 1, 15)
        var selected = initial
        let prebuilt = mountedCalendarPicker(
            "Shared", selection: Binding<Date>(get: { selected }, set: { selected = $0 }))
        let first = MountedOnChangeTestHost(size: Size(width: 500, height: 500)) { prebuilt }
        let second = MountedOnChangeTestHost(size: Size(width: 500, height: 500)) { prebuilt }
        defer {
            first.close()
            second.close()
        }
        try activateMountedCalendar(.nextMonth, label: "Shared", host: first)
        XCTAssertEqual(try mountedCalendarTitle(label: "Shared", host: first), "February 2024")
        XCTAssertEqual(try mountedCalendarTitle(label: "Shared", host: second), "January 2024")
        try activateMountedCalendar(.previousMonth, label: "Shared", host: second)
        XCTAssertEqual(try mountedCalendarTitle(label: "Shared", host: first), "February 2024")
        XCTAssertEqual(try mountedCalendarTitle(label: "Shared", host: second), "December 2023")
        first.close()
        second.reload()
        XCTAssertEqual(try mountedCalendarTitle(label: "Shared", host: second), "December 2023")
        XCTAssertEqual(selected, initial)
        XCTAssertNil(second.coordinator.latestInstallationError)
    }

    func testBindingChangesRecenterAndNeverResurrectOldBrowseMonth() async throws {
        let initial = mountedCalendarDate(2024, 1, 15)
        var selected = initial
        var bindingWrites = 0
        let binding = Binding<Date>(
            get: { selected },
            set: {
                bindingWrites += 1
                selected = $0
            })
        let host = MountedOnChangeTestHost(size: Size(width: 500, height: 500)) {
            mountedCalendarPicker("Start", selection: binding)
        }
        defer { host.close() }
        try activateMountedCalendar(.nextMonth, label: "Start", host: host)
        XCTAssertEqual(try mountedCalendarTitle(label: "Start", host: host), "February 2024")

        selected = mountedCalendarDate(2024, 3, 10)
        host.reload()
        host.render()
        XCTAssertEqual(try mountedCalendarTitle(label: "Start", host: host), "March 2024")
        selected = initial
        host.reload()
        host.render()
        XCTAssertEqual(try mountedCalendarTitle(label: "Start", host: host), "January 2024")
        XCTAssertEqual(bindingWrites, 0)
        XCTAssertFalse(host.componentHost.isBuilding)
    }

    func testEnvironmentChangesRecenterWithoutBindingWrite() async throws {
        let selected = mountedCalendarDate(2024, 7, 1).addingTimeInterval(30 * 60)
        var calendar = mountedCalendar()
        var timeZone = TimeZone(secondsFromGMT: 0)!
        var locale = Locale(identifier: "en_US_POSIX")
        var writes = 0
        let binding = Binding<Date>(get: { selected }, set: { _ in writes += 1 })
        let host = MountedOnChangeTestHost(size: Size(width: 500, height: 500)) {
            mountedCalendarPicker(
                "Start", selection: binding, calendar: calendar, timeZone: timeZone, locale: locale)
        }
        defer { host.close() }
        try activateMountedCalendar(.nextMonth, label: "Start", host: host)
        XCTAssertEqual(try mountedCalendarTitle(label: "Start", host: host), "August 2024")

        timeZone = TimeZone(secondsFromGMT: -8 * 3_600)!
        host.reload()
        host.render()
        XCTAssertEqual(try mountedCalendarTitle(label: "Start", host: host), "June 2024")
        calendar = Calendar(identifier: .buddhist)
        calendar.firstWeekday = 2
        host.reload()
        host.render()
        let buddhistTitle = try mountedCalendarTitle(label: "Start", host: host)
        XCTAssertTrue(buddhistTitle.contains("June"), buddhistTitle)
        XCTAssertTrue(buddhistTitle.contains("2567"), buddhistTitle)
        let weekday = try mountedCalendarNode(.weekday(0), label: "Start", host: host)
        XCTAssertEqual(weekday.text, "Mon")

        try activateMountedCalendar(.nextMonth, label: "Start", host: host)
        locale = Locale(identifier: "fr_FR")
        host.reload()
        host.render()
        let frenchTitle = try mountedCalendarTitle(label: "Start", host: host)
        XCTAssertTrue(frenchTitle.lowercased().contains("juillet"), frenchTitle)
        XCTAssertTrue(frenchTitle.contains("2567"), frenchTitle)
        XCTAssertEqual(writes, 0)
        XCTAssertNil(host.coordinator.latestInstallationError)
    }

    func testKeyedReorderPreservesMonthAndExplicitIDReplacementStartsFresh() async throws {
        var order = [1, 2]
        var firstGeneration = 0
        let initial = mountedCalendarDate(2024, 1, 15)
        let host = MountedOnChangeTestHost(size: Size(width: 900, height: 500)) {
            AnyView(
                HStack {
                    ForEach(order, id: \.self) { identifier in
                        mountedCalendarPicker("Picker \(identifier)", selection: .constant(initial))
                            .id("\(identifier)-\(identifier == 1 ? firstGeneration : 0)")
                    }
                })
        }
        defer { host.close() }
        try activateMountedCalendar(.nextMonth, label: "Picker 1", host: host)
        try activateMountedCalendar(.nextMonth, label: "Picker 2", host: host)
        try activateMountedCalendar(.nextMonth, label: "Picker 2", host: host)
        order.reverse()
        host.reload()
        host.render()
        XCTAssertEqual(try mountedCalendarTitle(label: "Picker 1", host: host), "February 2024")
        XCTAssertEqual(try mountedCalendarTitle(label: "Picker 2", host: host), "March 2024")

        firstGeneration = 1
        host.reload()
        host.render()
        XCTAssertEqual(try mountedCalendarTitle(label: "Picker 1", host: host), "January 2024")
        XCTAssertEqual(try mountedCalendarTitle(label: "Picker 2", host: host), "March 2024")
        XCTAssertNil(host.coordinator.latestInstallationError)
    }

    func testRejectedCandidateAndRemovalDoNotKeepProvisionalMonthState() async throws {
        let initial = mountedCalendarDate(2024, 1, 15)
        var shown = true
        var candidates: [ViewNode] = []
        var outerBuilds = 0
        var geometryBuilds = 0
        var reads = 0
        var writes = 0
        let binding = Binding<Date>(
            get: {
                reads += 1
                return initial
            }, set: { _ in writes += 1 })
        let host = MountedOnChangeTestHost(size: Size(width: 80, height: 500)) {
            outerBuilds += 1
            guard shown else { return AnyView(Text("Removed")) }
            return AnyView(
                GeometryReader { _ in
                    let _ = { geometryBuilds += 1 }()
                    ViewThatFits(in: .horizontal) {
                        MountedCalendarCandidate(
                            content: mountedCalendarPicker("Start", selection: binding),
                            capture: { candidates.append($0) })
                        Text("Fallback").frame(width: 60, height: 20)
                    }
                })
        }
        defer { host.close() }
        host.render()
        XCTAssertTrue(mountedCalendarDescendants(host.runtime.root).contains { $0.text == "Fallback" })
        XCTAssertFalse(
            mountedCalendarDescendants(host.runtime.root).contains {
                $0.nodeTag == GraphicalDatePickerNodeID.surface.nodeTag
            })
        let rejected = try XCTUnwrap(candidates.first)
        let rejectedNext = try XCTUnwrap(
            mountedCalendarDescendants(rejected).first {
                $0.nodeTag == GraphicalDatePickerNodeID.nextMonth.nodeTag
            })
        let escapedRejected = try XCTUnwrap(rejectedNext.onActivate)
        let afterRejectedReads = reads
        escapedRejected()
        XCTAssertEqual(reads, afterRejectedReads)

        let beforeResizeOuter = outerBuilds
        let beforeResizeGeometry = geometryBuilds
        host.runtime.setRootSize(IntSize(width: 600, height: 500))
        host.render()
        XCTAssertEqual(outerBuilds, beforeResizeOuter, "Resize rebuilds only the existing GeometryReader subtree")
        XCTAssertGreaterThan(geometryBuilds, beforeResizeGeometry)
        XCTAssertEqual(try mountedCalendarTitle(label: "Start", host: host), "January 2024")
        try activateMountedCalendar(.nextMonth, label: "Start", host: host)
        XCTAssertEqual(try mountedCalendarTitle(label: "Start", host: host), "February 2024")
        let liveNext = try mountedCalendarNode(.nextMonth, label: "Start", host: host)
        let liveDay = try mountedCalendarNode(.day(mountedCalendarDate(2024, 2, 20)), label: "Start", host: host)
        let oldSurface = try mountedCalendarNode(.surface, label: "Start", host: host)
        let oldMetadata = oldSurface.retainedPreferenceValues
        XCTAssertFalse(oldMetadata.isEmpty, "The actual accepted surface carries its publication receipt")
        let escapedLive = try XCTUnwrap(liveNext.onActivate)
        let escapedDay = try XCTUnwrap(liveDay.onActivate)

        // ViewThatFits returns only its selected candidate. GeometryReader can
        // reconstruct that choice on resize without re-running the outer body.
        let beforeNarrowing = outerBuilds
        host.runtime.setRootSize(IntSize(width: 80, height: 500))
        host.render()
        XCTAssertEqual(outerBuilds, beforeNarrowing)
        let narrowedNodes = mountedCalendarDescendants(host.runtime.root)
        XCTAssertTrue(narrowedNodes.contains { $0.text == "Fallback" })
        XCTAssertFalse(narrowedNodes.contains { $0.nodeTag == GraphicalDatePickerNodeID.surface.nodeTag })
        for (key, marker) in oldMetadata {
            XCTAssertFalse(
                narrowedNodes.contains { node in
                    guard let current = node.retainedPreferenceValues[key] else { return false }
                    return (current as AnyObject) === (marker as AnyObject)
                })
        }
        let afterNarrowingReads = reads
        escapedLive()
        escapedDay()
        escapedRejected()
        XCTAssertEqual(reads, afterNarrowingReads, "Inactive callbacks cannot even consult the binding")
        XCTAssertEqual(writes, 0)
        XCTAssertEqual(outerBuilds, beforeNarrowing)

        host.runtime.setRootSize(IntSize(width: 600, height: 500))
        host.render()
        XCTAssertEqual(
            try mountedCalendarTitle(label: "Start", host: host), "February 2024",
            "A still-declared previously accepted candidate retains its logical browsing State")
        let hiddenOwner = try XCTUnwrap(
            mountedCalendarDescendants(host.runtime.root).first {
                $0.accessibilityLabel == "Start"
            })
        let hiddenAction = try XCTUnwrap(mountedCalendarNode(.nextMonth, label: "Start", host: host).onActivate)
        let hiddenSurface = try mountedCalendarNode(.surface, label: "Start", host: host)
        let beforeHiding = outerBuilds
        hiddenOwner.isHidden = true
        host.render()
        XCTAssertTrue(mountedCalendarDescendants(host.runtime.root).contains { $0 === hiddenSurface })
        let hiddenReads = reads
        hiddenAction()
        XCTAssertEqual(reads, hiddenReads, "Physical presence under an inactive hidden ancestor is insufficient")
        XCTAssertEqual(outerBuilds, beforeHiding)
        hiddenOwner.isHidden = false
        host.render()

        shown = false
        host.reload()
        escapedLive()
        escapedDay()
        shown = true
        host.reload()
        host.render()
        XCTAssertEqual(try mountedCalendarTitle(label: "Start", host: host), "January 2024")
        XCTAssertEqual(writes, 0)
        XCTAssertNil(host.coordinator.latestInstallationError)
    }

    func testRemovedPickerActionsDoNotMutateDateOrRequestRebuild() async throws {
        let initial = mountedCalendarDate(2024, 1, 15)
        var selected = initial
        var shown = true
        var builds = 0
        var reads = 0
        var writes = 0
        var onRead: (() -> Void)?
        let binding = Binding<Date>(
            get: {
                reads += 1
                onRead?()
                return selected
            },
            set: {
                writes += 1
                selected = $0
            })
        let host = MountedOnChangeTestHost(size: Size(width: 500, height: 500)) {
            builds += 1
            return shown
                ? mountedCalendarPicker("Start", selection: binding)
                : AnyView(Text("Removed"))
        }
        defer {
            onRead = nil
            host.close()
        }
        host.render()
        let selectedAction = try XCTUnwrap(
            mountedCalendarNode(.day(initial), label: "Start", host: host).onActivate)
        let beforeStableQueries = builds
        let beforeStableReads = reads
        for _ in 0..<3 {
            XCTAssertNotNil(AccessibilityProjection.project(runtime: host.runtime))
            host.render()
            selectedAction()
        }
        XCTAssertEqual(writes, 0)
        XCTAssertEqual(builds, beforeStableQueries, "Unchanged queries and a no-op selection do not invalidate")
        XCTAssertGreaterThanOrEqual(reads, beforeStableReads + 3, "The live no-op actions still consult their binding")
        let day = try mountedCalendarNode(.day(mountedCalendarDate(2024, 1, 20)), label: "Start", host: host)
        let month = try mountedCalendarNode(.nextMonth, label: "Start", host: host)
        let escapedDay = try XCTUnwrap(day.onActivate)
        let escapedMonth = try XCTUnwrap(month.onActivate)
        shown = false
        host.reload()
        let afterRemoval = builds
        let afterRemovalReads = reads
        escapedDay()
        escapedMonth()
        XCTAssertEqual(writes, 0)
        XCTAssertEqual(selected, initial)
        XCTAssertEqual(builds, afterRemoval)
        XCTAssertEqual(reads, afterRemovalReads)

        shown = true
        host.reload()
        let replacement = try mountedCalendarNode(
            .day(mountedCalendarDate(2024, 1, 20)), label: "Start", host: host)
        let replacementAction = try XCTUnwrap(replacement.onActivate)
        onRead = { [weak host] in
            onRead = nil
            host?.close()
        }
        replacementAction()
        XCTAssertTrue(host.isClosed)
        XCTAssertEqual(writes, 0, "A binding getter that removes the occurrence revokes the following write")
        XCTAssertEqual(selected, initial)

        // Replacing the accepted configuration must also revoke the old
        // callback when the logical picker itself survives the getter.
        for change in ["month", "range", "disabled"] {
            var value = initial
            var upper = mountedCalendarDate(2024, 3, 31)
            var disabled = false
            var caseBuilds = 0
            var caseReads = 0
            var caseWrites = 0
            var duringRead: (() -> Void)?
            let caseBinding = Binding<Date>(
                get: {
                    caseReads += 1
                    duringRead?()
                    return value
                },
                set: {
                    caseWrites += 1
                    value = $0
                })
            let caseHost = MountedOnChangeTestHost(size: Size(width: 500, height: 500)) {
                caseBuilds += 1
                return AnyView(
                    DatePicker(
                        "Surviving picker", selection: caseBinding,
                        in: mountedCalendarDate(2024, 1, 1)...upper, displayedComponents: .date
                    )
                    .datePickerStyle(.graphical)
                    .disabled(disabled)
                    .environment(\.calendar, mountedCalendar())
                    .environment(\.timeZone, TimeZone(secondsFromGMT: 0)!)
                    .environment(\.locale, Locale(identifier: "en_US_POSIX")))
            }
            defer {
                duringRead = nil
                caseHost.close()
            }
            caseHost.render()
            let oldSurface = try mountedCalendarNode(.surface, label: "Surviving picker", host: caseHost)
            let oldIdentity = oldSurface.retainedViewIdentity
            let oldMetadata = oldSurface.retainedPreferenceValues
            XCTAssertFalse(oldMetadata.isEmpty)
            let oldDay = try XCTUnwrap(
                mountedCalendarNode(
                    .day(mountedCalendarDate(2024, 1, 20)), label: "Surviving picker", host: caseHost
                ).onActivate)
            let oldNext = try XCTUnwrap(
                mountedCalendarNode(.nextMonth, label: "Surviving picker", host: caseHost).onActivate)
            duringRead = { [weak caseHost] in
                duringRead = nil
                switch change {
                case "month":
                    oldNext()
                case "range":
                    upper = mountedCalendarDate(2024, 1, 19)
                    caseHost?.reload()
                default:
                    disabled = true
                    caseHost?.reload()
                }
            }
            oldDay()
            caseHost.render()
            XCTAssertFalse(caseHost.isClosed)
            XCTAssertEqual(caseWrites, 0, "A getter changing \(change) revokes the preceding day action")
            XCTAssertEqual(value, initial)
            let currentSurface = try mountedCalendarNode(.surface, label: "Surviving picker", host: caseHost)
            XCTAssertEqual(currentSurface.retainedViewIdentity, oldIdentity, "The same logical picker survives")
            for (key, marker) in oldMetadata {
                let current = try XCTUnwrap(currentSurface.retainedPreferenceValues[key])
                XCTAssertFalse((current as AnyObject) === (marker as AnyObject))
            }
            if change == "month" {
                XCTAssertEqual(try mountedCalendarTitle(label: "Surviving picker", host: caseHost), "February 2024")
            } else {
                XCTAssertEqual(try mountedCalendarTitle(label: "Surviving picker", host: caseHost), "January 2024")
                let blockedDay = try mountedCalendarNode(
                    .day(mountedCalendarDate(2024, 1, 20)), label: "Surviving picker", host: caseHost)
                XCTAssertNil(blockedDay.onActivate)
                XCTAssertFalse(blockedDay.isFocusable)
            }
            let settledReads = caseReads
            let settledBuilds = caseBuilds
            oldDay()
            oldNext()
            XCTAssertEqual(caseReads, settledReads, "A superseded \(change) callback cannot reread the binding")
            XCTAssertEqual(caseBuilds, settledBuilds)
            XCTAssertEqual(caseWrites, 0)
            XCTAssertNil(caseHost.coordinator.latestInstallationError)
        }

        // A setter may synchronously publish the accepted new date. The
        // retired receipt must not request a redundant second rebuild.
        var setterValue = initial
        var setterWrites = 0
        var setterBuilds = 0
        var afterWrite: (() -> Void)?
        let setterBinding = Binding<Date>(
            get: { setterValue },
            set: {
                setterWrites += 1
                setterValue = $0
                afterWrite?()
            })
        let setterHost = MountedOnChangeTestHost(size: Size(width: 500, height: 500)) {
            setterBuilds += 1
            return mountedCalendarPicker("Setter picker", selection: setterBinding)
        }
        defer {
            afterWrite = nil
            setterHost.close()
        }
        setterHost.render()
        let setterAction = try XCTUnwrap(
            mountedCalendarNode(
                .day(mountedCalendarDate(2024, 1, 20)), label: "Setter picker", host: setterHost
            ).onActivate)
        let beforeSetter = setterBuilds
        afterWrite = { [weak setterHost] in
            afterWrite = nil
            setterHost?.reload()
        }
        setterAction()
        setterHost.render()
        XCTAssertEqual(setterWrites, 1)
        XCTAssertEqual(setterValue, mountedCalendarDate(2024, 1, 20))
        XCTAssertEqual(setterBuilds, beforeSetter + 1)
        XCTAssertTrue(
            try mountedCalendarNode(
                .day(mountedCalendarDate(2024, 1, 20)), label: "Setter picker", host: setterHost
            )
            .accessibilityTraits.contains(.isSelected))
        XCTAssertNil(setterHost.coordinator.latestInstallationError)
    }
}

@MainActor
private func mountedCalendar() -> Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    calendar.firstWeekday = 1
    return calendar
}

@MainActor
private func mountedCalendarDate(_ year: Int, _ month: Int, _ day: Int) -> Date {
    mountedCalendar().date(from: DateComponents(year: year, month: month, day: day))!
}

@MainActor
private func mountedCalendarPicker(
    _ title: String, selection: Binding<Date>, calendar: Calendar? = nil,
    timeZone: TimeZone? = nil, locale: Locale = Locale(identifier: "en_US_POSIX")
) -> AnyView {
    AnyView(
        DatePicker(title, selection: selection, displayedComponents: .date)
            .datePickerStyle(.graphical)
            .environment(\.calendar, calendar ?? mountedCalendar())
            .environment(\.timeZone, timeZone ?? TimeZone(secondsFromGMT: 0)!)
            .environment(\.locale, locale))
}

@MainActor
private func mountedCalendarDescendants(_ node: ViewNode) -> [ViewNode] {
    [node] + node.children.flatMap(mountedCalendarDescendants)
}

@MainActor
private func mountedCalendarNode(
    _ identifier: GraphicalDatePickerNodeID, label: String, host: MountedOnChangeTestHost
) throws -> ViewNode {
    let owner = try XCTUnwrap(
        mountedCalendarDescendants(host.runtime.root).first {
            $0.accessibilityLabel == label
        })
    return try XCTUnwrap(mountedCalendarDescendants(owner).first { $0.nodeTag == identifier.nodeTag })
}

@MainActor
private func mountedCalendarTitle(label: String, host: MountedOnChangeTestHost) throws -> String {
    try XCTUnwrap(mountedCalendarNode(.monthTitle, label: label, host: host).text)
}

@MainActor
private func activateMountedCalendar(
    _ identifier: GraphicalDatePickerNodeID, label: String, host: MountedOnChangeTestHost
) throws {
    let action = try XCTUnwrap(mountedCalendarNode(identifier, label: label, host: host).onActivate)
    action()
    host.render()
}

@MainActor
private struct MountedCalendarCandidate: View {
    typealias Body = Never
    let content: AnyView
    let capture: (ViewNode) -> Void

    var body: Never { fatalError("The test candidate is a retained primitive") }

    func makeComponent(context: ViewBuildContext) -> Component {
        let component = makeViewComponent(content, context: context.withViewIdentityRole(.content))
        return Component { runtime in
            let node = component.makeNode(runtime: runtime)
            capture(node)
            return node
        }
    }
}
