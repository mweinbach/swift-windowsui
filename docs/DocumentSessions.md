# Document sessions and the shared text editor

This is an internal, headless document-hosting stage, not an enabled native
document application. `DocumentGroup` now declares typed document factories
and builds a writable `FileDocumentConfiguration` for each materialized
window. The coordinator requires explicit injected headless services, host
creation, and lifecycle hooks. Default native activation fails before model
creation or file access, including direct `WinSwiftUIWindowHost.run()`.
The executable's `AppEntry` remains unchanged.

`DemoDocumentScene` is shared SwiftUI-shaped source. It declares a
`DemoPlainTextDocument` and passes `configuration.$document` to
`DemoDocumentEditor`, which owns its selection with mounted `@State`. It does
not call Windows-only save/open APIs or manufacture a successful save. Native
close finalization, an owned deferred wake, decision presentation, and real
application command integration must be integrated and tested before this
scene can become a default Windows application template.

## Declaration, ownership, and configuration

The `DocumentGroup(newDocument:content:)` initializer retains a factory without
invoking it while collecting scenes. The editing overload requires the shim's
fixed `FileDocumentReadConfiguration` and `FileDocumentWriteConfiguration`
associated types. Viewing requires only the fixed read configuration and
never calls the writer. Editing/viewing declarations without a new-document
factory require actual file input; they do not decode a fabricated empty file.
There are no forced casts of associated configurations.

`FileDocumentConfiguration.document` is a bound model value, with the standard
`$document` projection. Its initializer still accepts a `Binding<Document>`.
A viewing configuration limits the underlying binding, so changing
`isEditable` on a copied configuration cannot grant write permission. Apple's
[document configuration](https://developer.apple.com/documentation/swiftui/filedocumentconfiguration/document)
also ties the writable document binding to change and undo tracking.

The coordinator installs a document context, its one undo manager, scene
storage, and environment actions before the host's first content build. Each
new window receives a separate session and owner lease. Exact standardized
file URLs within the same declaration reuse an existing window; this is not
file-identity, case-alias, symbolic-link, or external-change coordination.
Open/New requests retain the requesting window's identity and revision through
dialog selection, type getters, decoding, host construction, and startup.
An obsolete requester cannot admit a new document window or publish a late
error into a replacement one.

An escaped document binding may keep its last model readable, but it does not
retain the host or its write authority. Explicit close and isolated host
deinitialization revoke owner and editor capabilities before mounted State
and history payloads are released. Removing one session's actions does not
clear another window's or an application's actions from a shared manager.

## Regular UTF-8 files

The first codec supports `.txt` input declared as `.utf8PlainText` or
`.plainText`. The shared sample uses `.utf8PlainText` and a value type whose
only stored model data is a `String`. Its decoder rejects malformed UTF-8
instead of accepting replacement characters. Valid byte sequences retain a
BOM, decomposed characters, line endings, whitespace, and embedded NULs in
the file contents. Layout does not rewrite those bytes; the existing paste
normalization policy is separate.

The hosted stage caps regular-file input at **16 MiB** and permits a smaller
injected test boundary. `LiveDocumentFileService` reads in bounded chunks and
uses one overflow byte to detect an oversized file, then closes the handle
before calling the document decoder. This input bound does not cap later
model edits, saved output, or retained history. Directories,
unsupported wrappers, invalid file URLs, and oversized input fail instead of
being interpreted as empty content. `FileWrapper.isRegularFile` is only a
wrapper-representation query: empty `Data` is regular; nil data, directory
children, and malformed mixed wrappers are not. It makes no filesystem type
or security guarantee.

Serialization is synchronous on the main actor in this stage. The typed
codec rejects undeclared content types and packages. It passes
`existingFile: nil` to the application's writer and validates the returned wrapper; the
sample returns a fresh regular-file wrapper. Unrelated destination bytes are
never supplied as an `existingFile`. The shared exporter and document service
use the same atomic write helper. Foundation's atomic option is not a promise of power-loss
durability. Filesystem races, aliases, concurrent writers, coordinated access,
large-document responsiveness, and asynchronous non-Sendable ownership are
not qualified here.

## One model history and saved checkpoints

Each session owns value inverses in its stable manager. A direct write through
the document binding registers one model action. An accepted editor write
carries an explicit mutation ticket through generated binding projections and
registers that same model action; it does not also register an ordinary text
delta. Equal projected text is not used to guess whether a computed setter
changed another model field. Nil or disabled history registration still
permits accepted model edits without inventing an undo action.

The editor attaches optional before/after selection only to its exact accepted
action receipt. A subsequent direct assignment cannot acquire that selection
by becoming the manager's top action. Reconciliation uses the latest document
and editor owner. Losing an optional selection endpoint does not erase a
model action already accepted. Active composition blocks document replay.
Managed secure text input is unsupported and rejects writes rather than
storing plaintext model history; ordinary secure inputs retain their existing
behavior. Subtree undo-manager overrides do not replace the session's model
authority and are not a native behavior claim.

Selection restoration is conservative. It settles editor eligibility before
reading application bindings, then checks an optional monotonic runtime stamp
without another layout query. Any observed invalidation or layout pass after
capture, an exhausted stamp, changed explicit selection, or retired endpoint
refuses the optional restore. It does not claim to detect silent arbitrary
getter side effects. The model action still belongs to the session.

Dirty state compares the current checkpoint's identity with the saved
checkpoint. Every accepted model assignment creates a checkpoint; undo/redo
restore the corresponding checkpoints while mutation revisions keep
increasing. Saving does not erase history. Undoing to the saved checkpoint
becomes clean, and creating another branch at the same stack depth does not.
Known class-shaped documents and `ReferenceFileDocument` reject activation.
A struct containing mutable reference aliases has no automatic value-inverse
safety guarantee. The concrete UTF-8 value document is the supported model.

## File operations and close intent

A save owns a ticket with owner generation, session identity, operation
identity, and mutation revision before any application callback. The ticket
is checked around dialog selection, before and after serialization, and just
before the atomic write. Cancel, native failure, serialization failure, write
failure, and superseded ownership remain distinct. Rejected stale operations
cannot change existing bytes or clear dirty state. The requesting host's
explicit HWND ownership travels with native dialog requests; no global
mutable active owner is introduced.

A successful write returns an exact byte/destination receipt. If a newer edit
occurs after that write, the receipt still records the actual save and the
new model remains dirty. If the owner retired after the write, a superseded
result may retain that receipt but cannot apply URL/checkpoint metadata or
send a late window callback. Normal save actions do not infer success merely
from choosing a URL. Errors remain visible in the retained document host and
can be retried without replacing its editor identity.

Explicit error clearing and the start of a save retry keep the displaced
error alive until its stored-property mutation ends. The payload is then
released before change publication. A destructor that recursively clears the
error sees nil; one that reserves a clean close blocks the subsequent
publication through the existing reservation check.

Dirty close uses a separate intent identity. Repeated requests reuse the
pending decision; Save, Discard, and Cancel have distinct outcomes. Save can
approve only the current persisted revision. Discard approves without writing
or pretending the dirty model is clean. New edits, unrelated file operations,
and a changed host dismissal policy revoke queued approval. A final callback-free
reservation must consume an exact approval after all host/delegate decisions,
and must block model writes, undo, and file operations during synchronous
destruction callbacks. Failed destruction releases the reservation without
reviving the consumed approval; actual teardown alone closes the session.

This stage exercises that protocol through an explicit headless commit seam.
It does **not** use an ordinary second `WM_CLOSE` as a save approval or enable
native document destruction. The stack's native close and build-settlement
primitives coexist with this stage, but the document session does not register
a native close participant. Document-specific retry delivery, final reservation
across `DestroyWindow`, and decision UI remain required integration work.
`windowDismissBehavior` continues to veto ordinary closes, and a veto never
discards unsaved data.

Three integration rules keep the headless model protocol separate from native
activation. Typed host validation starts when a descriptor or prepared context
is present and retains every identity, ownership, and native handle check. A
legacy document marker without either remains an unadapted raw host; its close
queries still reject before flushing pending work or resolving layout. Native
startup rejects every document marker, descriptor, or context. Both built-in
startup hooks run that preflight before changing native window state or calling
the platform factory; custom injected headless hooks retain their behavior.

A direct Boolean close query can reach a bound document model only while its
native handle is absent. It always returns false for that document, including
when a pending-reload callback already tore down the host. A clean model can
record an approval without IO, cleanup, or a write reservation; the explicit
headless commit is still required. Dirty-model publication can rebuild authored
content, but it does not authorize native destruction.

## Validation boundary

`DocumentFileServiceTests` covers bounded real reads and atomic writes in owned
temporary directories. `FileDocumentSessionTests` covers model history,
checkpoints, save outcomes, reentry, retirement, and close reservations.
It also exercises recursive error clearing during explicit dismissal and a
save retry without retaining the failed result outside the session.
`DocumentTextUndoTests` isolates binding provenance and selection receipt
transport through real retained controls with a synthetic owner.
`DocumentSessionEditorIntegrationTests` joins the real model session and
retained editor. `DocumentGroupHostingTests` covers typed scene materialization,
first-build context, independent windows, routing, and teardown.
Its integration regressions also cover teardown during the close query's
pending-reload flush, rejection of partial metadata, and the unadapted marker's
startup guard. A refusing platform factory checks that the built-in platform
hook never starts a document window and still receives ordinary-window startup.
The Win32 hook's corresponding guard ordering has source review only. Existing
native-close guard fixtures remain unchanged.
`DemoDocumentTemplateTests` covers the shared strict codec and mounted editor
source. These suites need serial compiler and test execution; authored cases
alone do not establish a passed result.

No model or headless test substitutes for native keyboard, IME, Narrator,
wheel/UIA editor scrolling, pinned macOS behavior, actual file panels, or a
complete open/edit/undo/save/unsaved-close workflow. See
[TextInputUndo.md](TextInputUndo.md), [TextEditorNavigation.md](TextEditorNavigation.md),
and [FileDocumentExport.md](FileDocumentExport.md) for the underlying bounded
capabilities.
