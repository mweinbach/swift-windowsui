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

function Invoke-Step {
    param(
        [string]$Name,
        [scriptblock]$Command
    )

    Write-Host ""
    Write-Host "==> $Name"
    & $Command
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Step failed: $Name" -ForegroundColor Red
        exit $LASTEXITCODE
    }
}

if (-not $Quick -and -not $Full -and -not $ContractsOnly) {
    $Quick = $true
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

if ($Full) {
    Invoke-Step "swift test" {
        & $testScript
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
