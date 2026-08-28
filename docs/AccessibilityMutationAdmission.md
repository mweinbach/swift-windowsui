# Retained UIA mutation admission

Every mutating entry on `RuntimeUIAElementTreeSource` uses one runtime-owned
admission scope. Invoke, Toggle, SelectionItem, SetFocus, SetValue, and
VirtualizedItem.Realize cannot reenter one another through another adapter for
the same runtime. Entry rejects a stopped runtime, active retained build,
layout/render resolution, lifecycle/after-layout delivery, scroll observation
delivery, reconciliation, and presentation-action resolution. Inspection stays
available after terminal revocation.

The source still holds the runtime weakly between calls. Each admitted call
temporarily pins that runtime, and its inner helper releases selected callback
captures before the shared guard reopens. This is not a global restriction on
ordinary application focus, pointer handling, or programmatic scrolling. The
legacy Void SetFocus interface remains unchanged; its guarded focus transition
and result are described in [FocusAdmission.md](FocusAdmission.md).

VirtualizedItem.Realize captures the original node's physical path to the
runtime root before its layout query. Each path entry has a payload-free
identity that is discarded when its parent or runtime changes. Keeping the
old identity alive prevents a detach/reparent followed by reattachment from
reviving an old request, even if the node, coordinates, and parent chain later
look identical. These witnesses never own nodes, bindings, or application
callbacks. Synthetic accessibility representations do not have a physical
scroll owner and do not qualify through this path; their default-action
projection behavior is unchanged.

The single initial query must leave settled layout and current accessibility
prepaint. The same attached node must project as an enabled virtualized
placeholder in the current modal scope. The request then keeps its exact
descendant, coarse lazy target, scroll container, axis, geometry revision,
offset, and pointer sequence while sampling the clock. A mutation or ownership
change during that callback rejects the request before scrolling. The active
scope's mutation counter uses checked increment and cannot wrap into an old
authorization.

The UIA scroll path cancels an ordinary sole scroll-indicator interaction with
checks around its hover-exit callback and capture release. It publishes the
pointer/hover cancellation before invoking that callback and uses the already
sampled timestamp for subsequent chrome. It does not call the clock again or
run layout after cancellation effects. A callback that revokes the runtime,
changes the target, mutates retained state, or starts another pointer sequence
stops the old continuation. Repeated public pointer-down calls can leave a
scroll interaction alongside a press, repeat, long press, or node drag; UIA
rejects that mixed ownership before cancelling momentum, a tween, or pointer
slots. It leaves the public `pointerCancelled()` cleanup contract intact.

Scroll-phase bookkeeping can retire an application's cached geometry
observation value when its observed source or source epoch changes. The UIA
path pins existing values from every eligible phase-observation owner, including
owners whose eventual source differs from the target. It completes owned
bookkeeping without destroying those values inside observation-storage
accesses, records its expected state, then releases the pins in a separate
helper frame. A destructor that changes the offset or revokes ownership is
detected before any later alignment write or success result. The operation does
not absorb that callback's replacement offset as its own result.

`true` means the original scroll request was accepted under these checks; it
does not prove that another frame has already rendered the row or that a native
assistive client observed the change. `false` may follow clock, hover, scroll,
or cleanup effects. It never means those effects were rolled back, and this
path does not schedule a retry. A later independent request starts a new
admission. Existing deferred coarse-to-precise alignment and authored animation
continue only after the original request survives its checked continuation.

The public `scrollToDescendant` overloads keep their existing behavior, including
requests from after-layout callbacks, explicit transactions, and scrolling
while scroll input is disabled. No UIA admission, enabled, idle, or modal gate
has been added to ordinary public scrolling.

The shared guard is not a completed SetValue continuation fix. That route's
existing focus/select-all/commit behavior remains in this slice, including its
known need for a separate atomic editor operation across focus and selection
rebuilds. The editor work must preserve the existing retained-editor
`.id(documentSessionID)` boundary and document-owned undo; this change adds no
Binding/State identity, controller protocol, C ABI, or document guarantee.

`UIAMutationAdmissionTests` and `UIARealizeAdmissionTests` provide retained
source fixtures for admission, callback/capture reentry, weak runtime ownership,
lazy placeholders, pointer cancellation, and cached-value destruction. Existing
focus, projected action, UIA pattern, and public programmatic-scroll tests remain
separate regression coverage. Source results do not qualify native HRESULT
transport, provider disconnection, Narrator, visible windows, or native font and
rendering behavior; those require their own execution evidence.
