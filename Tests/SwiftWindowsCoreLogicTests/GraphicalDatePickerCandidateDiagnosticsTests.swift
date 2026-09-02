import Foundation
import SwiftWindowsCore
@preconcurrency import XCTest

@testable import SwiftWindowsUI
@testable import WinSwiftUI

@MainActor
final class GraphicalDatePickerCandidateDiagnosticsTests: XCTestCase {
    func testRejectedCandidateAndRemovalDoNotKeepProvisionalMonthState() async throws {
        let initial = diagCalendarDate(2024, 1, 15)
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
                        DiagCalendarCandidate(
                            content: diagCalendarPicker("Start", selection: binding),
                            capture: { candidates.append($0) })
                        Text("Fallback").frame(width: 60, height: 20)
                    }
                })
        }
        defer { host.close() }
        host.render()
        XCTAssertTrue(diagCalendarDescendants(host.runtime.root).contains { $0.text == "Fallback" })
        XCTAssertFalse(
            diagCalendarDescendants(host.runtime.root).contains {
                $0.nodeTag == GraphicalDatePickerNodeID.surface.nodeTag
            })
        let rejected = try XCTUnwrap(candidates.first)
        let rejectedNext = try XCTUnwrap(
            diagCalendarDescendants(rejected).first {
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
        XCTAssertEqual(try diagCalendarTitle(label: "Start", host: host), "January 2024")
        print(
            "GraphicalCandidate beforeNext reads=\(reads) writes=\(writes)"
                + " outer=\(outerBuilds) geometry=\(geometryBuilds)")
        try activateDiagCalendar(
            .nextMonth, label: "Start", host: host,
            diagnosticContext: { (reads, writes, outerBuilds, geometryBuilds) })
        print(
            "GraphicalCandidate afterOriginalRender reads=\(reads) writes=\(writes)"
                + " outer=\(outerBuilds) geometry=\(geometryBuilds)")
        XCTAssertEqual(try diagCalendarTitle(label: "Start", host: host), "February 2024")
        let liveNext = try diagCalendarNode(.nextMonth, label: "Start", host: host)
        let liveDay = try diagCalendarNode(.day(diagCalendarDate(2024, 2, 20)), label: "Start", host: host)
        let oldSurface = try diagCalendarNode(.surface, label: "Start", host: host)
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
        let narrowedNodes = diagCalendarDescendants(host.runtime.root)
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
            try diagCalendarTitle(label: "Start", host: host), "February 2024",
            "A still-declared previously accepted candidate retains its logical browsing State")
        let hiddenOwner = try XCTUnwrap(
            diagCalendarDescendants(host.runtime.root).first {
                $0.accessibilityLabel == "Start"
            })
        let hiddenAction = try XCTUnwrap(diagCalendarNode(.nextMonth, label: "Start", host: host).onActivate)
        let hiddenSurface = try diagCalendarNode(.surface, label: "Start", host: host)
        let beforeHiding = outerBuilds
        hiddenOwner.isHidden = true
        host.render()
        XCTAssertTrue(diagCalendarDescendants(host.runtime.root).contains { $0 === hiddenSurface })
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
        XCTAssertEqual(try diagCalendarTitle(label: "Start", host: host), "January 2024")
        XCTAssertEqual(writes, 0)
        XCTAssertNil(host.coordinator.latestInstallationError)
    }
}

@MainActor
private func diagCalendar() -> Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    calendar.firstWeekday = 1
    return calendar
}

@MainActor
private func diagCalendarDate(_ year: Int, _ month: Int, _ day: Int) -> Date {
    diagCalendar().date(from: DateComponents(year: year, month: month, day: day))!
}

@MainActor
private func diagCalendarPicker(
    _ title: String, selection: Binding<Date>, calendar: Calendar? = nil,
    timeZone: TimeZone? = nil, locale: Locale = Locale(identifier: "en_US_POSIX")
) -> AnyView {
    AnyView(
        DatePicker(title, selection: selection, displayedComponents: .date)
            .datePickerStyle(.graphical)
            .environment(\.calendar, calendar ?? diagCalendar())
            .environment(\.timeZone, timeZone ?? TimeZone(secondsFromGMT: 0)!)
            .environment(\.locale, locale))
}

@MainActor
private func diagCalendarDescendants(_ node: ViewNode) -> [ViewNode] {
    [node] + node.children.flatMap(diagCalendarDescendants)
}

@MainActor
private func diagCalendarNode(
    _ identifier: GraphicalDatePickerNodeID, label: String, host: MountedOnChangeTestHost
) throws -> ViewNode {
    let owner = try XCTUnwrap(
        diagCalendarDescendants(host.runtime.root).first {
            $0.accessibilityLabel == label
        })
    return try XCTUnwrap(diagCalendarDescendants(owner).first { $0.nodeTag == identifier.nodeTag })
}

@MainActor
private func diagCalendarTitle(label: String, host: MountedOnChangeTestHost) throws -> String {
    try XCTUnwrap(diagCalendarNode(.monthTitle, label: label, host: host).text)
}

@MainActor
private func activateDiagCalendar(
    _ identifier: GraphicalDatePickerNodeID, label: String, host: MountedOnChangeTestHost,
    diagnosticContext: @MainActor () -> (reads: Int, writes: Int, outerBuilds: Int, geometryBuilds: Int)
) throws {
    let action = try XCTUnwrap(diagCalendarNode(identifier, label: label, host: host).onActivate)
    action()
    let counters = diagnosticContext()
    print(
        "GraphicalCandidate actionReturned reads=\(counters.reads) writes=\(counters.writes)"
            + " outer=\(counters.outerBuilds) geometry=\(counters.geometryBuilds)")
    host.render()
}

@MainActor
private struct DiagCalendarCandidate: View {
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
