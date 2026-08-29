[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$BundlePath,
    [Parameter(Mandatory = $true)]
    [string]$DestinationDirectory
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

function Get-DemoResourceDigest([string]$Path) {
    $stream = [System.IO.File]::OpenRead($Path)
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $length = $stream.Length
        $digest = [System.BitConverter]::ToString($sha.ComputeHash($stream)).Replace("-", "").ToLowerInvariant()
        if ($stream.Length -ne $length) { throw "Resource length changed while reading '$Path'." }
        return [pscustomobject]@{ Length = $length; SHA256 = $digest }
    } finally {
        $sha.Dispose()
        $stream.Dispose()
    }
}

function Assert-DemoResourceDirectory([string]$Path) {
    $item = Get-Item -LiteralPath $Path -Force
    if ($item -isnot [System.IO.DirectoryInfo]) { throw "Expected a filesystem directory: '$Path'." }
    $ancestor = $item
    while ($null -ne $ancestor) {
        if (($ancestor.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw "Resource copying refuses reparse-point directories: '$($ancestor.FullName)'."
        }
        $ancestor = $ancestor.Parent
    }
    return $item
}

# Take the actual generated bundle as an explicit input. SwiftPM's basename
# and platform-specific internal paths must not be guessed from the product.
$source = Assert-DemoResourceDirectory $BundlePath
$destination = Assert-DemoResourceDirectory $DestinationDirectory
if ($null -eq $source.Parent) { throw "A filesystem root is not a resource bundle." }
$sourcePrefix = $source.FullName.TrimEnd('\', '/') + [System.IO.Path]::DirectorySeparatorChar
if ($destination.FullName.Equals($source.FullName, [System.StringComparison]::OrdinalIgnoreCase) -or
    $destination.FullName.StartsWith($sourcePrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "The destination must be outside the source resource bundle."
}
$target = Join-Path $destination.FullName $source.Name
if (Test-Path -LiteralPath $target) { throw "Destination bundle already exists: '$target'." }

$directories = New-Object 'System.Collections.Generic.List[string]'
$files = New-Object 'System.Collections.Generic.List[object]'
$pending = New-Object 'System.Collections.Generic.Stack[System.IO.DirectoryInfo]'
$pending.Push($source)
while ($pending.Count -gt 0) {
    $directory = $pending.Pop()
    foreach ($entry in (Get-ChildItem -LiteralPath $directory.FullName -Force)) {
        if (($entry.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw "Resource copying refuses reparse-point entries: '$($entry.FullName)'."
        }
        if (-not $entry.FullName.StartsWith($sourcePrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
            throw "Resource entry escaped the supplied bundle."
        }
        $relative = $entry.FullName.Substring($sourcePrefix.Length)
        if ($entry -is [System.IO.DirectoryInfo]) {
            $directories.Add($relative)
            $pending.Push($entry)
        } elseif ($entry -is [System.IO.FileInfo]) {
            $files.Add([pscustomobject]@{
                Name = $entry.Name
                Source = $entry.FullName
                Relative = $relative
                Digest = Get-DemoResourceDigest $entry.FullName
            })
        } else {
            throw "Unsupported resource entry: '$($entry.FullName)'."
        }
    }
}

# This helper stages the shared demo's bundle, not any arbitrary directory.
# Preserve all other resources and empty directories, including metadata.
foreach ($required in @("demo-bitmap-caps.png", "demo-bitmap-tile.png")) {
    $matches = @($files | Where-Object { $_.Name -ceq $required })
    if ($matches.Count -ne 1) { throw "Expected exactly one '$required' in the supplied bundle." }
}

# There is no overwrite, merge, deletion, or rollback. A failed copy leaves
# its partial destination for inspection and a later call refuses that path.
[System.IO.Directory]::CreateDirectory($target) | Out-Null
foreach ($relative in ($directories | Sort-Object)) {
    [System.IO.Directory]::CreateDirectory((Join-Path $target $relative)) | Out-Null
}
[long]$totalBytes = 0
foreach ($file in ($files | Sort-Object Relative)) {
    $copyPath = Join-Path $target $file.Relative
    [System.IO.File]::Copy($file.Source, $copyPath, $false)
    $copied = Get-DemoResourceDigest $copyPath
    $sourceAfter = Get-DemoResourceDigest $file.Source
    foreach ($observed in @($copied, $sourceAfter)) {
        if ($observed.Length -ne $file.Digest.Length -or $observed.SHA256 -cne $file.Digest.SHA256) {
            throw "Resource content changed while copying '$($file.Relative)'."
        }
    }
    $totalBytes += $copied.Length
}

[pscustomobject]@{
    SourceBundlePath = $source.FullName
    DestinationBundlePath = $target
    FileCount = $files.Count
    ByteCount = $totalBytes
}
