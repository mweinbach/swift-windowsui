# Window close ownership

An ordinary close is a request, not teardown. Titlebar Close, the system menu,
Alt-F4, and `Win32Window.requestClose()` enter the same native preflight. The
concrete delegate votes first; an installed neutral host votes afterward. Either
can veto. Refusal leaves the native window, renderer, accessibility bridge,
retained editor, and coordinator ownership intact.

`requestClose()` keeps its public void signature and posts an ordinary
`WM_CLOSE`. It does not report successful delivery or destruction, and calls
made during an active preflight remain suppressed. Package-owned deferred
approvals must not treat an untagged second `WM_CLOSE` as permission to destroy
a particular document revision.

## Final commit authority

The package-only `Win32CloseAuthority` capability is independent of the public
delegate chain. A participating host installs one weak authority with an opaque
`Win32CloseRegistration`. A missing or revoked required authority fails closed;
it does not restore the default approval used by windows that never installed
an authority. Replacement invalidates earlier tickets. Registration during an
active attempt or an unfinished native destruction is rejected.
`invalidateTickets()` retires a participant/session's tickets without removing
the host's required authority, so a fresh request can still be evaluated.

Each ordinary or tagged evaluation gets a fresh `Win32CloseAttempt`. After all
delegate votes, its authority prepares a `Win32CloseCommitLease` that pins the
actual owner and any session involved. The native path also retains the concrete
delegate, adapter, and neutral host through result handling, so weak participant
cleanup cannot occur between final approval and the native call.

The package-only `rejectAsUnavailable()` marker can strengthen the current
attempt's rejection without changing the delegate's public Boolean signature.
It takes precedence over a busy explanation or veto and cannot request a retry.
An escaped old attempt cannot mark a later evaluation unavailable. Observed
completion of the original native destruction still takes precedence over a
callback's rejection marker.

`validateAndReserve()` is a framework-only boundary. It reads current owned
state, rejects stale identity/revision/build/policy, and can reserve a short close
commit. It must not build content, invoke application callbacks or getters,
deliver observation, perform IO, pump native messages, or release application
payloads. Only primitive native guards follow it before `DestroyWindow`.

A document participant must reject writes, undo/redo, new IO, and reentrant
intent changes during that reservation. Native destruction itself can send
focus and teardown messages. A true predicate without a reservation does not
freeze document state while those messages run. Every prepared lease receives
one finish result, including rejection after reservation but before destruction.
Failure releases a still-live owner's reservation; it never revives a revoked
owner or makes a consumed approval reusable.

`finish(with:)` still runs inside the active close attempt, before the host
releases its reservation. It may perform exact primitive rollback or publish
owned framework error state, but it is not an idle prompt or retry callback.

## Tickets and actual outcomes

A `Win32CloseTicket` identifies one intent, registration, and native lifetime.
It contains no document value or strong host reference. Cancellation is
permanent. A terminal attempt consumes it before cleanup; a busy attempt can
leave an unconsumed ticket available for a controlled later continuation.

The package `attemptClose(ticket:)` API preserves that ticket through the same
veto and finalization path. Its result distinguishes:

| Outcome | Meaning |
| --- | --- |
| `closed` | The captured native lifetime completed destruction through `WM_NCDESTROY`. A replacement window is not included. |
| `vetoed` | A delegate, close affordance, or final policy rejected the request. |
| `busy` | A named native/build/owner phase prevented the attempt; this is not permission to spin or bypass a vote. |
| `unavailable` | Owner, registration, ticket, native lifetime, delegate topology, or required settlement evidence is unavailable. |
| `destructionFailed` | The native destroy call failed or returned without observed destruction. The session must not be declared closed from that return alone. |

A native lifetime has its own retained identity in addition to the existing
numeric generation. `WM_DESTROY` marks destruction started before callbacks;
`WM_NCDESTROY` records completion. A callback can destroy the old window and
recreate the same Swift object without giving the old approval authority over
the new lifetime, even when Windows reuses an HWND value.

## Owned deferred delivery

A registration can enqueue one pending close record for its current ticket.
The record has a prompt or retry phase, an action, and a checked process-wide
delivery number. Only that scalar is posted in the private `WM_APP + 0x100`
message; the message contains no pointer, document value, or approval. Exhausting
the number source makes submission unavailable instead of reusing a number.

Submitting the same pending ticket and phase coalesces without replacing the
first action. A conflicting pending intent returns busy. An executing prompt
may queue one retry for the same ticket. The record is removed before its action
runs, but prompt delivery does not consume the intent ticket. Cancellation,
registration replacement, ticket-epoch changes, and native destruction retire
pending work before its captures are released. Old or duplicate scalar messages
cannot remove newer work.

One executing retry record admits at most one matching tagged close attempt.
Only an observed `busy(buildsNotSettled)` result can earn a continuation, after
the lease's finish callback and revalidation of that exact attempt, ticket,
registration, native lifetime, topology, and delivery number. The ticket must
remain current and unconsumed. Resubmitting the same ticket and retry phase
consumes that permission once and queues a fresh delivery number; posting waits until the old
action and its captures have unwound. This permission is not document approval
and does not schedule work by itself.

Before its first admitted attempt, an executing record still coalesces an exact
duplicate. After a retry attempt, a missing or retired continuation returns busy
instead of reporting a coalesced action that will never run. A second close
request retires any unused continuation; cancellation, replacement, another
outcome, and native teardown cannot transfer it to another attempt or ticket.
Once a new pending record exists, its duplicates coalesce without replacement.
This retry permission does not change prompt-phase coalescing: submitting a
different callback for an executing prompt does not preserve that callback.

The old record's capture and promoted-owner cleanup also cannot create a new
record for its retiring ticket and phase. Only ticket/phase metadata spans that
cleanup; it does not keep application captures alive. An accepted replacement
for other work still waits to post until the cleanup boundary has returned.
Nested wake cleanup preserves each outer boundary.

An initial native posting failure returns `postFailed` to the submitting caller
without also invoking its failure observer. A posting failure during a later
rearm invokes that observer once, after the posting guard has cleared. A newer
submission for the same ticket suppresses the older failure notification. No
failure closes the window, consumes a document approval, or starts an automatic
retry. Callers must handle the result and revalidate any later continuation.

`Win32DispatchScope` spans the entire owned window procedure, including
`DefWindowProcW` and the final native self-reference release. It also spans close
attempts, mailbox delivery and cleanup, and the actual owned common file/color
dialog calls. File-dialog error sampling remains inside the modal scope,
immediately after a false native result.

A wake consumed by a nested dispatch or modal call keeps its record and requests
one rearm after the outer owned scope exits. It is not reposted while the nested
pump is running. The rearm pass only posts messages; failure observers and capture
cleanup run afterward under their own protected scope. Neither frames, timers,
Swift tasks, a presenter, nor a Foundation executor relay drive this mailbox.

A synchronous tagged attempt is allowed outside owned dispatch, or once inside
this window's exact executing retry record. A prompt, another window's action, an
ordinary window callback, and payload/failure cleanup cannot borrow that retry
permission. Ordinary untagged `WM_CLOSE` keeps its existing delegate behavior.

Queued actions must capture their host/session weakly. Delivery promotes and
pins the current authority before invoking an action. Teardown can hold
`pinDeferredWork()` through capability revocation, so removing a record does not
release application captures before editor and model writes have been disabled.
The native `WM_DESTROY` and failed-start paths keep that pin through their
ordinary cleanup. The failed-start path also snapshots and rechecks the original
handle, generation, and lifetime before its unconditional native destruction.

This scope covers owned entry points. It does not qualify arbitrary third-party
modal pumps entered outside them, and simulated dispatch tests do not prove real
Windows delivery. Hidden-window fixtures are separate from native document
workflow qualification.

## Managed host settlement

`WinSwiftUIWindowHost` installs a final authority independently of its optional
`WindowCloseParticipant`. Its first preflight for a native attempt keeps one
original receipt. Reentering the concrete delegate for that same attempt cannot
run another flush or replace the receipt after a later delegate changes state.
A direct Boolean policy query outside a native attempt cannot create a reusable
native approval.

A document configuration without an installed participant is rejected before
flushing observed work or querying layout. Native preflight records unavailable;
the legacy Boolean query returns false. Ordinary window configurations retain
their existing flush and policy behavior. This guard does not activate a native
document adapter.

Coordinated build settlement means no active build, queued build work, or reload
drain, and no retained reconciliation/terminal callback waiting or executing.
`ComponentHost.isBuildSettled` exposes that condition only for an installed build
lifecycle. Raw unmanaged hosts are unavailable; manually inserted geometry without
a build lease is not tracked by this condition. Root completion alone is not
settlement, and build settlement alone is not resolved layout.

`scheduleAfterBuildsSettled` registers an owner token without adding a rebuild or
changing a transaction. Replacing a pending owner preserves its FIFO slot and
uses its latest action. An idle registration may deliver synchronously. A delivery
pass processes only its original number of records; callbacks appended during
delivery wait for a later independent drain opportunity. It creates no wakeup or
automatic follow-up pass. `isBuildSettled` can therefore be true while a newly
registered observer is still pending.

The host's close helper keeps one current intent waiting for both coordinated
builds and host reload work. The host condition includes initial construction,
an active observed-reload flush, its scheduled flag, pending changed-object and
observation-context maps, and pending control invalidation. An empty component
queue alone does not satisfy it. The helper validates the weak host, participant
identity, registration, and ticket before submitting a native wake.

An already-ready caller submits directly. An idle coordinator is never registered
just to wait for a host-only batch. A real coordinator callback that finds host
work pending parks the same token; it does not register itself again. The existing
outermost accepted observed-reload flush supplies the host notification after
publication and transaction restoration. If component work remains then, one
observer waits for its actual drainage. These notifications create no build,
layout, frame, timer, polling loop, or automatic retry.

Settlement callbacks only submit owned native work; they do not prompt or attempt
close inline. If a busy retry becomes fully ready before its current action
returns, the exact native continuation above supplies one fresh pending wake.
Deferred submission failures are reported once after the wait token is retired;
failure observers may publish framework state but must not prompt, close, or
retry inline. Losing an owner or replacing its intent silently drops old work.

Readiness at submission is not a promise about later delivery. The action wrapper
revalidates ownership and ticket identity; it does not reserve build settlement.
A native retry performs fresh preflight. A future prompt or document IO adapter
must additionally check its delivery-time readiness and action phase, and prove
any later prompt handoff. This helper does not supply general same-phase UI
continuations or qualify those document workflows.

## Layout and final policy evidence

Preflight first checks that a layout query is permitted, flushes a pending
observed batch at most once, and uses the existing bounded
`resolvedLayoutFrame(of:)` query once. `canPrepareLayoutSettlement` reads owned
phase flags; it is not permission to close. A false value must not cause a
self-post or retry without a real settlement event. The host also rejects pending
live-resize geometry that has not yet reached the runtime.

The query can issue an opaque `RetainedLayoutSettlementReceipt` without rendering
or presenting. The receipt has a runtime identity, a checked geometry revision,
and a checked layout-resolution sequence. Both layout/children invalidation
paths retire it, and every later layout resolution retires it even when the
bounds happen to match. Paint-only writes do not change the geometry revision.

Every admitted coordinated root or deferred build also retires earlier evidence,
after the build guard is set and before update or lifecycle callbacks. An
unchanged, skipped, rejected, or abandoned build cannot revive the old receipt
when it returns to idle. This framework-only weak hook advances the same checked
revision without dirtying nodes or scheduling work. Preflight captures evidence
after its own required flush and layout, so legitimate settling can still
produce a receipt within the original attempt.

The final layout pass must finish without geometry invalidation or nested
resolution. Existing traversal limits must not truncate it. Pending after-layout
work, precise scroll alignment, or an eligible reader whose built size does not
match its positive resolved slot prevent a receipt. The check invokes no extra
reader body and does not change the existing four-round convergence limit.

Framework reader adoption copies its body and then its seed size. Assigning a
non-nil built size, even an equal value, or removing a previous size invalidates
that reader and its ancestor path. A nil-to-nil assignment remains a no-op. The
next ordinary query therefore reaches a replaced reader even when the new seed
looks identical but its actual constrained slot requires a different body.
The existing size comparison prevents repeated body calls once the slot matches.

A cleanup callback can render after the pair is copied but before the new
reader lease becomes active. If that render reaches the unresolved reader and
the lease denies building, the runtime preserves its layout invalidation through
the existing pending-node staging, only while a coordinated build is active.
It rechecks runtime attachment, exact lease identity, and body presence after
the lease getter. Idle denial adds no work or automatic retry. These targeted
invalidations can leave a follow-up dirty frame when adoption occurs during
rendering, like other mutations within a render; they do not add a queue, force
a render, or change convergence limits.

This evidence is conservative. A layout callback can make a geometry change that
the same pass happens to consume correctly, yet the pass cannot prove that all
earlier placement remains current. That completed attempt is unavailable. Normal
later layout can establish a new receipt; close handling does not add a convergence
loop or force a frame to obtain approval. Checked generation exhaustion remains
unavailable for that runtime's lifetime and is never a busy/retry condition.
The existing render dirty flags are not cleared to manufacture settlement.

Preflight captures the dismissal policy with its receipt, synchronizes the native
close affordance, and revalidates the same evidence afterward. Final validation
does not traverse the policy tree again: the policy setter itself invalidates
layout evidence. It checks the original receipt, captured policy, current native
affordance, host identity, pending work, and participant identity using owned
state only. It performs no build, layout, application getter, custom hash, IO,
callback delivery, or native synchronization.

The host's composite lease pins the actual host, participant, and prepared session
lease. It checks host evidence before and after the participant reserves its close,
and blocks participant replacement while that reservation is active. Failure
releases the matching live reservation; actual teardown remains authoritative.
This is a capability for a later document adapter, not document-scene activation.

Silent raw replacement of `onLayout` or `geometryReaderBuild`, raw reader pairs
that keep a nil built size, and external closure state that never invalidates the
retained tree are outside this receipt contract. Native SwiftUI policy for hidden
or deferred readers and conflicting sibling modifiers also remains unqualified.
`interactiveDismissDisabled` controls retained presentation overlays. The public
`windowDismissBehavior` modifier supplies native policy through the runtime's
`windowDismissalBehavior` getter.

## Forced cleanup and limits

Failed-start rollback remains unconditional through
`destroyForFailedStartup()`. It revokes close authority before destruction and
does not ask an unsaved-change question about a host whose renderer has already
been released. Ordinary dismissal must not use that path. Coordinator removal
and irreversible session teardown remain tied to actual `windowWillClose`.

This capability does not turn process termination, crashes, logoff, forced parent
destruction, or arbitrary external `DestroyWindow` calls into vetoable requests.
It also does not implement a document session, Save/Discard/Cancel UI, native File
menus, or default document-scene activation by itself.

Deterministic tests of `Win32CloseControl` use per-instance native-call adapters
and simulated lifetime notifications. They cover control flow and ownership,
not Windows message delivery. The existing hidden-window close suites and later
owned native delivery tests remain separate evidence. Native document workflow
qualification is tracked in [goal.md](../goal.md); a posted request or successful
save is not a completed window close.

Microsoft documents the confirmation boundary in
[WM_CLOSE](https://learn.microsoft.com/en-us/windows/win32/winmsg/wm-close),
native destruction and its return value in
[DestroyWindow](https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-destroywindow),
and asynchronous submission in
[PostMessageW](https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-postmessagew).
