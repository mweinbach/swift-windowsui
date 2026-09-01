# Native Button transfer receipts

Status: implemented in source after the original proposal was approved. Independent review and serialized compilation/runtime validation are still required. The superseded draft ignored attachment proofs while transferring and recaptured them after callbackful legacy attachment. The current implementation keeps those proofs live, updates them beside deliberate native writes, and refuses further insertion after a callback changes an observed attachment or child table.

Keep public child-removal signatures, transitions, task ownership, provider budgets, and callback ordering unchanged. An optional concrete RetainedButtonActionAdoption argument is carried only by internal source-transfer helpers and the existing setRuntime implementation. A mounted source additionally needs its original native departure cohort: losing insertion permission does not cancel cleanup already owed by that source. Nil callers retain their current behavior. Receipts are checked before and after authored callouts and refreshed only beside the corresponding deliberate native writes.

The following signatures describe the implemented native boundaries. The new removal overloads are private to ViewNode. Existing public removal methods keep their signatures and delegate with a nil batch. Authored calls to those public methods must never inherit an ambient adoption batch, because doing so would bless the very attachment ABA that the receipt must detect.

```swift
private func removeFromParent(buttonActions: RetainedButtonActionAdoption?)
private func removeChild(at index: Int, buttonActions: RetainedButtonActionAdoption?)
private func detachRemovedChild(
    _ removed: ViewNode, buttonActions: RetainedButtonActionAdoption? = nil
)
fileprivate func setRuntime(
    _ runtime: RetainedViewRuntime?, hasRevokedTextInputOwnership: Bool = false,
    buttonActions: RetainedButtonActionAdoption? = nil
)
```

The private source-removal overload finds the exact child index in its current parent and calls the private index overload with the supplied batch. The index overload retains its existing cleanup scopes. A detached construction source uses detachRemovedChild with the batch; an already mounted passive source captures ButtonActionSourceDeparture before the first child-table or attachment write and drains that exact cohort. The setRuntime(runtime) call in setChildrenUnchecked and the descendant call inside setRuntime forward the adoption batch explicitly. Existing unrelated call sites use nil through the default argument. A foreign mounted Button owner remains ineligible as a fresh declaration; ordinary passive source reparenting remains supported.

The mounted-source cohort captures original nodes, their in-cohort parent relationships, native attachment proofs, controller/storage/task-state references, and disappearance callbacks. Its local cleanup permission is independent of destination admission and whether the runtime has closed. Global Button refusal is latched permanently, but each still-owned source node finishes its old disappearance and runtime/controller departure. Changes to the source child table refuse insertion without abandoning the original root's cleanup. Captured children are traversed instead of enrolling callback-installed replacements. If a node or an original in-cohort ancestor has actually reattached, its later parent/runtime/controller writes stop; a captured old controller reference alone cannot authorize detaching that controller's newer attachment.

Disappearance begins at its existing phase, not before a potential removal overlay. Once a RetainedTaskDisappearance receipt has begun, it is finished even after admission or attachment loss. Original keyed task handles are snapshotted before disappearance hooks but remain publicly reachable through both hooks; an explicit cancellation or same-key replacement keeps its synchronous cancellation order. Only at the existing terminal cancellation phase are matching old handles removed in a native pass before cancellation callbacks. Tasks launched by hooks are taken at that phase only while the same old physical attachment remains owned. No scoped-task API, provider budget, or State ownership policy is added. Old scroll history is transferred out of storage before its payloads are released at the reset phase. The source receipt also reaches removal-transaction modifiers and clocks, and the existing pointer/hover/chrome helper call chain, before their later writes. Public callback reentry never receives that receipt.

The departure cohort captures each original runtime's pointer sequence, separate native hover and scroll-indicator slot identities, and physical proofs for original interaction targets before the first removal write. Those receipts cannot be acquired after dismantle, disappearance, controller, or drag callbacks. Source interaction helpers use the original cohort or runtime-target proofs, never a fresh fallback capture. After a callback changes hover, only that obsolete hover cleanup stops; other still-owned pointer cleanup continues. The inner hover and chrome helpers also recheck slot identity around exits, entries, and authored clocks. Ordinary nil callers keep their current behavior.

The checked retirement chain also needs the optional argument at the actual native child-table write, rather than a refresh after its callback drain:

```swift
private func retireLazyListChildren(
    _ roots: [ViewNode], nodes: [ViewNode], survivingChildren: [ViewNode],
    admission: RetainedLazyListAdoptionAdmission?, removalReason: RetainedChildRemovalReason,
    lazyJournal: RetainedLazyListAdoptionJournal?, deferringOwnedDeparture: Bool,
    sourceParent: ViewNode?, buttonActions: RetainedButtonActionAdoption? = nil
) -> [ObjectIdentifier: RetainedLazyListDepartureCause]

private func publishAndDrainLazyListRetirement(
    roots: [ViewNode], nodes: [ViewNode], survivingChildren: [ViewNode],
    interactionRuntime: RetainedViewRuntime?, admission: RetainedLazyListAdoptionAdmission?,
    scopedTaskCleanup: [RetainedLazyListAcceptedTaskCleanup],
    groupTaskCleanup: [RetainedLazyListAcceptedTaskCleanup],
    lazyJournal: RetainedLazyListAdoptionJournal?, sourceParent: ViewNode?,
    departureCauses: [ObjectIdentifier: RetainedLazyListDepartureCause], deferringOwnedDeparture: Bool,
    buttonActions: RetainedButtonActionAdoption? = nil
)
```

setChildrenChecked passes its existing batch into retireLazyListChildren, which passes it into publishAndDrainLazyListRetirement. Already claimed task, transition, and controller cleanup still completes even if later receipt checks fail; the argument does not authorize early returns that skip those obligations.

Native receipt methods in RetainedButtonActionAdoption.swift:

```swift
func beginDeparture(in roots: [ViewNode]) -> Bool
func recordChildrenWrite(on node: ViewNode) -> Bool
func recordAttachmentWrite(
    on node: ViewNode, afterChildrenWriteOf parent: ViewNode? = nil
) -> Bool
```

- Keep attachment, identity, owner-slot, and native child-table witnesses live while a source is transferring. Do not blanket-ignore attachment during transfer.
- Separate scheduled departure from actual departure. A matching prepass may schedule removal but must not discard identity/attachment proofs before its matching work and actual removal boundary finish.
- Each witness also stores its node's native children object identities in order. recordChildrenWrite updates only that table; recordAttachmentWrite updates only the affected attachment proof. Validate every unaffected witness and every unchanged facet of affected nodes. A successful isCurrent check must immediately precede the controlled write sequence, with no authored callout before its receipt update.
- The optional afterChildrenWriteOf parameter permits a combined update for a temporary parent's child-table removal plus the child's parent/proof write, or the destination parent's publication plus that child's parent/proof write. These native writes must be adjacent and contain no authored callout. It is not a general refresh after matching or callbacks.
- beginDeparture validates the still-live scheduled cohort immediately before the existing path claims native departure. Only then may that exact cohort stop participating in future adoption witnesses. prepareDepartures itself keeps the attachment and child-table checks live through matching.
- recordInsertion records publication after those receipt updates; it must not recapture proofs that crossed controller or dismantle callbacks.

The original approved Runtime.swift sites are identified below by exact existing statements. Line numbers are intentionally omitted because the separate retirement and UIA packets shift them. Already-claimed outgoing cleanup deliberately receives no insertion receipt: its whole witness cohort was consumed at beginDeparture, and a later receipt failure must not skip that cleanup.

1. In setChildrenUnchecked, call beginDeparture before constructing the departing RetainedButtonActionRetirement. Refresh the destination table immediately after `children = []` and `children = nextChildren`. Already-claimed outgoing detachRemovedChild cleanup keeps a nil batch. Pass the batch to incoming `child.removeFromParent()` and `child.setRuntime(runtime)`. Refresh the child's attachment immediately after the adjacent `child.revokeLazyListAttachmentProofs()` and `child.parent = self` writes. Check the batch after each existing removal/attachment callout and before final publication; do not overwrite a child table installed by a callback. Recheck after the existing long-press and group-task drains through the caller's original completion check.
2. In the new private removeChild(at:buttonActions:), capture a mounted source's original cleanup cohort before removal, then refresh the source parent's table immediately after `let removed = children.remove(at: index)`. Detached construction sources continue through detachRemovedChild; mounted sources drain their local departure receipt even when insertion fails. Preserve the existing task and long-press cleanup scopes. This overload is only for an explicitly supplied internal transfer; public authored removal keeps a nil batch.
3. In detachRemovedChild, refresh the initial `removed.revokeLazyListAttachmentProofs()` before onDismantlePlatformView. In each terminal branch, refresh the adjacent proof revocation and `removed.parent = nil` before forwarding the batch to setRuntime(nil). Check around onDismantlePlatformView, applyRemovalTransition, markSubtreeDisappeared, and setRuntime; a failed adoption receipt does not skip cleanup already claimed for a real departure.
4. In setRuntime, refresh the deliberate `revokeLazyListAttachmentProofs()` before any following cleanup callout, and refresh `self.runtime = runtime` before controller attachment. Carry the batch through each descendant call. Check before and after scrollObserverStorage.reset, controller willDetach/detach/attach, releaseInteractionTargets, and any existing callback-bearing attachment registration. Nil-batch runtime transfer and retirement behavior remain unchanged.
5. In setChildrenChecked, refresh `children = expectedChildren` in the survivor-only branch. In the temporary-parent branch, use the combined update immediately after `temporaryParent.children.remove(at: index)`, proof revocation, and `child.parent = nil`, before invalidateRuntime and onDismantlePlatformView. At destination publication, use the combined update immediately after proof revocation, `child.parent = self`, and `children = expectedChildren`. Keep the existing LazyListAttachmentEntry and LazyListPublishedChildrenProof checks as independent requirements.
6. In retireLazyListChildren, call beginDeparture before its native retirement claim. In publishAndDrainLazyListRetirement, refresh `children = survivingChildren` immediately at that write. The departed cohort no longer grants acceptance and does not need new receipts for its terminal parent/runtime writes. The retained parent and surviving descendants stay witnessed throughout every cleanup callback. Do not refresh them after the helper returns.
7. In attachLazyListCandidate, refresh each entry immediately after its existing proof/runtime writes ending in `node.runtime = nextRuntime`, before registration or controller callbacks. Keep all checked-entry proofs and the Button batch live before and after controller attachment. recordInsertion then records publication from these current receipts without recapturing a proof that crossed a callout.

The required strict source oracles are already authored and remain UNRUN:

- RetainedButtonActionConstructionTests/testTemporaryParentDismantleCannotRestoreAnUnpublishedDescendantAttachment
- RetainedButtonActionConstructionTests/testControllerAttachCannotRestoreAnUnpublishedDescendantAttachment
- RetainedButtonActionConstructionTests/testTemporaryParentCallbackCannotHaveItsNewParentTableOverwrittenByStaleInsertion

The first two require stale reconciliation refusal and no call through the escaped pending Button action after an exact descendant detach/reattach. The third requires refusal without overwriting the parent table installed by the callback. Existing ordinary insertion, standalone, accepted-transfer, and unchanged-old-control tests must remain positive controls; do not weaken them to accommodate a refusal-only implementation.

Composition must preserve the separate UIA reader authority successor, ComponentHost's concrete native conjunction, and the removal owner's sealed retirement ordering. That reader successor introduces `rebuildUIAGeometryReader` and `buildAndAdoptUnleasedUIAGeometryReader`; the latter must carry an independent Button construction frame across its typed unleased body and adoption. Keeping only this base's raw else-branch scope would miss that new helper. The managed entry/defer scope remains compatible. The Button batch is not a substitute for any original UIA permission.

The implementation also captures each source and retained root's ancestor chain before matching starts. Those witnesses record native attachment, identity, a weak owner-slot observation and ordered child IDs; they do not enroll sibling subtrees or acquire their action owners as source declarations. Ancestor witnesses cannot release retired payloads: only the actual retained/source cohort participates in payload cleanup. A temporary wrapper discovered only during insertion would be too late to establish the original source relationship.

The ordered child IDs describe the current table. They do not claim to detect a same-parent reorder followed by an exact restoration when no observed attachment changes. Attachment detach/reattach and equal-value identity assignments have independent native generations and remain invalid even when their final visible values are restored.

The original three insertion rejection oracles are unchanged. Four source cases cover harmless temporary-parent and controller callbacks followed by usable accepted actions, temporary-ancestor attachment ABA, scheduled-departure identity changes during later branch matching, and an enabled/disabled/enabled declaration sequence that never revives its escaped old action. Eight further methods cover ancestor payload isolation; supported mounted passive transfer; admission failure during dismantle, willDetach, and detach; captured controller replacement; real task cancellation before rejected Button payload release; and descendant relocation during dismantle, hover exit, and an interaction clock. Two more require synchronous explicit task cancellation inside disappearance and preserve a surviving sibling's hover after exit, drag-end, dismantle, and controller callbacks without refusing the otherwise valid transfer. The hover oracle checks its later public exit, not just its visible flag. All 94 Button methods remain uncompiled and unrun in this private source packet. Formatting and architecture checks are not runtime evidence.

Inherited boundary: ordinary raw transitionOverlays still retain executable ViewNodes and have their pre-existing disappearance timing. After an overlay source has been unparented, a controller willDetach hook can reattach that same node; the old overlay completion can later run markSubtreeDisappeared against it. This packet does not claim complete overlay ownership safety or change that separate raw-overlay policy. The independently delegated legacy overlay investigation owns that repair and its existing midpoint/completion task oracles.

The remaining work is independent review of the immutable successor, composition with the separate runtime/reader changes, and execution through the root's serialized validation lane. This source-only change does not establish Button or Table completion.
