# Paged media browser template

`DemoMediaBrowserTemplate` is a read-only shared-source workflow with a grid or
list, asynchronous thumbnails, stable selection, an image preview, real decode
failures, cancellation, retry, and incoming typed file URL drops. The controls
gallery owns it through `DemoWindowState.mediaBrowser`. The existing UTF-8 file
browser remains a separate template and service.

An application owns one `DemoMediaBrowserModel` and its `DemoMediaImageService`
per window, with one active template mount for that model. It passes that model
to the ordinary public view:

```swift
DemoMediaBrowserTemplate(model: mediaBrowser)
    .frame(height: 680)
```

The template uses the same SwiftUI-shaped source on Windows and macOS. It
composes the service's ordinary `Image` with `resizable().scaledToFit()`; no
renderer import, platform bitmap constructor, native image decoding, temporary
file, or synchronous file read occurs in its body. The platform adapter remains
confined to `DemoMediaImage.swift`, as described in
[the bounded image service contract](MediaImageService.md).

## Template policy and resource ownership

| Resource | Fixed policy |
| --- | --- |
| Admitted metadata records | 64 per model; at most the first 64 URLs of one drop are examined |
| Constructed page | Four records, sliced before `ForEach`, `LazyVGrid`, or `List` receives data |
| Thumbnail output | Longest edge at most 256 pixels |
| Preview output | Longest edge at most 1024 pixels |
| Concurrent model loads | One thumbnail lane and one preview lane |
| Pending model intent | At most four current-page thumbnail requests and one selected preview request |
| Images retained by the model | At most four current-page thumbnails and one selected preview |
| Service limits | Two physical workers, 8 MiB encoded input, 16,000,000 source pixels, 32 cached images / 16 MiB decoded cache payload |

The record cap and four-item pagination are explicit template choices. They are
not evidence of a fully lazy media grid: the Windows `LazyVGrid` currently
constructs all supplied content, and `onScrollTargetVisibilityChange` does not
deliver its callback. This template uses neither behavior as a work scheduler.
The separate large-grid and target-visibility API gaps remain open.

Only image wells with positive area inside their inherited scroll/root clips
request a load through the real public `onScrollVisibilityChange(threshold: 0)`
API. The template has its own scroll viewport and also respects an outer gallery
clip. It does not schedule every record when the view is constructed or use row
construction, list prefetch, `onAppear`, or a fake visible-ID list as permission
to decode an image. Geometry visibility does not detect sibling occlusion,
window occlusion, minimization, opacity, or an application's foreground status.

The preview has a reserved lane, so thumbnails cannot occupy both service
workers. Thumbnail demand proceeds in page order using one lane. No thumbnail
task is created for an off-page record, and queued intent stores only bounded record
references. Selecting or paging repeatedly replaces intent instead of growing a
queue. The service's own no-queue admission remains unchanged. Sharing this
service with unrelated concurrent callers can produce the real `busy` failure;
the template does not spin, poll, sleep, or bypass that failure with a third
worker. It expects an exclusively owned service.

The model keeps an occupied task handle until the awaited service load actually
returns, even after cancellation, selection changes, removal, or close. The
service likewise holds its physical worker slot through a blocked read or
codec call. Cancellation can revoke publication and request cooperation; it
cannot interrupt an OS call that has not returned. Model images, transient
worker results, renderer textures, and OS codec allocations are separate from
the service's cache payload accounting. None of these limits is a native codec
memory or time sandbox.

## Identity, lifetime, and actions

Record IDs are stable across selection and grid/list/page changes. A selected
image can remain selected on another page, but its preview loads only when the
preview image well is visible. Removing the selection selects its nearest
remaining neighbor. Clear removes all records and model-held images; Samples
restores the deterministic inputs. Neither action creates read work until
visibility and a live mounted lifetime authorize it.

Page and layout changes assign a fresh bounded page scope, so callbacks from a
previous page cannot request or cancel current thumbnails. The collection uses
that scope as ordinary public view identity: same-geometry A-to-B-to-A replacement
gets fresh visibility observers instead of reusing an already-delivered `true`.

The template's private `StateObject` creates a stable token for each actual
mounted view. Its lazy factory creates a fresh object even when a caller reuses
one authored template value after removal; an eagerly seeded `State<UUID>`
would not provide that property. Root appearance claims the token synchronously;
visibility, disappearance, and queued `.task` work identify their originating
mount. A superseded mount
cannot change a replacement's visibility, including when a removal transition
delays the old subtree's disappearance. A signal with one pending waiter avoids
depending on platform-specific `.task`/`onAppear` ordering. It re-arms on
disappearance and matches waiter identity when cancellation removes a waiter.
The ordinary view task owns the mounted lifetime, and cancellation revokes
admission synchronously before queued actor
cleanup. Terminal `close()` also revokes admission synchronously, including
before a queued task first enters. A single retained cleanup task closes the
service; `awaitServiceClose()` awaits that close operation, not blocked native
workers. Existing load calls are still responsible for draining those workers.

The model commits its authoritative snapshot before its observation signal.
Source, revision, request, page, selection, visibility, and lifetime checks
reject stale completions. Cancellation, error descriptions, and observation
notifications can reenter application code; the model changes authority before
cancelling and rechecks it after formatting an error. The small lifetime lock
protects only cancellation state and owned task/waiter references; it does not
invoke application code, cancel tasks, or resume continuations while locked.

Retry advances the record's content revision for both requested sizes and uses
the same service/decoder path. A changed revision revokes cached and in-flight
older content for that lexical file URL. Repeated retry keeps only the latest
intent while previous workers drain. Revision allocation does not wrap, and
Clear/Remove do not reset it; removing and readding the same URL therefore
cannot resurrect a previous file cache entry. External edits are not watched:
the user must retry to request fresh bytes. Explicit cancellation remains a
visible cancelled state for the current selection/page until retry or an action
replaces that state. Paging discards old thumbnail states, so returning to that
page can load them again. Leaving a clip cancels only loading work and returns
it to idle for a later visible request.

## Real inputs and file drops

The built-in corner and tile samples embed the exact existing owned PNG asset
bytes (184 and 101 encoded bytes). Construction creates those encoded values,
not successful images. Both go through `DemoMediaImageService` and the real OS
decoder. The other samples are a three-byte truncated PNG and a complete GIF
that the strict PNG/JPEG/BMP policy rejects. A progress indicator, idle message,
or failure message is never reported as a ready thumbnail.

The public `dropDestination(for: URL.self)` accepts references through the
unchanged shared `DemoFilePreviewService.validateFileURL` validator. The lexical
validated URL is the stable record identity; the original URL remains the read
and scoped-access capability. Admission does not assert that a file exists or
will decode. Missing files, unsupported formats, malformed bytes, and resource
limits produce actual service failures. The template opens no file dialog and
does not implement drag-out. Windows' existing incoming file-drop adaptation
and its OLE/format-negotiation limits remain unchanged.

Lexical URL validation is not a no-follow open, a sandbox, a storage-locality
guarantee, or a promise to recover spelling Foundation normalized before the
API received a URL. The service owns its bounded read and security-scope
lifetime; the template does not duplicate or weaken those checks. No workflow
action writes, renames, moves, or deletes a source file.

## Source checks and remaining evidence

The new model tests use controlled asynchronous byte readers, retain real
occupied reads after cancellation, and release them through explicit barriers.
Returned bytes still pass the actual image service and decoder. They cover
admission, worker/pending bounds, selection and page races, visibility, revision
freshness, lifetime cancellation, close before task entry, observation/error
reentry, real samples, output dimensions, and independent window ownership.

The new interaction tests compose the actual public template through the
retained runtime. They exercise ordinary `Button` and `List` selection, typed
URL drop, actual scroll-clip visibility, stable page/layout identity, removal
and remount, failures, retry, and decoded bitmap output. Every new method in a
`@MainActor` XCTest class is `async` to preserve Windows discovery safety.

The fixture drives explicit host rebuilds; its coordinator's observation
registration callbacks are no-ops. It verifies retained reconciliation, not
automatic host delivery of `ObservedObject` changes. The model tests separately
subscribe to real model notifications. Windows delivers root `onAppear` before
launching the ordinary `.task`, so the appearance signal's pending-waiter
cancellation and replacement branches are source-reviewed but not directly
exercised by these 39 methods. Native ordering and those suspension branches
still require dedicated qualification.

This source intake runs only architecture contracts, formatting, preservation
checks, and independent source review. The parent owns compilation, test
execution, retained PNG inspection, and native qualification. A retained
interaction test is not an Explorer/OLE session, Narrator session, macOS run,
frame-time measurement, or native color/metadata qualification. Existing file
browser tests, image service/decoder tests, and gallery fixture definitions are
unchanged. This bounded workflow advances the original media/file-browser goal;
it does not close the whole media API, accessibility, performance, drag-and-drop,
large-collection, or full-release gates.
