param(
    [switch]$Quick,
    [switch]$Full,
    [switch]$Format,
    [switch]$ContractsOnly
)

$ErrorActionPreference = "Stop"
$testScript = Join-Path $PSScriptRoot "test.ps1"
$buildScript = Join-Path $PSScriptRoot "build.ps1"
$lintScript = Join-Path $PSScriptRoot "lint.ps1"
$contractScript = Join-Path $PSScriptRoot "check-contracts.ps1"
$screenshotScript = Join-Path $PSScriptRoot "demo-screenshot.ps1"
$repoRoot = Split-Path -Parent $PSScriptRoot

function Get-ReportedExitCode {
    if ($null -eq $LASTEXITCODE) {
        return $null
    }
    return [int]$LASTEXITCODE
}

function Invoke-Step {
    param(
        [string]$Name,
        [scriptblock]$Command
    )

    Write-Host ""
    Write-Host "==> $Name"
    & $Command
    $code = Get-ReportedExitCode
    if ($null -eq $code) {
        Write-Host "Step failed: $Name (no exit code reported)" -ForegroundColor Red
        exit 1
    }
    if ($code -ne 0) {
        Write-Host "Step failed: $Name (exit code $code)" -ForegroundColor Red
        exit $code
    }
    Write-Host "Step passed: $Name" -ForegroundColor Green
}

if (-not $Quick -and -not $Full -and -not $ContractsOnly) {
    $Quick = $true
}

if ($Quick -and $Full) {
    Write-Host "Specify only one of -Quick or -Full." -ForegroundColor Red
    exit 1
}

Invoke-Step "contract checks" {
    & $contractScript
}

if ($Format) {
    Invoke-Step "swift-format lint" {
        if ($Full) {
            & $lintScript -AllSwift -SkipContracts
        } else {
            & $lintScript -SkipContracts
        }
    }
}

if ($ContractsOnly) {
    Write-Host ""
    Write-Host "Agent contracts passed."
    exit 0
}

# All SwiftPM steps below run strictly serially (shared .build/build.db).
if ($Full) {
    # Prefer sharded full tests: class/suite filters plus method batches for
    # oversized XCTest classes (avoids Windows error 206 on huge filter expansion).
    # Plain `scripts/test.ps1` (no -Sharded) remains available for a single
    # unfiltered `swift test` invocation.
    Invoke-Step "swift test (sharded full suite)" {
        & $testScript -Sharded
    }
    Invoke-Step "swift build swift-windowsui" {
        & $buildScript -Product "swift-windowsui"
    }
    Invoke-Step "scene screenshot" {
        & $screenshotScript
    }
    Invoke-Step "frame fallback screenshot" {
        & $screenshotScript -FrameDebug -OutputPath (Join-Path $repoRoot "artifacts/demo-screenshot-frame.png")
    }
} else {
    Invoke-Step "GPUISceneTests" {
        & $testScript -Filter "GPUISceneTests"
    }
    Invoke-Step "SceneRasterizerTests" {
        & $testScript -Filter "SceneRasterizerTests"
    }
    Invoke-Step "D3D11BatchRendererTests" {
        & $testScript -Filter "D3D11BatchRendererTests"
    }
    Invoke-Step "RetainedViewRuntimeTests" {
        & $testScript -Filter "RetainedViewRuntimeTests"
    }
    Invoke-Step "swift build swift-windowsui" {
        & $buildScript -Product "swift-windowsui"
    }
}

Write-Host ""
Write-Host "Agent check passed."
exit 0
