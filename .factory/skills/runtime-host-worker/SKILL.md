---
name: runtime-host-worker
description: Implements retained-runtime, WinSwiftUI host, and cross-area validation-harness features.
---

# Runtime Host Worker

NOTE: Startup and cleanup are handled by `worker-base`. This skill defines the work procedure.

## When to Use This Skill

Use this skill for features that primarily touch:

- `RetainedViewRuntime`
- `WinSwiftUIWindowHost`
- Win32 host event translation
- presenter selection and fallback
- host-focused integration tests and launch-probe observability

## Required Skills

None.

## Work Procedure

1. Read the assigned feature, the validation assertions it fulfills, `.factory/library/architecture.md`, and `.factory/services.yaml`. Read `.factory/library/user-testing.md` when the feature changes validation surfaces, host/demo probes, or user-testing setup assumptions.
2. Identify the host/runtime seams that must be observable for the assigned assertions. If the contract references a focused suite such as `WinSwiftUIWindowHostTests`, create or extend that suite first.
3. Add failing focused tests before implementation. For scrutiny or evidence-hardening fixes, strengthening an existing focused test in place is acceptable if it directly closes the cited proof gap. Prefer fake backend / fake window seams over manual reasoning. IMPORTANT: For scrutiny fixes, do NOT use mirrored helper hosts (like `TestableInputRecordingHost` or `TestableRuntimeObservingHost`) that bypass the real `WinSwiftUIWindowHost` logic; test the actual production pathways end-to-end. Refer to `.factory/library/host-runtime-test-seams.md` for the factual DPI, refresh-rate, and event production seams.
4. Implement the runtime/host changes while preserving:
   - retained-runtime ownership of layout/prepaint/interaction state,
   - backend-neutral scene semantics,
   - frame-path fallback safety.
5. If the feature changes presenter selection, downgrade logic, refresh pacing, or observed-object batching, add explicit observable evidence for those behaviors.
6. Deferred-subtree scene behavior depends on runtime-owned prepaint state; raw `ScenePainter.paint()` is not a sufficient harness for deferred-subtree replay or ancestor-routing assertions unless the feature explicitly proves the runtime seam is irrelevant.
7. If the validation contract explicitly requires evidence in both `RetainedViewRuntimeTests` and `ScenePainterTests`, land proof in both harnesses; runtime-owned prepaint notes do not relax the dual-suite requirement.
8. Keep the edit set inside the feature's declared scope. Do not bundle unrelated graphics cleanup, and do not touch `extern/zed`.
9. Run the smallest relevant focused suites during iteration.
10. Before finishing, verify `extern/zed` is untouched and review the changed files to confirm they all belong to the feature scope.
11. Before finishing, run:
   - the focused suites for the assigned assertions,
   - `commands.test`,
   - `commands.build`.
12. If the feature changes startup or presenter selection behavior, run the appropriate demo probe from `.factory/services.yaml` and capture the backend-selection or downgrade evidence.
13. In the handoff, explicitly list which fulfilled assertions were proven by tests vs demo probes.

## Example Handoff

```json
{
  "salientSummary": "Added a dedicated WinSwiftUIWindowHost test harness, then implemented presenter-selection and downgrade observability so host startup, resize fallback, and runtime pacing are contract-testable. Verified the host suite, full tests, build, and a demo launch probe.",
  "whatWasImplemented": "Created WinSwiftUIWindowHost-focused fake backend coverage for attach/resize/render downgrade, runtime scale propagation, and observed-object coalescing. Updated WinSwiftUIWindowHost to expose backend-selection evidence and to preserve deferred replay correctness across host-driven downgrade.",
  "whatWasLeftUndone": "",
  "verification": {
    "commandsRun": [
      {
        "command": "powershell -NoProfile -ExecutionPolicy Bypass -File .factory/windows-swift-env.ps1 swift test --package-path \"C:\\Users\\maxw6\\Projects\\swift-windowsui\" --filter WinSwiftUIWindowHostTests",
        "exitCode": 0,
        "observation": "Host-focused startup, fallback, resize, and observation tests passed."
      },
      {
        "command": "powershell -NoProfile -ExecutionPolicy Bypass -File .factory/windows-swift-env.ps1 swift test --package-path \"C:\\Users\\maxw6\\Projects\\swift-windowsui\"",
        "exitCode": 0,
        "observation": "Full package tests passed after the host/runtime changes."
      },
      {
        "command": "powershell -NoProfile -ExecutionPolicy Bypass -File .factory/windows-swift-env.ps1 swift build --package-path \"C:\\Users\\maxw6\\Projects\\swift-windowsui\" --product swift-windowsui",
        "exitCode": 0,
        "observation": "The executable still builds."
      }
    ],
    "interactiveChecks": [
      {
        "action": "Manual: launched the demo with the default presenter path after adding presenter-selection evidence.",
        "observed": "Startup succeeded and the probe captured frame-presenter selection as expected."
      }
    ]
  },
  "tests": {
    "added": [
      {
        "file": "Tests/SwiftWindowsCoreLogicTests/WinSwiftUIWindowHostTests.swift",
        "cases": [
          {
            "name": "testBatchRenderFailureFallsBackToFrameAndRendersSameFrame",
            "verifies": "VAL-RENDER-004 and VAL-CROSS-007 same-session downgrade behavior."
          },
          {
            "name": "testObservedObjectReloadsCoalesceWithinOneTurn",
            "verifies": "VAL-CROSS-010 observed-object batching."
          }
        ]
      }
    ]
  },
  "discoveredIssues": []
}
```

## When to Return to Orchestrator

- The feature requires graphics/text/renderer behavior that cannot be exercised from host/runtime seams alone.
- The contract depends on a new mission boundary, such as changing the default presenter before parity gates are complete.
- The only remaining proof would require manual validation outside the current native demo surface.
