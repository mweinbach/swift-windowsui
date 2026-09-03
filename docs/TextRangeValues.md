`SwiftWindowsCore/TextRangeValues.swift` provides package-only, immutable text and
index values. The reviewed Calendar+Text candidate uses them for an internal
plain-text copy request, not a TextPattern implementation or a change to the
supported compatibility surface. The Core helper imports
Foundation and reuses Swift `String.Index` and `Range<Int>`; it does not import the
Windows host, retained editor, or renderer.

`TextRangeSpan` stores ordered Swift Character offsets and a declared Character
count. Checked construction rejects invalid or reversed endpoints; selection
construction clamps and orders an anchor and extent. Replacing an endpoint
across its peer collapses the peer to the replacement. Copies, equality, and
endpoint comparisons describe numeric values only. Matching lengths do not
establish document identity, provider ownership, or an editor revision.

`TextRangeSnapshot` copies the source String and records its exact Character
boundaries in both String indices and UTF16 offsets. Conversion rejects UTF16
positions inside a Character, including a surrogate pair, combining sequence,
ZWJ sequence, or CRLF. Text extraction preserves the original code units,
including embedded NUL and line endings. It does not normalize, reshape, reorder,
mask, or sanitize the input. The snapshot cannot represent ill-formed UTF16 or a
native endpoint inside a Swift Character.

These retrieval and search choices are this helper's policies:

| Operation | Local policy |
| --- | --- |
| `getText` limit | `maximumUTF16Length` measures UTF16 code units. `-1` returns the complete range, `0` returns an empty String, and values below `-1` throw `invalidMaximumLength`. A nonnegative budget returns the longest prefix ending on a Character boundary, so it may underfill the budget or return empty when the first Character is too long. |
| `findText` direction | Enumerate forward Foundation matches and return the first or last eligible occurrence by logical start, including overlapping occurrences. The original range end stays fixed. Only matches wholly inside the span with both endpoints at Character boundaries are eligible; partial matches are skipped, never expanded. This does not adopt Foundation's `.backwards` tie-breaking. |
| `findText` comparison | Use Foundation `.literal`, optionally `.caseInsensitive`, with an explicit `en_US_POSIX` Locale for each call. No process or thread locale is changed. This is not Windows ordinal matching and does not promise behavior for every Unicode folding case across Foundation versions. |
| Empty search | An empty needle throws `emptySearchText`, including for an empty source or span. A nonempty needle in an empty span returns no match. |
| Mismatched lengths | Retrieval and search throw `incompatibleLength`; index conversion and unit operations return nil. Equal lengths still require the caller's separate document and revision checks. |

Microsoft's native
[GetText documentation](https://learn.microsoft.com/en-us/windows/win32/api/uiautomationcore/nf-uiautomationcore-itextrangeprovider-gettext)
specifies a maximum length and `-1` for all text, but does not define the
Character-safe truncation policy above. The
[managed provider contract](https://learn.microsoft.com/en-us/dotnet/api/system.windows.automation.provider.itextrangeprovider.gettext?view=windowsdesktop-10.0)
also rejects values below `-1`; that does not choose a native HRESULT for this
helper. Native
[FindText documentation](https://learn.microsoft.com/en-us/windows/win32/api/uiautomationcore/nf-uiautomationcore-itextrangeprovider-findtext)
defines direction, range containment, and case sensitivity without prescribing
this helper's locale, normalization, empty-needle, or Character-alignment policy.

A future adapter must decide explicitly whether these operations meet its native
contract. It can use the checked boundary and span values without calling
`getText` or `findText`, and must reject or replace a policy operation if native
qualification requires different behavior. These package methods do not install
a policy into the runtime or force an adapter to use it. No helper error is an
HRESULT, and no range value is evidence that a native call is authorized.

`TextRangeUnitBoundaries` accepts a copied, strictly increasing table that starts
at zero and ends at the declared Character count. The empty document's sole
table is `[0]`. The caller supplies the actual linguistic, visual-line, format,
page, or document boundaries and any fallback between unsupported units. There
is no word breaker, text shaper, or second layout engine here. Swift Character
boundaries are index validity boundaries, not a claim that every Character is a
UIA `TextUnit_Character`: UIA's
[text-unit definition](https://learn.microsoft.com/en-us/windows/win32/winauto/uiauto-uiautomationtextunits)
distinguishes navigable characters from control characters.

Expansion chooses the interval containing the start; an exact ordinary boundary
chooses the following interval. The helper's explicit EOF policy chooses the
last existing interval, while an empty document stays empty. A degenerate move
steps supplied boundaries and can reach EOF without becoming nondegenerate.
A nonempty move translates from the interval containing its start and returns
one destination interval. A zero requested count or zero achievable translation
leaves the original range unchanged. Endpoint movement counts the first crossed
boundary once and collapses the other endpoint on crossing. Counts clamp before
arithmetic; `Int.min` is never negated. These algorithms follow the shape of
[Move](https://learn.microsoft.com/en-us/windows/win32/api/uiautomationcore/nf-uiautomationcore-itextrangeprovider-move)
and
[MoveEndpointByUnit](https://learn.microsoft.com/en-us/windows/win32/api/uiautomationcore/nf-uiautomationcore-itextrangeprovider-moveendpointbyunit),
but the EOF and unachievable-move policies must be checked by the eventual
provider's qualification rather than inferred as universal UIA requirements.

`TextRangeValueTests` freezes finite value examples covering exact UTF16
boundaries, combining marks, ZWJ sequences, bidi text in logical order, CRLF, NUL,
empty values, invalid endpoints, clamping, crossing, copies, comparisons,
retrieval limits, first/last search, explicit unit tables, and signed extremes.
All twenty-five methods compiled and passed in the focused selection on
`1be9295`. The whole 118-case run still had one unrelated restored-button
diagnostic failure; it was not a full-suite pass.
Those tests do not establish complete Unicode search behavior, provider
authority, text-generation tracking, editor behavior, or native ABI correctness.

The candidate's optional internal text-snapshot request returns copied stored
text from a currently attached, projected plain-text element. It does not use
an accessible label or value as document content, and it does not read an
editor binding. Missing capability or denied content returns no text. The read
does not change selection, resolve layout, scroll, or realize a deferred row.
Ordinary disabled or offscreen plain text remains eligible; hidden, private,
redacted, modal-excluded, editor, secure, and lazy content is refused.

The source rechecks the original weak attachment and exact UTF16 content after
temporary node and projection references have been released. Detaching and
reinserting the same node cannot repair that request. A copied snapshot does
not retain the view or runtime, authorize a later provider call, or supply
selection or geometry. Selected-content projection must still expose the
actual text child; wrapper metadata is not substitute document text.

On 2026-09-03 at `cdef928` and again at `5a8e828`, all 19 plain-text request
and selected-content snapshot tests passed. These are retained in-process ownership and content
checks, separate from the earlier value-only results above. No native
TextPattern is advertised, and no COM, Narrator, editor, or IME qualification
follows from the internal copy.

An additional internal `UIATextDocument`/`UIATextRange` contract now retains a
copied snapshot together with weak original attachment, selected-path, source
and provider-owner observations. Each read, clone and endpoint comparison
checks that original authority; an observed refusal permanently invalidates the
document. Exact UTF16 text changes retire a separate content token, so changing
A to B and back to A cannot revive an old range. Assigning identical code units
keeps it valid. Ranges are immutable, and comparisons currently require the same
document object. All sixteen `UIAHeldTextDocumentTests` compiled and passed on
2026-09-03 at `85ddfe8` in `FocusedFoundation40`, with zero failures in the
[held-test output](../artifacts/focusedfoundation40-b3c716977aae48c0a352e0f1adadfa9b/batch-01.log).
The [aggregate result](../artifacts/focusedfoundation40-85ddfe8-results.json)
records all 40 selected tests passing. These are local in-process actor-side
contract checks, not a full-suite or native qualification result.

Owner checks here describe actor-side ownership, not native readiness. Native
attachment quiescence can revoke its session before the actor callback context
is cleared, so a direct package range read may remain available during that
interval. Existing native request publication separately requires its session
and complete-call lease. Direct actor document/range requests still have no COM
registration and do not advertise TextPattern.

The native held-text read candidate adds a separate optional callback table and
an internal IUnknown-only handle for acquire/read/release. It exposes neither
ITextProvider nor ITextRangeProvider. Each handle retains its original native
context and a non-reused ticket; the bridge alone stores the corresponding
actor range. Native reads enter the unchanged session and complete-call lease
path, so native quiescence rejects them even while the direct actor control
above can still read. Final handle release queues only the ticket for actor
cleanup and never waits for the actor. Terminal bridge revocation closes the
store before its weak callback link is cleared. A failed acquisition retires
its preissued ticket only after synchronous actor registration has completed,
including when the reply is suppressed. Allocation failure before registration
creates no record. Existing callback table layouts and typed Invoke behavior
are preserved.

This adapter explicitly selects the Core helper's UTF16-budget/Character-safe
truncation policy; that is still not native text-unit qualification. It maps a
maximum below -1 to E_INVALIDARG, denied authority to UIA_E_ELEMENTNOTAVAILABLE,
and allocation failure to E_OUTOFMEMORY. Empty eligible text is a nonnull empty
BSTR, not a denial. Checked exact UTF16 length preserves embedded NUL. Acquire
requires exactly S_OK after registration; unexpected positive callback results
are E_UNEXPECTED, with failed complete-call status taking precedence.

Native output permission linearizes at the final call-status load after BSTR
allocation. Revocation observed there suppresses the result. This does not
promise suppression for revocation racing between that load and the following
output-pointer store, nor for arbitrary UI mutations after the actor snapshot.
The complete call remains retained through output cleanup/publication; merely
holding a read handle retains no permanent call and does not block quiescence.

All twelve `UIANativeTextReadTests` methods compiled and passed on 2026-09-03
at `ffd035d`, alongside 56 unchanged held-document, call-lease, native-request
and actor-dispatch tests. The three serial batches had exactly 68 starts and
passing terminals, with natural exit 0, complete owned cleanup, and no skips
or timeouts. The [aggregate result](../artifacts/native-held-text68-ffd035d-results.json)
and [raw output](../artifacts/native-held-text68-75b1e98e200046a681d32f69f9006270/)
record this local headless C-helper, retained-source and actor-dispatch evidence.
The earlier `e74e2bd` build failure remains preserved: static helper names in
C callback closures required explicit type qualification; no test assertions
changed. Neither run establishes installed UIA, COM TextPattern, Narrator,
full-suite or native-window qualification. The preceding sixteen actor-test
results retain their narrower historical scope.

All work required for real TextPattern remains open: retained TextEditor and
TextField selection and composition integration; text and geometry revisions;
password and disabled/read-only enforcement on every live and held-range call;
binding reentrancy and owner validation; Character/UTF16 and native unit
qualification; per-line and bidi selection rectangles; point-to-range and
visible-range queries; reveal and top/bottom scrolling; text attributes and
embedded children; text and selection events; all ITextProvider and
ITextRangeProvider methods; safe COM identity, allocation, leases, and teardown;
and installed/native automation plus Narrator qualification. In particular, the
existing element-selection provider cannot be treated as text selection merely
because its COM method has the same name. The values neither mask secure text
nor attach lifetimes to snapshots; callers must not disclose a stale or
unauthorized snapshot through future providers. No completion requirement in
`goal.md` is narrowed by this dependency.

The integrated follow-on adds internal held-handle clone, equality and
endpoint-order queries. It still exposes no native text pattern or text range
interface. A clone has an independent ticket and range record while sharing the
original document authority. Peer operations revalidate both original documents,
their weak provider ownership, and exact immutable UTF16 contents. Runtime
documents from separate acquisitions are compatible only when their original
weak source, runtime and physical node, content token, attachment and selected
path still agree. Equal text or automation IDs do not establish compatibility.
Existing object equality and the original same-document endpoint method keep
their earlier semantics; the new compatibility operation is explicit.

The new paired checks finish with callback-free reads of both documents'
terminal invalidation flags, so a final callback cannot hide an already observed
peer refusal. These flags do not establish simultaneous freshness for arbitrary
custom package authorities that silently mutate each other. The concrete Runtime
path reads stored eligibility/attachment/installed-selection state and projects
metadata without invoking authored getters, actions or layout; projected actions
retain weak nodes/scopes rather than authored handlers. This source audit does
not turn the generic authority protocol into an atomic multi-document validator.

Native peers are resolved through a private IUnknown identity interface before
the actor looks up their original tickets in the same context's store. This is
an interoperability check, not new request admission. Complete-call/session
validation, synchronous registration rollback, numeric retirement and the final
status-load publication boundary remain unchanged. Foreign origins are
E_INVALIDARG; stale origins are UIA_E_ELEMENTNOTAVAILABLE. Comparisons return
only equality or -1/0/1 ordering, without claiming native text-unit distances.
The separate optional operations table preserves the existing callback layouts,
old factories and typed Invoke result.

All twelve `UIANativeTextRangeTests` methods compiled and passed on 2026-09-03
at `2d61cdd`, alongside all 68 unchanged held-document, native-read, call-lease,
native-request and actor-dispatch tests. The four serial batches had exactly
80 starts and passing terminals, natural exit 0 and complete owned cleanup,
with no skips, timeouts or source changes. The
[aggregate result](../artifacts/native-range80-2d61cdd-results.json) and
[raw output](../artifacts/nativerange80-ddf9ac7ab24846fb98b1eb926756d2c3/)
record headless C-handle and actor-dispatch evidence, not installed UIA,
ITextRangeProvider, Narrator, live-window or full-suite qualification. Strict
lint and contracts also passed. Formatting preserved every test method and
assertion; the separately reviewed fixture cleanup changes retained the
preimplementation oracles.

This prerequisite does not complete Microsoft's
[TextPattern contracts](https://learn.microsoft.com/en-us/windows/win32/winauto/uiauto-implementingtextandtextrange).
Plain-label layout currently discards fragment source mappings after wrapping
and truncation; editor geometry preserves a different whitespace policy and
cannot substitute for the rendered label's geometry. Actual visible ranges,
point/range mapping, rectangles, reveal, attributes, embedded children and text
events remain open. Character and Document units are required by the
[TextPattern overview](https://learn.microsoft.com/en-us/dotnet/framework/ui-automation/ui-automation-textpattern-overview);
fallback to Document alone is insufficient. No-selection plain text may report
SupportedTextSelection_None, but that does not excuse missing nonselection
methods. The native/display harness remains outside this candidate's scope.


### Ordinary layout source positions

The ordinary-label mapping loss described at the native-range80 checkpoint
is addressed by this later prerequisite. Its validation remains separate.

Ordinary text layout now retains internal provenance for the exact String already
submitted to layout. The source value records its UTF16 length and units; final
lines distinguish copied, replaced and generated output segments. Empty line
anchors are retained only when their original coordinate is unique and remains
ordered with surrounding source ranges. Anchors never consume source coverage.
Unrepresented
source ranges include hard breaks, collapsed whitespace and truncation gaps;
they are not a visibility or offscreen result. Raw scalar/UTF16 coordinates do not
become Character units, caret stops or native cluster boundaries.

The layout cache compares source text by exact UTF16, so even equal-length
canonically equivalent strings cannot borrow each other's source coordinates.
Identical code units still reuse the cache. Fragment width-probe equality and
hashing continue to ignore new empty-anchor metadata. Final projection assembly
shares one immutable source-unit buffer and scans only final output fragments.
No classification or source snapshot is added to the inner wrapping/width-probe
loops, and no extra native layout is requested. A caller using ordinary
NativeTextRenderer.layout for measurement still receives final-result provenance.

Provenance is optional. Missing/invalid line metadata, conflicting source order,
or an exact fragment/line mismatch clears the whole projection while preserving
the drawable text, glyphs and metrics. A partial result cannot produce a global
source complement. Existing synthetic layout overrides remain unqualified unless
explicitly passed through the same production assembly helper.

This records values within the existing text-layout/cache ownership. It reads no
node, binding, editor controller or raw secure value. Secure-field display input
remains masked before it reaches layout; metadata preserves only that submitted
input. It adds no UIA read authority, session/lease bypass, native callback or
TextPattern advertisement. The previously recorded native-range 80-test result
is unchanged and does not qualify this later change.

Sixteen new TextLayoutSourceProvenanceTests are frozen, including exact canonical
variants, generated and replaced segments, hard-break anchors, control-only source
extents, scalar precision, independent invalid mappings and unchanged drawing/
probe behavior. The original freeze is preserved alongside its approved additive
assertion amendment. These tests and the source change have not yet been compiled
or executed in this private preparation; toolchain formatting and parent serial
validation remain pending.

Character/Document semantic units and source-mapped geometry remain separate work.
A nonempty control-only source can have zero navigable Character units, which the
existing interval partition alone cannot express. A future semantic map must
separate source extent from explicit navigable spans and distinguish unavailable
from a known empty list. Real geometry still needs the actual selected native
layout's hit metrics, retained placement/clipping and current ownership; existing
editor wrapping or glyph-start approximations are not replacements. Full native
TextPattern methods, events, editor/selection/IME integration and qualification
remain open.
