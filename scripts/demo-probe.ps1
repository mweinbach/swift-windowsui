param(
    [switch]$FrameDebug,
    [string]$OutputPath = ""
)

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent $PSScriptRoot

if ([string]::IsNullOrWhiteSpace($OutputPath)) {
    $kind = if ($FrameDebug) { "frame" } else { "default" }
    $OutputPath = Join-Path $env:TEMP "swift-windowsui-$kind-probe.log"
}

Remove-Item $OutputPath -ErrorAction SilentlyContinue

if ($FrameDebug) {
    $env:SWIFT_WINDOWSUI_FRAME_DEBUG = "1"
} else {
    Remove-Item Env:\SWIFT_WINDOWSUI_FRAME_DEBUG -ErrorAction SilentlyContinue
}

$env:SWIFT_WINDOWSUI_STARTUP_PROBE_PATH = $OutputPath
$env:SWIFT_WINDOWSUI_STARTUP_PROBE_EXIT = "1"

& (Join-Path $PSScriptRoot "with-swift.ps1") swift run --package-path $repoRoot swift-windowsui
if ($LASTEXITCODE -ne 0) {
    exit $LASTEXITCODE
}

Get-Content $OutputPath
