# Performance Budgets

Release gates for rendering and animation performance, per Phase 9 of
`docs/StabilizationRoadmap.md`. Every budget below is a **structural bound**
— primitive counts, cache sizes, simulated frame counts — asserted by an
XCTest. No budget is a wall-clock assertion: timing gates flake on loaded CI
runners, and a flaky gate is worse than none. Simulated time (driving
`tickAnimations(at:)` with synthetic timestamps) is fine; `Date()` /
`DispatchTime` in an assertion is not. New performance tests must follow the
same rule.

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
| D3D11 path cache | Hard cap of 256 entries (`pathCacheMaxEntries` in `D3D11BatchRenderer.swift`), LRU eviction past the cap, stale eviction after 60 unused frames (`pathCacheStaleFrames`); cache keys normalize translated paths | `D3D11PathCacheTests`, `MemoryBoundsAuditTests.testD3D11PathCacheStaysAtZeroForFreshRenderer` |
| Glyph atlas cache | 4096-entry LRU (`GlyphAtlasCache(maxEntries:)` default) over a 2048×2048 atlas; eviction strictly oldest-first | `GlyphAtlasTests.testLRUEvictsOldestEntries`, `…testLookupUpdatesAccessOrder` |
| Text raster cache | 256 entries and 64 MiB (`TextRasterCache` defaults), whichever binds first; LRU eviction keeps both bounds invariant | `PerformanceBudgetGateTests.testTextRasterCacheEnforcesEntryCountAndMemoryBudgets`, `…testTextRasterCacheEnforcesMemoryBudgetBelowEntryCap` |

## Raising a budget

Budgets are ceilings, not targets. When a legitimate feature needs more
primitives or a larger cache, raise the bound in the same commit as the
feature and note the reason in the test comment. A bound that fails on a
healthy tree is a regression signal — do not loosen it just to go green.
