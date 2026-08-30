# Local UTF-8 file preview

`DemoFileBrowserTemplate` supplies one working local-file workflow: import or
drop file URLs, select a file, read a bounded UTF-8 preview, and cancel or retry
that read. The same view source uses native SwiftUI on macOS and WinSwiftUI on
Windows. It reuses the demo's styles and public controls. This is a partial
media/file-browser template; it does not complete goal section 7.

The component gallery includes the browser in its Controls collection. Search
for `file preview`, `utf8`, `import`, or `retry` to find it. `DemoWindowState`
owns a separate browser model for each window, while existing dashboard and
gallery preferences retain their existing ownership. No data-tab or settings
import action is repurposed by this slice.

The default demo starts on Dashboard. Its `TabView` constructs only the selected
page, so creating the window-owned browser model does not mount the browser's
task, read a preview, or present a file dialog. Selecting Gallery with Controls
visible mounts the browser and starts its built-in sample preview. A real file
read still requires an imported or dropped URL, and the importer requires the
Import action. This admission path is a source-level property of the joined
foundation; it has not been exercised natively for this intake.

For a separate window, keep one model at the window's root:

```swift
@MainActor
struct FileBrowserWindow: View {
    @StateObject private var browser = DemoFileBrowserModel()

    var body: some View {
        DemoFileBrowserTemplate(model: browser)
            .frame(minWidth: 320, minHeight: 560)
    }
}
```

The template switches between a stacked and side-by-side file list and preview.
It uses `List(data, selection:)`, `fileImporter`, typed
`dropDestination(for: URL.self)`, ordinary buttons, and text/progress views. The
shared view never reads `NSItemProvider.payload`, imports retained-runtime or
renderer internals, or presents a platform-only control. File selection is by
stable record ID, not by a retained row's old index.

## Model and extension points

- `DemoFileBrowserModel` owns at most 64 records, one active read, and one pending
  request. Admission examines at most the first 64 URLs of an incoming batch.
  The result notice reports duplicates, unsupported URLs, and excess items;
  acceptance means adding a reference, not successfully reading or decoding it.
- `DemoFilePreviewService` injects an asynchronous byte reader. Its `load`
  boundary validates file URLs, cancellation, the returned byte count, and exact
  UTF-8 even when the reader is replaced. The live `.localFiles` adapter reads
  real files; test readers can hold requests at deterministic barriers.
- `DemoFilePreviewSource` distinguishes file URLs from built-in bytes. The four
  deterministic samples contain ordinary text, Unicode and mixed line endings,
  an empty file, and genuinely invalid UTF-8 bytes. Samples pass through the same
  decoder. No network, artificial delay, fake success response, or service
  account is needed.
- `importFiles`, `select(id:)`, `removeSelectedFile`, `clearFiles`, and
  `restoreSamples` update only the model. An accepted batch selects its first new
  record. Duplicate URLs keep their existing record; Retry explicitly rereads
  the selected source. Removing the selected record selects its next available
  neighbor. An unknown or removed ID cannot select another record by position.
- `retryPreview`, `cancelPreview`, `resume`, `suspend`, and terminal `close`
  expose operation ownership. A caller that permanently disposes an externally
  retained model should call `close`; it cannot be reopened afterward.

New models start suspended. Import and selection can prepare intent without
performing I/O before a view's queued lifecycle task starts. A non-view client
must explicitly call `resume()` to begin reading and owns cancellation until a
view session attaches. Keep one stable model for each mounted browser/window
root; replacing the model at unchanged view identity is not a supported
lifecycle handoff for this ordinary-task slice.

Record identity uses a validated lexical URL spelling. The validator does not
ask the filesystem to standardize paths. It removes dot components and repeated
separators, rejects parent traversal and encoded slash ambiguities, and bounds
the original URL to 32,768 UTF-8 bytes. It rejects relative and non-file URLs,
credentials, URL parameters, remote authorities, and invalid path spellings.
The Windows adapter also rejects UNC/device/alternate-stream and reserved-name
spellings. The original URL is retained for actual reading and macOS scoped
access. Case aliases, hard links, mounts, renamed files, and filesystem identity
are not canonicalized; matching lexical URLs are the declared duplicate policy.

Admission first checks the URL's retained absolute spelling, before parsing
components: authority must be empty or literal ASCII `localhost` ignoring case,
and literal query/fragment delimiters are rejected even when their values are
empty. Windows also requires the raw `/[A-Za-z]:/` drive prefix before component
normalization or percent decoding. The existing single decode and traversal,
separator, device-name, stream, NUL, and trailing-character checks remain.
Percent-encoded percent signs in literal filenames are not decoded twice.
This boundary receives a `URL`, not the text passed to its initializer; it
cannot reconstruct spelling that Foundation has already discarded. It does
not provide a no-follow open or prove physical filesystem locality.

The root's Windows Foundation diagnostic on `6a55df0` observed an empty-port
URL retaining `localhost:` in `absoluteString` while `rangeOfPort` was absent.
The raw authority check rejects that spelling. A separate constructor input,
`file:///C:/bad\name`, had already become the same URL value as
`file:///C:/bad/name`, with matching absolute/relative/data/path spellings and
component fields. The validator cannot distinguish those inputs after this
normalization, and it does not blacklist the resulting ordinary path.

The existing Windows rejection fixture therefore changes exactly one input
from a literal backslash to `%5C`, which retains the forbidden character for
the single decode. Its rejection and zero-reader assertions are unchanged.
The separate `DemoFileURLConstructionTests` case documents the constructor
equivalence and the retained encoded-backslash rejection without opening a
file. The other 84 original feature methods and shared support are unchanged.
The diagnostic established Foundation behavior, not execution of this repair
or its new XCTest case; the repaired service suite and new case still require
the root's serial test workflow.

The model stores an authoritative snapshot before publishing a private change
signal. The signal is not a request ID. Nested synchronous subscribers therefore
read the current snapshot without an earlier property publication rolling it
back. Import-error formatting is an application callout: an intervening mutation
revokes the old callback's authority to dismiss a new importer or replace a newer
notice.

The view awaits `runWhileVisible()` through ordinary `.task`, not `task(id:)`.
The retained task owner cancels during removal
and window teardown, including when the host has stopped disappearance callbacks.
Its locked lifetime marker synchronously revokes completion/admission and cancels
the currently owned read task before waking MainActor cleanup. A replacement
mount installs a new lifetime first; the old task cannot suspend the replacement.
Already-cancelled view tasks do not attach or start a read. Manual `suspend` and
`resume` remain distinct from a user's explicit Cancel, and terminal `close`
releases the visibility waiter as well as cancelling the read.

## Reading, failure, retry, and cancellation

The preview limit is 65,536 bytes, including any BOM. Live reads request chunks
of at most 8,192 bytes and at most one overflow byte. A size check followed by an
unbounded whole-file read is not used. Oversized input fails explicitly; a
truncated prefix is never reported as the complete file. UTF-8 decoding rejects
repair and preserves valid BOMs, decomposed characters, line endings, and empty
input. The selected files are never written, renamed, moved, or deleted.

The live adapter checks regular-file metadata and rejects a selected directory
or symbolic link. Each load owns its detached worker and forwards cancellation
to that worker. The worker alone owns and closes its file handle. On macOS it
balances successful security-scoped access for the original URL; it does not
persist bookmarks or acquire permission outside the supplied URL.

Cancellation is cooperative. It is checked before admission, metadata/open
boundaries, between reads, after reading, and before publishing decoded content.
A filesystem call already blocking inside the OS cannot be forcibly preempted.
The UI distinguishes a cancellation still draining from a completed cancellation.
Changing selection cancels the previous read but keeps its occupied slot until
it returns. Rapid A-to-B-to-C selection retains only C as pending; it does not
launch one detached task for every click. A completion must still own its active
slot and match the desired request identity, selected record, and model lifetime.
Old success or failure cannot replace the current preview.

Retry reads the same source again. A missing or invalid file can be repaired
outside the browser and retried; the browser itself does not manufacture a
successful replacement. The malformed built-in sample continues to fail on
Retry because its bytes are still malformed. Tests use an explicitly controlled
reader to observe loading and cancellation without sleeping; the live adapter
does not introduce a fake loading delay.

Foundation checks the path's metadata and opens the file in separate operations.
This is not a race-free no-follow open: another process can replace the path,
an ancestor may resolve through a link, and a drive/provider may use remote
storage. Lexical URL validation does not prove physical filesystem locality or
a security sandbox. A stricter file-access adapter would need its own declared
capability and validation; the template does not claim that guarantee.

## Import and native adapter limits

The multi-file importer filters for UTF-8 plain text, but a filter is not a file
validation boundary. The reader still validates actual input. Import completion
failures leave the selected file and ready preview unchanged and display the
neutral message `Import was not completed` with the supplied error description.
The current Windows facade projects cancellation through a private opaque error,
so shared code cannot distinguish it from other failures using a supported
public error code. The template neither guesses that private type nor calls all
failure callbacks cancellation. The preview's explicit Cancel action has its
own model-owned cancellation path.

The joined Windows foundation carries the native dialog session and owner
request through `ViewBuildContext` and retains the importer's invocation scope.
Native selection uses the existing owned dialog request and revalidates its
presenter before completion; injected test providers keep their inline path.
Host teardown invalidates dialog requests and the native session before
cancelling retained lifecycle tasks. The template does not replace these hooks,
the UIA transport, or their actor boundaries with a private platform adapter.

Windows `WM_DROPFILES` supplies the final file URLs. The typed public destination
handles those URLs without depending on the provider shim. This native path does
not deliver drag-enter/exit hover state, outgoing OLE transfers, internal drag
reordering, or a custom drag preview. The panel has a static drop invitation;
it does not display fake native hover feedback or offer an unimplemented drag-out
action. macOS typed URL drop and importer/scoped-access behavior still require
same-source native qualification.

Asynchronous image thumbnails remain a separate requirement. The present
`AsyncImage` implementation has process-wide loader storage, unowned work, and
rebuild-triggered reload behavior; the file browser does not hide these defects
with cache-key tricks. It does not use placeholder `QuickLookPreview`, `PDFView`,
or fake image content. Full grid/list media browsing, image decoding and preview,
native drag-out, accessibility/Narrator, and performance qualification remain
open under the original goal.

## Validation scope

`DemoFilePreviewServiceTests` covers real temporary files, exact read limits,
Unicode, malformed input, URL admission, retry, cancellation forwarding, and
deterministic stream/handle cleanup. `DemoFileBrowserModelTests` covers scheduler
ownership, retained cancellation slots, latest pending selection, stale results,
independent models, lifecycle, and synchronous reentry. The gate does not release
a cancelled read until the test explicitly finishes it.

`DemoFileBrowserInteractionTests` connects the actual public typed URL modifier
to the retained drop dispatcher and model, drives real buttons and List
selection, checks preview content, injected importer results, removal, visibility,
host close and observation, and authors one real temporary-file drop-to-preview
path. An async XCTest entry checks that pre-appearance drops only queue intent
before host close in that same MainActor turn. Separate model tests await pre-cancelled
visibility entry, and a host test checks cancellation after the session starts;
the synchronous case does not claim to await the runtime's private task.
The retained fixture explicitly reloads models; a separate real host fixture
with a fake renderer checks automatic object observation without creating an
HWND. The scale matrix sets both runtime and environment display scales.
Source-authored narrow/wide, appearance and scale checks are not reviewed pixels
or native interaction evidence. List naming and retained arrow focus keep their
strict expectations against the already-joined public List implementation. Its
selection wrapper forwards the authored content-root label while the original
identifier and control ownership remain intact. The 64-record model cap does
not itself prove viewport construction budgets or the separate large-data
browser requirements.

This source intake on `ab63afc` has not been compiled or executed. An older frozen
composition containing these 85 feature cases completed a build, but all 392
selected cases in that composition remained unrun. That build does not qualify
this source intake, and separate foundation validation does not execute these
85 preserved cases. No preview/test file I/O or native dialog has been run for
this feature. Native/List/bitmap changes already in the base are preserved;
later root compiler repairs or validation do not silently change this source
identity. After source review and explicit execution authority, use the
repository's serial test workflow:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/test.ps1 -Filter DemoFilePreviewServiceTests
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/test.ps1 -Filter DemoFileBrowserModelTests
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/test.ps1 -Filter DemoFileBrowserInteractionTests
```

Preserve the existing file-drop/dialog, gallery state/responsive, window-state,
and List regression groups. Inspect raw retained-render snapshots and then
qualify real Windows/macOS, keyboard, pointer, Narrator/UIA, DPI, and teardown
behavior separately. None of the source tests or bounded local reads closes
the complete media/file-browser or release gates.
