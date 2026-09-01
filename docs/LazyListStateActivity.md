# Lazy List state and physical activity

This source candidate supplies the State and physical-activity bridge used by
public `List` viewport construction. `ManagedLazyListContent` is an internal
provider implementation, not a new public factory or a claim of SwiftUI
conformance. The composed checkpoint has not yet been compiled or executed.
Earlier Task and lazy-runtime results belong to their separately frozen sources,
not this composition.

A declared row and its displayed nodes have different lifetimes. The registry
allocates a sparse row record after an actual row visit. Its typed key and
occurrence remain scoped to the original List declaration. Existing State and
StateObject cells can survive viewport eviction while that logical row and the
exact owned property declarations remain valid. An accepted, exact declaration
removal retires its own slot generations. An old Binding retains the last value
with ordinary reference semantics, but cannot write a replacement generation.

Physical activity has a shorter lifetime. Observer baselines, subscriptions,
presentation anchors, deferred construction leases, and ID-task attempts require
their original accepted contribution and attachment. Keeping a logical row does
not keep these resources active. A returning physical row starts a new observer
baseline; `initial: false` seeds it without replaying cold changes, and
`initial: true` can deliver the current value after accepted publication. These
are explicit intermediate policies, still awaiting native characterization.

The renderer records actual accepted property, attachment, and structural
declaration contributions before releasing displaced captures. Facade publication
consumes those records, not a whole-row success flag. A stopped reconciliation
can therefore keep accepted A, preserve unchanged B, and discard unaccepted C.
An owning cell needs its original per-slot native permission. A synthetic group
needs a complete group receipt; a partially accepted footprint does not run its
comparison, action, or task. Ordinary components in a mixed root carry separate
component and group records; they are not fabricated rows.

One ID-task declaration owns one task slot for its complete physical group. Every
required member must reach the existing checked render callback on the accepted
attachment before a new attempt starts. There is no first-leaf shortcut, extra
render node, or second scheduler. Empty output has no launch target. Retirement
revokes an affected forest before callbacks and finishes captured cancellation
once. Compatible attempt transfer happens before mandatory outgoing cleanup.
Synchronous adoption, comparison, cancellation, and capture release retain the
request or subtree transaction; an asynchronous body is not a render or adoption
acknowledgment.

Managed materialization spends a one-use element receipt from the original
provider, request, and shared work budget before authored facade lookup. Rejection
does not refund it, and materialization cannot charge it twice. Metadata keeps
typed keys and occurrence tokens separate. A finite construction scope is not
stored in accepted provider configuration. The existing raw provider route does
not acquire this managed authority.

Managed keyed tables store native integer buckets. Each authored typed-key hash
or equality call is followed by a check of the original operation receipt before
another key, collision, or publication can be visited. Identity comparisons and
prefix checks walk structural segments explicitly, including an identity wrapped
inside another framework key. Resizing or removing a native bucket never asks
the standard library to rehash an authored key. Local snapshots pin displaced
keys and values until the caller's final receipt check after cleanup. Standard
`RetainedViewIdentity` Hashable conformances remain unchanged; these checked
operations are separate from ordinary key semantics.

Observer materialization captures its operation before comparing discard scopes.
An authored comparison cannot reenter the epoch and lend the older observer a
newer receipt for owner acquisition. Managed update callbacks, preference
defaults, and reducers keep the same operation through each authored call and
temporary cleanup before the update can be staged.

A declared component without State wrappers still carries native owner presence.
Inactive declaration preservation continues that presence only in its original
logical row or descriptor lifetime. It also carries each surviving property's
original slot receipt, including slots accepted from different partial rosters.
An empty property list cannot erase a deferred child's owner boundary, and a
parent row cannot borrow zero-slot ownership from a nested row.

Deferred children use a durable region associated with that native owner
presence. The currently accepted attachment and structural revision authorize
replacement of its child declaration table. Completion replaces only that
region, leaving the boundary owner, other deferred regions, and ordinary siblings
alone. A returning physical row can continue the same logical region through
its owner presence. Exact whole-row completion still controls the row's complete
roster; omission from an interrupted candidate never proves removal. Native
producers that cannot identify one exact deferred boundary remain rejected before
mutation rather than borrowing another region's declarations.

Zero-node managed rows use bounded native records. A real accepted removal from
the mounted table can retire their physical activity without a fake node, height,
or task target. Merely omitting a candidate does not establish removal. Deferred
GeometryReader work requires a fresh build scope derived from its original live
lease and contribution; a saved expired construction context is not reopened.
Accepted namespace replacement prunes the corresponding structural and empty
declaration records. Departure removes their physical registration while keeping
only ownership that the still-declared logical row permits. Repeated generations
at a shared anchor are covered by the native pruning fixtures; their boundedness
still needs execution against this composition.

Retained adoption stores weak native completion snapshots of the actual adopted
subtrees. When one snapshot covers every exact captured obligation of another,
the admission retains only the covering snapshot. It checks the old snapshots
and incoming one before compacting, then rechecks the admission. Attachment and
identity tokens, optional owner presence, runtime/parent references, and ordered
children must match; a new snapshot cannot repair stale authority. No currentness
result survives an application callback. Externally held receipts are unchanged.

For a nested chain of N nodes, this reduces admission-held witnesses from
quadratic to linear storage and cumulative completion validation from cubic to
quadratic work. Subtree capture and the rest of reconciliation still cost work.
`RetainedLazyListCompletionForestTests` covers structural counts and stale,
overlapping, independent, and externally held snapshots. These source bounds
do not establish end-to-end latency or hardware qualification.

The following qualification work remains open in this source checkpoint:

- The new checked-bucket, collision, nested-identity, and cleanup regressions
  require execution against this composed source. A source review or formatter
  result does not establish those behavioral results.
- Observer lookup continuation tests cover reentry during scope comparisons and
  update creation, including nested work that must survive rejection of the older
  operation. Preference traversal checks stop before a later default or reducer
  after the original operation expires.
- Exact declaration-marker replacement for declared but unevaluated children,
  partial multi-output ownership, empty output, and deferred owner continuity
  require the new source fixtures and preservation suites. No previous test
  assertion has been relaxed to qualify these paths.
- `MountedLazyListDeclaredOwnerContinuationTests` adds cold conditional and
  explicit-ID replacement, zero-slot continuation, and a deferred region that
  becomes empty while its siblings survive. It requires old Binding revocation
  and fresh generations on return without evaluating inactive bodies. These are
  source assertions, not reported behavioral passes.
- The full accepted 24-family matrix has not been executed against this composed
  source. Nested provider release, partial adoption, and repeated namespace
  replacement must retain their exact assertions. A build-only gate cannot
  establish any behavioral result.
- Raw legacy records without native component provenance reject a mixed managed
  adoption before mutation. This restriction is an intermediate implementation
  limit, not a change to SwiftUI's public contract. Existing nil routes remain
  separate.
- Public lazy List activation and focus/navigation integration must be qualified
  together with this bridge. Native task scheduling, native SwiftUI lifetime and
  reference behavior, rendering, performance, and App/Scene qualification remain
  separate requirements.

The fixture sources still require coordinated execution against the joined
tree. Source contracts, formatting, compilation, focused tests, native behavior,
and complete goal acceptance are distinct evidence levels.
