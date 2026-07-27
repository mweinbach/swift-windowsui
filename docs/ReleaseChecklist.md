# Release Checklist

Concrete sign-off procedure for cutting a `swift-windowsui` release. This
implements the Phase 9 release gate from
[`docs/StabilizationRoadmap.md`](StabilizationRoadmap.md). Run it on a clean
machine (or a fresh checkout) with the Swift for Windows toolchain available;
verify the toolchain first with
`powershell -NoProfile -ExecutionPolicy Bypass -File scripts/with-swift.ps1 -CheckOnly`.

Versioning rules and Supported-tier guarantees live in
[`CHANGELOG.md`](../CHANGELOG.md). Per-API status lives in
[`docs/CompatibilityStatus.md`](CompatibilityStatus.md) — the matrix for the
release version must be published (and agree with reality) before tagging.

## 1. Automated gate

All of the following must pass on the release commit, serially (never two
SwiftPM commands against the same `.build` in parallel):

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/with-swift.ps1 -CheckOnly
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/agent-check.ps1 -Full
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/lint.ps1 -AllSwift
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/test.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/build.ps1 -Product swift-windowsui
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/build.ps1 -Product swift-windowsui-snapshot
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/build.ps1 -Product swift-windowsui-gallery
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/demo-probe.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/demo-screenshot.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/demo-screenshot.ps1 -FrameDebug -OutputPath artifacts/demo-screenshot-frame.png
```

- [ ] `-Full` green: full test suite, demo build, scene + frame screenshots,
      gallery regression gate (25 baselines)
- [ ] `lint.ps1 -AllSwift` clean
- [ ] Windows CI (`.github/workflows/windows-ci.yml`) Full stage green on the
      release commit, with screenshot artifacts uploaded
- [ ] Scene and frame screenshot artifacts inspected by eye
      (`artifacts/demo-screenshot.png`,
      `artifacts/demo-screenshot-frame.png`) and attached to the release or
      linked CI run

## 2. Manual release smoke

These items are not automated; perform each one on real hardware and record
the result. Launch the demo with `scripts/run-demo.ps1` (or
`swift run swift-windowsui`) unless noted.

- [ ] **Core interaction:** launch `swift-windowsui`; resize the window,
      scroll all three demo tabs, tab through keyboard focus, activate
      buttons with keyboard and mouse
- [ ] **Multi-window open/close:** settings tab → "Open Second Window"
      (`openWindow(id:)`); confirm the second window renders independently,
      dismiss it, and confirm the primary window is unaffected; close all
      windows and confirm clean exit
- [ ] **Live CJK IME:** focus a `TextField`, compose with a real IME (e.g.
      Microsoft Pinyin or Japanese IME); confirm marked/underlined
      composition text, candidate window at the caret, and correct commit
- [ ] **File drag/drop:** drag files from Explorer onto an `onDrop`
      destination (the shared demo does not currently host one — use a
      scratch harness view or the host drop tests); confirm `onDrop`
      receives the file URLs
- [ ] **Real file dialogs:** invoke the `fileImporter` / `fileExporter`
      flows (no demo surface yet — use a scratch harness view); confirm
      the native Win32 open/save dialogs appear, honor the extension
      filters, and deliver URLs to the app closure
- [ ] **Native color dialog opt-in:** place a `ColorPicker` with
      `\.colorPickerUsesNativeDialog` enabled (no demo surface yet — use a
      scratch harness view), confirm the Win32 `ChooseColorW` dialog
      appears and writes the binding; disable the opt-in and confirm the
      keyboard palette still works
- [ ] **Narrator / UIA pass:** run Narrator (or
      `scripts/demo-uia-probe.ps1` plus a Narrator spot check) over the
      primary demo controls; confirm labels are read, control types are
      sensible, and the default button action activates via InvokePattern
- [ ] **High-contrast theme toggle:** enable a Windows high-contrast theme
      while the demo is running; confirm `colorSchemeContrast` updates
      without an app restart and Supported controls stay legible; toggle
      back and confirm recovery
- [ ] **Frosted materials on hardware:** on a real GPU (not WARP), confirm
      `.regularMaterial` / `.thinMaterial` panels show true backdrop blur
      and remain correct while content scrolls beneath them
- [ ] **Frame-debug fallback run:** launch with
      `SWIFT_WINDOWSUI_FRAME_DEBUG=1`; confirm the app runs on the frame
      path and Supported controls degrade readably (known cosmetic gaps:
      rectangular clips, uniform corner radii, solid base color for
      radial/conic gradients, plain offset shadows)
- [ ] **Recovery smoke (optional but recommended):** confirm
      `rendererHealthSnapshot` reports `.defaultScene` in a normal run

## 3. Documentation and metadata

- [ ] `CHANGELOG.md` has an entry for the release version with
      Added/Changed/Fixed and a known-limitations section; the
      `Unreleased` marker is replaced by the tag date
- [ ] `docs/CompatibilityStatus.md` matrix is current for the release
      version; no Supported API is documented as working when it is a
      placeholder or no-op
- [ ] `README.md`, `docs/WinSwiftUI.md`, `docs/Testing.md`,
      `docs/GPURenderingPipeline.md`, `docs/CompatibilityStatus.md`, and
      `docs/StabilizationRoadmap.md` agree on: default presentation path
      (scene/batch + frame fallback), Windows-only status, SwiftUI parity
      limits, text/IME level, UIA level, multi-window level
- [ ] Roadmap Phase 9 exit criteria reviewed; boxes checked only where
      honestly met
- [ ] Demo and gallery exercise Supported-tier (Implemented / safe-Partial)
      APIs only — no placeholder panels, no no-op shims driving visible
      behavior

## 4. Tag and publish

- [ ] Tag `v<version>` on the exact commit that passed sections 1–3
- [ ] Attach or link scene + frame screenshot artifacts to the release
- [ ] Record any manual-smoke deviations in the release notes

## Sign-off

| Field | Value |
| --- | --- |
| Version | |
| Commit | |
| Date | |
| Automated gate (section 1) | |
| Manual smoke (section 2) | |
| Known deviations | |
