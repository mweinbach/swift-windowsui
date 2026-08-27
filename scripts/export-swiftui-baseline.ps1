<#
.SYNOPSIS
Exports the pinned Apple desktop SwiftUI API as auditable inventory evidence.
.DESCRIPTION
Run with PowerShell 7 (pwsh) on a Mac with the pinned Xcode installed. This
does not run SwiftPM, change xcode-select, edit the baseline manifest, or
claim API/behavior conformance. Set DEVELOPER_DIR to select an installation.
.PARAMETER RequireReviewedIdentity
Reject an initial candidate capture until exact build identifiers have been
captured, reviewed, and explicitly recorded in docs/swiftui-baseline.json.
#>
param(
    [string]$OutputPath,
    [string]$ManifestPath = (Join-Path (Split-Path -Parent $PSScriptRoot) "docs/swiftui-baseline.json"),
    [switch]$RequireReviewedIdentity
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "swiftui-baseline-common.ps1")

if ($PSVersionTable.PSVersion.Major -lt 7 -or -not $IsMacOS) {
    throw "SwiftUI baseline export requires PowerShell 7 (pwsh) on macOS with the pinned Xcode. Windows fixture tests do not constitute an SDK capture."
}

$manifest = Read-SwiftUIBaselineManifest -Path $ManifestPath
$repoRoot = Split-Path -Parent $PSScriptRoot
$nativeCommands = [System.Collections.Generic.List[object]]::new()

function Invoke-SwiftUIBaselineNativeCommand {
    param(
        [Parameter(Mandatory)][string]$FilePath,
        [Parameter(Mandatory)][string[]]$Arguments,
        [int]$TimeoutSeconds = 60
    )

    # ArgumentList passes each argument literally, including installation paths
    # containing spaces. No command string is evaluated by a shell.
    $startInfo = [System.Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = $FilePath
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    foreach ($argument in $Arguments) { $startInfo.ArgumentList.Add($argument) }
    $process = [System.Diagnostics.Process]::new()
    $process.StartInfo = $startInfo
    $started = [DateTime]::UtcNow
    try {
        [void]$process.Start()
        $stdoutTask = $process.StandardOutput.ReadToEndAsync()
        $stderrTask = $process.StandardError.ReadToEndAsync()
        $timedOut = -not $process.WaitForExit($TimeoutSeconds * 1000)
        if ($timedOut) {
            $process.Kill($true)
            $process.WaitForExit()
        }
        $stdout = $stdoutTask.GetAwaiter().GetResult()
        $stderr = $stderrTask.GetAwaiter().GetResult()
        $nativeCommands.Add([pscustomobject][ordered]@{
            executable = $FilePath
            arguments = $Arguments
            exitCode = $process.ExitCode
            timedOut = $timedOut
            startedAtUtc = $started.ToString("o")
            durationSeconds = ([DateTime]::UtcNow - $started).TotalSeconds
            stdout = $stdout
            stderr = $stderr
        })
        if ($timedOut) { throw "Native command timed out after ${TimeoutSeconds}s: $FilePath" }
        if ($process.ExitCode -ne 0) {
            throw "Native command failed ($($process.ExitCode)): $FilePath $($Arguments -join ' ')`n$stderr"
        }
        return $stdout.Trim()
    } finally {
        $process.Dispose()
    }
}

$xcrun = "/usr/bin/xcrun"
$xcodeOutput = Invoke-SwiftUIBaselineNativeCommand -FilePath "/usr/bin/xcodebuild" -Arguments @("-version")
$sdkVersion = Invoke-SwiftUIBaselineNativeCommand -FilePath $xcrun -Arguments @("--sdk", "macosx", "--show-sdk-version")
$sdkBuild = Invoke-SwiftUIBaselineNativeCommand -FilePath $xcrun -Arguments @("--sdk", "macosx", "--show-sdk-build-version")
$sdkPath = Invoke-SwiftUIBaselineNativeCommand -FilePath $xcrun -Arguments @("--sdk", "macosx", "--show-sdk-path")
$swiftPath = Invoke-SwiftUIBaselineNativeCommand -FilePath $xcrun -Arguments @("--toolchain", "XcodeDefault", "--find", "swift")
$extractorPath = Invoke-SwiftUIBaselineNativeCommand -FilePath $xcrun -Arguments @("--toolchain", "XcodeDefault", "--find", "swift-symbolgraph-extract")
if ($swiftPath -notmatch '/Toolchains/XcodeDefault\.xctoolchain/usr/bin/swift$' -or
    $extractorPath -notmatch '/Toolchains/XcodeDefault\.xctoolchain/usr/bin/swift-symbolgraph-extract$' -or
    [System.IO.Path]::GetDirectoryName($swiftPath) -cne [System.IO.Path]::GetDirectoryName($extractorPath)) {
    throw "Swift and swift-symbolgraph-extract must come from the same selected XcodeDefault toolchain."
}
$swiftOutput = Invoke-SwiftUIBaselineNativeCommand -FilePath $swiftPath -Arguments @("--version")
$identity = ConvertTo-SwiftUIBaselineIdentity -XcodeOutput $xcodeOutput -SDKVersion $sdkVersion -SDKBuildVersion $sdkBuild -SwiftOutput $swiftOutput
$identityReviewed = Assert-SwiftUIBaselineIdentity -Manifest $manifest -Identity $identity -RequireReviewedIdentity:$RequireReviewedIdentity
# Required flags are checked by the actual extraction. Some flags are hidden
# from help, and the extractor can return failure after displaying help.
# Never retry with extension, re-export, or API preservation disabled.

$sdkSettingsPath = Join-Path $sdkPath "SDKSettings.json"
if (-not (Test-Path -LiteralPath $sdkSettingsPath -PathType Leaf)) {
    $sdkSettingsPath = Join-Path $sdkPath "SDKSettings.plist"
}
if (-not (Test-Path -LiteralPath $sdkSettingsPath -PathType Leaf)) {
    throw "The selected SDK has no SDKSettings.json or SDKSettings.plist to capture."
}

if ([string]::IsNullOrWhiteSpace($OutputPath)) {
    $captureName = [DateTime]::UtcNow.ToString("yyyyMMddTHHmmssfffZ")
    $OutputPath = Join-Path $repoRoot "artifacts/swiftui-baseline/$captureName"
}
$captureRoot = [System.IO.Path]::GetFullPath($OutputPath)
$insideAllowedRoot = $false
foreach ($allowedRoot in @((Join-Path $repoRoot "artifacts"), [System.IO.Path]::GetTempPath())) {
    try {
        [void](Get-SwiftUIBaselineRelativePath -Root $allowedRoot -Path $captureRoot)
        $insideAllowedRoot = $true
    } catch { }
}
if (-not $insideAllowedRoot) { throw "Generated baseline evidence must be inside repository artifacts/ or the OS temporary directory." }
if (Test-Path -LiteralPath $captureRoot) {
    if (-not (Test-Path -LiteralPath $captureRoot -PathType Container) -or
        $null -ne (Get-ChildItem -LiteralPath $captureRoot -Force | Select-Object -First 1)) {
        throw "OutputPath must be a new or empty directory; existing evidence is never overwritten."
    }
} else {
    [void](New-Item -ItemType Directory -Path $captureRoot)
}

$startedAt = [DateTime]::UtcNow.ToString("o")
$statusPath = Join-Path $captureRoot "capture-status.json"
Write-SwiftUIBaselineJson -Path $statusPath -Value ([ordered]@{
    baselineId = $manifest.baselineId; status = "in-progress"; startedAtUtc = $startedAt
    behaviorConformance = "not-verified"
})

try {
    $manifestCopy = Join-Path $captureRoot "baseline-manifest.json"
    Copy-Item -LiteralPath $ManifestPath -Destination $manifestCopy
    $sdkSettingsCopy = Join-Path $captureRoot ([System.IO.Path]::GetFileName($sdkSettingsPath))
    Copy-Item -LiteralPath $sdkSettingsPath -Destination $sdkSettingsCopy
    $interfaceRecords = [System.Collections.Generic.List[object]]::new()
    $crossImportDefinitions = [System.Collections.Generic.List[object]]::new()
    foreach ($module in $manifest.scope.modules) {
        $interfaceDirectory = Join-Path $sdkPath "System/Library/Frameworks/$module.framework/Modules/$module.swiftmodule"
        $frameworkModulesDirectory = Split-Path -Parent $interfaceDirectory
        # The compiler can silently skip cross-import modules that fail to
        # load. Preserve their declarations for an explicit completeness
        # review rather than treating exit 0 as proof all overlays appeared.
        foreach ($definition in Get-ChildItem -LiteralPath $frameworkModulesDirectory -Filter '*.swiftoverlay' -File -Recurse) {
            $relativeDefinition = Get-SwiftUIBaselineRelativePath -Root $frameworkModulesDirectory -Path $definition.FullName
            $definitionCopy = Join-Path $captureRoot "cross-imports/$module/$relativeDefinition"
            [void](New-Item -ItemType Directory -Path (Split-Path -Parent $definitionCopy) -Force)
            Copy-Item -LiteralPath $definition.FullName -Destination $definitionCopy
            $crossImportDefinitions.Add([pscustomobject][ordered]@{
                module = $module
                path = Get-SwiftUIBaselineRelativePath -Root $captureRoot -Path $definitionCopy
                sdkRelativeSource = Get-SwiftUIBaselineRelativePath -Root $sdkPath -Path $definition.FullName
                sha256 = (Get-FileHash -LiteralPath $definitionCopy -Algorithm SHA256).Hash.ToLowerInvariant()
                evaluation = "not-performed; reconcile definitions with emitted graphs during inventory review"
            })
        }
        $interfaces = @(Get-ChildItem -LiteralPath $interfaceDirectory -Filter '*.swiftinterface' -File -Recurse |
            Where-Object { $_.Name -notmatch '\.(private|package)\.swiftinterface$' })
        if ($interfaces.Count -eq 0) { throw "No public Swift interfaces found for '$module'; import/re-export evidence would be incomplete." }
        foreach ($interface in $interfaces) {
            $relativeInterface = Get-SwiftUIBaselineRelativePath -Root $interfaceDirectory -Path $interface.FullName
            $copyPath = Join-Path $captureRoot "interfaces/$module/$relativeInterface"
            [void](New-Item -ItemType Directory -Path (Split-Path -Parent $copyPath) -Force)
            Copy-Item -LiteralPath $interface.FullName -Destination $copyPath
            $interfaceRecords.Add([pscustomobject][ordered]@{
                module = $module
                path = Get-SwiftUIBaselineRelativePath -Root $captureRoot -Path $copyPath
                sdkRelativeSource = Get-SwiftUIBaselineRelativePath -Root $sdkPath -Path $interface.FullName
                sha256 = (Get-FileHash -LiteralPath $copyPath -Algorithm SHA256).Hash.ToLowerInvariant()
                imports = Get-SwiftUIBaselineInterfaceImports -Text (Get-Content -LiteralPath $copyPath -Raw -Encoding UTF8)
            })
        }
    }

    $exports = [System.Collections.Generic.List[object]]::new()
    foreach ($target in $manifest.scope.targets) {
        $cacheDirectory = Join-Path $captureRoot "module-cache/$target"
        [void](New-Item -ItemType Directory -Path $cacheDirectory -Force)
        foreach ($module in $manifest.scope.modules) {
            $directory = Join-Path $captureRoot "graphs/$target/$module"
            [void](New-Item -ItemType Directory -Path $directory -Force)
            $arguments = @(
                "-module-name", $module,
                "-sdk", $sdkPath,
                "-target", $target,
                "-swift-version", $manifest.toolchain.swiftLanguageMode,
                "-module-cache-path", $cacheDirectory,
                "-minimum-access-level", "public",
                "-emit-extension-block-symbols",
                "-experimental-allowed-reexported-modules=$($manifest.scope.allowedReexportedModules -join ',')",
                "-v",
                "-pretty-print",
                "-output-dir", $directory
            )
            Write-Host "==> Export $module ($target)"
            [void](Invoke-SwiftUIBaselineNativeCommand -FilePath $extractorPath -Arguments $arguments -TimeoutSeconds 1200)
            $exports.Add([pscustomobject]@{ module = $module; target = $target; directory = $directory })
        }
    }

    $inventory = New-SwiftUIBaselineInventory -Manifest $manifest -CaptureRoot $captureRoot -Exports $exports.ToArray()
    $inventoryPath = Join-Path $captureRoot "inventory.json"
    Write-SwiftUIBaselineJson -Value $inventory -Path $inventoryPath
    $hostVersion = Invoke-SwiftUIBaselineNativeCommand -FilePath "/usr/bin/sw_vers" -Arguments @("-productVersion")
    $hostBuild = Invoke-SwiftUIBaselineNativeCommand -FilePath "/usr/bin/sw_vers" -Arguments @("-buildVersion")
    $hostArchitecture = Invoke-SwiftUIBaselineNativeCommand -FilePath "/usr/bin/uname" -Arguments @("-m")
    $capture = [ordered]@{
        schemaVersion = 1
        baselineId = $manifest.baselineId
        status = "exported-awaiting-inventory-and-behavior-review"
        startedAtUtc = $startedAt
        finishedAtUtc = [DateTime]::UtcNow.ToString("o")
        exactIdentityPreviouslyReviewed = $identityReviewed
        observedIdentity = $identity
        host = [ordered]@{
            macOSVersion = $hostVersion; macOSBuildVersion = $hostBuild
            architecture = $hostArchitecture; powerShellVersion = $PSVersionTable.PSVersion.ToString()
            note = "Export host only; no native SwiftUI reference behavior was exercised."
        }
        developerDirectoryOverride = $env:DEVELOPER_DIR
        baselineManifest = [ordered]@{
            path = "baseline-manifest.json"
            sha256 = (Get-FileHash -LiteralPath $manifestCopy -Algorithm SHA256).Hash.ToLowerInvariant()
        }
        tools = @(
            [ordered]@{ path = $swiftPath; sha256 = (Get-FileHash -LiteralPath $swiftPath -Algorithm SHA256).Hash.ToLowerInvariant() },
            [ordered]@{ path = $extractorPath; sha256 = (Get-FileHash -LiteralPath $extractorPath -Algorithm SHA256).Hash.ToLowerInvariant() }
        )
        exporterSources = @(
            foreach ($scriptName in @("export-swiftui-baseline.ps1", "swiftui-baseline-common.ps1")) {
                [ordered]@{ path = "scripts/$scriptName"; sha256 = (Get-FileHash -LiteralPath (Join-Path $PSScriptRoot $scriptName) -Algorithm SHA256).Hash.ToLowerInvariant() }
            }
        )
        sdk = [ordered]@{
            path = $sdkPath; version = $sdkVersion; buildVersion = $sdkBuild
            settingsPath = [System.IO.Path]::GetFileName($sdkSettingsCopy)
            settingsSha256 = (Get-FileHash -LiteralPath $sdkSettingsCopy -Algorithm SHA256).Hash.ToLowerInvariant()
        }
        requestedScope = $manifest.scope
        publicInterfaces = $interfaceRecords.ToArray()
        crossImportDefinitions = $crossImportDefinitions.ToArray()
        crossImportOverlayCompleteness = "not-verified; compiler may silently skip an overlay that fails to load"
        inventory = [ordered]@{
            path = "inventory.json"
            sha256 = (Get-FileHash -LiteralPath $inventoryPath -Algorithm SHA256).Hash.ToLowerInvariant()
            graphSetSha256 = $inventory.graphSetSha256
            counts = $inventory.counts
        }
        commands = $nativeCommands.ToArray()
        qualification = [ordered]@{
            publicAPIAuditComplete = $false
            behaviorConformanceVerified = $false
            releaseQualified = $false
        }
    }
    $capturePath = Join-Path $captureRoot "capture.json"
    Write-SwiftUIBaselineJson -Value $capture -Path $capturePath
    $captureHash = (Get-FileHash -LiteralPath $capturePath -Algorithm SHA256).Hash.ToLowerInvariant()
    [System.IO.File]::WriteAllText((Join-Path $captureRoot "capture.sha256"), "$captureHash  capture.json`n", [System.Text.UTF8Encoding]::new($false))
    Write-SwiftUIBaselineJson -Path $statusPath -Value ([ordered]@{
        baselineId = $manifest.baselineId; status = "exported-awaiting-review"
        captureManifest = "capture.json"; captureManifestSha256 = $captureHash
        behaviorConformance = "not-verified"
    })
    Write-Host "Exported $($inventory.counts.preciseSymbols) precise symbol identifiers; this is not behavior conformance."
    if (-not $identityReviewed) { Write-Warning "Exact build identity is captured but remains unreviewed. The baseline manifest was not changed." }
    Write-Host "Evidence: $captureRoot"
} catch {
    Write-SwiftUIBaselineJson -Path $statusPath -Value ([ordered]@{
        baselineId = $manifest.baselineId; status = "failed"; startedAtUtc = $startedAt
        error = $_.Exception.Message; commands = $nativeCommands.ToArray()
        behaviorConformance = "not-verified"
    })
    throw
}
