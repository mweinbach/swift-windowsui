# Bounded local image service

`DemoMediaImageService` adds real asynchronous PNG, JPEG, and BMP decoding for
future media-browser thumbnails and image previews. It returns owned pixels and
an ordinary public `Image`; it does not return a symbol or metadata standing in
for decoded content. It is separate from the existing UTF-8 file preview. This
source slice does not wire a new browser or gallery, complete the media/file
template, or qualify macOS/Windows parity.

One browser/window owns one service instance. Construction does no I/O. A caller
explicitly awaits `load`, owns that task's cancellation, and calls `close` when
disposing of a long-lived service. The service dispatches its own worker; the
view must not synchronously invoke a decoder while building its body.

```swift
let service = DemoMediaImageService()
let thumbnail = try await service.load(.file(selectedURL), maximumPixelDimension: 256)
let preview = try await service.load(.file(selectedURL), maximumPixelDimension: 1024)
// Dispose of the browser's service when its owner is permanently closed.
await service.close()
```

The shared view source uses the same ordinary composition on macOS and Windows:

```swift
@MainActor
struct MediaPreviewContent: View {
    let preview: DemoMediaImage

    var body: some View {
        preview.image
            .resizable()
            .scaledToFit()
            .accessibilityLabel("Selected image")
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
```

Only the platform service constructs an ImageIO/CoreGraphics or WinSwiftUI image
value. Shared view code does not import graphics/runtime/renderer targets, open
files, call native decoders, use private image storage, or create native controls.
The caller still owns selection identity and visible loading/failure/retry state;
the service does not decide which asynchronously returned image is selected.

## Limits and work ownership

| Resource | Per-service admission limit |
| --- | --- |
| Encoded input | 8,388,608 bytes (8 MiB) per load |
| Source raster | 16,000,000 pixels, before pixel copying |
| Media output | Longest edge 1...1024 pixels; no upscaling |
| Output pixels | At most 4,194,304 tightly packed BGRA bytes per image |
| Physical workers | 2, including cancelled calls still draining |
| Waiting requests | No service queue; excess work fails with `busy` |
| Cached images | At most 32 entries and 16,777,216 pixel bytes (16 MiB) |
| File URL spelling | 32,768 UTF-8 bytes, using existing lexical validation |

Size arithmetic is checked before narrowing, pitch calculation, buffer copying,
and allocation. The limits govern admitted encoded data, source dimensions,
owned output, cache payloads, and active work. They are not a process memory
sandbox: WIC/ImageIO may allocate internal metadata, profiles, source rasters,
and conversion buffers. A native codec call is not time-bounded. Transient input
and output copies add memory beyond the cache, as do caller-retained images,
renderer texture caches, framework objects, and a replacement reader's own work.
The fixed input/worker limits bound this service's admitted copies; external
callers can still create their own tasks or hold their own source data.

File reads request chunks of at most 65,536 bytes and one overflow byte. The
reader does not check metadata size and then perform an unbounded whole-file
read. A replacement asynchronous reader passes the same admission, returned-size,
codec and cancellation checks, but must bound its own allocation behavior.

Each awaited load owns one detached utility worker. Its cancellation cell handles
cancellation before worker installation and forwards cancellation without holding
the cell lock. Cancellation remains cooperative before/between reads and around
decoding. It cannot preempt a metadata, open, read, or codec call already blocked
inside the OS. A cancelled worker keeps its slot until its actual return; `close`
does not make that slot disappear. A replacement load can therefore report
`busy` while cancellation drains. There are no detached retry loops or sleeps.

Cancellation and publication have a precise ordering: the operation cell commits
publication under its lock, then unlocks before actor-owned cache mutation, task
destruction, or pixel release. There is no actor suspension between that commit
and the cache/result write. Cancellation that wins first forbids both cache and
result publication. Cancellation after the commit cannot revoke its completed
result. Explicit actor invalidation always removes an already-cached value and
revokes any still-active operation. No user callback, continuation resume, or
`Task.cancel()` call runs while the operation lock is held.

## Identity, cache, retry, and file access

File cache identity is the validated lexical URL plus the caller's `UInt64`
revision and requested pixel edge. It is not filesystem identity or an automatic
mtime watcher. External edits at the same path require `cachePolicy: .reload`,
`invalidate(url)`, or a new revision. A revision change revokes every cached size
and active older-revision load for that URL. Reload revokes all existing sizes
and revisions before attempting admission; if both workers are occupied, it
returns `busy` without starting a third. The caller retries after work drains.

Invalidation and terminal `close` cancel owned tasks but do not discard their
occupied slots. Late success or failure cannot repopulate a revoked cache entry
or return an authoritative result. Source identity bookkeeping lives only in the
two active entries and 32 cache entries; there is no growing revision/tombstone
dictionary. Data sources pass through the real decoder but are never cached,
so the cache does not retain encoded input bytes as keys.

Cache hits update LRU order. Admission subtracts actual owned pixel counts on
replacement/eviction and evicts until both limits admit the new value. Eviction
releases only the cache's reference: an image already held by a view remains
valid. The cache counts the owned tightly packed raster, not a compressed-file
size estimate. It does not count images retained separately by application code.

The local reader reuses `DemoFilePreviewService.validateFileURL` without changing
that service. It preserves the original URL for access, rejects selected folders
and symbolic links using regular-file metadata, and owns/closes the handle on
its worker. On macOS it balances successful security-scoped access. Files are
read only; no decode temporary file, bookmark, rename, deletion, or write occurs.

Metadata and open are separate Foundation operations. This is not a race-free
no-follow open, a path sandbox, or proof of physical storage locality: another
process can replace a path, ancestors can be links, and drives/providers can be
remote. The lexical spelling check supplies none of those stronger guarantees.

## Decode policies and platform boundaries

`DecodedImage(data:maximumPixelDimension:)` is the Windows facade for the media
policy. `BoundedImageDecoder.decode` implements it without retaining a cache or
dispatching a task. Its C boundary decodes admitted bytes through an in-memory
WIC stream. It initializes COM on that worker and releases every COM resource
before balancing successful `CoInitializeEx` calls, including `S_FALSE`. An
already-initialized different apartment remains owned by its original caller.
Swift copies the output into owned `Data` before freeing the C allocation.

The media policy accepts PNG/JPEG/BMP with exactly one decoded frame. It also
rejects PNG `acTL` and pre-scan JPEG APP2 `MPF` markers, because a codec may expose
those containers as one default frame. This is not a comprehensive validator for
every compound or proprietary container. PNG and BMP use raster orientation;
reported JPEG EXIF 1...8 is applied before scaling. Absent or unsupported WIC
JPEG metadata means orientation 1. Invalid exposed orientation values fail.

Reported WIC color profiles are transformed to sRGB. Absent or unsupported WIC
color contexts are assumed sRGB, not evidence that a source has no profile.
More than one reported context or a failed transform gives an explicit error.
Premultiplication occurs before Fant downsampling, and output is tagged
`.bgra8Premultiplied`, matching the existing renderer-neutral bitmap contract.
Filtering operates in stored sRGB channels, not linear-light radiance. These
metadata and color assumptions need native qualification, especially with CMYK,
embedded profiles and alternative installed codecs. “Strict” describes the
media format/frame/bounds policy, not universal metadata conformance.

The macOS adapter is confined to `DemoMediaImage.swift`. ImageIO preflights source
dimensions, checks the same formats/frame markers, downsamples, and applies JPEG
orientation using its exposed metadata. A bounded sRGB CoreGraphics context owns
the final premultiplied BGRA raster. One explicit immutable CFData object owns
the cache payload, and the CGImage provider retains that exact object; the cache
does not separately retain the Swift Data bridge or assume it shares storage.
Its cost is the CFData byte length. Any transient bridge copy during decoding is
outside the cache bound. The returned image retains no lazy ImageIO source or
file handle. This native
adapter has not been compiled or exercised by this source-only intake. Pixel
rounding, metadata exposure and color profiles are not claimed identical across
the two OS decoders.

`BoundedImageDecoder.decodeFirstFrame` is a separate bounded Windows compatibility
policy for existing image loaders: any installed WIC format, frame zero, full
admitted dimensions, raw orientation/color, and straight BGRA. It shares the
8 MiB encoded / 16,000,000 source-pixel / 64,000,000 output-byte checks and owned
memory boundary. The strict media API never falls back to it. These limits are
explicit Windows adaptations, not complete desktop SwiftUI compatibility.

At the source base for this slice, `AsyncImage` still has a global URL-loader
cache, unowned work and rebuild-triggered reloading; `ImageLoader` also has an
unbounded path cache. This service bypasses those paths. Providing a bounded
legacy decoder entry does not repair or qualify either loader's lifecycle or
cache. Any separate loader repair requires its own integration and tests.

## Evidence and remaining qualification

The source-authored `BoundedImageDecoderTests` checks actual PNG/BMP/JPEG pixels,
premultiplication, transparent-edge scaling, all eight JPEG orientations, native
admission/reset boundaries, malformed/truncated data, limits, the distinct legacy
policy, cancellation and retained `Image` composition. Its APNG/MPO inputs are
rejection-marker witnesses, not complete animation/multi-picture fixtures. The
JPEG fixture encodes six known grayscale DCT blocks without an OS encoder.

`DemoMediaImageServiceTests` covers actual temporary files and retry, explicit
file freshness, cache sizes/LRU/pixel accounting, preserved evicted values,
independent service instances, pre-cancellation, owned cancellation, full worker
slots, revision changes, invalidation, close, late success/failure, and bounded
stream cleanup. Its deterministic read gates keep cancellation draining until
the test explicitly releases the read; no sleep or fake live delay is used.

This intake has source contract, formatting and independent source review only;
no compiler, test execution, file-preview runtime, native UI, or screenshot is
run by this subtask. The parent owns serial builds/tests and retained-render
evidence. The existing UTF-8 preview/model/template and their 85 test methods are
unchanged. Before qualification, execute both new groups plus existing image,
file-preview and retained bitmap regressions; inspect retained PNG output and
qualify native Windows/macOS metadata, color, lifecycle and resource behavior.
No source test here completes the media/browser, accessibility, drag-and-drop,
performance, or full-release gates in the original goal.
