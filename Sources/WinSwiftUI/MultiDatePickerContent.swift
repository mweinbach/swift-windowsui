import Foundation
import SwiftWindowsCore
import SwiftWindowsUI

/// Only these exact date-only representations are aliases for a visible day.
/// Other calendar settings, time zones and additional components stay untouched.
struct MultiDatePickerDaySelection {
    let insertion: DateComponents
    let aliases: Set<DateComponents>

    init?(day: DatePickerCalendarModel.Day, calendar: Calendar) {
        guard day.start.timeIntervalSinceReferenceDate.isFinite, day.end.timeIntervalSinceReferenceDate.isFinite,
            day.start < day.end,
            let interval = calendar.dateInterval(of: .day, for: day.start),
            interval.start == day.start, interval.end == day.end
        else { return nil }
        let components = calendar.dateComponents([.era, .year, .month, .day], from: day.start)
        guard let era = components.era, let year = components.year,
            let month = components.month, let number = components.day, month > 0, number > 0
        else { return nil }
        let isLeapMonth = components.isLeapMonth ?? false
        let bare = DateComponents(year: year, month: month, day: number)
        var qualified = DateComponents(calendar: calendar, era: era, year: year, month: month, day: number)
        qualified.isLeapMonth = isLeapMonth
        guard calendar.date(from: qualified) == day.start else { return nil }

        // Preserve the existing Windows click value whenever YMD is sufficient.
        // Historical eras and leap months can require the qualified value.
        let insertion = calendar.date(from: bare) == day.start ? bare : qualified
        var aliases: Set<DateComponents> = []
        for includesCalendar in [false, true] {
            for includesTimeZone in [false, true] {
                for includesEra in [false, true] {
                    for includesLeapMarker in [false, true] {
                        var candidate = DateComponents(
                            calendar: includesCalendar ? calendar : nil,
                            timeZone: includesTimeZone ? calendar.timeZone : nil,
                            era: includesEra ? era : nil, year: year, month: month, day: number)
                        if includesLeapMarker { candidate.isLeapMonth = isLeapMonth }
                        if calendar.date(from: candidate) == day.start { aliases.insert(candidate) }
                    }
                }
            }
        }
        guard aliases.contains(insertion) else { return nil }
        self.insertion = insertion
        self.aliases = aliases
    }

    func isSelected(in selection: Set<DateComponents>) -> Bool {
        aliases.contains { selection.contains($0) }
    }

    func toggling(in selection: Set<DateComponents>) -> Set<DateComponents> {
        var result = selection
        var removed = false
        for alias in aliases {
            if result.remove(alias) != nil { removed = true }
        }
        if !removed { result.insert(insertion) }
        return result
    }
}

/// These tags aid inspection; retention uses identities scoped to an occurrence.
enum MultiDatePickerNodeID: Hashable {
    case surface, container, label, monthTitle, previousMonth, nextMonth, weekdays, grid
    case weekday(Int)
    case week(Int)
    case day(Date)
    case padding(Int)

    var nodeTag: String {
        let suffix: String
        switch self {
        case .surface: suffix = "surface"
        case .container: suffix = "container"
        case .label: suffix = "label"
        case .monthTitle: suffix = "monthTitle"
        case .previousMonth: suffix = "previousMonth"
        case .nextMonth: suffix = "nextMonth"
        case .weekdays: suffix = "weekdays"
        case .grid: suffix = "grid"
        case .weekday(let index): suffix = "weekday.\(index)"
        case .week(let index): suffix = "week.\(index)"
        case .padding(let index): suffix = "padding.\(index)"
        case .day(let date):
            suffix = "day.\(String(date.timeIntervalSinceReferenceDate.bitPattern, radix: 16))"
        }
        return "WinSwiftUI.MultiDatePicker.calendar.\(suffix)"
    }
}

@MainActor
private final class MultiDatePickerInitialDate: ObservableObject {
    let value: Date

    init(value: Date) {
        self.value = value
    }
}

private enum MultiDatePickerAdmissionMarker {}

/// The existing retained preference copy installs this receipt on the adopted
/// surface. Escaped actions retain neither that surface nor an installed owner.
@MainActor
private final class MultiDatePickerAdmission {
    private weak var runtime: RetainedViewRuntime?
    private weak var owner: StateMountOwner?
    private let isManaged: Bool

    init(runtime: RetainedViewRuntime, context: ViewBuildContext) {
        self.runtime = runtime
        owner = context.viewIdentity.installedOwner
        isManaged = context.stateMountCoordinator != nil
    }

    func mark(_ surface: ViewNode) {
        surface.retainedPreferenceValues[ObjectIdentifier(MultiDatePickerAdmissionMarker.self)] = self
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
            if (node.retainedPreferenceValues[ObjectIdentifier(MultiDatePickerAdmissionMarker.self)]
                as? MultiDatePickerAdmission) === self
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
struct MultiDatePickerContent: View {
    let selection: Binding<Set<DateComponents>>
    let label: [AnyView]
    @Environment(\.calendar) private var calendar
    @Environment(\.timeZone) private var timeZone
    @Environment(\.locale) private var locale
    @StateObject private var initialDate: MultiDatePickerInitialDate
    @State private var browsedMonth: Date?

    init(
        selection: Binding<Set<DateComponents>>, label: [AnyView],
        now: @escaping @MainActor () -> Date = { Date() }
    ) {
        self.selection = selection
        self.label = label
        // StateObject's factory is lazy per mounted occurrence. A State seed
        // containing Date() would otherwise read the clock on every rebuild.
        _initialDate = StateObject(wrappedValue: MultiDatePickerInitialDate(value: now()))
    }

    var body: some View {
        var interactionCalendar = calendar
        interactionCalendar.timeZone = timeZone
        return MultiDatePickerPrimitive(
            selection: selection, selected: selection.wrappedValue, label: label,
            displayedMonth: browsedMonth ?? initialDate.value,
            calendar: interactionCalendar, locale: locale, browse: $browsedMonth)
    }
}

private struct MultiDatePickerMetrics {
    let width: Double
    let cellHeight: Double
    let horizontalPadding: Double
    let gap: Double

    var contentWidth: Double { width - horizontalPadding * 2 }
    var cellWidth: Double { (contentWidth - gap * 6) / 7 }
    var weekdayHeight: Double { cellHeight < 30 ? 20 : 22 }
    var headerHeight: Double { max(cellHeight, 28) }

    init(controlSize: ControlSize) {
        switch controlSize {
        case .mini:
            width = 224
            cellHeight = 22
            horizontalPadding = 8
            gap = 3
        case .small:
            width = 252
            cellHeight = 26
            horizontalPadding = 8
            gap = 3
        case .regular:
            width = 280
            cellHeight = 30
            horizontalPadding = 10
            gap = 4
        case .large:
            width = 308
            cellHeight = 34
            horizontalPadding = 10
            gap = 4
        case .extraLarge:
            width = 336
            cellHeight = 38
            horizontalPadding = 12
            gap = 5
        }
    }
}

@MainActor
private struct MultiDatePickerPrimitive: View {
    typealias Body = Never

    let selection: Binding<Set<DateComponents>>
    let selected: Set<DateComponents>
    let label: [AnyView]
    let displayedMonth: Date
    let calendar: Calendar
    let locale: Locale
    let browse: Binding<Date?>

    var body: Never { fatalError("The multiple-date calendar is a retained primitive") }

    func makeComponent(context: ViewBuildContext) -> Component {
        let labelContext = context.withViewIdentityRole(.label).withTextAlignment(.leading).withLineLimit(1)
        guard let labelViews = materializedDeferredViewList(label, context: labelContext) else {
            return rejectedRetainedViewComponent()
        }
        let labelComponent = composeComponent(
            from: labelViews, context: labelContext,
            fallbackLayout: .stack(.horizontal(spacing: 0, alignment: .center)), isHitTestVisible: false)
        return Component { runtime in
            let admission = MultiDatePickerAdmission(runtime: runtime, context: context)
            let isCurrent: @MainActor () -> Bool = { admission.isCurrent }
            let selection = self.selection.limitingWrites(isCurrent)
            let browse = self.browse.limitingWrites(isCurrent)
            let metrics = MultiDatePickerMetrics(controlSize: context.controlSize)
            let labelNode = labelComponent.makeNode(runtime: runtime)
            let node = calendarSurface(
                runtime: runtime, context: context, metrics: metrics,
                selection: selection, browse: browse, isCurrent: isCurrent)
            node.accessibilityLabel = accessibleLabel(in: labelNode)
            admission.mark(node)
            guard !context.labelsHidden, !labelViews.isEmpty else { return node }

            labelNode.layoutPriority = max(labelNode.layoutPriority, 1)
            identify(labelNode, as: .label, context: context)
            if context.isInsideGroupedForm {
                return groupedFormRowNode(label: labelNode, content: node, isHitTestVisible: context.isEnabled)
            }
            let container = Controls.stackPanel(
                stackLayout: .vertical(
                    spacing: 8, alignment: context.layoutDirection == .rightToLeft ? .trailing : .leading),
                isHitTestVisible: context.isEnabled, children: [labelNode, node])
            container.accessibilityChildBehavior = .contain
            identify(container, as: .container, context: context)
            return container
        }
    }

    private func calendarSurface(
        runtime: RetainedViewRuntime, context: ViewBuildContext, metrics: MultiDatePickerMetrics,
        selection: Binding<Set<DateComponents>>, browse: Binding<Date?>,
        isCurrent: @escaping @MainActor () -> Bool
    ) -> ViewNode {
        guard
            let model = DatePickerCalendarModel(
                containing: displayedMonth, calendar: calendar, timeZone: calendar.timeZone, locale: locale)
        else {
            let message = Text("Calendar unavailable").foregroundColor(.secondary)
                .makeComponent(context: context).makeNode(runtime: runtime)
            let node = surface(children: [message], height: 42, metrics: metrics, context: context)
            node.accessibilityRespondsToUserInteraction = false
            return node
        }
        let previous = monthButton(
            direction: -1, model: model, metrics: metrics, runtime: runtime, context: context,
            browse: browse, isCurrent: isCurrent)
        let next = monthButton(
            direction: 1, model: model, metrics: metrics, runtime: runtime, context: context,
            browse: browse, isCurrent: isCurrent)
        let title = Text(model.title).font(.headline).lineLimit(1)
            .makeComponent(context: context.withTextAlignment(.center).withLineLimit(1)).makeNode(runtime: runtime)
        title.layoutFillAxes = .horizontalOnly
        title.accessibilityTraits.formUnion(.isHeader)
        identify(title, as: .monthTitle, context: context)
        let header = Controls.stackPanel(
            preferredSize: Size(width: metrics.contentWidth, height: metrics.headerHeight),
            stackLayout: .horizontal(spacing: metrics.gap, alignment: .center), isHitTestVisible: false,
            children: context.layoutDirection == .rightToLeft ? [next, title, previous] : [previous, title, next])

        var weekdayNodes: [ViewNode] = []
        for (index, symbol) in model.weekdaySymbols.enumerated() {
            let node = Text(symbol).font(.caption).foregroundColor(.secondary).lineLimit(1)
                .makeComponent(context: context.withTextAlignment(.center).withLineLimit(1)).makeNode(runtime: runtime)
            node.preferredSize = Size(width: metrics.cellWidth, height: metrics.weekdayHeight)
            node.isHitTestVisible = false
            identify(node, as: .weekday(index), context: context)
            weekdayNodes.append(node)
        }
        let weekdays = row(children: weekdayNodes, height: metrics.weekdayHeight, metrics: metrics, context: context)
        identify(weekdays, as: .weekdays, context: context)
        var rows = [weekdays]
        for week in 0..<model.rowCount {
            var children: [ViewNode] = []
            for column in 0..<7 {
                let index = week * 7 + column
                if let day = model.cells[index] {
                    children.append(
                        dayButton(
                            day, metrics: metrics, runtime: runtime, context: context,
                            selection: selection, isCurrent: isCurrent))
                } else {
                    let node = Controls.panel(
                        preferredSize: Size(width: metrics.cellWidth, height: metrics.cellHeight),
                        isHitTestVisible: false)
                    node.isAccessibilityHidden = true
                    identify(node, as: .padding(index), context: context)
                    children.append(node)
                }
            }
            let node = row(children: children, height: metrics.cellHeight, metrics: metrics, context: context)
            identify(node, as: .week(week), context: context)
            rows.append(node)
        }
        let gridHeight = metrics.weekdayHeight + Double(model.rowCount) * (metrics.cellHeight + metrics.gap)
        let grid = Controls.stackPanel(
            preferredSize: Size(width: metrics.contentWidth, height: gridHeight),
            stackLayout: .vertical(spacing: metrics.gap, alignment: .stretch),
            isHitTestVisible: false, children: rows)
        identify(grid, as: .grid, context: context)
        return surface(
            children: [header, grid], height: 16 + metrics.headerHeight + 7 + gridHeight,
            metrics: metrics, context: context)
    }

    private func monthButton(
        direction: Int, model: DatePickerCalendarModel, metrics: MultiDatePickerMetrics,
        runtime: RetainedViewRuntime, context: ViewBuildContext, browse: Binding<Date?>,
        isCurrent: @escaping @MainActor () -> Bool
    ) -> ViewNode {
        let target = model.adjacentMonth(direction: direction, range: .unbounded)
        let enabled = context.isEnabled && target != nil
        let pointsLeft = (direction < 0) != (context.layoutDirection == .rightToLeft)
        let icon = Controls.icon(
            pointsLeft ? .chevronLeft : .chevronRight, preferredSize: Size(width: 14, height: 14),
            color: enabled ? context.controlPalette.label : context.controlPalette.disabledLabel,
            scale: 1, displayScale: context.iconRasterDisplayScale)
        let button = Controls.button(
            runtime: runtime, preferredSize: Size(width: metrics.headerHeight, height: metrics.headerHeight),
            layoutPriority: 1, cornerRadius: 6,
            palette: buttonPalette(selected: false, context: context), chrome: buttonChrome(context: context),
            clipsToBounds: true, layoutMode: .stack(.vertical(alignment: .center, mainAlignment: .center)),
            isEnabled: enabled, repeatBehavior: .disabled,
            action: {
                guard isCurrent(), let target else { return }
                // Browsing has no dependency on, or write to, the selected Set.
                browse.wrappedValue = target
            }, children: [icon])
        button.accessibilityLabel = direction < 0 ? "Previous month" : "Next month"
        identify(button, as: direction < 0 ? .previousMonth : .nextMonth, context: context)
        return button
    }

    private func dayButton(
        _ day: DatePickerCalendarModel.Day, metrics: MultiDatePickerMetrics,
        runtime: RetainedViewRuntime, context: ViewBuildContext,
        selection: Binding<Set<DateComponents>>, isCurrent: @escaping @MainActor () -> Bool
    ) -> ViewNode {
        let daySelection = MultiDatePickerDaySelection(day: day, calendar: calendar)
        let isSelected = daySelection?.isSelected(in: selected) == true
        let enabled = context.isEnabled && daySelection != nil
        let color = !enabled ? context.controlPalette.disabledLabel : isSelected ? .white : context.controlPalette.label
        let text = Text(day.label).lineLimit(1)
            .makeComponent(context: context.withForegroundColor(color).withTextAlignment(.center).withLineLimit(1))
            .makeNode(runtime: runtime)
        let button = Controls.button(
            runtime: runtime, preferredSize: Size(width: metrics.cellWidth, height: metrics.cellHeight),
            cornerRadius: 7,
            palette: buttonPalette(selected: isSelected, context: context), chrome: buttonChrome(context: context),
            clipsToBounds: true, layoutMode: .stack(.vertical(alignment: .center, mainAlignment: .center)),
            isEnabled: enabled, repeatBehavior: .disabled,
            action: {
                guard isCurrent(), let daySelection else { return }
                let current = selection.wrappedValue
                guard isCurrent() else { return }
                selection.wrappedValue = daySelection.toggling(in: current)
                guard isCurrent() else { return }
                context.invalidate()
            }, children: [text])
        button.accessibilityLabel = day.accessibilityLabel
        if isSelected { button.accessibilityTraits.formUnion(.isSelected) }
        identify(button, as: .day(day.start), context: context)
        return button
    }

    private func row(
        children: [ViewNode], height: Double, metrics: MultiDatePickerMetrics, context: ViewBuildContext
    ) -> ViewNode {
        Controls.stackPanel(
            preferredSize: Size(width: metrics.contentWidth, height: height),
            stackLayout: .horizontal(spacing: metrics.gap, alignment: .stretch, distribution: .fillEqually),
            isHitTestVisible: false,
            children: context.layoutDirection == .rightToLeft ? Array(children.reversed()) : children)
    }

    private func surface(
        children: [ViewNode], height: Double, metrics: MultiDatePickerMetrics, context: ViewBuildContext
    ) -> ViewNode {
        let palette = context.controlPalette
        let node = Controls.stackPanel(
            preferredSize: Size(width: metrics.width, height: height),
            backgroundColor: context.isEnabled ? palette.raisedSurface : palette.controlBackground,
            borderColor: context.isEnabled ? palette.controlBorder : palette.separator,
            borderWidth: 1, cornerRadius: 12,
            stackLayout: .vertical(
                spacing: 7,
                padding: EdgeInsets(
                    top: 8, leading: metrics.horizontalPadding, bottom: 8, trailing: metrics.horizontalPadding),
                alignment: .stretch),
            isHitTestVisible: context.isEnabled, children: children)
        node.accessibilityChildBehavior = .contain
        node.accessibilityRespondsToUserInteraction = context.isEnabled
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

    private func identify(_ node: ViewNode, as identifier: MultiDatePickerNodeID, context: ViewBuildContext) {
        node.nodeTag = identifier.nodeTag
        node.retainedViewIdentity = context.retainedViewIdentity
            .appending(.role(.content)).appending(.keyed(.init(identifier)))
    }

    private func accessibleLabel(in node: ViewNode) -> String? {
        guard !node.isHidden, !node.isAccessibilityHidden else { return nil }
        if let label = node.accessibilityLabel, !label.isEmpty { return label }
        if let text = node.text, !text.isEmpty, node.textStyle.fontFamily != "Segoe Fluent Icons" { return text }
        guard node.accessibilityChildBehavior != .ignore else { return nil }
        for child in node.children {
            if let label = accessibleLabel(in: child) { return label }
        }
        return nil
    }
}
