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

.PARAMETER List
    List matching baseline entries, appearances, and tiers without building,
    rendering, creating output directories, or loading image-processing tools.

.PARAMETER Entries
    Compare or update only these exact baseline entry ids. Accepts an array or
    comma-separated ids. Unknown ids fail before any build or file changes.

.PARAMETER Pattern
    Filter baseline entry ids with a PowerShell wildcard pattern. A plain word
    is treated as a contains search, so `-Pattern button` matches button ids.

.PARAMETER Appearance
    Restrict entries to dark or light appearance; defaults to all appearances.

.PARAMETER Tier
    Restrict entries to control, interaction, or composed showcase fixtures.
    Interaction and showcase tiers work with either appearance.

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
    powershell -NoProfile -ExecutionPolicy Bypass -File scripts/gallery-compare.ps1 -List -Appearance light -Tier showcase
    powershell -NoProfile -ExecutionPolicy Bypass -File scripts/gallery-compare.ps1 -SkipBuild -Pattern button
    powershell -NoProfile -ExecutionPolicy Bypass -File scripts/gallery-compare.ps1 -SkipBuild -Entries group-box,light-group-box
#>
param(
    [switch] $UpdateBaselines,
    [switch] $SkipBuild,
    [switch] $SkipRender,
    [switch] $List,
    [string[]] $Entries = @(),
    [string] $Pattern = "",
    [ValidateSet("all", "dark", "light")]
    [string] $Appearance = "all",
    [ValidateSet("all", "control", "interaction", "showcase")]
    [string] $Tier = "all",
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
    # A curved, inset diagonal three-stop fill plus independently shaded
    # stroke. Rectangle gradients take the quad lane, so they cannot guard
    # authored path endpoints, per-pixel ramps, or independent stroke colors.
    "canvas-path-gradient",

    # Composed showcase tier: practical component combinations and miniature
    # product layouts. Each fixture is deterministic; there are no wall-clock
    # animations or unresolved user input in its captured state.
    "typography-scale",
    "semantic-labels",
    "symbol-palette",
    "status-badges",
    "button-control-sizes",
    "tinted-controls",
    "group-box",
    "disclosure-collapsed",
    "disclosure-expanded",
    "labeled-content",
    "content-unavailable",
    "dashboard-metrics",
    "grid-layout",
    "tab-view",
    "canvas-sparkline",
    "canvas-donut",

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
    "light-state-picker-hover",

    # Curated light twins of the composed showcase fixtures. Their dark and
    # light variants are derived from the same gallery view definitions.
    "light-typography-scale",
    "light-semantic-labels",
    "light-group-box",
    "light-disclosure-expanded",
    "light-labeled-content",
    "light-content-unavailable",
    "light-dashboard-metrics",
    "light-canvas-sparkline"
)

function Write-Step {
    param([string] $Message)
    Write-Host "[gallery-compare] $Message" -ForegroundColor Cyan
}

$ShowcaseEntryIds = @(
    "typography-scale",
    "semantic-labels",
    "symbol-palette",
    "status-badges",
    "button-control-sizes",
    "tinted-controls",
    "group-box",
    "disclosure-collapsed",
    "disclosure-expanded",
    "labeled-content",
    "content-unavailable",
    "dashboard-metrics",
    "grid-layout",
    "tab-view",
    "canvas-sparkline",
    "canvas-donut"
)

function Get-GalleryEntryMetadata {
    param([string] $Id)

    $isLightAppearance = $Id.StartsWith("light-", [System.StringComparison]::OrdinalIgnoreCase)
    $baseId = if ($isLightAppearance) { $Id.Substring(6) } else { $Id }
    $entryTier = if ($baseId.StartsWith("state-", [System.StringComparison]::OrdinalIgnoreCase)) {
        "interaction"
    } elseif ($ShowcaseEntryIds -contains $baseId) {
        "showcase"
    } else {
        "control"
    }

    return [pscustomobject]@{
        Id         = $Id
        Appearance = if ($isLightAppearance) { "light" } else { "dark" }
        Tier       = $entryTier
    }
}

$galleryCatalog = @($GalleryBaselineEntries | ForEach-Object { Get-GalleryEntryMetadata $_ })
$requestedEntryIds = @(
    $Entries |
        ForEach-Object { $_ -split "," } |
        ForEach-Object { $_.Trim() } |
        Where-Object { $_ -ne "" } |
        Select-Object -Unique
)

if ($PSBoundParameters.ContainsKey("Entries") -and $requestedEntryIds.Count -eq 0) {
    throw "-Entries requires at least one non-empty gallery baseline id."
}

if ($requestedEntryIds.Count -gt 0) {
    $unknownEntryIds = @($requestedEntryIds | Where-Object { $GalleryBaselineEntries -notcontains $_ })
    if ($unknownEntryIds.Count -gt 0) {
        throw "Unknown gallery baseline entries: $($unknownEntryIds -join ', '). Run with -List to inspect supported ids."
    }
}

$effectivePattern = $Pattern.Trim()
if ($effectivePattern -ne "" -and $effectivePattern.IndexOfAny([char[]]@('*', '?', '[')) -lt 0) {
    $effectivePattern = "*$effectivePattern*"
}

$selectedGalleryEntries = @(
    $galleryCatalog | Where-Object {
        ($requestedEntryIds.Count -eq 0 -or $requestedEntryIds -contains $_.Id) -and
        ($effectivePattern -eq "" -or $_.Id -like $effectivePattern) -and
        ($Appearance -eq "all" -or $_.Appearance -eq $Appearance) -and
        ($Tier -eq "all" -or $_.Tier -eq $Tier)
    }
)

if ($selectedGalleryEntries.Count -eq 0) {
    throw "No gallery baseline entries match the supplied filters. Run with -List to inspect supported ids."
}

if ($List) {
    if ($UpdateBaselines) {
        throw "-List cannot be combined with -UpdateBaselines."
    }

    Write-Step "Listing $($selectedGalleryEntries.Count) of $($galleryCatalog.Count) baseline entries."
    $selectedGalleryEntries | Format-Table Id, Appearance, Tier -AutoSize
    exit 0
}

$selectedEntryIds = @($selectedGalleryEntries | ForEach-Object { $_.Id })

# Capture before build/image-processing setup, and keep this initial record
# separate from later phases. A failed build must not label an old executable
# as the product of the current checkout. -List still performs no collection.
. (Join-Path $PSScriptRoot "gallery-font-provenance.ps1") -GalleryExe $GalleryExe
$galleryProvenancePath = Join-Path $WorkDir "provenance.json"
$galleryInitialProvenancePath = Join-Path $WorkDir "provenance-initial.json"
$galleryFontProvenance = New-GalleryFontProvenance -Executable $GalleryExe -Root (Split-Path -Parent $PSScriptRoot) -CaptureStage "before-build"
$galleryFontProvenance.build.status = if ($SkipBuild) { "skipped" } else { "pending" }
$galleryFontProvenance.render.status = if ($SkipRender) { "skipped" } else { "pending" }
$galleryFontProvenance.render.requestedEntries = $selectedEntryIds
$galleryFontProvenance.render.outputDirectory = Resolve-GalleryProvenancePath (Join-Path $WorkDir "current")
Write-GalleryFontProvenance $galleryFontProvenance $galleryInitialProvenancePath
Write-GalleryFontProvenance $galleryFontProvenance $galleryProvenancePath

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

function ConvertTo-EmbeddedPng {
    param([string] $Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return $null
    }

    # Swift's raw-scene writer deliberately emits uncompressed PNG blocks.
    # Re-encode the review copy so a standalone report containing every
    # baseline and current image remains a practical CI artifact.
    $bitmap = New-Object System.Drawing.Bitmap([System.IO.Path]::GetFullPath($Path))
    $buffer = New-Object System.IO.MemoryStream
    try {
        $bitmap.Save($buffer, [System.Drawing.Imaging.ImageFormat]::Png)
        return "data:image/png;base64,$([Convert]::ToBase64String($buffer.ToArray()))"
    } finally {
        $buffer.Dispose()
        $bitmap.Dispose()
    }
}

function ConvertTo-HtmlLiteral {
    param([AllowNull()][string] $Value)

    return [System.Net.WebUtility]::HtmlEncode($Value)
}

function New-GalleryImagePanel {
    param(
        [string] $Label,
        [string] $Path,
        [string] $Appearance,
        [string] $MissingText
    )

    $safeLabel = ConvertTo-HtmlLiteral $Label
    $image = ConvertTo-EmbeddedPng $Path
    $content = if ($null -eq $image) {
        '<span class="placeholder">{0}</span>' -f (ConvertTo-HtmlLiteral $MissingText)
    } else {
        '<img alt="{0}" src="{1}">' -f $safeLabel, $image
    }

    return @"
<figure class="panel $Appearance">
    <figcaption>$safeLabel</figcaption>
    <div class="canvas">$content</div>
</figure>
"@
}

function Write-GalleryHtmlReport {
    param(
        [array] $Results,
        [int] $FailureCount,
        [string] $ReportPath,
        [string] $BaselineDirectory,
        [string] $CurrentDirectory,
        [string] $DiffDirectory
    )

    $cards = @(
        foreach ($entry in $Results) {
            $metadata = Get-GalleryEntryMetadata $entry.Id
            $safeId = ConvertTo-HtmlLiteral $entry.Id
            $safeDetail = ConvertTo-HtmlLiteral $entry.Detail
            $baselinePanel = New-GalleryImagePanel `
                -Label "Reviewed baseline" `
                -Path (Join-Path $BaselineDirectory "$($entry.Id).png") `
                -Appearance $metadata.Appearance `
                -MissingText "Baseline unavailable"
            $currentPanel = New-GalleryImagePanel `
                -Label "Current render" `
                -Path (Join-Path $CurrentDirectory "$($entry.Id).png") `
                -Appearance $metadata.Appearance `
                -MissingText "Render unavailable"
            $diffPanel = New-GalleryImagePanel `
                -Label "Difference overlay" `
                -Path (Join-Path $DiffDirectory "$($entry.Id)-diff.png") `
                -Appearance $metadata.Appearance `
                -MissingText $(if ($entry.Status -eq "pass") { "No visual regression" } else { "No diff image available" })

            @"
<article class="entry $($entry.Status)" data-id="$safeId" data-status="$($entry.Status)" data-appearance="$($metadata.Appearance)" data-tier="$($metadata.Tier)">
    <div class="entry-heading">
        <div>
            <h2>$safeId</h2>
            <p>$($metadata.Appearance) appearance &middot; $($metadata.Tier) tier</p>
        </div>
        <span class="badge $($entry.Status)">$($entry.Status.ToUpperInvariant())</span>
    </div>
    <div class="panels">
        $baselinePanel
        $currentPanel
        $diffPanel
    </div>
    <p class="detail">$safeDetail</p>
</article>
"@
        }
    ) -join "`n"

    $statusLabel = if ($FailureCount -eq 0) { "All visual baselines match" } else { "$FailureCount visual regressions require review" }
    $statusClass = if ($FailureCount -eq 0) { "pass" } else { "fail" }
    $passCount = $Results.Count - $FailureCount
    $darkCount = @($Results | Where-Object { $_.Id -notlike "light-*" }).Count
    $lightCount = $Results.Count - $darkCount
    $generatedAt = [DateTimeOffset]::Now.ToString("yyyy-MM-dd HH:mm zzz")

    $html = @"
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title>SwiftWindowsUI visual comparison</title>
    <style>
        :root { color-scheme: dark; font-family: "Segoe UI", system-ui, sans-serif; background: #101317; color: #e8edf3; }
        * { box-sizing: border-box; }
        body { max-width: 1520px; margin: 0 auto; padding: 36px clamp(18px, 5vw, 64px) 72px; }
        header { display: grid; gap: 18px; padding: 28px; border: 1px solid #29323c; border-radius: 18px; background: linear-gradient(145deg, #19222d, #131820); }
        .eyebrow { margin: 0; color: #94a7bb; font-size: 11px; font-weight: 700; letter-spacing: .12em; text-transform: uppercase; }
        h1 { margin: 0; font-size: clamp(26px, 4vw, 42px); letter-spacing: -.05em; }
        .summary { display: flex; flex-wrap: wrap; gap: 9px; }
        .chip { padding: 7px 11px; border: 1px solid #34404d; border-radius: 999px; color: #c2cbd5; font-size: 12px; }
        .chip.fail { border-color: #803d45; color: #ff9ba5; }
        .chip.pass { border-color: #285a45; color: #82e4af; }
        .toolbar { display: flex; flex-wrap: wrap; gap: 12px; align-items: center; margin: 25px 0 18px; }
        .search, select, button { min-height: 38px; border: 1px solid #33404d; border-radius: 9px; background: #171d25; color: #e8edf3; }
        .search { flex: 1 1 220px; padding: 0 12px; }
        select, button { padding: 0 12px; }
        button { cursor: pointer; }
        button[aria-pressed="true"] { border-color: #598dd1; background: #22344b; }
        .visible-count { margin-left: auto; color: #a0adba; font-size: 12px; }
        main { display: grid; gap: 16px; }
        .entry { padding: 19px; border: 1px solid #29323d; border-radius: 15px; background: #151a21; }
        .entry.fail { border-color: #823940; }
        .entry[hidden] { display: none; }
        .entry-heading { display: flex; justify-content: space-between; align-items: center; gap: 12px; }
        h2 { margin: 0; font-size: 16px; font-weight: 650; }
        .entry-heading p, .detail { color: #95a3b2; font-size: 12px; }
        .entry-heading p { margin: 5px 0 0; }
        .badge { padding: 6px 9px; border-radius: 7px; font-size: 10px; font-weight: 750; letter-spacing: .08em; }
        .badge.pass { background: #173629; color: #8aefb5; }
        .badge.fail { background: #462229; color: #ffa6ad; }
        .panels { display: grid; grid-template-columns: repeat(3, minmax(0, 1fr)); gap: 12px; margin-top: 16px; }
        .panel { min-width: 0; margin: 0; border: 1px solid #2c3641; border-radius: 10px; overflow: hidden; }
        figcaption { padding: 9px 11px; color: #b9c4ce; background: #1d242d; font-size: 11px; }
        .canvas { display: grid; min-height: 150px; padding: 10px; place-items: center; background: #07090b; }
        .panel.light .canvas { background: #ededed; }
        .panel.light .placeholder { color: #526170; }
        img { display: block; max-width: 100%; max-height: 280px; object-fit: contain; }
        .placeholder { color: #8594a2; font-size: 12px; }
        .detail { margin: 13px 0 0; font-family: Consolas, monospace; }
        @media (max-width: 720px) { body { padding-top: 20px; } header { padding: 20px; } .panels { grid-template-columns: 1fr; } .canvas { min-height: 120px; } .visible-count { margin-left: 0; } }
    </style>
</head>
<body>
    <header>
        <p class="eyebrow">SwiftWindowsUI &middot; retained-runtime gallery</p>
        <h1>$statusLabel</h1>
        <div class="summary">
            <span class="chip $statusClass">$($Results.Count) reviewed fixtures</span>
            <span class="chip pass">$passCount passing</span>
            <span class="chip $(if ($FailureCount -gt 0) { 'fail' })">$FailureCount failing</span>
            <span class="chip">$darkCount dark &middot; $lightCount light</span>
            <span class="chip">Generated $generatedAt</span>
        </div>
    </header>
    <div class="toolbar">
        <input class="search" id="search" type="search" placeholder="Search fixture ids" aria-label="Search fixture ids">
        <select id="appearance" aria-label="Filter appearance">
            <option value="all">Every appearance</option>
            <option value="dark">Dark</option>
            <option value="light">Light</option>
        </select>
        <select id="tier" aria-label="Filter fixture tier">
            <option value="all">Every tier</option>
            <option value="control">Controls</option>
            <option value="interaction">Interaction states</option>
            <option value="showcase">Composed showcases</option>
        </select>
        <button type="button" data-status="all" aria-pressed="true">All</button>
        <button type="button" data-status="fail" aria-pressed="false">Failures</button>
        <button type="button" data-status="pass" aria-pressed="false">Passing</button>
        <span class="visible-count" id="visible-count">$($Results.Count) visible</span>
    </div>
    <main id="entries">
        $cards
    </main>
    <script>
        (function () {
            var search = document.getElementById("search");
            var appearance = document.getElementById("appearance");
            var tier = document.getElementById("tier");
            var count = document.getElementById("visible-count");
            var cards = Array.prototype.slice.call(document.querySelectorAll(".entry"));
            var buttons = Array.prototype.slice.call(document.querySelectorAll("button[data-status]"));
            var activeStatus = "all";

            function update() {
                var query = search.value.trim().toLowerCase();
                var visible = 0;
                cards.forEach(function (card) {
                    var matches = (!query || card.dataset.id.toLowerCase().indexOf(query) !== -1)
                        && (appearance.value === "all" || card.dataset.appearance === appearance.value)
                        && (tier.value === "all" || card.dataset.tier === tier.value)
                        && (activeStatus === "all" || card.dataset.status === activeStatus);
                    card.hidden = !matches;
                    if (matches) { visible += 1; }
                });
                count.textContent = visible + " visible";
            }

            search.addEventListener("input", update);
            appearance.addEventListener("change", update);
            tier.addEventListener("change", update);
            buttons.forEach(function (button) {
                button.addEventListener("click", function () {
                    activeStatus = button.dataset.status;
                    buttons.forEach(function (item) {
                        item.setAttribute("aria-pressed", String(item === button));
                    });
                    update();
                });
            });
        })();
    </script>
</body>
</html>
"@

    $html | Out-File -FilePath $ReportPath -Encoding utf8
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

if ($selectedEntryIds.Count -ne $GalleryBaselineEntries.Count) {
    Write-Step "Selected $($selectedEntryIds.Count) of $($GalleryBaselineEntries.Count) baseline entries."
}

# ── Build ──────────────────────────────────────────────────────────────────

try {
    if (-not $SkipBuild) {
        Write-Step "Building gallery executable..."
        $galleryFontProvenance.build.status = "running"
        swift build --product swift-windowsui-gallery
        $galleryFontProvenance.build.exitCode = $LASTEXITCODE
        if ($LASTEXITCODE -ne 0) { throw "Build failed." }
        $galleryFontProvenance.build.status = "succeeded"
        $galleryFontProvenance.build.executableAfter = Get-GalleryFileFingerprint $GalleryExe
    }

    # ── Render ─────────────────────────────────────────────────────────────

    if (-not $SkipRender) {
        $galleryPreviousProvenance = $galleryFontProvenance
        $galleryFontProvenance = New-GalleryFontProvenance -Executable $GalleryExe -Root (Split-Path -Parent $PSScriptRoot) -CaptureStage "before-render"
        $galleryFontProvenance.invocationID = $galleryPreviousProvenance.invocationID
        $galleryFontProvenance.build = $galleryPreviousProvenance.build
        $galleryFontProvenance.render.requestedEntries = $selectedEntryIds
        $galleryFontProvenance.render.outputDirectory = Resolve-GalleryProvenancePath $currentDir
        $galleryFontProvenance.render.status = "running"
        $galleryFontProvenance.executableAssociation = if ($SkipBuild) { "preexisting-file-invoked-without-build" } else { "observed-after-successful-build; build-revision-not-embedded" }
        Write-GalleryFontProvenance $galleryFontProvenance $galleryProvenancePath
        Write-Step "Rendering $($selectedEntryIds.Count) baseline entries..."
        & $GalleryExe --entries ($selectedEntryIds -join ",") --output-dir $currentDir
        $galleryFontProvenance.render.exitCode = $LASTEXITCODE
        $galleryFontProvenance.render.executableAfter = Get-GalleryFileFingerprint $GalleryExe
        if ($null -ne $galleryFontProvenance.executable.sha256 -and $null -ne $galleryFontProvenance.render.executableAfter.sha256) {
            $galleryFontProvenance.render.executableUnchanged = $galleryFontProvenance.executable.sha256 -ceq $galleryFontProvenance.render.executableAfter.sha256
        }
        if ($galleryFontProvenance.render.exitCode -ne 0) { throw "Gallery render failed." }
        $galleryFontProvenance.stage = "render-completed"
        $galleryFontProvenance.render.status = "succeeded"
        $galleryFontProvenance.render.imageAssociation = if ($galleryFontProvenance.render.executableUnchanged -eq $true) { "invocation-completed; environment-probed-before-render; glyph-faces-not-observed" } else { "unverified-executable-changed-or-unreadable" }
    } else {
        $galleryFontProvenance.stage = "render-skipped"
        $galleryFontProvenance.render.imageAssociation = "unknown-existing-images; current-environment-is-not-their-provenance"
    }
    Write-GalleryFontProvenance $galleryFontProvenance $galleryProvenancePath
} catch {
    if ($galleryFontProvenance.build.status -eq "running") {
        $galleryFontProvenance.stage = "build-failed"
        $galleryFontProvenance.build.status = "failed"
        $galleryFontProvenance.build.executableAfter = Get-GalleryFileFingerprint $GalleryExe
        $galleryFontProvenance.executableAssociation = "preexisting-or-partial-file-after-failed-build; not-a-current-build"
    } elseif ($galleryFontProvenance.render.status -eq "running") {
        $galleryFontProvenance.stage = "render-failed"
        $galleryFontProvenance.render.status = "failed"
        $galleryFontProvenance.render.imageAssociation = "unverified-partial-or-preexisting-images"
    }
    Write-GalleryFontProvenance $galleryFontProvenance $galleryProvenancePath
    throw
}

# ── Update or compare ──────────────────────────────────────────────────────

if ($UpdateBaselines) {
    Write-Step "Updating $($selectedEntryIds.Count) baselines in $BaselineDir ..."
    Ensure-Dir $BaselineDir
    foreach ($id in $selectedEntryIds) {
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
foreach ($id in $selectedEntryIds) {
    $entryDiffPath = Join-Path $diffDir "$id-diff.png"
    if (Test-Path -LiteralPath $entryDiffPath -PathType Leaf) {
        Remove-Item -LiteralPath $entryDiffPath -Force
    }

    $entry = Compare-Entry `
        -Id $id `
        -BaselinePath (Join-Path $BaselineDir "$id.png") `
        -CurrentPath (Join-Path $currentDir "$id.png") `
        -DiffPath $entryDiffPath
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
    "selection: $($results.Count) / $($GalleryBaselineEntries.Count) entries; appearance=$Appearance tier=$Tier pattern=$Pattern",
    "thresholds: maxChangedPercent=$MaxChangedPercent maxChannelDelta=$MaxChannelDelta channelTolerance=$ChannelTolerance",
    "font provenance: $galleryProvenancePath (unqualified; no accepted baseline font profile)",
    "image provenance: $($galleryFontProvenance.render.imageAssociation)",
    ""
)
foreach ($entry in $results) {
    $lines += "{0,-4} {1,-22} {2}" -f $entry.Status.ToUpper(), $entry.Id, $entry.Detail
}
$lines += ""
$lines += "failures: $failCount / $($results.Count)"
$lines | Out-File -FilePath $reportPath -Encoding utf8
Write-Step "Report written to $reportPath"

$jsonReportPath = Join-Path $WorkDir "report.json"
$jsonEntries = @(
    foreach ($entry in $results) {
        $metadata = Get-GalleryEntryMetadata $entry.Id
        $relativeDiffPath = "diffs/$($entry.Id)-diff.png"
        [ordered]@{
            id             = $entry.Id
            appearance     = $metadata.Appearance
            tier           = $metadata.Tier
            status         = $entry.Status
            detail         = $entry.Detail
            changedPercent = $entry.ChangedPercent
            maxChannelDelta = $entry.MaxDelta
            images         = [ordered]@{
                baseline = Join-Path $BaselineDir "$($entry.Id).png"
                current  = "current/$($entry.Id).png"
                diff     = if (Test-Path -LiteralPath (Join-Path $diffDir "$($entry.Id)-diff.png") -PathType Leaf) {
                    $relativeDiffPath
                } else {
                    $null
                }
            }
        }
    }
)

$jsonReport = [ordered]@{
    schemaVersion = 2
    generatedAt   = [DateTimeOffset]::UtcNow.ToString("o")
    status        = if ($failCount -eq 0) { "pass" } else { "fail" }
    fontProvenance = $galleryFontProvenance
    selection     = [ordered]@{
        selectedCount = $results.Count
        catalogCount  = $GalleryBaselineEntries.Count
        appearance    = $Appearance
        tier          = $Tier
        pattern       = $Pattern
        requestedIds  = $requestedEntryIds
    }
    thresholds    = [ordered]@{
        maxChangedPercent = $MaxChangedPercent
        channelTolerance  = $ChannelTolerance
        maxChannelDelta   = $MaxChannelDelta
    }
    summary       = [ordered]@{
        total   = $results.Count
        passing = $results.Count - $failCount
        failing = $failCount
    }
    entries       = $jsonEntries
}
$jsonReport | ConvertTo-Json -Depth 14 | Out-File -FilePath $jsonReportPath -Encoding utf8
Write-Step "Machine-readable report written to $jsonReportPath"

$htmlReportPath = Join-Path $WorkDir "report.html"
Write-GalleryHtmlReport `
    -Results $results `
    -FailureCount $failCount `
    -ReportPath $htmlReportPath `
    -BaselineDirectory $BaselineDir `
    -CurrentDirectory $currentDir `
    -DiffDirectory $diffDir
Write-Step "Self-contained visual review written to $htmlReportPath"

if ($failCount -gt 0) {
    Write-Step "FAILED: $failCount of $($results.Count) entries regressed. Diff images (if any) are in $diffDir."
    exit 1
}

Write-Step "Passed: all $($results.Count) entries match baselines within thresholds."
exit 0
