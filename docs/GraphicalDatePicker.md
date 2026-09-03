# Graphical DatePicker

The retained graphical style has a month grid for date-containing pickers. It
uses the existing SwiftUI-shaped call site:

```swift
DatePicker("Start", selection: $start, in: earliest...latest, displayedComponents: .date)
    .datePickerStyle(.graphical)
```

Previous and next month buttons browse without changing `selection`. An enabled
day button chooses a date. The selected value remains visible below the month
heading, and the authored label keeps its existing behavior in ordinary rows,
grouped forms, and `.labelsHidden()`.

This remains a partial SwiftUI implementation. A graphical clock, wheel
columns, editable date fields, calendar popovers, month/year chooser, native
calendar keyboard navigation, and native pixel parity are not implemented by
this slice. A time-only graphical picker displays its value and keeps the
existing minute adjustments; it does not draw decorative squares that imply a
working clock. A picker displaying both date and time has a day grid, but time
changes still use the existing minute adjustments.

## Calendar and environment

The grid copies the inherited `calendar` and applies the inherited `timeZone`.
The calendar's `firstWeekday` determines weekday order. Local formatters use
the inherited `locale` for month headings, weekday symbols, day numbers, and
full accessible date names. Changing locale does not override an explicitly
configured first weekday.

Months and days come from Foundation calendar intervals, including calendar
month arithmetic for December/January and leap-month transitions. There is no
fixed 30-day month, Gregorian leap-year table, or dependency on today's date.
Cells contain actual civil days. Padding cells have no action, focus stop, or
accessible element. Right-to-left layout reverses the physical columns while
keeping each weekday and date paired.

The supported grid has seven columns and four through six week rows. Short
months, including the five- or six-day thirteenth Coptic month, pad to the
four-row display minimum. Every interval must be finite and advance, and
enumeration is bounded. If a date or calendar cannot produce a complete grid
within that boundary, the control falls back to its formatted value. It never
truncates a larger calendar and claims omitted days are represented. The
preferred calendar size is 280 points wide and varies with its row count;
these are retained layout choices, not pinned macOS measurements.

## Selection and ranges

The existing `DatePickerRange.contains` check remains the final absolute-date
authority. Closed bounds remain inclusive, and the existing exclusive-upper
Windows overload remains exclusive. Initial construction and month browsing
do not clamp or write an out-of-range selection. An initially out-of-range
month can still browse toward the allowed interval.

A civil day is enabled when its half-open interval intersects the supplied
range. Activating it first reads the current selection, then preserves its
wall-clock hour, minute, second, and fractional second on the chosen day.
Foundation's direct matching API uses
`.nextTimePreservingSmallerComponents` for a missing local time and `.first`
for a repeated time. For example, the proposed spring-gap policy maps a
missing 02:37 to 03:37 rather than 03:00. The fractional second comes directly
from Date's reference interval, avoiding integer-nanosecond quantization.

If that time lies outside the allowed portion of the day, selection uses the
nearest allowed representable instant. Exclusive endpoints are handled using
the predecessor of `timeIntervalSinceReferenceDate`; subtracting a fixed
second or converting through the Unix epoch could admit or skip an incorrect
instant. Both the original date and result must belong to finite, advancing
day intervals; this rejects silent Foundation capping of extreme inputs.
The result is checked again against the range before writing the binding.
Activating the already selected accepted instant does not write again.

These hidden-time, repeated-time, partial-day, and initial-range policies are
explicit Windows choices awaiting native behavior characterization. The
pinned SDK's inclusive date-bound declarations do not establish those native
details.

## State and interaction

The private calendar content uses ordinary mounted `@State` and the normal
typed view installer. There is no global month registry or callsite identity.
Unrelated rebuilds and keyed reordering preserve a surviving occurrence's
browsed month. Sibling controls and separate hosts keep independent months.
Replacing or removing an occurrence retires its state.

A changed selection, calendar, or time zone immediately determines the
displayed month. Existing mounted `onChange` delivery then clears obsolete
browse state after accepted publication, so changing a selection back later
cannot revive an old browsed month. Construction itself does not write State.
Locale-only changes can relabel the currently browsed month.

Month and day controls use retained buttons for pointer activation, Tab
focus, Enter/Space activation, and appearance-aware hover, focus, and pressed
surfaces. Disabled or out-of-range days remain named but have no activation
handler or focus stop. The selected day exposes selected metadata; the
calendar contains its accessible child buttons rather than combining them
into a decorative element. Navigation action names currently remain English.

Existing date-picker root arrow and accessibility increment/decrement
behavior is unchanged: exactly `.date` steps by one calendar day; other
component combinations step by one minute. Grid-specific arrow navigation,
roving focus, native assistive-technology behavior, and native focus order
remain unqualified.

Each constructed calendar gives its buttons a private publication receipt
holding only weak runtime and occurrence references. The retained host copies
that exact receipt onto the accepted surface. Before and after authored
binding callbacks, actions require an idle, live runtime and occurrence plus
the same receipt on a reachable current surface. The lookup follows valid
parent-child edges, is cycle-safe, and skips hidden and removal ancestors.
The existing binding admission path checks again before a write. A surviving
picker with a newly accepted month, range, or disabled configuration therefore
rejects callbacks escaped from its previous surface. There is no extra State
write, runtime field, global registry, or retained construction node.

The current ViewThatFits constructs candidates and returns only the chosen
node; it has no separate selector that changes among attached alternatives
during layout. A GeometryReader resize can reconstruct that choice without
rebuilding the outer view. If it chooses a fallback, the old calendar receipt
is absent from the accepted tree and cannot authorize an escaped action.
Normal retained pointer and keyboard dispatch continues to enforce its own
clipping, virtualization, and presentation rules; this receipt is not a new
general-purpose dispatch policy.

## Evidence and remaining compatibility

The source slice adds 35 XCTest cases for calendar arithmetic, ranges,
controls, environment propagation, focus, and mounted state, plus 14 cases
for the shared absolute-layout sizing correction it requires. Fixed
fixtures include 1900/2000/2023/2024 leap behavior, year rollover, local month
boundaries, Buddhist and Coptic calendars, and New York DST transitions. Its
preservation selection contains 126 existing cases, including all thirteen
existing DatePicker cases. Only the two assertions that expected the old
graphical placeholder size and five decorative squares change.

All 175 selected XCTest cases passed on private commit
`9f56ad97bab11979643e1e6425e945fa2b45ffe8`: the 49 additions and 126 preservation
cases, with no selected failures or skips. The complete 5,472-entry XCTest
registration was reconciled, but only the 175 selected cases ran. No Swift
Testing cases were selected. This result predates joining the source to the
newer main checkout; the private result does not transfer to that combination.

The combined checkout has fresh focused evidence at
`85ddfe8d1a66ded7ea20d802f385ec2e51033bb3`. The separate `CalendarText155`
selection ran 155 cases across 42 classes in eight naturally completed batches:
152 passed, three failed, and none skipped. The graphical mounted class passed
seven of eight cases; its candidate diagnostic failed. The MultiDatePicker
mounted class passed ten of eleven. All 19 UIA text-snapshot cases passed,
but those results do not qualify calendar behavior.

`GraphicalDatePickerMountedTests.testRejectedCandidateAndRemovalDoNotKeepProvisionalMonthState`
and the same-named `GraphicalDatePickerCandidateDiagnosticsTests` method still
fail while looking up required `ViewNode` values. The MultiDatePicker candidate
case also fails to find its calendar surface. The current record does not prove
the cause of those missing nodes or convert the earlier wrong-month observation
into a passing result. The two public MultiDatePicker accessibility-action cases
that failed at `63fd6dd` were not selected in this run. They both passed in the
separate `CalendarPublicActions2` selection at the same commit, as recorded in
[MultiDatePicker](MultiDatePicker.md); that does not establish full control
coverage or make the three candidate cases pass.

The result summary is `artifacts/calendar-text-85ddfe8-results.json`
(19,522 bytes; SHA-256
`a2fc0cbd17664e4f4eb770b11eef2a85e4cde6ea3a9b05b2be06dffc83670369`).
Its eight raw logs are under
`artifacts/calendar-text-selected-af8ea23bf6d94258875f419383a108d7/`.
This selection does not rerun the complete original 175-case roster or all 35
calendar cases. Broader validation, retained screenshots, and native comparison
remain outstanding.

The follow-up at `db417e57d6ba79574fd477b5585d62dbc59ff890` passed all 155 methods
in the same CalendarText155 selection, including all eight graphical mounted
methods and the candidate diagnostic. The three formerly failing calendar
methods retained their original assertions. Eight serial batches each exited
naturally with exact starts and passing terminals, complete owned process
cleanup, and no skips or timeouts. The separate CalendarReader24 selection
passed all 24 methods, including three new reader-member ownership tests.
Results are recorded in `artifacts/calendar-text155-db417e5-results.json` and
`artifacts/calendar-reader24-db417e5-results.json`.

The correction preserves a still-declared candidate's logical member through
an exact ordinary reader replacement. It requires the original accepted field,
drained own retirement and actual replacement completion. It does not revive
the old reader qualification or old button callbacks. Cold selection keeps the
same declared State; exact omission retires it. These headless tests do not
qualify full SwiftUI proposal probing, native calendar behavior or pixels,
performance, the full suite or the separate original155 keyboard gate.

The reference capture is `swiftui-macos-26.5-xcode-26.6`, exported from Xcode
26.6 (17F113), macOS SDK 26.5 (25F70), using Apple Swift 6.3.3. It declares
graphical style as an interactive calendar or clock but records no native
behavior verification. The Windows non-generic DatePicker, closed
style-profile API, missing `LocalizedStringResource` overloads, Int-backed
components, and extra exclusive-upper range initializer remain API
differences. No original release or compatibility goal is closed by this
calendar slice alone.
