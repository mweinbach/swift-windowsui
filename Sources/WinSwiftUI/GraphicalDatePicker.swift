import Foundation
import SwiftWindowsCore
import SwiftWindowsUI

/// Calendar arithmetic is separate from retained interaction. This model uses
/// half-open civil days even though Foundation's DateInterval includes its end.
struct DatePickerCalendarModel {
    struct Day: Equatable {
        let start: Date
        let end: Date
        let number: Int
        let label: String
        let accessibilityLabel: String
    }

    let month: DateInterval
    let title: String
    let weekdaySymbols: [String]
    let cells: [Day?]
    let calendar: Calendar
    private let locale: Locale

    var rowCount: Int { cells.count / 7 }

    init?(containing date: Date, calendar source: Calendar, timeZone: TimeZone, locale: Locale) {
        guard date.timeIntervalSinceReferenceDate.isFinite else { return nil }
        var calendar = source
        calendar.timeZone = timeZone
        guard (1...7).contains(calendar.firstWeekday),
            let month = calendar.dateInterval(of: .month, for: date),
            Self.isFiniteAdvancing(month), date >= month.start, date < month.end
        else { return nil }

        // Locale changes the symbols, not the inherited first-weekday override.
        var symbolCalendar = calendar
        symbolCalendar.locale = locale
        let symbols = symbolCalendar.shortStandaloneWeekdaySymbols
        guard symbols.count == 7 else { return nil }
        let firstColumn = calendar.firstWeekday - 1
        weekdaySymbols = (0..<7).map { symbols[(firstColumn + $0) % 7] }

        let formatter = Self.formatter(calendar: calendar, locale: locale)
        formatter.setLocalizedDateFormatFromTemplate("yMMMM")
        title = formatter.string(from: month.start)
        let dayFormatter = Self.formatter(calendar: calendar, locale: locale)
        dayFormatter.setLocalizedDateFormatFromTemplate("d")
        let accessibilityFormatter = Self.formatter(calendar: calendar, locale: locale)
        accessibilityFormatter.dateStyle = .full
        accessibilityFormatter.timeStyle = .none

        var cells: [Day?] = []
        var cursor = month.start
        var dayCount = 0
        while cursor < month.end {
            guard dayCount < 42,
                let interval = calendar.dateInterval(of: .day, for: cursor),
                Self.isFiniteAdvancing(interval), interval.start == cursor, interval.end <= month.end
            else { return nil }
            let weekday = calendar.component(.weekday, from: cursor)
            let number = calendar.component(.day, from: cursor)
            guard (1...7).contains(weekday), number > 0 else { return nil }
            let column = (weekday - calendar.firstWeekday + 7) % 7
            let padding = (column - cells.count % 7 + 7) % 7
            guard cells.count + padding < 42 else { return nil }
            cells.append(contentsOf: Array(repeating: nil, count: padding))
            cells.append(
                Day(
                    start: interval.start, end: interval.end, number: number,
                    label: dayFormatter.string(from: interval.start),
                    accessibilityLabel: accessibilityFormatter.string(from: interval.start)))
            cursor = interval.end
            dayCount += 1
        }
        guard cursor == month.end, !cells.isEmpty else { return nil }
        // Short epagomenal months (for example Coptic month 13) are valid
        // calendars too. Four rows is a display minimum, not a minimum month.
        let cellCount = max(28, ((cells.count + 6) / 7) * 7)
        guard cellCount <= 42 else { return nil }
        cells.append(contentsOf: Array(repeating: nil, count: cellCount - cells.count))
        self.month = month
        self.cells = cells
        self.calendar = calendar
        self.locale = locale
    }

    func adjacentMonth(direction: Int, range: DatePickerRange) -> Date? {
        guard direction == -1 || direction == 1, Self.hasFiniteBounds(range),
            let proposed = calendar.date(byAdding: .month, value: direction, to: month.start),
            proposed.timeIntervalSinceReferenceDate.isFinite,
            let candidate = DatePickerCalendarModel(
                containing: proposed, calendar: calendar, timeZone: calendar.timeZone, locale: locale)
        else { return nil }
        if direction < 0 {
            guard candidate.month.start < month.start, candidate.month.end == month.start else { return nil }
            if let lower = range.lowerBound, candidate.month.end <= lower { return nil }
        } else {
            guard candidate.month.start == month.end, candidate.month.end > month.end else { return nil }
            if let upper = range.upperBound {
                guard range.includesUpperBound ? candidate.month.start <= upper : candidate.month.start < upper
                else { return nil }
            }
        }
        return candidate.month.start
    }

    func isEnabled(_ day: Day, range: DatePickerRange) -> Bool {
        allowedInstants(in: day, range: range) != nil
    }

    func selectedDate(for day: Day, preserving current: Date, range: DatePickerRange) -> Date? {
        guard current.timeIntervalSinceReferenceDate.isFinite,
            let allowed = allowedInstants(in: day, range: range),
            let currentDay = calendar.dateInterval(of: .day, for: current),
            Self.isFiniteAdvancing(currentDay), current >= currentDay.start, current < currentDay.end
        else { return nil }
        if current >= allowed.lowerBound, current <= allowed.upperBound { return current }

        let time = calendar.dateComponents([.hour, .minute, .second], from: current)
        guard let hour = time.hour, let minute = time.minute, let second = time.second,
            (0...23).contains(hour), (0...59).contains(minute), (0...59).contains(second),
            let beforeDay = Self.predecessor(of: day.start)
        else { return nil }
        let matching = DateComponents(hour: hour, minute: minute, second: second, nanosecond: 0)
        // date(bySettingHour:...) can downgrade this matching policy to
        // .nextTime. Use the matching API so a missing 02:37 resolves to 03:37.
        guard
            let wholeSecond = calendar.nextDate(
                after: beforeDay, matching: matching,
                matchingPolicy: .nextTimePreservingSmallerComponents,
                repeatedTimePolicy: .first, direction: .forward),
            wholeSecond.timeIntervalSinceReferenceDate.isFinite,
            wholeSecond >= day.start, wholeSecond < day.end
        else { return nil }
        // Date can represent fractions smaller than one nanosecond near its
        // reference epoch. Integer nanosecond components would quantize them.
        let reference = current.timeIntervalSinceReferenceDate
        let fraction = reference - reference.rounded(.down)
        let proposed = wholeSecond.addingTimeInterval(fraction)
        guard proposed.timeIntervalSinceReferenceDate.isFinite else { return nil }
        // A fine fraction near the reference epoch can round up to the next
        // midnight when applied far from that epoch. Clamp the representable
        // result after validating the matched whole second belongs to this day.
        let result = min(max(proposed, allowed.lowerBound), allowed.upperBound)
        guard result.timeIntervalSinceReferenceDate.isFinite, result >= day.start, result < day.end,
            range.contains(result)
        else { return nil }
        return result
    }

    private func allowedInstants(in day: Day, range: DatePickerRange) -> ClosedRange<Date>? {
        guard Self.hasFiniteBounds(range), day.start.timeIntervalSinceReferenceDate.isFinite,
            day.end.timeIntervalSinceReferenceDate.isFinite, day.start < day.end,
            day.start >= month.start, day.end <= month.end,
            let last = Self.predecessor(of: day.end)
        else { return nil }
        var lower = day.start
        var upper = last
        if let bound = range.lowerBound { lower = max(lower, bound) }
        if let bound = range.upperBound {
            if range.includesUpperBound {
                upper = min(upper, bound)
            } else {
                guard let previous = Self.predecessor(of: bound) else { return nil }
                upper = min(upper, previous)
            }
        }
        guard lower <= upper, lower >= day.start, upper < day.end,
            range.contains(lower), range.contains(upper)
        else { return nil }
        return lower...upper
    }

    private static func predecessor(of date: Date) -> Date? {
        let reference = date.timeIntervalSinceReferenceDate
        guard reference.isFinite else { return nil }
        let previous = reference.nextDown
        guard previous.isFinite else { return nil }
        let result = Date(timeIntervalSinceReferenceDate: previous)
        guard result < date, result.timeIntervalSinceReferenceDate.isFinite else { return nil }
        return result
    }

    private static func hasFiniteBounds(_ range: DatePickerRange) -> Bool {
        (range.lowerBound?.timeIntervalSinceReferenceDate.isFinite ?? true)
            && (range.upperBound?.timeIntervalSinceReferenceDate.isFinite ?? true)
    }

    private static func isFiniteAdvancing(_ interval: DateInterval) -> Bool {
        interval.start.timeIntervalSinceReferenceDate.isFinite
            && interval.end.timeIntervalSinceReferenceDate.isFinite
            && interval.duration.isFinite && interval.start < interval.end
    }

    private static func formatter(calendar: Calendar, locale: Locale) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        return formatter
    }
}

/// Tags aid inspection; typed identities, scoped to the installed occurrence,
/// determine retention. They never serve as a global picker registry.
enum GraphicalDatePickerNodeID: Hashable {
    case surface, monthTitle, previousMonth, nextMonth, weekdays, value, grid
    case weekday(Int)
    case week(Int)
    case day(Date)
    case padding(Int)

    var nodeTag: String {
        let suffix: String
        switch self {
        case .surface: suffix = "surface"
        case .monthTitle: suffix = "monthTitle"
        case .previousMonth: suffix = "previousMonth"
        case .nextMonth: suffix = "nextMonth"
        case .weekdays: suffix = "weekdays"
        case .value: suffix = "value"
        case .grid: suffix = "grid"
        case .weekday(let index): suffix = "weekday.\(index)"
        case .week(let index): suffix = "week.\(index)"
        case .padding(let index): suffix = "padding.\(index)"
        case .day(let date):
            suffix = "day.\(String(date.timeIntervalSinceReferenceDate.bitPattern, radix: 16))"
        }
        return "WinSwiftUI.DatePicker.calendar.\(suffix)"
    }
}

private struct GraphicalDatePickerBasis: Equatable {
    let selection: Date
    let calendar: Calendar
}

private struct GraphicalDatePickerBrowse {
    let basis: GraphicalDatePickerBasis
    let month: Date
}

private enum GraphicalDatePickerAdmissionMarker {}

/// ComponentHost copies retained preference metadata onto the actual adopted
/// surface. An escaped action owns only this receipt, never a construction node.
@MainActor
private final class GraphicalDatePickerAdmission {
    private weak var runtime: RetainedViewRuntime?
    private weak var owner: StateMountOwner?
    private let isManaged: Bool

    init(runtime: RetainedViewRuntime, context: ViewBuildContext) {
        self.runtime = runtime
        owner = context.viewIdentity.installedOwner
        isManaged = context.stateMountCoordinator != nil
    }

    func mark(_ surface: ViewNode) {
        surface.retainedPreferenceValues[ObjectIdentifier(GraphicalDatePickerAdmissionMarker.self)] = self
    }

    var isCurrent: Bool {
        guard let runtime, runtime.presentationActionsAreAvailable,
            !isManaged || owner?.isLive == true, runtime.root.parent == nil
        else { return false }
        var pending = [runtime.root]
        var visited: Set<ObjectIdentifier> = []
        while let node = pending.popLast() {
            guard visited.insert(ObjectIdentifier(node)).inserted else { return false }
            guard !node.isHidden, !node.isRemovalOverlay else { continue }
            if (node.retainedPreferenceValues[ObjectIdentifier(GraphicalDatePickerAdmissionMarker.self)]
                as? GraphicalDatePickerAdmission) === self
            {
                return runtime.presentationActionsAreAvailable && (!isManaged || owner?.isLive == true)
            }
            for child in node.children {
                guard child.parent === node else { return false }
                pending.append(child)
            }
        }
        return false
    }
}

@MainActor
struct GraphicalDatePickerContent: View {
    let selection: Binding<Date>
    let range: DatePickerRange
    let displayedComponents: DatePickerComponents
    @Environment(\.calendar) private var calendar
    @Environment(\.timeZone) private var timeZone
    @Environment(\.locale) private var locale
    @State private var browse: GraphicalDatePickerBrowse?

    init(selection: Binding<Date>, range: DatePickerRange, displayedComponents: DatePickerComponents) {
        self.selection = selection
        self.range = range
        self.displayedComponents = displayedComponents
    }

    var body: some View {
        var interactionCalendar = calendar
        interactionCalendar.timeZone = timeZone
        let selected = selection.wrappedValue
        let basis = GraphicalDatePickerBasis(selection: selected, calendar: interactionCalendar)
        let displayedMonth = browse?.basis == basis ? browse?.month ?? selected : selected
        return GraphicalDatePickerPrimitive(
            selection: selection, range: range, displayedComponents: displayedComponents,
            selected: selected, displayedMonth: displayedMonth, calendar: interactionCalendar,
            locale: locale, browse: $browse, basis: basis
        )
        .onChange(of: basis) { _, _ in
            // Effective display already uses the new basis. Retire the old
            // browse state only after this observation was actually adopted.
            if browse != nil { browse = nil }
        }
    }
}

@MainActor
private struct GraphicalDatePickerPrimitive: View {
    typealias Body = Never

    let selection: Binding<Date>
    let range: DatePickerRange
    let displayedComponents: DatePickerComponents
    let selected: Date
    let displayedMonth: Date
    let calendar: Calendar
    let locale: Locale
    let browse: Binding<GraphicalDatePickerBrowse?>
    let basis: GraphicalDatePickerBasis

    var body: Never { fatalError("The graphical calendar is a retained primitive") }

    func makeComponent(context: ViewBuildContext) -> Component {
        return Component { runtime in
            let admission = GraphicalDatePickerAdmission(runtime: runtime, context: context)
            let isCurrent: @MainActor () -> Bool = { admission.isCurrent }
            let selection = self.selection.limitingWrites(isCurrent)
            let browse = self.browse.limitingWrites(isCurrent)
            let value = DatePicker.formattedValue(
                selected, components: displayedComponents, calendar: calendar,
                timeZone: calendar.timeZone, locale: locale)
            let valueNode = Text(value).monospaced().lineLimit(1)
                .makeComponent(context: context.withTextAlignment(.trailing).withLineLimit(1))
                .makeNode(runtime: runtime)
            valueNode.preferredSize = Size(width: 260, height: 22)
            valueNode.layoutPriority = max(valueNode.layoutPriority, 1)
            identify(valueNode, as: .value, context: context)
            guard
                let model = DatePickerCalendarModel(
                    containing: displayedMonth, calendar: calendar, timeZone: calendar.timeZone, locale: locale)
            else {
                let node = surface(children: [valueNode], height: 38, context: context)
                admission.mark(node)
                return node
            }

            let previous = monthButton(
                direction: -1, model: model, runtime: runtime, context: context,
                selection: selection, browse: browse, isCurrent: isCurrent)
            let next = monthButton(
                direction: 1, model: model, runtime: runtime, context: context,
                selection: selection, browse: browse, isCurrent: isCurrent)
            let title = Text(model.title).font(.headline).lineLimit(1)
                .makeComponent(context: context.withTextAlignment(.center).withLineLimit(1))
                .makeNode(runtime: runtime)
            title.layoutFillAxes = .horizontalOnly
            title.accessibilityTraits.formUnion(.isHeader)
            identify(title, as: .monthTitle, context: context)
            let headerChildren =
                context.layoutDirection == .rightToLeft
                ? [next, title, previous] : [previous, title, next]
            let header = Controls.stackPanel(
                preferredSize: Size(width: 260, height: 30),
                stackLayout: .horizontal(spacing: 4, alignment: .center),
                isHitTestVisible: false, children: headerChildren)

            var weekdayNodes: [ViewNode] = []
            for (index, symbol) in model.weekdaySymbols.enumerated() {
                let node = Text(symbol).font(.caption).foregroundColor(.secondary).lineLimit(1)
                    .makeComponent(context: context.withTextAlignment(.center).withLineLimit(1))
                    .makeNode(runtime: runtime)
                node.preferredSize = Size(width: 32, height: 22)
                node.isHitTestVisible = false
                identify(node, as: .weekday(index), context: context)
                weekdayNodes.append(node)
            }
            let weekdays = row(
                children: weekdayNodes, height: 22, context: context)
            identify(weekdays, as: .weekdays, context: context)
            var rows = [weekdays]
            for week in 0..<model.rowCount {
                var children: [ViewNode] = []
                for column in 0..<7 {
                    let index = week * 7 + column
                    if let day = model.cells[index] {
                        children.append(
                            dayButton(
                                day, model: model, runtime: runtime, context: context,
                                selection: selection, isCurrent: isCurrent))
                    } else {
                        let padding = Controls.panel(
                            preferredSize: Size(width: 32, height: 30), isHitTestVisible: false)
                        padding.isAccessibilityHidden = true
                        identify(padding, as: .padding(index), context: context)
                        children.append(padding)
                    }
                }
                let weekNode = row(children: children, height: 30, context: context)
                identify(weekNode, as: .week(week), context: context)
                rows.append(weekNode)
            }
            let grid = Controls.stackPanel(
                preferredSize: Size(width: 260, height: 22 + Double(model.rowCount) * 34),
                stackLayout: .vertical(spacing: 4, alignment: .stretch),
                isHitTestVisible: false, children: rows)
            identify(grid, as: .grid, context: context)
            let node = surface(
                children: [header, valueNode, grid], height: 104 + Double(model.rowCount) * 34,
                context: context)
            admission.mark(node)
            return node
        }
    }

    private func monthButton(
        direction: Int, model: DatePickerCalendarModel, runtime: RetainedViewRuntime,
        context: ViewBuildContext, selection: Binding<Date>, browse: Binding<GraphicalDatePickerBrowse?>,
        isCurrent: @escaping @MainActor () -> Bool
    ) -> ViewNode {
        let target = model.adjacentMonth(direction: direction, range: range)
        let enabled = context.isEnabled && target != nil
        let pointsLeft = (direction < 0) != (context.layoutDirection == .rightToLeft)
        let icon = Controls.icon(
            pointsLeft ? .chevronLeft : .chevronRight, preferredSize: Size(width: 14, height: 14),
            color: enabled ? context.controlPalette.label : context.controlPalette.disabledLabel,
            scale: 1, displayScale: context.iconRasterDisplayScale)
        let button = Controls.button(
            runtime: runtime, preferredSize: Size(width: 30, height: 30), layoutPriority: 1,
            cornerRadius: 6, palette: buttonPalette(selected: false, context: context),
            chrome: buttonChrome(context: context), clipsToBounds: true,
            layoutMode: .stack(.vertical(alignment: .center, mainAlignment: .center)),
            isEnabled: enabled, repeatBehavior: .disabled,
            action: {
                guard isCurrent(), let target else { return }
                let current = selection.wrappedValue
                guard isCurrent() else { return }
                // Do not apply a button from the former binding value to a
                // newly selected month before its replacement is published.
                guard current == basis.selection else { return }
                browse.wrappedValue = GraphicalDatePickerBrowse(basis: basis, month: target)
            }, children: [icon])
        button.accessibilityLabel = direction < 0 ? "Previous month" : "Next month"
        identify(button, as: direction < 0 ? .previousMonth : .nextMonth, context: context)
        return button
    }

    private func dayButton(
        _ day: DatePickerCalendarModel.Day, model: DatePickerCalendarModel,
        runtime: RetainedViewRuntime, context: ViewBuildContext, selection: Binding<Date>,
        isCurrent: @escaping @MainActor () -> Bool
    ) -> ViewNode {
        let isSelected = selected >= day.start && selected < day.end
        let enabled = context.isEnabled && model.isEnabled(day, range: range)
        let color = !enabled ? context.controlPalette.disabledLabel : isSelected ? .white : context.controlPalette.label
        let label = Text(day.label).lineLimit(1)
            .makeComponent(context: context.withForegroundColor(color).withTextAlignment(.center).withLineLimit(1))
            .makeNode(runtime: runtime)
        let button = Controls.button(
            runtime: runtime, preferredSize: Size(width: 32, height: 30), cornerRadius: 7,
            palette: buttonPalette(selected: isSelected, context: context), chrome: buttonChrome(context: context),
            clipsToBounds: true, layoutMode: .stack(.vertical(alignment: .center, mainAlignment: .center)),
            isEnabled: enabled, repeatBehavior: .disabled,
            action: {
                guard isCurrent() else { return }
                let current = selection.wrappedValue
                guard isCurrent(), let proposed = model.selectedDate(for: day, preserving: current, range: range),
                    proposed != current
                else { return }
                selection.wrappedValue = proposed
                guard isCurrent() else { return }
                context.invalidate()
            }, children: [label])
        button.accessibilityLabel = day.accessibilityLabel
        if isSelected { button.accessibilityTraits.formUnion(.isSelected) }
        identify(button, as: .day(day.start), context: context)
        return button
    }

    private func row(children: [ViewNode], height: Double, context: ViewBuildContext) -> ViewNode {
        Controls.stackPanel(
            preferredSize: Size(width: 260, height: height),
            stackLayout: .horizontal(spacing: 4, alignment: .stretch, distribution: .fillEqually),
            isHitTestVisible: false,
            children: context.layoutDirection == .rightToLeft ? Array(children.reversed()) : children)
    }

    private func surface(children: [ViewNode], height: Double, context: ViewBuildContext) -> ViewNode {
        let palette = context.controlPalette
        let node = Controls.stackPanel(
            preferredSize: Size(width: 280, height: height),
            backgroundColor: context.isEnabled ? palette.raisedSurface : palette.controlBackground,
            borderColor: context.isEnabled ? palette.controlBorder : palette.separator,
            borderWidth: 1, cornerRadius: 12,
            stackLayout: .vertical(
                spacing: 7, padding: EdgeInsets(top: 8, leading: 10, bottom: 8, trailing: 10),
                alignment: .stretch),
            isHitTestVisible: context.isEnabled, children: children)
        node.accessibilityChildBehavior = .contain
        identify(node, as: .surface, context: context)
        return node
    }

    private func buttonPalette(selected: Bool, context: ViewBuildContext) -> SurfacePalette {
        let palette = context.controlPalette
        return SurfacePalette(
            idle: selected ? context.tint : .clear,
            hovered: selected ? context.tint.opacity(0.88) : palette.quaternaryFill,
            focused: selected ? context.tint : palette.quaternaryFill,
            pressed: selected ? context.tint.opacity(0.74) : palette.secondaryFill,
            disabledBackground: selected ? palette.quaternaryFill : .clear,
            disabledForeground: palette.disabledLabel, disabledBorder: .clear)
    }

    private func buttonChrome(context: ViewBuildContext) -> SurfaceChrome {
        SurfaceChrome(
            borderColor: .clear, borderWidth: 0,
            focusRingColor: context.controlPalette.accentRing,
            focusRingWidth: MacOSControlMetrics.FocusRing.strokeWidth)
    }

    private func identify(_ node: ViewNode, as identifier: GraphicalDatePickerNodeID, context: ViewBuildContext) {
        node.nodeTag = identifier.nodeTag
        node.retainedViewIdentity = context.retainedViewIdentity
            .appending(.role(.content)).appending(.keyed(.init(identifier)))
    }
}
