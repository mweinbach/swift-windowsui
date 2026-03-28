# User Testing

Validation surfaces, tools, and concurrency guidance for this mission.

**What belongs here:** testable surfaces, probe commands, evidence expectations, concurrency limits, manual validation notes.
**What does NOT belong here:** feature decomposition or implementation tasks.

---

## Validation Surface

### Surface: Swift test suites

- Primary automated surface for scene, runtime, text, atlas, host, and renderer assertions.
- Use `.factory/services.yaml` commands or the same wrapper pattern manually.
- Expected evidence:
  - passing terminal output,
  - focused suite names,
  - any assertion-specific logs required by the contract.

### Surface: Build verification

- `swift build --product swift-windowsui`
- Used to prove executable wiring stays intact after runtime/renderer changes.

### Surface: Native demo launch probes

- Frame path: `demo_frame`
- Batch path: `demo_batch`
- Expected evidence:
  - successful startup,
  - explicit presenter selection or downgrade evidence,
  - no crash on initial launch.

Manual interaction probes are allowed when a feature changes presenter selection, fallback, clipping, text, or image behavior and no equivalent focused automated assertion exists yet.

## Validation Concurrency

### Surface: Swift test suites

- Max concurrent validators: `1`
- Reasoning:
  - the mission depends on a normalized Windows shell wrapper,
  - the repo builds native Windows/D3D11 targets,
  - user requested environment normalization first and serial validation is the conservative posture.

### Surface: Demo launch probes

- Max concurrent validators: `1`
- Reasoning:
  - only one native demo window should be under validation at a time,
  - presenter selection and downgrade evidence become ambiguous with concurrent launches.

## Validator Guidance

- Prefer focused suites first, then run full `test` and `build` before concluding a feature.
- If a contract assertion references a test suite that does not exist yet, that feature is expected to create the focused suite or equivalent coverage.
- Treat batch-image and renderer-atlas assertions as end-to-end gates; do not mark them passed from runtime-only evidence.

## Flow Validator Guidance: Swift test suites

- Isolation boundary:
  - Run from the repository at `C:\Users\maxw6\Projects\swift-windowsui`.
  - Use `.factory/windows-swift-env.ps1` or the equivalent command from `.factory/services.yaml` for every Swift command.
  - Write only the assigned flow report under `.factory/validation/<milestone>/user-testing/flows/` and evidence under the assigned mission evidence directory.
- Concurrency:
  - Treat Swift validation as single-lane for this mission; do not overlap Swift test invocations with other validators.
  - Keep each flow scoped to its assigned assertion IDs and focused suite/tool.
- Safety and evidence:
  - Do not edit source files during validation.
  - Capture the exact command run, exit code, relevant suite names, and a concise assertion-to-evidence mapping in the flow report.
  - If a focused suite fails, stop that flow after collecting enough output to explain the failure instead of running broader validators.
