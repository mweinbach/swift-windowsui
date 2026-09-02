# MultiDatePicker

The existing unbounded `MultiDatePicker` initializers now use retained month
browsing and day buttons. This remains a partial Windows implementation, and
the new source has not yet been compiled or exercised in this combined tree.
Its presence in WinSwiftUI does not establish availability in the pinned macOS
SwiftUI API or qualify a shared-source example on that platform.

## Calendar and state

The control reuses `DatePickerCalendarModel`. It copies the inherited calendar,
applies the inherited time zone, and uses calendar intervals for month and day
arithmetic. The inherited locale formats month, weekday, day, and accessible
date labels; the calendar's explicit first weekday remains authoritative.
Seven columns and four through six rows produce 28, 35, or 42 cells. Padding
cells have no action or focus stop. Invalid or unsupported calendar intervals
do not produce a truncated calendar presented as complete.

Previous and next buttons browse months without writing the selection. A lazy
mounted `StateObject` captures the initial date once per occurrence; ordinary
`State` then holds an optional absolute browse anchor. Rebuilds and keyed
reordering preserve a surviving occurrence, while removal and replacement
retire its state. Siblings and separate hosts have independent browse state.
Changing the selected set does not move the displayed month. Calendar or time
zone changes reinterpret the same absolute anchor; they do not convert the
stored selection or reset browsing. These are explicit Windows policies,
pending comparison with a supported reference-platform control.

Right-to-left layout reverses physical columns while keeping dates paired with
their weekdays. Retained metrics vary from mini through extra-large control
sizes. These dimensions are local layout choices, not native measurements.

## Date components and selection

Selection matches exact date-only representations of a displayed civil day.
For each day the control constructs at most sixteen possible aliases: the
current calendar or no calendar, its time zone or no explicit time zone, the
current era or no era, and an explicit leap-month marker or no marker. Each
candidate must round-trip through that calendar to the exact day start.

Activation reads the current set. If a supported alias is present, it removes
all supported aliases for that day. Otherwise it inserts year/month/day alone
when those components round-trip unambiguously, or a calendar/era/leap-month
qualified value when required. Foreign calendars or time zones, additional
components, invalid dates, and other unsupported representations stay in the
set unchanged. The implementation does not scan and normalize arbitrary user
values by interpreting all of them as dates.

The grid bound is not a selection-size bound. Copying and writing a large
`Set<DateComponents>` still costs work proportional to the supplied value;
sixteen alias candidates do not make the entire operation constant-cost.

## Interaction and accessible content

Day and navigation controls use retained buttons for pointer activation, Tab
focus, Enter/Space activation, and accessibility default actions. Selected
days expose selected metadata. Disabled controls retain their names but do
not activate. Grid-specific arrow navigation, roving focus, native calendar
keyboard behavior, and Narrator operation remain unqualified. Navigation
action names currently remain English even when calendar text is localized.

An authored label contributes its accessible name only when its node is not
hidden or accessibility-hidden. An explicit name is considered before an
ignored-children boundary, so ignoring children does not discard the node's
own accessible name. Visible child labels are inspected only when that
boundary permits them.

Each constructed surface carries a private admission receipt copied through
the existing retained preference path. Actions require that same receipt on a
reachable, visible, accepted surface in an idle live runtime. Managed actions
also require a live mounted owner. Receipts keep runtime and owner references
weak and are checked around authored binding reads and before writes. A new
surface, hidden alternative, removal, or superseding build cannot authorize an
escaped old button callback. This local check does not replace normal runtime
hit testing, clipping, focus, or accessibility dispatch.

## Validation and remaining work

The source adds 32 XCTest methods: seven selection tests, thirteen control
tests, eleven mounted tests, and one accessible-label regression. The focused
preservation selection adds all 35 existing calendar/graphical DatePicker
methods, for 67 methods total. All 701 existing tracked test entries at the
integration base remain unchanged. Strict formatting and architecture
contracts pass; compilation and these executions are still pending.

Range overloads, unrestricted alias normalization, native calendar focus and
style behavior, complete action localization, platform API availability,
retained screenshots, native visual comparison, and assistive-technology
validation remain open. None of the original product completion gates is
closed by this source slice.
