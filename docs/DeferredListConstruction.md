# Deferred List construction: internal model and integration boundary

The original requirement in `goal.md` sections 3 and 7 remains unchanged:
construction and retained row resources must follow the viewport and bounded
prefetch while preserving state, scrolling, keyboard selection, and
accessibility. The types described here are the first internal implementation
slice. **They are not connected to public `List`, `ForEach`, or `LazyVStack`.**
Those controls still construct their existing row values and nodes eagerly.
Passing the model tests would not establish lazy rendering, native behavior,
or completion of either goal section.

## Source contract and ownership

`SwiftWindowsUI/RetainedLazyListProvider.swift` defines a package-only provider
contract with an associated row-content type. It does not import `WinSwiftUI`,
renderer types, or platform APIs. A future facade adapter can supply view
content, and a retained adapter can build nodes under the existing build lease.
Neither adapter is installed by this slice.

`RetainedLazyListDataSource` snapshots the input collection's element values,
enumerates typed IDs and duplicate occurrences, and stores one content factory
for the collection. Enumeration never calls that factory. Source ordinals are
zero-based metadata positions, including when the input collection has a
different index range. They are not flattened view slots. The source does not
decide how many leaf rows a data element will produce.

Each logical element receives an opaque token scoped to one source. Its hash
and equality compare immutable framework identities and cannot invoke authored
`Hashable` code. Surviving typed keys and occurrences keep their tokens across
reordering. Removing a key and later inserting it creates a new token. A token
keeps only its small identity objects alive, not the provider, model, content,
state registry, or retained runtime. Duplicate occurrences are distinguished
without claiming that duplicate authored IDs provide stable application identity.

Each replacement intent also creates a fresh identity, avoiding generation
counter wraparound. Every old materialization request becomes obsolete even
when its row token survives. Reentrant replacement revokes the in-flight intent
but does not queue or retry either replacement. Failed replacement leaves the
old storage unavailable for requests until a fresh successful replacement or
close. Closing is irreversible. Old requests cannot acquire a new lifetime by
matching a key, position, or string description.

Collection iteration, key getters, equality, hashing, factories, and outgoing
payload destruction can run application code. Replacement constructs its
candidate separately, checks its intent after those calls, and releases the
outgoing configuration outside the stored property's write access. Lookup and
materialization refuse nested admission. A newer intent or close prevents
publication. Temporary key cleanup finishes before the caller rechecks the
primitive request generation.

IDs must remain stable within a published snapshot. Materialization checks the
captured ID before and after its one factory call and revokes the generation
if it detects drift. This is not observation of arbitrary reference-model
mutations. The future integration must additionally validate the retained build
epoch and current model/environment revision before adoption.

Model values, typed IDs, ordinals, and extent metadata require O(data count)
storage. Values are not deep-copied: application-defined model objects and IDs
may retain arbitrary payloads. The provider does not cache returned row
content, create per-row factory closures, or allocate nodes, controllers,
lifecycle tasks, renderer resources, or mounted State/StateObject cells. The
collection factory itself is one retained application closure. None of these
facts proves a bound on application-owned state or total process memory.

## Extent index and work budget

`SwiftWindowsUI/RetainedLazyListExtentIndex.swift` stores logical tokens and
scalar extent metadata. An unknown estimate must be finite and positive so an
unbuilt item is not silently treated as empty. A measured record can contain
zero, one, or multiple leaf extents; each must be finite and nonnegative.
The record retains their total and known leaf count, not their views or nodes.
An empty measured record has zero extent and zero leaves. This representation
does not add a visual wrapper or change the current List leaf-projection rules.

The segment tree builds in O(data count), with O(log data count) prefix queries,
point updates, window bounds, and anchor lookup. Duplicate tokens, invalid
numbers, and aggregate overflow are rejected. An invalid point update leaves
the previous index intact. Updating a shared index value also takes the normal
O(data count) array copy-on-write cost; the future container should retain a
unique index while applying point updates. The measurement context includes width, display
scale, content revision, and environment revision; updates for another context
are refused. This context is a cache tag, not proof of actual measured geometry
or permission to build a row.

Windows are half-open and expand by an explicit prefetch extent. Zero-size
records can remain inside the resulting metadata range, but they do not become
visible geometry. All-zero content yields an empty window. The model operates
on finite `Double` coordinates; a tiny positive extent can lose coordinate
resolution next to a much larger extent. End-anchor lookup still preserves the
last positive logical record rather than confusing that rounding with a
different item. This is not a claim that such coordinates are valid rendered
pixel geometry.

An anchor records a row token and an offset within its record. Rebuilding an
index with reordered surviving tokens preserves that identity. Resolving an
anchor clamps its local offset after a height reduction and clamps the result
to the new scrollable range. A removed token returns no anchor result; the
model does not invent a neighboring-item fallback. Authored default anchors,
explicit reveal requests, animation, overshoot, and presented geometry remain
the runtime's responsibility.

`RetainedLazyListWorkBudget` has separate element and convergence-round limits.
An admitted materialization consumes an element before authored key access;
empty output and invalidated candidates still consume it. Obsolete requests
and rejected nested admission do not run a factory. Exhaustion prevents further
authored work through that materialization entry point. The integration must
consume rounds around its bounded convergence loop. The budget creates no wakeup
or retry, and its completion value reports only whether the caller declared
pending work. It does not assert runtime layout settlement.

## Required next integration

1. Preserve the existing public initializer shapes, adding the escaping row
   factories confirmed by the pinned SwiftUI interface. Route by-value data
   List initializers through the provider while retaining the eager builder
   path for other content until that path has its own implementation. Reuse
   the existing row decoration helpers, including independently corrected
   accessibility, insets, separator, and retained keyboard-navigation behavior.
2. Add an optional provider to the retained list container. Layout reads extent
   metadata and records a requested window without executing row builders
   while mutating children. Post-layout resolution uses `ViewBuildContext`,
   `RetainedSubtreeBuildLease`, the retained build coordinator, and a shared
   bounded convergence budget. Content, order, extent, or context changes must
   invalidate layout and settlement. Logical omissions must preserve the
   virtualization descent path even when omitted rows have no nodes.
3. Preserve declared offscreen state independently of mounted visual resources.
   Use keyed membership so deleted rows retire, rather than retaining an entire
   list prefix indefinitely. Reconcile surviving mounted nodes by identity;
   register the adopted retained rows, not weak references to throwaway build
   candidates. Add an eviction reason that suppresses deletion transitions
   while retaining editor/capture/task/lifecycle teardown and reentry guards.
   Any offscreen interaction-owner allowance must have an explicit bound.
4. Maintain total content extent and a visible keyed anchor as variable heights
   become known. Do not derive scroll range from the mounted child union. Give
   logical selection/reveal requests a generation and current scroll attachment;
   resolve their physical nodes only after adoption and actual layout.
5. Keep efficient typed data-key lookup distinct from searches for opaque `.id`
   values authored inside an unbuilt body. Such searches need cancellation and
   bounded per-turn work, with honest O(data count) worst-case total work.
   Preserve explicit-over-implicit ID precedence, nested readers, and the
   existing zero/multiple-leaf identity and selection behavior. Do not perform
   an eager metadata pass that calls every row factory to hide this cost.
6. Add a separate logical UIA item route and ItemContainer support. Current
   UIA mutation targets remain tied to real node attachments; logical tokens
   cannot replace that authorization. Unknown properties and estimated bounds
   must not be reported as current measured properties. Realization must result
   in current nodes, full properties, and checked focus/Value ownership.

Enable the public deferred path only with joined construction, state, selection,
scrolling, eviction, and accessibility tests. Keep old eager-construction
characterizations for `LazyVStack` plus `ForEach` until that path changes. For
data List tests, replace obsolete eager node counts with logical counts and
bounded materialization assertions while preserving semantic assertions.

## Validation scope

The new provider and extent-index test classes are pure model tests. They cover
metadata enumeration without factory calls, bounded requests, typed keys,
reorder/deletion lifetimes, callback reentry and cleanup, finite arithmetic,
zero/multiple cardinality, prefix updates, windows, anchors, and context
invalidation. Their large-data cases establish structural model properties,
not a rendered-viewport or elapsed-time performance result.

Runtime integration still needs live node/resource counters over repeated
scrolling, variable-height rendering against an eager reference, retained state
and editor lifetime checks, keyboard/reveal checks after rebuild, and stale UIA
provider tests. Native Narrator, presentation, and full-suite qualification are
not supplied by this inactive model.
