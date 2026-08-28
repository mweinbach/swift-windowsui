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

A synchronous tagged attempt is allowed outside owned dispatch, or inside this
window's exact executing retry record. A prompt, another window's action, an
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
