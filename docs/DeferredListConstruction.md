# Deferred public List construction

This is a source checkpoint, not a completed compatibility or performance gate.
The composed changes have source checks but have not been compiled or executed
together. The original collection, lifecycle, accessibility, animation, visual,
and resource requirements in `goal.md` remain unchanged.

Flat `List(data, id:)`, Identifiable and mutable Binding data initializers now
retain a logical projection. `List { ForEach(...) }` uses that projection too,
including transparent Group, array, optional, conditional, and mixed static
fragments. ForEach stores its collection and one row factory; collecting IDs
does not call that factory. A native viewport request invokes only the selected
records. A record can produce zero, one, or several ordinary row leaves. No
synthetic visual wrapper is inserted around a record to manufacture identity,
focus, task appearance, or accessibility geometry.

Explicit static List content keeps its existing physical construction path.
Ordinary eager consumers such as Picker, TabView, stacks, grids, toolbars, and
Canvas symbol composition expand opaque builder segments where their semantics
need actual content. Explicit array-returning builder helper calls keep their
existing eager contract. This change does not make every ForEach consumer lazy.

## Ownership and bounds

Model IDs, duplicate occurrences, scalar measurements, and source metadata are
O(data count). Visited State and StateObject payloads can remain alive while
their exact keyed property declarations remain present. Those authored values
are distinct from evictable physical nodes, observations, task attempts,
presentation anchors, and deferred child leases. The latter belong to accepted
physical activity and retire on viewport eviction or actual removal. Escaped
Bindings keep their last readable snapshot but cannot write a retired generation
or a later same-key reinsertion.

The public adapter uses a bounded prefetch extent, native record/leaf limits,
and a capped set of protected interaction targets. A normal owned render or
layout shares the runtime's element and convergence allowance across viewport
work, target realization, probes, and lifecycle callbacks. Exhaustion yields to
ordinary later layout; it does not authorize another full budget in a nested
callback. A single row factory remains authored code: its own computation,
returned View values, and arbitrary nested content cannot be bounded by the
number of logical records. The facade also checks projected sibling count
before building their physical nodes. Exceeding that cap closes the original
source after temporary View cleanup; later frames do not retry an unsupported
shape or accept it as an empty row.

The current runtime defaults allow 128 element admissions and four convergence
rounds per owned pass. Public List prefetch is three estimated row extents,
clamped to 64–256 points. Its record cap is the larger of 512 and the declared
canvas height rounded up plus 64, with the height capped at 16,384; the leaf cap
is eight times that record cap, and interaction protection is capped at 16
records. Gaps count as retained leaves. These are source limits, not measured
latency, memory, or native performance results.

Accepted source replacement stages a new descriptor without revoking the old
one during body construction. The checked native exchange carries surviving
tokens, keyed state, bounded physical rows and compatible task ownership;
rejected or incomplete replacement is not proof that an omitted row departed.
Managed keyed tables use native buckets and check the original operation after
each authored hash/equality. The underlying model identity is checked again
after custom body, component and node construction, and after temporary View
cleanup, rather than only checking an immutable aggregate key.

Declared but unevaluated children and deferred child regions carry exact native
ownership provenance. Removing one accepted region retires only its own slot
generations. Native weak activity records and expired zero-output registrations
are pruned; a permanent set of every revoked anchor is not retained until the
whole List leaves. The new ownership and reentry tests must still run against
this composition before the earlier L06/L21/L23 gaps can be called verified.
See [LazyListStateActivity.md](LazyListStateActivity.md).

Direct construction without a State coordinator uses a native standalone lease.
The adapter binds it once when Runtime claims an actual attached container, not
when a temporary source node is built. GeometryReader reconciliation can keep
the previous List node while copying a new adapter and lease onto that target.
The fixed attachment and identity proof, expected runtime, exact adapter, and
installed lease must still match before any standalone row construction.
Adapter release, lease replacement, detach, and identity reassignment cannot
refresh that original proof. Discarded source nodes cannot revoke its accepted
target, and a replacement protocol lease cannot reopen the opted-in adapter.
Managed ownership and raw adapters without this standalone opt-in keep their
existing paths. This does not add mounted State continuity to direct snapshots.

A newly accepted adapter attachment marks the List and its ancestors dirty for
layout. A rejected foreign runtime can have painted the same empty subtree and
left its outer frame wrappers cached and clean; that cache cannot suppress the
first real layout visit in the expected runtime. Failed claims and repeated
registration of an existing attachment do not add this invalidation. The normal
layout pass still supplies all geometry and build authority.

## Navigation, scrolling and accessibility

Standalone public Lists explicitly capture their original runtime weakly for
navigation. Native owner publication records one actual attachment after real
membership, including the accepted target of an in-place declaration copy.
A rejected foreign runtime cannot arm that proof or consume the first accepted
navigation lifetime; it can cancel an old in-flight construction action.
Removing or replacing an accepted owner, adapter, lease, or identity invalidates
the old actions permanently. Raw owner and adapter setters finish publication
before delivering deferred navigation cancellation, so a cancellation callback's
newer replacement cannot be overwritten by the old setter.

Ordinary weak runtime expiry is distinct from explicit host closure. Existing
returned-tree activation and navigation among already realized rows remain
available after plain expiry, without creating rows or acquiring focus authority.
The navigation-only check uses the original native attachment and identity
tokens. A lazily allocated scalar close witness preserves terminal host closure
without retaining the runtime or its outer logical-host lifetime; descriptor
scopes still expire normally. Two expired runtimes cannot share a navigation
attachment merely because both weak references are nil. Managed/default native
owners keep their existing path, and standalone build permission still requires
a live runtime. These navigation changes have source checks only until the new
`StandaloneListNavigationLifetimeTests` and existing regression suites execute.

Deferred keyboard controllers carry a separate native container binding owned
by their fresh adapter. A GeometryReader or component rebuild can discard the
construction List while retaining its previous physical target; copying the
adapter and row declarations alone does not update a weak construction-node
reference. The binding records its first actual target only at successful native
claim publication in the original runtime. A repeated claim can finish an
earlier provisional claim once membership is real, but cannot refresh an old
proof. Foreign or provisional claims grant no container, and release of an
accepted attachment permanently revokes that binding. Its getter checks the
fixed native proof, installed adapter and standalone lease without looking up a
new owner, invoking a provider, or rebuilding rows.

Each fresh declaration has its own container binding. An old action that already
wrote selection still finishes through its original prepared physical receipt;
it does not acquire the new declaration's container. New actions use the adopted
controller and its accepted target. Already realized direct-data rows retain
their physical keyboard path after plain runtime expiry, while explicit close,
departure, and identity or adapter replacement remain terminal. Before actual
materialization a deferred public List has no selectable rows; existing eager
returned-tree construction actions are unchanged. Source-only transport and
native publication tests are listed in [Testing.md](Testing.md); execution
qualification still belongs to the integrated root run.

Direct data initializers preserve element-ID selection precedence. Builder rows
preserve their explicit `.tag` values. Keyboard movement realizes a real target,
protects the prepared source and target through the accepted action, and uses
the existing physical focus/reveal receipt. A later root rebuild cannot revive
an escaped old handler. Pending work retains one native demand; it does not
retain a registry of all row owners visited. Selection is written once, with
the original transaction, and focus needs an actual completed settlement.

One native scope slot owns a prepared request across accepted row-handler
replacement. Supersession, departure, external focus and host closure notify
terminal cancellation after native revocation and safe cleanup. Once the first
reveal is accepted, one runtime continuation owns only the native receipt and
weak physical endpoints. It waits through bounded layout and the accepted
tween without retaining the facade binding or repeating its write/reveal.
Animated focus requires a real terminal render; focus consumes that exact
settlement rather than borrowing a later nested query's proof.

Typed implicit scroll IDs are metadata. Arbitrary authored `.id` values and
selection tags cannot be inferred from that metadata. Finding a tag's first
eligible occurrence can need a search even when a later matching leaf is
already focused. Their ordered search may require **O(data) total row-factory
work**, in bounded slices. Each speculative row is abandoned; the search does not mount it, start
its tasks, keep its nodes, or publish a provisional jump. Explicit scroll IDs
continue to take precedence over implicit IDs. This search cost is separate
from the viewport construction bound.

UIA ItemContainer property-zero enumeration uses logical tokens without
constructing rows. Unknown names, bounds and actions stay unavailable instead
of being invented from estimated geometry. Realize enters the actual retained
admission and layout path. Logical IDs survive bounded receipt-cache eviction
and accepted same-membership adapter replacement, but not departure or
removal/reinsertion. Physical action receipts still expire on their original
attachment. One multi-output record uses its first actual projected leaf for
its logical provider; remaining leaves use ordinary provider identities.

## Remaining work under the original goal

- Tree OutlineGroup data initializers still need their own deferred hierarchy
  semantics. Dynamic collections hidden inside opaque row bodies or Section
  containers are not flattened into this public flat-record projection.
- Managed nonidentity structural removal now has a bounded source bridge for
  passive paint replay. Unsupported placement/effect transport remains
  refused, raw-provider behavior is unchanged, and the bridge still needs
  combined execution and native qualification. Full removal-transition parity
  remains required; see [ManagedListRemovalPaint.md](ManagedListRemovalPaint.md).
- The native pending-focus source now consumes `requiresRevealBeforeFocus`,
  including budget exhaustion after an accepted reveal. The separate frozen
  animated List cohort and its receipt/capture regressions still require a
  context join and combined execution; its earlier compilation does not
  qualify this composed implementation.
- Negative or nonfinite List row spacing is currently refused by this deferred
  path; matching the existing authored spacing semantics remains required.
- Unknown extents remain estimates. Alternating row parity uses actual known
  projected counts and estimates one row for a never-measured record; parity
  after an unknown zero/multiple-output prefix is not qualified. Layout must
  not construct the entire prefix merely to choose a stripe color.
- UIA searches by Name or AutomationID return `E_NOTIMPL`. Per-leaf logical
  metadata enumeration is not implemented. Opaque scroll targets inside an
  unbuilt nested List under the same reader return an explicit unsupported
  outcome rather than a false no-match or an incorrect implicit fallback.
- A raw external collection Binding cannot detect a removal/reinsertion interval
  that was never observed by any source update. Hosted bindings use exact
  logical membership. Producing the public `Set<Value>` selection payload also
  leaves one standard-library Hashable operation opaque; construction avoids
  that operation and event publication checks its surrounding receipt.
- An unknown predecessor gap can remain unresolved if required rows consume
  every record or leaf slot; the runtime does not invent an adjacency summary.
  Raw construction without a coordinator does not supply managed State
  continuity. A custom primitive/native producer that assigns two distinct
  GeometryReader build nodes to one installed component is still refused.
  Ordinary separately attributed sibling GeometryReaders have distinct owners.
- Fresh combined compilation, all preserved and new tests, retained visual
  review, native UIA/host behavior, animation characterization and resource
  measurements remain required. Source lint does not substitute for them.

## Removal-transition continuation

The current removal-overlay route in Runtime/ScenePainter paints a detached root
from a new zero origin and fresh clip, and can execute a Canvas draw closure
again while replaying the overlay. A lazy row cannot safely keep that route
alive after its state, observations, tasks and action ownership have retired.

The managed bridge now records the outgoing attachment's last completed
normal paint, copies its renderer resources, and retains native animation
values after executable retirement. It does not repaint the old node or keep
its callback payloads. Its supported transport, explicit restrictions, bounds,
and source-only verification status are described in
[ManagedListRemovalPaint.md](ManagedListRemovalPaint.md). Clipped motion,
scale/rotation, effect provenance, interrupted descendant animation, and full
native parity remain required under the original goal. Unsupported capture
does not fall back to a live detached subtree.

## Context join with the current retained controls

The public source has been joined onto the root containing shared-track Grid,
interactive graphical DatePicker, fixed-frame sizing intent, bitmap cap/tile
sampling, and the newer geometry diagnostics. Grid and GridRow expand deferred
ForEach carriers before structural child insertion, without replacing their
new layout modes with stacks. Reconciliation copies fixed-axis and bitmap
resizing flags through the same checked property path as other row content;
changed Grid configuration remains an update, not a new row identity.

Control labels are also eager consumers. DatePicker, ColorPicker, Picker,
Slider, primitive ProgressView, and Gauge resolve each label list once under
its existing environment before testing emptiness. An empty ForEach label no
longer creates a blank column, header, or bounds row. ProgressView custom-style
dispatch retains its own label construction path. Source regressions compare
static and deferred labels and cover Grid updates, image/frame flags, and
calendar browse state after eviction through both public List forms.

Static and deferred selectable rows also copy the actual content root's
accessibility label onto their existing selection owner. Empty labels stay
empty, and hidden content does not supply a label. Content identifiers,
grouping, values, traits, controllers, and actions remain on their original
nodes. This is not decoration traversal: labels behind inset, background, or
separator panels still need the separate row-decoration work, as do inset and
separator edge semantics. The root-label change adds no row construction or
logical UIA metadata search.

Logical UIA identity must survive the interval between an accepted adapter
exchange and its first prepared viewport. Absence of prepared metadata is not
proof of container departure. Current logical membership is checked against
the accepted source's native token table without invoking a row factory;
unknown physical properties remain unavailable. A direct Realize prepares and
resolves the same token under one work allowance and original native ownership,
while a deleted token cannot borrow the replacement container's lifetime.
Framework prefix-anchor corrections may continue that exact preparation;
authored scrolling, including a same-value write, cancels it. If a row callback
accepts another source on the same scroll owner, the obsolete preparation also
blocks that successor's anchor writes until the original query unwinds.
These regressions, including first-query and exhausted-budget cases, remain
unexecuted with this source composition.

The native host source now shares this construction path. Logical item-state
and property-zero ItemContainer lookup use typed native requests with copied
geometry. The full C-call lease spans actor dispatch, foreign start-after
identity checks, provider allocation, and final output marshalling. Transport
HRESULTs remain distinct from lookup status and Boolean action results. The
actor captures whether a source supports ItemContainer before creating its
native attachment; native code does not inspect actor-owned source objects.
No synchronous UIA operation may wait for native-owner progress or a
presentation acknowledgment. Nonzero property searches remain unsupported.

Both native dialog hooks survive every derived ViewBuildContext. The shared
retained invocation helper clears lazy-row and descriptor construction
attribution as well as the installed owner and epoch, without eagerly reading
a deferred file-dialog environment provider. An invocation context preserves
captured inputs; it does not restore a retired row's action authority.

Finite aspect-fit configuration is copied through the checked reconciliation
path. Its private measurement cache is never copied from construction nodes.
A lazy List's current scalar extent is resolved before persistent and per-walk
cache probes, stored with the current measurement key and no fit admission,
and never memoized as a stable child measurement. This path does not use a
measurement plan that has not yet been initialized.

The combined native/List source and its integration regressions remain
uncompiled and unrun at this handoff. All original held lifecycle tests are
preserved. The separate animated 125-test runtime cohort also remains unrun;
neither source composition nor lint closes an original goal gate.

## Foundation contract retained from the initial model

The following specification is retained from the initial internal-model
checkpoint. Its descriptions of an inactive public path refer to that earlier
source snapshot, not to the candidate above. Its ownership, measurement, work
budget, integration, and qualification requirements remain in force. The
current source join has not yet supplied their combined execution evidence.

The original requirement in `goal.md` sections 3 and 7 remains unchanged:
construction and retained row resources must follow the viewport and bounded
prefetch while preserving state, scrolling, keyboard selection, and
accessibility. The types described here are the first internal implementation
slice. **They are not connected to public `List`, `ForEach`, or `LazyVStack`.**
Those controls still construct their existing row values and nodes eagerly.
Passing the model tests would not establish lazy rendering, native behavior,
or completion of either goal section.

### Source contract and ownership

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

### Extent index and work budget

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

### Required next integration

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

### Validation scope

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
