# Reusing an unentered UIA provider phase

The typed UIA request may reuse the still-unentered reader/provider portion of
one already paid initial convergence iteration. It never refunds a round or
raises the shared element or round limits. Generic lazy-list preparation does
not get this capability. A phase that entered its provider, including an empty
or refused provider, cannot be saved or resumed again.

This is a conditional optimization, not a claim that arbitrary row factories,
GeometryReaders, or callbacks fit four rounds. The unchanged default-four
pending-replacement regression must execute successfully before that failure is
considered repaired. Source review, contracts, formatting, and the accounting
below are not runtime execution evidence.

## Issue and ownership

Runtime can issue the native record after an ordinary charged measurement
batch returned unchanged, or after that batch's one required actual correction
pass as detailed below. Either boundary precedes reader and provider entry. The
terminal comparison requires accepted measurements and gap provenance, no
unresolved reader, no anchor correction, and no pending callback work. This must
be the original, nonrendering, unnested initial UIA preparation, before any target
request or demand exists. A preparation can issue only one record.

The record keeps the original layout pass and ordered weak visits, adapter and
accepted-record proofs, native view identities, reader body/lease assignment
markers, local layout and attachment proofs, and weak native completion witnesses
for the actual tree. It does not own application callbacks, leases, providers,
row nodes, State owners, or the old prepaint snapshot. Weak expiry is rejection.

The initial query still runs every normal range check, after-layout drain,
precise-alignment drain, prepaint update, focus restoration, coordinator drain,
navigation reveal, and both query unwinds. A saved phase requires all possible
callback queues and delivery flags absent and no presented scroll tween.
Checks before these boundaries revoke the phase before a no-op callback can run;
unchanged values after a callback cannot restore permission.

Prepaint release has a separate ownership proof. An ephemeral walk verifies the
actual root/children graph, parent/runtime edges, depth and cycle bounds, then
requires every old strong dispatch/interaction node to remain owned by that
tree. It returns only a Boolean and drops its temporary node references. If an
old snapshot is a node's last owner, the phase is revoked before the ordinary
snapshot release. Nothing delays its destruction. This proof covers whatever
payload a current node owns; it does not assume renderer structs or `Data`
deallocators are incapable of application effects.

## Original revisions and one-use entry

All checked additions are reserved before demand. G is the original geometry
revision, M the original accessibility mutation revision, S the original
resolution sequence, and P the presentation mutation revision.

| Checkpoint | Geometry | Accessibility mutation | Resolution | Presentation | Actual pass |
| --- | --- | --- | --- | --- | --- |
| Saved and consumed after complete initial query | G | M | S | P | Original |
| Existing target demand mark/invalidate | G+1 | M+1 | S | P+1 | Original |
| Distinct resumed query begins | G+1 | M+1 | S+1 | P+1 | Original |
| Runtime-owned coordinator build begins | G+2 | M+1 | S+1 | P+1 | Original |

Overflow rejects the reservation before demand. The arithmetic value is not an
authority and cannot create a phase. No latest counter is copied into an old
visit. The resumed query copies only the originally captured local proofs, not
fresh replacement stamps. An unexpected callback mutation or a nested query
after consumption revokes the original preparation, preventing another build
from recapturing authority under it.

The separate resumed query shares the ordinary frame query, layout settlement,
and epilogue implementation. It replaces only the redundant initial target
layout pass. The originally resolved reader phase runs once, then the original
target visit enters the provider with the normal standalone lease permission,
pre/post-lease guards, protected-root limits, element prepayment, candidate caps,
and probe rules. Other original lists must still have no work; work introduced
by a provider callback waits for ordinary charged convergence.

Before any lease callback the original full witness is checked. A false answer
is checked too. Between the complete post-lease check and the build checkpoint,
only the runtime-owned coordinator start can run. Its `isBuilding` flag is
expected at that checkpoint. Once original proofs qualify ordinary admission,
the phase is spent: the old actual-row table is not used to prohibit the row
adoption just admitted. Ordinary build admission, completion witnesses, epoch
seal/commit/abandon, cancellation and transport cleanup retain their existing
authority and run even after subsequent revocation.

One actual pass follows the resumed provider, including an unchanged build.
Every following measurement/reader/provider iteration consumes another round
normally. No second measurement batch runs under the saved debit. The target
certificate still requires a real debit in its target query, and an adopted
construction probe must retire before owned scrolling.

## Expected four-round path and diagnostics

| Debit | Measurement work | Reader/provider work |
| --- | --- | --- |
| 1 | Ordinary initial batch | Replacement visible rows |
| 2 | Accepted initial metadata | Saved while unentered; resumed once for target/hint/probe after all initial epilogues |
| 3 | Actual target/probe measurements | Ordinary probe retirement |
| 4 | Moved viewport measurements | Ordinary final selection and cleanup |

The test-only trace is disabled by default. Enabling it clears prior entries;
at most 512 entries retain native scalars and object identifiers, never a
callback or authority. Events identify actual passes, round debits, measurement,
reader, provider, save, resume, revocation and owned scroll. The resume event
uses the original pass with exactly the reserved G+1/M+1/S+1 values.

Layout-pass and owned-scroll events during a typed request optionally include a
complete native snapshot of active physical activity receipt identities in the
actual target List subtree. A failed walk is nil, not a misleading empty set.
Tests require a transient State row's receipt to be present after the resumed
provider adopted it, absent before the owned scroll completes, and revoked on
completion, while the target's receipt remains present. This distinguishes real
probe retirement from discarded construction or cleanup delayed until the final
viewport query. The trace cannot inject work or invoke a callback.

`LazyListUIAUnusedProviderPhaseTests` covers the public default budget, State and
probe lifetime, one-use and spent-empty phases, old-prepaint ownership, a no-op
epilogue, pass changes, attachment/identity/scroll ABA, and checked arithmetic
exhaustion. All earlier UIA budget and continuation tests remain unchanged by
this optimization. The separate reader-authority successor changes only its
approved temporary valid-reader-refusal oracle and adds independent safety
coverage; see [reader construction](ListUIAReaderConstruction.md).

## Composition with managed insertion

Managed construction captures each selected row's insertion origin before its
first factory. An introduction keeps its original native event; an already
accepted physical row keeps its original activity and attachment proofs. The
UIA plan can append one predecessor probe and spare ordinary prefetch only after
building its initial prefix. Those possible later rows must therefore belong to
the original capture as well. Otherwise the insertion plan's ordinary absent-row
fallback could classify an appended introduction as materialization.

Only managed preparation with an original UIA hint uses the additional capture.
Let K be the record cap. Its native token universe is the union of the initial
ordered tokens, the ordinary selection tokens, and the cached unknown predecessor
of each initial token. Each input has at most K entries, so the union has at most
3K entries and requires at most K existing logarithmic predecessor queries. The
candidate probe can walk backward only through prepared initial positions;
therefore any unknown predecessor it chooses is among these original candidates.
Selection prefetch comes only from the original selection array.

This universe does not authorize constructing all its members. The existing
record, leaf, element, round, and one-probe limits still choose actual work.
Planning hashes native token identities and queries the existing ordinal index;
it does not call providers, hash application IDs, copy the index, enumerate the
pending-event table, or scan an unknown source prefix. Existing expiration
cleanup reached through a pending-event lookup still runs; the 3K bound describes
the planning universe, not a new bound on that already required cleanup.

The capture holds the original attempt, configuration, generation, descriptor,
origin dictionary, and carried-row proofs. Its adapter and actual node references
remain weak. The existing carried-row proof's activity reference remains strong;
the additional capture uses that unchanged proof representation and lasts only
for this preparation.
The same captured dictionaries feed the candidate and its original cohort checks.
Full Runtime, lease, journal, and UIA guards surround capture and every factory;
the metadata object itself grants none of their authority.

A later appended token must have an entry in that same capture. A stale cohort,
changed native attempt, expired descriptor, or newly selected token outside the
original universe rejects forward work before another provider call. No callback
can cause a fresh provenance capture for that preparation. An event that has
since been claimed or expired stays the same event object; its existing claim
gate controls eligibility. It is never reclassified as materialization. Ordinary
cleanup still runs after rejection. Managed preparation without a UIA hint keeps
the original origin loop, and raw preparation does not enter this capture path.

`LazyListUIAInsertionOriginTests` adds ten separate cases. Native tests check the
3K universe, provider and authored-hash purity, invalid inputs, original expired
and claimed event identity, accepted prefetch cohort revocation, and descriptor
replacement. Event tests call the production metadata helper inside an actual
managed introduction before the directed predecessor/prefetch factories; they
do not fabricate a build or insertion completion. A nil-hint control checks the
ordinary accepted transaction. Three typed UIA cases check current-request
completion, scroll-intent revocation, and host-close cleanup with an explicit
16-round allowance. That allowance isolates composition behavior and does not
replace the unchanged default-four, eight, sixteen, exhausted-1x1, or generic
far-300 assertions. This source concern is not evidence of a demonstrated public
UIA animation failure. Runtime execution remains necessary for all new tests
and the original budget regression.

## First issuance after an initial measurement correction

A plain public List estimates the minimum row plus its separator. The first
actual row has no predecessor separator, so accepting its thirty-point extent
can require a correction to the thirty-one-point estimate even when the app's
unchanged row requests a twenty-four-point frame. Entering reader/provider work
before that required pass spends the phase while its old visit is stale. This
case may instead run the same paid measurement's required actual pass before
either remaining phase enters. It creates no extra query or measurement.

Only the original typed initial preparation may try this once, before any
request, demand, issued phase, or earlier correction attempt. The original
preparation, budget, and resolution sequence captured before measurement must
still match. Pending native work, unresolved existing readers, anchor work,
incomplete list cohorts, active scrolling, and checked overflow decline this
path and leave the original flow intact.

Before the pass, a scoped helper captures original native inputs and releases
all temporary strong references. The proof reuses weak actual-tree completion,
list layout and accepted-record proofs, and ordered list/reader cohorts. It also
keeps weak node/lease references with presence, construction nonce, local layout
identity, reader built size, and scalar gap inputs for the actual tree. Capturing
absence detects a body assigned to an original nonreader after its visit. This
adds work proportional to the mounted actual tree, not an unknown logical-row
scan. No application payload, old prepaint snapshot, callback, body, lease,
State owner, or actual row is kept alive by the proof.

The original geometry, accessibility mutation, presentation, sequence, pass,
scale, scroll, budget/count, and weak ownership facts must survive the complete
pass. Paint-only mutations therefore reject even when geometry did not change.
Resolved frames, content sizes, and reader slots are outputs, not equal-to-old
input requirements. Existing strict save/terminal checks decide whether their
new values are ready; the old weak input proof is never refreshed.

If capture is ineligible, ordinary ordering continues. If the moved pass loses
its original proof, only that preparation becomes inactive and normal query
epilogues and owed cleanup still run. If its proof survives, the unchanged save
helper may issue the first record. If strict save refuses nonterminal outputs,
the still-unentered reader and provider phases run once under the same debit.
An unchanged result does not skip the original terminal check or next paid
measurement decision.

This last fallback can require two actual passes under one phase debit: the
moved measurement correction and at most one necessary post-phase pass. A
provider's coordinator start invalidates geometry even if its build returns
unchanged, so Boolean work results alone cannot waive that second pass. If the
corrected pass remains valid and no work changes, no duplicate pass runs. There
is no inner retry, second measurement, second phase execution, refund, or new
debit in that iteration. Ordinary epilogues retain their separate existing work.

The saved/resumed revision table, one-issue rule, strict currentness checks, and
all query epilogues above remain unchanged. A resumed phase still receives its
existing post-provider actual pass. `LazyListUIAMeasurementCorrectionTests` adds
focused original-input, lifetime, cohort, overflow, output-slot, and fallback
accounting coverage. The old public budget and UIA tests remain unchanged and
must execute, together with the new cases, before this candidate is considered
a demonstrated repair.
