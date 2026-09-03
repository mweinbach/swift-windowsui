param([Parameter(Mandatory = $true)][string]$PackageDirectory)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$package = (Get-Item -LiteralPath $PackageDirectory -Force).FullName
$manifest = Get-Content -LiteralPath (Join-Path $package 'stage-manifest.json') -Raw | ConvertFrom-Json
if ($manifest.schema -cne 'GPUWorkbench.stage.v1') { throw 'Unsupported stage manifest.' }
$names = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
foreach ($file in $manifest.files) {
    $name = [string]$file.path
    if ([IO.Path]::IsPathRooted($name) -or $name -match '(^|[/\\])\.\.([/\\]|$)' -or -not $names.Add($name)) {
        throw "Invalid manifest path: $name"
    }
    $path = [IO.Path]::GetFullPath((Join-Path $package $name))
    if (-not $path.StartsWith($package + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Path escapes package: $name"
    }
    $item = Get-Item -LiteralPath $path -Force
    if ($item.PSIsContainer -or $item.Length -ne $file.length -or
        (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -ine $file.sha256) {
        throw "Missing or changed package file: $name"
    }
}
if (-not $names.Contains('GPUWorkbench.exe')) { throw 'Manifest lacks GPUWorkbench.exe.' }

# A fresh unrelated cwd and child-only environment prevent developer PATH from
# satisfying runtime dependencies. This is not a clean-machine qualification.
$working = Join-Path ([IO.Path]::GetTempPath()) ('GPUWorkbench-deployment-' + [Guid]::NewGuid().ToString('N'))
$null = New-Item -ItemType Directory -Path $working
$info = [Diagnostics.ProcessStartInfo]::new()
$info.FileName = Join-Path $package 'GPUWorkbench.exe'
$info.Arguments = '--check-deployment'
$info.WorkingDirectory = $working
$info.UseShellExecute = $false
$info.CreateNoWindow = $true
$info.RedirectStandardOutput = $true
$info.RedirectStandardError = $true
$info.StandardOutputEncoding = [Text.UTF8Encoding]::new($false)
$info.StandardErrorEncoding = [Text.UTF8Encoding]::new($false)
$info.EnvironmentVariables['PATH'] = "$package;$env:SystemRoot\System32;$env:SystemRoot"
foreach ($key in @($info.EnvironmentVariables.Keys)) {
    if ($key -match '^(SDKROOT|SWIFT.*|LLVM.*|LIB|LIBPATH|INCLUDE)$') {
        $info.EnvironmentVariables.Remove($key)
    }
}
$process = [Diagnostics.Process]::new()
$process.StartInfo = $info
try {
    if (-not $process.Start()) { throw 'Failed to start staged executable.' }
    $stdout = $process.StandardOutput.ReadToEndAsync()
    $stderr = $process.StandardError.ReadToEndAsync()
    if (-not $process.WaitForExit(30000)) {
        $process.Kill()
        if (-not $process.WaitForExit(5000)) { throw 'Owned deployment check did not close after termination.' }
        throw 'Deployment check exceeded 30 seconds; it did not pass.'
    }
    $output = $stdout.GetAwaiter().GetResult()
    $errorOutput = $stderr.GetAwaiter().GetResult()
    if ($process.ExitCode -ne 0) {
        throw "Deployment check exited $($process.ExitCode). Missing runtime DLLs are a deployment failure. $errorOutput"
    }
    $receipt = $output | ConvertFrom-Json
    if ($receipt.check -cne 'GPUWorkbench.deployment.v1' -or $receipt.checksNativePresentation -ne $false) {
        throw 'The executable did not return the expected deployment-only receipt.'
    }
    $output
} finally {
    $process.Dispose()
    # Leave the unique working directory available for inspection. No cleanup
    # by name and no action against an unrelated running application.
}
