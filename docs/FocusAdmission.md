# Retained focus admission

Ordinary `RetainedViewRuntime.requestFocus(_:)` keeps its public Void shape.
It accepts focus during construction, an active build, and render lifecycle
callbacks such as `onAppear`. FocusState and default-focus modifiers construct
their candidates before attaching them, so ordinary detached construction is
still supported. A candidate that was attached when a request began cannot
gain that construction exception by detaching during a callback.

Ordinary and presentation-restoration focus share one checked intent revision.
Every admitted request advances it, including an unchanged target or nil-to-nil
request. Exhaustion does not wrap or authorize a later restoration. The runtime
removes its old focus pointer and clears the old control's chrome before
delivering its exit callback. A callback's newer focus choice wins; the
suspended request cannot enter its old destination or publish an obsolete
accessibility completion afterward.

Same-target requests from an entry callback or the new control's chrome clock
reaffirm only that exact entry. They do not enter twice. The witness lasts
through that clock's capture cleanup and is cleared before the final
accessibility notification. Moving away and back creates a new entry with its
own completion and cannot revive an outer entry's witness. Presentation removal
still uses its existing accepted-absence receipt and waits for its action/reset
flight and retained work to finish; this does not introduce another focus queue.

A reaffirmation carries the newer intent's primitive policy, attachment history,
and mutation witness. A newer ordinary request can finish once during an active
build, even if the suspended entry began as UIA focus or presentation restoration.
It cannot turn a formerly attached, incomplete entry into a detached construction
exception. A strict UIA caller still reports its original intent as superseded;
it does not claim that the newer ordinary completion belongs to its old request.

The runtime clock is an application callback too. Focus samples it before
writing chrome, checks whether its intent still owns the operation, and then
passes the sampled timestamp to the existing chrome writer. This prevents a
clock callback's newer focused/idle colors from being overwritten by an old
phase. Ordinary non-focus chrome callers retain their existing behavior.

Terminal revocation rejects new ordinary and accessibility focus requests.
The explicit window-focus-loss and subtree-detachment cleanup paths can still
clear an old focus and deliver its one exit. They do not reopen non-nil focus
after close. This preserves cleanup when a host stops render callbacks before
its editor and pointer/focus teardown.

## Retained UIA SetFocus

The live source keeps its required `uiaSetFocus(elementID:)` Void method and
weak runtime ownership. An internal result route uses a stricter runtime entry:

- Resolve the requested live node and perform one bounded layout query.
- Keep the focus authority captured before that query. A focus intent accepted
  by its callbacks supersedes the pending request instead of becoming its new
  authority.
- Require current layout settlement and prepaint, an actually attached and
  focusable target, enabled ancestors, and the current projected modal scope.
  Synthetic accessibility representation nodes have no keyboard-focus owner
  mapping and are rejected rather than focusing an unrelated owner.
- Recheck intent, terminal state, attachment, and callback-phase admission
  after exit, entry, and clock callbacks. Starting a build can change phase
  admission without changing a paint revision, so it is checked separately.

Known focus-owned writes (`isFocused`, caret opacity, timestamp-fed chrome,
and explicit invalidation) can dirty paint/layout without changing the target's
accepted modal scope. A local witness accounts only for those audited writes;
the runtime's global prepaint and layout receipts are never marked current to
excuse them. Application callbacks and their capture destruction are separate
boundaries. If they change retained state, each boundary can perform at most
one qualification query and must then observe settled, current admission.

There are at most five explicit queries: one at entry and at most one each
after the old clock, exit, entry, and new clock. Each existing query retains its
own bounded convergence work. An unresolved query stops the request; there is
no loop, scheduled retry, or fallback. A no-mutation focus request needs only
its initial query.

The final accessibility notification and callback-capture destruction finish
before the final pure result check. No query runs after that notification.
`false` can therefore mean that focus callbacks already happened but the final
target/context was superseded or became unqualified. It does not mean that no
effects occurred, and must not trigger an automatic repeat or erase newer focus.
Temporary operation pins protect the runtime through the result; the source
and copied capabilities do not retain it between calls.

An entry cannot borrow an intent accepted during a qualification query. Initial,
follow-up, and presentation-restoration focus queries suspend the published entry
witness for the complete query and its capture cleanup. They restore it only if
the original revision and focused target still own it. A final-notification
same-target request therefore neither repeats the notification nor revives the
completed entry.

## Limits and verification

These rules do not make arbitrary ordinary build/render focus depend on UIA
idle requirements, nor establish fully settled ordinary modal/layout policy
during every reentrant construction callback. General build/adoption admission,
SetValue, and VirtualizedItem.Realize remain separate work.

The native UIA SetFocus callback is still Void. Its current HRESULT reports
native context availability, not the new internal retained result. A future
optional result transport must preserve the legacy callback-table/factory ABI.
This slice does not change C/COM provider lifetime, native event delivery,
Narrator, or visible user/IME qualification.

`RetainedFocusTransitionTests`, `UIAFocusAdmissionTests`, and
`FocusClockCompletionTests` author headless ordinary, restoration, source, and
fake-host cases. They cover exact callback
counts, newer focus, clock/capture reentry, terminal cleanup, current modal and
enabled ownership, and bounded queries. They are not a replacement for native
qualification. Run them with the existing presentation focus, alert, FocusState,
window teardown, modal accessibility, and UIA ownership regression suites.
