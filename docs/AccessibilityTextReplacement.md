# Atomic retained text value replacement

`TextInputAccessibilityValueReplacing` is an internal capability of retained
`TextField` and `TextEditor` controllers. It submits an entire string through
the original binding once. It does not synthesize select-all, key input, IME
events, or a public selection-binding write. This source slice does not wire
the UI Automation Value provider to the capability or qualify native UIA
threading, focus, scheduling, or return-code behavior.

The caller supplies two synchronous, call-scoped checks. `mayDispatch` proves
that the originally selected controller and input handler are still eligible
before any write. `isRetainedTargetCurrent` checks the original retained
attachment, runtime, focus, and eligibility after possible effects; it must
permit a compatible controller rebuild without reading application bindings
or running layout. The capability does not retain either closure in a
controller, history action, document receipt, or queued callback. The eventual
adapter must not fall back to raw input after selecting this capability,
regardless of its result.

## One original effect

The controller captures its original binding, retained node, local history
session or managed document endpoint, and an editor-local attempt. The attempt
is shared only across compatible retained rebuilds. Removal, explicit identity
changes, incompatible input kinds, disabling, manager changes, and window
closure revoke it. Ordinary keyboard, IME replacement, or local undo text
replay supersedes an in-flight accessibility attempt before another text
effect. A nil undo manager does not remove that ownership protection.

Before the write, guarded reads use only the original text binding. A temporary
`Binding.limitingWrites` predicate also guards generated projection work, so a
projection getter cannot replace the editor and then reach the old root setter.
The controller stages an internal end caret and nil selection. During the
attempt, a compatible reconciliation preserves that staging if the cached
authored selection is unchanged. A changed authored selection takes priority.
Rejected text can restore unchanged internal staging without changing a
selection binding or a newer authored selection.

After submission, a guarded original getter verifies the observed UTF-8 value.
No replacement controller's text getter, selection getter, selection setter,
or invalidation closure is invoked by the continuation. If the original
controller itself still owns the attempt, its original selection getter can
observe an authored change made without a rebuild. Ownership is checked again
and the original text is verified again before that selection is converted to
safe retained offsets or captured in history. Silent, self-mutating arbitrary
getters have no stronger consistency guarantee than ordinary custom bindings.

Local history uses the existing `TextInputUndoSession.Mutation`. An unexpected
missing mutation after history-release reentry refuses dispatch. A compatible
adoption with registration disabled, or a finish whose registration is declined,
may clear its own checkpoint once; that does not authorize accepting a newer
control edit. The accepted post-finish generation is then pinned exactly across
the final invalidation. Existing typing/grouping behavior is unchanged.

Managed document bindings use their existing source, edit ticket, explicit
`binding.write(_:mutation:)`, accepted model-action receipt, and optional
selection sidecar. They never create a second local text history, including
when the document manager is nil or registration is disabled. A committed
document inverse can survive removal of its editor even when the interrupted
operation can no longer finish selection. A nested direct document assignment
does not acquire the interrupted edit's receipt. Read-only, expired, and secure
managed sources refuse the write.

Once verification, history completion, and internal metadata are settled, a
plain custom binding may need one final **original** context invalidation to
rebuild its authored display. It runs only if the original controller still
owns the attempt. A setter that already rebuilt skips it. No application
callback follows that invalidation in the continuation; final checks inspect
only retained ownership and history/source revisions. Deferred normal rendering
may of course evaluate the application's current views and bindings later.

## Result and identity limits

`didDispatch` means the one original `Binding.write` was submitted. A revoked
binding or arbitrary setter can still refuse it. `accepted` combines the
original getter's observed requested value, any required document receipt,
and retained availability after completion and the final refresh. It is not
an immutable snapshot of arbitrary application state after every later
callback. In particular, `accepted == false` can follow a real text effect and
an accepted document undo action. Neither boolean makes a retry safe.

The existing [retained text undo identity contract](TextInputUndo.md) remains
in force. Arbitrary custom binding closures cannot distinguish an equal-text
document switch under unchanged retained control identity. Applications must
use `.id(documentSessionID)` for that switch. The attempt token is not a new
public Binding identity, State location, or document provenance API. Managed
document key-path projections keep their existing endpoint guarantees;
optional/indexed or arbitrary projection identity is not expanded here.

## Authored regression fixtures

`UIATextValueReplacementTests` uses real public controls in
`WinSwiftUIWindowHost` with fake presentation and synthetic text metrics. It
covers one custom setter call and one final authored refresh, compatible
synchronous rebuilds, local undo/redo, explicit binding transactions,
selection overrides, registration changes, stale getters and projections,
ordinary/nested replacement reentry, identity/manager/security/close
revocation, and call-scoped validation lifetimes.

`UIADocumentValueReplacementTests` uses actual `FileDocumentSession`
configuration bindings and retained public controls. It covers one model
authority, compatible projected rebuilds and selection sidecars, nested
assignments, source/projection/removal boundaries, nil/disabled managers, and
read-only/expired/secure sources. These are capability-driver fixtures, not a
native COM-provider launch or a public DocumentGroup activation proof. Source
review, formatting, and contracts do not establish that these tests pass;
compilation and execution remain separate integration gates.
