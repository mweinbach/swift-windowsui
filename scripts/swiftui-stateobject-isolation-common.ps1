# Bounded StateObject compiler-characterization helpers. Import defines functions
# only. This file never launches a process, invokes Swift, or writes evidence.

function Get-SwiftUIStateObjectBytesSHA256 {
    param([Parameter(Mandatory)][AllowEmptyCollection()][byte[]]$Bytes)
    $algorithm = [System.Security.Cryptography.SHA256]::Create()
    try { return [System.BitConverter]::ToString($algorithm.ComputeHash($Bytes)).Replace('-', '').ToLowerInvariant() }
    finally { $algorithm.Dispose() }
}

function Test-SwiftUIStateObjectUnixFileType {
    param([AllowNull()]$ItemType)
    return $ItemType -is [string] -and $ItemType -ceq 'File'
}

function Assert-SwiftUIStateObjectPathAncestors {
    param([Parameter(Mandatory)][string]$Path)
    $fullPath = [System.IO.Path]::GetFullPath($Path)
    $parentPath = [System.IO.Path]::GetDirectoryName($fullPath)
    while (-not [string]::IsNullOrEmpty($parentPath)) {
        $directory = Get-Item -LiteralPath $parentPath -Force -ErrorAction Stop
        if ($directory -isnot [System.IO.DirectoryInfo] -or
            ($directory.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -or
            ($directory.Attributes -band [System.IO.FileAttributes]::Device)) {
            throw "A path ancestor is not an ordinary directory: $parentPath"
        }
        $nextParent = [System.IO.Path]::GetDirectoryName($parentPath)
        if ($nextParent -ceq $parentPath) { break }
        $parentPath = $nextParent
    }
}

function Assert-SwiftUIStateObjectRegularFile {
    param([Parameter(Mandatory)][string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path) -or $Path -match '[\x00-\x1f\x7f]') { throw 'A regular-file path must be nonempty and contain no control characters.' }
    $file = Get-Item -LiteralPath $Path -Force -ErrorAction Stop
    if ($file -isnot [System.IO.FileInfo] -or $file.PSIsContainer -or
        ($file.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -or
        ($file.Attributes -band [System.IO.FileAttributes]::Device)) {
        throw "Evidence must be an ordinary regular file: $Path"
    }
    Assert-SwiftUIStateObjectPathAncestors -Path $file.FullName
    if ([System.Environment]::OSVersion.Platform -ne [System.PlatformID]::Win32NT) {
        if ($PSVersionTable.PSVersion.Major -lt 7) { throw 'Unix regular-file validation requires PowerShell 7 or newer.' }
        # Use fresh provider lstat metadata. UnixMode can cache display text by
        # permission bits and therefore cannot distinguish every FIFO from a file.
        $statProperty = $file.PSObject.Properties['UnixStat']
        if ($null -eq $statProperty -or $null -eq $statProperty.Value) { throw "Unix regular-file metadata is unavailable: $Path" }
        $typeProperty = $statProperty.Value.PSObject.Properties['ItemType']
        if ($null -eq $typeProperty -or
            -not (Test-SwiftUIStateObjectUnixFileType -ItemType ([string]$typeProperty.Value))) {
            throw "Evidence is not a proven Unix regular file: $Path"
        }
    }
    return $file
}

function Assert-SwiftUIStateObjectDirectory {
    param([Parameter(Mandatory)][string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path) -or $Path -match '[\x00-\x1f\x7f]') { throw 'An evidence directory path must be nonempty and contain no control characters.' }
    $directory = Get-Item -LiteralPath $Path -Force -ErrorAction Stop
    if ($directory -isnot [System.IO.DirectoryInfo] -or
        ($directory.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -or
        ($directory.Attributes -band [System.IO.FileAttributes]::Device)) {
        throw "Evidence root must be an ordinary directory: $Path"
    }
    Assert-SwiftUIStateObjectPathAncestors -Path $directory.FullName
    return $directory
}

function Assert-SwiftUIStateObjectRelativePath {
    param($Value, [string]$Name = 'relativePath')
    if ($Value -isnot [string] -or $Value.Length -gt 512 -or
        $Value -cnotmatch '\A[A-Za-z0-9][A-Za-z0-9._-]*(?:/[A-Za-z0-9][A-Za-z0-9._-]*)*\z') {
        throw "$Name must be a bounded portable relative path with forward slashes."
    }
    foreach ($segment in $Value.Split('/')) {
        if ($segment.EndsWith('.') -or $segment -match '\A(?i:CON|PRN|AUX|NUL|COM[0-9]|LPT[0-9])(?:\..*)?\z') {
            throw "$Name contains a reserved or ambiguous path component."
        }
    }
}

function Resolve-SwiftUIStateObjectEvidencePath {
    param(
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)][string]$RelativePath,
        [switch]$AllowMissingLeaf
    )
    Assert-SwiftUIStateObjectRelativePath -Value $RelativePath
    $directory = Assert-SwiftUIStateObjectDirectory -Path $Root
    $currentPath = $directory.FullName
    $segments = $RelativePath.Split('/')
    for ($index = 0; $index -lt $segments.Count; $index++) {
        $currentPath = [System.IO.Path]::Combine($currentPath, $segments[$index])
        $item = Get-Item -LiteralPath $currentPath -Force -ErrorAction SilentlyContinue
        if ($null -eq $item) {
            if ($AllowMissingLeaf -and $index -eq $segments.Count - 1) { return $currentPath }
            throw "Required evidence path does not exist: $RelativePath"
        }
        if (($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -or
            ($item.Attributes -band [System.IO.FileAttributes]::Device)) {
            throw "Evidence paths must not contain filesystem aliases or devices: $RelativePath"
        }
        if ($index -lt $segments.Count - 1 -and $item -isnot [System.IO.DirectoryInfo]) {
            throw "An evidence path ancestor is not a directory: $RelativePath"
        }
    }
    return [System.IO.Path]::GetFullPath($currentPath)
}

function Get-SwiftUIStateObjectFileHash {
    param([Parameter(Mandatory)][string]$Path, [long]$MaxBytes = 1073741824)
    if ($MaxBytes -lt 0 -or $MaxBytes -gt 2147483647) { throw 'File hash limit must be between zero and 2147483647 bytes.' }
    $file = Assert-SwiftUIStateObjectRegularFile -Path $Path
    if ($file.Length -gt $MaxBytes) { throw "File exceeds the $MaxBytes byte limit: $Path" }
    $stream = [System.IO.File]::Open($file.FullName, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::Read)
    $algorithm = [System.Security.Cryptography.SHA256]::Create()
    $countedBytes = [long]0
    try {
        $buffer = [byte[]]::new(65536)
        while (($count = $stream.Read($buffer, 0, $buffer.Length)) -gt 0) {
            $countedBytes += $count
            if ($countedBytes -gt $MaxBytes) { throw "File exceeds the $MaxBytes byte limit: $Path" }
            [void]$algorithm.TransformBlock($buffer, 0, $count, $buffer, 0)
        }
        [void]$algorithm.TransformFinalBlock([byte[]]::new(0), 0, 0)
        if ($countedBytes -ne $file.Length) { throw "File size changed during hashing: $Path" }
        $sha256 = [System.BitConverter]::ToString($algorithm.Hash).Replace('-', '').ToLowerInvariant()
    } finally { $stream.Dispose(); $algorithm.Dispose() }
    return [pscustomobject][ordered]@{ path = $file.FullName; sha256 = $sha256; bytes = $countedBytes }
}

function Read-SwiftUIStateObjectBoundedBytes {
    param([Parameter(Mandatory)][string]$Path, [long]$MaxBytes)
    if ($MaxBytes -lt 0 -or $MaxBytes -gt 16777216) { throw 'Buffered evidence limit must be between zero and 16 MiB.' }
    $file = Assert-SwiftUIStateObjectRegularFile -Path $Path
    if ($file.Length -gt $MaxBytes) { throw "Evidence exceeds the $MaxBytes byte limit: $Path" }
    $stream = [System.IO.File]::Open($file.FullName, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::Read)
    $memory = [System.IO.MemoryStream]::new()
    try {
        $buffer = [byte[]]::new(8192)
        while (($count = $stream.Read($buffer, 0, $buffer.Length)) -gt 0) {
            if ($memory.Length + $count -gt $MaxBytes) { throw "Evidence exceeds the $MaxBytes byte limit: $Path" }
            $memory.Write($buffer, 0, $count)
        }
        $rawBytes = $memory.ToArray()
        if ($rawBytes.Length -ne $file.Length) { throw "Evidence size changed during reading: $Path" }
    } finally { $stream.Dispose(); $memory.Dispose() }
    return [pscustomobject]@{ path = $file.FullName; rawBytes = $rawBytes; bytes = [long]$rawBytes.Length; sha256 = (Get-SwiftUIStateObjectBytesSHA256 -Bytes $rawBytes) }
}

function ConvertFrom-SwiftUIStateObjectJsonElement {
    param([Parameter(Mandatory)]$Element, [Parameter(Mandatory)][ref]$RemainingNodes)
    $RemainingNodes.Value = [int]$RemainingNodes.Value - 1
    if ($RemainingNodes.Value -lt 0) { throw 'JSON exceeds its converted-node limit.' }
    switch ($Element.ValueKind.ToString()) {
        'Object' {
            $names = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
            $properties = [ordered]@{}
            foreach ($property in $Element.EnumerateObject()) {
                if (-not $names.Add($property.Name)) { throw "Duplicate or case-colliding JSON property: $($property.Name)" }
                $properties.Add($property.Name, (ConvertFrom-SwiftUIStateObjectJsonElement -Element $property.Value -RemainingNodes $RemainingNodes))
            }
            return [pscustomobject]$properties
        }
        'Array' {
            $items = [System.Collections.Generic.List[object]]::new()
            foreach ($item in $Element.EnumerateArray()) { $items.Add((ConvertFrom-SwiftUIStateObjectJsonElement -Element $item -RemainingNodes $RemainingNodes)) }
            return ,$items.ToArray()
        }
        'String' { return $Element.GetString() }
        'Number' {
            $integer = [long]0
            if ($Element.TryGetInt64([ref]$integer)) { return $integer }
            $number = $Element.GetDouble()
            if ([double]::IsNaN($number) -or [double]::IsInfinity($number)) { throw 'JSON numbers must be finite.' }
            return $number
        }
        'True' { return $true }
        'False' { return $false }
        'Null' { return $null }
        default { throw 'Unsupported JSON token.' }
    }
}

function Read-SwiftUIStateObjectJson {
    param(
        [Parameter(Mandatory)][string]$Path,
        [long]$MaxBytes = 1048576,
        [int]$MaxDepth = 32,
        [int]$MaxNodes = 200000,
        [switch]$IncludeText
    )
    if ($PSVersionTable.PSVersion.Major -lt 7) { throw 'Strict StateObject JSON validation requires PowerShell 7 or newer; PowerShell 5.1 JSON parsing is unsupported.' }
    if ($MaxBytes -lt 1 -or $MaxBytes -gt 16777216 -or $MaxDepth -lt 1 -or $MaxDepth -gt 64 -or $MaxNodes -lt 1 -or $MaxNodes -gt 200000) {
        throw 'JSON limits must be positive, at most 16 MiB, at most 64 levels, and at most 200000 converted nodes.'
    }
    $record = Read-SwiftUIStateObjectBoundedBytes -Path $Path -MaxBytes $MaxBytes
    $utf8 = [System.Text.UTF8Encoding]::new($false, $true)
    $text = $utf8.GetString($record.rawBytes)
    if ($text.Length -eq 0 -or $text[0] -eq [char]0xfeff -or $text -match '\r(?!\n)') {
        throw 'JSON must use UTF-8 without a BOM and LF or CRLF line endings.'
    }
    $options = [System.Text.Json.JsonDocumentOptions]::new()
    $options.AllowTrailingCommas = $false
    $options.CommentHandling = [System.Text.Json.JsonCommentHandling]::Disallow
    $options.MaxDepth = $MaxDepth
    $json = [System.Text.Json.JsonDocument]::Parse([string]$text, $options)
    try {
        if ($json.RootElement.ValueKind -ne [System.Text.Json.JsonValueKind]::Object) { throw 'JSON root must be an object.' }
        $remainingNodes = $MaxNodes
        $document = ConvertFrom-SwiftUIStateObjectJsonElement -Element $json.RootElement -RemainingNodes ([ref]$remainingNodes)
    } finally { $json.Dispose() }
    $normalized = $text.Replace(([string][char]13 + [char]10), [string][char]10)
    $result = [ordered]@{
        document = $document
        sha256 = $record.sha256
        contentSha256 = (Get-SwiftUIStateObjectBytesSHA256 -Bytes $utf8.GetBytes($normalized))
        bytes = $record.bytes
    }
    if ($IncludeText) { $result.Add('text', $text) }
    return [pscustomobject]$result
}

function Assert-SwiftUIStateObjectFields {
    param($Value, [string]$Name, [string[]]$Required)
    if ($Value -isnot [pscustomobject]) { throw "$Name must be an object." }
    $actual = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
    $allowed = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
    foreach ($field in $Required) { [void]$allowed.Add($field) }
    foreach ($property in $Value.PSObject.Properties) {
        if (-not $allowed.Contains($property.Name)) { throw "$Name contains an unknown or incorrectly cased field: $($property.Name)" }
        [void]$actual.Add($property.Name)
    }
    foreach ($field in $Required) { if (-not $actual.Contains($field)) { throw "$Name is missing $field." } }
}

function Assert-SwiftUIStateObjectString {
    param($Value, [string]$Name, [int]$MaxLength = 4096, [switch]$AllowEmpty)
    if ($Value -isnot [string] -or $Value.Length -gt $MaxLength -or (-not $AllowEmpty -and [string]::IsNullOrWhiteSpace($Value))) {
        throw "$Name must be a bounded string."
    }
}

function Assert-SwiftUIStateObjectInteger {
    param($Value, [string]$Name, [long]$Minimum = 0, [long]$Maximum = [long]::MaxValue)
    if (($Value -isnot [int] -and $Value -isnot [long]) -or $Value -lt $Minimum -or $Value -gt $Maximum) { throw "$Name must be an integer within its bounds." }
}

function Assert-SwiftUIStateObjectBoolean {
    param($Value, [string]$Name)
    if ($Value -isnot [bool]) { throw "$Name must be a Boolean." }
}

function Assert-SwiftUIStateObjectHash {
    param($Value, [string]$Name)
    if ($Value -isnot [string] -or $Value -cnotmatch '\A[0-9a-f]{64}\z') { throw "$Name must be a lowercase SHA256 string." }
}

function Assert-SwiftUIStateObjectArray {
    param($Value, [string]$Name, [int]$MaximumCount = 4096)
    if ($Value -isnot [System.Array] -or $Value.Count -gt $MaximumCount) { throw "$Name must be a bounded array." }
}

function Test-SwiftUIStateObjectEqual {
    param($Left, $Right)
    if ($null -eq $Left -or $null -eq $Right) { return $null -eq $Left -and $null -eq $Right }
    if ($Left -is [System.Array] -or $Right -is [System.Array]) {
        if ($Left -isnot [System.Array] -or $Right -isnot [System.Array] -or $Left.Count -ne $Right.Count) { return $false }
        for ($index = 0; $index -lt $Left.Count; $index++) {
            if (-not (Test-SwiftUIStateObjectEqual -Left $Left[$index] -Right $Right[$index])) { return $false }
        }
        return $true
    }
    if ($Left -is [pscustomobject] -or $Right -is [pscustomobject]) {
        if ($Left -isnot [pscustomobject] -or $Right -isnot [pscustomobject]) { return $false }
        $leftProperties = @($Left.PSObject.Properties)
        $rightProperties = @($Right.PSObject.Properties)
        if ($leftProperties.Count -ne $rightProperties.Count) { return $false }
        foreach ($property in $leftProperties) {
            $rightProperty = @($rightProperties | Where-Object { $_.Name -ceq $property.Name })
            if ($rightProperty.Count -ne 1 -or -not (Test-SwiftUIStateObjectEqual -Left $property.Value -Right $rightProperty[0].Value)) { return $false }
        }
        return $true
    }
    if ($Left -is [bool] -or $Right -is [bool]) { return $Left -is [bool] -and $Right -is [bool] -and $Left -eq $Right }
    if ($Left -is [string] -or $Right -is [string]) { return $Left -is [string] -and $Right -is [string] -and $Left -ceq $Right }
    $leftInteger = $Left -is [int] -or $Left -is [long]
    $rightInteger = $Right -is [int] -or $Right -is [long]
    if ($leftInteger -or $rightInteger) { return $leftInteger -and $rightInteger -and $Left -eq $Right }
    return $Left.GetType() -eq $Right.GetType() -and $Left -eq $Right
}

function New-SwiftUIStateObjectCasePolicy {
    param(
        [string]$Name,
        [int]$Family,
        [string]$Role = 'admission-control',
        [AllowEmptyCollection()][string[]]$Shared = @('00-pure-model'),
        [AllowEmptyCollection()][string[]]$Controls = @(),
        [AllowEmptyCollection()][string[]]$Observations = @(),
        [AllowEmptyCollection()][string[]]$Attribution = @(),
        [AllowNull()]$Diagnostic = $null
    )
    $expected = 'admit'
    if ($Role -ceq 'source-observation-or-confound') { $expected = 'confound' }
    elseif ($Role -cne 'admission-control') { $expected = 'reject' }
    $desiredSafety = $null
    if ($Role -ceq 'unsafe-wrapper-characterization') { $desiredSafety = 'reject' }
    return [pscustomobject][ordered]@{
        caseID = "paired-public:$Name"; family = $Family; source = "paired-public/$Name.swift"
        sharedSources = @($Shared | ForEach-Object { "paired-public/$_.swift" })
        originalExpected = $expected; role = $Role; desiredSafetyOutcome = $desiredSafety
        requiredPriorControls = @($Controls | ForEach-Object { "paired-public:$_" })
        requiredPriorObservationCases = @($Observations | ForEach-Object { "paired-public:$_" })
        requiresForWrapperSpecificAdmission = @($Attribution | ForEach-Object { "paired-public:$_" })
        diagnosticExpectation = $Diagnostic
    }
}

function Get-SwiftUIStateObjectCasePolicies {
    # This is a fixed reviewed operation policy, not executable patterns supplied
    # by JSON. Matrix data must match it exactly before it can drive a request.
    New-SwiftUIStateObjectCasePolicy -Name '01-direct' -Family 1
    New-SwiftUIStateObjectCasePolicy -Name '02-generic-forwarding' -Family 2 -Shared @()
    New-SwiftUIStateObjectCasePolicy -Name '03-explicit-initializer' -Family 3 -Controls @('01-direct')
    New-SwiftUIStateObjectCasePolicy -Name '04-synthesized-mainactor-control' -Family 4 -Controls @('01-direct')
    New-SwiftUIStateObjectCasePolicy -Name '05-sendable-control' -Family 5 -Controls @('01-direct')
    New-SwiftUIStateObjectCasePolicy -Name '05-actor-transfer' -Family 5 -Controls @('01-direct', '05-sendable-control')
    New-SwiftUIStateObjectCasePolicy -Name '06-mainactor-access' -Family 6 -Controls @('01-direct')
    New-SwiftUIStateObjectCasePolicy -Name '06-mainactor-factory-control' -Family 6 -Controls @('01-direct')
    New-SwiftUIStateObjectCasePolicy -Name '08-capture-transfer-task-control' -Family 8 -Shared @('00-pure-model', '00-mutable-counter') -Controls @('01-direct', '05-sendable-control')
    New-SwiftUIStateObjectCasePolicy -Name '08-capture-transfer-actor-control' -Family 8 -Shared @('00-pure-model', '00-mutable-counter') -Controls @('01-direct', '05-sendable-control')
    New-SwiftUIStateObjectCasePolicy -Name '08-direct-capture-checker-control' -Family 8 -Shared @('00-mutable-counter') -Role 'intended-diagnostic-control' -Diagnostic ([pscustomobject]@{
        family = 'direct-capture-transfer'; subject = 'ProbeMutableCounter'; anchors = @(
            [pscustomobject]@{ line = 13; operation = 'task-transfer' },
            [pscustomobject]@{ line = 14; operation = 'captured-access' },
            [pscustomobject]@{ line = 16; operation = 'alias-reuse' })
    })
    New-SwiftUIStateObjectCasePolicy -Name '06-reject-wrapped-access' -Family 6 -Role 'intended-diagnostic-control' -Controls @('06-mainactor-access') -Diagnostic ([pscustomobject]@{
        family = 'mainactor-property-access'; subject = 'wrappedValue'; anchors = @([pscustomobject]@{ line = 10; operation = 'wrapped-access' })
    })
    New-SwiftUIStateObjectCasePolicy -Name '06-reject-projected-access' -Family 6 -Role 'intended-diagnostic-control' -Controls @('06-mainactor-access') -Diagnostic ([pscustomobject]@{
        family = 'mainactor-property-access'; subject = 'projectedValue'; anchors = @([pscustomobject]@{ line = 10; operation = 'projected-access' })
    })
    New-SwiftUIStateObjectCasePolicy -Name '06-reject-mainactor-factory' -Family 6 -Role 'intended-diagnostic-control' -Controls @('01-direct', '06-mainactor-factory-control') -Diagnostic ([pscustomobject]@{
        family = 'mainactor-factory-call'; subject = 'makeActorOnlyModel'; anchors = @([pscustomobject]@{ line = 15; operation = 'helper-call' })
    })
    New-SwiftUIStateObjectCasePolicy -Name '04-synthesized-initializer' -Family 4 -Role 'source-observation-or-confound' -Controls @('04-synthesized-mainactor-control')
    New-SwiftUIStateObjectCasePolicy -Name '04-synthesized-app' -Family 4 -Role 'source-observation-or-confound' -Controls @('04-synthesized-mainactor-control')
    New-SwiftUIStateObjectCasePolicy -Name '04-synthesized-scene' -Family 4 -Role 'source-observation-or-confound' -Controls @('04-synthesized-mainactor-control')
    New-SwiftUIStateObjectCasePolicy -Name '07-observable-protocol-control' -Family 7 -Role 'source-observation-or-confound' -Shared @('07-ordinary-model')
    New-SwiftUIStateObjectCasePolicy -Name '07-observable-protocol-confound' -Family 7 -Role 'source-observation-or-confound' -Shared @('07-ordinary-model') -Observations @('07-observable-protocol-control')
    New-SwiftUIStateObjectCasePolicy -Name '08-capture-transfer' -Family 8 -Role 'unsafe-wrapper-characterization' -Shared @('00-pure-model', '00-mutable-counter') -Controls @('01-direct', '02-generic-forwarding', '05-sendable-control', '08-capture-transfer-task-control') -Attribution @('08-direct-capture-checker-control') -Diagnostic ([pscustomobject]@{
        family = 'mutable-capture-transfer'; subject = 'ProbeMutableCounter'; anchors = @(
            [pscustomobject]@{ line = 14; operation = 'deferred-expression' },
            [pscustomobject]@{ line = 15; operation = 'task-transfer' },
            [pscustomobject]@{ line = 16; operation = 'wrapped-access' },
            [pscustomobject]@{ line = 20; operation = 'alias-reuse' })
    })
    New-SwiftUIStateObjectCasePolicy -Name '08-capture-transfer-actor' -Family 8 -Role 'unsafe-wrapper-characterization' -Shared @('00-pure-model', '00-mutable-counter') -Controls @('01-direct', '02-generic-forwarding', '05-sendable-control', '08-capture-transfer-actor-control') -Attribution @('08-direct-capture-checker-control') -Diagnostic ([pscustomobject]@{
        family = 'mutable-capture-transfer'; subject = 'ProbeMutableCounter'; anchors = @(
            [pscustomobject]@{ line = 13; operation = 'deferred-expression' },
            [pscustomobject]@{ line = 14; operation = 'task-transfer' },
            [pscustomobject]@{ line = 15; operation = 'wrapped-access' },
            [pscustomobject]@{ line = 19; operation = 'alias-reuse' })
    })
}

function Get-SwiftUIStateObjectCasePolicy {
    param([Parameter(Mandatory)][string]$CaseID)
    foreach ($policy in @(Get-SwiftUIStateObjectCasePolicies)) {
        if ($policy.caseID -ceq $CaseID) { return $policy }
    }
    throw "Unknown StateObject case ID: $CaseID"
}

function Assert-SwiftUIStateObjectCase {
    param($Case)
    Assert-SwiftUIStateObjectFields -Value $Case -Name 'case' -Required @(
        'caseID', 'family', 'source', 'sharedSources', 'originalExpected', 'role', 'desiredSafetyOutcome',
        'requiredPriorControls', 'requiredPriorObservationCases', 'requiresForWrapperSpecificAdmission', 'diagnosticExpectation')
    Assert-SwiftUIStateObjectString -Value $Case.caseID -Name 'case.caseID' -MaxLength 128
    $policy = Get-SwiftUIStateObjectCasePolicy -CaseID $Case.caseID
    if (-not (Test-SwiftUIStateObjectEqual -Left $Case -Right $policy)) { throw "Case metadata differs from the reviewed operation policy: $($Case.caseID)" }
}

function Get-SwiftUIStateObjectSourcePolicy {
    $rows = @(
        @('00-mutable-counter', 'dfb47b609eff7e8bb8c4f45d534292b5507b13fc0858f6fe13ea74e4d801dc51'),
        @('00-pure-model', 'a3e819335e849a87260331f847ef8702879484d6b35b80d0bf9745e838c03f73'),
        @('01-direct', '97f36daa68e9806af0fea4235c8de288e782a01edcb3d4f66da62fbd2c41434e'),
        @('02-generic-forwarding', '334bff15ac31c86741b67f58a71146997dd2a1ccadab7ccd1f54d7997f9abca6'),
        @('03-explicit-initializer', 'd5c25002660d2b6ee8e98d317121b34662894059dd1ea4fee6a02a4f8e86ffd9'),
        @('04-synthesized-app', 'f4c93db76b7aee12fc9c81b6c09e45d514bf8fc9c92a3bb3101c4f42d58d9520'),
        @('04-synthesized-initializer', '12566ced67f54bcc965d98180489933023300f335ac8bdf5ae6da2066f2c9622'),
        @('04-synthesized-mainactor-control', '3bc93600b166f7b5096e40ba12bf117295fa82fe1fc9263062c72c52953dc528'),
        @('04-synthesized-scene', '82170e33111d68f2930091319e2d29babf8017f5356c36e276c9f2b4c4e81156'),
        @('05-actor-transfer', '4d29e2aa064ef35be94e424c570cbfef39a4c056b82a29331b7e03de3d267989'),
        @('05-sendable-control', '4f27aa2ea5fb7fb263b25810b771ff421ebc22a8dd7719a227202051ad551a49'),
        @('06-mainactor-access', '12ad6730536086e98d55954e142b187cfb9e4f562c4bab7c09afd21b65b3cc38'),
        @('06-mainactor-factory-control', '38361a55c106682cb83e527c9db2a52cedbfe13c82b34520dcd683a9909622c2'),
        @('06-reject-mainactor-factory', '8e326ab9be9ef5a5481a1581078e8e6055fa832fd96a7ebeb3747168aa6a441a'),
        @('06-reject-projected-access', '41401291ae3ffd47d719b274c1114397b6e08ec1c21c063ac6401950b9ea4766'),
        @('06-reject-wrapped-access', 'cbcedd66fe06e804aa1c3792112f935e315d9ef80b596f445e18039e93f913e5'),
        @('07-observable-protocol-confound', '4954fd5ef0cee5fe5be9ff19f54828cf2756b749d2135f14bbc07ebbacf7411d'),
        @('07-observable-protocol-control', '20bf476f966e6867d77a2ca3da7d1fc65a7cf198e5be88a9abeb0618141faa68'),
        @('07-ordinary-model', 'a11aeeb199204ad7c628e7da48edd97c7df2a8d83252d16c8712b9e25a2c99ac'),
        @('08-capture-transfer-actor-control', '47f6ef09e21f69476a25a52629ae452280d8c25967d87abc0f252b05ffecf15f'),
        @('08-capture-transfer-actor', 'c1896633530bca60cec94b129581960823702d49779d016f1d77a84b19b99d75'),
        @('08-capture-transfer-task-control', 'ab768dd1310e92c5d2e2f654d9c35d608502adbf44c0374944b45d72b7c32400'),
        @('08-capture-transfer', 'a1a4c5d732c16f280c55daac54c9c3eda1ca8f061d42317c9026053eb041cd8a'),
        @('08-direct-capture-checker-control', '38791f2bac1513d1a8cdbf62c9455c92288f4d62589e534b0e0ce393a983802e')
    )
    foreach ($row in $rows) { [pscustomobject][ordered]@{ path = "paired-public/$($row[0]).swift"; sha256 = $row[1] } }
}

function Read-SwiftUIStateObjectMatrix {
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][string]$SourceRoot)
    $record = Read-SwiftUIStateObjectJson -Path $Path -MaxBytes 262144 -MaxDepth 16 -MaxNodes 10000
    $matrix = $record.document
    Assert-SwiftUIStateObjectFields -Value $matrix -Name 'matrix' -Required @(
        'schemaVersion', 'product', 'provenance', 'targets', 'requiredFlags', 'counts', 'sourceFiles', 'cases', 'limits', 'protocol', 'qualification')
    Assert-SwiftUIStateObjectInteger -Value $matrix.schemaVersion -Name 'matrix.schemaVersion' -Minimum 1 -Maximum 1
    if ($matrix.product -cne 'swiftui-stateobject-isolation') { throw 'The matrix product is not approved.' }
    $targets = @('x86_64-apple-macosx26.5', 'arm64-apple-macosx26.5')
    $flags = @('-swift-version', '6', '-strict-concurrency=complete', '-warnings-as-errors', '-default-isolation', 'nonisolated', '-parse-as-library', '-emit-sil', '-whole-module-optimization')
    if (-not (Test-SwiftUIStateObjectEqual -Left $matrix.targets -Right $targets) -or
        -not (Test-SwiftUIStateObjectEqual -Left $matrix.requiredFlags -Right $flags)) { throw 'The matrix targets or flags differ from the approved desktop requests.' }
    $counts = [pscustomobject]@{ families = 8; publicSourceFiles = 24; casesPerNativeTarget = 21; desktopTargets = 2; plannedNativeRequests = 42; futureSeparateWindowsPublicRequests = 21 }
    if (-not (Test-SwiftUIStateObjectEqual -Left $matrix.counts -Right $counts)) { throw 'The matrix coverage counts differ from the reviewed plan.' }
    Assert-SwiftUIStateObjectArray -Value $matrix.cases -Name 'matrix.cases' -MaximumCount 21
    $policies = @(Get-SwiftUIStateObjectCasePolicies)
    if ($matrix.cases.Count -ne 21) { throw 'Exactly 21 public cases are required.' }
    for ($index = 0; $index -lt 21; $index++) {
        Assert-SwiftUIStateObjectCase -Case $matrix.cases[$index]
        if ($matrix.cases[$index].caseID -cne $policies[$index].caseID) { throw 'Case order must preserve the reviewed prerequisite order.' }
    }
    if (-not (Test-SwiftUIStateObjectEqual -Left $matrix.sourceFiles -Right @(Get-SwiftUIStateObjectSourcePolicy))) { throw 'The source file inventory differs from the frozen 24 public files.' }
    $provenance = [pscustomobject]@{
        originalFixtureManifestSHA256 = '0b545ca4fb02507d02c5c11abceff23b981d3f00e52813d178deb9c35f27541e'
        originalSourcePackageSHA256 = 'fd60c674d9542fe88f7cd20af2d942d2527d4ac5a785e5b2242e9bafbe9c6c8d'
        approvedMatrixPlanSHA256 = '5becb88dac5db061d0db33da8973367d60dbbb15ef36605b9a3ebd9c9963a51e'
    }
    if (-not (Test-SwiftUIStateObjectEqual -Left $matrix.provenance -Right $provenance)) { throw 'Matrix provenance differs from the reviewed source package and plan.' }
    $limits = [pscustomobject]@{
        perRequestSeconds = 120; maxCombinedRawOutputBytes = 1048576; maxArchivedSILBytesPerCase = 8388608
        maxMatrixSeconds = 1800; mustBeReviewedAndFrozenBeforeExecution = $true; automaticLimitIncreaseAllowed = $false
    }
    if (-not (Test-SwiftUIStateObjectEqual -Left $matrix.limits -Right $limits)) { throw 'Matrix limits differ from the approved bounds.' }
    $protocol = [pscustomobject]@{
        characterizeNativeAdmitAndRejectSeparatelyFromDesiredSafety = $true; continueAcrossOrdinarySourceOutcomes = $true
        stopOnToolOrProvenanceFailure = $true; failedControlInvalidatesDependentQualification = $true
        preserveAllUnrunCells = $true; linkOrExecuteAllowed = $false; noCaseLaunchWithoutApprovedCompilerProfile = $true
        existingFrozen67UnrunCellsMustRemainUnchanged = $true
        dependencyKeyFields = @('attemptID', 'target', 'compilerProfileSHA256', 'caseID')
        crossTargetProfileOrAttemptDependencyReuseAllowed = $false
        qualifiedNegativeRequiresNormalCompilerRejectionAndIntendedPrimaryError = $true
        notesOnlyOrMixedUnrelatedPrimaryErrorsCanQualify = $false
    }
    if (-not (Test-SwiftUIStateObjectEqual -Left $matrix.protocol -Right $protocol)) { throw 'Matrix protocol differs from the approved evidence rules.' }
    $qualification = [pscustomobject]@{ nativeSourceBehaviorObserved = $false; runtimeEvidence = $false; parityClaimed = $false; productionApprovalChanged = $false }
    if (-not (Test-SwiftUIStateObjectEqual -Left $matrix.qualification -Right $qualification)) { throw 'Source-only matrix qualification flags must remain false.' }
    # Normalize only checkout line endings, never other whitespace or JSON data.
    if ($record.contentSha256 -cne '7608f38966424c4f9ca8628836a11aea3388ede5d7b9858c6e99f42474cd887b') { throw 'The matrix content hash differs from the reviewed canonical file.' }
    $mappedSources = [System.Collections.Generic.List[object]]::new()
    foreach ($source in $matrix.sourceFiles) {
        $sourcePath = Resolve-SwiftUIStateObjectEvidencePath -Root $SourceRoot -RelativePath $source.path
        $sourceHash = Get-SwiftUIStateObjectFileHash -Path $sourcePath -MaxBytes 65536
        if ($sourceHash.sha256 -cne $source.sha256) { throw "A frozen Swift source changed: $($source.path)" }
        $mappedSources.Add([pscustomobject][ordered]@{ path = $sourceHash.path; relativePath = $source.path; sha256 = $sourceHash.sha256; bytes = $sourceHash.bytes })
    }
    $cells = [System.Collections.Generic.List[object]]::new()
    foreach ($target in $targets) {
        foreach ($case in $matrix.cases) {
            $cells.Add([pscustomobject][ordered]@{ sequence = $cells.Count + 1; caseID = $case.caseID; target = $target })
        }
    }
    return [pscustomobject][ordered]@{
        document = $matrix; sha256 = $record.sha256; contentSha256 = $record.contentSha256
        cases = $matrix.cases; targets = $targets; cells = $cells.ToArray(); sourceFiles = $mappedSources.ToArray()
    }
}

function Get-SwiftUIStateObjectSourceLineLengths {
    param([string]$RelativePath)
    # UTF-8 byte lengths for the exact 24 SHA-pinned source files, including a
    # final empty line. This lets the pure classifier reject stale position flags.
    $lengths = @{
        'paired-public/00-mutable-counter.swift' = @(22,18,5,21,6,0,82,75,33,17,0,27,18,20,5,1,0)
        'paired-public/00-pure-model.swift' = @(22,18,5,21,6,0,82,10,48,24,0,40,24,5,1,0)
        'paired-public/01-direct.swift' = @(22,18,5,21,6,0,70,58,52,49,1,0)
        'paired-public/02-generic-forwarding.swift' = @(22,18,5,21,6,0,56,75,51,34,26,37,1,0)
        'paired-public/03-explicit-initializer.swift' = @(22,18,5,21,6,0,65,10,39,45,0,33,65,5,0,25,32,5,1,0,68,40,1,0)
        'paired-public/04-synthesized-app.swift' = @(22,18,5,21,6,0,79,72,10,39,55,0,26,58,36,9,5,1,0,61,31,1,0)
        'paired-public/04-synthesized-initializer.swift' = @(22,18,5,21,6,0,87,69,10,42,55,0,25,32,5,1,0,65,33,1,0)
        'paired-public/04-synthesized-mainactor-control.swift' = @(22,18,5,21,6,0,72,42,10,42,55,0,25,32,5,1,0,10,65,33,1,0)
        'paired-public/04-synthesized-scene.swift' = @(22,18,5,21,6,0,78,68,10,43,55,0,26,60,36,9,5,1,0,65,33,1,0)
        'paired-public/05-actor-transfer.swift' = @(22,18,5,21,6,0,77,72,27,59,56,5,1,0,10,75,53,36,1,0)
        'paired-public/05-sendable-control.swift' = @(22,18,5,21,6,0,57,74,63,0,67,27,1,0)
        'paired-public/06-mainactor-access.swift' = @(22,18,5,21,6,0,70,10,77,37,30,17,1,0)
        'paired-public/06-mainactor-factory-control.swift' = @(22,18,5,21,6,0,65,10,48,22,1,0,10,64,51,1,0)
        'paired-public/06-reject-mainactor-factory.swift' = @(22,18,5,21,6,0,72,61,10,48,22,1,0,57,51,1,0)
        'paired-public/06-reject-projected-access.swift' = @(22,18,5,21,6,0,72,61,63,30,1,0)
        'paired-public/06-reject-wrapped-access.swift' = @(22,18,5,21,6,0,70,78,74,24,1,0)
        'paired-public/07-observable-protocol-confound.swift' = @(22,18,5,21,6,0,74,75,68,58,1,0)
        'paired-public/07-observable-protocol-control.swift' = @(22,18,5,21,6,0,75,65,56,31,1,0)
        'paired-public/07-ordinary-model.swift' = @(22,18,5,21,6,0,73,77,57,25,0,28,25,5,1,0)
        'paired-public/08-capture-transfer-actor-control.swift' = @(22,18,5,21,6,0,65,60,34,47,0,48,27,34,70,51,36,9,27,21,5,1,0)
        'paired-public/08-capture-transfer-actor.swift' = @(22,18,5,21,6,0,63,27,47,0,48,27,81,51,36,9,82,81,27,21,5,1,0)
        'paired-public/08-capture-transfer-task-control.swift' = @(22,18,5,21,6,0,64,64,56,19,43,27,34,70,51,36,9,29,18,5,1,0)
        'paired-public/08-capture-transfer.swift' = @(22,18,5,21,6,0,60,83,74,49,19,43,27,81,51,36,9,78,75,29,18,5,1,0)
        'paired-public/08-direct-capture-checker-control.swift' = @(22,18,5,21,6,0,77,78,58,19,43,27,49,31,9,29,18,5,1,0)
    }
    if ($RelativePath -cnotin @($lengths.Keys)) { throw 'No frozen source position policy exists for this path.' }
    return ,$lengths[$RelativePath]
}

function Test-SwiftUIStateObjectSourcePosition {
    param([string]$RelativePath, [long]$Line, [long]$Column)
    $lengths = Get-SwiftUIStateObjectSourceLineLengths -RelativePath $RelativePath
    return $Line -ge 1 -and $Line -le $lengths.Count -and $Column -ge 1 -and $Column -le ($lengths[[int]$Line - 1] + 1)
}

function New-SwiftUIStateObjectEmptyDiagnostics {
    param([AllowEmptyCollection()][string[]]$Issues = @())
    return [pscustomobject][ordered]@{
        schemaVersion = 1; stderr = $null; headers = @(); unrecognizedPrimaryLines = @()
        hasConfigurationFailure = $false; hasCrashMarker = $false; issues = @($Issues)
    }
}

function Test-SwiftUIStateObjectConfigurationMessage {
    param([string]$Message)
    # These identify invocation/import failures, not an expected source rejection.
    return [regex]::IsMatch($Message,
        '\A(?:unknown argument:|unknown option:|unsupported (?:option|argument|target)|unknown target|unable to load standard library|no such module |missing required module |failed to build module |could not build (?:module|Objective-C module)|could not find module |cannot load module |unable to find (?:SDK|sdk)|SDK .+ (?:not found|does not exist)|error opening input file |module .+ was created for incompatible target|compilation for target .+ is not supported|unable to execute command:)',
        [System.Text.RegularExpressions.RegexOptions]::IgnoreCase -bor [System.Text.RegularExpressions.RegexOptions]::CultureInvariant)
}

function Test-SwiftUIStateObjectCrashMessage {
    param([string]$Message)
    return [regex]::IsMatch($Message,
        '\A(?:Stack dump:|PLEASE submit a bug report|Please submit a bug report|Assertion failed:|LLVM ERROR:|(?:error: )?(?:compile|emit-module) command failed due to signal|swift-frontend.*(?:crashed|segmentation fault))',
        [System.Text.RegularExpressions.RegexOptions]::CultureInvariant)
}

function Get-SwiftUIStateObjectUnlocatedDiagnostic {
    param([string]$Text)
    $match = [regex]::Match($Text, '\A(?<severity>fatal error|error|warning|note):[ \t]*(?<message>.*)\z')
    if (-not $match.Success) {
        $match = [regex]::Match($Text, '\A\S.*?:[ \t]*(?<severity>fatal error|error|warning|note):[ \t]*(?<message>.*)\z')
    }
    return $match
}

function Get-SwiftUIStateObjectDiagnosticOperation {
    param($Case, [AllowNull()]$RelativePath, [long]$Line, [bool]$SourcePositionValid)
    if (-not $SourcePositionValid -or $null -eq $Case.diagnosticExpectation -or $RelativePath -cne $Case.source) { return $null }
    foreach ($anchor in $Case.diagnosticExpectation.anchors) {
        if ($anchor.line -eq $Line) { return $anchor.operation }
    }
    return $null
}

function Test-SwiftUIStateObjectIntendedMessage {
    param($Case, [string]$Message, [AllowNull()]$Operation)
    if ($null -eq $Case.diagnosticExpectation -or $null -eq $Operation) { return $false }
    $family = $Case.diagnosticExpectation.family
    $subject = [regex]::Escape($Case.diagnosticExpectation.subject)
    if ($family -ceq 'mainactor-property-access') {
        $pattern = "\A(?i:main actor-isolated property) '$subject' (?i:can not|cannot) be (?i:referenced|accessed) from (?i:a |the )?nonisolated context[.]?\z"
        return [regex]::IsMatch($Message, $pattern, [System.Text.RegularExpressions.RegexOptions]::CultureInvariant)
    }
    if ($family -ceq 'mainactor-factory-call') {
        $pattern = "\A(?i:call to main actor-isolated (?:global )?function) '$subject\(\)' (?i:in a synchronous nonisolated context)[.]?\z"
        return [regex]::IsMatch($Message, $pattern, [System.Text.RegularExpressions.RegexOptions]::CultureInvariant)
    }
    if ($family -ceq 'mutable-capture-transfer' -or $family -ceq 'direct-capture-transfer') {
        # The known counter type or its actual alias names must be the subject.
        # Generic task/closure transfer wording and constructor/accessor isolation
        # are deliberately not treated as proof about this deferred capture.
        $typed = "\A(?i:sending value of non-Sendable type) '(?:[A-Za-z_][A-Za-z0-9_]*[.])*$subject' (?i:risks causing data races)[.]?\z"
        $named = "\A(?i:sending) '(?:alias|counter)' (?i:risks causing data races)[.]?\z"
        return [regex]::IsMatch($Message, $typed, [System.Text.RegularExpressions.RegexOptions]::CultureInvariant) -or
            [regex]::IsMatch($Message, $named, [System.Text.RegularExpressions.RegexOptions]::CultureInvariant)
    }
    return $false
}

function Get-SwiftUIStateObjectHeaderClassification {
    param($Case, $Header)
    if ($Header.severity -ceq 'note') { return 'note' }
    if ($Header.severity -ceq 'error' -and
        ((Test-SwiftUIStateObjectConfigurationMessage -Message $Header.message) -or
        ($null -eq $Header.relativePath -and $Header.rawPath -match '\.(?:swiftinterface|h|modulemap)\z'))) {
        return 'configuration-diagnostic'
    }
    if ($null -eq $Header.relativePath) { return 'foreign-diagnostic' }
    if (-not $Header.sourcePositionValid) { return 'invalid-source-position' }
    if ($Header.severity -ceq 'error' -and
        (Test-SwiftUIStateObjectIntendedMessage -Case $Case -Message $Header.message -Operation $Header.operation)) {
        return 'intended-diagnostic'
    }
    return 'unclassified-source-diagnostic'
}

function ConvertTo-SwiftUIStateObjectDiagnosticPath {
    param([AllowNull()]$Value)
    # Capture paths are names from the producing host, which can differ from the
    # archive-validation host. Do not resolve a POSIX name against a Windows cwd.
    if ($Value -isnot [string] -or $Value.Length -eq 0 -or $Value.Length -gt 4096 -or $Value -match '[\x00-\x1f\x7f]') { return $null }
    if ($Value.StartsWith('/') -and -not $Value.StartsWith('//') -and -not $Value.Contains('\')) {
        if ($Value.EndsWith('/') -or $Value -match '//|(?:\A|/)\.{1,2}(?:/|\z)') { return $null }
        return $Value
    }
    if ($Value -cmatch '\A[A-Za-z]:[\\/]') {
        $normalized = $Value.Replace('/', '\')
        if ($normalized.EndsWith('\') -or $normalized.Substring(3).Contains(':') -or
            $normalized.Substring(3).Contains('\\') -or $normalized -match '(?:\A|\\)\.{1,2}(?:\\|\z)') { return $null }
        return $normalized
    }
    return $null
}

function Get-SwiftUIStateObjectDiagnostics {
    param(
        [Parameter(Mandatory)][string]$StderrPath,
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Sources,
        [Parameter(Mandatory)]$Case,
        [System.Collections.IDictionary]$DiagnosticPaths
    )
    Assert-SwiftUIStateObjectCase -Case $Case
    $requiredPaths = @($Case.source) + @($Case.sharedSources)
    if ($Sources.Count -ne $requiredPaths.Count) { throw 'Diagnostic sources must be exactly this case and its declared shared files.' }
    $mappedSources = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::Ordinal)
    $relativeNames = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
    $actualNames = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
    if ($null -ne $DiagnosticPaths) {
        if ($DiagnosticPaths.Count -ne $requiredPaths.Count) { throw 'Diagnostic capture-path mapping must include exactly the case and shared sources.' }
        $captureNames = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
        foreach ($name in $DiagnosticPaths.Keys) {
            if ($name -isnot [string] -or $name -cnotin $requiredPaths -or -not $captureNames.Add($name) -or
                $null -eq (ConvertTo-SwiftUIStateObjectDiagnosticPath -Value $DiagnosticPaths[$name])) {
                throw 'Diagnostic capture-path mapping contains an unknown, duplicate, or noncanonical entry.'
            }
        }
    }
    $utf8 = [System.Text.UTF8Encoding]::new($false, $true)
    $sourcePolicy = @(Get-SwiftUIStateObjectSourcePolicy)
    foreach ($source in $Sources) {
        Assert-SwiftUIStateObjectFields -Value $source -Name 'diagnostic source' -Required @('path', 'relativePath', 'sha256', 'bytes')
        Assert-SwiftUIStateObjectString -Value $source.path -Name 'diagnostic source.path'
        if (-not [System.IO.Path]::IsPathRooted($source.path)) { throw 'Diagnostic source paths must be absolute.' }
        Assert-SwiftUIStateObjectRelativePath -Value $source.relativePath -Name 'diagnostic source.relativePath'
        if ($source.relativePath -cnotin $requiredPaths -or -not $relativeNames.Add($source.relativePath)) { throw 'Diagnostic source mapping is duplicated or outside this case.' }
        Assert-SwiftUIStateObjectHash -Value $source.sha256 -Name 'diagnostic source.sha256'
        Assert-SwiftUIStateObjectInteger -Value $source.bytes -Name 'diagnostic source.bytes' -Minimum 1 -Maximum 65536
        $expectedSource = @($sourcePolicy | Where-Object { $_.path -ceq $source.relativePath })
        if ($expectedSource.Count -ne 1 -or $expectedSource[0].sha256 -cne $source.sha256) { throw 'Diagnostic source hash is not one of the frozen public inputs.' }
        $sourceRecord = Read-SwiftUIStateObjectBoundedBytes -Path $source.path -MaxBytes 65536
        if ($sourceRecord.sha256 -cne $source.sha256 -or $sourceRecord.bytes -ne $source.bytes) { throw "A diagnostic source changed: $($source.relativePath)" }
        $sourceText = $utf8.GetString($sourceRecord.rawBytes)
        if ($sourceText.Length -eq 0 -or $sourceText[0] -eq [char]0xfeff -or $sourceText -match '\r(?!\n)') { throw 'Frozen diagnostic sources must be UTF-8 without BOM and use LF or CRLF.' }
        $sourceLines = [regex]::Split($sourceText, '\r\n|\n')
        $actualLengths = @($sourceLines | ForEach-Object { $utf8.GetByteCount($_) })
        if (-not (Test-SwiftUIStateObjectEqual -Left $actualLengths -Right (Get-SwiftUIStateObjectSourceLineLengths -RelativePath $source.relativePath))) {
            throw 'The source position policy does not match the frozen source bytes.'
        }
        if (-not $actualNames.Add($sourceRecord.path)) { throw 'Diagnostic sources resolve to the same actual file.' }
        $capturePath = $sourceRecord.path
        if ($null -ne $DiagnosticPaths) { $capturePath = $DiagnosticPaths[$source.relativePath] }
        $capturePath = ConvertTo-SwiftUIStateObjectDiagnosticPath -Value $capturePath
        if ($null -eq $capturePath -or $mappedSources.ContainsKey($capturePath)) { throw 'Diagnostic sources must have unique canonical capture paths.' }
        $mappedSources.Add($capturePath, [pscustomobject]@{ relativePath = $source.relativePath; lines = $sourceLines })
    }
    $record = Read-SwiftUIStateObjectBoundedBytes -Path $StderrPath -MaxBytes 1048576
    $text = $utf8.GetString($record.rawBytes)
    if (($text.Length -gt 0 -and $text[0] -eq [char]0xfeff) -or $text -match '\r(?!\n)' -or $text.Contains([string][char]0)) {
        throw 'Diagnostic text must be UTF-8 without BOM or NUL and use LF or CRLF.'
    }
    $headers = [System.Collections.Generic.List[object]]::new()
    $unrecognized = [System.Collections.Generic.List[object]]::new()
    $hasConfiguration = $false
    $hasCrash = $false
    $physicalLines = [regex]::Split($text, '\r\n|\n')
    $lineNumber = 0
    foreach ($physicalLine in $physicalLines) {
        $lineNumber++
        if ($physicalLine.Length -eq 0) { continue }
        # Never trim or strip an echo gutter. Message substrings are never parsed
        # again as headers. A whole unprefixed forged physical line cannot be
        # authenticated by text grammar alone; pinned source/tool provenance is
        # a separate requirement, and this parser makes no such authentication claim.
        if ($physicalLine -match '\A[ \t]*(?:[0-9]+[ \t]*\||\||\^|//|/\*|\*|\x60)') { continue }
        if (Test-SwiftUIStateObjectCrashMessage -Message $physicalLine) {
            $hasCrash = $true
            $unrecognized.Add([pscustomobject]@{ rawLineNumber = $lineNumber; text = $physicalLine })
            continue
        }
        $headerMatch = [regex]::Match($physicalLine, '\A(?<path>\S.*?):(?<line>[1-9][0-9]*):(?<column>[1-9][0-9]*):[ \t]*(?<severity>error|warning|note):[ \t]*(?<message>.*)\z')
        $driverMatch = Get-SwiftUIStateObjectUnlocatedDiagnostic -Text $physicalLine
        # A root/tool diagnostic may quote an entire located header. Its earlier
        # severity owns the message; matching that quoted suffix must not hide
        # an outer error or turn an explanatory note into a primary error.
        if ($headerMatch.Success -and (-not $driverMatch.Success -or
            $headerMatch.Groups['severity'].Index -le $driverMatch.Groups['severity'].Index)) {
            $sourceLine = [long]0
            $sourceColumn = [long]0
            if (-not [long]::TryParse($headerMatch.Groups['line'].Value, [ref]$sourceLine) -or
                -not [long]::TryParse($headerMatch.Groups['column'].Value, [ref]$sourceColumn) -or
                $sourceLine -gt [int]::MaxValue -or $sourceColumn -gt [int]::MaxValue) {
                $unrecognized.Add([pscustomobject]@{ rawLineNumber = $lineNumber; text = $physicalLine })
                continue
            }
            $rawPath = $headerMatch.Groups['path'].Value
            $message = $headerMatch.Groups['message'].Value
            $identifier = $null
            $identifierMatch = [regex]::Match($message, '[ \t]+\[(?<id>#[A-Za-z][A-Za-z0-9_-]*)\]\z')
            if ($identifierMatch.Success) {
                $identifier = $identifierMatch.Groups['id'].Value
                $message = $message.Substring(0, $identifierMatch.Index)
            }
            $canonicalPath = $null
            $relativePath = $null
            $validPosition = $false
            # Exact absolute mapping; no basename, case folding, path traversal,
            # suffix matching, whitespace removal, or filesystem alias lookup.
            $candidatePath = ConvertTo-SwiftUIStateObjectDiagnosticPath -Value $rawPath
            if ($null -ne $candidatePath -and $mappedSources.ContainsKey($candidatePath)) {
                $canonicalPath = $candidatePath
                $relativePath = $mappedSources[$candidatePath].relativePath
                $fileLines = $mappedSources[$candidatePath].lines
                if ($sourceLine -le $fileLines.Count) {
                    $maximumColumn = $utf8.GetByteCount($fileLines[[int]$sourceLine - 1]) + 1
                    $validPosition = $sourceColumn -le $maximumColumn
                }
            }
            $header = [pscustomobject][ordered]@{
                rawLineNumber = $lineNumber; rawPath = $rawPath; canonicalPath = $canonicalPath; relativePath = $relativePath
                line = $sourceLine; column = $sourceColumn; severity = $headerMatch.Groups['severity'].Value
                message = $message; identifier = $identifier; sourcePositionValid = $validPosition
                operation = (Get-SwiftUIStateObjectDiagnosticOperation -Case $Case -RelativePath $relativePath -Line $sourceLine -SourcePositionValid $validPosition)
                isPrimaryHeader = $headerMatch.Groups['severity'].Value -cne 'note'; classification = $null
            }
            $header.classification = Get-SwiftUIStateObjectHeaderClassification -Case $Case -Header $header
            if ($header.classification -ceq 'configuration-diagnostic') { $hasConfiguration = $true }
            if (Test-SwiftUIStateObjectCrashMessage -Message $message) { $hasCrash = $true }
            $headers.Add($header)
            continue
        }
        # The first root severity wins before an unknown/absolute tool prefix.
        if ($driverMatch.Success) {
            $driverCrash = Test-SwiftUIStateObjectCrashMessage -Message $driverMatch.Groups['message'].Value
            if ($driverMatch.Groups['severity'].Value -cne 'note' -or $driverCrash) {
                $unrecognized.Add([pscustomobject]@{ rawLineNumber = $lineNumber; text = $physicalLine })
            }
            if ($driverMatch.Groups['severity'].Value -cin @('error', 'fatal error') -and
                (Test-SwiftUIStateObjectConfigurationMessage -Message $driverMatch.Groups['message'].Value)) { $hasConfiguration = $true }
            if ($driverCrash) { $hasCrash = $true }
        } elseif ($physicalLine -match '\A\S.*?:[0-9]+:[0-9]+:[ \t]*(?:error|warning):') {
            # Header-shaped errors with zero/out-of-range positions stay visible
            # and unqualified; they do not disappear beside an intended error.
            $unrecognized.Add([pscustomobject]@{ rawLineNumber = $lineNumber; text = $physicalLine })
        }
    }
    return [pscustomobject][ordered]@{
        schemaVersion = 1
        stderr = [pscustomobject][ordered]@{ path = $record.path; sha256 = $record.sha256; bytes = $record.bytes }
        headers = $headers.ToArray(); unrecognizedPrimaryLines = $unrecognized.ToArray()
        hasConfigurationFailure = $hasConfiguration; hasCrashMarker = $hasCrash; issues = @()
    }
}

function Assert-SwiftUIStateObjectStringArray {
    param($Value, [string]$Name, [int]$MaximumCount = 64, [int]$MaximumStringLength = 4096, [switch]$Unique)
    Assert-SwiftUIStateObjectArray -Value $Value -Name $Name -MaximumCount $MaximumCount
    $seen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
    foreach ($item in $Value) {
        Assert-SwiftUIStateObjectString -Value $item -Name $Name -MaxLength $MaximumStringLength
        if ($Unique -and -not $seen.Add($item)) { throw "$Name contains a duplicate." }
    }
}

function Assert-SwiftUIStateObjectDiagnostics {
    param($Value, $Case)
    Assert-SwiftUIStateObjectFields -Value $Value -Name 'diagnostics' -Required @(
        'schemaVersion', 'stderr', 'headers', 'unrecognizedPrimaryLines', 'hasConfigurationFailure', 'hasCrashMarker', 'issues')
    Assert-SwiftUIStateObjectInteger -Value $Value.schemaVersion -Name 'diagnostics.schemaVersion' -Minimum 1 -Maximum 1
    foreach ($field in @('hasConfigurationFailure', 'hasCrashMarker')) { Assert-SwiftUIStateObjectBoolean -Value $Value.$field -Name "diagnostics.$field" }
    Assert-SwiftUIStateObjectStringArray -Value $Value.issues -Name 'diagnostics.issues'
    if ($null -ne $Value.stderr) {
        Assert-SwiftUIStateObjectFields -Value $Value.stderr -Name 'diagnostics.stderr' -Required @('path', 'sha256', 'bytes')
        Assert-SwiftUIStateObjectString -Value $Value.stderr.path -Name 'diagnostics.stderr.path'
        Assert-SwiftUIStateObjectHash -Value $Value.stderr.sha256 -Name 'diagnostics.stderr.sha256'
        Assert-SwiftUIStateObjectInteger -Value $Value.stderr.bytes -Name 'diagnostics.stderr.bytes' -Maximum 1048576
    }
    Assert-SwiftUIStateObjectArray -Value $Value.headers -Name 'diagnostics.headers' -MaximumCount 16384
    Assert-SwiftUIStateObjectArray -Value $Value.unrecognizedPrimaryLines -Name 'diagnostics.unrecognizedPrimaryLines' -MaximumCount 16384
    $previousLine = [long]0
    $allowedSources = @($Case.source) + @($Case.sharedSources)
    foreach ($header in $Value.headers) {
        Assert-SwiftUIStateObjectFields -Value $header -Name 'diagnostic header' -Required @(
            'rawLineNumber', 'rawPath', 'canonicalPath', 'relativePath', 'line', 'column', 'severity', 'message',
            'identifier', 'sourcePositionValid', 'operation', 'isPrimaryHeader', 'classification')
        Assert-SwiftUIStateObjectInteger -Value $header.rawLineNumber -Name 'header.rawLineNumber' -Minimum 1 -Maximum 1048577
        if ($header.rawLineNumber -le $previousLine) { throw 'Diagnostic headers must preserve physical-line order.' }
        $previousLine = $header.rawLineNumber
        Assert-SwiftUIStateObjectString -Value $header.rawPath -Name 'header.rawPath' -MaxLength 1048576
        foreach ($field in @('line', 'column')) { Assert-SwiftUIStateObjectInteger -Value $header.$field -Name "header.$field" -Minimum 1 -Maximum ([int]::MaxValue) }
        if ($header.severity -cnotin @('error', 'warning', 'note')) { throw 'Unknown diagnostic severity.' }
        Assert-SwiftUIStateObjectString -Value $header.message -Name 'header.message' -MaxLength 1048576 -AllowEmpty
        if ($null -ne $header.identifier -and ($header.identifier -isnot [string] -or $header.identifier -cnotmatch '\A#[A-Za-z][A-Za-z0-9_-]*\z')) { throw 'Invalid diagnostic identifier.' }
        foreach ($field in @('sourcePositionValid', 'isPrimaryHeader')) { Assert-SwiftUIStateObjectBoolean -Value $header.$field -Name "header.$field" }
        if ($header.isPrimaryHeader -ne ($header.severity -cne 'note')) { throw 'Diagnostic primary/note marker is inconsistent.' }
        if ($null -eq $header.relativePath) {
            if ($null -ne $header.canonicalPath -or $header.sourcePositionValid) { throw 'An unmapped diagnostic cannot have a validated source position.' }
        } else {
            if ($header.relativePath -cnotin $allowedSources) { throw 'A mapped diagnostic is outside the case sources.' }
            Assert-SwiftUIStateObjectString -Value $header.canonicalPath -Name 'header.canonicalPath'
            if ($null -eq (ConvertTo-SwiftUIStateObjectDiagnosticPath -Value $header.canonicalPath)) { throw 'A canonical diagnostic path must be absolute and preserve the capture-host syntax.' }
            if ((ConvertTo-SwiftUIStateObjectDiagnosticPath -Value $header.rawPath) -cne $header.canonicalPath) { throw 'Diagnostic raw and canonical capture paths disagree.' }
            $expectedPosition = Test-SwiftUIStateObjectSourcePosition -RelativePath $header.relativePath -Line $header.line -Column $header.column
            if ($header.sourcePositionValid -ne $expectedPosition) { throw 'Diagnostic source position flag disagrees with the frozen UTF8 source bounds.' }
        }
        $operation = Get-SwiftUIStateObjectDiagnosticOperation -Case $Case -RelativePath $header.relativePath -Line $header.line -SourcePositionValid $header.sourcePositionValid
        if (-not (Test-SwiftUIStateObjectEqual -Left $header.operation -Right $operation)) { throw 'Diagnostic operation does not match the reviewed source anchor.' }
        $classification = Get-SwiftUIStateObjectHeaderClassification -Case $Case -Header $header
        if ($classification -cne $header.classification) { throw 'Diagnostic classification disagrees with the reviewed semantic policy.' }
        if ($classification -ceq 'configuration-diagnostic' -and -not $Value.hasConfigurationFailure) { throw 'A configuration diagnostic cannot be hidden by an aggregate flag.' }
        if ((Test-SwiftUIStateObjectCrashMessage -Message $header.message) -and -not $Value.hasCrashMarker) { throw 'A retained crash message cannot be hidden by an aggregate flag.' }
    }
    foreach ($line in $Value.unrecognizedPrimaryLines) {
        Assert-SwiftUIStateObjectFields -Value $line -Name 'unrecognized primary line' -Required @('rawLineNumber', 'text')
        Assert-SwiftUIStateObjectInteger -Value $line.rawLineNumber -Name 'unrecognized rawLineNumber' -Minimum 1 -Maximum 1048577
        Assert-SwiftUIStateObjectString -Value $line.text -Name 'unrecognized text' -MaxLength 1048576
        if ((Test-SwiftUIStateObjectCrashMessage -Message $line.text) -and -not $Value.hasCrashMarker) {
            throw 'A retained standalone crash marker cannot be hidden.'
        }
        $driverMatch = Get-SwiftUIStateObjectUnlocatedDiagnostic -Text $line.text
        if ($driverMatch.Success) {
            $message = $driverMatch.Groups['message'].Value
            if ($driverMatch.Groups['severity'].Value -cin @('error', 'fatal error') -and
                (Test-SwiftUIStateObjectConfigurationMessage -Message $message) -and -not $Value.hasConfigurationFailure) { throw 'A retained driver configuration failure cannot be hidden.' }
            if ((Test-SwiftUIStateObjectCrashMessage -Message $message) -and -not $Value.hasCrashMarker) { throw 'A retained driver crash message cannot be hidden.' }
        }
    }
    if ($null -eq $Value.stderr -and ($Value.headers.Count -gt 0 -or $Value.unrecognizedPrimaryLines.Count -gt 0)) { throw 'Diagnostics without a stream cannot contain parsed headers.' }
}

function Get-SwiftUIStateObjectNativeHypothesis {
    param($Case)
    if ($Case.role -ceq 'admission-control') { return 'admit' }
    if ($Case.role -ceq 'intended-diagnostic-control') { return 'reject' }
    return 'unknown'
}

function Assert-SwiftUIStateObjectIdentity {
    param($AttemptID, $Target, $CompilerProfileSHA256)
    if ($AttemptID -isnot [string] -or $AttemptID -cnotmatch '\A[A-Za-z0-9][A-Za-z0-9._-]{0,127}\z') { throw 'attemptID must be a bounded explicit identifier.' }
    if ($Target -cnotin @('x86_64-apple-macosx26.5', 'arm64-apple-macosx26.5')) { throw 'The target is not part of the approved native desktop matrix.' }
    Assert-SwiftUIStateObjectHash -Value $CompilerProfileSHA256 -Name 'compilerProfileSHA256'
}

function Get-SwiftUIStateObjectDependencyPolicy {
    param($Case)
    foreach ($caseID in $Case.requiredPriorControls) { [pscustomobject]@{ caseID = $caseID; requirement = 'control' } }
    foreach ($caseID in $Case.requiredPriorObservationCases) { [pscustomobject]@{ caseID = $caseID; requirement = 'observation' } }
    foreach ($caseID in $Case.requiresForWrapperSpecificAdmission) { [pscustomobject]@{ caseID = $caseID; requirement = 'wrapper-specific-admission' } }
}

function Assert-SwiftUIStateObjectAssessment {
    param($Value)
    Assert-SwiftUIStateObjectFields -Value $Value -Name 'assessment' -Required @(
        'schemaVersion', 'attemptID', 'target', 'compilerProfileSHA256', 'caseID', 'role', 'observedOutcome',
        'diagnosticQualification', 'nativeHypothesis', 'desiredSafetyOutcome', 'safetyRequirementMet',
        'controlRequirementMet', 'prerequisites', 'reviewFlags', 'comparisonEligible',
        'runtimeEvidence', 'parityClaimed', 'productionApprovalChanged')
    Assert-SwiftUIStateObjectInteger -Value $Value.schemaVersion -Name 'assessment.schemaVersion' -Minimum 1 -Maximum 1
    Assert-SwiftUIStateObjectIdentity -AttemptID $Value.attemptID -Target $Value.target -CompilerProfileSHA256 $Value.compilerProfileSHA256
    Assert-SwiftUIStateObjectString -Value $Value.caseID -Name 'assessment.caseID' -MaxLength 128
    $case = Get-SwiftUIStateObjectCasePolicy -CaseID $Value.caseID
    if ($Value.role -cne $case.role -or $Value.nativeHypothesis -cne (Get-SwiftUIStateObjectNativeHypothesis -Case $case) -or
        -not (Test-SwiftUIStateObjectEqual -Left $Value.desiredSafetyOutcome -Right $case.desiredSafetyOutcome)) { throw 'Assessment case semantics differ from the reviewed case.' }
    if ($Value.observedOutcome -cnotin @('not-run', 'source-admitted', 'source-rejected', 'unsupported-configuration', 'tool-failure', 'timeout', 'artifact-failure')) { throw 'Unknown observed compiler outcome.' }
    if ($Value.diagnosticQualification -cnotin @('not-applicable', 'intended-diagnostic', 'unclassified-diagnostic', 'contaminated-diagnostic', 'prerequisite-not-established')) { throw 'Unknown diagnostic qualification.' }
    if (($Value.observedOutcome -ceq 'source-rejected') -eq ($Value.diagnosticQualification -ceq 'not-applicable')) { throw 'Diagnostic qualification does not match the raw outcome.' }
    foreach ($field in @('comparisonEligible', 'runtimeEvidence', 'parityClaimed', 'productionApprovalChanged')) {
        Assert-SwiftUIStateObjectBoolean -Value $Value.$field -Name "assessment.$field"
    }
    if ($Value.runtimeEvidence -or $Value.parityClaimed -or $Value.productionApprovalChanged) { throw 'Compiler assessment cannot claim runtime, parity, or production approval.' }
    foreach ($field in @('safetyRequirementMet', 'controlRequirementMet')) {
        if ($null -ne $Value.$field) { Assert-SwiftUIStateObjectBoolean -Value $Value.$field -Name "assessment.$field" }
    }
    Assert-SwiftUIStateObjectArray -Value $Value.prerequisites -Name 'assessment.prerequisites' -MaximumCount 16
    $dependencyPolicy = @(Get-SwiftUIStateObjectDependencyPolicy -Case $case)
    if ($Value.prerequisites.Count -ne $dependencyPolicy.Count) { throw 'An assessment must account for every declared prerequisite.' }
    $coreEstablished = $true
    $attributionEstablished = $true
    for ($index = 0; $index -lt $dependencyPolicy.Count; $index++) {
        $dependency = $Value.prerequisites[$index]
        Assert-SwiftUIStateObjectFields -Value $dependency -Name 'prerequisite' -Required @('caseID', 'requirement', 'established', 'reason')
        if ($dependency.caseID -cne $dependencyPolicy[$index].caseID -or $dependency.requirement -cne $dependencyPolicy[$index].requirement) { throw 'Prerequisite metadata differs from the reviewed dependency order.' }
        Assert-SwiftUIStateObjectBoolean -Value $dependency.established -Name 'prerequisite.established'
        if ($dependency.reason -cnotin @('established', 'missing', 'different-attempt-target-or-profile', 'control-not-qualified', 'no-ordinary-source-outcome')) { throw 'Unknown prerequisite reason.' }
        if ($dependency.established -ne ($dependency.reason -ceq 'established')) { throw 'Prerequisite reason and established flag disagree.' }
        if (-not $dependency.established) {
            if ($dependency.requirement -ceq 'wrapper-specific-admission') { $attributionEstablished = $false }
            else { $coreEstablished = $false }
        }
    }
    Assert-SwiftUIStateObjectStringArray -Value $Value.reviewFlags -Name 'assessment.reviewFlags' -MaximumCount 16 -MaximumStringLength 96 -Unique
    $allowedFlags = @('unsafe-shape-admitted', 'prerequisite-not-established', 'wrapper-specific-attribution-not-established',
        'unclassified-diagnostic', 'contaminated-diagnostic', 'source-admission-with-diagnostics',
        'control-requirement-not-met', 'infrastructure-failure', 'not-run')
    foreach ($flag in $Value.reviewFlags) { if ($flag -cnotin $allowedFlags) { throw 'Unknown assessment review flag.' } }
    if (-not $coreEstablished -and 'prerequisite-not-established' -cnotin $Value.reviewFlags) { throw 'Missing prerequisites must remain visible in review flags.' }
    $ineligibleFlags = @('prerequisite-not-established', 'wrapper-specific-attribution-not-established',
        'unclassified-diagnostic', 'contaminated-diagnostic', 'source-admission-with-diagnostics', 'infrastructure-failure', 'not-run')
    if ($Value.comparisonEligible -and @($Value.reviewFlags | Where-Object { $_ -cin $ineligibleFlags }).Count -gt 0) {
        throw 'Unqualified review flags cannot be marked comparison eligible.'
    }
    if ($Value.comparisonEligible -and
        ($Value.observedOutcome -cnotin @('source-admitted', 'source-rejected') -or -not $coreEstablished -or
        ($Value.observedOutcome -ceq 'source-rejected' -and $Value.diagnosticQualification -cne 'intended-diagnostic'))) {
        throw 'Comparison eligibility requires a qualified ordinary source observation.'
    }
    if ($case.role -ceq 'unsafe-wrapper-characterization') {
        if ($Value.observedOutcome -ceq 'source-admitted') {
            if ($null -eq $Value.safetyRequirementMet -or $Value.safetyRequirementMet -ne $false -or 'unsafe-shape-admitted' -cnotin $Value.reviewFlags) { throw 'An admitted unsafe shape must preserve the unmet safety requirement.' }
            if (-not $attributionEstablished -and
                ($Value.comparisonEligible -or 'wrapper-specific-attribution-not-established' -cnotin $Value.reviewFlags)) {
                throw 'Wrapper-specific attribution requires its qualified direct-capture control.'
            }
        } elseif ($Value.safetyRequirementMet -eq $true -and
            ($Value.observedOutcome -cne 'source-rejected' -or $Value.diagnosticQualification -cne 'intended-diagnostic' -or -not $coreEstablished)) {
            throw 'Static safety cannot be established by an unqualified rejection.'
        } elseif ($null -ne $Value.safetyRequirementMet -and $Value.safetyRequirementMet -eq $false) {
            throw 'Only an observed unsafe admission sets the safety requirement to false.'
        }
    } elseif ($null -ne $Value.safetyRequirementMet) { throw 'A non-witness case has no desired safety requirement.' }
    if ($case.role -cin @('admission-control', 'intended-diagnostic-control')) {
        $intendedOutcome = 'source-admitted'
        if ($case.role -ceq 'intended-diagnostic-control') { $intendedOutcome = 'source-rejected' }
        if ($Value.controlRequirementMet -eq $true -and
            (-not $Value.comparisonEligible -or $Value.observedOutcome -cne $intendedOutcome -or
            ($intendedOutcome -ceq 'source-rejected' -and $Value.diagnosticQualification -cne 'intended-diagnostic'))) {
            throw 'A control cannot be established by the wrong or unqualified outcome.'
        }
        if ($null -ne $Value.controlRequirementMet -and $Value.controlRequirementMet -eq $false -and
            ($Value.observedOutcome -cnotin @('source-admitted', 'source-rejected') -or $Value.observedOutcome -ceq $intendedOutcome)) {
            throw 'Only an ordinary opposite outcome records an unmet control requirement.'
        }
        if ($null -ne $Value.controlRequirementMet -and $Value.controlRequirementMet -eq $false -and 'control-requirement-not-met' -cnotin $Value.reviewFlags) { throw 'An unmet control requirement must remain visible.' }
    } elseif ($null -ne $Value.controlRequirementMet) { throw 'A characterization case is not a control.' }
}

function Test-SwiftUIStateObjectPriorControl {
    param($Prior, [System.Collections.Generic.Dictionary[string, object]]$PriorByKey, [int]$Depth = 0)
    if ($Depth -gt 21) { throw 'Prerequisite traversal exceeded the fixed case matrix.' }
    if ($Prior.controlRequirementMet -ne $true -or -not $Prior.comparisonEligible) { return $false }
    # A saved "established" flag is not an independent proof. Every transitive
    # control must still be present under the exact same attempt/target/profile.
    foreach ($dependency in $Prior.prerequisites) {
        if (-not $dependency.established) { return $false }
        $key = "$($Prior.attemptID)|$($Prior.target)|$($Prior.compilerProfileSHA256)|$($dependency.caseID)"
        if (-not $PriorByKey.ContainsKey($key)) { return $false }
        $ancestor = $PriorByKey[$key]
        if ($dependency.requirement -ceq 'observation') {
            if ($ancestor.observedOutcome -cnotin @('source-admitted', 'source-rejected')) { return $false }
        } elseif (-not (Test-SwiftUIStateObjectPriorControl -Prior $ancestor -PriorByKey $PriorByKey -Depth ($Depth + 1))) { return $false }
    }
    return $true
}

function Get-SwiftUIStateObjectCaseAssessment {
    param(
        [Parameter(Mandatory)]$Case,
        [Parameter(Mandatory)][string]$AttemptID,
        [Parameter(Mandatory)][string]$Target,
        [Parameter(Mandatory)][string]$CompilerProfileSHA256,
        [Parameter(Mandatory)]$Process,
        [Parameter(Mandatory)]$Diagnostics,
        [AllowEmptyCollection()][object[]]$PrerequisiteResults = @()
    )
    Assert-SwiftUIStateObjectCase -Case $Case
    Assert-SwiftUIStateObjectIdentity -AttemptID $AttemptID -Target $Target -CompilerProfileSHA256 $CompilerProfileSHA256
    Assert-SwiftUIStateObjectDiagnostics -Value $Diagnostics -Case $Case
    Assert-SwiftUIStateObjectFields -Value $Process -Name 'process adapter' -Required @(
        'processStarted', 'exitCode', 'timedOut', 'outputLimitExceeded', 'abnormalTermination',
        'allRedirectedStreamsClosed', 'terminationCompleted', 'error', 'notRunReason', 'artifactIssues', 'sil')
    foreach ($field in @('processStarted', 'timedOut', 'outputLimitExceeded', 'abnormalTermination', 'allRedirectedStreamsClosed', 'terminationCompleted')) {
        Assert-SwiftUIStateObjectBoolean -Value $Process.$field -Name "process.$field"
    }
    if ($null -ne $Process.exitCode) { Assert-SwiftUIStateObjectInteger -Value $Process.exitCode -Name 'process.exitCode' -Minimum ([int]::MinValue) -Maximum ([uint32]::MaxValue) }
    foreach ($field in @('error', 'notRunReason')) {
        if ($null -ne $Process.$field) { Assert-SwiftUIStateObjectString -Value $Process.$field -Name "process.$field" }
    }
    Assert-SwiftUIStateObjectStringArray -Value $Process.artifactIssues -Name 'process.artifactIssues'
    if ($null -ne $Process.sil) {
        Assert-SwiftUIStateObjectFields -Value $Process.sil -Name 'process.sil' -Required @('path', 'sha256', 'bytes')
        Assert-SwiftUIStateObjectRelativePath -Value $Process.sil.path -Name 'process.sil.path'
        Assert-SwiftUIStateObjectHash -Value $Process.sil.sha256 -Name 'process.sil.sha256'
        Assert-SwiftUIStateObjectInteger -Value $Process.sil.bytes -Name 'process.sil.bytes' -Maximum 2147483647
    }
    if (-not $Process.processStarted) {
        if ($null -ne $Process.exitCode -or $null -ne $Process.sil -or $Process.timedOut -or $Process.outputLimitExceeded) { throw 'An unlaunched request cannot have an exit, SIL, timeout, or output-limit event.' }
        if ($null -ne $Process.error -and $null -ne $Process.notRunReason) { throw 'Launch failure and intentional not-run reasons must remain distinct.' }
        if ($null -eq $Process.error -and $null -eq $Process.notRunReason -and $Process.artifactIssues.Count -eq 0 -and $Diagnostics.issues.Count -eq 0) { throw 'An unlaunched request requires a concrete not-run, launch-error, or integrity-failure reason.' }
        if ($Diagnostics.headers.Count -gt 0 -or $Diagnostics.unrecognizedPrimaryLines.Count -gt 0) { throw 'An unlaunched request cannot contain compiler diagnostics.' }
    } elseif ($null -ne $Process.notRunReason) { throw 'A launched request cannot be relabeled not-run.' }

    $policies = @(Get-SwiftUIStateObjectCasePolicies)
    $caseOrder = [System.Collections.Generic.Dictionary[string, int]]::new([System.StringComparer]::Ordinal)
    for ($index = 0; $index -lt $policies.Count; $index++) { $caseOrder.Add($policies[$index].caseID, $index) }
    $priorByKey = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::Ordinal)
    if ($PrerequisiteResults.Count -gt 42) { throw 'There cannot be more than 42 prior matrix observations.' }
    foreach ($prior in $PrerequisiteResults) {
        Assert-SwiftUIStateObjectAssessment -Value $prior
        $key = "$($prior.attemptID)|$($prior.target)|$($prior.compilerProfileSHA256)|$($prior.caseID)"
        if ($priorByKey.ContainsKey($key)) { throw 'Duplicate prerequisite identity is ambiguous.' }
        if ($prior.attemptID -ceq $AttemptID -and $prior.target -ceq $Target -and $prior.compilerProfileSHA256 -ceq $CompilerProfileSHA256 -and
            $caseOrder[$prior.caseID] -ge $caseOrder[$Case.caseID]) { throw 'A same-boundary prerequisite record is not a prior case.' }
        $priorByKey.Add($key, $prior)
    }
    $prerequisites = [System.Collections.Generic.List[object]]::new()
    $coreEstablished = $true
    $attributionEstablished = $true
    foreach ($dependency in @(Get-SwiftUIStateObjectDependencyPolicy -Case $Case)) {
        $key = "$AttemptID|$Target|$CompilerProfileSHA256|$($dependency.caseID)"
        $established = $false
        $reason = 'missing'
        if ($priorByKey.ContainsKey($key)) {
            $prior = $priorByKey[$key]
            if ($dependency.requirement -ceq 'observation') {
                $established = $prior.observedOutcome -cin @('source-admitted', 'source-rejected')
                $reason = 'no-ordinary-source-outcome'
            } else {
                $established = Test-SwiftUIStateObjectPriorControl -Prior $prior -PriorByKey $priorByKey
                $reason = 'control-not-qualified'
            }
            if ($established) { $reason = 'established' }
        } elseif (@($PrerequisiteResults | Where-Object { $_.caseID -ceq $dependency.caseID }).Count -gt 0) {
            $reason = 'different-attempt-target-or-profile'
        }
        if (-not $established) {
            if ($dependency.requirement -ceq 'wrapper-specific-admission') { $attributionEstablished = $false }
            else { $coreEstablished = $false }
        }
        $prerequisites.Add([pscustomobject][ordered]@{ caseID = $dependency.caseID; requirement = $dependency.requirement; established = $established; reason = $reason })
    }

    $errors = @($Diagnostics.headers | Where-Object { $_.isPrimaryHeader -and $_.severity -ceq 'error' })
    $sourceErrors = @($errors | Where-Object { $null -ne $_.relativePath -and $_.sourcePositionValid })
    $primaries = @($Diagnostics.headers | Where-Object { $_.isPrimaryHeader })
    $intended = @($errors | Where-Object { $_.classification -ceq 'intended-diagnostic' })
    $otherPrimaries = @($primaries | Where-Object { $_.classification -cne 'intended-diagnostic' })
    $hasIntegrityFailure = $Process.artifactIssues.Count -gt 0 -or $Diagnostics.issues.Count -gt 0 -or
        $Process.outputLimitExceeded -or ($null -ne $Process.sil -and $Process.sil.bytes -gt 8388608)
    $outcome = $null
    if (-not $Process.processStarted) {
        if ($hasIntegrityFailure) { $outcome = 'artifact-failure' }
        elseif ($null -ne $Process.error -or $Process.abnormalTermination) { $outcome = 'tool-failure' }
        else { $outcome = 'not-run' }
    } elseif ($Process.timedOut) { $outcome = 'timeout' }
    elseif ($Process.outputLimitExceeded) { $outcome = 'artifact-failure' }
    elseif ($Process.abnormalTermination -or $Diagnostics.hasCrashMarker -or $null -ne $Process.error -or
        $null -eq $Process.exitCode -or $Process.exitCode -cnotin @(0, 1)) { $outcome = 'tool-failure' }
    elseif ($hasIntegrityFailure -or -not $Process.allRedirectedStreamsClosed -or -not $Process.terminationCompleted) { $outcome = 'artifact-failure' }
    elseif ($Diagnostics.hasConfigurationFailure) { $outcome = 'unsupported-configuration' }
    elseif ($null -eq $Diagnostics.stderr) { $outcome = 'artifact-failure' }
    elseif ($Process.exitCode -eq 0) {
        if ($null -eq $Process.sil -or $Process.sil.bytes -eq 0 -or $errors.Count -gt 0 -or $Diagnostics.unrecognizedPrimaryLines.Count -gt 0) { $outcome = 'artifact-failure' }
        else { $outcome = 'source-admitted' }
    } elseif ($sourceErrors.Count -eq 0) {
        # Exit 1 alone, notes, or an unlocated message do not establish a normal
        # source diagnostic. Unknown wording on a real source header still does.
        $outcome = 'tool-failure'
    } else { $outcome = 'source-rejected' }

    $flags = [System.Collections.Generic.List[string]]::new()
    $qualification = 'not-applicable'
    if ($outcome -ceq 'source-rejected') {
        if ($intended.Count -gt 0 -and $otherPrimaries.Count -eq 0 -and $Diagnostics.unrecognizedPrimaryLines.Count -eq 0) {
            if ($coreEstablished) { $qualification = 'intended-diagnostic' }
            else { $qualification = 'prerequisite-not-established' }
        } elseif ($intended.Count -gt 0) {
            $qualification = 'contaminated-diagnostic'
            $flags.Add('contaminated-diagnostic')
        } else {
            $qualification = 'unclassified-diagnostic'
            $flags.Add('unclassified-diagnostic')
        }
    }
    if (-not $coreEstablished) { $flags.Add('prerequisite-not-established') }
    $cleanAdmission = $outcome -ceq 'source-admitted' -and $primaries.Count -eq 0 -and $Diagnostics.unrecognizedPrimaryLines.Count -eq 0
    if ($outcome -ceq 'source-admitted' -and -not $cleanAdmission) { $flags.Add('source-admission-with-diagnostics') }
    $comparisonEligible = $coreEstablished -and ($cleanAdmission -or ($outcome -ceq 'source-rejected' -and $qualification -ceq 'intended-diagnostic'))
    $safetyMet = $null
    if ($Case.role -ceq 'unsafe-wrapper-characterization') {
        if ($outcome -ceq 'source-admitted') {
            $safetyMet = $false
            $flags.Add('unsafe-shape-admitted')
            if (-not $attributionEstablished) { $comparisonEligible = $false; $flags.Add('wrapper-specific-attribution-not-established') }
        } elseif ($outcome -ceq 'source-rejected' -and $qualification -ceq 'intended-diagnostic') { $safetyMet = $true }
    }
    $controlMet = $null
    if ($Case.role -ceq 'admission-control') {
        if ($comparisonEligible -and $outcome -ceq 'source-admitted') { $controlMet = $true }
        elseif ($outcome -ceq 'source-rejected') { $controlMet = $false }
    } elseif ($Case.role -ceq 'intended-diagnostic-control') {
        if ($comparisonEligible -and $outcome -ceq 'source-rejected' -and $qualification -ceq 'intended-diagnostic') { $controlMet = $true }
        elseif ($outcome -ceq 'source-admitted') { $controlMet = $false }
    }
    if ($null -ne $controlMet -and $controlMet -eq $false) { $flags.Add('control-requirement-not-met') }
    if ($outcome -ceq 'not-run') { $flags.Add('not-run') }
    elseif ($outcome -cnotin @('source-admitted', 'source-rejected')) { $flags.Add('infrastructure-failure') }
    $result = [pscustomobject][ordered]@{
        schemaVersion = 1; attemptID = $AttemptID; target = $Target; compilerProfileSHA256 = $CompilerProfileSHA256
        caseID = $Case.caseID; role = $Case.role; observedOutcome = $outcome; diagnosticQualification = $qualification
        nativeHypothesis = (Get-SwiftUIStateObjectNativeHypothesis -Case $Case)
        desiredSafetyOutcome = $Case.desiredSafetyOutcome; safetyRequirementMet = $safetyMet; controlRequirementMet = $controlMet
        prerequisites = $prerequisites.ToArray(); reviewFlags = $flags.ToArray(); comparisonEligible = $comparisonEligible
        runtimeEvidence = $false; parityClaimed = $false; productionApprovalChanged = $false
    }
    Assert-SwiftUIStateObjectAssessment -Value $result
    return $result
}
