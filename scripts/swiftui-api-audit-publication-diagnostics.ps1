# Loaded only after Directory.Move fails. These bounded observations do not
# establish a cause, change the original error, retry publication, or alter cleanup.

function Get-SwiftUIAuditPublicationExceptionFacts {
    param([Parameter(Mandatory)][System.Exception]$Exception)

    $chain = [System.Collections.Generic.List[object]]::new()
    $cursor = $Exception
    while ($null -ne $cursor -and $chain.Count -lt 8) {
        $typeName = [string]$cursor.GetType().FullName
        if ($typeName.Length -gt 256) { $typeName = $typeName.Substring(0, 256) }
        $hresult = [int]$cursor.HResult
        $nativeErrorCode = $null
        if ($cursor -is [System.ComponentModel.Win32Exception]) {
            $nativeErrorCode = [int]$cursor.NativeErrorCode
        }
        $chain.Add([ordered]@{
            type = $typeName
            hresult = $hresult
            hresultHex = "0x" + $hresult.ToString("X8")
            nativeErrorCode = $nativeErrorCode
        })
        $cursor = $cursor.InnerException
    }
    return [pscustomobject][ordered]@{ chain = $chain.ToArray(); truncated = ($null -ne $cursor) }
}

function Get-SwiftUIAuditPublicationPathFacts {
    param([Parameter(Mandatory)][string]$Path)

    if ($Path.Length -gt 32768) { throw "Publication diagnostic path exceeds its bound." }
    $attributes = $null
    $attributeReadError = $null
    try {
        $attributes = [int][System.IO.File]::GetAttributes($Path)
    } catch {
        $exception = $_.Exception
        $typeName = [string]$exception.GetType().FullName
        if ($typeName.Length -gt 256) { $typeName = $typeName.Substring(0, 256) }
        $hresult = [int]$exception.HResult
        $exceptionFacts = Get-SwiftUIAuditPublicationExceptionFacts -Exception $exception
        $attributeReadError = [ordered]@{
            type = $typeName
            hresult = $hresult
            hresultHex = "0x" + $hresult.ToString("X8")
            exceptions = $exceptionFacts.chain
            exceptionChainTruncated = $exceptionFacts.truncated
        }
    }
    # Exists can return false for an inaccessible path. Keep the attribute read
    # error separately; these observations are not proof that a path is absent.
    return [pscustomobject][ordered]@{
        path = $Path
        fileExists = [System.IO.File]::Exists($Path)
        directoryExists = [System.IO.Directory]::Exists($Path)
        attributes = $attributes
        attributeReadError = $attributeReadError
    }
}

function Write-SwiftUIAuditPublicationFailureDiagnostic {
    param(
        [Parameter(Mandatory)][System.Management.Automation.ErrorRecord]$ErrorRecord,
        [Parameter(Mandatory)][string]$StagingPath,
        [Parameter(Mandatory)][string]$OutputPath,
        [Parameter(Mandatory)][string]$OutputParent,
        [Parameter(Mandatory)][string]$StagingLeaf,
        [Parameter(Mandatory)][string]$ManifestSha256,
        [Parameter(Mandatory)][string]$AttemptedAtUTC
    )

    if ($StagingLeaf -cnotmatch '\A\.swiftui-api-audit-[0-9a-f]{32}\z' -or
        $ManifestSha256 -cnotmatch '\A[0-9a-f]{64}\z' -or $AttemptedAtUTC.Length -gt 64) {
        throw "Invalid publication diagnostic identity."
    }
    foreach ($path in @($StagingPath, $OutputPath, $OutputParent)) {
        if ($path.Length -gt 32768) { throw "Publication diagnostic path exceeds its bound." }
    }
    $parent = [System.IO.Path]::GetFullPath($OutputParent)
    $staging = [System.IO.Path]::GetFullPath($StagingPath)
    $destination = [System.IO.Path]::GetFullPath($OutputPath)
    if ((Resolve-SwiftUIBaselineFileSystemPath -Path $parent) -cne $parent -or
        [System.IO.Path]::GetDirectoryName($staging) -cne $parent -or
        [System.IO.Path]::GetDirectoryName($destination) -cne $parent -or
        [System.IO.Path]::GetFileName($staging) -cne $StagingLeaf -or
        -not [System.IO.Directory]::Exists($parent) -or
        (([System.IO.File]::GetAttributes($parent)) -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
        throw "Refusing unsafe publication diagnostic destination."
    }
    $diagnosticPath = Join-Path $parent ($StagingLeaf + ".publication-failure.json")
    if ([System.IO.Path]::GetDirectoryName([System.IO.Path]::GetFullPath($diagnosticPath)) -cne $parent) {
        throw "Publication diagnostic must remain in its owned parent."
    }
    $currentDirectory = [string][Environment]::CurrentDirectory
    if ($currentDirectory.Length -gt 32768) { throw "Publication diagnostic current directory exceeds its bound." }
    $exceptions = Get-SwiftUIAuditPublicationExceptionFacts -Exception $ErrorRecord.Exception
    $report = [ordered]@{
        schemaVersion = 1
        evidenceKind = "api-audit-publication-failure-diagnostic"
        operation = "System.IO.Directory.Move"
        attemptedAtUTC = $AttemptedAtUTC
        observedAtUTC = [DateTime]::UtcNow.ToString("o")
        auditManifestSha256 = $ManifestSha256
        paths = [ordered]@{
            staging = Get-SwiftUIAuditPublicationPathFacts -Path $staging
            destination = Get-SwiftUIAuditPublicationPathFacts -Path $destination
            parent = Get-SwiftUIAuditPublicationPathFacts -Path $parent
        }
        process = [ordered]@{
            pid = [int]$PID
            powerShellVersion = [string]$PSVersionTable.PSVersion.ToString()
            clrVersion = [string][Environment]::Version.ToString()
            currentDirectory = $currentDirectory
        }
        exceptions = $exceptions.chain
        exceptionChainTruncated = $exceptions.truncated
        publicationSucceeded = $false
        failureCauseEstablished = $false
    }
    # Only the explicitly projected primitives above reach JSON serialization.
    $json = ConvertTo-Json -InputObject $report -Depth 8 -Compress -WarningAction Stop
    $bytes = [System.Text.UTF8Encoding]::new($false, $true).GetBytes($json + "`n")
    if ($bytes.Length -gt 256KB) { throw "Publication diagnostic exceeds its byte bound." }
    $stream = $null
    try {
        $stream = [System.IO.FileStream]::new($diagnosticPath, [System.IO.FileMode]::CreateNew,
            [System.IO.FileAccess]::Write, [System.IO.FileShare]::Read)
        $stream.Write($bytes, 0, $bytes.Length)
    } finally {
        if ($null -ne $stream) { $stream.Dispose() }
    }
    return $diagnosticPath
}
