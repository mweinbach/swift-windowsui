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
document object. Sixteen added tests cover these local rules but are not yet
compiled or executed on the integrated source.

Owner checks here describe actor-side ownership, not native readiness. Native
attachment quiescence can revoke its session before the actor callback context
is cleared, so a direct package range read may remain available during that
interval. Existing native request publication separately requires its session
and complete-call lease. The new internal request cases have no native callback
or COM registration and do not advertise TextPattern. Native held-range teardown
and complete provider behavior remain open qualification work.

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
