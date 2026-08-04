<#
.SYNOPSIS
    Gallery regression gate: re-render Supported-tier gallery entries and
    compare them against checked-in baselines.

.DESCRIPTION
    Renders the baseline subset of swift-windowsui-gallery entries into a
    work directory, then computes bounded per-entry pixel diffs against the
    baselines in tests/fixtures/gallery-baselines/.

    A pixel counts as changed when any B/G/R/A channel differs by more than
    -ChannelTolerance. An entry fails when either:
      - changed pixels exceed -MaxChangedPercent of the entry, or
      - any single channel delta exceeds -MaxChannelDelta.
    Missing baselines and canvas-size mismatches also fail the entry.
    The script exits non-zero when any entry regresses.

    Threshold rationale: the raw-scene CPU rasterizer is deterministic, so
    exact renders produce 0% changed pixels. The small defaults below absorb
    toolchain-level rasterization noise without hiding real control changes.

.PARAMETER UpdateBaselines
    Re-render the baseline entries and overwrite the checked-in baselines
    (re-encoded as compact PNGs). Review the new baselines before commit.

.PARAMETER SkipBuild
    Skip `swift build --product swift-windowsui-gallery`.

.PARAMETER SkipRender
    Skip re-rendering and compare whatever is already in the work directory
    (useful for manually produced before/after images).

.PARAMETER GalleryExe
    Path to the gallery executable (default: .build/debug/swift-windowsui-gallery.exe).

.PARAMETER BaselineDir
    Directory holding the checked-in baseline PNGs
    (default: tests/fixtures/gallery-baselines).

.PARAMETER WorkDir
    Scratch directory for current renders, diff images, and the report
    (default: artifacts/gallery-compare).

.EXAMPLE
    powershell -NoProfile -ExecutionPolicy Bypass -File scripts/gallery-compare.ps1
    powershell -NoProfile -ExecutionPolicy Bypass -File scripts/gallery-compare.ps1 -UpdateBaselines
#>
param(
    [switch] $UpdateBaselines,
    [switch] $SkipBuild,
    [switch] $SkipRender,
    [string] $GalleryExe = ".build/debug/swift-windowsui-gallery.exe",
    [string] $BaselineDir = "tests/fixtures/gallery-baselines",
    [string] $WorkDir = "artifacts/gallery-compare",
    [double] $MaxChangedPercent = 0.5,
    [int] $ChannelTolerance = 8,
    [int] $MaxChannelDelta = 64
)

$ErrorActionPreference = "Stop"

# Baseline gate subset: Supported-tier control entries only (deterministic
# renders — no animation-, focus-, or time-dependent entries).
$GalleryBaselineEntries = @(
    "button",
    "button-destructive",
    "button-disabled",
    "button-styles",
    "text-field",
    "text-field-empty",
    "text-field-disabled",
    "secure-field",
    "toggle",
    "toggle-off",
    "toggle-disabled",
    "slider",
    "slider-low",
    "slider-high",
    "slider-labeled",
    "picker",
    "stepper",
    "progress-view",
    "progress-complete",
    "progress-labeled",
    "list",
    "list-data",
    "form",
    "form-settings",
    "divider",

    # Interaction-state tier. The hover/pressed/focus/disabled ramps were
    # pinned only by unit tests reading colour fields, so a ramp could go
    # visually wrong with every assertion still green — which is how a focused
    # bordered button came to render accent-blue (the focus ring was a filled
    # slab under a translucent fill, not a ring). These are deterministic: the
    # gallery drives the runtime's own input entry points, then settles every
    # tween to its end value before capturing, so no wall clock is involved.
    "state-button-idle",
    "state-button-hover",
    "state-button-pressed",
    "state-button-focused",
    "state-button-disabled",
    "state-toggle-idle",
    "state-toggle-hover",
    "state-toggle-pressed",
    "state-toggle-disabled",
    "state-field-idle",
    "state-field-focused",
    "state-field-disabled",
    "state-picker-idle",
    "state-picker-hover",
    "state-picker-pressed",
    "state-picker-focused",

    # Light appearance tier. Every entry above renders dark, so the whole
    # light half of `ControlPalette` — the derived grooves, the container
    # surfaces, the hover/pressed/focus ramps on white — was pinned only by
    # unit tests reading colour fields. That is how a light-mode Form came to
    # draw a charcoal groove across a white settings pane and survive to final
    # verification: nothing rendered it. Each `light-` entry is its dark twin
    # in the other appearance, derived from the same view in the tool, so the
    # pair cannot drift apart.
    "light-button",
    "light-button-styles",
    "light-text-field",
    "light-toggle",
    "light-toggle-off",
    "light-slider",
    "light-picker",
    "light-stepper",
    "light-progress-view",
    "light-progress-labeled",
    "light-list-data",
    "light-form-settings",
    "light-divider",
    "light-state-button-hover",
    "light-state-button-pressed",
    "light-state-button-focused",
    "light-state-toggle-pressed",
    "light-state-field-focused",
    "light-state-picker-hover"
)

function Write-Step {
    param([string] $Message)
    Write-Host "[gallery-compare] $Message" -ForegroundColor Cyan
}

function Ensure-Dir {
    param([string] $Path)
    if (-not (Test-Path $Path)) {
        New-Item -ItemType Directory -Path $Path -Force | Out-Null
    }
}

Add-Type -AssemblyName System.Drawing

function Read-BitmapPixels {
    param([string] $Path)
    $fullPath = [System.IO.Path]::GetFullPath($Path)
    $bmp = New-Object System.Drawing.Bitmap($fullPath)
    try {
        $rect = New-Object System.Drawing.Rectangle(0, 0, $bmp.Width, $bmp.Height)
        $data = $bmp.LockBits(
            $rect,
            [System.Drawing.Imaging.ImageLockMode]::ReadOnly,
            [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
        try {
            $length = [Math]::Abs($data.Stride) * $data.Height
            $bytes = New-Object byte[] $length
            [System.Runtime.InteropServices.Marshal]::Copy($data.Scan0, $bytes, 0, $length)
            return @{
                Width  = $bmp.Width
                Height = $bmp.Height
                Stride = [Math]::Abs($data.Stride)
                Pixels = $bytes
            }
        } finally {
            $bmp.UnlockBits($data)
        }
    } finally {
        $bmp.Dispose()
    }
}

function Save-CompactPng {
    # Re-encode through System.Drawing so checked-in baselines use real
    # DEFLATE compression (the Swift PNG writer emits uncompressed blocks).
    param([string] $SourcePath, [string] $DestPath)
    $bmp = New-Object System.Drawing.Bitmap([System.IO.Path]::GetFullPath($SourcePath))
    try {
        Ensure-Dir (Split-Path -Parent $DestPath)
        $bmp.Save([System.IO.Path]::GetFullPath($DestPath), [System.Drawing.Imaging.ImageFormat]::Png)
    } finally {
        $bmp.Dispose()
    }
}

function Compare-Entry {
    param(
        [string] $Id,
        [string] $BaselinePath,
        [string] $CurrentPath,
        [string] $DiffPath
    )
    $result = [ordered]@{
        Id             = $Id
        Status         = "pass"
        Detail         = ""
        ChangedPercent = 0.0
        MaxDelta       = 0
    }

    if (-not (Test-Path $BaselinePath)) {
        $result.Status = "fail"
        $result.Detail = "missing baseline (run with -UpdateBaselines)"
        return $result
    }
    if (-not (Test-Path $CurrentPath)) {
        $result.Status = "fail"
        $result.Detail = "entry did not render"
        return $result
    }

    $baseline = Read-BitmapPixels $BaselinePath
    $current = Read-BitmapPixels $CurrentPath

    if ($baseline.Width -ne $current.Width -or $baseline.Height -ne $current.Height) {
        $result.Status = "fail"
        $result.Detail = "canvas size changed: baseline $($baseline.Width)x$($baseline.Height) vs current $($current.Width)x$($current.Height)"
        $result.ChangedPercent = 100.0
        $result.MaxDelta = 255
        return $result
    }

    $width = $baseline.Width
    $height = $baseline.Height
    $changed = 0
    $maxDelta = 0
    $basePixels = $baseline.Pixels
    $curPixels = $current.Pixels
    $baseStride = $baseline.Stride
    $curStride = $current.Stride
    $diffMask = New-Object byte[] ($width * $height)

    for ($y = 0; $y -lt $height; $y++) {
        $baseRow = $y * $baseStride
        $curRow = $y * $curStride
        for ($x = 0; $x -lt $width; $x++) {
            $bi = $baseRow + $x * 4
            $ci = $curRow + $x * 4
            $pixelMax = 0
            for ($c = 0; $c -lt 4; $c++) {
                $delta = [Math]::Abs([int]$basePixels[$bi + $c] - [int]$curPixels[$ci + $c])
                if ($delta -gt $pixelMax) { $pixelMax = $delta }
            }
            if ($pixelMax -gt $maxDelta) { $maxDelta = $pixelMax }
            if ($pixelMax -gt $ChannelTolerance) {
                $changed++
                $diffMask[$y * $width + $x] = 1
            }
        }
    }

    $total = $width * $height
    $percent = [Math]::Round(($changed * 100.0) / $total, 4)
    $result.ChangedPercent = $percent
    $result.MaxDelta = $maxDelta
    $result.Detail = "changed=$percent% maxDelta=$maxDelta ($width x $height)"

    if ($percent -gt $MaxChangedPercent -or $maxDelta -gt $MaxChannelDelta) {
        $result.Status = "fail"
        # Write a diff image (changed pixels in red over the current render)
        # to make CI artifact review easy.
        try {
            $diffBmp = New-Object System.Drawing.Bitmap([System.IO.Path]::GetFullPath($CurrentPath))
            try {
                for ($y = 0; $y -lt $height; $y++) {
                    for ($x = 0; $x -lt $width; $x++) {
                        if ($diffMask[$y * $width + $x] -eq 1) {
                            $diffBmp.SetPixel($x, $y, [System.Drawing.Color]::FromArgb(255, 255, 0, 0))
                        }
                    }
                }
                Ensure-Dir (Split-Path -Parent $DiffPath)
                $diffBmp.Save([System.IO.Path]::GetFullPath($DiffPath), [System.Drawing.Imaging.ImageFormat]::Png)
            } finally {
                $diffBmp.Dispose()
            }
        } catch {
            Write-Step "Could not write diff image for $Id`: $_"
        }
    }

    return $result
}

# ── Setup ────────────────────────────────────────────────────────────────────

$currentDir = Join-Path $WorkDir "current"
$diffDir = Join-Path $WorkDir "diffs"
Ensure-Dir $currentDir

# ── Build ──────────────────────────────────────────────────────────────────

if (-not $SkipBuild) {
    Write-Step "Building gallery executable..."
    swift build --product swift-windowsui-gallery
    if ($LASTEXITCODE -ne 0) {
        throw "Build failed."
    }
}

# ── Render ─────────────────────────────────────────────────────────────────

if (-not $SkipRender) {
    Write-Step "Rendering $($GalleryBaselineEntries.Count) baseline entries..."
    & $GalleryExe --entries ($GalleryBaselineEntries -join ",") --output-dir $currentDir
    if ($LASTEXITCODE -ne 0) {
        throw "Gallery render failed."
    }
}

# ── Update or compare ──────────────────────────────────────────────────────

if ($UpdateBaselines) {
    Write-Step "Updating baselines in $BaselineDir ..."
    Ensure-Dir $BaselineDir
    foreach ($id in $GalleryBaselineEntries) {
        $currentPath = Join-Path $currentDir "$id.png"
        if (-not (Test-Path $currentPath)) {
            throw "Entry '$id' did not render; refusing to update baselines."
        }
        Save-CompactPng -SourcePath $currentPath -DestPath (Join-Path $BaselineDir "$id.png")
        Write-Step "  baseline updated: $id"
    }
    Write-Step "Done. Review the regenerated baselines before committing."
    exit 0
}

Write-Step "Comparing against baselines (tolerance: >$MaxChangedPercent% changed pixels or channel delta >$MaxChannelDelta fails; pixel noise <=$ChannelTolerance ignored)..."

$results = @()
$failCount = 0
foreach ($id in $GalleryBaselineEntries) {
    $entry = Compare-Entry `
        -Id $id `
        -BaselinePath (Join-Path $BaselineDir "$id.png") `
        -CurrentPath (Join-Path $currentDir "$id.png") `
        -DiffPath (Join-Path $diffDir "$id-diff.png")
    $results += $entry
    if ($entry.Status -eq "fail") {
        $failCount++
        Write-Host "  FAIL $($entry.Id): $($entry.Detail)" -ForegroundColor Red
    } else {
        Write-Host "  ok   $($entry.Id): $($entry.Detail)" -ForegroundColor DarkGray
    }
}

# ── Report ─────────────────────────────────────────────────────────────────

$reportPath = Join-Path $WorkDir "report.txt"
$lines = @(
    "gallery-compare report",
    "baselines: $BaselineDir",
    "current:   $currentDir",
    "thresholds: maxChangedPercent=$MaxChangedPercent maxChannelDelta=$MaxChannelDelta channelTolerance=$ChannelTolerance",
    ""
)
foreach ($entry in $results) {
    $lines += "{0,-4} {1,-22} {2}" -f $entry.Status.ToUpper(), $entry.Id, $entry.Detail
}
$lines += ""
$lines += "failures: $failCount / $($results.Count)"
$lines | Out-File -FilePath $reportPath -Encoding utf8
Write-Step "Report written to $reportPath"

if ($failCount -gt 0) {
    Write-Step "FAILED: $failCount of $($results.Count) entries regressed. Diff images (if any) are in $diffDir."
    exit 1
}

Write-Step "Passed: all $($results.Count) entries match baselines within thresholds."
exit 0
