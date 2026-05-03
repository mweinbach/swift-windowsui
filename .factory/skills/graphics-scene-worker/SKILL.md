---
name: graphics-scene-worker
description: Implements scene-contract, text/atlas, and batch-renderer features in the Swift graphics stack.
---

# Graphics Scene Worker

NOTE: Startup and cleanup are handled by `worker-base`. This skill defines the work procedure.

## When to Use This Skill

Use this skill for features that primarily touch:

- `SwiftWindowsGraphics`
- `ScenePainter`
- text layout / atlas plumbing
- `D3D11BatchRenderer`
- focused graphics or renderer test suites

## Required Skills

None.

## Work Procedure

1. Read the assigned feature, the mission validation contract assertions it fulfills, `.factory/library/architecture.md`, `.factory/library/environment.md`, `.factory/library/zed-reference.md`, and `.factory/services.yaml`.
2. Identify the exact focused test suites or probe surfaces that must prove the assigned assertions.
3. Add or update focused tests first so the missing behavior fails visibly before implementation.
4. Implement the smallest graphics/text/renderer changes that satisfy the feature while preserving backend-neutral semantics above the renderer layer.
5. If the feature touches batch presentation, verify unsupported or incomplete capabilities still fail softly or downgrade cleanly.
6. Keep the edit set inside the feature's declared scope. Do not bundle unrelated graphics/runtime cleanup, and do not touch `extern/zed`.
7. Run the smallest relevant focused suites during iteration.
8. Before finishing, verify `extern/zed` is untouched and review the changed files to confirm they all belong to the feature scope.
9. Before finishing, run:
   - the focused suites for the assigned assertions,
   - `commands.test`,
   - `commands.build`.
10. If the feature changes presenter behavior, atlas upload behavior, or demo launch behavior, run the appropriate demo probe from `.factory/services.yaml`.
11. In the handoff, map every fulfilled assertion to the test/probe evidence that proves it.

## Example Handoff

```json
{
  "salientSummary": "Expanded GPUIScene ordering and replay coverage, then updated ScenePainter batching so scoped-layer replay and family tie precedence match the new contract. Verified focused scene tests plus the full package test/build commands.",
  "whatWasImplemented": "Added focused GPUIScene tests for mixed-family tie precedence, balanced replay ranges, and unsupported style fallback behavior, then updated GPUIScene and GPUISceneBridge so deterministic batch ordering and bridge fallback semantics match the contract without leaking D3D11 details into SwiftWindowsGraphics.",
  "whatWasLeftUndone": "",
  "verification": {
    "commandsRun": [
      {
        "command": "powershell -NoProfile -ExecutionPolicy Bypass -File .factory/windows-swift-env.ps1 swift test --package-path \"C:\\Users\\maxw6\\Projects\\swift-windowsui\" --filter GPUISceneTests",
        "exitCode": 0,
        "observation": "Focused scene tests passed with the new family-order and replay-range coverage."
      },
      {
        "command": "powershell -NoProfile -ExecutionPolicy Bypass -File .factory/windows-swift-env.ps1 swift test --package-path \"C:\\Users\\maxw6\\Projects\\swift-windowsui\"",
        "exitCode": 0,
        "observation": "Full package tests passed."
      },
      {
        "command": "powershell -NoProfile -ExecutionPolicy Bypass -File .factory/windows-swift-env.ps1 swift build --package-path \"C:\\Users\\maxw6\\Projects\\swift-windowsui\" --product swift-windowsui",
        "exitCode": 0,
        "observation": "Executable wiring still builds after the graphics-contract changes."
      }
    ],
    "interactiveChecks": [
      {
        "action": "Manual: launched the demo on the default path after the scene-contract changes.",
        "observed": "Startup remained successful and no immediate rendering regressions appeared on the frame path."
      }
    ]
  },
  "tests": {
    "added": [
      {
        "file": "Tests/SwiftWindowsCoreLogicTests/GPUISceneTests.swift",
        "cases": [
          {
            "name": "testFinishUsesDeterministicFamilyTiePrecedence",
            "verifies": "VAL-SCENE-003 tie precedence stays deterministic for equal-order mixed-family input."
          },
          {
            "name": "testReplayRejectsUnbalancedScopedLayerRange",
            "verifies": "VAL-SCENE-007 unbalanced replay ranges fail safely."
          }
        ]
      }
    ]
  },
  "discoveredIssues": []
}
```

## When to Return to Orchestrator

- The feature requires a host-level seam or test harness outside graphics/text/renderer ownership.
- A contract assertion depends on presenter selection or downgrade behavior that cannot be proven from graphics-layer changes alone.
- The current fallback/default-path policy needs to change in a way that affects mission boundaries.
