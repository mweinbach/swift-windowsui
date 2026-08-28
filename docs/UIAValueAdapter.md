# Retained UIA whole-value replacement

`RuntimeUIAElementTreeSource.uiaSetValue` now selects the internal
`TextInputAccessibilityValueReplacing` capability of a retained `TextField` or
`TextEditor`. This joins the shared admission described in
[AccessibilityMutationAdmission.md](AccessibilityMutationAdmission.md) to the
editor operation described in
[AccessibilityTextReplacement.md](AccessibilityTextReplacement.md). The earlier
slice descriptions intentionally recorded an unwired capability and provisional
raw-input adapter; this increment replaces that adapter path.

There is one original binding submission. The adapter does not synthesize
Ctrl+A, Backspace, an IME commit, a selection-binding write, or a second text
effect. It does not assign the requested string directly to accessibility
metadata. Authored display and metadata continue to come from the editor and
its binding. Selecting a capability never authorizes a raw-input fallback,
including when the setter normalizes, refuses, or commits the value before a
later ownership check fails.

## Admission and continuation

The runtime's existing synchronous mutation scope remains closed across the
entire operation. Another adapter for that runtime cannot enter Invoke, Value,
SelectionItem, Toggle, SetFocus, or Realize from a focus callback, setter, or
capture destructor. The source keeps only a weak runtime between calls and
temporarily pins it during an admitted call. Ordinary application focus and
binding writes keep their existing behavior; this is not a global UI lock.

Before checked accessibility focus can run layout or application callbacks,
the adapter captures the original physical attachment and original controller.
The controller's capability is the chosen handler, rather than a raw keyboard
or IME closure. A focus callback that replaces that controller cannot lend the
request to the replacement. The existing focus transition still uses runtime
layout and prepaint authority, including its bounded callback checks.

The controller receives two synchronous checks. Before submission, the exact
original controller must still be installed. After possible effects, a
compatible controller may survive the same retained attachment; the capability
itself verifies its editor attempt, history session, or document endpoint.
Neither adapter check reads a binding, invokes another controller's methods,
runs layout, or schedules a retry. Both preserve the original focus revision,
including detecting an ordinary away-and-back request to the same node.

Normal text completion deliberately invalidates layout. Its continuation
therefore cannot require the pre-edit settled-layout or prepaint receipt to
remain current. It checks stored physical attachment, focus, visibility,
removal, virtualization, enabled state, input role, security, and projection
membership instead. The root-only accessibility projection supplies semantic
membership, not geometry or replacement prepaint authority. It reads already
constructed retained children and metadata without evaluating view bodies,
virtualized suppliers, action closures, or binding getters.

A compatible value submission can rebuild a focused `TextField` before the
next accessibility request. While that exact submission still owns its staged
selection, reconciliation prepares the incoming field's caret and selection
rows from constructor-cached text and style and the retained editing snapshot.
This prevents predictable framework chrome work from invalidating the next
request's normal layout query. It does not add a query, retry, binding read, or
selection-binding write, and it leaves the runtime's settlement checks intact.

Preparation is limited to the never-attached construction candidate and its
unchanged framework label. It appends fresh framework rows without changing
the live target's children; an unexpected or reused child tree is left alone.
Secure fields and multiline editors do not use this preparation. Arbitrary
application mutation during a later query can still invalidate that request;
preparation does not turn the cached constructor text into binding provenance.

## Conservative modal qualification

A modal marked `isAccessibilityHidden` still blocks ordinary input even though
the root-only accessibility projection omits it. That projection alone is not
an input-modal authority. The adapter additionally walks the physical retained
tree without accessibility filtering. Every modal scope must enclose the
original target. Hidden, clipped, deferred, and removal-overlay scopes are
included conservatively; malformed parent links or a traversal exceeding the
retained depth limit refuse the request.

This deliberately rejects some legitimate frontmost editors when a sibling
modal remains in the physical tree, including a clipped sibling that currently
paints nothing. It is not equivalent to the renderer's draw order or culling
policy. Exact post-edit modal qualification without another layout call remains
open. The conservative refusal never authorizes a retry and does not undo an
already committed binding or document action.

## Completion and lifetime

The dispatch helper pins the original controller until it constructs a small
completion receipt. That receipt contains the effect result, weak controller
and target references, attachment identities, and scalar revisions. It contains
no binding, application closure, or runtime owner.

The helper then returns while the shared mutation scope is still closed.
Retiring the original controller can release arbitrary binding captures. The
outer frame checks the completed controller, attachment, focus revision, and
the mutation revision captured after the editor's own effects. A destructor
that closes the host, changes focus, replaces the editor, or invalidates the
runtime cannot become part of an earlier successful receipt. An internal,
callback-free capability property also reads the existing current-controller,
attachment, and owner-valid flags. Calling `revokeOwnership` or `detach`
directly cannot hide retirement behind an unchanged node slot or focus. This
property is not an edit receipt or Binding identity and does not promise
consistency across silent arbitrary model mutation. Retired local editor
history cannot write through that controller; an already accepted document
model inverse remains owned by its still-live document session.

The adapter returns true only when the capability reports both a submitted
write and acceptance, followed by these final availability checks. False can
follow focus callbacks, a real text effect, or a committed document inverse.
`didDispatch` is an internal submission fact, not proof that an arbitrary setter
accepted the requested bytes. The public Boolean result is not a rollback,
native HRESULT, or a request to repeat the operation.

Before the final original invalidation callback, a still-current original
controller publishes the text already observed from its selected binding into
the retained accessibility value (nil for empty text). A custom binding with
a no-op invalidation therefore has immediate Value-pattern readback without a
body rebuild or an added getter, layout query, or render. A normalizing setter
publishes its observed result even when it rejected the requested bytes; a
refused or interrupted attempt does not invent a value from the request.
A compatible replacement controller keeps the metadata produced by its own
construction, and the final application callback can replace that metadata
without a later write from the old attempt. This preserves the previous
adapter's automatic value-publication policy; it does not add provenance for
an explicit accessibility-value override on an unchanged controller.

## Supported controls and remaining boundaries

Secure fields never select this capability through the adapter and expose no
Value pattern or plaintext value. A nonsecure edit element may still expose
the readable Value pattern, but its snapshot is read-only when it has no
supported internal capability or is disabled. Raw nodes and custom
`RetainedTextInputController` implementations without that capability receive
no synthesized input. An arbitrary binding can still be constant, normalize
input, or reject a write; snapshot metadata does not invent setter provenance
or a guarantee that every proposed string will be accepted.

Nil undo managers and disabled registration do not remove the editor's attempt
ownership. Document-backed bindings keep their existing document-owned history
and selection sidecars rather than acquiring a duplicate local inverse.
The existing `.id(documentSessionID)` boundary remains necessary for arbitrary
equal-text custom-binding rebinding. This increment does not enable native
DocumentGroup activation or change document close, IO, or save policy.

`UIAValueAdapterTests`, `UIADocumentValueAdapterTests`, and
`UIAValueAdapterCaptureLifetimeTests` exercise the real adapter with public
controls in an offscreen host, fake presenters, and synthetic text metrics.
The document fixtures use real session projections and a service that refuses
all file and dialog operations. The separate provisional-routing fixture
overlay preserves the shared admission and lifetime checks while replacing the
obsolete Ctrl+A expectation with a single built-in editor write and zero raw
input events. Frozen dependency tests remain recorded separately.

`UIAFieldChromeAdoptionTests` adds consecutive requests without an intervening
frame, original-getter identity, selection, style, composition, secure-field,
and unexpected-child lifetime fixtures for the field preparation boundary.

`UIAValuePublicationTests` covers immediate retained and in-process COM value
readback, custom setter outcomes, replacement and final-invalidation ordering,
and refusal without publishing a secure or retired editor's value. The
existing real TextField Value-pattern fixture remains unchanged.

Source review, contracts, and formatting do not establish that these fixtures
compile or pass. Execution must be recorded after integration. COM apartment
marshalling, disconnected providers, native scheduling, Narrator, native focus,
and visible window or DirectWrite behavior are not qualified by these headless
fixtures.
