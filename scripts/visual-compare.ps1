<#
.SYNOPSIS
    Visual comparison script for SwiftWindowsUI rendering backends.

.DESCRIPTION
    Renders the demo dashboard through three backends (raw-scene, raw-frame,
    cpu-batch), writes BMPs, computes pixel diffs, and generates an HTML
    comparison report.

.PARAMETER Width
    Snapshot width in pixels (default: 1280).

.PARAMETER Height
    Snapshot height in pixels (default: 720).

.PARAMETER Scale
    Display scale factor (default: 1.0).

.PARAMETER OutputDir
    Directory for outputs (default: artifacts/visual-compare).

.PARAMETER SkipBuild
    If set, skip building the snapshot executable.

.EXAMPLE
    powershell -NoProfile -ExecutionPolicy Bypass -File scripts/visual-compare.ps1
    powershell -NoProfile -ExecutionPolicy Bypass -File scripts/visual-compare.ps1 -Width 640 -Height 360
#>
param(
    [int] $Width = 1280,
    [int] $Height = 720,
    [double] $Scale = 1.0,
    [string] $OutputDir = "artifacts/visual-compare",
    [switch] $SkipBuild
)

$ErrorActionPreference = "Stop"

function Write-Step {
    param([string] $Message)
    Write-Host "[visual-compare] $Message" -ForegroundColor Cyan
}

function Ensure-Dir {
    param([string] $Path)
    if (-not (Test-Path $Path)) {
        New-Item -ItemType Directory -Path $Path -Force | Out-Null
    }
}

function Run-Snapshot {
    param(
        [string] $Backend,
        [string] $OutPath
    )
    $args = @(
        "--output", $OutPath,
        "--width", "$Width",
        "--height", "$Height",
        "--scale", "$Scale",
        "--backend", $Backend,
        "--html-report"
    )
    & .build/debug/swift-windowsui-snapshot.exe @args
    if ($LASTEXITCODE -ne 0) {
        throw "Snapshot failed for backend: $Backend"
    }
}

function Compute-PixelDiff {
    param(
        [string] $PathA,
        [string] $PathB,
        [string] $DiffPath
    )
    # Simple pixel diff using ImageMagick if available; otherwise skip.
    $magick = Get-Command magick -ErrorAction SilentlyContinue
    if (-not $magick) {
        Write-Step "ImageMagick not found; skipping pixel diff generation."
        return $null
    }

    & magick compare -metric RMSE "$PathA" "$PathB" "$DiffPath" 2>$null
    if ($LASTEXITCODE -eq 0 -or $LASTEXITCODE -eq 1) {
        return $DiffPath
    }
    return $null
}

# ── Setup ────────────────────────────────────────────────────────────────────

Write-Step "Output directory: $OutputDir"
Ensure-Dir $OutputDir

# ── Build ──────────────────────────────────────────────────────────────────

if (-not $SkipBuild) {
    Write-Step "Building snapshot executable..."
    swift build --product swift-windowsui-snapshot
    if ($LASTEXITCODE -ne 0) {
        throw "Build failed."
    }
}

# ── Render ─────────────────────────────────────────────────────────────────

$sceneBMP = Join-Path $OutputDir "scene.bmp"
$frameBMP = Join-Path $OutputDir "frame.bmp"
$cpuBMP   = Join-Path $OutputDir "cpu.bmp"

Write-Step "Rendering raw-scene backend..."
Run-Snapshot -Backend "raw-scene" -OutPath $sceneBMP

Write-Step "Rendering raw-frame backend..."
Run-Snapshot -Backend "raw-frame" -OutPath $frameBMP

Write-Step "Rendering cpu-batch backend..."
Run-Snapshot -Backend "cpu-batch" -OutPath $cpuBMP

# ── Diff ───────────────────────────────────────────────────────────────────

$diffSceneCpu = Join-Path $OutputDir "diff-scene-cpu.png"
$diffSceneFrame = Join-Path $OutputDir "diff-scene-frame.png"

Write-Step "Computing diffs..."
$hasDiffSceneCpu = Compute-PixelDiff -PathA $sceneBMP -PathB $cpuBMP -DiffPath $diffSceneCpu
$hasDiffSceneFrame = Compute-PixelDiff -PathA $sceneBMP -PathB $frameBMP -DiffPath $diffSceneFrame

# ── Report ─────────────────────────────────────────────────────────────────

$reportPath = Join-Path $OutputDir "index.html"
Write-Step "Writing comparison report to $reportPath"

$html = @"
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<title>SwiftWindowsUI Visual Comparison</title>
<style>
body { font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif; margin: 24px; background: #0f1419; color: #e6edf3; }
h1 { font-size: 22px; margin-bottom: 6px; }
.subtitle { color: #8b949e; font-size: 13px; margin-bottom: 20px; }
.grid { display: grid; grid-template-columns: repeat(3, 1fr); gap: 12px; }
.card { background: #161b22; border: 1px solid #30363d; border-radius: 8px; padding: 12px; }
.card h2 { font-size: 13px; margin: 0 0 10px; color: #58a6ff; }
img { max-width: 100%; border-radius: 4px; border: 1px solid #30363d; background: #000; image-rendering: pixelated; }
.diff-card { grid-column: 1 / -1; display: grid; grid-template-columns: repeat(2, 1fr); gap: 12px; }
.diff-card .card { margin-top: 0; }
</style>
</head>
<body>
<h1>SwiftWindowsUI Visual Comparison</h1>
<div class="subtitle">$Width&times;$Height &middot; scale=$Scale</div>
<div class="grid">
    <div class="card">
        <h2>Raw Scene (CPU Rasterizer)</h2>
        <img src="scene.bmp" alt="Scene" width="$Width" height="$Height">
    </div>
    <div class="card">
        <h2>Raw Frame (CPU Rasterizer)</h2>
        <img src="frame.bmp" alt="Frame" width="$Width" height="$Height">
    </div>
    <div class="card">
        <h2>CPU Batch (Protocol Backend)</h2>
        <img src="cpu.bmp" alt="CPU Batch" width="$Width" height="$Height">
    </div>
</div>
"@

if ($hasDiffSceneCpu) {
    $html += @"
    <div class="diff-card">
        <div class="card">
            <h2>Diff: Scene vs CPU Batch</h2>
            <img src="diff-scene-cpu.png" alt="Diff">
        </div>
"@
}
if ($hasDiffSceneFrame) {
    $html += @"
        <div class="card">
            <h2>Diff: Scene vs Frame</h2>
            <img src="diff-scene-frame.png" alt="Diff">
        </div>
    </div>
"@
} elseif ($hasDiffSceneCpu) {
    $html += "    </div>`n"
}

$html += @"
</body>
</html>
"@

$html | Out-File -FilePath $reportPath -Encoding utf8

Write-Step "Done. Open $reportPath in a browser."
