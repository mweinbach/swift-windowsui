# Environment

Environment variables, external dependencies, and setup notes.

**What belongs here:** required local toolchains, shell wrappers, external references, platform constraints.
**What does NOT belong here:** feature definitions, assertion ownership, or service port policy.

---

## Platform

- Repository: `C:\Users\maxw6\Projects\swift-windowsui`
- OS: Windows only
- No network services, databases, or external credentials are required for this mission.

## Required Local Tooling

- Visual Studio developer shell via `VsDevCmd.bat`
- Swift 6.3 toolchain
- Swift 6.3 runtime DLLs
- Swift Windows SDK via `SDKROOT`

Workers should not assume these are already present in the shell. Always use `.factory/windows-swift-env.ps1` or commands from `.factory/services.yaml`.

## Shell Normalization

`windows-swift-env.ps1` is the source of truth for Swift command execution in this repo. It:

1. loads the Visual Studio developer environment,
2. prepends Swift runtime and toolchain paths to `PATH`,
3. sets `SDKROOT` to the Swift Windows SDK,
4. runs the requested command.

If Swift commands fail with missing `link`, missing DLLs, or missing standard library errors, the shell was not normalized correctly.

## External Reference Material

- Zed reference checkout: `extern/zed`
- Treat `extern/zed` as read-only architecture reference material.
- Do not add `extern/zed` to the Swift package graph.
