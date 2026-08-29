# Mounted observer admission

Mounted observers use a conditional construction path. They do not call the
ordinary State property resolver after authored identity hashing may have
closed or superseded the current build. The existing `onChange` adapter uses
this path; other adapters can reuse its private owner and bookkeeping cell
without changing public view or property-wrapper APIs.

## Receipt and publication

The original epoch must still be constructing, open, active in its registry,
and not superseded. A subtree epoch also requires its original live anchor
generation. The observer copies committed membership before the first authored
anchor hash, then establishes membership against that pinned local snapshot.
Scalar epoch and materialization receipts precede the lookup, follow it and
each subsequent key operation, and run again after the inner scope releases
its dictionaries. The observer never delegates this admission to ordinary
`canAdopt`, which still reads live membership. Within one constructing epoch,
anchor membership cannot change without adoption, retirement, or close
changing one of those scalar conditions.

The epoch tracks mutations of its candidate-owner, claimed-slot, and provisional
cell maps with a private revision. The ordinary State and StateObject resolver
bodies and signatures are unchanged; their map writes advance this receipt too.
Revision exhaustion disables observer admission without trapping or changing
ordinary property resolution.

An observer works on local dictionary snapshots and checks the epoch and map
revision after authored lookup, equality, and seed boundaries. It never holds
the epoch's dictionaries inout across an authored key operation. A nested
ordinary resolver can complete normally. Its map mutation makes the observer's
snapshot obsolete, so the observer rejects instead of overwriting that work.
There is no busy latch or retry loop that suppresses nested resolution.

These dictionary snapshots can add construction work. This slice makes no
performance claim and does not change the existing rebuild timing boundaries.

After resolution, three callback-free dictionary assignments publish the
candidate, claimed slots, and provisional cells. The expected revision advances
by exactly three. Old dictionaries remain pinned through all assignments.
Local snapshots and their displaced keys, owners, and values leave an inner
scope before a final scalar check returns the acquired location. Cleanup that
closes, supersedes, or mutates the epoch cannot authorize a later observer
publication.

A new cell or owner rejected before publication is revoked and retained by the
existing retirement queues until normal epoch cleanup. If that epoch already
finished, the unowned provisional storage retires immediately. Rejection itself
does not change a committed baseline; its continued membership depends on
which observer declarations are actually adopted.

If a materialized observer rejects a snapshot because ordinary nested work
changed the same epoch, its adapter can stage a no-action preservation marker
for the original committed owner and typed cell. A checked read-only lookup
creates the marker without a seed, reducer, observer comparison, or action.
The marker uses the existing staged-observation map and order. Rejected parent
prefixes discard it just as they discard ordinary proposals. A bare registry
lookup or an unused component does not stage a marker.

Each stage registers a materialization receipt before authored lookups. A
matching parent discard invalidates that attempt permanently, including a
discard reached from the fallback lookup itself. Private active discard scopes
cover activity removal, observer removal, State cleanup, and outgoing captures.
Prefix comparisons use snapshots and recheck the receipt after equality can
reenter. A new matching stage cannot escape the still-running discard; an
unrelated prefix remains eligible. Once discard returns, a genuinely later
materialization can receive a new receipt. The conditional resolver checks a
primitive, callback-free validator for that same receipt before seed/publication.

Only surviving markers prepare preservation at `willAdopt`. Their receipt is
bound to the original epoch, exact owner generation, and exact typed cell.
Revocation, replacement, or close rejects it. Prepare/commit include those
owners in cell pruning while retaining only normally claimed cells or the
exact preserved cell identifiers. This does not preserve descendant State
owners, unrelated slots, or an unmaterialized observer. No prefix-wide lifetime
exception is installed. The next accepted value still compares against the
last accepted baseline; the marker itself never compares or delivers.

The adapter factory runs only after conditional acquisition succeeds. A final
owner/cell check and scalar receipt follow the factory's application work before
staging its update. Both coordinator overloads use observer-only snapshot
validation for those final checks. Owner validation pins committed membership
and candidate owners; typed-cell validation also pins claimed slots, provisional
cells, and the owner's committed cells. All authored key access finishes and
those snapshots leave the inner scope before the final scalar check. These
checks do not call the ordinary `isInstallationActive`, `isInstalling`, or
`isInstalled` paths. A committed fallback checks exact live-cell identity
directly, without entering the provisional `isWritable` lookup. Its receipt
deliberately permits candidate-map changes from nested ordinary work while
still requiring the original active epoch and materialization.
Equality and actions still wait for adoption and the
existing guarded callback phase described in [MountedOnChange.md](MountedOnChange.md).
Both captured transaction slots, request completion order, and retirement
boundaries remain unchanged.

## Scope and evidence

This is private observer bookkeeping. It does not qualify arbitrary reentrant
authored hashing in ordinary State/StateObject resolution or general dictionary
mutation, nor change their preconditions, seeds, factories, or public API.
In particular, ordinary `canAdopt`, `beginSubtreeBuild`, installation, lease,
shared discard, and adoption paths retain their existing live dictionary
access. Their behavior under arbitrary authored hash/equality reentry remains
open; this correction does not make those entry points safe by implication. The
legacy owner-only `stageOnChange` signature remains available internally and
uses the same checked owner-acquisition path.

`MountedObserverAdmissionTests`, `MountedObserverReentryTests`, and
`MountedObserverAnchorGuardTests` cover fresh owners, provisional and committed
cells, anchor and final lookup cancellation, seed/factory cancellation, nested
ordinary resolution, and cleanup reentry. Anchored fixtures create and enter
their lease unarmed, exercise observer admission/final validation or snapshot
release, then disarm before ordinary adoption or teardown. They do not turn
the remaining ordinary-entry risk into a claimed guarantee.
The existing mounted-onChange tests remain unchanged. These are authored
regressions; execution results are recorded separately in the validation
handoff. They are not native SwiftUI, scheduling, or presentation qualification.
