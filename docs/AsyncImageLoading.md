# Bounded AsyncImage loading

`AsyncImage` keeps the existing three initializers, `AsyncImagePhase`,
`AsyncImageError.decodingFailed`, and the imperative `AsyncImageLoader.phase` /
`load(url:scale:)` surface. Loading no longer creates a global URL-to-loader
dictionary, starts I/O during view construction, or writes temporary image files.
This is a bounded compatibility repair, not complete image or network parity.

## Mounted ownership and publication

An ordinary private View owns one loader through the existing mounted
`StateObject` implementation. A stable `ZStack` carries `task(id:)` even when the
default placeholder is empty, including in a managed List row. Task identity is
the URL and service identity. Rebuilding the same request, changing `scale`, or
changing only the transaction does not start another download. Separate mounted
copies and separate hosts do not share phases or request cancellation.

An adjacent mounted `onChange(initial: true)` adopts presentation configuration.
Its source initializer identity carries the transaction without defining false
value equality for `Transaction`. Completion uses the latest matching *adopted*
transaction and scale. Building or rejecting a provisional candidate cannot
replace that configuration or cancel the currently adopted request. Phase
construction returns `.empty` when the requested URL/service differs from the
published source, so a new candidate does not display an old URL's image.

URL replacement, nil, and cancellation revoke the previous invocation. Both its
identity and its cooperative cancellation flag must still be current before
publication. Identity, terminal state, and owned handles settle before assigning
`@Published phase`, whose subscribers can reenter synchronously. Errors produce
`.failure`; cancellation does not become a displayed failure. A terminal phase
stays terminal on matching rebuilds. Removing and creating a new mounted owner
permits a new attempt. An adopted source change retires terminal authority too:
completed A followed by adopted B (or nil) and then A starts a fresh A request,
even when the intermediate task never runs. An abandoned candidate does not.

The existing retained lifecycle defines disappearance: an outgoing transition
can keep its task until physical disappearance. Raw snapshot contexts have no
mounted `task(id:)` ownership and stay at the placeholder; taking a snapshot does
not initiate network work. The imperative loader owns a separate service/task,
and loading nil clears its phase and revokes its old request.

## Admission and cancellation

Each host lazily owns one non-UI `AsyncImageService`. It is not a phase cache and
does not retain views or ObservableObjects. Closing the host first seals image
admission without callbacks, including the lazy getter when no service exists.
It then revokes mounted ownership before cancelling active requests and draining
queued continuations. Teardown cannot construct a replacement service.

| Resource | Bound and behavior |
| --- | --- |
| Active fetch/decode operations | 2 per host |
| Queued request owners | 64 per host; excess requests fail with `queueFull` |
| Encoded response/file bytes | 8,388,608; reject headers or chunks that exceed it |
| Decoded source pixels | 16,000,000, checked before native output allocation |
| Owned tight decoded output | 64,000,000 bytes per image |
| File read chunk | At most 65,536 bytes, plus one overflow-probe byte |
| HTTP redirects | At most 5, remaining within HTTP/HTTPS |
| URLSession timeouts | 30-second request and 60-second resource configuration |

A queued owner has no worker. Each active operation has an owned worker task,
and cancellation reaches both that task and the actual URLSession data task.
An active slot and its awaiting continuation remain occupied until the operation
returns; cancellation cannot manufacture spare capacity while a codec is still
running. Queued cancellation removes that owner immediately. All cancellation
callbacks, captured-payload release, and continuation resumptions occur outside
service locks. The two-operation limit ends when the source/decode operation
returns, not when every Swift Task object has been destroyed; bookkeeping and
payload cleanup can still be finishing. It is not a limit on live Task objects.

File workers check cancellation before and after each bounded read and before
and after decoding. WIC and synchronous filesystem calls cannot be preempted
by Swift task cancellation. A stuck native call can therefore retain a physical
slot after the view is gone. The implementation does not claim immediate native
termination or a wall-clock bound from cooperative cancellation.

HTTP uses a per-operation ephemeral URLSession with no URL response cache,
cookie storage, or credential storage. A data delegate checks the response and
appends only admitted chunks; it never buffers an unlimited `data(for:)` result.
Only a successful HTTP status reaches decoding. The public view does not add
custom headers, authentication flows, progressive rendering, animated playback,
or a persistent network cache.

## Decoding and file freshness

Both AsyncImage and named image loading use
`BoundedImageDecoder.decodeFirstFrame(_:)`, the distinct legacy policy of the
bounded in-memory WIC decoder. It preserves installed WIC formats, frame zero,
the full admitted dimensions, raw orientation/color, and straight-alpha BGRA.
It does not silently apply the strict demo thumbnail policy's format allowlist,
single-frame restriction, orientation transform, sRGB conversion, or downsample.
See [the media image service](MediaImageService.md) for that separate policy.

AsyncImage's file URL conversion accepts empty or literal localhost authority;
other or ambiguous authorities fail instead of being discarded to obtain a
different local path. This small conversion check is not the demo document
preview validator and does not change `Image(name,bundle:)` resource lookup.
It validates the retained Foundation URL representation, not constructor text
that Foundation has already normalized or discarded. A normalized ordinary
local-path counterpart is not denied merely because another spelling produced
the same URL.

The stateless package file reader resolves a path once, reads through one
handle, and compares size, timestamps, and stable file identity before and after
reading. Its snapshot is checked again after decoding. Stable identity includes
volume, the 128-bit file ID, and the actual opened NTFS stream spelling in raw
UTF-16; equal-length streams or canonically equivalent names cannot alias each
other's cache entry. AsyncImage fails closed if stable identity is unavailable.
These are ordinary freshness observations, not content attestation: another
process can change the file after validation, including during an executor hop
before publication. Request identity still guards the UI publication.

The synchronous named-image API remains synchronous. Its cache is bounded to
64 entries and 32 MiB of retained pixel Data, with least-recently-used eviction.
Each lookup opens and identifies the current file before accepting a hit.
Changed sources and failed refreshes cannot fall back to stale cached pixels.
Identity-unavailable sources decode uncached; a valid image larger than the
cache byte budget is returned uncached without evicting unrelated entries.
Byte-cost and dimension calculations use checked arithmetic.

These bounds do not cover caller-retained images, renderer texture caches,
Foundation internals, or codec scratch space. Multiple hosts have independent
budgets. A byte limit alone is not a process-wide peak-memory guarantee.

## Source density

`scale` means source pixels per logical point. Nonfinite or nonpositive values
fall back to 1. Intrinsic and unconstrained resizable sizes divide pixel
dimensions by scale; the source Data and content token stay unchanged.

Cap insets and destination placement remain authored in points. The sampling
resolver accepts a source density, defaulting to 1, and converts only cap/center
sampling distances into source-texel units. Placement validation still checks
the actual destination in points. Source dimensions are not rewritten. The resolver emits the same
dimensionless source/destination fractions and repeat counts already consumed
by CPU and D3D sampling. Paint placement remains in points until the usual
display-DPI conversion. Device scale must not change tile count.

Whole-source-texel cap admission and existing tile-phase limits still apply.
Uncapped stretch returns its density-independent legacy descriptor before any
unnecessary multiplication can overflow or underflow at an extreme finite scale.
Nonlegacy plans retain explicit failure when their texel bands or phases cannot
be represented.
For example, a 12 by 8 pixel image at scale 2 has a 6 by 4 point ideal; 1-point
caps select two source texels. In a 24 by 16 point destination its center repeats
5.5 by 7 times. Fractional density can admit fractional point caps when they map
to whole texels. Unsupported plans still report a typed failure. Full native
filtering, color, animation, and modifier-order parity remain unqualified.

## Validation scope

`AsyncImageLoadingTests` uses controlled suspended workers and a URLProtocol
fixture to exercise admission, actual URLSession cancellation, streaming limits,
and cancellation ordering without an external server. `AsyncImageLifecycleTests`
exercises mounted ownership and phase/configuration changes. `AsyncImageScaleTests`
provides analytic retained sizing, cap/tile descriptor, reconciliation, and DPI
oracles. `ImageLoaderCacheTests` injects file identities/readers and small budgets
to exercise freshness, overflow, release, and eviction independently of WIC.

Existing bitmap, resource, mounted state, task, transaction, and lifecycle tests
remain unchanged. Newly authored tests are not proof of execution: the parent
validation lane must compile the joined decoder/lifecycle source and run them
serially. Native host, WIC, runtime PNG, macOS reference, and full-suite outcomes
must be reported separately; no gallery baseline or tolerance changes belong to
this repair.
