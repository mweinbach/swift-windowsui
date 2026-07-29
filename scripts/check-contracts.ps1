param()

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent $PSScriptRoot
$failures = New-Object System.Collections.Generic.List[string]

function Add-Failure {
    param([string]$Message)
    $script:failures.Add($Message) | Out-Null
}

function Get-RepoPath {
    param([string]$RelativePath)
    Join-Path $repoRoot $RelativePath
}

function Read-RepoFile {
    param([string]$RelativePath)

    $path = Get-RepoPath $RelativePath
    if (-not (Test-Path -LiteralPath $path)) {
        Add-Failure "$RelativePath is missing."
        return ""
    }

    Get-Content -LiteralPath $path -Raw
}

function Assert-PathExists {
    param(
        [string]$RelativePath,
        [string]$Message
    )

    if (-not (Test-Path -LiteralPath (Get-RepoPath $RelativePath))) {
        Add-Failure $Message
    }
}

function Assert-Contains {
    param(
        [string]$RelativePath,
        [string]$Pattern,
        [string]$Message
    )

    $text = Read-RepoFile $RelativePath
    if ($text -notmatch $Pattern) {
        Add-Failure $Message
    }
}

function Assert-NotContains {
    param(
        [string]$RelativePath,
        [string]$Pattern,
        [string]$Message
    )

    $text = Read-RepoFile $RelativePath
    if ($text -match $Pattern) {
        Add-Failure $Message
    }
}

function Assert-NoMatchesInRoots {
    param(
        [string[]]$Roots,
        [string]$Pattern,
        [string]$Message
    )

    foreach ($root in $Roots) {
        $rootPath = Get-RepoPath $root
        if (-not (Test-Path -LiteralPath $rootPath)) {
            continue
        }

        $matches = Get-ChildItem -LiteralPath $rootPath -Recurse -File |
            Select-String -Pattern $Pattern

        if ($matches) {
            foreach ($match in $matches) {
                Add-Failure "$Message Found at $($match.Path):$($match.LineNumber)."
            }
        }
    }
}

function Assert-NoTestBaselineImageDirectories {
    # Test runs must never write generated images into the source tree. A
    # self-healing reference-image harness used to do exactly that (recording
    # whatever the renderer produced as the baseline on first run); reviewed
    # baselines live in scripts/gallery-compare.ps1 and the golden-hash
    # suites, and everything generated belongs under artifacts/ or the OS
    # temp directory.
    $testsPath = Get-RepoPath "Tests"
    if (-not (Test-Path -LiteralPath $testsPath)) {
        return
    }

    $baselineDirectories = Get-ChildItem -LiteralPath $testsPath -Recurse -Directory -Force |
        Where-Object { $_.Name -eq "ReferenceImages" }

    foreach ($directory in $baselineDirectories) {
        Add-Failure "Remove generated baseline directory $($directory.FullName); test output belongs under artifacts/ or the OS temp directory, and baselines must be reviewed, not self-healed."
    }
}

function Assert-NoRootScratchFiles {
    $scratchPatterns = @(
        ".*\.log$",
        "^all_errors\.txt$",
        "^full_test\d*\.txt$",
        "^test\d*\.txt$",
        "^test_output\d*\.txt$",
        "^screenshot.*\.png$"
    )

    $rootFiles = Get-ChildItem -LiteralPath $repoRoot -File -Force
    foreach ($file in $rootFiles) {
        foreach ($pattern in $scratchPatterns) {
            if ($file.Name -match $pattern) {
                Add-Failure "Remove generated root scratch file $($file.Name); use artifacts/ or the OS temp directory instead."
                break
            }
        }
    }
}

Assert-PathExists "AGENTS.md" "AGENTS.md must exist at the repo root for agent handoff."
Assert-PathExists "CLAUDE.md" "CLAUDE.md must exist at the repo root for agent handoff."
Assert-PathExists ".swift-format" ".swift-format must exist so Swift formatting is deterministic."

Assert-Contains "CLAUDE.md" "@AGENTS\.md" "CLAUDE.md must import AGENTS.md so both agent context files share one source of truth."
Assert-Contains "AGENTS.md" "SwiftUI on Windows" "AGENTS.md must state the SwiftUI-on-Windows goal."
Assert-Contains "AGENTS.md" "GPUI" "AGENTS.md must state the GPUI-inspired rendering target."
Assert-Contains "AGENTS.md" "RetainedViewRuntime" "AGENTS.md must anchor agents on the retained runtime."
Assert-Contains "AGENTS.md" "paintOperations" "AGENTS.md must preserve the paintOperations presentation contract."
Assert-Contains "AGENTS.md" "agent-check\.ps1" "AGENTS.md must document the agent validation loop."
Assert-Contains "README.md" "scripts/agent-check\.ps1" "README.md must point contributors to the agent check script."
Assert-Contains "docs/Testing.md" "agent-check\.ps1" "docs/Testing.md must document the agent check script."

Assert-Contains `
    "Sources/SwiftWindowsGraphics/GPUIScene.swift" `
    "paintOperations" `
    "GPUIScene must expose paintOperations as the source paint stream."
Assert-Contains `
    "Sources/SwiftWindowsGraphics/GPUIScene.swift" `
    "remapPaintOperations" `
    "GPUIScene.finish() must remap paintOperations after primitive sorting."
Assert-Contains `
    "Sources/SwiftWindowsRendererD3D11/D3D11BatchRenderer.swift" `
    "layer\.paintOperations" `
    "D3D11BatchRenderer must consume layer.paintOperations for presentation order."
Assert-NotContains `
    "Sources/SwiftWindowsRendererD3D11/D3D11BatchRenderer.swift" `
    "orderedBatches\(" `
    "D3D11BatchRenderer must not plan visible presentation from orderedBatches()."
Assert-Contains `
    "Sources/SwiftWindowsGraphics/SceneRasterizer.swift" `
    "layer\.paintOperations" `
    "GPUIRawSceneRasterizer must consume layer.paintOperations for scene screenshots."
Assert-Contains `
    "Sources/SwiftWindowsUI/ScenePainter.swift" `
    "skipCacheUpdates" `
    "ScenePainter must keep skipCacheUpdates for offscreen compositing."
Assert-Contains `
    "Sources/SwiftWindowsUI/ScenePainter.swift" `
    "if !skipCacheUpdates" `
    "ScenePainter cache writes must be guarded by skipCacheUpdates."

Assert-Contains `
    "Sources/SwiftWindowsDemo/DemoDashboard.swift" `
    "#if canImport\(SwiftUI\)" `
    "The shared demo must keep the SwiftUI/WinSwiftUI conditional import."
Assert-Contains `
    "Sources/SwiftWindowsDemo/DemoDashboard.swift" `
    "import WinSwiftUI" `
    "The shared demo must keep the WinSwiftUI fallback import."
Assert-NotContains `
    "Sources/SwiftWindowsDemo/DemoDashboard.swift" `
    "(?m)^\s*for\s+\w+\s+in\s+" `
    "The shared demo must not use raw for loops in ViewBuilder source; use ForEach."

Assert-Contains `
    "Sources/swift-windowsui-snapshot/SnapshotMain.swift" `
    "(?s)case \.scene:.*return \.rawScene" `
    "Snapshot --mode scene must default to the raw GPUIScene screenshot path."
Assert-Contains `
    "Sources/swift-windowsui-snapshot/SnapshotMain.swift" `
    "(?s)case \.frame:.*return \.rawFrame" `
    "Snapshot --mode frame must default to the raw RenderFrame screenshot path."
Assert-Contains `
    "scripts/demo-screenshot.ps1" `
    "swift-windowsui-snapshot" `
    "demo-screenshot.ps1 must use swift-windowsui-snapshot."
$desktopCapturePattern = "Copy" + "FromScreen"
Assert-NoMatchesInRoots `
    @("Sources", "scripts") `
    $desktopCapturePattern `
    "Desktop capture is not an acceptable screenshot validation path."
Assert-NoRootScratchFiles
Assert-NoTestBaselineImageDirectories

# MARK: Phase 8 — target dependency direction
#
# Allowed internal imports per library target, derived from the declared
# dependencies in Package.swift and the layered architecture (bottom to top):
#
#   SwiftWindowsCore          (no internal imports)
#   SwiftWindowsGraphics      → Core
#   SwiftWindowsLayout        → Core
#   SwiftWindowsPlatform      → Core, CUIAInterop
#   SwiftWindowsScene         → Core, Graphics            (legacy/secondary)
#   SwiftWindowsRendererD3D11 → Core, Graphics, CDirect2DInterop
#   SwiftWindowsUI            → Core, Graphics, Layout, Platform, CDirect2DInterop
#   SwiftWindowsApp           → UI, RendererD3D11         (legacy/secondary)
#   WinSwiftUI                → Core, Graphics, Layout, Platform, UI (+CUIAInterop
#                               transitively via Platform for the UIA bridge)
#   SwiftWindowsDemo          → WinSwiftUI only           (same-source demo)
#
# Executables (swift-windowsui, -snapshot, -gallery, macos-reference-renderer)
# are composition roots and may import any internal module; they are not
# scanned. Anything not listed as allowed above is forbidden below.
$script:dependencyDirectionRules = @(
    @{
        Root      = "Sources/SwiftWindowsCore"
        Forbidden = @(
            "SwiftWindowsGraphics", "SwiftWindowsLayout", "SwiftWindowsPlatform",
            "SwiftWindowsScene", "SwiftWindowsUI", "SwiftWindowsRendererD3D11",
            "SwiftWindowsApp", "WinSwiftUI", "SwiftWindowsDemo",
            "CDirect2DInterop", "CUIAInterop"
        )
    },
    @{
        Root      = "Sources/SwiftWindowsGraphics"
        Forbidden = @(
            "SwiftWindowsLayout", "SwiftWindowsPlatform", "SwiftWindowsScene",
            "SwiftWindowsUI", "SwiftWindowsRendererD3D11", "SwiftWindowsApp",
            "WinSwiftUI", "SwiftWindowsDemo", "CDirect2DInterop", "CUIAInterop"
        )
    },
    @{
        Root      = "Sources/SwiftWindowsLayout"
        Forbidden = @(
            "SwiftWindowsGraphics", "SwiftWindowsPlatform", "SwiftWindowsScene",
            "SwiftWindowsUI", "SwiftWindowsRendererD3D11", "SwiftWindowsApp",
            "WinSwiftUI", "SwiftWindowsDemo", "CDirect2DInterop", "CUIAInterop"
        )
    },
    @{
        Root      = "Sources/SwiftWindowsPlatform"
        Forbidden = @(
            "SwiftWindowsGraphics", "SwiftWindowsLayout", "SwiftWindowsScene",
            "SwiftWindowsUI", "SwiftWindowsRendererD3D11", "SwiftWindowsApp",
            "WinSwiftUI", "SwiftWindowsDemo", "CDirect2DInterop"
        )
    },
    @{
        Root      = "Sources/SwiftWindowsScene"
        Forbidden = @(
            "SwiftWindowsLayout", "SwiftWindowsPlatform", "SwiftWindowsUI",
            "SwiftWindowsRendererD3D11", "SwiftWindowsApp", "WinSwiftUI",
            "SwiftWindowsDemo", "CDirect2DInterop", "CUIAInterop"
        )
    },
    @{
        Root      = "Sources/SwiftWindowsRendererD3D11"
        Forbidden = @(
            "SwiftWindowsLayout", "SwiftWindowsPlatform", "SwiftWindowsScene",
            "SwiftWindowsUI", "SwiftWindowsApp", "WinSwiftUI", "SwiftWindowsDemo",
            "CUIAInterop"
        )
    },
    @{
        Root      = "Sources/SwiftWindowsUI"
        Forbidden = @(
            "SwiftWindowsScene", "SwiftWindowsRendererD3D11", "SwiftWindowsApp",
            "WinSwiftUI", "SwiftWindowsDemo", "CUIAInterop"
        )
    },
    @{
        Root      = "Sources/SwiftWindowsApp"
        Forbidden = @("SwiftWindowsScene", "WinSwiftUI", "SwiftWindowsDemo")
    },
    @{
        # The facade is renderer-neutral: the D3D11 backend is selected by the
        # app composition root, never imported here.
        Root      = "Sources/WinSwiftUI"
        Forbidden = @(
            "SwiftWindowsScene", "SwiftWindowsRendererD3D11", "SwiftWindowsApp",
            "SwiftWindowsDemo", "CDirect2DInterop"
        )
    },
    @{
        Root      = "Sources/SwiftWindowsDemo"
        Forbidden = @(
            "SwiftWindowsCore", "SwiftWindowsGraphics", "SwiftWindowsLayout",
            "SwiftWindowsPlatform", "SwiftWindowsScene", "SwiftWindowsUI",
            "SwiftWindowsRendererD3D11", "SwiftWindowsApp",
            "CDirect2DInterop", "CUIAInterop"
        )
    }
)

foreach ($rule in $script:dependencyDirectionRules) {
    $rootPath = Get-RepoPath $rule.Root
    if (-not (Test-Path -LiteralPath $rootPath)) {
        continue
    }

    $swiftFiles = Get-ChildItem -LiteralPath $rootPath -Recurse -File -Filter *.swift
    foreach ($file in $swiftFiles) {
        $importMatches = Select-String -LiteralPath $file.FullName -Pattern "(?m)^\s*(?:@_\w+\s+)*import\s+(?:(?:struct|class|enum|protocol|func|var|typealias)\s+)?([A-Za-z_][A-Za-z0-9_]*)"
        foreach ($importMatch in $importMatches) {
            $module = $importMatch.Matches[0].Groups[1].Value
            if ($rule.Forbidden -contains $module) {
                Add-Failure "$($rule.Root) must not import $module (target dependency direction; see Package.swift and the Phase 8 rules in check-contracts.ps1). Found at $($file.FullName):$($importMatch.LineNumber)."
            }
        }
    }
}

# WinSwiftUI must not declare a target dependency on the D3D11 backend; the
# Windows product selects it at the composition root instead.
$packageManifest = Read-RepoFile "Package.swift"
if ($packageManifest -match '(?s)name:\s*"WinSwiftUI"\s*,\s*dependencies:\s*\[(?<deps>[^\]]*)\]') {
    if ($Matches.deps -match "SwiftWindowsRendererD3D11") {
        Add-Failure "Package.swift: the WinSwiftUI target must not depend on SwiftWindowsRendererD3D11; the facade stays renderer-neutral behind RenderBackendFactory and the composition root picks the backend."
    }
} else {
    Add-Failure "Package.swift must declare a WinSwiftUI target with an explicit dependency list."
}

# The product composition root must keep pinning the D3D11 GPU factory so the
# app default stays scene/batch on the GPU with frame fallback.
if ($packageManifest -match '(?s)name:\s*"swift-windowsui"\s*,\s*dependencies:\s*\[(?<deps>[^\]]*)\]') {
    if ($Matches.deps -notmatch "SwiftWindowsRendererD3D11") {
        Add-Failure "Package.swift: the swift-windowsui executable (composition root) must depend on SwiftWindowsRendererD3D11 so the product keeps the D3D11 GPU backend."
    }
} else {
    Add-Failure "Package.swift must declare a swift-windowsui executable target with an explicit dependency list."
}
Assert-Contains `
    "Sources/swift-windowsui/AppEntry.swift" `
    "D3D11RenderBackendFactory" `
    "The swift-windowsui composition root must override renderBackendFactory() with D3D11RenderBackendFactory so the product default stays the D3D11 GPU backend."
Assert-NotContains `
    "Sources/WinSwiftUI/App.swift" `
    "SwiftWindowsRendererD3D11" `
    "WinSwiftUI/App.swift must not reference the D3D11 backend; the facade default is the backend-neutral CPURenderBackendFactory."
Assert-NotContains `
    "Sources/WinSwiftUI/WindowCoordinator.swift" `
    "SwiftWindowsRendererD3D11" `
    "WinSwiftUI/WindowCoordinator.swift must not reference the D3D11 backend; factories are injected via RenderBackendFactory."

function Assert-SinglePresentCallSite {
    param(
        [string] $RelativePath,
        [string] $Message
    )

    $fullPath = Get-RepoPath $RelativePath
    if (-not (Test-Path -LiteralPath $fullPath)) {
        Add-Failure "$RelativePath is missing; cannot verify its presentation contract."
        return
    }

    $content = Get-Content -LiteralPath $fullPath -Raw
    $matchCount = ([regex]::Matches($content, "\.Present\(")).Count
    if ($matchCount -ne 1) {
        Add-Failure "$RelativePath has $matchCount Present call sites (expected 1). $Message"
    }
}

# A renderer with two Present call sites can present the same frame twice —
# which is exactly what happened when the Direct2D branch presented inside its
# own `do` block and then fell through to the D3D11 path on any error,
# including an error the Present itself raised. One call site per swap-chain
# owner keeps present-result classification and frame pacing honest.
Assert-SinglePresentCallSite `
    "Sources/SwiftWindowsRendererD3D11/D3D11Renderer.swift" `
    "Both draw paths must end at the single presentFrame(swapChain:) helper so a present error cannot be attributed to Direct2D and cannot double-present a frame."
Assert-SinglePresentCallSite `
    "Sources/SwiftWindowsRendererD3D11/D3D11BatchRenderer.swift" `
    "The batch backend must present only from presentFrame(), where the HRESULT is classified by DeviceLostPolicy."

# `detach()` is the only thing in the stack that owns GPU resource lifetime,
# and a protocol-extension default let a backend holding a device, a swap
# chain and two atlases satisfy it by inheriting an empty implementation --
# leaking exactly as it did before the requirement existed. A bare
# requirement makes every conformer state its teardown, no-op included.
Assert-NotContains `
    "Sources/SwiftWindowsGraphics/RenderGraph.swift" `
    "extension RenderBackend \{[\s\S]*?func detach\(\) \{\}" `
    "RenderBackend must not supply a default detach(); a backend that owns a device would inherit a silent no-op teardown."
Assert-NotContains `
    "Sources/SwiftWindowsGraphics/BatchRenderBackend.swift" `
    "extension BatchRenderBackend \{[\s\S]*?func detach\(\) \{\}" `
    "BatchRenderBackend must not supply a default detach(); a backend that owns a swap chain would inherit a silent no-op teardown."

function Assert-SwapChainOwnerImplementsDetach {
    param(
        [string] $RelativePath
    )

    $fullPath = Get-RepoPath $RelativePath
    if (-not (Test-Path -LiteralPath $fullPath)) {
        Add-Failure "$RelativePath is missing; cannot verify its teardown contract."
        return
    }

    $content = Get-Content -LiteralPath $fullPath -Raw
    if ($content -notmatch "CreateSwapChainForHwnd\(") {
        return
    }
    if ($content -notmatch "func detach\(\)\s*\{") {
        Add-Failure "$RelativePath creates an HWND swap chain but defines no detach(); the swap chain pins the window and nothing else in the process can release it."
    }
}

# Anything that binds a swap chain to an HWND owns a resource the rest of the
# process cannot reach. It has to define its own teardown, not inherit one.
Assert-SwapChainOwnerImplementsDetach "Sources/SwiftWindowsRendererD3D11/D3D11Renderer.swift"
Assert-SwapChainOwnerImplementsDetach "Sources/SwiftWindowsRendererD3D11/D3D11BatchRenderer.swift"

function Assert-SwapChainWindowAssociation {
    param(
        [string] $RelativePath
    )

    $fullPath = Get-RepoPath $RelativePath
    if (-not (Test-Path -LiteralPath $fullPath)) {
        Add-Failure "$RelativePath is missing; cannot verify its swap-chain window association."
        return
    }

    $content = Get-Content -LiteralPath $fullPath -Raw
    $swapChainCount = ([regex]::Matches($content, "CreateSwapChainForHwnd\(")).Count
    $associationCount = ([regex]::Matches($content, "MakeWindowAssociation\(")).Count
    if ($swapChainCount -eq 0) {
        return
    }

    if ($associationCount -lt $swapChainCount) {
        Add-Failure "$RelativePath creates $swapChainCount HWND swap chain(s) but calls MakeWindowAssociation $associationCount time(s); DXGI keeps its default Alt+Enter / Print Screen hooks on any window that is missed."
    }
}

# DXGI installs its own window hooks the moment a swap chain is bound to an
# HWND: Alt+Enter becomes a fullscreen mode switch and Print Screen becomes a
# DXGI capture, neither of which this stack implements. Every swap-chain owner
# must opt out for the window it just claimed.
Assert-SwapChainWindowAssociation "Sources/SwiftWindowsRendererD3D11/D3D11Renderer.swift"
Assert-SwapChainWindowAssociation "Sources/SwiftWindowsRendererD3D11/D3D11BatchRenderer.swift"

if ($failures.Count -gt 0) {
    Write-Host "Contract checks failed:" -ForegroundColor Red
    foreach ($failure in $failures) {
        Write-Host " - $failure" -ForegroundColor Red
    }
    exit 1
}

Write-Host "Contract checks passed."
exit 0
