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
`87f8735` is failing. Across two disjoint selections, 32 methods passed, four
failed, one started without a terminal result, and forty never started. The
missing terminal coincides with a Windows stack-overflow report; its Swift
caller has not yet been identified. These are incomplete focused results, not
a full-suite result. Earlier passing chrome and controller tests do not
validate the new combination.

Source review has identified three independent behavioral gaps: children-only
frame adoption suspends List ancestor metadata that its own admission still
needs; default labeled Toggle rows do not explicitly nominate their actual
switch as semantic content; and direct child attachment attempts publication
before the parent has appended that child. Corrections are in progress with
the original failed assertions preserved. The stack overflow is being
diagnosed separately, without reducing fixture depth or enlarging the stack
as a claimed behavioral fix.

Precise scrolling after framed Realize still conservatively refuses an
unchanged, previously admitted frontmost sibling-modal stack. Existing
dirty-layout refusal also remains. Supported modal-stack continuation is
unfinished scope, not a platform exception. This work does not establish full
clipping parity, native UIA/Narrator, GPU presentation, visual parity,
performance or full-suite qualification.
