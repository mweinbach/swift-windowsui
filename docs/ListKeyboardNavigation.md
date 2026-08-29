# List keyboard selection and deferred layout

Keyboard selection can name a row whose retained node exists but whose subtree
has not been laid out. Ordinary focus still requires an attached, available,
nondeferred target. Selecting that row must therefore reveal and lay it out
before asking for focus. Updating the selection and scroll offset alone does
not complete keyboard navigation.

The List action captures its source row, destination row, List scope, original
focus intent, and modal before entering the selection binding's setter. Binding
getters, equality operations, setters, and invalidation callbacks may rebuild
the tree. A surviving row can adopt a new declaration on the same physical
node; a removed, reparented, disabled, or replaced row cannot lend its old
attachment to the action. A newer List action or focus request supersedes the
old action. Accepted selection writes and already applied scroll offsets are
not rolled back when later work becomes incomplete.

`RetainedListNavigationOwner` carries these List-specific attachments. Its
references to nodes and the runtime are weak. ComponentHost prepares adoption
before releasing departing callbacks, redirects the new declaration to the
actual retained row, and finishes the exact adopted owner. Temporary fresh
build nodes do not become keyboard destinations. True departure, unavailable
row or vertical-scroll roles, and host shutdown revoke old attachments.

For a target that is already laid out, the existing focus-then-reveal ordering
is preserved. For a deferred target or ancestor, the same receipt first reveals
the row, then calls the existing bounded `resolvedLayoutFrame(of:)` operation.
Focus follows only after that call and its cleanup return, the original owners
and intent remain current, the actual layout settlement receipt is current,
and the target is no longer deferred. There is at most one preparation query
and one post-reveal query for this action. Each query retains Runtime's existing
GeometryReader convergence limits. No render, UIA Realize, deferred-focus
eligibility exception, dirty-flag clearing, or new general scheduler is used.

The optional List receipt also participates in ordinary focus validation.
An exit callback cannot detach and reattach the same row and then receive focus
through its revoked attachment. Geometry changes during an otherwise valid
ordinary focus transition can cancel the later reveal without changing global
ordinary-focus policy. Public focus, UIA focus, and scroll calls with no List
receipt retain their existing admission paths.

If a matching scrollbar interaction must be cancelled, the List path first
rejects mixed gesture ownership. It publishes cleared pointer and hover owners
before delivering the old exit callback. It checks the original receipt,
pointer sequence, and empty ownership slots again after callback and node
capture cleanup. A nested pointer move can therefore install a new hover owner
without an old continuation erasing it. Timestamped chrome and phase changes
acknowledge only their own mutations; cached observation payloads retire before
the next check. The general pointer-cancellation and UIA paths are unchanged.

A realized target may retain one guarded after-layout reveal through the
existing keyed queue. Replacing an entry releases the displaced captures before
admitting the replacement. Replays use the original receipt and do not enqueue
themselves. An incomplete preparation does not drain another callback round or
retry a consumed receipt.

## Limits and further integration

An accepted animated scroll keeps its existing offset and tween. If the bounded
query still leaves the target deferred, focus remains incomplete. Later guarded
focus completion at animation or layout completion is not implemented by this
slice. This is not complete animated keyboard navigation, and the existing
tween's later lifetime is not newly qualified by the List receipt checks.

These changes do not defer List row construction. Data initializers still
construct every row, while lazy-stack layout bounds recursive layout work.
The dormant provider and extent models remain dormant. The new layout budgets
do not prove bounded construction, physical node counts, or retained resources.

The separate retained lazy-list adapter must eventually join these owner hooks
into its checked adoption and virtualization teardown: adopt only actual
retained rows, finish the captured installed owner, and revoke all retiring
attachments before cleanup callbacks. Selective State/task publication and
logical-only accessibility providers remain separate gates. No part of that
adapter or its public List activation is included here.

The new facade and input regressions are source-only until separately compiled
and executed. They preserve the existing eight List virtualization tests and
all existing focus assertions. Headless rendering can use platform font APIs;
these tests do not establish visible-window, physical-input, Narrator, visual
parity, performance, or native animated-focus qualification.
