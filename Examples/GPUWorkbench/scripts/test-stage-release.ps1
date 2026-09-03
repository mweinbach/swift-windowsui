$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$root = Join-Path ([IO.Path]::GetTempPath()) ('GPUWorkbench-stage-tests-' + [Guid]::NewGuid().ToString('N'))
$null = New-Item -ItemType Directory -Path $root
$source = Join-Path $root 'source'
$bundle = Join-Path $source 'fixture_GPUWorkbench.resources'
$null = New-Item -ItemType Directory -Path (Join-Path $bundle 'nested/empty') -Force
[IO.File]::WriteAllBytes((Join-Path $source 'GPUWorkbench.exe'), [byte[]]@(1, 2, 3))
[IO.File]::WriteAllBytes((Join-Path $source 'swiftCore.dll'), [byte[]]@(4, 5, 6))
[IO.File]::WriteAllBytes((Join-Path $bundle 'gpu-workbench-mark.png'), [byte[]]@(7, 8, 9))
[IO.File]::WriteAllBytes((Join-Path $bundle 'nested/metadata.bin'), [byte[]]@(10, 11))
$stage = Join-Path $root 'good-stage'
$script = Join-Path $PSScriptRoot 'stage-release.ps1'
$arguments = @{
    ExecutablePath = Join-Path $source 'GPUWorkbench.exe'
    ResourceBundlePath = $bundle
    DllPath = @((Join-Path $source 'swiftCore.dll'))
}
& $script @arguments -DestinationDirectory $stage | Out-Null
$manifest = Get-Content -LiteralPath (Join-Path $stage 'stage-manifest.json') -Raw | ConvertFrom-Json
if ($manifest.files.Count -ne 4 -or $manifest.dllClosureVerified -ne $false -or $manifest.nativeSmokePassed -ne $false) {
    throw 'Synthetic staging manifest is incomplete or overstates validation.'
}
foreach ($file in $manifest.files) {
    $copy = Join-Path $stage $file.path
    if ((Get-FileHash -LiteralPath $copy -Algorithm SHA256).Hash -ine $file.sha256) {
        throw "Copy mismatch: $($file.path)"
    }
}
if (-not (Test-Path -LiteralPath (Join-Path $stage 'fixture_GPUWorkbench.resources/nested/empty') -PathType Container)) {
    throw 'Empty resource directory was not preserved.'
}

function Expect-Failure([scriptblock]$Action, [string]$Message) {
    try { & $Action | Out-Null } catch {
        if ($_.Exception.Message -notlike "*$Message*") { throw }
        return
    }
    throw "Expected failure did not occur: $Message"
}
Expect-Failure { & $script @arguments -DestinationDirectory $stage } 'Destination must not already exist'
$duplicate = $arguments.Clone()
$duplicate.DllPath = @($arguments.DllPath[0], $arguments.DllPath[0])
Expect-Failure { & $script @duplicate -DestinationDirectory (Join-Path $root 'duplicate') } 'duplicate DLL filename'
$missing = $arguments.Clone()
$missing.DllPath = @((Join-Path $source 'missing.dll'))
Expect-Failure { & $script @missing -DestinationDirectory (Join-Path $root 'missing-dll') } 'Required staging path is missing'
$missingBundle = Join-Path $root 'missing_GPUWorkbench.resources'
$null = New-Item -ItemType Directory -Path $missingBundle
$missing = $arguments.Clone()
$missing.ResourceBundlePath = $missingBundle
Expect-Failure { & $script @missing -DestinationDirectory (Join-Path $root 'missing-mark') } 'Required staging path is missing'
Write-Output "PASS: five synthetic staging cases; no Swift, executable, or DLL was loaded. Fixtures retained at $root"
