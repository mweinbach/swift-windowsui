# Accessibility through declared frames

A sizing frame must not turn its content into an unrelated accessibility
container or lose modifiers applied outside the frame. The retained runtime
now records the declared content of fixed, flexible and alignment frames and
projects the corresponding semantic element through those wrappers.

Explicit outer metadata includes nil, false, zero and empty values, as well as
ordered trait changes. Absence of an override is distinct from explicitly
clearing a value. Same-child metadata updates preserve semantic identity;
replacement, detach and action mutation invalidate the relevant saved authority.
Explicit child policies and representation boundaries remain boundaries.

The mapping preserves the physical tree and actual control owner. Layout,
clipping, modal ancestry and focus do not move to an arbitrary descendant.
Projection, invocation, Value, Text and item capabilities consult the same
accepted semantic mapping. A directly framed root keeps window endpoint zero
separate from its identified semantic child; the window cannot inherit the
child's actionable capabilities.

Reconciliation publishes frame metadata after native field-chrome construction
ownership is released and Button adoption completes its original checks.
Generated field chrome cannot carry frame declaration/publication state,
metadata mutation state or authored action history. Its closed-payload check
includes all seven new frame/action fields. Ordinary retained controls are not
subject to that fresh-recipe restriction. Secure input continues to retain its
real controller and password authority across callbacks.

The integrated candidate has 77 frozen regression methods: 72 original frame
methods plus five inventory tests. These include a real framed TextField whose
setter synchronously rebuilds the host and must publish both chrome and frame
metadata. The first build stopped on test-fixture result-builder and access
errors before any method ran. A separate correction preserves all expectations,
uses an existing exact lifecycle alias, and exposes the unchanged effective-scroll
getter internally. The corrected candidate compiles, but focused execution at
`87f8735` failed. Across two disjoint selections, 32 methods passed, four
failed, one started without a terminal result, and forty never started. The
missing terminal coincides with a Windows stack-overflow report. These are incomplete focused results, not
a full-suite result. Earlier passing chrome and controller tests do not
validate the new combination.

Three reviewed corrections are now integrated and passed focused execution.
Children-only reconciliation suspends the copied child subtrees and their
actual forwarding owners, keeping the untouched List container available to
its original admission. A separate weak parent anchor publishes newly inserted
frames only after the existing completion checks. Standalone child attachment
publishes after parent membership is established and before registration can
release a staged transaction payload; checked panel assembly is unchanged.

Default labeled Toggle rows now explicitly nominate the actual switch. Grouped
Toggle rows declare both physical edges through their value column. Labels
remain independent siblings, and other grouped control factories are unchanged.
No control role, action handler or descendant-search heuristic moves onto a
layout row. Full-runtime projection preserves label descendants; directly
projecting an installed declared row as a subtree returns its semantic switch.
A declared row used as the actual runtime root retains the neutral window
endpoint zero and a separate actionable switch endpoint.

Eighteen additive methods cover these corrections, while all 77 original
methods remain unchanged. Their first focused build stopped before any test
ran because the new Toggle fixture omitted its C interop import. That import
is corrected separately with all assertions intact. At `a899778`, all 54 selected
methods passed: the original 36 Forwarding methods, including the four previous
failures, and the eighteen additions. Every selected method had one start and
one passing terminal; all three batches exited naturally with full owned
process/resource closure. This selection excludes the Metadata crash and does
not qualify the complete original 77-method group.

Static reconstruction of the captured stack-overflow dump reaches the original
Metadata test through 559 frames. Four Foundation frames require explicitly
documented prologue bridges; the other 555 use PE unwind metadata. The captured
chain spans 1,032,064 bytes and contains exactly 36 finite modifier layers,
matching the original fixture. This supports construction stack pressure,
not infinite recursion. The analysis and its caveats are retained under
`artifacts/frame77-static-unwind-644245323cb5405687845c2995eff0c6/`.

The next correction stores each `ModifiedView` content value in an immutable
box, bounding inline payload growth while retaining its generic content type.
Metadata extraction stays at the original erasure point, outer metadata remains
independent across copies, and child state installs under the original context
and identity. A framework-only field projection preserves the original
read-only DynamicProperty declaration after complete physical-field coverage;
it does not relax installation checks or write installed state into the box.
Fourteen additive tests cover size, copies, metadata timing, identity, lifetime,
local state and installation diagnostics. Their first build at `397ff91` stopped
before execution: the new storage fixture omitted three required canvas
providers and used an effectful Never body inside the inherited result builder.
A separate fixture correction preserves its assertions and the original
Metadata regression. At `1636b23`, that unchanged regression passed, followed
by all eleven Metadata methods and all fourteen storage additions in the
109-method frame selection. The selection completed with 107 passes and two
failures, each with an exact start and terminal. There was no stack overflow.
The change adds one allocation per modifier; it does not remove recursion or
establish performance qualification. No fixture depth or stack-size setting
has changed.

The two remaining failures are the original selected-root composition tests.
Standalone `setChildren` assigns the runtime before writing the final child
table, so its early publication cannot yet validate selected membership.
The integrated correction publishes after that final write, using original
weak parent and incoming-subtree witnesses to reject cleanup changes. It
preserves the real selected Button at endpoint zero, the unchanged-child
no-op, and existing checked reconciliation acceptance. Detached and frame-free
trees avoid the new witness allocation. Nine additive tests cover the boundary,
including identity changes followed by restoration and an existing frame
ancestor over a bare selected child. At `b8b08d5`, all 118 frame methods passed,
including every earlier selector and the nine additions. The focused thirteen
are contained in that selection, not additional distinct coverage. All six
batches had exact starts and passing terminals, natural zero exits, complete
owned closure, and unchanged source pins.

Separately, 67 existing property-installation, state, environment, object and
binding methods passed at the same commit. All completed batches in these
focused runs exited naturally with full owned process/resource closure and
unchanged source pins. The independent state baseline does not turn the
failed frame selection into a pass or qualify the full suite.

The subsequent unchanged collateral selection exposed an integration defect:
frame witnesses make field-chrome binding strict, but a field with authored
children present before capture was incorrectly treated as a failed chrome
recipe. The correction checks only captured constructor shape. An unclaimed
non-template tree uses ordinary reconciliation; an initially eligible or
already-claimed recipe keeps all existing controller, attachment, mutation,
and strict-refusal checks. Five additive methods exercise plain and framed
fields, Button companions, later mutations, attachment restoration, and
claimed-registration reuse. The original eighteen chrome methods remain
unchanged. Execution of this correction is pending.

At `b8b08d5`, the independent secure/controller cohort completed with 228
passes and four failures: the same authored-child failure and three copied
snapshot mapper fixtures. Changing a framed field's controller invalidates
its copied publication; those three fixtures require separate scalar and
framed privacy expectations. No disclosure or passing privacy result is
inferred from their failed snapshot unwraps. Button125, paint20, caret3,
CPU2, and state67 passed independently at that commit. Their overlap does
not provide extra distinct coverage or qualify the failed collateral gate.

Precise scrolling after framed Realize still conservatively refuses an
unchanged, previously admitted frontmost sibling-modal stack. Existing
dirty-layout refusal also remains. Supported modal-stack continuation is
unfinished scope, not a platform exception. This work does not establish full
clipping parity, native UIA/Narrator, GPU presentation, visual parity,
performance or full-suite qualification.
