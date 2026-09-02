import Foundation
import SwiftWindowsCore
@preconcurrency import XCTest

@testable import SwiftWindowsUI
@testable import WinSwiftUI

func multiDatePickerCalendar(
    _ identifier: Calendar.Identifier = .gregorian,
    firstWeekday: Int = 1,
    timeZone: TimeZone = TimeZone(secondsFromGMT: 0)!
) -> Calendar {
    var calendar = Calendar(identifier: identifier)
    calendar.timeZone = timeZone
    calendar.firstWeekday = firstWeekday
    return calendar
}

func multiDatePickerDate(_ year: Int, _ month: Int, _ day: Int, hour: Int = 0, minute: Int = 0) -> Date {
    multiDatePickerCalendar().date(
        from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
}

func multiDatePickerDay(
    _ date: Date, calendar: Calendar = multiDatePickerCalendar(),
    file: StaticString = #filePath, line: UInt = #line
) throws -> DatePickerCalendarModel.Day {
    let model = try XCTUnwrap(
        DatePickerCalendarModel(
            containing: date, calendar: calendar, timeZone: calendar.timeZone,
            locale: Locale(identifier: "en_US_POSIX")),
        file: file, line: line)
    return try XCTUnwrap(
        model.cells.compactMap { $0 }.first { date >= $0.start && date < $0.end }, file: file, line: line)
}

@MainActor
final class MultiDatePickerTestSelection {
    var value: Set<DateComponents>
    var writes: [Set<DateComponents>] = []
    var reads = 0
    var onRead: (@MainActor () -> Void)?
    var onWrite: (@MainActor () -> Void)?

    init(_ value: Set<DateComponents> = []) {
        self.value = value
    }

    var binding: Binding<Set<DateComponents>> {
        Binding(
            get: {
                self.reads += 1
                self.onRead?()
                return self.value
            },
            set: {
                self.value = $0
                self.writes.append($0)
                self.onWrite?()
            })
    }
}

@MainActor
func multiDatePickerView(
    _ label: String = "Available dates",
    selection: Binding<Set<DateComponents>>,
    now: @escaping @MainActor () -> Date = { multiDatePickerDate(2024, 2, 15) },
    calendar: Calendar = multiDatePickerCalendar(),
    timeZone: TimeZone = TimeZone(secondsFromGMT: 0)!,
    locale: Locale = Locale(identifier: "en_US_POSIX"),
    direction: LayoutDirection = .leftToRight,
    controlSize: ControlSize = .regular
) -> AnyView {
    AnyView(
        MultiDatePickerContent(selection: selection, label: [AnyView(Text(label))], now: now)
            .environment(\.calendar, calendar)
            .environment(\.timeZone, timeZone)
            .environment(\.locale, locale)
            .environment(\.layoutDirection, direction)
            .environment(\.colorScheme, .light)
            .controlSize(controlSize))
}

@MainActor
func multiDatePickerHost(
    size: Size = Size(width: 420, height: 440),
    content: @escaping @MainActor () -> AnyView
) -> MountedOnChangeTestHost {
    MountedOnChangeTestHost(size: size, content: content)
}

@MainActor
func multiDatePickerDescendants(_ root: ViewNode) -> [ViewNode] {
    var result = [root]
    var index = 0
    while index < result.count {
        result.append(contentsOf: result[index].children)
        index += 1
    }
    return result
}

@MainActor
func multiDatePickerSurface(
    _ label: String = "Available dates", in host: MountedOnChangeTestHost,
    file: StaticString = #filePath, line: UInt = #line
) throws -> ViewNode {
    try XCTUnwrap(
        multiDatePickerDescendants(host.runtime.root).first {
            $0.nodeTag == MultiDatePickerNodeID.surface.nodeTag && $0.accessibilityLabel == label
        }, "Missing calendar surface for \(label)", file: file, line: line)
}

@MainActor
func multiDatePickerNode(
    _ identifier: MultiDatePickerNodeID,
    label: String = "Available dates", in host: MountedOnChangeTestHost,
    file: StaticString = #filePath, line: UInt = #line
) throws -> ViewNode {
    let surface = try multiDatePickerSurface(label, in: host, file: file, line: line)
    return try XCTUnwrap(
        multiDatePickerDescendants(surface).first { $0.nodeTag == identifier.nodeTag },
        "Missing calendar node \(identifier)", file: file, line: line)
}

@MainActor
func multiDatePickerTitle(
    label: String = "Available dates", in host: MountedOnChangeTestHost,
    file: StaticString = #filePath, line: UInt = #line
) throws -> String {
    try XCTUnwrap(
        multiDatePickerNode(.monthTitle, label: label, in: host, file: file, line: line).text, file: file, line: line)
}

@MainActor
func multiDatePickerActivate(
    _ identifier: MultiDatePickerNodeID,
    label: String = "Available dates", in host: MountedOnChangeTestHost,
    file: StaticString = #filePath, line: UInt = #line
) throws {
    let action = try XCTUnwrap(
        multiDatePickerNode(identifier, label: label, in: host, file: file, line: line).onActivate,
        file: file, line: line)
    action()
    host.render()
}

@MainActor
func multiDatePickerFrame(_ node: ViewNode) -> Rect {
    var origin = node.resolvedFrame.origin
    var parent = node.parent
    while let ancestor = parent {
        origin.x += ancestor.resolvedFrame.origin.x
        origin.y += ancestor.resolvedFrame.origin.y
        parent = ancestor.parent
    }
    return Rect(origin: origin, size: node.resolvedFrame.size)
}

@MainActor
func multiDatePickerClick(_ node: ViewNode, in host: MountedOnChangeTestHost) {
    let frame = multiDatePickerFrame(node)
    XCTAssertGreaterThan(frame.width, 0)
    XCTAssertGreaterThan(frame.height, 0)
    let point = Point(x: frame.midX, y: frame.midY)
    host.runtime.pointerMoved(to: point)
    host.runtime.pointerDown(at: point)
    host.runtime.pointerUp(at: point)
    host.render()
}

@MainActor
func multiDatePickerFocus(
    _ identifier: MultiDatePickerNodeID, in host: MountedOnChangeTestHost,
    file: StaticString = #filePath, line: UInt = #line
) -> Bool {
    let stops = multiDatePickerDescendants(host.runtime.root).filter(\.isFocusable).count
    for _ in 0...stops {
        host.runtime.keyDown(KeyboardEvent(keyCode: KeyboardKey.tab.rawValue))
        if host.runtime.focusedNode?.nodeTag == identifier.nodeTag { return true }
    }
    XCTFail("Tab could not reach \(identifier)", file: file, line: line)
    return false
}

@MainActor
func multiDatePickerAssertContained(
    _ bounds: Rect, in container: Rect, file: StaticString = #filePath, line: UInt = #line
) {
    XCTAssertGreaterThanOrEqual(bounds.minX, container.minX - 0.51, file: file, line: line)
    XCTAssertGreaterThanOrEqual(bounds.minY, container.minY - 0.51, file: file, line: line)
    XCTAssertLessThanOrEqual(bounds.maxX, container.maxX + 0.51, file: file, line: line)
    XCTAssertLessThanOrEqual(bounds.maxY, container.maxY + 0.51, file: file, line: line)
}

@MainActor
struct MultiDatePickerCapturedCandidate: View {
    typealias Body = Never
    let content: AnyView
    let capture: @MainActor (ViewNode) -> Void

    var body: Never { fatalError("A test captures the candidate construction node") }

    func makeComponent(context: ViewBuildContext) -> Component {
        let component = makeViewComponent(content, context: context)
        return Component { runtime in
            let node = component.makeNode(runtime: runtime)
            capture(node)
            return node
        }
    }
}
