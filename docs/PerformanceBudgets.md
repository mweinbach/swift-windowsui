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
| Animations settle | Wheel momentum + rubber-band springs + presented-delta tweens all complete within 1500 simulated frames (25 s at 60 fps); `hasActiveAnimations` returns `false`, overshoot and presented delta zero out | `AnimationStressTests.testSustainedTickingSettlesAllAnimations` |
| Primitive topology stability | Across 200 rounds of scroll/keyboard/pointer mutation, layer count is unchanged and quad count drifts by at most one scroll-indicator quad per scroll container | `AnimationStressTests.testDynamicMutationPreservesScenePrimitiveTopology` |
| Sustained input | 500 wheel events interleaved with ticks leave scroll offsets within `[0, maxScrollOffset]` with zero overshoot, and everything settles within 1500 frames | `AnimationStressTests.testRepeatedWheelAndTickPreservesRuntimeIntegrity` |

## Cache and memory bounds

| Budget | Bound | Enforcing test |
| --- | --- | --- |
| Per-node animation state | `animationStates` drains to empty once animations settle (1000 alternating wheel events included); `transitionOverlays` empties when no transitions are pending | `MemoryBoundsAuditTests.testScrollMomentumCachesDrainAfterActivitySettles`, `…testRepeatedScrollOscillationKeepsMomentaBounded`, `…testTransitionOverlaysClearWhenAnimationsComplete` |
| D3D11 path cache | 256 entries (`pathCacheMaxEntries`) **and** 64 MiB (`pathCacheByteBudget`), whichever binds first; LRU eviction past either bound, stale eviction after 60 unused frames (`pathCacheStaleFrames`). Keys normalize translated paths and exclude the clip entirely — the clip is a draw parameter, so a moving clip is a hit | `D3D11PathCacheTests`, `MemoryBoundsAuditTests.testD3D11PathCacheStaysAtZeroForFreshRenderer` |
| Glyph atlas cache | 4096-entry LRU (`GlyphAtlasCache(maxEntries:)` default) over a 2048×2048 atlas; eviction strictly oldest-first by a per-entry access stamp (total order, so intra-frame taps are ordered too), and it returns the evicted rect to the atlas free list | `GlyphAtlasTests.testLRUEvictsOldestEntries`, `…testLookupUpdatesAccessOrder`, `CacheComplexityAndReclamationTests` |
| Glyph atlas lookup cost | 3,000 warm lookups against a full 4,096-entry cache visit **zero** entries linearly, at 64 entries and at 4,096 alike — lookup is a dictionary hit, not a scan. Counted through `GlyphAtlasCache.scannedEntriesForTesting`, never timed | `CacheComplexityAndReclamationTests.testWarmCacheServesThreeThousandLookupsWithoutScanningAnyEntry`, `…testLookupWorkDoesNotScaleWithCacheSize`, `…testTheScanCounterObservesTheEvictionScanItIsMeantToBound` |
| Text layout cache | 512 entries (`WindowTextSystem(maxEntryCount:)` default), LRU by access stamp | `CacheComplexityAndReclamationTests.testLayoutCacheEvictsLeastRecentlyUsedAcrossTheStampChange` |
| Text raster cache | 256 entries and 64 MiB (`TextRasterCache` defaults), whichever binds first; LRU eviction keeps both bounds invariant. `TextRasterCache.shared` serves every whole-string raster in the stack — `Controls.icon` and the frame path's `NativeTextRenderer` / `DirectWriteTextRenderer` `appendCommands`, both through `FramePathTextRaster` — keyed by content, style, raster size **and** device scale. Deliberately a process global, not a runtime property: the justification is at the declaration, and `installForTesting` is the seam | `PerformanceBudgetGateTests.testTextRasterCacheEnforcesEntryCountAndMemoryBudgets`, `…testTextRasterCacheEnforcesMemoryBudgetBelowEntryCap`, `CacheComplexityAndReclamationTests.testIconRasterizationIsServedFromTheSharedRasterCache`, `…testFramePathTextIsRasterizedOnceAndServedFromTheCacheAfterwards`, `…testFramePathRasterKeysSeparateScaleFactors` |
| Glyph atlas reclamation cost | Reusing a cell eviction returned is not a recycle: with the atlas full, a frame that introduces one new glyph costs **zero** discarded paint passes, and the frame after a reclaim runs one pass with replay disabled rather than two. A pass that frees a cell it already drew from is still discarded | `GlyphAtlasExhaustionSafetyTests.testOneNewGlyphPerFrameAgainstAFullAtlasCostsNoRepaint`, `…testAFrameAfterReclamationStartsWithReplayDisabled`, `…testReusingACellThisPassAlreadyDrewFromStillDiscardsThePass` |
| Font-availability probes | 512 entries (`NativeFontAvailability.maxCacheEntries`), LRU by access stamp. The key is `(family, character)` over an app-supplied alphabet, so it is unbounded without this | `CacheComplexityAndReclamationTests.testFontAvailabilityProbeCacheIsBounded` |

## Raising a budget

Budgets are ceilings, not targets. When a legitimate feature needs more
primitives or a larger cache, raise the bound in the same commit as the
feature and note the reason in the test comment. A bound that fails on a
healthy tree is a regression signal — do not loosen it just to go green.
