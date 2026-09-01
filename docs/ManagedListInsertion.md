# Managed List deferred insertion

Managed List factories run at a viewport visit, after the component host has
already reconciled the containing declaration. The ordinary root insertion
walk therefore cannot be the delivery boundary for these rows. A later root
walk also cannot determine whether an unpresented row is an initial view,
a viewport materialization, or a newly declared logical row.

The managed path carries a native introduction event through its existing
provider continuation and accepts it through the same journal as row state,
tasks, input, and retained attachment. This does not change the public List
API or the existing provider, mounted-record, leaf, or per-opportunity budgets.

## Eligibility follows accepted logical membership

The typed provider's existing old/new token tables determine introduced and
removed tokens after the checked key work completes. This uses no extra key
enumeration or row-factory pass. A first source has no predecessor continuation
and does not introduce its initial rows. An accepted empty source followed by
a nonempty accepted source does introduce those new tokens, even when the
empty source never materialized a row.

| Accepted situation | Insertion behavior |
| --- | --- |
| First source, including a nested List's first source | Suppress initial row insertion |
| Existing logical row first visited or remounted by scrolling | Suppress viewport insertion |
| Existing accepted physical row gains a fresh retained descendant | Permit the fresh descendant's insertion |
| Accepted source introduces a new logical token | Permit one introduction event |
| Delete/reinsert reuses an old typed physical node | Permit the new logical event without resetting physical lifecycle flags |
| Already claimed row is retained or reordered | Preserve its existing animation; do not replay arrival |

Existing physical-row classification uses the original accepted record and
activity proofs, including the structural anchor of a zero-root row. Missing
State or absence from a mounted-node table is not proof of logical insertion.
These cohort proofs remain checked through provider and matching callbacks;
the complete child plan takes over intentional physical departures only at
the first checked mutation boundary.

## Transaction and modifier transport

A fresh source stages its full optional `Transaction` and legacy animation
tuple inside the component host's effective modifier scope. Activation requires
the exact accepted logical descriptor and the actual adapter attachment. If
descriptor publication precedes the physical claim, activation pins the first
accepted attachment fact while waiting for that claim; it cannot replace that
fact after an intervening callback.

Before an introduction is claimed, a newer accepted descriptor supplies the
latest transaction while retaining the same native introduction identity.
For example, when G2 introduces a row and G3 retains it before a viewport visit,
the row uses G3's accepted context. G3 with an explicit nil animation or disabled
animations does not inherit G2's animation. A fully absent transaction and
legacy animation retains the existing implicit timing or 0.35-second default;
absence is distinct from explicit suppression.

The row candidate freezes each node's effective context and authored insertion
endpoint during normal modifier evaluation, before copying properties onto a
retained target. A new logical event evaluates value modifiers with no previous
logical trigger, even when typed matching keeps the old physical node.
Established rows keep their existing modifier history. Modifiers are not run
again at delivery, and the current global transaction is not recaptured there.
An in-flight old opacity does not replace the new source's authored endpoint.

## Claim at publication, deliver after checked adoption

An introduction has one stable native event and one native candidate claim
identity. The first accepted prefix consumes that event: an exact prepared
property copy, a fresh actual attachment, an accepted final children field,
an accepted unchanged attachment, or the accepted zero-root row table. These
notifications use the journal's original candidate, not whichever adapter may
be current after a callback. A later rejection cannot return the event to a
successor candidate.

The fresh actual nodes receive initial-suppression or consumed-arrival markers
before any attachment controller runs. A partial accepted row therefore cannot
replay through an ordinary root traversal. Logical reintroduction does not
clear `hasAppeared`, State, task state, or existing lifecycle flags.

The candidate indexes the complete returned source forest, not only nodes with
separate owned-output registrations. Source identities, transition configuration,
actual target identities, and original attachments remain guarded through
modifier callbacks, accepted publication, and cleanup. Only an exact accepted
framework copy of transition, implicit timing, or modifier configuration can
advance that target's configuration witness. Equal external assignments revoke
the original witness.

Delivery runs after complete attached reconciliation and before the journal is
sealed. Every recipient needs its completed accepted row table. All presentation
plans are prepared before one shared runtime clock sample; the clock and its
captured payloads unwind before the original admission, tree, configuration,
pose, and animation-state checks run again. A nonfinite clock rejects delivery.
Identity and explicitly suppressed transitions consume arrival without reading
the clock. Native writes replace only the transition's channels and preserve
unrelated animation state. Fresh sources that are also actual targets advance
only their own planned scalar pose witnesses; completion does not discard their
identity, configuration, or attachment obligations.

Unclaimed events and accepted declaration context expire on actual release or
the existing viewport settlement boundary. Generic candidate revocation,
measurement invalidation, and bounded retries do not invent a new expiry or
arrival. Candidate disposal revokes its transport before releasing source
payloads. No timer, retry queue, extra factory debit, or global event cache is
introduced.

## Evidence and limits

The original focused run at `02edb4cb233f5684c5efbbc7881843506702a779`
completed naturally with 145 passes and five failures. Two failures were missing
managed insertion animation states. The other three test methods expected a
zero blue-minus-red pixel contrast where the declared plain List background is
opaque `#17171C`; their separately reviewed fixture correction is documented in
[ManagedListRemovalPaint.md](ManagedListRemovalPaint.md). The original failed
run remains evidence and is not rewritten as a pass.

`ManagedLazyListInsertionEventTests` adds eleven actual retained-node tests for
initial and cold rows, nested sources, empty rows, accepted transaction changes,
physical reuse with fresh State, and modifier history. The ten
`ManagedLazyListInsertionBoundaryTests` exercise rejected preparation, accepted
partial attachment and field-copy cleanup, a returned descendant without its
own factory output, shared timing, nonfinite clocks, clock-capture destruction,
configuration revocation, unrelated animation writes, and reordering. Existing
managed removal regressions are preserved. At the source-repair checkpoint,
independent source reviews, strict formatting, and contracts passed; compilation
and executable validation remain the integrating root's responsibility.

The G2/G3 rule is retained-runtime behavior, not proven native SwiftUI coalescing
parity. Geometry-dependent transition destinations still use the existing
pre-layout retained-frame semantics. This repair does not establish wider
transition geometry, native scheduling, GPU execution, or product completion.
