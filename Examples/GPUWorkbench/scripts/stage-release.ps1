param(
    [Parameter(Mandatory = $true)][string]$ExecutablePath,
    [Parameter(Mandatory = $true)][string]$ResourceBundlePath,
    # Explicit reviewed transitive non-system runtime dependencies. No PATH scan.
    [Parameter(Mandatory = $true)][string[]]$DllPath,
    [Parameter(Mandatory = $true)][string]$DestinationDirectory
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Get-OrdinaryPath([string]$Path, [bool]$Directory) {
    if (-not (Test-Path -LiteralPath $Path)) { throw "Required staging path is missing: $Path" }
    $item = Get-Item -LiteralPath $Path -Force
    if ($item.PSIsContainer -ne $Directory) { throw "Unexpected path kind: $Path" }
    $ancestor = $item
    while ($null -ne $ancestor) {
        if (($ancestor.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw "Resolve reparse points before staging: $($ancestor.FullName)"
        }
        $ancestor = if ($ancestor -is [IO.DirectoryInfo]) { $ancestor.Parent } else { $ancestor.Directory }
    }
    return $item.FullName
}

$executable = Get-OrdinaryPath $ExecutablePath $false
if ([IO.Path]::GetFileName($executable) -cne 'GPUWorkbench.exe') {
    throw 'Executable must be the release GPUWorkbench.exe product.'
}
$bundle = Get-OrdinaryPath $ResourceBundlePath $true
$bundleName = [IO.Path]::GetFileName($bundle)
if (-not $bundleName.EndsWith('.resources', [StringComparison]::OrdinalIgnoreCase)) {
    throw 'Supply the whole generated SwiftPM .resources directory.'
}
$mark = Join-Path $bundle 'gpu-workbench-mark.png'
$null = Get-OrdinaryPath $mark $false
$items = @(Get-ChildItem -LiteralPath $bundle -Recurse -Force)
foreach ($item in $items) {
    if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
        throw "Resource reparse point is not supported: $($item.FullName)"
    }
}
if ($DllPath.Count -eq 0) { throw 'Supply the reviewed Swift/runtime DLL closure.' }
$files = [Collections.Generic.List[object]]::new()
$files.Add([pscustomobject]@{ Source = $executable; Relative = 'GPUWorkbench.exe' })
$names = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
$null = $names.Add('GPUWorkbench.exe')
foreach ($path in $DllPath) {
    $dll = Get-OrdinaryPath $path $false
    $name = [IO.Path]::GetFileName($dll)
    if ([IO.Path]::GetExtension($name) -ine '.dll' -or -not $names.Add($name)) {
        throw "Invalid or duplicate DLL filename: $name"
    }
    $files.Add([pscustomobject]@{ Source = $dll; Relative = $name })
}
foreach ($item in $items | Where-Object { -not $_.PSIsContainer }) {
    $relative = $item.FullName.Substring($bundle.Length).TrimStart('\', '/')
    $files.Add([pscustomobject]@{ Source = $item.FullName; Relative = "$bundleName/$relative" })
}

$destination = [IO.Path]::GetFullPath($DestinationDirectory)
if (Test-Path -LiteralPath $destination) { throw 'Destination must not already exist.' }
$parent = Split-Path -Parent $destination
$null = Get-OrdinaryPath $parent $true
if ($destination.StartsWith($bundle + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
    throw 'Destination must not be inside the source bundle.'
}
$null = New-Item -ItemType Directory -Path $destination
$null = New-Item -ItemType Directory -Path (Join-Path $destination $bundleName)
foreach ($item in $items | Where-Object { $_.PSIsContainer }) {
    $relative = $item.FullName.Substring($bundle.Length).TrimStart('\', '/')
    $null = New-Item -ItemType Directory -Path (Join-Path $destination "$bundleName/$relative") -Force
}
$manifest = @()
foreach ($file in $files) {
    $sourceHash = (Get-FileHash -LiteralPath $file.Source -Algorithm SHA256).Hash.ToLowerInvariant()
    $target = Join-Path $destination $file.Relative
    Copy-Item -LiteralPath $file.Source -Destination $target
    $copiedHash = (Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($sourceHash -cne $copiedHash) { throw "Copied bytes differ: $($file.Relative)" }
    $manifest += [ordered]@{
        path = $file.Relative.Replace('\', '/')
        length = (Get-Item -LiteralPath $target).Length
        sha256 = $copiedHash
    }
}
[ordered]@{
    schema = 'GPUWorkbench.stage.v1'
    files = $manifest
    dllClosureVerified = $false
    nativeSmokePassed = $false
} | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $destination 'stage-manifest.json') -Encoding UTF8
Write-Output "Staged $($manifest.Count) files in $destination. Runtime closure and native behavior still require qualification."
