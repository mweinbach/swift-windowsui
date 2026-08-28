[CmdletBinding()]
param([switch]$KeepArtifacts)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'swiftui-stateobject-isolation-common.ps1')

# All process outcomes and SIL metadata below are fabricated. These tests never
# launch Swift, a compiler, a generated executable, or a UI framework.
$script:assertionCount = 0
$script:testCount = 0
$script:failures = [System.Collections.Generic.List[string]]::new()
$script:skips = [System.Collections.Generic.List[string]]::new()
$script:logNumber = 0
$script:attempt = 'synthetic-attempt'
$script:target = 'x86_64-apple-macosx26.5'
$script:profileHash = 'a' * 64
$script:utf8 = [System.Text.UTF8Encoding]::new($false, $true)
$script:fixtureRoot = Join-Path $PSScriptRoot 'fixtures/swiftui-stateobject-isolation'
$testDirectoryName = 'swiftui-stateobject-isolation-tests-' + [guid]::NewGuid().ToString('N')
$script:testRoot = [System.IO.Path]::GetFullPath((Join-Path ([System.IO.Path]::GetTempPath()) $testDirectoryName))
[void][System.IO.Directory]::CreateDirectory($script:testRoot)
$script:sourceRecords = @()
$script:qualifiedResults = @()
$script:casePolicies = @(Get-SwiftUIStateObjectCasePolicies)
$script:originalHashes = @()

function Assert-Synthetic {
    param([bool]$Condition, [string]$Message)
    $script:assertionCount++
    if (-not $Condition) { throw $Message }
}

function Assert-SyntheticEqual {
    param($Actual, $Expected, [string]$Message)
    $script:assertionCount++
    if ($null -eq $Expected) {
        if ($null -ne $Actual) { throw "$Message (expected null)" }
    } elseif ($null -eq $Actual -or $Actual -cne $Expected) {
        throw "$Message (expected '$Expected', got '$Actual')"
    }
}

function Assert-SyntheticThrows {
    param([scriptblock]$Action, [string]$Pattern)
    $script:assertionCount++
    $caught = $null
    try { & $Action | Out-Null } catch { $caught = $_ }
    if ($null -eq $caught) { throw 'Expected an exception, but the action succeeded.' }
    if (-not [string]::IsNullOrEmpty($Pattern) -and $caught.Exception.Message -notmatch $Pattern) {
        throw "Unexpected exception: $($caught.Exception.Message)"
    }
}

function Invoke-SyntheticCase {
    param([string]$Name, [scriptblock]$Body)
    $script:testCount++
    try { & $Body } catch { $script:failures.Add("$Name : $($_.Exception.Message)") }
}

function Copy-SyntheticValue {
    param($Value)
    # Test-only cloning of trusted constructed values. Production JSON input
    # always goes through the strict PowerShell 7 reader.
    $json = ConvertTo-Json -InputObject $Value -Depth 40
    $copy = ConvertFrom-Json -InputObject $json
    if ($Value -is [System.Array]) {
        # Windows PowerShell emits a root JSON array as one pipeline object;
        # enumerate it explicitly instead of depending on edition behavior.
        foreach ($item in $copy) { $item }
    } else { return $copy }
}

function Write-SyntheticText {
    param([string]$Name, [AllowEmptyString()][string]$Text)
    $path = Join-Path $script:testRoot $Name
    [System.IO.File]::WriteAllText($path, $Text, $script:utf8)
    return $path
}

function Get-SyntheticSources {
    param($Case)
    $paths = @($Case.source) + @($Case.sharedSources)
    return @($script:sourceRecords | Where-Object { $_.relativePath -cin $paths })
}

function New-SyntheticDiagnostics {
    param([string]$CaseID, [AllowEmptyString()][string]$Text = '')
    $script:logNumber++
    $path = Write-SyntheticText -Name ('stderr-{0:D4}.log' -f $script:logNumber) -Text $Text
    $case = Get-SwiftUIStateObjectCasePolicy -CaseID $CaseID
    return Get-SwiftUIStateObjectDiagnostics -StderrPath $path -Sources @(Get-SyntheticSources -Case $case) -Case $case
}

function New-SyntheticProcess {
    param([int]$ExitCode = 0)
    $sil = $null
    if ($ExitCode -eq 0) { $sil = [pscustomobject]@{ path = 'cases/fabricated.sil'; sha256 = ('b' * 64); bytes = 32 } }
    return [pscustomobject][ordered]@{
        processStarted = $true; exitCode = $ExitCode; timedOut = $false; outputLimitExceeded = $false
        abnormalTermination = $false; allRedirectedStreamsClosed = $true; terminationCompleted = $true
        error = $null; notRunReason = $null; artifactIssues = @(); sil = $sil
    }
}

function Get-SyntheticMessage {
    param($Case)
    switch ($Case.diagnosticExpectation.family) {
        'mainactor-property-access' { return "main actor-isolated property '$($Case.diagnosticExpectation.subject)' can not be referenced from a nonisolated context" }
        'mainactor-factory-call' { return "call to main actor-isolated global function 'makeActorOnlyModel()' in a synchronous nonisolated context" }
        default { return "sending value of non-Sendable type 'ProbeMutableCounter' risks causing data races [#SendingRisksDataRace]" }
    }
}

function Get-SyntheticHeader {
    param($Case, [string]$Message, [string]$Severity = 'error', [long]$Line = 0, [long]$Column = 1, [AllowNull()][string]$SourcePath)
    if ($null -eq $SourcePath -or $SourcePath.Length -eq 0) {
        $SourcePath = @($script:sourceRecords | Where-Object { $_.relativePath -ceq $Case.source })[0].path
    }
    if ($Line -eq 0) { $Line = $Case.diagnosticExpectation.anchors[0].line }
    return '{0}:{1}:{2}: {3}: {4}' -f $SourcePath, $Line, $Column, $Severity, $Message
}

function Get-SyntheticPriors {
    param([string]$CaseID)
    $index = 0
    while ($script:casePolicies[$index].caseID -cne $CaseID) { $index++ }
    $priorIDs = @($script:casePolicies | Select-Object -First $index | ForEach-Object { $_.caseID })
    return @($script:qualifiedResults | Where-Object { $_.caseID -cin $priorIDs })
}

function Invoke-SyntheticAssessment {
    param(
        [string]$CaseID, $Process, $Diagnostics,
        [AllowEmptyCollection()][object[]]$Prior = @(),
        [string]$AttemptID = $script:attempt,
        [string]$Target = $script:target,
        [string]$ProfileHash = $script:profileHash
    )
    $request = @{
        Case = (Get-SwiftUIStateObjectCasePolicy -CaseID $CaseID); AttemptID = $AttemptID; Target = $Target
        CompilerProfileSHA256 = $ProfileHash; Process = $Process; Diagnostics = $Diagnostics; PrerequisiteResults = $Prior
    }
    return Get-SwiftUIStateObjectCaseAssessment @request
}

try {
    [void][System.IO.Directory]::CreateDirectory((Join-Path $script:testRoot 'paired-public'))
    foreach ($source in @(Get-SwiftUIStateObjectSourcePolicy)) {
        $originalPath = Resolve-SwiftUIStateObjectEvidencePath -Root $script:fixtureRoot -RelativePath $source.path
        $before = Get-SwiftUIStateObjectFileHash -Path $originalPath -MaxBytes 65536
        Assert-SyntheticEqual $before.sha256 $source.sha256 'The original fixture hash must match the frozen source policy.'
        $script:originalHashes += $before
        $copyPath = Join-Path $script:testRoot $source.path
        Copy-Item -LiteralPath $originalPath -Destination $copyPath
        $copied = Get-SwiftUIStateObjectFileHash -Path $copyPath -MaxBytes 65536
        $script:sourceRecords += [pscustomobject]@{ path = $copied.path; relativePath = $source.path; sha256 = $copied.sha256; bytes = $copied.bytes }
    }
    $matrixPath = Join-Path $script:fixtureRoot 'matrix.json'
    $script:originalHashes += Get-SwiftUIStateObjectFileHash -Path $matrixPath -MaxBytes 262144

    Invoke-SyntheticCase 'fixed policy and source accounting' {
        Assert-SyntheticEqual $script:casePolicies.Count 21 'Case count'
        Assert-SyntheticEqual $script:sourceRecords.Count 24 'Source count'
        foreach ($role in @(@('admission-control',10),@('intended-diagnostic-control',4),@('source-observation-or-confound',5),@('unsafe-wrapper-characterization',2))) {
            Assert-SyntheticEqual @($script:casePolicies | Where-Object { $_.role -ceq $role[0] }).Count $role[1] 'Role count'
        }
        Assert-SyntheticEqual @($script:casePolicies.family | Sort-Object -Unique).Count 8 'Family count'
        Assert-SyntheticEqual (Get-SwiftUIStateObjectCasePolicy 'paired-public:08-direct-capture-checker-control').sharedSources.Count 1 'Checker common-file count'
        foreach ($case in $script:casePolicies) { Assert-SwiftUIStateObjectCase -Case $case; $script:assertionCount++ }
    }

    if ($PSVersionTable.PSVersion.Major -ge 7) {
        Invoke-SyntheticCase 'strict canonical matrix and CRLF-only normalization' {
            $matrix = Read-SwiftUIStateObjectMatrix -Path $matrixPath -SourceRoot $script:testRoot
            Assert-SyntheticEqual $matrix.cells.Count 42 'All native cells'
            Assert-SyntheticEqual $matrix.targets.Count 2 'Desktop target count'
            Assert-SyntheticEqual $matrix.contentSha256 '7608f38966424c4f9ca8628836a11aea3388ede5d7b9858c6e99f42474cd887b' 'Canonical matrix hash'
            $text = [System.IO.File]::ReadAllText($matrixPath, $script:utf8)
            $lfText = $text.Replace(([string][char]13 + [char]10), [string][char]10)
            $lfPath = Write-SyntheticText 'matrix-lf.json' $lfText
            $lfCopy = Read-SwiftUIStateObjectMatrix -Path $lfPath -SourceRoot $script:testRoot
            $crlfText = $lfText.Replace([string][char]10, ([string][char]13 + [char]10))
            $copyPath = Write-SyntheticText 'matrix-crlf.json' $crlfText
            $copy = Read-SwiftUIStateObjectMatrix -Path $copyPath -SourceRoot $script:testRoot
            Assert-SyntheticEqual $copy.contentSha256 $matrix.contentSha256 'CRLF content identity'
            Assert-Synthetic ($copy.sha256 -cne $lfCopy.sha256) 'Raw checkout bytes must remain distinguishable.'
            $changed = Write-SyntheticText 'matrix-whitespace.json' ($text + ' ')
            Assert-SyntheticThrows { Read-SwiftUIStateObjectMatrix -Path $changed -SourceRoot $script:testRoot } 'content hash'
        }
        $invalidJson = @(
            @('duplicate','{"a":1,"a":2}','Duplicate'), @('case-collision','{"a":1,"A":2}','case-colliding'),
            @('decoded-duplicate','{"a":1,"\u0061":2}','Duplicate'), @('nested-collision','{"outer":[{"x":1,"X":2}]}','case-colliding'),
            @('array-root','[]','root'), @('comment','{/* no */"a":1}',''), @('trailing-comma','{"a":1,}',''),
            @('nonfinite','{"a":1e400}','finite'), @('empty','',''), @('bare-cr',('{"a":1}'+[char]13),'line endings')
        )
        foreach ($invalid in $invalidJson) {
            Invoke-SyntheticCase ("JSON " + $invalid[0]) {
                $path = Write-SyntheticText ($invalid[0] + '.json') $invalid[1]
                Assert-SyntheticThrows { Read-SwiftUIStateObjectJson -Path $path } $invalid[2]
            }
        }
        Invoke-SyntheticCase 'JSON UTF8 and exact resource bounds' {
            $path = Join-Path $script:testRoot 'invalid-utf8.json'
            [System.IO.File]::WriteAllBytes($path, [byte[]]@(123,34,97,34,58,34,195,40,34,125))
            Assert-SyntheticThrows { Read-SwiftUIStateObjectJson -Path $path } ''
            $bom = Join-Path $script:testRoot 'bom.json'
            [System.IO.File]::WriteAllBytes($bom, ([byte[]]@(239,187,191) + $script:utf8.GetBytes('{"a":1}')))
            Assert-SyntheticThrows { Read-SwiftUIStateObjectJson -Path $bom } 'BOM'
            $bounded = Write-SyntheticText 'nodes.json' '{"a":[null,true]}'
            $record = Read-SwiftUIStateObjectJson -Path $bounded -MaxNodes 4
            Assert-SyntheticEqual $record.document.a.Count 2 'JSON array retained'
            Assert-SyntheticEqual $record.document.a[0] $null 'JSON null retained'
            Assert-SyntheticThrows { Read-SwiftUIStateObjectJson -Path $bounded -MaxNodes 3 } 'node'
            Assert-SyntheticThrows { Read-SwiftUIStateObjectJson -Path $bounded -MaxBytes 1 } 'byte limit'
            Assert-SyntheticThrows { Read-SwiftUIStateObjectJson -Path $bounded -MaxDepth 1 } 'depth'
            Assert-SyntheticThrows { Read-SwiftUIStateObjectJson -Path $bounded -MaxDepth 65 } 'limits'
            Assert-SyntheticThrows { Read-SwiftUIStateObjectJson -Path $bounded -MaxNodes 0 } 'limits'
        }
        Invoke-SyntheticCase 'matrix structure cannot override reviewed policy' {
            $record = Read-SwiftUIStateObjectJson -Path $matrixPath
            $changed = Copy-SyntheticValue $record.document
            $changed.cases[0].family = 8
            $path = Write-SyntheticText 'matrix-policy-change.json' ($changed | ConvertTo-Json -Depth 30)
            Assert-SyntheticThrows { Read-SwiftUIStateObjectMatrix -Path $path -SourceRoot $script:testRoot } 'operation policy'
            $changed = Copy-SyntheticValue $record.document
            $changed.targets[0] = 'x86_64-apple-ios26.5-macabi'
            $path = Write-SyntheticText 'matrix-catalyst.json' ($changed | ConvertTo-Json -Depth 30)
            Assert-SyntheticThrows { Read-SwiftUIStateObjectMatrix -Path $path -SourceRoot $script:testRoot } 'targets'
            $changed = Copy-SyntheticValue $record.document
            $changed.cases[0] | Add-Member -NotePropertyName arbitraryRegex -NotePropertyValue '.*'
            $path = Write-SyntheticText 'matrix-regex.json' ($changed | ConvertTo-Json -Depth 30)
            Assert-SyntheticThrows { Read-SwiftUIStateObjectMatrix -Path $path -SourceRoot $script:testRoot } 'unknown'
        }
    } else {
        Invoke-SyntheticCase 'PowerShell 5.1 strict JSON explicitly unsupported' {
            Assert-SyntheticThrows { Read-SwiftUIStateObjectJson -Path $matrixPath } 'PowerShell 7.*unsupported'
            Assert-SyntheticThrows { Read-SwiftUIStateObjectMatrix -Path $matrixPath -SourceRoot $script:testRoot } 'PowerShell 7.*unsupported'
        }
    }

    Invoke-SyntheticCase 'portable relative path and regular file bounds' {
        foreach ($bad in @('../escape','/absolute','C:/absolute','a\b','a/../b','a//b','CON.txt','dir/name.','dir/NUL','space name')) {
            Assert-SyntheticThrows { Resolve-SwiftUIStateObjectEvidencePath -Root $script:testRoot -RelativePath $bad -AllowMissingLeaf } 'relative|reserved|ambiguous'
        }
        $missing = Resolve-SwiftUIStateObjectEvidencePath -Root $script:testRoot -RelativePath 'new.log' -AllowMissingLeaf
        Assert-SyntheticEqual $missing (Join-Path $script:testRoot 'new.log') 'Missing leaf stays in owned root.'
        Assert-SyntheticThrows { Resolve-SwiftUIStateObjectEvidencePath -Root $script:testRoot -RelativePath 'missing/new.log' -AllowMissingLeaf } 'does not exist'
        $empty = Write-SyntheticText 'empty-file.log' ''
        Assert-SyntheticEqual (Get-SwiftUIStateObjectFileHash -Path $empty -MaxBytes 0).sha256 'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855' 'Empty-file hash'
        $large = Write-SyntheticText 'bounded-file.log' 'abc'
        Assert-SyntheticThrows { Get-SwiftUIStateObjectFileHash -Path $large -MaxBytes 2 } 'byte limit'
        Assert-SyntheticThrows { Assert-SwiftUIStateObjectRegularFile -Path $script:testRoot } 'regular file'
        Assert-Synthetic (Test-SwiftUIStateObjectUnixFileType 'File') 'Exact Unix regular-file type'
        foreach ($type in @($null,'file','FIFO','Socket','Directory','SymbolicLink','BlockDevice','CharacterDevice',1)) {
            Assert-Synthetic (-not (Test-SwiftUIStateObjectUnixFileType $type)) 'Other Unix types cannot pass the pure predicate.'
        }
    }
    Invoke-SyntheticCase 'owned filesystem alias rejection' {
        $targetPath = Write-SyntheticText 'alias-target.log' 'sentinel'
        $aliasPath = Join-Path $script:testRoot 'alias-file.log'
        try { [void](New-Item -ItemType SymbolicLink -Path $aliasPath -Target $targetPath -ErrorAction Stop) }
        catch { $script:skips.Add('File symlink creation unavailable on this test host.'); return }
        Assert-SyntheticThrows { Assert-SwiftUIStateObjectRegularFile -Path $aliasPath } 'regular file'
        Assert-SyntheticThrows { Resolve-SwiftUIStateObjectEvidencePath -Root $script:testRoot -RelativePath 'alias-file.log' } 'aliases'
        $targetDirectory = Join-Path $script:testRoot 'alias-target-directory'
        [void][System.IO.Directory]::CreateDirectory($targetDirectory)
        $aliasDirectory = Join-Path $script:testRoot 'alias-directory'
        [void](New-Item -ItemType SymbolicLink -Path $aliasDirectory -Target $targetDirectory -ErrorAction Stop)
        Assert-SyntheticThrows { Resolve-SwiftUIStateObjectEvidencePath -Root $aliasDirectory -RelativePath 'anything.log' -AllowMissingLeaf } 'ordinary directory'
        [System.IO.File]::WriteAllText((Join-Path $targetDirectory 'inside.log'), 'inside-sentinel', $script:utf8)
        Assert-SyntheticThrows { Assert-SwiftUIStateObjectRegularFile -Path (Join-Path $aliasDirectory 'inside.log') } 'ordinary directory'
        $danglingPath = Join-Path $script:testRoot 'dangling.log'
        [void](New-Item -ItemType SymbolicLink -Path $danglingPath -Target (Join-Path $script:testRoot 'missing-target.log') -ErrorAction Stop)
        Assert-SyntheticThrows { Resolve-SwiftUIStateObjectEvidencePath -Root $script:testRoot -RelativePath 'dangling.log' -AllowMissingLeaf } 'aliases'
        Assert-SyntheticEqual ([System.IO.File]::ReadAllText($targetPath)) 'sentinel' 'Alias target remains unchanged.'
    }

    Invoke-SyntheticCase 'complete synthetic case policy and qualified prerequisites' {
        $results = [System.Collections.Generic.List[object]]::new()
        foreach ($case in $script:casePolicies) {
            $process = New-SyntheticProcess
            $text = ''
            if ($null -ne $case.diagnosticExpectation) { $process = New-SyntheticProcess -ExitCode 1; $text = Get-SyntheticHeader -Case $case -Message (Get-SyntheticMessage -Case $case) }
            $diagnostics = New-SyntheticDiagnostics -CaseID $case.caseID -Text $text
            $assessment = Invoke-SyntheticAssessment -CaseID $case.caseID -Process $process -Diagnostics $diagnostics -Prior $results.ToArray()
            Assert-Synthetic $assessment.comparisonEligible ("Qualified synthetic case: " + $case.caseID)
            foreach ($flag in @('runtimeEvidence','parityClaimed','productionApprovalChanged')) { Assert-SyntheticEqual $assessment.$flag $false 'No qualification may be invented.' }
            if ($case.role -ceq 'unsafe-wrapper-characterization') { Assert-SyntheticEqual $assessment.safetyRequirementMet $true 'Qualified fabricated rejection only.' }
            elseif ($case.role -cne 'source-observation-or-confound') { Assert-SyntheticEqual $assessment.controlRequirementMet $true 'Control established.' }
            $results.Add($assessment)
        }
        $script:qualifiedResults = $results.ToArray()
        Assert-SyntheticEqual $script:qualifiedResults.Count 21 'All synthetic cases accounted for.'
    }
    if ($script:qualifiedResults.Count -ne 21) { throw 'Dependent synthetic tests require the complete qualified baseline.' }

    $wrappedID = 'paired-public:06-reject-wrapped-access'
    $wrappedCase = Get-SwiftUIStateObjectCasePolicy $wrappedID
    $wrappedMessage = Get-SyntheticMessage $wrappedCase
    $wrappedHeader = Get-SyntheticHeader -Case $wrappedCase -Message $wrappedMessage
    $wrappedPriors = @(Get-SyntheticPriors $wrappedID)
    $newline = [string][char]10
    Invoke-SyntheticCase 'echoes, notes, and nested header text do not create primary errors' {
        foreach ($echo in @("10 | $wrappedHeader","   | ^- error: $wrappedHeader","// $wrappedHeader","  /* $wrappedHeader","   $wrappedHeader")) {
            $diagnostics = New-SyntheticDiagnostics $wrappedID $echo
            $result = Invoke-SyntheticAssessment $wrappedID (New-SyntheticProcess 1) $diagnostics $wrappedPriors
            Assert-SyntheticEqual $diagnostics.headers.Count 0 'Echo is not a header.'
            Assert-SyntheticEqual $result.observedOutcome 'tool-failure' 'Exit1 without a source error is not source rejection.'
        }
        $note = Get-SyntheticHeader -Case $wrappedCase -Message $wrappedMessage -Severity 'note'
        $diagnostics = New-SyntheticDiagnostics $wrappedID $note
        Assert-SyntheticEqual (Invoke-SyntheticAssessment $wrappedID (New-SyntheticProcess 1) $diagnostics $wrappedPriors).observedOutcome 'tool-failure' 'Notes alone do not establish diagnostic rejection.'
        $nested = Get-SyntheticHeader -Case $wrappedCase -Message ("unrelated error containing " + $wrappedHeader)
        $diagnostics = New-SyntheticDiagnostics $wrappedID $nested
        Assert-SyntheticEqual $diagnostics.headers.Count 1 'First physical header wins.'
        Assert-SyntheticEqual $diagnostics.headers[0].classification 'unclassified-source-diagnostic' 'Nested intended text is not reparsed.'
        Assert-SyntheticEqual (Invoke-SyntheticAssessment $wrappedID (New-SyntheticProcess 1) $diagnostics $wrappedPriors).observedOutcome 'source-rejected' 'Unknown wording on a source header remains a source observation.'
        $diagnostics = New-SyntheticDiagnostics $wrappedID ($wrappedHeader + $newline + $nested)
        Assert-SyntheticEqual (Invoke-SyntheticAssessment $wrappedID (New-SyntheticProcess 1) $diagnostics $wrappedPriors).diagnosticQualification 'contaminated-diagnostic' 'Unrelated primary error stays visible.'
        $foreignNote = '/SDK/SwiftUI.swiftinterface:12:4: note: property declared here'
        $diagnostics = New-SyntheticDiagnostics $wrappedID ($wrappedHeader + $newline + $foreignNote + $newline + 'note: supplementary explanation')
        Assert-SyntheticEqual (Invoke-SyntheticAssessment $wrappedID (New-SyntheticProcess 1) $diagnostics $wrappedPriors).diagnosticQualification 'intended-diagnostic' 'Notes do not become primary contamination.'
        $diagnostics = New-SyntheticDiagnostics $wrappedID ($wrappedHeader + $newline + '/tool/path/unknown-frontend: error: an unrelated tool error')
        Assert-SyntheticEqual $diagnostics.unrecognizedPrimaryLines.Count 1 'Unknown tool prefixes must stay visible.'
        Assert-SyntheticEqual (Invoke-SyntheticAssessment $wrappedID (New-SyntheticProcess 1) $diagnostics $wrappedPriors).diagnosticQualification 'contaminated-diagnostic' 'An unrelated tool error cannot disappear.'
        $diagnostics = New-SyntheticDiagnostics $wrappedID ($wrappedHeader + $newline + 'note: a message containing tool: error: quoted text')
        Assert-SyntheticEqual (Invoke-SyntheticAssessment $wrappedID (New-SyntheticProcess 1) $diagnostics $wrappedPriors).diagnosticQualification 'intended-diagnostic' 'A root note message is not reparsed.'
    }
    Invoke-SyntheticCase 'root and tool severity outrank quoted complete located headers' {
        foreach ($prefix in @('note: quoted ', '/tool/path/unknown-frontend: note: quoted ')) {
            $diagnostics = New-SyntheticDiagnostics $wrappedID ($wrappedHeader + $newline + $prefix + $wrappedHeader)
            Assert-SyntheticEqual $diagnostics.headers.Count 1 'A quoted complete source header is not a second located diagnostic.'
            Assert-SyntheticEqual $diagnostics.unrecognizedPrimaryLines.Count 0 'An outer note does not create a primary error.'
            Assert-SyntheticEqual (Invoke-SyntheticAssessment $wrappedID (New-SyntheticProcess 1) $diagnostics $wrappedPriors).diagnosticQualification 'intended-diagnostic' 'The first real severity controls the quoted message.'
        }
        $quotedNote = Get-SyntheticHeader -Case $wrappedCase -Message 'quoted' -Severity 'note'
        foreach ($prefix in @('error: unknown argument: ', '/tool/path/unknown-frontend: error: unknown argument: ')) {
            $diagnostics = New-SyntheticDiagnostics $wrappedID ($prefix + "'" + $quotedNote + "'" + $newline + $wrappedHeader)
            Assert-Synthetic $diagnostics.hasConfigurationFailure 'A root/tool configuration error cannot disappear inside a quoted source note.'
            Assert-SyntheticEqual $diagnostics.unrecognizedPrimaryLines.Count 1 'The outer primary error remains visible.'
            Assert-SyntheticEqual (Invoke-SyntheticAssessment $wrappedID (New-SyntheticProcess 1) $diagnostics $wrappedPriors).observedOutcome 'unsupported-configuration' 'A quoted note cannot qualify a configuration failure.'
        }
        foreach ($prefix in @('error: unrelated failure quoting ', '/tool/path/unknown-frontend: warning: unrelated warning quoting ')) {
            $diagnostics = New-SyntheticDiagnostics $wrappedID ($prefix + $quotedNote + $newline + $wrappedHeader)
            Assert-SyntheticEqual $diagnostics.unrecognizedPrimaryLines.Count 1 'A quoted note cannot hide an unrelated outer primary.'
            Assert-SyntheticEqual (Invoke-SyntheticAssessment $wrappedID (New-SyntheticProcess 1) $diagnostics $wrappedPriors).diagnosticQualification 'contaminated-diagnostic' 'Outer unrelated errors and warnings prevent qualified rejection.'
        }
    }
    Invoke-SyntheticCase 'exact source file and in-file operation anchors' {
        $wrongFile = Join-Path $script:testRoot 'elsewhere/06-reject-wrapped-access.swift'
        $actualFile = @($script:sourceRecords | Where-Object { $_.relativePath -ceq $wrappedCase.source })[0].path
        $variants = @(
            (Get-SyntheticHeader $wrappedCase $wrappedMessage -Column 9999),
            (Get-SyntheticHeader $wrappedCase $wrappedMessage -SourcePath $wrongFile),
            (Get-SyntheticHeader $wrappedCase $wrappedMessage -SourcePath $actualFile.ToUpperInvariant()),
            (Get-SyntheticHeader $wrappedCase $wrappedMessage -SourcePath (Join-Path $script:testRoot 'paired-public/../paired-public/06-reject-wrapped-access.swift')),
            ($actualFile + ':0:0: error: ' + $wrappedMessage),
            ($actualFile + ':9999999999999999999999:1: error: ' + $wrappedMessage)
        )
        foreach ($variant in $variants) {
            $diagnostics = New-SyntheticDiagnostics $wrappedID $variant
            Assert-SyntheticEqual (Invoke-SyntheticAssessment $wrappedID (New-SyntheticProcess 1) $diagnostics $wrappedPriors).observedOutcome 'tool-failure' 'No valid mapped source error was observed.'
        }
        $diagnostics = New-SyntheticDiagnostics $wrappedID (Get-SyntheticHeader $wrappedCase $wrappedMessage -Line 9)
        Assert-SyntheticEqual (Invoke-SyntheticAssessment $wrappedID (New-SyntheticProcess 1) $diagnostics $wrappedPriors).diagnosticQualification 'unclassified-diagnostic' 'Wrong operation anchor cannot qualify.'
        $commonFile = @($script:sourceRecords | Where-Object { $_.relativePath -ceq 'paired-public/00-pure-model.swift' })[0].path
        $diagnostics = New-SyntheticDiagnostics $wrappedID (Get-SyntheticHeader $wrappedCase $wrappedMessage -SourcePath $commonFile)
        Assert-SyntheticEqual (Invoke-SyntheticAssessment $wrappedID (New-SyntheticProcess 1) $diagnostics $wrappedPriors).diagnosticQualification 'unclassified-diagnostic' 'Common model errors are not accessor proof.'
    }
    Invoke-SyntheticCase 'semantic family and literal diagnostic ID are independent' {
        $factory = Get-SwiftUIStateObjectCasePolicy 'paired-public:06-reject-mainactor-factory'
        $constructorError = "call to main actor-isolated initializer 'init(wrappedValue:)' in a synchronous nonisolated context"
        $diagnostics = New-SyntheticDiagnostics $factory.caseID (Get-SyntheticHeader $factory $constructorError)
        $result = Invoke-SyntheticAssessment $factory.caseID (New-SyntheticProcess 1) $diagnostics @(Get-SyntheticPriors $factory.caseID)
        Assert-SyntheticEqual $result.diagnosticQualification 'unclassified-diagnostic' 'Constructor isolation is not helper invocation isolation.'
        $checker = Get-SwiftUIStateObjectCasePolicy 'paired-public:08-direct-capture-checker-control'
        $diagnostics = New-SyntheticDiagnostics $checker.caseID (Get-SyntheticHeader $checker (Get-SyntheticMessage $checker))
        Assert-SyntheticEqual $diagnostics.headers[0].identifier '#SendingRisksDataRace' 'Literal hash in ID preserved.'
        $diagnostics = New-SyntheticDiagnostics $checker.caseID (Get-SyntheticHeader $checker 'unrelated error [#SendingRisksDataRace]')
        Assert-SyntheticEqual (Invoke-SyntheticAssessment $checker.caseID (New-SyntheticProcess 1) $diagnostics @(Get-SyntheticPriors $checker.caseID)).diagnosticQualification 'unclassified-diagnostic' 'An ID alone cannot qualify.'
    }
    Invoke-SyntheticCase 'archived diagnostics use explicit exact capture path mappings' {
        $mapping = [ordered]@{}
        foreach ($source in @(Get-SyntheticSources $wrappedCase)) { $mapping.Add($source.relativePath, ('/original/capture/' + $source.relativePath)) }
        $text = Get-SyntheticHeader $wrappedCase $wrappedMessage -SourcePath $mapping[$wrappedCase.source]
        $path = Write-SyntheticText 'relocated-stderr.log' $text
        $diagnostics = Get-SwiftUIStateObjectDiagnostics -StderrPath $path -Sources @(Get-SyntheticSources $wrappedCase) -Case $wrappedCase -DiagnosticPaths $mapping
        Assert-SyntheticEqual $diagnostics.headers[0].canonicalPath $mapping[$wrappedCase.source] 'Original POSIX capture identity survives Windows replay.'
        Assert-SyntheticEqual $diagnostics.headers[0].classification 'intended-diagnostic' 'Current copied bytes prove the original source operation.'
        $unmapped = Get-SwiftUIStateObjectDiagnostics -StderrPath $path -Sources @(Get-SyntheticSources $wrappedCase) -Case $wrappedCase
        Assert-SyntheticEqual $unmapped.headers[0].classification 'foreign-diagnostic' 'An old path is not inferred without its explicit mapping.'
        $changed = [ordered]@{}
        foreach ($key in $mapping.Keys) { $changed.Add($key, $mapping[$key]) }
        $changed.Remove($wrappedCase.sharedSources[0])
        Assert-SyntheticThrows { Get-SwiftUIStateObjectDiagnostics -StderrPath $path -Sources @(Get-SyntheticSources $wrappedCase) -Case $wrappedCase -DiagnosticPaths $changed } 'exactly'
        $changed.Add($wrappedCase.sharedSources[0], '/original/capture/../case.swift')
        Assert-SyntheticThrows { Get-SwiftUIStateObjectDiagnostics -StderrPath $path -Sources @(Get-SyntheticSources $wrappedCase) -Case $wrappedCase -DiagnosticPaths $changed } 'noncanonical'
        $changed[$wrappedCase.sharedSources[0]] = $changed[$wrappedCase.source]
        Assert-SyntheticThrows { Get-SwiftUIStateObjectDiagnostics -StderrPath $path -Sources @(Get-SyntheticSources $wrappedCase) -Case $wrappedCase -DiagnosticPaths $changed } 'unique canonical'
    }

    foreach ($field in @('attemptID','target','compilerProfileSHA256')) {
        Invoke-SyntheticCase ("dependency boundary " + $field) {
            $priors = @(Copy-SyntheticValue $wrappedPriors)
            $control = @($priors | Where-Object { $_.caseID -ceq 'paired-public:06-mainactor-access' })[0]
            switch ($field) { 'attemptID' { $control.attemptID = 'other-attempt' } 'target' { $control.target = 'arm64-apple-macosx26.5' } default { $control.compilerProfileSHA256 = 'c' * 64 } }
            $diagnostics = New-SyntheticDiagnostics $wrappedID $wrappedHeader
            $result = Invoke-SyntheticAssessment $wrappedID (New-SyntheticProcess 1) $diagnostics $priors
            Assert-SyntheticEqual $result.diagnosticQualification 'prerequisite-not-established' 'Cross-boundary control is not borrowed.'
            Assert-SyntheticEqual $result.prerequisites[0].reason 'different-attempt-target-or-profile' 'Boundary reason preserved.'
            Assert-SyntheticEqual $result.comparisonEligible $false 'Cross-boundary comparison is ineligible.'
        }
    }
    Invoke-SyntheticCase 'dependency ambiguity, future records, and forged control flags' {
        $diagnostics = New-SyntheticDiagnostics $wrappedID $wrappedHeader
        Assert-SyntheticThrows { Invoke-SyntheticAssessment $wrappedID (New-SyntheticProcess 1) $diagnostics (@($wrappedPriors) + @($wrappedPriors[0])) } 'Duplicate prerequisite'
        Assert-SyntheticThrows { Invoke-SyntheticAssessment $wrappedID (New-SyntheticProcess 1) $diagnostics $script:qualifiedResults } 'not a prior'
        $priors = @(Copy-SyntheticValue $wrappedPriors)
        $control = @($priors | Where-Object { $_.caseID -ceq 'paired-public:06-mainactor-access' })[0]
        $control.runtimeEvidence = $true
        Assert-SyntheticThrows { Invoke-SyntheticAssessment $wrappedID (New-SyntheticProcess 1) $diagnostics $priors } 'cannot claim'
        $priors = @(Copy-SyntheticValue $wrappedPriors)
        $control = @($priors | Where-Object { $_.caseID -ceq 'paired-public:06-mainactor-access' })[0]
        $control.observedOutcome = 'source-rejected'; $control.diagnosticQualification = 'intended-diagnostic'
        Assert-SyntheticThrows { Invoke-SyntheticAssessment $wrappedID (New-SyntheticProcess 1) $diagnostics $priors } 'wrong or unqualified'
    }
    Invoke-SyntheticCase 'a diagnostic-bearing admission cannot be promoted into a qualified control' {
        $controlCase = Get-SwiftUIStateObjectCasePolicy 'paired-public:06-mainactor-access'
        $warning = Get-SyntheticHeader -Case $controlCase -Line 10 -Severity 'warning' -Message 'an unclassified source warning'
        $warningPrior = Invoke-SyntheticAssessment $controlCase.caseID (New-SyntheticProcess) (New-SyntheticDiagnostics $controlCase.caseID $warning) @(Get-SyntheticPriors $controlCase.caseID)
        Assert-SyntheticEqual $warningPrior.observedOutcome 'source-admitted' 'Raw warning-bearing admission remains admitted.'
        Assert-SyntheticEqual $warningPrior.controlRequirementMet $null 'Warning-bearing control remains unestablished.'
        Assert-Synthetic ($warningPrior.reviewFlags -ccontains 'source-admission-with-diagnostics') 'Warning limitation is retained.'
        $warningPrior.controlRequirementMet = $true
        $warningPrior.comparisonEligible = $true
        $priors = @($wrappedPriors | ForEach-Object { if ($_.caseID -ceq $controlCase.caseID) { $warningPrior } else { $_ } })
        Assert-SyntheticThrows { Invoke-SyntheticAssessment $wrappedID (New-SyntheticProcess 1) (New-SyntheticDiagnostics $wrappedID $wrappedHeader) $priors } 'Unqualified review flags'
    }
    Invoke-SyntheticCase 'transitive prerequisites cannot survive missing or contradicted ancestors' {
        $directCase = Get-SwiftUIStateObjectCasePolicy 'paired-public:01-direct'
        $text = Get-SyntheticHeader -Case $directCase -Line 9 -Message 'unclassified direct-construction failure'
        $failedDirect = Invoke-SyntheticAssessment $directCase.caseID (New-SyntheticProcess 1) (New-SyntheticDiagnostics $directCase.caseID $text) @()
        foreach ($variation in @('failed','missing','other-target')) {
            $priors = @($wrappedPriors | ForEach-Object {
                if ($_.caseID -cne $directCase.caseID) { $_ }
                elseif ($variation -ceq 'failed') { $failedDirect }
                elseif ($variation -ceq 'other-target') { $changed = Copy-SyntheticValue $_; $changed.target = 'arm64-apple-macosx26.5'; $changed }
            })
            $result = Invoke-SyntheticAssessment $wrappedID (New-SyntheticProcess 1) (New-SyntheticDiagnostics $wrappedID $wrappedHeader) $priors
            Assert-SyntheticEqual $result.diagnosticQualification 'prerequisite-not-established' 'A descendant cannot borrow stale ancestor qualification.'
            Assert-SyntheticEqual $result.prerequisites[0].reason 'control-not-qualified' 'The declared direct dependency is present but its proof chain is not qualified.'
            Assert-SyntheticEqual $result.comparisonEligible $false 'Contradictory or absent ancestor evidence cannot support comparison.'
        }
    }
    Invoke-SyntheticCase 'unsafe admission, attribution, and rejection stay distinct' {
        $witness = Get-SwiftUIStateObjectCasePolicy 'paired-public:08-capture-transfer'
        $priors = @(Get-SyntheticPriors $witness.caseID)
        $diagnostics = New-SyntheticDiagnostics $witness.caseID ''
        $result = Invoke-SyntheticAssessment $witness.caseID (New-SyntheticProcess) $diagnostics $priors
        Assert-SyntheticEqual $result.observedOutcome 'source-admitted' 'Unsafe raw admission.'
        Assert-SyntheticEqual $result.safetyRequirementMet $false 'Admission does not satisfy rejection requirement.'
        Assert-Synthetic ($result.reviewFlags -ccontains 'unsafe-shape-admitted') 'Unsafe shape remains explicit.'
        Assert-SyntheticEqual $result.comparisonEligible $true 'Qualified observation does not mean safety met.'
        $result = Invoke-SyntheticAssessment $witness.caseID (New-SyntheticProcess) $diagnostics @()
        Assert-SyntheticEqual $result.safetyRequirementMet $false 'Missing controls never turn admission into an unknown safety outcome.'
        Assert-SyntheticEqual $result.comparisonEligible $false 'Missing controls limit attribution.'
        $noChecker = @($priors | Where-Object { $_.caseID -cne 'paired-public:08-direct-capture-checker-control' })
        $result = Invoke-SyntheticAssessment $witness.caseID (New-SyntheticProcess) $diagnostics $noChecker
        Assert-Synthetic ($result.reviewFlags -ccontains 'wrapper-specific-attribution-not-established') 'Direct control is required for wrapper-specific admission attribution.'
        $diagnostics = New-SyntheticDiagnostics $witness.caseID (Get-SyntheticHeader $witness (Get-SyntheticMessage $witness))
        $result = Invoke-SyntheticAssessment $witness.caseID (New-SyntheticProcess 1) $diagnostics $noChecker
        Assert-SyntheticEqual $result.safetyRequirementMet $true 'Attribution-only prerequisite does not expand the rejection gate.'
        $diagnostics = New-SyntheticDiagnostics $witness.caseID (Get-SyntheticHeader $witness "main actor-isolated property 'wrappedValue' can not be referenced from a nonisolated context")
        Assert-SyntheticEqual (Invoke-SyntheticAssessment $witness.caseID (New-SyntheticProcess 1) $diagnostics $priors).safetyRequirementMet $null 'An unrelated rejection does not establish static capture safety.'
    }
    Invoke-SyntheticCase 'observation prerequisite requires presence, not admission' {
        $case = Get-SwiftUIStateObjectCasePolicy 'paired-public:07-observable-protocol-confound'
        $priorCase = Get-SwiftUIStateObjectCasePolicy 'paired-public:07-observable-protocol-control'
        $text = Get-SyntheticHeader -Case $priorCase -Line 9 -Message 'unclassified model-isolation observation'
        $prior = Invoke-SyntheticAssessment $priorCase.caseID (New-SyntheticProcess 1) (New-SyntheticDiagnostics $priorCase.caseID $text) @()
        Assert-SyntheticEqual $prior.comparisonEligible $false 'Unclassified source observation stays unqualified.'
        $result = Invoke-SyntheticAssessment $case.caseID (New-SyntheticProcess) (New-SyntheticDiagnostics $case.caseID '') @($prior)
        Assert-SyntheticEqual $result.prerequisites[0].established $true 'A raw ordinary rejection is still an earlier observation.'
    }

    $directID = 'paired-public:01-direct'
    $emptyDiagnostics = New-SyntheticDiagnostics $directID ''
    foreach ($scenario in @('missing-sil','empty-sil','oversize-sil','open-stream','unfinished-cleanup','integrity-issue','output-limit')) {
        Invoke-SyntheticCase ("artifact outcome " + $scenario) {
            $process = New-SyntheticProcess
            switch ($scenario) {
                'missing-sil' { $process.sil = $null }
                'empty-sil' { $process.sil.bytes = 0 }
                'oversize-sil' { $process.sil.bytes = 8388609 }
                'open-stream' { $process.allRedirectedStreamsClosed = $false }
                'unfinished-cleanup' { $process.terminationCompleted = $false }
                'integrity-issue' { $process.artifactIssues = @('source-hash-changed') }
                'output-limit' { $process.outputLimitExceeded = $true; $process.abnormalTermination = $true }
            }
            Assert-SyntheticEqual (Invoke-SyntheticAssessment $directID $process $emptyDiagnostics).observedOutcome 'artifact-failure' 'Artifact failure cannot be source admission.'
        }
    }
    Invoke-SyntheticCase 'timeout and abnormal compiler results are not source rejection' {
        $process = New-SyntheticProcess 1
        $process.timedOut = $true; $process.exitCode = $null; $process.allRedirectedStreamsClosed = $false; $process.terminationCompleted = $false
        Assert-SyntheticEqual (Invoke-SyntheticAssessment $directID $process (New-SwiftUIStateObjectEmptyDiagnostics)).observedOutcome 'timeout' 'Timeout retains its own outcome.'
        foreach ($code in @(2,-1073741819)) {
            Assert-SyntheticEqual (Invoke-SyntheticAssessment $directID (New-SyntheticProcess $code) $emptyDiagnostics).observedOutcome 'tool-failure' 'Abnormal exit is not rejection.'
        }
        $crash = New-SyntheticDiagnostics $directID ('Stack dump:' + [char]10 + '0. Program arguments')
        Assert-Synthetic $crash.hasCrashMarker 'Crash marker preserved.'
        Assert-SyntheticEqual (Invoke-SyntheticAssessment $directID (New-SyntheticProcess 1) $crash).observedOutcome 'tool-failure' 'Crash despite exit1 is not a negative control.'
        foreach ($text in @('', 'note: only a note', 'error: unlocated unknown failure')) {
            Assert-SyntheticEqual (Invoke-SyntheticAssessment $directID (New-SyntheticProcess 1) (New-SyntheticDiagnostics $directID $text)).observedOutcome 'tool-failure' 'Exit1 without a source error cannot complete an ordinary source case.'
        }
    }
    Invoke-SyntheticCase 'configuration errors remain separate' {
        foreach ($text in @("error: unknown argument: '-invented'", "error: unable to load standard library for target 'unsupported'", '/SDK/SwiftUI.swiftinterface:10:2: error: unrelated SDK declaration failure')) {
            $diagnostics = New-SyntheticDiagnostics $directID $text
            Assert-Synthetic $diagnostics.hasConfigurationFailure 'Configuration flag preserved.'
            Assert-SyntheticEqual (Invoke-SyntheticAssessment $directID (New-SyntheticProcess 1) $diagnostics).observedOutcome 'unsupported-configuration' 'Configuration failure is not source rejection.'
        }
        $case = Get-SwiftUIStateObjectCasePolicy $directID
        $text = Get-SyntheticHeader -Case $case -Line 4 -Message "no such module 'WinSwiftUI'"
        Assert-SyntheticEqual (Invoke-SyntheticAssessment $directID (New-SyntheticProcess 1) (New-SyntheticDiagnostics $directID $text)).observedOutcome 'unsupported-configuration' 'Wrong conditional-import branch cannot satisfy a source case.'
    }
    Invoke-SyntheticCase 'not-run null rules and launch failure' {
        $process = New-SyntheticProcess
        $process.processStarted = $false; $process.exitCode = $null; $process.sil = $null; $process.notRunReason = 'cancelled-before-launch'
        $diagnostics = New-SwiftUIStateObjectEmptyDiagnostics
        Assert-SyntheticEqual (Invoke-SyntheticAssessment $directID $process $diagnostics).observedOutcome 'not-run' 'Intentional not-run.'
        foreach ($field in @('exitCode','sil','notRunReason','timedOut')) {
            $changed = Copy-SyntheticValue $process
            switch ($field) { 'exitCode' { $changed.exitCode = 0 } 'sil' { $changed.sil = (New-SyntheticProcess).sil } 'notRunReason' { $changed.notRunReason = $null } 'timedOut' { $changed.timedOut = $true } }
            Assert-SyntheticThrows { Invoke-SyntheticAssessment $directID $changed $diagnostics } 'unlaunched'
        }
        $process.notRunReason = $null; $process.error = 'fabricated launch error'
        Assert-SyntheticEqual (Invoke-SyntheticAssessment $directID $process $diagnostics).observedOutcome 'tool-failure' 'Launch failure is not intentional not-run.'
    }
    Invoke-SyntheticCase 'strict process and diagnostic DTO integrity' {
        $process = New-SyntheticProcess
        $process.processStarted = 1
        Assert-SyntheticThrows { Invoke-SyntheticAssessment $directID $process $emptyDiagnostics } 'Boolean'
        $process = New-SyntheticProcess
        $process | Add-Member -NotePropertyName assumedPassed -NotePropertyValue $true
        Assert-SyntheticThrows { Invoke-SyntheticAssessment $directID $process $emptyDiagnostics } 'unknown'
        $process = New-SyntheticProcess
        $process.sil.sha256 = 'BAD'
        Assert-SyntheticThrows { Invoke-SyntheticAssessment $directID $process $emptyDiagnostics } 'SHA256'
        $process = New-SyntheticProcess
        $process.sil.path = '../escape.sil'
        Assert-SyntheticThrows { Invoke-SyntheticAssessment $directID $process $emptyDiagnostics } 'relative path'
        Assert-SyntheticEqual (Invoke-SyntheticAssessment $directID (New-SyntheticProcess) (New-SwiftUIStateObjectEmptyDiagnostics)).observedOutcome 'artifact-failure' 'A missing diagnostic stream is not clean evidence.'
        $diagnostics = New-SyntheticDiagnostics $wrappedID $wrappedHeader
        Assert-SyntheticEqual (Invoke-SyntheticAssessment $wrappedID (New-SyntheticProcess) $diagnostics $wrappedPriors).observedOutcome 'artifact-failure' 'Exit0 plus a primary error is inconsistent.'
        $diagnostics.headers[0].message = 'unrelated failure'
        Assert-SyntheticThrows { Invoke-SyntheticAssessment $wrappedID (New-SyntheticProcess 1) $diagnostics $wrappedPriors } 'classification disagrees'
    }
    Invoke-SyntheticCase 'parsed path, position, and crash claims cannot be mutated independently' {
        $diagnostics = New-SyntheticDiagnostics $wrappedID $wrappedHeader
        $diagnostics.headers[0].rawPath = '/unrelated.swift'
        Assert-SyntheticThrows { Invoke-SyntheticAssessment $wrappedID (New-SyntheticProcess 1) $diagnostics $wrappedPriors } 'raw and canonical'
        $diagnostics = New-SyntheticDiagnostics $wrappedID $wrappedHeader
        $diagnostics.headers[0].column = 9999
        Assert-SyntheticThrows { Invoke-SyntheticAssessment $wrappedID (New-SyntheticProcess 1) $diagnostics $wrappedPriors } 'source position flag'
        $diagnostics = New-SyntheticDiagnostics $wrappedID (Get-SyntheticHeader $wrappedCase 'LLVM ERROR: fabricated crash')
        Assert-Synthetic $diagnostics.hasCrashMarker 'Source-located crash marker is retained.'
        $diagnostics.hasCrashMarker = $false
        Assert-SyntheticThrows { Invoke-SyntheticAssessment $wrappedID (New-SyntheticProcess 1) $diagnostics $wrappedPriors } 'crash message'
        $diagnostics = New-SyntheticDiagnostics $wrappedID 'swiftc: error: emit-module command failed due to signal 11'
        Assert-Synthetic $diagnostics.hasCrashMarker 'Driver crash marker is retained.'
        $diagnostics.hasCrashMarker = $false
        Assert-SyntheticThrows { Invoke-SyntheticAssessment $wrappedID (New-SyntheticProcess 1) $diagnostics $wrappedPriors } 'driver crash'
    }
    Invoke-SyntheticCase 'every standalone or note-prefixed crash flag retains its evidence' {
        foreach ($marker in @(
            'LLVM ERROR: fabricated crash', 'Stack dump:',
            'note: LLVM ERROR: fabricated crash',
            '/tool/path/unknown-frontend: note: LLVM ERROR: fabricated crash',
            ('LLVM ERROR: quoted ' + (Get-SyntheticHeader -Case $wrappedCase -Message 'quoted' -Severity 'note'))
        )) {
            $diagnostics = New-SyntheticDiagnostics $wrappedID ($wrappedHeader + $newline + $marker)
            Assert-Synthetic $diagnostics.hasCrashMarker 'A recognized standalone or note-prefixed crash is preserved.'
            Assert-SyntheticEqual $diagnostics.unrecognizedPrimaryLines.Count 1 'Every non-located crash marker has one retained physical line.'
            Assert-SyntheticEqual $diagnostics.unrecognizedPrimaryLines[0].text $marker 'Retained crash text is exact.'
            Assert-SyntheticEqual (Invoke-SyntheticAssessment $wrappedID (New-SyntheticProcess 1) $diagnostics $wrappedPriors).observedOutcome 'tool-failure' 'An intended source error cannot qualify beside a crash.'
            $diagnostics.hasCrashMarker = $false
            Assert-SyntheticThrows { Invoke-SyntheticAssessment $wrappedID (New-SyntheticProcess 1) $diagnostics $wrappedPriors } 'crash'
        }
    }
    Invoke-SyntheticCase 'diagnostic bytes, mapping hashes, and invalid stream framing' {
        $path = Join-Path $script:testRoot 'invalid-stderr.log'
        [System.IO.File]::WriteAllBytes($path, [byte[]]@(195,40))
        Assert-SyntheticThrows { Get-SwiftUIStateObjectDiagnostics -StderrPath $path -Sources @(Get-SyntheticSources $wrappedCase) -Case $wrappedCase } ''
        foreach ($text in @('bad'+[char]0+'text', 'bad'+[char]13+'text')) {
            $path = Write-SyntheticText 'bad-framing.log' $text
            Assert-SyntheticThrows { Get-SwiftUIStateObjectDiagnostics -StderrPath $path -Sources @(Get-SyntheticSources $wrappedCase) -Case $wrappedCase } 'Diagnostic text'
        }
        $sources = @(Copy-SyntheticValue @(Get-SyntheticSources $wrappedCase))
        $sources[0].sha256 = 'd' * 64
        $path = Write-SyntheticText 'clean-stderr.log' ''
        Assert-SyntheticThrows { Get-SwiftUIStateObjectDiagnostics -StderrPath $path -Sources $sources -Case $wrappedCase } 'frozen public inputs'
        $sourceRecord = @($script:sourceRecords | Where-Object { $_.relativePath -ceq $wrappedCase.source })[0]
        $originalBytes = [System.IO.File]::ReadAllBytes($sourceRecord.path)
        try {
            [System.IO.File]::WriteAllBytes($sourceRecord.path, ($originalBytes + [byte[]]@(32)))
            Assert-SyntheticThrows { Get-SwiftUIStateObjectDiagnostics -StderrPath $path -Sources @(Get-SyntheticSources $wrappedCase) -Case $wrappedCase } 'diagnostic source changed'
        } finally { [System.IO.File]::WriteAllBytes($sourceRecord.path, $originalBytes) }
    }
    Invoke-SyntheticCase 'separate arm64 context must establish its own controls' {
        $results = [System.Collections.Generic.List[object]]::new()
        foreach ($case in $script:casePolicies) {
            $process = New-SyntheticProcess
            $text = ''
            if ($null -ne $case.diagnosticExpectation) { $process = New-SyntheticProcess 1; $text = Get-SyntheticHeader $case (Get-SyntheticMessage $case) }
            $result = Invoke-SyntheticAssessment -CaseID $case.caseID -Process $process -Diagnostics (New-SyntheticDiagnostics $case.caseID $text) -Prior $results.ToArray() -Target 'arm64-apple-macosx26.5'
            Assert-Synthetic $result.comparisonEligible 'Each independent arm64 observation has local prerequisites.'
            $results.Add($result)
        }
        Assert-SyntheticEqual ($results.Count + $script:qualifiedResults.Count) 42 'Exactly 42 synthetic native cells, with no compiler invocation.'
    }
    Invoke-SyntheticCase 'frozen fixture files remain unchanged' {
        foreach ($before in $script:originalHashes) {
            $after = Get-SwiftUIStateObjectFileHash -Path $before.path -MaxBytes 262144
            Assert-SyntheticEqual $after.sha256 $before.sha256 'Original fixture bytes changed.'
            Assert-SyntheticEqual $after.bytes $before.bytes 'Original fixture byte count changed.'
        }
    }
} catch {
    $script:failures.Add("Harness setup/dependency failure: $($_.Exception.Message)")
} finally {
    if (-not $KeepArtifacts) {
        $resolvedRoot = [System.IO.Path]::GetFullPath($script:testRoot)
        $expectedRoot = [System.IO.Path]::GetFullPath((Join-Path ([System.IO.Path]::GetTempPath()) $testDirectoryName))
        if ($resolvedRoot -cne $expectedRoot -or [System.IO.Path]::GetFileName($resolvedRoot) -cne $testDirectoryName) { throw 'Refusing cleanup outside the exact owned synthetic test directory.' }
        $rootItem = Get-Item -LiteralPath $resolvedRoot -Force -ErrorAction SilentlyContinue
        if ($null -ne $rootItem) {
            if ($rootItem -isnot [System.IO.DirectoryInfo] -or ($rootItem.Attributes -band [System.IO.FileAttributes]::ReparsePoint)) { throw 'Refusing recursive cleanup of an aliased synthetic root.' }
            Remove-Item -LiteralPath $resolvedRoot -Recurse -Force
        }
    }
}

foreach ($skip in $script:skips) { Write-Output "SKIP: $skip" }
if ($script:failures.Count -gt 0) {
    foreach ($failure in $script:failures) { Write-Output "FAIL: $failure" }
    Write-Output ("FAILED: {0} assertions, {1} synthetic cases, PowerShell {2}. No compiler or UI execution." -f $script:assertionCount, $script:testCount, $PSVersionTable.PSVersion)
    if ($KeepArtifacts) { Write-Output "Synthetic artifacts: $script:testRoot" }
    exit 1
}
Write-Output ("PASSED: {0} assertions, {1} synthetic cases, PowerShell {2}. No compiler or UI execution." -f $script:assertionCount, $script:testCount, $PSVersionTable.PSVersion)
if ($KeepArtifacts) { Write-Output "Synthetic artifacts: $script:testRoot" }
