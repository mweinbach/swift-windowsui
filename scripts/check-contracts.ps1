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

if ($failures.Count -gt 0) {
    Write-Host "Contract checks failed:" -ForegroundColor Red
    foreach ($failure in $failures) {
        Write-Host " - $failure" -ForegroundColor Red
    }
    exit 1
}

Write-Host "Contract checks passed."
exit 0
