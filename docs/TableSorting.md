# Table sort-header interaction

The existing Windows Table callback API now builds a normal plain Button for a
column when both `isSortable` and `onSort != nil` hold. Its label retains the
authored header content. Pointer activation, Enter/Space, focus, enabled state,
and the UI Automation Invoke path use the same retained control as other
Buttons. There is no separate hit target, demo action, or rendering route.

The sort value remains controlled by the application:

- A header for the currently ascending key requests `.reverse`.
- A header for the currently descending key requests `.forward`.
- Another key, or an unsorted table, requests `.forward`.
- Repeated activation without an authored sort-state update repeats the same
  request. Table does not mutate the data, choose a comparator, or sort rows.

Both existing selection initializers keep their signatures. The callback receives
the column's optional `AnyHashable` key and `SortOrder`. The low-level
`AnyTableColumn` initializer can explicitly make a nil-key column sortable; that
column requests `(nil, .forward)` and never falsely displays a current sort.
A sortable column without a callback shows only the existing passive indicator.
A nonsortable column gains no Table action. An authored interactive header retains
its own ordinary control behavior.

For example, an application can update its own descriptor and rows in the
existing callback:

```swift
Table(rows, selection: $selection, sort: currentSort, onSort: { key, order in
    guard key == AnyHashable("name") else { return }
    currentSort = (key: AnyHashable("name"), order: order)
    rows.sort {
        order == .forward ? $0.name < $1.name : $0.name > $1.name
    }
}) {
    TableColumn("Name", value: \.name, sort: "name")
}
```

This documents the existing callback API. Full SwiftUI `sortOrder` bindings,
key-path comparator overloads, multi-column sorting, and a new public column-ID
API are not implemented by this change.

## Identity, accessibility, and ownership

Sortable headers with a supplied key use that key and a duplicate occurrence as
their retained header identity. Unique keyed headers can move without changing
their physical Button, focus owner, or UIA element ID. Duplicate keys belong to
their occurrence in the authored order; moving labels among equal keys updates
the content and current callback at that occurrence. Nil keys stay positional.
No identity includes the current sort direction, visible title, or callback.
An authored header `.id` remains on the content inside the Button.

The Button name comes from the authored root accessibility label, including an
explicit empty label, then visible header text, then the column title. The sort
glyph is decorative. Accessible value and hint describe the current sort and
next requested direction. The column width belongs to the whole interactive
header, including its glyph. Typed row identity, cell width, selection actions,
and List ownership retain their existing behavior.

Managed Table construction keeps its original lazy-row or descriptor attribution
while preparing headers and cells. Header occurrences use the existing checked
key map, and all header identities are prepared before any header builder runs.
Each key lookup, builder, collection operation, selection read, and diagnostic
row description is checked against its own original operation receipt. A callback
that closes the host or performs a nested registry installation stops the obsolete
Table before another authored callback or returned view is constructed. Rejection
is permanent for that construction; the next lookup cannot renew it.

Ordinary child view installation can still publish its own State owners. The Table
does not hold a registry-revision lookup across that work: it checks the original
construction attribution afterward, while the child keeps its own checked
installation path. Data traversal now checks each index and element operation,
and captures each row ID once instead of calling its getter twice. An Optional nil
ID remains a valid identity. Construction without a managed attribution keeps its
existing behavior and does not acquire a synthetic host-lifetime authority.

Both typed row-ID conversions share one lookup receipt. Swift's custom
`AnyHashable` representation hook can run authored code during either conversion,
so construction checks that same receipt between the conversions and afterward.
The retained key still uses the declared row-ID type. Shared single-selection
reads also carry the caller's original check through the binding getter and its
conversion, including deferred List keyboard navigation. Each getter runs once;
no selection and a selected Optional nil ID remain distinct.

The shared retained Button action owner is a prerequisite for callback lifetime.
Accepted rebuilding must replace the declaration behind the retained control;
old escaped activation callbacks must not run after replacement, removal,
detach/reinsert, or close. A callback replacing its own Button cannot reenter the
same physical action while that invocation is in flight. The ordinary Button
completion must not invalidate a removed or replaced declaration after the
author's callback returns. These are control rules, not Table-specific guards.
Arbitrary effects surrounding a manually assigned delegating `onActivate`
wrapper are outside the owned Button action's guarantee.

## Validation scope

`TableSortInteractionTests` covers the declared sort behavior, actual retained
pointer and keyboard routes, UIA source invocation/focus, passive and disabled
headers, naming, width/alignment, both selection initializers, and the existing
public value-key-path column initializer. `TableSortOwnershipTests` covers current
callbacks, clearing/restoration, keyed and duplicate-key reorder, authored IDs,
typed keys, removal/ABA, reentry, teardown, construction counts, and two windows.
The fixture uses a real `StateMountCoordinator`, typed view dispatch, and
`ComponentHost`; it creates no HWND, native COM provider, renderer backend,
dialog, or OS keyboard injection.

`TableConstructionAdmissionTests` adds 14 async methods for close and nested
installation during hashing, collision equality, sort comparison, header and cell
builders, collection traversal, selection reads, and row descriptions. Positive
cases preserve normal State installation in descriptor and lazy-row scopes,
unmanaged construction, and Optional nil row identity. The original 30 sort tests
and all pre-existing test files remain unchanged.

`TableAnyHashableAdmissionTests` adds 12 async methods for custom representation
callbacks during row conversion and all four single-selection read paths, plus
normal conversion, typed identity, and nil-value behavior. These cases supplement
the earlier 44 Table methods; none of those methods or their assertions is changed.

These cases are source-authored and remain uncompiled and unrun in this slice.
Formatter, contracts, and source review are not runtime or visual qualification.
Existing tests and their assertions are unchanged. Native pointer/keyboard/UIA
qualification, Narrator, macOS reference comparison, reviewed retained renders,
and full Table template qualification remain open. Table still constructs data
rows eagerly; a sortable header and checked callback boundaries are not evidence
of viewport-bounded Table construction.
