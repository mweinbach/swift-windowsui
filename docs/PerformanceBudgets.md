# Performance Budgets

Release gates for rendering and animation performance, per Phase 9 of
`docs/StabilizationRoadmap.md`. Every budget below is a **structural bound**
— primitive counts, cache sizes, simulated frame counts — asserted by an
XCTest. No budget is a wall-clock assertion: timing gates flake on loaded CI
runners, and a flaky gate is worse than none. Simulated time (driving
`tickAnimations(at:)` with synthetic timestamps) is fine; `Date()` /
`DispatchTime` in an assertion is not. New performance tests must follow the
same rule — including complexity claims, which have no carve-out: "this
lookup does not scale with cache size" is asserted by counting the operations
that would scale (a scan counter on the cache), not by racing two clocks.

The suites run in the standard ladder (`scripts/test.ps1`, sharded); a red
budget test blocks release sign-off.

## Scene and list rendering

| Budget | Bound | Enforcing test |
| --- | --- | --- |
| List virtualization | A 1000-row `LazyVStack` (22 px rows, 360 px viewport) renders < 1000 quads — primitive count tracks the visible window, not the data size | `DynamicListStressTests.testThousandItemListRendersWithNativeGlyphsAndBoundedPrimitives` |
| Native text at scale | Zero PixelText fallback at 13 pt across 100–5000-row lists; all text via DirectWrite glyphs | `DynamicListStressTests.testThousandItemListRendersWithNativeGlyphsAndBoundedPrimitives`, `…testListGrowingFromHundredsToThousandsKeepsRenderingConsistent` |
| Scene determinism | Identical layer, quad, and glyph counts across re-snapshots of the same 1000-row list | `DynamicListStressTests.testRepeatedSnapshotsOfLargeListProduceDeterministicPrimitiveCounts` |
| Demo dashboard scene | Full demo dashboard at 1280×720 stays under 1600 scene primitives / 500 quads (measured 802 / 216 when pinned) | `PerformanceBudgetGateTests.testDemoDashboardStaysWithinScenePrimitiveBudget` |
| Demo data screen scene | Full demo data screen at 1280×720 stays under 1200 scene primitives / 600 quads (measured 582 / 258 when pinned) | `PerformanceBudgetGateTests.testDemoDataScreenStaysWithinScenePrimitiveBudget` |

## Animation and interaction

| Budget | Bound | Enforcing test |
| --- | --- | --- |
| Animating frame traversal | With one of 40 sibling subtrees animating (281-node probe tree), no rebuilt frame enters more than 80 view nodes — the animating branch plus one visit per replayed sibling, measured 47. Counted through `ScenePaintMetrics.nodesVisited`; with subtree replay disabled the same frame walks 227 | `AnimationFrameCostGateTests.testAnimatingOneSubtreeDoesNotWalkTheWholeTree` |
| Traversal holds for the whole animation | Zero of the ~32 frames a momentum ride rebuilds may exceed that bound. A cache invalidated once and never repopulated passes the first-frames test and fails this one | `AnimationFrameCostGateTests.testFrameCostHoldsForTheWholeLifeOfAnAnimation` |
| Settled window rebuilds nothing | Once `hasActiveAnimations` clears, 20 further tick+render pairs leave `sceneRebuildCount` unchanged — every frame served from the whole-scene cache | `AnimationFrameCostGateTests.testASettledWindowStopsRebuildingScenes` |
| Animations settle | Wheel momentum + rubber-band springs + presented-delta tweens all complete within 1500 simulated frames (25 s at 60 fps); `hasActiveAnimations` returns `false`, overshoot and presented delta zero out | `AnimationStressTests.testSustainedTickingSettlesAllAnimations` |
| Primitive topology stability | Across 200 rounds of scroll/keyboard/pointer mutation, layer count is unchanged and quad count drifts by at most one scroll-indicator quad per scroll container | `AnimationStressTests.testDynamicMutationPreservesScenePrimitiveTopology` |
| Sustained input | 500 wheel events interleaved with ticks leave scroll offsets within `[0, maxScrollOffset]` with zero overshoot, and everything settles within 1500 frames | `AnimationStressTests.testRepeatedWheelAndTickPreservesRuntimeIntegrity` |

## Cache and memory bounds

| Budget | Bound | Enforcing test |
| --- | --- | --- |
| Per-node animation state | `animationStates` drains to empty once animations settle (1000 alternating wheel events included); `transitionOverlays` empties when no transitions are pending | `MemoryBoundsAuditTests.testScrollMomentumCachesDrainAfterActivitySettles`, `…testRepeatedScrollOscillationKeepsMomentaBounded`, `…testTransitionOverlaysClearWhenAnimationsComplete` |
| D3D11 path cache | 256 entries (`pathCacheMaxEntries`) **and** 64 MiB (`pathCacheByteBudget`), whichever binds first; LRU eviction past either bound, stale eviction after 60 unused frames (`pathCacheStaleFrames`). Two key regimes, split at the 8 MB whole-raster estimate (`pathWholeRasterByteBudget`): below it the whole path is rasterized and the key normalizes translation and excludes the clip entirely — the clip is a draw parameter, so a moving clip is a hit; above it only the visible region is rasterized, snapped out to a 128 px tile grid (`pathRasterWindowTile`), and that window is part of the key — scrolling within a tile is still a hit, crossing one is a new entry. A single raster bigger than the whole byte budget is denied insertion (`pathCacheOversizedDenials`): it draws once from a caller-owned texture and leaves the cache alone rather than flushing it | `D3D11PathCacheTests` (`…testATranslatingClippedPathStaysOneRasterizationAcrossSixtyFrames`, `…testAHugePathInsideASmallClipRasterizesBounded`, `…testAWindowedPathStillHitsWhileScrollingInsideOneTile`, `…testAnOversizedRasterIsDeniedRatherThanFlushingTheCache`), `MemoryBoundsAuditTests.testD3D11PathCacheStaysAtZeroForFreshRenderer` |
| Glyph atlas cache | 4096-entry LRU (`GlyphAtlasCache(maxEntries:)` default) over a 2048×2048 atlas; eviction strictly oldest-first by a per-entry access stamp (total order, so intra-frame taps are ordered too), and it returns the evicted rect to the atlas free list | `GlyphAtlasTests.testLRUEvictsOldestEntries`, `…testLookupUpdatesAccessOrder`, `CacheComplexityAndReclamationTests` |
| Glyph atlas lookup cost | 3,000 warm lookups against a full 4,096-entry cache visit **zero** entries linearly, at 64 entries and at 4,096 alike — lookup is a dictionary hit, not a scan. Counted through `GlyphAtlasCache.scannedEntriesForTesting`, never timed | `CacheComplexityAndReclamationTests.testWarmCacheServesThreeThousandLookupsWithoutScanningAnyEntry`, `…testLookupWorkDoesNotScaleWithCacheSize`, `…testTheScanCounterObservesTheEvictionScanItIsMeantToBound` |
| Text layout cache | 512 entries (`WindowTextSystem(maxEntryCount:)` default), LRU by access stamp | `CacheComplexityAndReclamationTests.testLayoutCacheEvictsLeastRecentlyUsedAcrossTheStampChange` |
| Text raster cache | 256 entries and 64 MiB (`TextRasterCache` defaults), whichever binds first; LRU eviction keeps both bounds invariant. `TextRasterCache.shared` serves every whole-string raster in the stack — `Controls.icon` and the frame path's `NativeTextRenderer` / `DirectWriteTextRenderer` `appendCommands`, both through `FramePathTextRaster` — keyed by content, style, raster size **and** device scale. Deliberately a process global, not a runtime property: the justification is at the declaration, and `installForTesting` is the seam | `PerformanceBudgetGateTests.testTextRasterCacheEnforcesEntryCountAndMemoryBudgets`, `…testTextRasterCacheEnforcesMemoryBudgetBelowEntryCap`, `CacheComplexityAndReclamationTests.testIconRasterizationIsServedFromTheSharedRasterCache`, `…testFramePathTextIsRasterizedOnceAndServedFromTheCacheAfterwards`, `…testFramePathRasterKeysSeparateScaleFactors` |
| Glyph atlas reclamation cost | Reusing a cell eviction returned is not a recycle: with the atlas full, a frame that introduces one new glyph costs **zero** discarded paint passes, and the frame after a reclaim runs one pass with replay disabled rather than two. A pass that frees a cell it already drew from is still discarded | `GlyphAtlasExhaustionSafetyTests.testOneNewGlyphPerFrameAgainstAFullAtlasCostsNoRepaint`, `…testAFrameAfterReclamationStartsWithReplayDisabled`, `…testReusingACellThisPassAlreadyDrewFromStillDiscardsThePass` |
| Font-availability probes | 512 entries (`NativeFontAvailability.maxCacheEntries`), LRU by access stamp. The key is `(family, character)` over an app-supplied alphabet, so it is unbounded without this | `CacheComplexityAndReclamationTests.testFontAvailabilityProbeCacheIsBounded` |

## Live measurements

The gates above are counts, on purpose. This section is the other half: what
the real window actually measured, so the counts can be judged against
something. These are wall-clock numbers from a real session and are therefore
**evidence, not gates** — nothing here is asserted by a test, and a different
machine will produce different figures.

Reproduce with `swift-windowsui --diagnostics`, which opens the real window,
drives a scripted hover / scroll / screen-switch workload through the normal
input entry points, closes itself, and writes a JSON report. Add
`--diagnostics-no-vsync` to unpace presents and measure the app's own cost
rather than the compositor's vblank wait, `--diagnostics-seconds N` to
lengthen the run, `--diagnostics-output PATH` to place the report.

### 2026-08 — release build, RTX 5090, 12 s scripted run

The report separates **animating** frames from idle ones. Whole-run
percentiles are close to meaningless for this question: a session that is
mostly idle serves most of its frames from one whole-scene cache hit, and the
frames that actually have to do work vanish into the tail.

| Measure | Unpaced (`--diagnostics-no-vsync`) | vsync-paced |
| --- | --- | --- |
| Frames per second over the run | 1482 | 4.05 |
| Frame time while animating, p50 / p95 / p99 | 0.225 / 0.635 / 1.457 ms | 256.3 ms p50 |
| Worst frame in the run | 6.89 ms | 262 ms |
| Animating frames over the 16.67 ms refresh budget | **0 of 612** | 40 of 40 |
| Scene build, p50 (whole run) | 0.147 ms | 0.577 ms |
| Backend submit, p50 | 0.119 ms | 0.057 ms |
| Backend present, p50 | 0.016 ms | **255.4 ms** |

Read together: the app's own per-frame cost is 0.6 ms and the paced frame is
256 ms, so **99.75 % of a paced frame is the wait inside `Present`**, not work
this process does. On the machine that produced these numbers that wait is
environmental — a headless/virtual 1024x768 @ 60 Hz display with no EDID,
where `Present(sync=1)` blocks roughly fifteen vblanks. The Direct2D frame
backend (`SWIFT_WINDOWSUI_FRAME_DEBUG=1`) measures the same 254 ms through a
completely different renderer, which is what rules out renderer code as the
cause. **This has not been reproduced or ruled out on a physical monitor**, and
until it is, the paced column says nothing about the app.

What the unpaced column does establish, and what the gates above protect: at
p95 the animating frame has ~26x headroom against a 60 Hz budget and ~13x
against 120 Hz, and the single worst frame of the run still fits inside one
120 Hz frame.

Supporting counts from the same run:

- **Traversal.** A full-tree walk is 484 nodes. A rebuilt frame walks a median
  of 1 (the whole root replays as a single cached range) and a p95 of 163.
  Subtree replay is doing the work the budget assumes.
- **Batching.** 80 instanced draws per frame covering ~760 primitives, a
  coalescing ratio of 9.5. Submission of that scene costs 0.119 ms.
- **Atlas.** 8 frames uploaded anything after warmup, across six screen
  switches — new glyphs on newly visited screens. Once a screen has been
  visited, revisiting it uploads nothing.

### 2026-08 — the presentation pacing watchdog

The 4.05 fps column above is what a user of that machine actually saw, and no
amount of app-side headroom fixes it: the wait is inside `Present`. The stack
therefore stopped accepting it. `PresentPacingPolicy`
(`Sources/SwiftWindowsGraphics/PresentPacing.swift`) watches what presents cost
and, when six consecutive paced presents each exceed 2.5 display periods and
add up to 0.75 s while the app's own frame cost stays inside one period,
switches the swap chain to `Present(0)` and hands frame pacing to the host's
own clock. It keeps probing — 2 s, then 4, 8, 16, capped at 30 — so a laptop
that gets docked to a real monitor goes back to proper vsync. Both presenters
carry it; the mode is a typed field on `RendererHealthSnapshot.presentPacing`
and a `presentPacing` block in the diagnostics JSON.

Measured on the same machine, same 10 s scripted workload, release:

| Measure | Before | After |
| --- | --- | --- |
| Frames per second over the run | 4.05 | **37.1** |
| Frames presented | 49 | 371 |
| Frames with an animation running | 40 | 362 |
| Backend present, p50 | 255.4 ms | **0.035 ms** |
| Frame time, p50 | 256.3 ms | 0.225 ms |
| Frame-debug (Direct2D) path, fps | ~4.1 | **33.5** |

The residual gap to 60 is the watchdog paying for its own recovery: engaging
costs six blocked presents (~1.5 s), and each probe costs about three more
(~0.8 s) because DXGI queues three presents before `Present` has to wait for
anything. Between probes the window runs at ~61 fps — a 20 s run
(`artifacts/perf/l8-after4-vsync.json`) presents 949 frames, of which 18 are the
blocked ones, leaving 931 frames across 15.3 s. As the probe backoff reaches
its 30 s ceiling that overhead tends to ~2.6 %.

Two things this measurement fixed that arithmetic alone would not have:

- A **one-frame probe is worthless, and a four-frame probe is too**. The first
  presents after a self-paced run drain into an empty DXGI queue and return in
  0.04 ms whatever the compositor is doing. Probes that trusted them handed
  pacing back twice in one run and measured 10.9 and then 20.3 fps.
- The self-paced schedule is pinned to the **runtime pacing floor, not the
  display period**. Frames arrive on a timer-queue timer whose accuracy is the
  ~15.6 ms system tick; a schedule at 16.667 ms rejected every second tick for
  being a millisecond early and then waited a whole further tick, measuring
  49 fps from a gate that was arithmetically correct.

### Debug builds are not the measurement

The same run in a debug build reports animating p95 2.7 ms / p99 4.3 ms and a
worst frame of 52 ms — about 5.8x the release cost, and the 52 ms is a
cold-cache screen paint that release does in 10 ms. Any frame-time figure
quoted without its configuration is unusable; quote release, or say debug.

## Raising a budget

Budgets are ceilings, not targets. When a legitimate feature needs more
primitives or a larger cache, raise the bound in the same commit as the
feature and note the reason in the test comment. A bound that fails on a
healthy tree is a regression signal — do not loosen it just to go green.
