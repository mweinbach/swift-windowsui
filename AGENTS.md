# AGENTS.md

SwiftUI on Windows as a native Swift UI stack: SwiftUI-shaped app code on a
retained runtime, a renderer-neutral scene contract, a Win32 host, and a
Direct3D 11 presentation path. The architecture is GPUI-inspired Swift, not a
wrapper around native Win32 controls. Swift / SwiftPM; all tooling is
PowerShell scripts under `scripts/`.

## Layout

SwiftPM targets under `Sources/`, top of the stack first:

- `WinSwiftUI` — the SwiftUI-shaped API app code imports on Windows.
- `SwiftWindowsUI` — the retained runtime (`RetainedViewRuntime`); `Runtime.swift` is the source of truth for layout, hit testing, focus, clipping, and animation.
- `SwiftWindowsGraphics` — renderer-neutral `GPUIScene` paint records, typed primitives, and the CPU rasterizer.
- `SwiftWindowsRendererD3D11` / `SwiftWindowsPlatform` — D3D11 backend and Win32 host.
- `SwiftWindowsDemo` — shared-source demo (same source builds against macOS SwiftUI); `swift-windowsui` runs it, `swift-windowsui-snapshot` renders it offscreen for screenshots.

`extern/zed` is a read-only reference checkout; never edit or build it.

## Invariants

`scripts/check-contracts.ps1` machine-checks the architecture contracts. Run it
before and after architecture-sensitive edits; if a change fights a contract,
rethink the change, not the contract. In addition:

- App rendering goes through `WinSwiftUIWindowHost` and `RetainedViewRuntime`; `SwiftWindowsScene` and `FoundationApp` are not the primary path.
- `GPUIScene.paintOperations` is the presentation-order paint stream; family batches are data-layout optimizations, never presentation order.
- UI-facing code (runtime, controls, host, `WinSwiftUI`) is main-actor-centric.
- Screenshots are raw retained-runtime output via `swift-windowsui-snapshot`; never desktop or window capture.
- Demo source stays SwiftUI-shaped and same-source with macOS; fix Windows rendering bugs in the stack, not with platform-only APIs in demo code.
- Prefer extending `ViewBuildContext` and inherited environment propagation over global UI state.

## Build, test, verify

Invoke scripts as `powershell -NoProfile -ExecutionPolicy Bypass -File scripts/<name>.ps1`.
Never run two SwiftPM commands against the same `.build` directory in parallel.

```powershell
scripts/agent-check.ps1 -ContractsOnly    # contract checks; run before architecture-sensitive edits
scripts/agent-check.ps1 -Quick            # after runtime, scene, renderer, or screenshot changes
scripts/agent-check.ps1 -Full             # release-quality validation
scripts/lint.ps1                          # toolchain swift-format on changed Swift files; run before finishing (-Path <file> if the checkout is dirty)
scripts/test.ps1 -Filter <TestClass>      # focused XCTest, e.g. RetainedViewRuntimeTests, GPUISceneTests, D3D11BatchRendererTests
scripts/build.ps1 -Product swift-windowsui
scripts/demo-screenshot.ps1               # writes artifacts/demo-screenshot.png — open and inspect after visual changes
```

Generated output belongs under `artifacts/` or the OS temp directory; the
contract check rejects root-level logs and screenshots. Commit as you go with
clear messages, and keep `README.md` and `docs/` current when architecture or
compatibility changes.

## Task docs (read when relevant)

- `docs/Testing.md` — full validation matrix: script details, test filters, screenshot and gallery workflows.
- `docs/GPURenderingPipeline.md` — how a view tree becomes pixels, with the test protecting each step.
- `docs/WinSwiftUI.md` — what the compatibility layer is and how it maps onto the runtime.
- `docs/CompatibilityStatus.md` — what is safe to use today in the shared-source subset.
- `docs/MacOSDesignParity.md`, `docs/AnimationParity.md` — pinned macOS design and animation constants, enforced by parity tests.
- `docs/MacOSReferenceParityWorkflow.md` — producing macOS reference renders and comparing them against Windows output.
- `docs/StabilizationRoadmap.md` — the phased plan toward release quality.
