param(
    [switch]$Quick,
    [switch]$Full,
    [switch]$Format,
    [switch]$ContractsOnly,
    [switch]$GalleryCompare
)

$ErrorActionPreference = "Stop"
$testScript = Join-Path $PSScriptRoot "test.ps1"
$buildScript = Join-Path $PSScriptRoot "build.ps1"
$lintScript = Join-Path $PSScriptRoot "lint.ps1"
$contractScript = Join-Path $PSScriptRoot "check-contracts.ps1"
$screenshotScript = Join-Path $PSScriptRoot "demo-screenshot.ps1"
$galleryCompareScript = Join-Path $PSScriptRoot "gallery-compare.ps1"
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
    Invoke-Step "gallery regression gate" {
        & $galleryCompareScript
    }
} else {
    Invoke-Step "GPUISceneTests" {
        & $testScript -Filter "GPUISceneTests"
    }
    # The single draw-order authority and the replay log behind it. Cheap
    # (~0.4 s of tests) and the only gate on the invariant that the CPU
    # rasterizer and the D3D11 plan builder read one presentation order.
    Invoke-Step "ScenePresentationOrderTests" {
        & $testScript -Filter "ScenePresentationOrderTests"
    }
    Invoke-Step "SceneRasterizerTests" {
        & $testScript -Filter "SceneRasterizerTests"
    }
    # Path fills/strokes intentionally bypass solid-quad promotion; both the
    # raw scene rasterizer and shipping D3D11 path cache must preserve authored
    # gradient stops, transformed coordinates, and cache identity.
    Invoke-Step "PathGradientRenderingTests" {
        & $testScript -Filter "PathGradientRenderingTests"
    }
    Invoke-Step "CanvasPathGradientIntegrationTests" {
        & $testScript -Filter "CanvasPathGradientIntegrationTests"
    }
    # The coverage kernel the CPU rasterizer shares with the quad shader,
    # checked against an independent transcription of the HLSL (~0.02 s).
    # A divergence here is invisible to every screenshot gate, because every
    # screenshot comes through the CPU side of it.
    Invoke-Step "SharedCoverageKernelTests" {
        & $testScript -Filter "SharedCoverageKernelTests"
    }
    Invoke-Step "D3D11BatchRendererTests" {
        & $testScript -Filter "D3D11BatchRendererTests"
    }
    # The GPU frame path and cross-backend pixel parity: these run the real
    # D3D11 batch renderer offscreen on WARP, so they observe what the CPU
    # rasterizer (which every screenshot goes through) cannot.
    Invoke-Step "D3D11BatchRendererRenderTests" {
        & $testScript -Filter "D3D11BatchRendererRenderTests"
    }
    Invoke-Step "CrossBackendPixelParityTests" {
        & $testScript -Filter "CrossBackendPixelParityTests"
    }
    # One blend decision on both paths: source-over everywhere, asserted on
    # the scene path, the frame path and WARP (~0.15 s). Landing the opposite
    # decision means implementing the modes on the GPU, not editing this step.
    Invoke-Step "CPUGPUBlendModeContractTests" {
        & $testScript -Filter "CPUGPUBlendModeContractTests"
    }
    # The pixel-format contract: BGRA channel order, the straight vs
    # premultiplied alpha convention each producer declares, and the
    # validation that stops a short buffer reaching CreateTexture2D.
    Invoke-Step "PixelFormatContractTests" {
        & $testScript -Filter "PixelFormatContractTests"
    }
    # GPU resource lifetime: detach() releases what attach() acquired, and
    # the host calls it on window close and on every presenter switch.
    Invoke-Step "RenderBackendLifetimeTests" {
        & $testScript -Filter "RenderBackendLifetimeTests"
    }
    # Device loss: HRESULT classification, the bounded rebuild, generation
    # tokens keying device-owned caches, and the typed failure the host's
    # recovery policy switches on.
    Invoke-Step "DeviceLostPolicyTests" {
        & $testScript -Filter "DeviceLostPolicyTests"
    }
    Invoke-Step "DeviceLossRecoveryTests" {
        & $testScript -Filter "DeviceLossRecoveryTests"
    }
    Invoke-Step "PresentationFailurePolicyTests" {
        & $testScript -Filter "PresentationFailurePolicyTests"
    }
    Invoke-Step "MalformedInputResilienceTests" {
        & $testScript -Filter "MalformedInputResilienceTests"
    }
    # External clipboard/drop payloads cross a trust boundary; malformed wide
    # offsets and unsupported paste types must fail closed instead of trapping
    # or delivering a mismatched payload.
    Invoke-Step "DropFilesPayloadHardeningTests" {
        & $testScript -Filter "DropFilesPayloadHardeningTests"
    }
    Invoke-Step "ClipboardFileFormatTests" {
        & $testScript -Filter "ClipboardFileFormatTests"
    }
    # One clip value in one space: the narrowing rule, the in-band encoding,
    # rounded clips on every family, and the coherence of the painted and the
    # interactive region under a transform (~0.06 s).
    Invoke-Step "ClipAbstractionTests" {
        & $testScript -Filter "ClipAbstractionTests"
    }
    Invoke-Step "RetainedViewRuntimeTests" {
        & $testScript -Filter "RetainedViewRuntimeTests"
    }
    # Programmatic scrolling must work on first scene/frame render, resolve
    # deferred lazy-stack rows, and preserve nested-reader ownership.
    Invoke-Step "RuntimeProgrammaticScrollTests" {
        & $testScript -Filter "RuntimeProgrammaticScrollTests"
    }
    Invoke-Step "WinSwiftUIScrollViewReaderTests" {
        & $testScript -Filter "WinSwiftUIScrollViewReaderTests"
    }
    # The render-pass vocabulary both backends speak: the blur schedule, the
    # halving tap model and the texel-centre clamp, plus the cross-backend
    # parity scenes over it (~0.71 s). The contract check can only see that
    # each side *mentions* the shared derivations; this is what checks they
    # agree on the answers.
    Invoke-Step "RenderPassAbstractionTests" {
        & $testScript -Filter "RenderPassAbstractionTests"
    }
    # StrokeStyle as a contract rather than a suggestion: caps, joins and the
    # bounds outset that has to cover them, on both the tessellated and the
    # rasterized route (~0.03 s).
    Invoke-Step "StrokeStyleContractTests" {
        & $testScript -Filter "StrokeStyleContractTests"
    }
    # Never ship a glyph quad addressing someone else's atlas cell — through a
    # recycle, or through the free list handing a reclaimed cell to a second
    # glyph inside one pass (~0.06 s). Invisible to every screenshot gate,
    # because a stale UV renders as a plausible wrong character.
    Invoke-Step "GlyphAtlasExhaustionSafetyTests" {
        & $testScript -Filter "GlyphAtlasExhaustionSafetyTests"
    }
    Invoke-Step "swift build swift-windowsui" {
        & $buildScript -Product "swift-windowsui"
    }
    if ($GalleryCompare) {
        Invoke-Step "gallery regression gate" {
            & $galleryCompareScript
        }
    }
}

Write-Host ""
Write-Host "Agent check passed."
exit 0
