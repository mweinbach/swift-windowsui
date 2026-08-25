param(
    [switch]$BuildProducts
)

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent $PSScriptRoot
$withSwift = Join-Path $PSScriptRoot "with-swift.ps1"

if ($BuildProducts) {
    $portableProducts = @(
        "SwiftWindowsCore",
        "SwiftWindowsGraphics",
        "SwiftWindowsLayout",
        "SwiftWindowsScene"
    )

    $manifestOutput = & $withSwift swift package --package-path $repoRoot dump-package
    if ($LASTEXITCODE -ne 0) {
        exit $LASTEXITCODE
    }
    $manifest = $manifestOutput | ConvertFrom-Json
    $publishedProducts = @($manifest.products | ForEach-Object { $_.name })

    foreach ($product in $portableProducts) {
        if ($product -notin $publishedProducts) {
            throw "Portable public library product '$product' is missing from Package.swift."
        }

        # Automatic SwiftPM library products cannot be isolated with
        # --product; --target proves the actual module dependency closure.
        Write-Host "==> Portable public product and isolated target: $product"
        & $withSwift swift build --package-path $repoRoot --target $product
        if ($LASTEXITCODE -ne 0) {
            exit $LASTEXITCODE
        }
    }
}

Write-Host "==> Renderer-neutral portable core, layout, and CPU backend tests"
& $withSwift swift test --package-path $repoRoot --filter SwiftWindowsPortableTests
exit $LASTEXITCODE
