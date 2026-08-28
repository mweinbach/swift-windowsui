# Bounded RGB-constructor evidence helpers. Importing runs no native command,
# Swift compiler, SwiftPM build, reference executable, or inventory reader.
. (Join-Path $PSScriptRoot "swiftui-material-reference-common.ps1")

function Get-SwiftUIColorRGBProtocol {
    return [pscustomobject][ordered]@{
        schemaVersion = 1
        protocolId = "canonical-rgb-constructor-v1"
        caseSetId = "canonical-rgb-finite-23-plus-exploratory-p3-2-v1"
        componentEncoding = "extended-srgb-encoded-unpremultiplied"
        toleranceId = "float32-absolute-2e-6-relative-16epsilon-alpha-2epsilon-v1"
        repetitions = 3
        absoluteRGB = 0.000002
        relativeRGB = (16.0 * 1.1920928955078125e-7)
        absoluteAlpha = (2.0 * 1.1920928955078125e-7)
    }
}

function Get-SwiftUIColorRGBSourceNames {
    return @(
        "Sources/swiftui-color-rgb-reference/RGBConstructorCases.swift",
        "Sources/swiftui-color-rgb-reference/RGBObservation.swift",
        "Sources/swiftui-color-rgb-reference/NativeColorRGBObservation.swift",
        "Sources/swiftui-color-rgb-reference/WindowsColorRGBObservation.swift",
        "Sources/swiftui-color-rgb-reference/ColorRGBReferenceMain.swift"
    )
}

function Get-SwiftUIColorRGBCases {
    $rows = @(
        @("srgb-zero", "srgb", 0, 0, 0, 1),
        @("srgb-white", "srgb", 1, 1, 1, 1),
        @("srgb-interior", "srgb", 0.25, 0.5, 0.75, 1),
        @("srgb-extended", "srgb", -0.5, 1.25, 2, 1),
        @("srgb-alpha-zero", "srgb", 0.25, 0.5, 0.75, 0),
        @("srgb-alpha-fraction", "srgb", 0.25, 0.5, 0.75, 0.625),
        @("linear-zero", "srgb-linear", 0, 0, 0, 1),
        @("linear-white", "srgb-linear", 1, 1, 1, 1),
        @("linear-interior", "srgb-linear", 0.25, 0.5, 0.75, 1),
        @("linear-low", "srgb-linear", 0.001, 0.0030, 0.0032, 1),
        @("linear-negative-low", "srgb-linear", -0.001, -0.0030, -0.0032, 1),
        @("linear-extended", "srgb-linear", -0.25, 0.5, 2, 1),
        @("linear-alpha-zero", "srgb-linear", 0.25, 0.5, 0.75, 0),
        @("linear-alpha-fraction", "srgb-linear", 0.25, 0.5, 0.75, 0.625),
        @("p3-zero", "display-p3", 0, 0, 0, 1),
        @("p3-white", "display-p3", 1, 1, 1, 1),
        @("p3-neutral", "display-p3", 0.5, 0.5, 0.5, 1),
        @("p3-interior", "display-p3", 0.1, 0.2, 0.3, 1),
        @("p3-red", "display-p3", 1, 0, 0, 1),
        @("p3-green", "display-p3", 0, 1, 0, 1),
        @("p3-blue", "display-p3", 0, 0, 1, 1),
        @("p3-alpha-zero", "display-p3", 1, 0, 0, 0),
        @("p3-alpha-fraction", "display-p3", 1, 0, 0, 0.625),
        @("p3-extended-input", "display-p3", 1.2, -0.2, 0.5, 1),
        @("p3-negative-input", "display-p3", -0.1, -0.2, -0.3, 1)
    )
    foreach ($row in $rows) {
        $domain = "required-finite"
        if ($row[0] -cin @("p3-extended-input", "p3-negative-input")) { $domain = "exploratory-extended-p3" }
        [pscustomobject][ordered]@{
            caseId = $row[0]; domain = $domain; sourceSpace = $row[1]
            input = [pscustomobject][ordered]@{
                red = [double]$row[2]; green = [double]$row[3]
                blue = [double]$row[4]; opacity = [double]$row[5]
            }
        }
    }
}

function Get-SwiftUIColorRGBBits {
    param([double]$Value, [ValidateSet("float32", "float64")][string]$Storage = "float64")
    if ($Storage -ceq "float32") {
        return [BitConverter]::ToInt32([BitConverter]::GetBytes([single]$Value), 0).ToString("x8")
    }
    return [BitConverter]::DoubleToInt64Bits($Value).ToString("x16")
}

function New-SwiftUIColorRGBNumber {
    param([double]$Value, [ValidateSet("float32", "float64")][string]$Storage = "float64")
    if ($Storage -ceq "float32") { $Value = [double][single]$Value }
    $kind = "finite"; $jsonValue = $Value
    if ([double]::IsNaN($Value)) { $kind = "nan"; $jsonValue = $null }
    elseif ([double]::IsPositiveInfinity($Value)) { $kind = "positive-infinity"; $jsonValue = $null }
    elseif ([double]::IsNegativeInfinity($Value)) { $kind = "negative-infinity"; $jsonValue = $null }
    return [pscustomobject][ordered]@{
        kind = $kind; value = $jsonValue; storage = $Storage
        bitPattern = Get-SwiftUIColorRGBBits -Value $Value -Storage $Storage
    }
}

function Assert-SwiftUIColorRGBObject {
    param($Value, [string]$Name, [string[]]$Keys)
    if ($Value -isnot [pscustomobject]) { throw "RGB_INVALID_OBJECT: $Name" }
    $actual = @($Value.PSObject.Properties | ForEach-Object { $_.Name })
    if ($actual.Count -ne $Keys.Count) { throw "RGB_INVALID_FIELDS: $Name" }
    foreach ($key in $Keys) {
        if ($actual -cnotcontains $key) { throw "RGB_INVALID_FIELDS: $Name.$key" }
    }
}

function Assert-SwiftUIColorRGBString {
    param($Value, [string]$Name, [switch]$AllowEmpty, [int]$MaxLength = 4096)
    if ($Value -isnot [string] -or $Value.Length -gt $MaxLength -or
        (-not $AllowEmpty -and [string]::IsNullOrWhiteSpace($Value))) { throw "RGB_INVALID_STRING: $Name" }
}

function Assert-SwiftUIColorRGBInteger {
    param($Value, [string]$Name, [long]$Minimum = 0, [long]$Maximum = 2147483647)
    if (($Value -isnot [int] -and $Value -isnot [long]) -or $Value -lt $Minimum -or $Value -gt $Maximum) {
        throw "RGB_INVALID_INTEGER: $Name"
    }
}

function Assert-SwiftUIColorRGBBoolean {
    param($Value, [string]$Name)
    if ($Value -isnot [bool]) { throw "RGB_INVALID_BOOLEAN: $Name" }
}

function Assert-SwiftUIColorRGBArray {
    param($Value, [string]$Name, [int]$Minimum = 0, [int]$Maximum = 4096)
    if ($Value -isnot [System.Array] -or $Value.Count -lt $Minimum -or $Value.Count -gt $Maximum) {
        throw "RGB_INVALID_ARRAY: $Name"
    }
}

function Initialize-SwiftUIColorRGBJsonHelper {
    # This managed helper parses grammar only. PowerShell still constructs the
    # DTOs, and ReadNumber independently enforces numeric value/IEEE identity.
    # The type name and constant are bound to this exact source template. A
    # long-lived PowerShell session cannot silently reuse a stale implementation.
    $template = @'
using System;
using System.Collections.Generic;
using System.IO;
using System.Text;
namespace SwiftUIColorRGB.Evidence {
    public sealed class __TYPE__ {
        public const string SourceIdentity = "__SOURCE_HASH__";
        private readonly string text;
        private int position;
        private int tokens;
        private __TYPE__(string value) { text = value; }
        private void Fail(string code) { throw new InvalidDataException(code); }
        private void Token() { if (++tokens > 500000) Fail("RGB_JSON_TOKEN_LIMIT"); }
        private void White() {
            while (position < text.Length) {
                char c = text[position];
                if (c != ' ' && c != '\t' && c != '\r' && c != '\n') break;
                position++;
            }
        }
        private char Peek() { return position < text.Length ? text[position] : '\0'; }
        private void Punctuation(char expected) {
            White();
            if (position >= text.Length || text[position++] != expected) Fail("RGB_INVALID_JSON_DELIMITER");
            Token();
        }
        private int Hex() {
            if (position >= text.Length) { Fail("RGB_INCOMPLETE_JSON_ESCAPE"); return 0; }
            char c = text[position++];
            if (c >= '0' && c <= '9') return c - '0';
            if (c >= 'a' && c <= 'f') return c - 'a' + 10;
            if (c >= 'A' && c <= 'F') return c - 'A' + 10;
            Fail("RGB_INVALID_JSON_ESCAPE"); return 0;
        }
        private char Unicode() { return (char)((Hex() << 12) | (Hex() << 8) | (Hex() << 4) | Hex()); }
        private string String() {
            White();
            if (position >= text.Length || text[position++] != '"') Fail("RGB_INVALID_JSON_STRING");
            Token();
            StringBuilder value = new StringBuilder();
            while (position < text.Length) {
                char c = text[position++];
                if (c == '"') return value.ToString();
                if (c < 0x20) Fail("RGB_INVALID_JSON_STRING_CONTROL");
                if (c == '\\') {
                    if (position >= text.Length) Fail("RGB_INCOMPLETE_JSON_ESCAPE");
                    char escape = text[position++];
                    switch (escape) {
                        case '"': value.Append('"'); break;
                        case '\\': value.Append('\\'); break;
                        case '/': value.Append('/'); break;
                        case 'b': value.Append('\b'); break;
                        case 'f': value.Append('\f'); break;
                        case 'n': value.Append('\n'); break;
                        case 'r': value.Append('\r'); break;
                        case 't': value.Append('\t'); break;
                        case 'u':
                            char unit = Unicode();
                            if (Char.IsHighSurrogate(unit)) {
                                if (position + 1 >= text.Length || text[position] != '\\' || text[position + 1] != 'u') Fail("RGB_INVALID_JSON_SURROGATE");
                                position += 2;
                                char low = Unicode();
                                if (!Char.IsLowSurrogate(low)) Fail("RGB_INVALID_JSON_SURROGATE");
                                value.Append(unit); value.Append(low);
                            } else {
                                if (Char.IsLowSurrogate(unit)) Fail("RGB_INVALID_JSON_SURROGATE");
                                value.Append(unit);
                            }
                            break;
                        default: Fail("RGB_INVALID_JSON_ESCAPE"); break;
                    }
                } else if (Char.IsHighSurrogate(c)) {
                    if (position >= text.Length || !Char.IsLowSurrogate(text[position])) Fail("RGB_INVALID_JSON_SURROGATE");
                    value.Append(c); value.Append(text[position++]);
                } else {
                    if (Char.IsLowSurrogate(c)) Fail("RGB_INVALID_JSON_SURROGATE");
                    value.Append(c);
                }
            }
            Fail("RGB_INCOMPLETE_JSON_STRING"); return null;
        }
        private static bool Digit(char c) { return c >= '0' && c <= '9'; }
        private void Number() {
            Token();
            if (Peek() == '-') position++;
            char c = Peek();
            if (c == '0') {
                position++;
                if (Digit(Peek())) Fail("RGB_INVALID_JSON_NUMBER");
            } else {
                if (c < '1' || c > '9') Fail("RGB_INVALID_JSON_NUMBER");
                do { position++; } while (Digit(Peek()));
            }
            if (Peek() == '.') {
                position++;
                if (!Digit(Peek())) Fail("RGB_INVALID_JSON_NUMBER");
                do { position++; } while (Digit(Peek()));
            }
            if (Peek() == 'e' || Peek() == 'E') {
                position++;
                if (Peek() == '+' || Peek() == '-') position++;
                if (!Digit(Peek())) Fail("RGB_INVALID_JSON_NUMBER");
                do { position++; } while (Digit(Peek()));
            }
        }
        private void Literal(string expected) {
            Token();
            if (position + expected.Length > text.Length || System.String.CompareOrdinal(text, position, expected, 0, expected.Length) != 0) Fail("RGB_INVALID_JSON_LITERAL");
            position += expected.Length;
        }
        private void Value(int depth) {
            White();
            if (position >= text.Length) Fail("RGB_INCOMPLETE_JSON");
            char c = Peek();
            if (c == '{') Object(depth + 1);
            else if (c == '[') Array(depth + 1);
            else if (c == '"') String();
            else if (c == 't') Literal("true");
            else if (c == 'f') Literal("false");
            else if (c == 'n') Literal("null");
            else if (c == '-' || Digit(c)) Number();
            else Fail("RGB_INVALID_JSON_VALUE");
        }
        private void Object(int depth) {
            if (depth > 48) Fail("RGB_JSON_DEPTH_LIMIT");
            Punctuation('{'); White();
            HashSet<string> keys = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
            if (Peek() == '}') { Punctuation('}'); return; }
            while (true) {
                string key = String();
                // The PS5 JSON reader consumes this reserved metadata key.
                // Reject it before any host reader can silently discard data.
                if (System.String.Equals(key, "__type", StringComparison.OrdinalIgnoreCase)) Fail("RGB_JSON_RESERVED_KEY");
                if (!keys.Add(key)) Fail("RGB_DUPLICATE_JSON_KEY");
                Punctuation(':'); Value(depth); White();
                if (Peek() == '}') { Punctuation('}'); return; }
                Punctuation(',');
                White();
                if (Peek() == '}') Fail("RGB_INVALID_JSON_OBJECT_KEY");
            }
        }
        private void Array(int depth) {
            if (depth > 48) Fail("RGB_JSON_DEPTH_LIMIT");
            Punctuation('['); White();
            if (Peek() == ']') { Punctuation(']'); return; }
            while (true) {
                Value(depth); White();
                if (Peek() == ']') { Punctuation(']'); return; }
                Punctuation(',');
                White();
                if (Peek() == ']') Fail("RGB_INVALID_JSON_VALUE");
            }
        }
        public static void Validate(string text) {
            if (text == null) throw new InvalidDataException("RGB_INCOMPLETE_JSON");
            __TYPE__ parser = new __TYPE__(text);
            parser.White();
            if (parser.Peek() != '{') parser.Fail("RGB_JSON_ROOT_MUST_BE_OBJECT");
            parser.Object(1);
            parser.White();
            if (parser.position != text.Length) parser.Fail("RGB_INVALID_JSON_TRAILING_CONTENT");
        }
    }
}
'@
    $templateHash = Get-SwiftUIBaselineTextHash $template
    $typeShortName = "Parser_" + $templateHash
    $typeName = "SwiftUIColorRGB.Evidence." + $typeShortName
    $source = $template.Replace("__TYPE__", $typeShortName).Replace("__SOURCE_HASH__", $templateHash)
    $type = $typeName -as [type]
    if ($null -eq $type) {
        Add-Type -TypeDefinition $source -Language CSharp -ErrorAction Stop
        $type = $typeName -as [type]
    }
    if ($null -eq $type -or $type.GetField("SourceIdentity").GetRawConstantValue() -cne $templateHash) { throw "RGB_JSON_HELPER_SOURCE_MISMATCH" }
    return [pscustomobject]@{ type = $type; templateSha256 = $templateHash; compiledSourceSha256 = Get-SwiftUIBaselineTextHash $source }
}

function Assert-SwiftUIColorRGBJsonGrammar {
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Text)
    $helper = Initialize-SwiftUIColorRGBJsonHelper
    try { [void]$helper.type.GetMethod("Validate").Invoke($null, [object[]]@($Text)) } catch {
        $errorObject = $_.Exception
        while ($null -ne $errorObject.InnerException) { $errorObject = $errorObject.InnerException }
        if ($errorObject.Message -cmatch '^RGB_[A-Z0-9_]+$') { throw $errorObject.Message }
        throw "RGB_JSON_HELPER_FAILURE"
    }
}

function Get-SwiftUIColorRGBJsonParserIdentity {
    $helper = Initialize-SwiftUIColorRGBJsonHelper
    $assemblies = @(
        foreach ($assembly in [AppDomain]::CurrentDomain.GetAssemblies()) {
            if ($assembly.GetName().Name -cnotin @("Microsoft.CSharp", "System.CodeDom", "Microsoft.CodeAnalysis", "Microsoft.CodeAnalysis.CSharp", "System.Management.Automation", "mscorlib", "System.Private.CoreLib")) { continue }
            $location = $assembly.Location
            [pscustomobject]@{
                name = $assembly.GetName().Name; fullName = $assembly.FullName
                location = $location
                sha256 = $(if (-not [string]::IsNullOrEmpty($location) -and (Test-Path -LiteralPath $location -PathType Leaf)) { Get-SwiftUIColorRGBHash $location } else { $null })
            }
        }
    )
    $compilerCandidate = $null
    if ($PSVersionTable.PSVersion.Major -lt 7) {
        $path = Join-Path ([Runtime.InteropServices.RuntimeEnvironment]::GetRuntimeDirectory()) "csc.exe"
        if (Test-Path -LiteralPath $path -PathType Leaf) {
            $compilerCandidate = [pscustomobject]@{ path = $path; sha256 = Get-SwiftUIColorRGBHash $path; identification = "Framework compiler file metadata; compiler process invocation not independently observed" }
        }
    }
    $hostPath = [Diagnostics.Process]::GetCurrentProcess().MainModule.FileName
    return [pscustomobject]@{
        implementation = "bounded-managed-json-grammar-v1"; templateSha256 = $helper.templateSha256
        compiledSourceSha256 = $helper.compiledSourceSha256; typeName = $helper.type.FullName
        generatedAssembly = $helper.type.Assembly.FullName; managedHelperCompilation = $true
        powerShellVersion = $PSVersionTable.PSVersion.ToString(); clrVersion = [Environment]::Version.ToString()
        hostProcess = [pscustomobject]@{ path = $hostPath; sha256 = Get-SwiftUIColorRGBHash $hostPath; processId = $PID; fileVersion = [Diagnostics.FileVersionInfo]::GetVersionInfo($hostPath).FileVersion }
        assemblyMetadata = $assemblies; compilerFileCandidate = $compilerCandidate
        swiftCompilerExecuted = $false; swiftPMExecuted = $false; nativeColorObserverExecuted = $false
        scope = "Managed JSON helper only; no Swift compiler, SwiftPM, color observer, or native fixture execution"
    }
}

function ConvertFrom-SwiftUIColorRGBJsonToken {
    param([Parameter(Mandatory)]$Token, [int]$Depth = 1)
    # Only reached after the bounded strict grammar check. This projection is
    # for PowerShell versions whose public JSON cmdlet cannot preserve dates
    # as strings; it never reconstructs text from a parsed DateTime.
    $kind = $Token.get_Type().ToString()
    if ($kind -cin @("Object", "Array") -and $Depth -gt 48) { throw "RGB_JSON_DEPTH_LIMIT" }
    if ($kind -ceq "Object") {
        $properties = [ordered]@{}
        foreach ($property in $Token.Properties()) {
            $properties.Add($property.get_Name(), (ConvertFrom-SwiftUIColorRGBJsonToken $property.get_Value() ($Depth + 1)))
        }
        return [pscustomobject]$properties
    }
    if ($kind -ceq "Array") {
        $values = [System.Collections.Generic.List[object]]::new()
        foreach ($item in $Token.Children()) { $values.Add((ConvertFrom-SwiftUIColorRGBJsonToken $item ($Depth + 1))) }
        return ,$values.ToArray()
    }
    if ($kind -ceq "Null") { return $null }
    if ($kind -cin @("String", "Integer", "Float", "Boolean")) { return $Token.get_Value() }
    throw "RGB_JSON_UNEXPECTED_DESERIALIZED_TYPE"
}

function ConvertFrom-SwiftUIColorRGBJsonText {
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Text, [switch]$ForceNewtonsoftFallback)
    Assert-SwiftUIColorRGBJsonGrammar -Text $Text
    try {
        $reader = Get-Command ConvertFrom-Json -CommandType Cmdlet -ErrorAction Stop
        if (-not $ForceNewtonsoftFallback -and $reader.Parameters.ContainsKey("DateKind")) {
            return (ConvertFrom-Json -InputObject $Text -DateKind String -ErrorAction Stop)
        }
        if (-not $ForceNewtonsoftFallback -and $PSVersionTable.PSVersion.Major -le 5) {
            # PS5 treats the legacy escaped spelling "\/Date(0)\/" as a
            # DateTime. Removing only a JSON slash escape is semantically
            # identical JSON and prevents that coercion. Preserve every pair
            # of escaped backslashes; do not rewrite any numeric token or the
            # archived source bytes. Grammar was checked before this step.
            $slashEscapes = [regex]::new('(?<!\\)((?:\\\\)*)\\/', [Text.RegularExpressions.RegexOptions]::CultureInvariant, [TimeSpan]::FromSeconds(5))
            $ps5Text = $slashEscapes.Replace($Text, '$1/')
            return (ConvertFrom-Json -InputObject $ps5Text -ErrorAction Stop)
        }
        # Load only the JSON implementation already supplied by PowerShell.
        # Its permissive grammar is never the acceptance gate: the strict
        # source-bound helper above has already rejected JSON extensions.
        $null = ConvertFrom-Json -InputObject '{}' -ErrorAction Stop
        $settingsType = "Newtonsoft.Json.JsonSerializerSettings" -as [type]
        $convertType = "Newtonsoft.Json.JsonConvert" -as [type]
        if ($null -eq $settingsType -or $null -eq $convertType) { throw "RGB_JSON_READER_UNAVAILABLE" }
        $settings = [Activator]::CreateInstance($settingsType)
        $settings.DateParseHandling = [Enum]::Parse(("Newtonsoft.Json.DateParseHandling" -as [type]), "None")
        $settings.TypeNameHandling = [Enum]::Parse(("Newtonsoft.Json.TypeNameHandling" -as [type]), "None")
        $settings.MetadataPropertyHandling = [Enum]::Parse(("Newtonsoft.Json.MetadataPropertyHandling" -as [type]), "Ignore")
        $settings.MaxDepth = 48
        $root = [Newtonsoft.Json.JsonConvert]::DeserializeObject($Text, $settings)
        return (ConvertFrom-SwiftUIColorRGBJsonToken $root)
    } catch {
        if ($_.Exception.Message -cmatch '^RGB_[A-Z0-9_]+$') { throw }
        throw "RGB_JSON_DESERIALIZATION_FAILURE"
    }
}

function Read-SwiftUIColorRGBJson {
    param([Parameter(Mandatory)][string]$Path, [int]$MaxBytes = 2097152)
    $stream = [IO.File]::Open($Path, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
    $memory = [IO.MemoryStream]::new()
    try {
        $buffer = [byte[]]::new(8192)
        while (($count = $stream.Read($buffer, 0, $buffer.Length)) -gt 0) {
            if ($memory.Length + $count -gt $MaxBytes) { throw "RGB_METADATA_BYTE_LIMIT" }
            $memory.Write($buffer, 0, $count)
        }
        try { $text = [Text.UTF8Encoding]::new($false, $true).GetString($memory.ToArray()) }
        catch [Text.DecoderFallbackException] { throw "RGB_JSON_INVALID_UTF8" }
        if ($text.Length -gt 0 -and $text[0] -eq [char]0xfeff) { throw "RGB_JSON_BOM_NOT_ALLOWED" }
        return (ConvertFrom-SwiftUIColorRGBJsonText -Text $text)
    } finally { $stream.Dispose(); $memory.Dispose() }
}

function Write-SwiftUIColorRGBTextNew {
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][AllowEmptyString()][string]$Text)
    $bytes = [Text.UTF8Encoding]::new($false).GetBytes($Text)
    $stream = [IO.File]::Open($Path, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::Read)
    try { $stream.Write($bytes, 0, $bytes.Length) } finally { $stream.Dispose() }
}

function Write-SwiftUIColorRGBJsonNew {
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)]$Value)
    $text = ConvertTo-Json -InputObject $Value -Depth 48 -WarningAction Stop
    Write-SwiftUIColorRGBTextNew -Path $Path -Text ($text + "`n")
}

function Get-SwiftUIColorRGBHash {
    param([Parameter(Mandatory)][string]$Path)
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Get-SwiftUIColorRGBGitBlobHash {
    param([byte[]]$Bytes)
    $header = [Text.Encoding]::ASCII.GetBytes("blob $($Bytes.Length)`0")
    $algorithm = [Security.Cryptography.SHA1]::Create()
    try {
        [void]$algorithm.TransformBlock($header, 0, $header.Length, $header, 0)
        [void]$algorithm.TransformFinalBlock($Bytes, 0, $Bytes.Length)
        return [BitConverter]::ToString($algorithm.Hash).Replace('-', '').ToLowerInvariant()
    } finally { $algorithm.Dispose() }
}

function Get-SwiftUIColorRGBSourceByteIdentity {
    param([string]$Path, [string]$GitBlob)
    if ((Get-Item -LiteralPath $Path).Length -gt 33554432) { throw "RGB_SOURCE_SNAPSHOT_BYTE_LIMIT" }
    $bytes = [IO.File]::ReadAllBytes($Path)
    if ((Get-SwiftUIColorRGBGitBlobHash $bytes) -ceq $GitBlob) { return "git-blob-exact" }
    # The only permitted checkout representation change is CRLF -> LF. No
    # clean filter, whitespace trimming, BOM removal, or text rewriting can
    # make modified compiled source look like the claimed committed blob.
    $encoding = [Text.UTF8Encoding]::new($false, $true)
    try { $text = $encoding.GetString($bytes) } catch { throw "RGB_SOURCE_BYTES_NOT_COMMITTED_BLOB" }
    if ($text.Contains("`r`n")) {
        $normalized = $encoding.GetBytes($text.Replace("`r`n", "`n"))
        if ((Get-SwiftUIColorRGBGitBlobHash $normalized) -ceq $GitBlob) { return "git-blob-after-crlf-normalization" }
    }
    throw "RGB_SOURCE_BYTES_NOT_COMMITTED_BLOB"
}

function Get-SwiftUIColorRGBWindowsEnvironmentOverrides {
    param([System.Collections.IDictionary]$Environment)
    $preparedNames = @("SDKROOT", "SWIFT_REPO_ROOT", "SWIFT_WINDOWSUI_DEV_ENV_SIGNATURE")
    foreach ($name in @(Get-SwiftUIMaterialEnvironmentOverrides $Environment)) {
        if ($name -cnotin $preparedNames) { Write-Output $name }
    }
}

function Get-SwiftUIColorRGBFileRecord {
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][string]$EvidenceFile)
    return [pscustomobject][ordered]@{
        evidenceFile = $EvidenceFile; bytes = (Get-Item -LiteralPath $Path).Length
        sha256 = Get-SwiftUIColorRGBHash -Path $Path
    }
}

function Get-SwiftUIColorRGBEvidencePath {
    param([Parameter(Mandatory)][string]$Root, [Parameter(Mandatory)][string]$Name)
    if ($Name -cnotmatch '^[A-Za-z0-9][A-Za-z0-9._/+-]*$' -or
        $Name -match '(^|/)\.\.?(/|$)|//|/$') { throw "RGB_INVALID_EVIDENCE_PATH" }
    $resolvedRoot = Resolve-SwiftUIBaselineFileSystemPath -Path $Root
    $path = Resolve-SwiftUIBaselineFileSystemPath -Path (Join-Path $resolvedRoot $Name)
    [void](Get-SwiftUIBaselineRelativePath -Root $resolvedRoot -Path $path)
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "RGB_MISSING_EVIDENCE_FILE: $Name" }
    return $path
}

function Assert-SwiftUIColorRGBFileRecord {
    param([Parameter(Mandatory)][string]$Root, [Parameter(Mandatory)]$Record, [long]$MaxBytes = 536870912)
    Assert-SwiftUIColorRGBObject $Record "file" @("evidenceFile", "bytes", "sha256")
    Assert-SwiftUIColorRGBString $Record.evidenceFile "file.evidenceFile"
    Assert-SwiftUIColorRGBInteger $Record.bytes "file.bytes" 0 $MaxBytes
    if ($Record.sha256 -isnot [string] -or $Record.sha256 -cnotmatch '^[0-9a-f]{64}$') { throw "RGB_INVALID_SHA256" }
    $path = Get-SwiftUIColorRGBEvidencePath -Root $Root -Name $Record.evidenceFile
    if ((Get-Item -LiteralPath $path).Length -ne $Record.bytes) { throw "RGB_EVIDENCE_LENGTH_MISMATCH" }
    if ((Get-SwiftUIColorRGBHash $path) -cne $Record.sha256) { throw "RGB_EVIDENCE_HASH_MISMATCH" }
    return $path
}

function New-SwiftUIColorRGBOutputRoot {
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][string]$RepositoryRoot,
        [string[]]$ExcludedRoots = @())
    $output = Resolve-SwiftUIBaselineFileSystemPath -Path $Path
    $allowed = $false
    foreach ($candidate in @((Join-Path $RepositoryRoot "artifacts"), [IO.Path]::GetTempPath())) {
        $resolved = Resolve-SwiftUIBaselineFileSystemPath -Path $candidate
        try { [void](Get-SwiftUIBaselineRelativePath -Root $resolved -Path $output); $allowed = $true } catch { }
    }
    if (-not $allowed) { throw "RGB_OUTPUT_OUTSIDE_ARTIFACTS_OR_TEMP" }
    foreach ($excluded in $ExcludedRoots) {
        if ([string]::IsNullOrWhiteSpace($excluded)) { continue }
        $resolved = Resolve-SwiftUIBaselineFileSystemPath -Path $excluded
        $inside = $false
        try { [void](Get-SwiftUIBaselineRelativePath -Root $resolved -Path $output); $inside = $true } catch { }
        if ($inside -or $resolved -eq $output) { throw "RGB_OUTPUT_INSIDE_INPUT_EVIDENCE" }
    }
    if (Test-Path -LiteralPath $output) { throw "RGB_OUTPUT_EXISTS: evidence is immutable." }
    $parent = Split-Path -Parent $output
    [void][IO.Directory]::CreateDirectory($parent)
    [void](New-Item -ItemType Directory -Path $output -ErrorAction Stop)
    return $output
}

function Read-SwiftUIColorRGBNumber {
    param($Record, [string]$ExpectedStorage, [string]$Name)
    Assert-SwiftUIColorRGBObject $Record $Name @("kind", "value", "storage", "bitPattern")
    Assert-SwiftUIColorRGBString $Record.kind "$Name.kind"
    Assert-SwiftUIColorRGBString $Record.storage "$Name.storage"
    if ($Record.storage -cne $ExpectedStorage -or $ExpectedStorage -cnotin @("float32", "float64")) { throw "RGB_NUMERIC_STORAGE_MISMATCH: $Name" }
    $digits = if ($ExpectedStorage -ceq "float32") { 8 } else { 16 }
    if ($Record.bitPattern -isnot [string] -or $Record.bitPattern -cnotmatch ("^[0-9a-f]{{{0}}}$" -f $digits)) { throw "RGB_INVALID_NUMERIC_BITS: $Name" }
    $bytes = [byte[]]::new($digits / 2)
    for ($i = 0; $i -lt $bytes.Length; $i++) { $bytes[$i] = [Convert]::ToByte($Record.bitPattern.Substring($i * 2, 2), 16) }
    if ([BitConverter]::IsLittleEndian) { [Array]::Reverse($bytes) }
    $number = if ($ExpectedStorage -ceq "float32") { [double][BitConverter]::ToSingle($bytes, 0) } else { [BitConverter]::ToDouble($bytes, 0) }
    $kind = "finite"
    if ([double]::IsNaN($number)) { $kind = "nan" }
    elseif ([double]::IsPositiveInfinity($number)) { $kind = "positive-infinity" }
    elseif ([double]::IsNegativeInfinity($number)) { $kind = "negative-infinity" }
    if ($Record.kind -cne $kind) { throw "RGB_NUMERIC_KIND_BITS_MISMATCH: $Name" }
    if ($kind -ceq "finite") {
        if ($Record.value -isnot [int] -and $Record.value -isnot [long] -and $Record.value -isnot [double] -and $Record.value -isnot [decimal]) { throw "RGB_NUMERIC_VALUE_BITS_MISMATCH: $Name" }
        # Windows PowerShell 5.1's JSON reader can return Decimal. On .NET
        # Framework, casting that Decimal directly to Double can introduce a
        # one-ULP error even for a valid widened Float (e.g. 0.88082504272460938).
        # Parse its preserved invariant decimal text instead. Equality to the
        # recorded IEEE bits remains exact; this adds no numerical tolerance.
        $jsonNumber = if ($Record.value -is [decimal]) {
            [double]::Parse($Record.value.ToString([Globalization.CultureInfo]::InvariantCulture), [Globalization.NumberStyles]::Float, [Globalization.CultureInfo]::InvariantCulture)
        } else { [double]$Record.value }
        if ([double]::IsNaN($jsonNumber) -or [double]::IsInfinity($jsonNumber) -or $jsonNumber -ne $number) {
            throw "RGB_NUMERIC_VALUE_BITS_MISMATCH: $Name"
        }
        # JSON parsers may normalize the sign of zero. The raw sign bit remains
        # preserved; this protocol expressly does not compare signed-zero identity.
    } elseif ($null -ne $Record.value) { throw "RGB_NONFINITE_JSON_VALUE_MUST_BE_NULL: $Name" }
    return [pscustomobject]@{ kind = $kind; value = $number; bitPattern = $Record.bitPattern; storage = $ExpectedStorage }
}

function Get-SwiftUIColorRGBDelta {
    param([double]$Windows, [double]$Native, [ValidateSet("red", "green", "blue", "alpha")][string]$Component)
    $p = Get-SwiftUIColorRGBProtocol
    if ([double]::IsNaN($Windows) -or [double]::IsInfinity($Windows) -or [double]::IsNaN($Native) -or [double]::IsInfinity($Native)) {
        return [pscustomobject]@{ status = "nonfinite"; absoluteDelta = $null; bound = $null; matches = $false }
    }
    $bound = $p.absoluteAlpha
    if ($Component -cne "alpha") { $bound = [Math]::Max($p.absoluteRGB, $p.relativeRGB * [Math]::Max([Math]::Abs($Windows), [Math]::Abs($Native))) }
    $delta = [Math]::Abs($Windows - $Native)
    return [pscustomobject]@{ status = "compared"; absoluteDelta = $delta; bound = $bound; matches = ($delta -le $bound) }
}

function Read-SwiftUIColorRGBReport {
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][string]$ExpectedObserver,
        [Parameter(Mandatory)][string]$ExpectedRunId, [Parameter(Mandatory)][string]$ExpectedArchitecture)
    $report = Read-SwiftUIColorRGBJson -Path $Path
    Assert-SwiftUIColorRGBObject $report "report" @("schemaVersion", "protocolId", "caseSetId", "componentEncoding", "collectionStatus", "runId", "observer", "platform", "runtime", "cases")
    Assert-SwiftUIColorRGBInteger $report.schemaVersion "report.schemaVersion" 1 1
    foreach ($field in @("protocolId", "caseSetId", "componentEncoding", "collectionStatus", "runId", "observer", "platform")) { Assert-SwiftUIColorRGBString $report.$field "report.$field" }
    $p = Get-SwiftUIColorRGBProtocol
    foreach ($field in @("schemaVersion", "protocolId", "caseSetId", "componentEncoding")) {
        if ($report.$field -cne $p.$field) { throw "RGB_REPORT_PROTOCOL_MISMATCH: $field" }
    }
    if ($report.collectionStatus -cne "complete" -or $report.observer -cne $ExpectedObserver -or
        $ExpectedObserver -cnotin @("windows-retained", "swiftui-resolved", "appkit-extended-srgb") -or
        $report.runId -cne $ExpectedRunId -or $ExpectedRunId -cnotmatch '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$') {
        throw "RGB_REPORT_IDENTITY_MISMATCH"
    }
    $platform = if ($ExpectedObserver -ceq "windows-retained") { "windows" } else { "macos" }
    if ($report.platform -cne $platform) { throw "RGB_REPORT_PLATFORM_MISMATCH" }
    Assert-SwiftUIColorRGBObject $report.runtime "runtime" @("processId", "processArchitecture", "operatingSystemVersion", "operatingSystemVersionString")
    Assert-SwiftUIColorRGBInteger $report.runtime.processId "runtime.processId" 1
    Assert-SwiftUIColorRGBString $report.runtime.processArchitecture "runtime.processArchitecture"
    Assert-SwiftUIColorRGBString $report.runtime.operatingSystemVersionString "runtime.operatingSystemVersionString"
    if ($report.runtime.processArchitecture -cne $ExpectedArchitecture -or $ExpectedArchitecture -cnotin @("arm64", "x86_64") -or
        $report.runtime.operatingSystemVersion -isnot [string] -or $report.runtime.operatingSystemVersion -cnotmatch '^[0-9]+\.[0-9]+\.[0-9]+$') { throw "RGB_REPORT_RUNTIME_MISMATCH" }
    Assert-SwiftUIColorRGBArray $report.cases "cases" 25 25
    $expectedCases = @{}; foreach ($case in Get-SwiftUIColorRGBCases) { $expectedCases.Add($case.caseId, $case) }
    $seen = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    $values = [ordered]@{}
    $environments = @("none"); $storage = "float32"
    if ($ExpectedObserver -ceq "swiftui-resolved") { $environments = @("light", "dark") }
    if ($ExpectedObserver -ceq "appkit-extended-srgb") { $storage = "float64" }
    foreach ($case in $report.cases) {
        Assert-SwiftUIColorRGBObject $case "case" @("caseId", "domain", "sourceSpace", "input", "observations")
        Assert-SwiftUIColorRGBString $case.caseId "case.caseId"
        Assert-SwiftUIColorRGBString $case.domain "case.domain"
        Assert-SwiftUIColorRGBString $case.sourceSpace "case.sourceSpace"
        if (-not $expectedCases.ContainsKey($case.caseId) -or -not $seen.Add($case.caseId)) { throw "RGB_UNKNOWN_OR_DUPLICATE_CASE" }
        $expected = $expectedCases[$case.caseId]
        if ($case.caseId -cne $expected.caseId -or $case.domain -cne $expected.domain -or $case.sourceSpace -cne $expected.sourceSpace) { throw "RGB_CASE_RECLASSIFIED" }
        Assert-SwiftUIColorRGBObject $case.input "input" @("red", "green", "blue", "opacity")
        foreach ($component in @("red", "green", "blue", "opacity")) {
            $number = Read-SwiftUIColorRGBNumber $case.input.$component "float64" "input.$component"
            if ($number.kind -cne "finite" -or $number.bitPattern -cne (Get-SwiftUIColorRGBBits $expected.input.$component "float64")) { throw "RGB_WRONG_INPUT_BITS" }
        }
        Assert-SwiftUIColorRGBArray $case.observations "observations" $environments.Count $environments.Count
        $seenEnvironments = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
        $caseValues = [ordered]@{}
        foreach ($observation in $case.observations) {
            Assert-SwiftUIColorRGBObject $observation "observation" @("environment", "status", "reason", "encodedRGBA", "linearRGB", "appKit")
            Assert-SwiftUIColorRGBString $observation.environment "observation.environment"
            Assert-SwiftUIColorRGBString $observation.status "observation.status"
            if ($observation.environment -cnotin $environments -or -not $seenEnvironments.Add($observation.environment) -or
                $observation.status -cnotin @("observed", "unsupported", "failure")) { throw "RGB_INVALID_OBSERVATION_KEY_OR_STATE" }
            $encoded = $null; $linear = $null
            if ($observation.status -ceq "observed") {
                if ($null -ne $observation.reason) { throw "RGB_OBSERVED_REASON_MUST_BE_NULL" }
                Assert-SwiftUIColorRGBObject $observation.encodedRGBA "encodedRGBA" @("red", "green", "blue", "alpha")
                $encoded = [ordered]@{}
                foreach ($component in @("red", "green", "blue", "alpha")) { $encoded[$component] = Read-SwiftUIColorRGBNumber $observation.encodedRGBA.$component $storage "encodedRGBA.$component" }
                if ($ExpectedObserver -ceq "swiftui-resolved") {
                    Assert-SwiftUIColorRGBObject $observation.linearRGB "linearRGB" @("red", "green", "blue")
                    $linear = [ordered]@{}
                    foreach ($component in @("red", "green", "blue")) { $linear[$component] = Read-SwiftUIColorRGBNumber $observation.linearRGB.$component "float32" "linearRGB.$component" }
                } elseif ($null -ne $observation.linearRGB) { throw "RGB_UNEXPECTED_LINEAR_DIAGNOSTICS" }
            } else {
                Assert-SwiftUIColorRGBString $observation.reason "observation.reason"
                if ($null -ne $observation.encodedRGBA -or $null -ne $observation.linearRGB) { throw "RGB_NONOBSERVED_COMPONENTS_MUST_BE_NULL" }
            }
            if ($ExpectedObserver -ceq "appkit-extended-srgb") {
                if ($null -ne $observation.appKit) {
                    Assert-SwiftUIColorRGBObject $observation.appKit "appKit" @("targetColorSpace", "actualColorSpaceName", "colorSpaceModel", "componentCount", "targetIdentityMatches")
                    Assert-SwiftUIColorRGBString $observation.appKit.actualColorSpaceName "appKit.actualColorSpaceName" -AllowEmpty
                    Assert-SwiftUIColorRGBString $observation.appKit.colorSpaceModel "appKit.colorSpaceModel"
                    Assert-SwiftUIColorRGBBoolean $observation.appKit.targetIdentityMatches "appKit.targetIdentityMatches"
                    Assert-SwiftUIColorRGBString $observation.appKit.targetColorSpace "appKit.targetColorSpace"
                    if ($observation.appKit.targetColorSpace -cne "extendedSRGB") { throw "RGB_APPKIT_WRONG_REQUESTED_SPACE" }
                    if ($null -ne $observation.appKit.componentCount) { Assert-SwiftUIColorRGBInteger $observation.appKit.componentCount "appKit.componentCount" 0 1024 }
                    if ($observation.status -ceq "observed" -and ($observation.appKit.targetIdentityMatches -ne $true -or $observation.appKit.colorSpaceModel -cne "rgb" -or $observation.appKit.componentCount -ne 4)) { throw "RGB_APPKIT_UNEXPECTED_OBSERVED_SPACE" }
                    if ($observation.status -cne "observed" -and $null -eq $observation.appKit.componentCount -and $observation.appKit.colorSpaceModel -ceq "rgb") { throw "RGB_APPKIT_MISSING_RGB_COMPONENT_COUNT" }
                } elseif ($observation.status -ceq "observed") { throw "RGB_APPKIT_MISSING_SPACE_METADATA" }
            } elseif ($null -ne $observation.appKit) { throw "RGB_UNEXPECTED_APPKIT_METADATA" }
            $caseValues[$observation.environment] = [pscustomobject]@{ status = $observation.status; reason = $observation.reason; encoded = $encoded; linear = $linear; raw = $observation }
        }
        $values[$case.caseId] = $caseValues
    }
    return [pscustomobject]@{ report = $report; values = $values; sha256 = Get-SwiftUIColorRGBHash $Path }
}

function Test-SwiftUIColorRGBObserverControls {
    param([object[]]$Reports, [string]$Observer)
    $reasons = [System.Collections.Generic.List[string]]::new()
    if ($Reports.Count -ne 3) { return [pscustomobject]@{ state = "failure"; reasons = @("incomplete-repetitions") } }
    $required = @(Get-SwiftUIColorRGBCases | Where-Object { $_.domain -ceq "required-finite" })
    $environments = @("none")
    if ($Observer -ceq "swiftui-resolved") { $environments = @("light", "dark") }
    $unsupported = $false; $failed = $false; $nonfinite = $false
    foreach ($report in $Reports) {
        foreach ($case in $required) {
            foreach ($environment in $environments) {
                $observation = $report.values[$case.caseId][$environment]
                if ($observation.status -ceq "unsupported") { $unsupported = $true; $reasons.Add("unsupported:$($case.caseId):$environment"); continue }
                if ($observation.status -ceq "failure") { $failed = $true; $reasons.Add("failed:$($case.caseId):$environment"); continue }
                foreach ($component in @("red", "green", "blue", "alpha")) {
                    if ($observation.encoded[$component].kind -cne "finite") { $nonfinite = $true; $reasons.Add("nonfinite:$($case.caseId):${environment}:$component") }
                }
                if ($Observer -ceq "swiftui-resolved") {
                    foreach ($component in @("red", "green", "blue")) {
                        if ($observation.linear[$component].kind -cne "finite") { $nonfinite = $true; $reasons.Add("nonfinite-linear:$($case.caseId):${environment}:$component") }
                    }
                }
            }
        }
    }
    if ($failed) { return [pscustomobject]@{ state = "failure"; reasons = @($reasons.ToArray()) } }
    if ($nonfinite -and $Observer -ceq "windows-retained") { return [pscustomobject]@{ state = "failure"; reasons = @($reasons.ToArray()) } }
    if ($unsupported) { return [pscustomobject]@{ state = "unsupported"; reasons = @($reasons.ToArray()) } }
    if ($nonfinite) {
        $state = if ($Observer -ceq "windows-retained") { "failure" } else { "inconclusive" }
        return [pscustomobject]@{ state = $state; reasons = @($reasons.ToArray()) }
    }
    # Windows is the implementation under test, not the reference observer.
    # Finite instability must remain a per-repetition mismatch against a
    # healthy native reference, rather than escaping comparison as unsupported.
    if ($Observer -ceq "windows-retained") { return [pscustomobject]@{ state = "healthy"; reasons = @() } }
    # No conversion formula is a native oracle. These are only the frozen
    # observer controls: identity colors, extended range, and distinct getter
    # encodings. Alpha-zero RGB is deliberately not constrained by a control.
    if ($Observer -cne "windows-retained") {
        foreach ($report in $Reports) {
            foreach ($environment in $environments) {
                foreach ($id in @("srgb-zero", "srgb-white", "srgb-interior", "srgb-extended")) {
                    $expected = @($required | Where-Object { $_.caseId -ceq $id })[0]
                    foreach ($component in @("red", "green", "blue")) {
                        $value = $report.values[$id][$environment].encoded[$component].value
                        if (-not (Get-SwiftUIColorRGBDelta $value $expected.input.$component $component).matches) { $reasons.Add("identity-control:${id}:${environment}:$component") }
                    }
                }
                $extended = $report.values["srgb-extended"][$environment].encoded
                if ($extended.red.value -ge 0 -or $extended.green.value -le 1 -or $extended.blue.value -le 1) { $reasons.Add("extended-range-control:$environment") }
                if ($Observer -ceq "swiftui-resolved") {
                    $linear = $report.values["linear-interior"][$environment]
                    $expectedLinear = @{ red = 0.25; green = 0.5; blue = 0.75 }
                    foreach ($component in @("red", "green", "blue")) {
                        if (-not (Get-SwiftUIColorRGBDelta $linear.linear[$component].value $expectedLinear[$component] $component).matches) { $reasons.Add("linear-getter-identity:${environment}:$component") }
                    }
                    if ((Get-SwiftUIColorRGBDelta $linear.encoded.green.value $linear.linear.green.value "green").matches) { $reasons.Add("encoded-and-linear-getters-indistinguishable:$environment") }
                    $srgb = $report.values["srgb-interior"][$environment]
                    if ((Get-SwiftUIColorRGBDelta $srgb.encoded.green.value $srgb.linear.green.value "green").matches) { $reasons.Add("srgb-getter-encodings-indistinguishable:$environment") }
                }
            }
        }
    }
    # Pairwise, never average. A repetition is an independently constructed
    # process observation, not another sample to make a disagreeing value pass.
    foreach ($case in $required) {
        foreach ($environment in $environments) {
            foreach ($pair in @(@(0, 1), @(0, 2), @(1, 2))) {
                foreach ($component in @("red", "green", "blue", "alpha")) {
                    $first = $Reports[$pair[0]].values[$case.caseId][$environment].encoded[$component].value
                    $second = $Reports[$pair[1]].values[$case.caseId][$environment].encoded[$component].value
                    if (-not (Get-SwiftUIColorRGBDelta $first $second $component).matches) { $reasons.Add("unstable:$($case.caseId):${environment}:${component}:$($pair[0] + 1)-$($pair[1] + 1)") }
                }
                if ($Observer -ceq "swiftui-resolved") {
                    foreach ($component in @("red", "green", "blue")) {
                        $first = $Reports[$pair[0]].values[$case.caseId][$environment].linear[$component].value
                        $second = $Reports[$pair[1]].values[$case.caseId][$environment].linear[$component].value
                        if (-not (Get-SwiftUIColorRGBDelta $first $second $component).matches) { $reasons.Add("unstable-linear:$($case.caseId):${environment}:$component") }
                    }
                }
            }
        }
        if ($Observer -ceq "swiftui-resolved") {
            foreach ($report in $Reports) {
                foreach ($component in @("red", "green", "blue", "alpha")) {
                    $light = $report.values[$case.caseId]["light"].encoded[$component].value
                    $dark = $report.values[$case.caseId]["dark"].encoded[$component].value
                    if (-not (Get-SwiftUIColorRGBDelta $light $dark $component).matches) { $reasons.Add("constant-color-environment:$($case.caseId):$component") }
                }
                foreach ($component in @("red", "green", "blue")) {
                    $light = $report.values[$case.caseId]["light"].linear[$component].value
                    $dark = $report.values[$case.caseId]["dark"].linear[$component].value
                    if (-not (Get-SwiftUIColorRGBDelta $light $dark $component).matches) { $reasons.Add("constant-color-linear-environment:$($case.caseId):$component") }
                }
            }
        }
    }
    $state = "healthy"
    if ($reasons.Count -gt 0) { $state = if ($Observer -ceq "windows-retained") { "failure" } else { "inconclusive" } }
    return [pscustomobject]@{ state = $state; reasons = @($reasons.ToArray() | Select-Object -Unique) }
}

function Compare-SwiftUIColorRGBObserver {
    param([object[]]$WindowsReports, [object[]]$NativeReports, [string]$Observer)
    $windowsControl = Test-SwiftUIColorRGBObserverControls -Reports $WindowsReports -Observer "windows-retained"
    $nativeControl = Test-SwiftUIColorRGBObserverControls -Reports $NativeReports -Observer $Observer
    $rows = [System.Collections.Generic.List[object]]::new()
    $requiredMismatch = $false
    $environments = @("none")
    if ($Observer -ceq "swiftui-resolved") { $environments = @("light", "dark") }
    if ($WindowsReports.Count -eq 3 -and $NativeReports.Count -eq 3) {
        foreach ($case in Get-SwiftUIColorRGBCases) {
            for ($repetition = 1; $repetition -le 3; $repetition++) {
                foreach ($environment in $environments) {
                    $win = $WindowsReports[$repetition - 1].values[$case.caseId]["none"]
                    $native = $NativeReports[$repetition - 1].values[$case.caseId][$environment]
                    foreach ($component in @("red", "green", "blue", "alpha")) {
                        $state = "not-observed"; $delta = $null; $bound = $null; $winNumber = $null; $nativeNumber = $null
                        if ($win.status -ceq "observed") { $winNumber = $win.raw.encodedRGBA.$component }
                        if ($native.status -ceq "observed") { $nativeNumber = $native.raw.encodedRGBA.$component }
                        if ($null -ne $winNumber -and $null -ne $nativeNumber) {
                            $comparison = Get-SwiftUIColorRGBDelta $win.encoded[$component].value $native.encoded[$component].value $component
                            $delta = $comparison.absoluteDelta; $bound = $comparison.bound
                            $state = if ($comparison.status -ceq "nonfinite") { "nonfinite" } elseif ($comparison.matches) { "match" } else { "mismatch" }
                            if ($case.domain -ceq "required-finite" -and $state -ceq "mismatch") { $requiredMismatch = $true }
                        }
                        $rows.Add([pscustomobject][ordered]@{
                            caseId = $case.caseId; domain = $case.domain; repetition = $repetition
                            nativeObserver = $Observer; environment = $environment; component = $component
                            state = $state; windows = $winNumber; native = $nativeNumber
                            windowsObservationState = $win.status; nativeObservationState = $native.status
                            windowsReason = $win.reason; nativeReason = $native.reason
                            absoluteDelta = $delta; bound = $bound
                        })
                    }
                }
            }
        }
    }
    $state = "match-candidate"
    if ($windowsControl.state -ceq "failure" -or $nativeControl.state -ceq "failure") { $state = "failure" }
    elseif ($windowsControl.state -cne "healthy" -or $nativeControl.state -cne "healthy") { $state = "unsupported" }
    elseif ($requiredMismatch) { $state = "mismatch" }
    return [pscustomobject][ordered]@{
        state = $state; nativeObserver = $Observer
        windowsObserverControls = $windowsControl; nativeObserverControls = $nativeControl
        requiredComparisons = @($rows.ToArray() | Where-Object { $_.domain -ceq "required-finite" }).Count
        exploratoryComparisons = @($rows.ToArray() | Where-Object { $_.domain -ceq "exploratory-extended-p3" }).Count
        rows = @($rows.ToArray())
    }
}

function ConvertTo-SwiftUIColorRGBWindowsArgument {
    param([AllowEmptyString()][string]$Value)
    # ProcessStartInfo.Arguments uses Windows argv quoting, not PowerShell or
    # JSON quoting. No shell is involved in the direct child process.
    $builder = [Text.StringBuilder]::new(); [void]$builder.Append('"'); $slashes = 0
    foreach ($character in $Value.ToCharArray()) {
        if ($character -eq '\') { $slashes++; continue }
        if ($character -eq '"') {
            [void]$builder.Append(('\' * ($slashes * 2 + 1))); [void]$builder.Append('"')
        } else { [void]$builder.Append(('\' * $slashes)); [void]$builder.Append($character) }
        $slashes = 0
    }
    [void]$builder.Append(('\' * ($slashes * 2))); [void]$builder.Append('"')
    return $builder.ToString()
}

function Read-SwiftUIColorRGBText {
    param([string]$Path, [int]$MaxBytes = 65536)
    $stream = [IO.File]::Open($Path, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
    $memory = [IO.MemoryStream]::new()
    try {
        $buffer = [byte[]]::new(8192)
        while (($count = $stream.Read($buffer, 0, $buffer.Length)) -gt 0) {
            if ($memory.Length + $count -gt $MaxBytes) { throw "RGB_TEXT_BYTE_LIMIT" }
            $memory.Write($buffer, 0, $count)
        }
        return [Text.UTF8Encoding]::new($false, $true).GetString($memory.ToArray())
    } finally { $stream.Dispose(); $memory.Dispose() }
}

function Invoke-SwiftUIColorRGBProcess {
    param([Parameter(Mandatory)][string]$FilePath, [string[]]$Arguments = @(),
        [Parameter(Mandatory)][string]$WorkingDirectory, [Parameter(Mandatory)][string]$EvidenceRoot,
        [Parameter(Mandatory)][string]$CommandId, [int]$TimeoutSeconds = 30,
        [int]$MaxLogBytes = 16777216, [System.Collections.IDictionary]$EnvironmentOverrides = @{})
    if ($CommandId -cnotmatch '^[a-z][a-z0-9-]{0,63}$' -or $TimeoutSeconds -lt 1 -or $TimeoutSeconds -gt 1800 -or
        $MaxLogBytes -lt 1 -or $MaxLogBytes -gt 16777216) { throw "RGB_INVALID_PROCESS_LIMITS" }
    $info = [Diagnostics.ProcessStartInfo]::new()
    $info.FileName = $FilePath; $info.WorkingDirectory = $WorkingDirectory
    $info.UseShellExecute = $false; $info.CreateNoWindow = $true
    $info.RedirectStandardOutput = $true; $info.RedirectStandardError = $true
    if ($null -ne $info.PSObject.Properties["ArgumentList"]) {
        foreach ($argument in $Arguments) { $info.ArgumentList.Add($argument) }
    } else {
        if ([IO.Path]::DirectorySeparatorChar -ne '\') { throw "RGB_PROCESS_ARGUMENT_API_UNAVAILABLE" }
        $quoted = @($Arguments | ForEach-Object { ConvertTo-SwiftUIColorRGBWindowsArgument $_ })
        $info.Arguments = $quoted -join ' '
    }
    foreach ($name in $EnvironmentOverrides.Keys) {
        if ($name -cne "DEVELOPER_DIR") { throw "RGB_UNEXPECTED_CHILD_ENVIRONMENT_OVERRIDE" }
        $info.EnvironmentVariables[$name] = [string]$EnvironmentOverrides[$name]
    }
    $stdoutName = "$CommandId.stdout.txt"; $stderrName = "$CommandId.stderr.txt"
    $stdoutPath = Join-Path $EvidenceRoot $stdoutName; $stderrPath = Join-Path $EvidenceRoot $stderrName
    $record = [pscustomobject][ordered]@{
        commandId = $CommandId; executable = $FilePath; executableSha256 = $null; arguments = @($Arguments)
        processId = $null; startedAtUtc = [DateTime]::UtcNow.ToString("o"); finishedAtUtc = $null
        timeoutSeconds = $TimeoutSeconds; maxLogBytesPerStream = $MaxLogBytes
        state = "start-failure"; exitCode = $null; errorCode = $null; cleanupComplete = $false
        cleanupScope = "owned-root-and-redirected-streams; no process-tree closure claim"
        stdout = $null; stderr = $null
    }
    $process = [Diagnostics.Process]::new(); $process.StartInfo = $info
    $files = @($null, $null); $started = $false; $streamsClosed = $false
    try {
        $files[0] = [IO.File]::Open($stdoutPath, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::Read)
        $files[1] = [IO.File]::Open($stderrPath, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::Read)
        if (-not [IO.Path]::IsPathRooted($FilePath) -or -not (Test-Path -LiteralPath $FilePath -PathType Leaf)) { throw "RGB_PROCESS_EXECUTABLE_NOT_ABSOLUTE_FILE" }
        $record.executableSha256 = Get-SwiftUIColorRGBHash $FilePath
        [void]$process.Start(); $started = $true; $record.processId = $process.Id
        $record.state = "running"
        $inputStreams = @($process.StandardOutput.BaseStream, $process.StandardError.BaseStream)
        $buffers = @([byte[]]::new(8192), [byte[]]::new(8192))
        $tasks = @($inputStreams[0].ReadAsync($buffers[0], 0, $buffers[0].Length), $inputStreams[1].ReadAsync($buffers[1], 0, $buffers[1].Length))
        $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds); $drainDeadline = $null
        while ($true) {
            for ($index = 0; $index -lt 2; $index++) {
                if ($null -eq $tasks[$index] -or -not $tasks[$index].IsCompleted) { continue }
                $count = $tasks[$index].GetAwaiter().GetResult()
                if ($count -eq 0) { $tasks[$index] = $null; continue }
                $allowed = [Math]::Min($count, [Math]::Max(0, $MaxLogBytes - $files[$index].Length))
                if ($allowed -gt 0) { $files[$index].Write($buffers[$index], 0, [int]$allowed) }
                if ($allowed -lt $count) { $record.state = "output-limit"; $record.errorCode = "RGB_PROCESS_OUTPUT_LIMIT"; break }
                $tasks[$index] = $inputStreams[$index].ReadAsync($buffers[$index], 0, $buffers[$index].Length)
            }
            if ($record.state -ceq "output-limit") { break }
            if ($process.HasExited) {
                if ($null -eq $drainDeadline) { $drainDeadline = [DateTime]::UtcNow.AddSeconds(5) }
                if ($null -eq $tasks[0] -and $null -eq $tasks[1]) { $streamsClosed = $true; break }
                if ([DateTime]::UtcNow -ge $drainDeadline) { $record.state = "stream-timeout"; $record.errorCode = "RGB_PROCESS_STREAM_CLOSE_TIMEOUT"; break }
            }
            if ([DateTime]::UtcNow -ge $deadline) { $record.state = "timeout"; $record.errorCode = "RGB_PROCESS_TIMEOUT"; break }
            [Threading.Thread]::Sleep(10)
        }
        if ($record.state -ceq "running") { $record.state = "exited"; $record.exitCode = $process.ExitCode; $record.cleanupComplete = $streamsClosed }
        else {
            if (-not $process.HasExited) {
                try {
                    if ($PSVersionTable.PSVersion.Major -ge 7) { $process.Kill($true) } else { $process.Kill() }
                    [void]$process.WaitForExit(5000)
                } catch { }
            }
            if ($process.HasExited) { $record.exitCode = $process.ExitCode }
            # A timeout or inherited pipe can hide an unobserved descendant.
            # Do not run the next command or claim cleanup closure in this case.
            $record.cleanupComplete = $false
        }
    } catch {
        $record.state = if ($started) { "io-failure" } else { "start-failure" }
        $record.errorCode = if ($started) { "RGB_PROCESS_IO_FAILURE" } else { "RGB_PROCESS_START_FAILURE" }
        if ($started) {
            try {
                if (-not $process.HasExited) {
                    if ($PSVersionTable.PSVersion.Major -ge 7) { $process.Kill($true) } else { $process.Kill() }
                    [void]$process.WaitForExit(5000)
                }
                if ($process.HasExited) { $record.exitCode = $process.ExitCode }
            } catch { }
        }
    } finally {
        foreach ($file in $files) { if ($null -ne $file) { $file.Dispose() } }
        $process.Dispose()
        $record.finishedAtUtc = [DateTime]::UtcNow.ToString("o")
        if (Test-Path -LiteralPath $stdoutPath -PathType Leaf) { $record.stdout = Get-SwiftUIColorRGBFileRecord $stdoutPath $stdoutName }
        if (Test-Path -LiteralPath $stderrPath -PathType Leaf) { $record.stderr = Get-SwiftUIColorRGBFileRecord $stderrPath $stderrName }
    }
    return $record
}

function Invoke-SwiftUIColorRGBPreparedWindowsRequest {
    param([Parameter(Mandatory)][string]$RequestPath)
    # Only the evidence-local helper calls this after with-swift prepared its
    # child environment. It never exports the whole environment. The Process
    # record below names the actual Swift or reference PID, not this helper PID.
    $request = Read-SwiftUIColorRGBJson $RequestPath -MaxBytes 65536
    Assert-SwiftUIColorRGBObject $request "request" @("action", "runId", "repositoryRoot", "evidenceRoot", "resultFile", "commandId", "filePath", "arguments", "timeoutSeconds", "maxLogBytes")
    if ($request.action -cnotin @("identity", "run")) { throw "RGB_INVALID_PREPARED_ACTION" }
    $resultPath = Join-Path $request.evidenceRoot $request.resultFile
    [void](Get-SwiftUIBaselineRelativePath -Root $request.evidenceRoot -Path $resultPath)
    if ($request.action -ceq "identity") {
        $tools = @(
            foreach ($name in @("swift", "swiftc", "swift-frontend")) {
                $path = (Get-Command -Name ($name + ".exe") -CommandType Application -ErrorAction Stop | Select-Object -First 1).Source.Replace('\', '/')
                [pscustomobject]@{ role = $name; path = $path; sha256 = Get-SwiftUIColorRGBHash $path; bytes = (Get-Item -LiteralPath $path).Length }
            }
        )
        $overrides = @(Get-SwiftUIColorRGBWindowsEnvironmentOverrides ([Environment]::GetEnvironmentVariables()))
        if ($overrides.Count -gt 0) { throw "RGB_WINDOWS_ENVIRONMENT_OVERRIDE_REJECTED" }
        $runtimeType = "System.Runtime.InteropServices.RuntimeInformation" -as [type]
        if ($null -eq $runtimeType) { throw "RGB_WINDOWS_ARCHITECTURE_API_UNAVAILABLE" }
        $architecture = switch ([System.Runtime.InteropServices.RuntimeInformation]::ProcessArchitecture.ToString()) { "X64" { "x86_64" } "Arm64" { "arm64" } default { "unsupported" } }
        $hardware = switch ([System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture.ToString()) { "X64" { "x86_64" } "Arm64" { "arm64" } default { "unsupported" } }
        Write-SwiftUIColorRGBJsonNew -Path $resultPath -Value ([pscustomobject]@{
            runId = $request.runId; tools = $tools; sdkPath = $env:SDKROOT
            processArchitecture = $architecture; hardwareArchitecture = $hardware; translated = ($architecture -cne $hardware)
            operatingSystemVersion = [Environment]::OSVersion.Version.ToString()
            operatingSystemBuild = [Environment]::OSVersion.Version.Build.ToString()
            helperProcessId = $PID; environmentContentsRecorded = $false
        })
        return
    }
    $filePath = $request.filePath
    if (-not [IO.Path]::IsPathRooted($filePath)) {
        if ($filePath -cne "swift") { throw "RGB_UNEXPECTED_PREPARED_TOOL" }
        $filePath = (Get-Command -Name "swift.exe" -CommandType Application -ErrorAction Stop | Select-Object -First 1).Source.Replace('\', '/')
    }
    $record = Invoke-SwiftUIColorRGBProcess -FilePath $filePath -Arguments $request.arguments -WorkingDirectory $request.repositoryRoot `
        -EvidenceRoot $request.evidenceRoot -CommandId $request.commandId -TimeoutSeconds $request.timeoutSeconds -MaxLogBytes $request.maxLogBytes
    Write-SwiftUIColorRGBJsonNew -Path $resultPath -Value $record
}

function Assert-SwiftUIColorRGBCommandRecord {
    param([string]$Root, $Command)
    Assert-SwiftUIColorRGBObject $Command "command" @("commandId", "executable", "executableSha256", "arguments", "processId", "startedAtUtc", "finishedAtUtc", "timeoutSeconds", "maxLogBytesPerStream", "state", "exitCode", "errorCode", "cleanupComplete", "cleanupScope", "stdout", "stderr")
    foreach ($field in @("commandId", "executable", "startedAtUtc", "finishedAtUtc", "state", "cleanupScope")) { Assert-SwiftUIColorRGBString $Command.$field "command.$field" }
    if ($Command.commandId -cnotmatch '^[a-z][a-z0-9-]{0,63}$' -or
        $Command.state -cnotin @("exited", "start-failure", "io-failure", "timeout", "stream-timeout", "output-limit")) { throw "RGB_INVALID_COMMAND_STATE" }
    Assert-SwiftUIColorRGBInteger $Command.timeoutSeconds "command.timeoutSeconds" 1 1800
    Assert-SwiftUIColorRGBInteger $Command.maxLogBytesPerStream "command.maxLogBytesPerStream" 1 16777216
    Assert-SwiftUIColorRGBBoolean $Command.cleanupComplete "command.cleanupComplete"
    if ($Command.cleanupScope -cne "owned-root-and-redirected-streams; no process-tree closure claim") { throw "RGB_INVALID_CLEANUP_SCOPE" }
    Assert-SwiftUIColorRGBArray $Command.arguments "command.arguments" 0 1024
    foreach ($argument in $Command.arguments) { Assert-SwiftUIColorRGBString $argument "command.argument" -AllowEmpty -MaxLength 131072 }
    if ($null -ne $Command.processId) { Assert-SwiftUIColorRGBInteger $Command.processId "command.processId" 1 }
    if ($null -ne $Command.exitCode) { Assert-SwiftUIColorRGBInteger $Command.exitCode "command.exitCode" -2147483648 2147483647 }
    if ($null -ne $Command.errorCode) { Assert-SwiftUIColorRGBString $Command.errorCode "command.errorCode" }
    if ($null -ne $Command.executableSha256 -and ($Command.executableSha256 -isnot [string] -or $Command.executableSha256 -cnotmatch '^[0-9a-f]{64}$')) { throw "RGB_INVALID_COMMAND_EXECUTABLE_HASH" }
    foreach ($field in @("stdout", "stderr")) {
        if ($null -ne $Command.$field) { [void](Assert-SwiftUIColorRGBFileRecord $Root $Command.$field $Command.maxLogBytesPerStream) }
        elseif ($Command.state -ceq "exited") { throw "RGB_COMMAND_LOG_MISSING" }
    }
    $start = [DateTime]::Parse($Command.startedAtUtc, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::RoundtripKind)
    $finish = [DateTime]::Parse($Command.finishedAtUtc, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::RoundtripKind)
    if ($start.Kind -ne [DateTimeKind]::Utc -or $finish.Kind -ne [DateTimeKind]::Utc -or $finish -lt $start) { throw "RGB_COMMAND_TIME_INVALID" }
    if ($Command.state -ceq "exited" -and ($null -eq $Command.processId -or $null -eq $Command.exitCode -or $null -eq $Command.executableSha256 -or $Command.cleanupComplete -ne $true -or $null -ne $Command.errorCode)) { throw "RGB_EXITED_COMMAND_INCOMPLETE" }
    if ($Command.state -cne "exited" -and ($Command.cleanupComplete -ne $false -or $null -eq $Command.errorCode)) { throw "RGB_FAILED_COMMAND_INCONSISTENT" }
}

function Test-SwiftUIColorRGBCommandSucceeded {
    param($Command)
    return ($null -ne $Command -and $Command.state -ceq "exited" -and $Command.exitCode -eq 0 -and $Command.cleanupComplete -eq $true)
}

function Assert-SwiftUIColorRGBSourceSnapshot {
    param([string]$Root, $Source)
    Assert-SwiftUIColorRGBObject $Source "source" @("repositoryRoot", "commit", "tree", "clean", "sharedSources", "buildInputs", "collectorSources")
    Assert-SwiftUIColorRGBString $Source.repositoryRoot "source.repositoryRoot"
    if ($Source.commit -isnot [string] -or $Source.commit -cnotmatch '^[0-9a-f]{40}$' -or
        $Source.tree -isnot [string] -or $Source.tree -cnotmatch '^[0-9a-f]{40}$' -or $Source.clean -isnot [bool] -or $Source.clean -ne $true) { throw "RGB_SOURCE_NOT_CLEAN_COMMIT" }
    $expected = @(Get-SwiftUIColorRGBSourceNames)
    Assert-SwiftUIColorRGBArray $Source.sharedSources "source.sharedSources" 5 5
    Assert-SwiftUIColorRGBArray $Source.buildInputs "source.buildInputs" 1 4096
    Assert-SwiftUIColorRGBArray $Source.collectorSources "source.collectorSources" 1 32
    $index = 0
    foreach ($entry in $Source.sharedSources) {
        if ($entry.path -cne $expected[$index]) { throw "RGB_SHARED_SOURCE_SET_OR_ORDER_MISMATCH" }
        $index++
    }
    foreach ($group in @("sharedSources", "buildInputs", "collectorSources")) {
        $seen = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
        [long]$total = 0
        foreach ($entry in $Source.$group) {
            Assert-SwiftUIColorRGBObject $entry "source.file" @("path", "gitBlob", "byteIdentity", "file")
            Assert-SwiftUIColorRGBString $entry.path "source.file.path"
            if ($entry.path -cnotmatch '^[A-Za-z0-9._/+-]+$' -or $entry.path -match '(^|/)\.\.?(/|$)' -or
                -not $seen.Add($entry.path) -or $entry.gitBlob -isnot [string] -or $entry.gitBlob -cnotmatch '^[0-9a-f]{40}$') { throw "RGB_SOURCE_FILE_IDENTITY_INVALID" }
            $sourcePath = Assert-SwiftUIColorRGBFileRecord $Root $entry.file 33554432
            if ((Get-SwiftUIColorRGBSourceByteIdentity $sourcePath $entry.gitBlob) -cne $entry.byteIdentity) { throw "RGB_SOURCE_BYTE_IDENTITY_MISMATCH" }
            $total += $entry.file.bytes
            if ($total -gt 134217728) { throw "RGB_SOURCE_SNAPSHOT_BYTE_LIMIT" }
        }
    }
    foreach ($shared in $Source.sharedSources) {
        $same = @($Source.buildInputs | Where-Object { $_.path -ceq $shared.path })
        if ($same.Count -ne 1 -or $same[0].gitBlob -cne $shared.gitBlob -or $same[0].file.sha256 -cne $shared.file.sha256) { throw "RGB_SHARED_AND_BUILD_SOURCE_MISMATCH" }
    }
    if (@($Source.buildInputs | Where-Object { $_.path -ceq "Package.swift" }).Count -ne 1) { throw "RGB_PACKAGE_SOURCE_MISSING" }
}

function Assert-SwiftUIColorRGBArguments {
    param([object[]]$Actual, [string[]]$Expected)
    if ($Actual.Count -ne $Expected.Count) { throw "RGB_COMPILE_ARGUMENTS_MISMATCH" }
    for ($i = 0; $i -lt $Expected.Count; $i++) { if ($Actual[$i] -isnot [string] -or $Actual[$i] -cne $Expected[$i]) { throw "RGB_COMPILE_ARGUMENTS_MISMATCH" } }
}

function Assert-SwiftUIColorRGBToolCommand {
    param($Command, $Tool)
    if ($null -eq $Command -or $Command.executable -cne $Tool.path -or $Command.executableSha256 -cne $Tool.sha256) { throw "RGB_COMMAND_TOOL_BINDING_MISMATCH" }
}

function Assert-SwiftUIColorRGBCompilationBinding {
    param([string]$Root, $Manifest, [hashtable]$Commands)
    if ($null -eq $Manifest.toolchain) {
        if ($Manifest.sourceCompilation.state -ceq "compiled") { throw "RGB_COMPILED_WITHOUT_TOOLCHAIN" }
        return
    }
    $tools = @{}; foreach ($tool in $Manifest.toolchain.tools) { $tools[$tool.role] = $tool }
    Assert-SwiftUIColorRGBArray $Manifest.toolchain.versionCommands "toolchain.versionCommands" 1 3
    $versions = @{}; $seen = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($entry in $Manifest.toolchain.versionCommands) {
        Assert-SwiftUIColorRGBObject $entry "versionCommand" @("role", "commandId")
        if ($entry.role -cnotin @("swift", "swiftc", "swift-frontend") -or -not $seen.Add($entry.role) -or $entry.commandId -isnot [string] -or -not $Commands.ContainsKey($entry.commandId)) { throw "RGB_VERSION_COMMAND_IDENTITY_INVALID" }
        $command = $Commands[$entry.commandId]
        Assert-SwiftUIColorRGBToolCommand $command $tools[$entry.role]
        Assert-SwiftUIColorRGBArguments $command.arguments @("--version")
        if (-not (Test-SwiftUIColorRGBCommandSucceeded $command)) { throw "RGB_TOOL_VERSION_COMMAND_FAILED" }
        $versions[$entry.role] = (Read-SwiftUIColorRGBText (Get-SwiftUIColorRGBEvidencePath $Root $command.stdout.evidenceFile) 65536).Trim()
    }
    if ($Manifest.platform -ceq "windows") {
        if ($seen.Count -ne 1 -or -not $seen.Contains("swift") -or $versions.swift -notmatch '(?m)^Swift version [0-9]+\.[0-9]+' -or
            ($versions.swift -split "`n")[0].TrimEnd("`r") -cne $Manifest.toolchain.versionLine) { throw "RGB_WINDOWS_VERSION_IDENTITY_MISMATCH" }
        if ($null -ne $Manifest.sourceCompilation.moduleCacheRoot) { throw "RGB_WINDOWS_NATIVE_MODULE_CACHE_CLAIM" }
        if ($Manifest.sourceCompilation.state -ceq "compiled") {
            foreach ($path in @("Sources/WinSwiftUI/Core.swift", "Sources/WinSwiftUI/ColorSpaceConversion.swift")) {
                if (@($Manifest.source.buildInputs | Where-Object { $_.path -ceq $path }).Count -ne 1) { throw "RGB_WINDOWS_DEPENDENCY_SOURCE_MISSING" }
            }
        }
        if ($null -ne $Manifest.sourceCompilation.buildCommandId) {
            $build = $Commands[$Manifest.sourceCompilation.buildCommandId]
            Assert-SwiftUIColorRGBToolCommand $build $tools.swift
            Assert-SwiftUIColorRGBArguments $build.arguments @("build", "--package-path", $Manifest.source.repositoryRoot, "--configuration", "release", "--product", "swiftui-color-rgb-reference")
            $targetArchitecture = if ($Manifest.runtimeEligibility.processArchitecture -ceq "arm64") { "aarch64" } else { "x86_64" }
            $expectedTarget = "$targetArchitecture-unknown-windows-msvc"
            if ($Manifest.sourceCompilation.buildTarget -cne $expectedTarget -or $versions.swift -cnotmatch ("(?m)^Target: " + [regex]::Escape($expectedTarget) + '[ \t]*\r?$')) { throw "RGB_WINDOWS_BUILD_TARGET_MISMATCH" }
        }
        if ($null -ne $Manifest.binary) {
            if ($Manifest.sourceCompilation.binaryPathCommandId -isnot [string] -or -not $Commands.ContainsKey($Manifest.sourceCompilation.binaryPathCommandId)) { throw "RGB_WINDOWS_BINARY_PATH_COMMAND_MISSING" }
            $pathCommand = $Commands[$Manifest.sourceCompilation.binaryPathCommandId]
            Assert-SwiftUIColorRGBToolCommand $pathCommand $tools.swift
            Assert-SwiftUIColorRGBArguments $pathCommand.arguments @("build", "--package-path", $Manifest.source.repositoryRoot, "--configuration", "release", "--show-bin-path")
            if (-not (Test-SwiftUIColorRGBCommandSucceeded $pathCommand)) { throw "RGB_WINDOWS_BINARY_PATH_COMMAND_FAILED" }
            $directory = (Read-SwiftUIColorRGBText (Get-SwiftUIColorRGBEvidencePath $Root $pathCommand.stdout.evidenceFile) 65536).Trim().Replace('\', '/').TrimEnd('/')
            if ($directory -match '[\r\n]' -or $directory -match '(^|/)\.\.?(/|$)' -or
                -not $directory.StartsWith($Manifest.source.repositoryRoot.TrimEnd('/') + "/.build/", [StringComparison]::OrdinalIgnoreCase) -or
                $Manifest.binary.originalPath -cne ($directory + "/swiftui-color-rgb-reference.exe")) { throw "RGB_WINDOWS_BINARY_BUILD_OUTPUT_MISMATCH" }
        }
        return
    }
    if ($seen.Count -ne 3 -or $null -eq $Manifest.sdk) { throw "RGB_NATIVE_TOOL_OR_SDK_PROVENANCE_MISSING" }
    $sdkCapture = Read-SwiftUIColorRGBJson (Get-SwiftUIColorRGBEvidencePath $Root $Manifest.sdk.files.capture.evidenceFile) -MaxBytes 16777216
    $baseline = Read-SwiftUIBaselineManifest (Get-SwiftUIColorRGBEvidencePath $Root $Manifest.sdk.files.baseline.evidenceFile)
    if ($Manifest.toolchain.sdkPath -cne $sdkCapture.sdk.path -or $Manifest.toolchain.versionLine -cne $sdkCapture.observedIdentity.swiftCompilerVersionLine) { throw "RGB_NATIVE_SDK_TOOLCHAIN_MISMATCH" }
    $capturedSwift = @($sdkCapture.tools | Where-Object { [IO.Path]::GetFileName($_.path) -ceq "swift" })
    if ($capturedSwift.Count -ne 1 -or $tools.swift.path -cne $capturedSwift[0].path -or $tools.swift.sha256 -cne $capturedSwift[0].sha256) { throw "RGB_NATIVE_CAPTURED_SWIFT_MISMATCH" }
    $toolDirectory = $tools.swift.path.Substring(0, $tools.swift.path.LastIndexOf('/'))
    foreach ($role in @("swiftc", "swift-frontend")) { if ($tools[$role].path -cne "$toolDirectory/$role") { throw "RGB_NATIVE_TOOL_NOT_CAPTURED_XCODEDEFAULT" } }
    foreach ($role in @("swift", "swiftc", "swift-frontend")) {
        $identity = ConvertTo-SwiftUIBaselineIdentity -XcodeOutput ("Xcode " + $sdkCapture.observedIdentity.xcodeVersion + "`nBuild version " + $sdkCapture.observedIdentity.xcodeBuildVersion) `
            -SDKVersion $sdkCapture.observedIdentity.sdkVersion -SDKBuildVersion $sdkCapture.observedIdentity.sdkBuildVersion -SwiftOutput $versions[$role]
        [void](Assert-SwiftUIBaselineIdentity -Manifest $baseline -Identity $identity)
        foreach ($field in @("xcodeVersion", "xcodeBuildVersion", "sdkVersion", "sdkBuildVersion", "swiftCompilerVersion", "swiftCompilerVersionLine")) {
            if ($identity.$field -cne $sdkCapture.observedIdentity.$field) { throw "RGB_NATIVE_VERSION_BUILD_MISMATCH" }
        }
    }
    if ($Manifest.sourceCompilation.typechecks.Count -eq 0 -and $null -eq $Manifest.sourceCompilation.buildCommandId) { return }
    Assert-SwiftUIColorRGBString $Manifest.sourceCompilation.moduleCacheRoot "moduleCacheRoot"
    $cacheRoot = $Manifest.sourceCompilation.moduleCacheRoot
    if (-not $cacheRoot.StartsWith('/') -or $cacheRoot.Contains('\') -or $cacheRoot -match '(^|/)\.\.?(/|$)' -or
        -not $cacheRoot.EndsWith("/swiftui-color-rgb-cache-$($Manifest.captureId)", [StringComparison]::Ordinal)) { throw "RGB_NATIVE_MODULE_CACHE_IDENTITY_INVALID" }
    $sourcePaths = @(Get-SwiftUIColorRGBSourceNames | ForEach-Object { $Manifest.source.repositoryRoot.TrimEnd('/') + '/' + $_ })
    $common = @("-parse-as-library", "-swift-version", "6", "-module-name", "SwiftUIColorRGBReference", "-sdk", $Manifest.toolchain.sdkPath)
    foreach ($typecheck in $Manifest.sourceCompilation.typechecks) {
        $command = $Commands[$typecheck.commandId]
        $architecture = $typecheck.target.Split('-')[0]
        Assert-SwiftUIColorRGBToolCommand $command $tools.swiftc
        Assert-SwiftUIColorRGBArguments $command.arguments ($common + @("-target", $typecheck.target, "-module-cache-path", "$cacheRoot/$architecture", "-typecheck") + $sourcePaths)
    }
    if ($null -ne $Manifest.sourceCompilation.buildCommandId) {
        $command = $Commands[$Manifest.sourceCompilation.buildCommandId]
        $target = "$($Manifest.runtimeEligibility.hardwareArchitecture)-apple-macosx26.5"
        if ($Manifest.sourceCompilation.buildTarget -cne $target) { throw "RGB_NATIVE_BUILD_TARGET_MISMATCH" }
        Assert-SwiftUIColorRGBToolCommand $command $tools.swiftc
        Assert-SwiftUIColorRGBArguments $command.arguments ($common + @("-target", $target, "-module-cache-path", "$cacheRoot/native-host", "-O", "-framework", "SwiftUI", "-framework", "AppKit", "-o", ($Manifest.originalOutputRoot + "/reference-executable")) + $sourcePaths)
    }
    if ($null -ne $Manifest.sourceCompilation.binaryPathCommandId -or ($null -ne $Manifest.binary -and $Manifest.binary.originalPath -cne ($Manifest.originalOutputRoot + "/reference-executable"))) { throw "RGB_NATIVE_BINARY_BUILD_OUTPUT_MISMATCH" }
}

function Read-SwiftUIColorRGBCapture {
    param([Parameter(Mandatory)][string]$Root)
    $manifestPath = Get-SwiftUIColorRGBEvidencePath $Root "capture.json"
    $sealPath = Get-SwiftUIColorRGBEvidencePath $Root "capture.sha256"
    $hash = Get-SwiftUIColorRGBHash $manifestPath
    if ((Read-SwiftUIColorRGBText $sealPath 1024).Trim() -cne "$hash  capture.json") { throw "RGB_CAPTURE_SEAL_MISMATCH" }
    $manifest = Read-SwiftUIColorRGBJson $manifestPath -MaxBytes 16777216
    Assert-SwiftUIColorRGBObject $manifest "capture" @("schemaVersion", "evidenceKind", "protocolId", "caseSetId", "toleranceId", "captureId", "originalOutputRoot", "platform", "status", "startedAtUtc", "finishedAtUtc", "source", "sourceCompilation", "runtimeEligibility", "toolchain", "sdk", "binary", "commands", "bootstrapCommands", "runs", "auxiliaryFiles", "observerControls", "integrity", "qualification", "failureCodes")
    $p = Get-SwiftUIColorRGBProtocol
    Assert-SwiftUIColorRGBInteger $manifest.schemaVersion "capture.schemaVersion" 1 1
    foreach ($field in @("protocolId", "caseSetId", "toleranceId")) {
        Assert-SwiftUIColorRGBString $manifest.$field "capture.$field"
        if ($manifest.$field -cne $p.$field) { throw "RGB_CAPTURE_PROTOCOL_MISMATCH" }
    }
    foreach ($field in @("evidenceKind", "captureId", "originalOutputRoot", "platform", "status", "startedAtUtc", "finishedAtUtc")) { Assert-SwiftUIColorRGBString $manifest.$field "capture.$field" }
    if ($manifest.originalOutputRoot -cnotmatch '^(?:[A-Za-z]:/|/)' -or $manifest.originalOutputRoot.Contains('\') -or $manifest.originalOutputRoot.EndsWith('/')) { throw "RGB_ORIGINAL_OUTPUT_ROOT_INVALID" }
    if ($manifest.evidenceKind -cne "color-rgb-reference-candidate" -or
        $manifest.captureId -cnotmatch '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' -or
        $manifest.platform -cnotin @("windows", "native") -or $manifest.status -cnotin @("captured-candidate", "unsupported", "failure")) { throw "RGB_CAPTURE_IDENTITY_INVALID" }
    Assert-SwiftUIColorRGBObject $manifest.qualification "qualification" @("declarationReview", "sourceReview", "behaviorReview", "releaseQualified")
    foreach ($field in @("declarationReview", "sourceReview", "behaviorReview")) {
        if ($manifest.qualification.$field -isnot [string] -or $manifest.qualification.$field -cne "unverified") { throw "RGB_CAPTURE_CANNOT_PROMOTE_QUALIFICATION" }
    }
    if ($manifest.qualification.releaseQualified -isnot [bool] -or $manifest.qualification.releaseQualified -ne $false) { throw "RGB_CAPTURE_CANNOT_PROMOTE_QUALIFICATION" }
    Assert-SwiftUIColorRGBArray $manifest.failureCodes "failureCodes" 0 256
    foreach ($failure in $manifest.failureCodes) { Assert-SwiftUIColorRGBString $failure "failureCode" }
    Assert-SwiftUIColorRGBArray $manifest.auxiliaryFiles "auxiliaryFiles" 0 128
    foreach ($entry in $manifest.auxiliaryFiles) { [void](Assert-SwiftUIColorRGBFileRecord $Root $entry 16777216) }
    Assert-SwiftUIColorRGBObject $manifest.integrity "integrity" @("sourceUnchanged", "toolsUnchanged", "executableUnchanged", "sdkCaptureUnchanged")
    foreach ($field in @("sourceUnchanged", "toolsUnchanged", "executableUnchanged", "sdkCaptureUnchanged")) { Assert-SwiftUIColorRGBBoolean $manifest.integrity.$field "integrity.$field" }
    if ($null -ne $manifest.source) { Assert-SwiftUIColorRGBSourceSnapshot $Root $manifest.source }
    Assert-SwiftUIColorRGBArray $manifest.commands "commands" 0 96
    Assert-SwiftUIColorRGBArray $manifest.bootstrapCommands "bootstrapCommands" 0 32
    $commands = @{}
    foreach ($command in @($manifest.commands) + @($manifest.bootstrapCommands)) {
        Assert-SwiftUIColorRGBCommandRecord $Root $command
        if ($commands.ContainsKey($command.commandId)) { throw "RGB_DUPLICATE_COMMAND_ID" }
        $commands.Add($command.commandId, $command)
    }
    Assert-SwiftUIColorRGBObject $manifest.sourceCompilation "sourceCompilation" @("state", "typechecks", "buildCommandId", "buildTarget", "moduleCacheRoot", "binaryPathCommandId")
    if ($manifest.sourceCompilation.state -isnot [string] -or $manifest.sourceCompilation.state -cnotin @("compiled", "failure", "not-run")) { throw "RGB_SOURCE_COMPILATION_STATE_INVALID" }
    Assert-SwiftUIColorRGBArray $manifest.sourceCompilation.typechecks "typechecks" 0 2
    $seenTargets = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($typecheck in $manifest.sourceCompilation.typechecks) {
        Assert-SwiftUIColorRGBObject $typecheck "typecheck" @("target", "commandId", "state", "nativeExecution")
        if ($typecheck.target -cnotin @("arm64-apple-macosx26.5", "x86_64-apple-macosx26.5") -or -not $seenTargets.Add($typecheck.target) -or
            $typecheck.commandId -isnot [string] -or -not $commands.ContainsKey($typecheck.commandId) -or $typecheck.nativeExecution -isnot [bool] -or $typecheck.nativeExecution -ne $false) { throw "RGB_TYPECHECK_ATTRIBUTION_INVALID" }
        $expectedState = if (Test-SwiftUIColorRGBCommandSucceeded $commands[$typecheck.commandId]) { "typechecked" } else { "failure" }
        if ($typecheck.state -cne $expectedState -or $commands[$typecheck.commandId].arguments -cnotcontains "-typecheck" -or $commands[$typecheck.commandId].arguments -cnotcontains $typecheck.target) { throw "RGB_TYPECHECK_OUTCOME_INVALID" }
    }
    if ($manifest.sourceCompilation.state -ceq "compiled") {
        if ($null -eq $manifest.source -or $manifest.sourceCompilation.buildCommandId -isnot [string] -or
            -not $commands.ContainsKey($manifest.sourceCompilation.buildCommandId) -or
            -not (Test-SwiftUIColorRGBCommandSucceeded $commands[$manifest.sourceCompilation.buildCommandId])) { throw "RGB_SOURCE_COMPILE_NOT_PROVEN" }
        if ($manifest.platform -ceq "native" -and ($seenTargets.Count -ne 2 -or @($manifest.sourceCompilation.typechecks | Where-Object { $_.state -cne "typechecked" }).Count -ne 0)) { throw "RGB_SOURCE_COMPILE_REQUIRES_BOTH_ARCHITECTURES" }
        if ($manifest.platform -ceq "windows" -and $seenTargets.Count -ne 0) { throw "RGB_WINDOWS_CANNOT_CLAIM_NATIVE_TYPECHECKS" }
    }
    Assert-SwiftUIColorRGBObject $manifest.runtimeEligibility "runtimeEligibility" @("state", "reason", "processArchitecture", "hardwareArchitecture", "translated", "operatingSystemVersion", "operatingSystemBuild")
    if ($manifest.runtimeEligibility.state -isnot [string] -or $manifest.runtimeEligibility.state -cnotin @("eligible", "unsupported", "not-evaluated")) { throw "RGB_RUNTIME_ELIGIBILITY_STATE_INVALID" }
    if ($manifest.runtimeEligibility.state -ceq "eligible") {
        foreach ($field in @("processArchitecture", "hardwareArchitecture", "operatingSystemVersion", "operatingSystemBuild")) { Assert-SwiftUIColorRGBString $manifest.runtimeEligibility.$field "runtimeEligibility.$field" }
        if ($manifest.runtimeEligibility.processArchitecture -cnotin @("arm64", "x86_64") -or $manifest.runtimeEligibility.hardwareArchitecture -cnotin @("arm64", "x86_64") -or
            $manifest.runtimeEligibility.translated -isnot [bool] -or $null -ne $manifest.runtimeEligibility.reason) { throw "RGB_RUNTIME_NOT_NATIVE_HOST" }
        if ($manifest.runtimeEligibility.translated -ne ($manifest.runtimeEligibility.processArchitecture -cne $manifest.runtimeEligibility.hardwareArchitecture)) { throw "RGB_RUNTIME_ARCHITECTURE_FACTS_INCONSISTENT" }
        if ($manifest.platform -ceq "native" -and ([version]$manifest.runtimeEligibility.operatingSystemVersion -lt [version]"26.5" -or $manifest.runtimeEligibility.processArchitecture -cne $manifest.runtimeEligibility.hardwareArchitecture)) { throw "RGB_RUNTIME_BELOW_NATIVE_REQUIREMENT" }
    } else { Assert-SwiftUIColorRGBString $manifest.runtimeEligibility.reason "runtimeEligibility.reason" }
    if ($null -ne $manifest.binary) {
        Assert-SwiftUIColorRGBObject $manifest.binary "binary" @("originalPath", "file")
        Assert-SwiftUIColorRGBString $manifest.binary.originalPath "binary.originalPath"
        [void](Assert-SwiftUIColorRGBFileRecord $Root $manifest.binary.file)
    }
    if ($null -ne $manifest.toolchain) {
        Assert-SwiftUIColorRGBObject $manifest.toolchain "toolchain" @("kind", "versionLine", "sdkPath", "tools", "versionCommands")
        Assert-SwiftUIColorRGBString $manifest.toolchain.kind "toolchain.kind"
        Assert-SwiftUIColorRGBString $manifest.toolchain.versionLine "toolchain.versionLine"
        Assert-SwiftUIColorRGBString $manifest.toolchain.sdkPath "toolchain.sdkPath"
        Assert-SwiftUIColorRGBArray $manifest.toolchain.tools "toolchain.tools" 3 3
        $roles = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
        foreach ($tool in $manifest.toolchain.tools) {
            Assert-SwiftUIColorRGBObject $tool "tool" @("role", "path", "sha256", "bytes")
            if ($tool.role -cnotin @("swift", "swiftc", "swift-frontend") -or -not $roles.Add($tool.role) -or
                $tool.sha256 -isnot [string] -or $tool.sha256 -cnotmatch '^[0-9a-f]{64}$') { throw "RGB_TOOL_IDENTITY_INVALID" }
            Assert-SwiftUIColorRGBString $tool.path "tool.path"
            Assert-SwiftUIColorRGBInteger $tool.bytes "tool.bytes" 1 1073741824
        }
        $expectedKind = if ($manifest.platform -ceq "native") { "pinned-xcode" } else { "windows-with-swift" }
        if ($manifest.toolchain.kind -cne $expectedKind) { throw "RGB_TOOLCHAIN_KIND_MISMATCH" }
    }
    if ($manifest.platform -ceq "native" -and $null -ne $manifest.sdk) { Assert-SwiftUIColorRGBArchivedSDK $Root $manifest.sdk }
    elseif ($manifest.platform -ceq "windows" -and $null -ne $manifest.sdk) { throw "RGB_WINDOWS_NATIVE_SDK_CLAIM" }
    Assert-SwiftUIColorRGBCompilationBinding $Root $manifest $commands
    Assert-SwiftUIColorRGBArray $manifest.runs "runs" 0 6
    $runKeys = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    $nonces = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    $reports = @{ "windows-retained" = @(); "swiftui-resolved" = @(); "appkit-extended-srgb" = @() }
    $invalidRuns = [System.Collections.Generic.List[object]]::new()
    foreach ($run in @($manifest.runs | Sort-Object repetition)) {
        Assert-SwiftUIColorRGBObject $run "run" @("observer", "repetition", "runId", "commandId", "report", "reportState", "reasonCode")
        Assert-SwiftUIColorRGBInteger $run.repetition "run.repetition" 1 3
        foreach ($field in @("observer", "runId", "commandId", "reportState")) { Assert-SwiftUIColorRGBString $run.$field "run.$field" }
        $allowedObservers = if ($manifest.platform -ceq "windows") { @("windows-retained") } else { @("swiftui-resolved", "appkit-extended-srgb") }
        if ($run.observer -cnotin $allowedObservers -or -not $runKeys.Add("$($run.observer):$($run.repetition)") -or
            $run.runId -cnotmatch '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' -or -not $nonces.Add($run.runId) -or
            -not $commands.ContainsKey($run.commandId) -or $run.reportState -cnotin @("valid", "invalid", "missing")) { throw "RGB_RUN_IDENTITY_INVALID" }
        if ($null -ne $run.report) { $reportPath = Assert-SwiftUIColorRGBFileRecord $Root $run.report 2097152 }
        $command = $commands[$run.commandId]
        if ($run.reportState -ceq "valid") {
            if ($null -eq $run.report -or $null -ne $run.reasonCode -or -not (Test-SwiftUIColorRGBCommandSucceeded $command) -or $null -eq $manifest.binary -or
                $command.executableSha256 -cne $manifest.binary.file.sha256 -or $command.executable -cne $manifest.binary.originalPath) { throw "RGB_VALID_REPORT_PROCESS_NOT_PROVEN" }
            # The last path is recorded explicitly in the invocation and must
            # name this report beneath the collection output, even after moving
            # the sealed directory to another machine for comparison.
            if ($command.arguments.Count -ne 6 -or $command.arguments[0] -cne "--observer" -or $command.arguments[1] -cne $run.observer -or
                $command.arguments[2] -cne "--run-id" -or $command.arguments[3] -cne $run.runId -or $command.arguments[4] -cne "--output" -or
                $command.arguments[5] -cne ($manifest.originalOutputRoot + "/" + $run.report.evidenceFile)) { throw "RGB_REPORT_COMMAND_ARGUMENTS_MISMATCH" }
            $validated = Read-SwiftUIColorRGBReport -Path $reportPath -ExpectedObserver $run.observer -ExpectedRunId $run.runId -ExpectedArchitecture $manifest.runtimeEligibility.processArchitecture
            if ($validated.report.runtime.processId -ne $command.processId) { throw "RGB_REPORT_PID_MISMATCH" }
            $observedVersion = [version]$validated.report.runtime.operatingSystemVersion
            $hostVersion = [version]$manifest.runtimeEligibility.operatingSystemVersion
            if ($observedVersion.Major -ne $hostVersion.Major -or $observedVersion.Minor -ne $hostVersion.Minor -or $observedVersion.Build -ne $hostVersion.Build) { throw "RGB_REPORT_OS_VERSION_MISMATCH" }
            $reports[$run.observer] += $validated
        } else {
            Assert-SwiftUIColorRGBString $run.reasonCode "run.reasonCode"
            $invalidRuns.Add($run)
        }
    }
    Assert-SwiftUIColorRGBArray $manifest.observerControls "observerControls" 0 2
    $seenControls = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($control in $manifest.observerControls) {
        Assert-SwiftUIColorRGBObject $control "observerControl" @("observer", "state", "reasons")
        if ($control.observer -cnotin @("windows-retained", "swiftui-resolved", "appkit-extended-srgb") -or -not $seenControls.Add($control.observer)) { throw "RGB_DUPLICATE_OBSERVER_CONTROL" }
        Assert-SwiftUIColorRGBArray $control.reasons "observerControl.reasons" 0 1024
        foreach ($reason in $control.reasons) { Assert-SwiftUIColorRGBString $reason "observerControl.reason" }
        $expectedControl = if ($manifest.runtimeEligibility.state -ceq "unsupported") { [pscustomobject]@{ state = "unsupported"; reasons = @($manifest.runtimeEligibility.reason) } } else { Test-SwiftUIColorRGBObserverControls $reports[$control.observer] $control.observer }
        if ($control.state -cne $expectedControl.state -or ($control.reasons -join "`n") -cne ($expectedControl.reasons -join "`n")) { throw "RGB_OBSERVER_CONTROL_CLASSIFICATION_MISMATCH" }
    }
    if ($manifest.status -ceq "captured-candidate") {
        if ($manifest.sourceCompilation.state -cne "compiled" -or $manifest.runtimeEligibility.state -cne "eligible" -or $null -eq $manifest.toolchain -or
            $null -eq $manifest.binary -or $invalidRuns.Count -gt 0 -or $manifest.failureCodes.Count -ne 0 -or
            @($manifest.integrity.PSObject.Properties | Where-Object { $_.Value -ne $true }).Count -gt 0) { throw "RGB_CAPTURE_SUCCESS_INCONSISTENT" }
        $expectedCount = if ($manifest.platform -ceq "windows") { 3 } else { 6 }
        if ($manifest.runs.Count -ne $expectedCount) { throw "RGB_CAPTURE_REPETITIONS_INCOMPLETE" }
        $expectedControls = if ($manifest.platform -ceq "windows") { @("windows-retained") } else { @("swiftui-resolved", "appkit-extended-srgb") }
        if ($seenControls.Count -ne $expectedControls.Count -or @($manifest.observerControls | Where-Object { $_.state -cne "healthy" }).Count -gt 0) { throw "RGB_CAPTURE_CONTROLS_NOT_HEALTHY" }
        foreach ($observer in $expectedControls) { if (-not $seenControls.Contains($observer)) { throw "RGB_CAPTURE_OBSERVER_CONTROL_MISSING" } }
        if ($manifest.platform -ceq "native" -and $null -eq $manifest.sdk) { throw "RGB_NATIVE_SDK_PROVENANCE_MISSING" }
    }
    if ($manifest.runtimeEligibility.reason -ceq "requested-platform-unavailable") {
        if ($manifest.status -cne "unsupported" -or $manifest.runtimeEligibility.state -cne "unsupported" -or
            $manifest.sourceCompilation.state -cne "not-run" -or $manifest.sourceCompilation.typechecks.Count -ne 0 -or
            $null -ne $manifest.sourceCompilation.buildCommandId -or $null -ne $manifest.sourceCompilation.buildTarget -or
            $null -ne $manifest.sourceCompilation.moduleCacheRoot -or $null -ne $manifest.sourceCompilation.binaryPathCommandId -or
            $null -ne $manifest.source -or $null -ne $manifest.toolchain -or $null -ne $manifest.binary -or $null -ne $manifest.sdk -or
            $manifest.commands.Count -ne 0 -or $manifest.bootstrapCommands.Count -ne 0 -or $manifest.runs.Count -ne 0 -or
            $manifest.observerControls.Count -ne 0 -or $manifest.failureCodes.Count -ne 0 -or $manifest.integrity.sourceUnchanged -ne $false -or
            $manifest.integrity.toolsUnchanged -ne $false -or $manifest.integrity.executableUnchanged -ne $false) { throw "RGB_PLATFORM_UNAVAILABLE_RECORD_INCONSISTENT" }
    }
    return [pscustomobject]@{ root = $Root; manifest = $manifest; manifestSha256 = $hash; reports = $reports; invalidRuns = @($invalidRuns.ToArray()) }
}

function Assert-SwiftUIColorRGBArchivedSDK {
    param([string]$Root, $SDK)
    Assert-SwiftUIColorRGBObject $SDK "sdk" @("validationMethod", "beforeVerified", "afterVerified", "captureRoot", "baselineId", "observedIdentity", "files")
    if ($SDK.validationMethod -cne "Read-SwiftUIMaterialSDKContext" -or $SDK.beforeVerified -isnot [bool] -or $SDK.afterVerified -isnot [bool] -or $SDK.beforeVerified -ne $true -or $SDK.afterVerified -ne $true) { throw "RGB_SDK_VALIDATION_NOT_PROVEN" }
    Assert-SwiftUIColorRGBString $SDK.captureRoot "sdk.captureRoot"
    Assert-SwiftUIColorRGBObject $SDK.files "sdk.files" @("capture", "status", "seal", "baseline", "settings")
    $paths = @{}
    foreach ($field in @("capture", "status", "seal", "baseline", "settings")) { $paths[$field] = Assert-SwiftUIColorRGBFileRecord $Root $SDK.files.$field 16777216 }
    $capture = Read-SwiftUIColorRGBJson $paths.capture -MaxBytes 16777216
    $status = Read-SwiftUIColorRGBJson $paths.status -MaxBytes 65536
    Assert-SwiftUIMaterialFields $status "Archived SDK status" -Strings @("status", "captureManifest", "captureManifestSha256", "baselineId", "behaviorConformance")
    Assert-SwiftUIMaterialFields $capture "Archived SDK capture" -Strings @("baselineId", "status", "developerDirectoryOverride") -Numbers @("schemaVersion") `
        -Booleans @("exactIdentityPreviouslyReviewed") -Arrays @("tools") -Objects @("observedIdentity", "host", "baselineManifest", "sdk", "qualification")
    Assert-SwiftUIMaterialFields $capture.observedIdentity "Archived SDK identity" -Strings @("xcodeVersion", "xcodeBuildVersion", "sdkVersion", "sdkBuildVersion", "swiftCompilerVersion", "swiftCompilerVersionLine")
    Assert-SwiftUIMaterialFields $capture.baselineManifest "Archived SDK baseline" -Strings @("path", "sha256")
    Assert-SwiftUIMaterialFields $capture.sdk "Archived SDK settings" -Strings @("path", "version", "buildVersion", "settingsPath", "settingsSha256")
    Assert-SwiftUIMaterialFields $capture.qualification "Archived SDK qualification" -Booleans @("publicAPIAuditComplete", "behaviorConformanceVerified", "releaseQualified")
    [void](Read-SwiftUIColorRGBJson $paths.baseline -MaxBytes 1048576)
    $baseline = Read-SwiftUIBaselineManifest $paths.baseline
    if ((Read-SwiftUIColorRGBText $paths.seal 1024).Trim() -cne "$($SDK.files.capture.sha256)  capture.json" -or
        $status.status -cne "exported-awaiting-review" -or $status.captureManifest -cne "capture.json" -or
        $status.captureManifestSha256 -cne $SDK.files.capture.sha256 -or $status.behaviorConformance -cne "not-verified" -or
        $capture.schemaVersion -ne 1 -or $capture.status -cne "exported-awaiting-inventory-and-behavior-review" -or $capture.baselineId -cne $baseline.baselineId -or
        $SDK.baselineId -cne $baseline.baselineId -or $status.baselineId -cne $baseline.baselineId -or
        $capture.baselineManifest.path -cne "baseline-manifest.json" -or $capture.baselineManifest.sha256 -cne $SDK.files.baseline.sha256 -or
        $capture.sdk.settingsSha256 -cne $SDK.files.settings.sha256 -or $capture.sdk.settingsPath -cnotin @("SDKSettings.json", "SDKSettings.plist") -or
        $capture.sdk.version -cne $capture.observedIdentity.sdkVersion -or $capture.sdk.buildVersion -cne $capture.observedIdentity.sdkBuildVersion -or
        $capture.qualification.publicAPIAuditComplete -ne $false -or $capture.qualification.behaviorConformanceVerified -ne $false -or $capture.qualification.releaseQualified -ne $false) { throw "RGB_ARCHIVED_SDK_IDENTITY_MISMATCH" }
    if ($baseline.toolchain.xcodeVersion -cne "26.6" -or $baseline.toolchain.sdkVersion -cne "26.5" -or $baseline.toolchain.swiftCompilerMajorMinor -cne "6.3" -or $baseline.toolchain.swiftLanguageMode -cne "6") { throw "RGB_ARCHIVED_SDK_PIN_CHANGED" }
    $reviewed = Assert-SwiftUIBaselineIdentity -Manifest $baseline -Identity $capture.observedIdentity
    if ($capture.exactIdentityPreviouslyReviewed -ne $reviewed) { throw "RGB_ARCHIVED_SDK_REVIEW_STATUS_MISMATCH" }
    foreach ($field in @("xcodeVersion", "xcodeBuildVersion", "sdkVersion", "sdkBuildVersion", "swiftCompilerVersion", "swiftCompilerVersionLine")) {
        if ($SDK.observedIdentity.$field -cne $capture.observedIdentity.$field) { throw "RGB_ARCHIVED_SDK_BUILD_IDENTITY_MISMATCH" }
    }
    # This checks archived hashes/identity only. Live compiler/SDK containment
    # and success acceptance were (and must be) performed by the existing
    # Read-SwiftUIMaterialSDKContext on the collecting Mac, before and after.
    # It never substitutes for that validator or opens inventory.json.
}

function Read-SwiftUIColorRGBPinnedSDKContext {
    param([Parameter(Mandatory)][string]$CaptureRoot, [Parameter(Mandatory)][string]$ManifestPath)
    foreach ($name in @("capture.json", "capture-status.json", "baseline-manifest.json")) {
        [void](Read-SwiftUIColorRGBJson (Get-SwiftUIMaterialEvidenceFile $CaptureRoot $name) -MaxBytes 16777216)
    }
    [void](Read-SwiftUIColorRGBJson $ManifestPath)
    # Acceptance, compiler containment, live SDK hashes, and identity policy
    # stay in the shared validator. This wrapper only adds bounded strict JSON
    # and checks that this fixed color protocol has not changed its SDK pin.
    $context = Read-SwiftUIMaterialSDKContext -CaptureRoot $CaptureRoot -ManifestPath $ManifestPath
    if ($context.manifest.toolchain.xcodeVersion -cne "26.6" -or $context.manifest.toolchain.sdkVersion -cne "26.5" -or
        $context.manifest.toolchain.swiftCompilerMajorMinor -cne "6.3" -or $context.manifest.toolchain.swiftLanguageMode -cne "6") { throw "RGB_SDK_PROTOCOL_PIN_CHANGED" }
    return $context
}

function Set-SwiftUIColorRGBComparisonFailure {
    param([Parameter(Mandatory)]$Comparison, [Parameter(Mandatory)][string]$Code, [switch]$AssociationOnly)
    $Comparison.state = "failure"
    if ($null -ne $Comparison.PSObject.Properties["failureCodes"]) { $Comparison.failureCodes += $Code }
    if ($AssociationOnly) { return }
    if ($null -ne $Comparison.primary) { $Comparison.primary.state = "failure" }
    if ($null -ne $Comparison.appKit) { $Comparison.appKit.state = "failure" }
    if ($null -eq $Comparison.provenance) { $Comparison.provenance = [pscustomobject]@{ state = "failure"; reasons = @($Code) } }
    else { $Comparison.provenance.state = "failure"; $Comparison.provenance.reasons += $Code }
}

function Test-SwiftUIColorRGBContainedObserverFailure {
    param($Manifest, $Run, [System.Collections.IDictionary]$Commands)
    # Only an independently bound, cleanly exited adapter may fail without
    # invalidating another observer's provenance. Reason text is not proof of
    # scope, and transient executable/PID/OS/source/tool faults stay global.
    $allowed = if ($Manifest.platform -ceq "windows") { @("windows-retained") } else { @("swiftui-resolved", "appkit-extended-srgb") }
    if ($Run.observer -cnotin $allowed -or $Run.reasonCode -cnotin @("RGB_OBSERVER_REPORT_MISSING", "RGB_OBSERVER_PROCESS_FAILED") -or
        $null -eq $Manifest.binary -or -not $Commands.Contains($Run.commandId)) { return $false }
    $command = $Commands[$Run.commandId]
    if ($command.state -cne "exited" -or $command.cleanupComplete -ne $true -or $null -ne $command.errorCode -or
        $null -eq $command.processId -or $null -eq $command.exitCode -or
        $command.executable -cne $Manifest.binary.originalPath -or $command.executableSha256 -cne $Manifest.binary.file.sha256) { return $false }
    $reportName = "$($Run.observer)-$($Run.repetition).json"
    $expected = @("--observer", $Run.observer, "--run-id", $Run.runId, "--output", ($Manifest.originalOutputRoot + "/" + $reportName))
    if ($command.arguments.Count -ne $expected.Count) { return $false }
    for ($index = 0; $index -lt $expected.Count; $index++) { if ($command.arguments[$index] -cne $expected[$index]) { return $false } }
    if ($null -ne $Run.report -and $Run.report.evidenceFile -cne $reportName) { return $false }
    if ($Run.reasonCode -ceq "RGB_OBSERVER_REPORT_MISSING") { return ($Run.reportState -ceq "missing" -and $null -eq $Run.report) }
    return ($Run.reportState -ceq "invalid" -and $null -ne $Run.report -and $command.exitCode -ne 0)
}

function Compare-SwiftUIColorRGBCaptures {
    param([Parameter(Mandatory)]$WindowsCapture, [Parameter(Mandatory)]$NativeCapture)
    $win = $WindowsCapture.manifest; $native = $NativeCapture.manifest
    if ($win.platform -cne "windows" -or $native.platform -cne "native") { throw "RGB_CAPTURE_PLATFORM_ORDER_MISMATCH" }
    $primary = Compare-SwiftUIColorRGBObserver $WindowsCapture.reports["windows-retained"] $NativeCapture.reports["swiftui-resolved"] "swiftui-resolved"
    $appKit = Compare-SwiftUIColorRGBObserver $WindowsCapture.reports["windows-retained"] $NativeCapture.reports["appkit-extended-srgb"] "appkit-extended-srgb"
    $provenanceReasons = [System.Collections.Generic.List[string]]::new()
    $unavailablePlatforms = [System.Collections.Generic.List[string]]::new()
    foreach ($validatedCapture in @($WindowsCapture, $NativeCapture)) {
        $capture = $validatedCapture.manifest
        if ($capture.status -ceq "unsupported" -and $capture.runtimeEligibility.state -ceq "unsupported" -and
            $capture.runtimeEligibility.reason -ceq "requested-platform-unavailable" -and $capture.sourceCompilation.state -ceq "not-run" -and
            $null -eq $capture.source -and $capture.runs.Count -eq 0 -and $capture.failureCodes.Count -eq 0 -and
            $null -eq $capture.toolchain -and $null -eq $capture.binary -and $null -eq $capture.sdk -and $capture.commands.Count -eq 0 -and $capture.bootstrapCommands.Count -eq 0) {
            $unavailablePlatforms.Add($capture.platform); continue
        }
        $commands = @{}
        foreach ($command in @($capture.commands) + @($capture.bootstrapCommands)) { $commands[$command.commandId] = $command }
        $explainedCodes = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
        $containedCommands = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
        $uncontainedObservers = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
        foreach ($run in $capture.runs) {
            if ($run.reportState -ceq "valid") { continue }
            if (Test-SwiftUIColorRGBContainedObserverFailure $capture $run $commands) {
                [void]$explainedCodes.Add($run.reasonCode); [void]$containedCommands.Add($run.commandId)
            } else {
                [void]$uncontainedObservers.Add($run.observer)
                $provenanceReasons.Add("uncontained-observer-failure:$($capture.platform):$($run.observer):$($run.repetition):$($run.reasonCode)")
            }
        }
        $allowedObservers = if ($capture.platform -ceq "windows") { @("windows-retained") } else { @("swiftui-resolved", "appkit-extended-srgb") }
        if ($capture.runtimeEligibility.state -ceq "eligible") {
            foreach ($observer in $allowedObservers) {
                $runs = @($capture.runs | Where-Object { $_.observer -ceq $observer })
                $control = Test-SwiftUIColorRGBObserverControls $validatedCapture.reports[$observer] $observer
                if ($control.state -ceq "failure" -and $runs.Count -eq 3 -and -not $uncontainedObservers.Contains($observer)) {
                    [void]$explainedCodes.Add("RGB_OBSERVER_FAILURE:$observer")
                }
            }
        }
        # Examine every recorded process and invalid run even when the
        # aggregate failureCodes array is missing or misleading.
        foreach ($command in $commands.Values) {
            if (-not (Test-SwiftUIColorRGBCommandSucceeded $command) -and -not $containedCommands.Contains($command.commandId)) {
                $provenanceReasons.Add("uncontained-command-failure:$($capture.platform):$($command.commandId)")
            }
        }
        foreach ($code in $capture.failureCodes) {
            if (-not $explainedCodes.Contains($code)) { $provenanceReasons.Add("global-capture-failure:$($capture.platform):$code") }
        }
        if ($capture.status -ceq "failure" -and ($capture.failureCodes.Count -eq 0 -or $explainedCodes.Count -eq 0)) { $provenanceReasons.Add("unexplained-failure-aggregate:$($capture.platform)") }
        if ($capture.sourceCompilation.state -cne "compiled") { $provenanceReasons.Add("source-not-compiled:$($capture.platform)") }
        if ($null -eq $capture.source -or $null -eq $capture.toolchain -or $null -eq $capture.binary) { $provenanceReasons.Add("build-provenance-missing:$($capture.platform)") }
        foreach ($field in @("sourceUnchanged", "toolsUnchanged", "executableUnchanged", "sdkCaptureUnchanged")) {
            if ($capture.integrity.$field -ne $true) { $provenanceReasons.Add("integrity-unverified:$($capture.platform):$field") }
        }
    }
    if ($null -ne $win.source -and $null -ne $native.source) {
        if ($win.source.commit -cne $native.source.commit -or $win.source.tree -cne $native.source.tree) { $provenanceReasons.Add("source-commit-or-tree-mismatch") }
        for ($i = 0; $i -lt 5; $i++) {
            if ($win.source.sharedSources[$i].path -cne $native.source.sharedSources[$i].path -or
                $win.source.sharedSources[$i].gitBlob -cne $native.source.sharedSources[$i].gitBlob -or
                $win.source.sharedSources[$i].file.sha256 -cne $native.source.sharedSources[$i].file.sha256) { $provenanceReasons.Add("compiled-shared-source-bytes-mismatch:$i") }
        }
    }
    if ($null -eq $native.sdk -and -not $unavailablePlatforms.Contains("native")) { $provenanceReasons.Add("native-sdk-validation-missing") }
    $provenanceState = "verified-for-candidate"
    if ($provenanceReasons.Count -gt 0) {
        $provenanceState = "failure"; $primary.state = "failure"; $appKit.state = "failure"
    } elseif ($win.runtimeEligibility.state -ceq "unsupported" -or $native.runtimeEligibility.state -ceq "unsupported") {
        $windowsFailure = $win.runtimeEligibility.state -ceq "eligible" -and $primary.windowsObserverControls.state -ceq "failure"
        $primaryFailure = $native.runtimeEligibility.state -ceq "eligible" -and $primary.nativeObserverControls.state -ceq "failure"
        $bridgeFailure = $native.runtimeEligibility.state -ceq "eligible" -and $appKit.nativeObserverControls.state -ceq "failure"
        $primary.state = if ($windowsFailure -or $primaryFailure) { "failure" } else { "unsupported" }
        $appKit.state = if ($windowsFailure -or $bridgeFailure) { "failure" } else { "unsupported" }
        if ($unavailablePlatforms.Count -gt 0) {
            $provenanceState = "not-evaluated"
            foreach ($platform in $unavailablePlatforms) { $provenanceReasons.Add("requested-platform-unavailable:$platform") }
        }
    } elseif ($win.runtimeEligibility.state -cne "eligible" -or $native.runtimeEligibility.state -cne "eligible") {
        $primary.state = "failure"; $appKit.state = "failure"
        $provenanceReasons.Add("runtime-eligibility-not-evaluated"); $provenanceState = "failure"
    }
    # A bridge-only failure does not veto a complete primary observation. The
    # capture's aggregate status alone is therefore never a primary gate.
    return [pscustomobject][ordered]@{
        state = $primary.state
        sourceCompilation = [pscustomobject]@{ windows = $win.sourceCompilation; native = $native.sourceCompilation }
        provenance = [pscustomobject]@{ state = $provenanceState; reasons = @($provenanceReasons.ToArray()) }
        primary = $primary; appKit = $appKit
    }
}

function Read-SwiftUIColorRGBReviewAssociation {
    param([Parameter(Mandatory)][string]$PacketRoot, [Parameter(Mandatory)][string]$PreciseIdentifier,
        [Parameter(Mandatory)]$WindowsCapture, [Parameter(Mandatory)]$NativeCapture)
    # Exact pinned declaration ID was located in the sealed four-occurrence
    # ledger. Association still requires an explicit immutable review packet;
    # this constant is not a Windows declaration mapping or semantic approval.
    $canonical = 's:7SwiftUI5ColorV_3red5green4blue7opacityA2C13RGBColorSpaceO_S4dtcfc'
    if ($PreciseIdentifier -cne $canonical) { throw "RGB_REVIEW_PRECISE_IDENTIFIER_MISMATCH" }
    $manifestPath = Get-SwiftUIColorRGBEvidencePath $PacketRoot "review-unit.json"
    $manifestHash = Get-SwiftUIColorRGBHash $manifestPath
    $sealPath = Get-SwiftUIColorRGBEvidencePath $PacketRoot "review-unit.sha256"
    if ((Read-SwiftUIColorRGBText $sealPath 1024).Trim() -cne "$manifestHash  review-unit.json") { throw "RGB_REVIEW_SEAL_MISMATCH" }
    $packet = Read-SwiftUIColorRGBJson $manifestPath -MaxBytes 16777216
    Assert-SwiftUIMaterialFields $packet "Review packet" -Numbers @("schemaVersion") -Strings @("baselineId", "evidenceKind", "status", "reviewStatus") `
        -Objects @("selection", "sourceCapture", "sourceAudit", "windowsSource") -Arrays @("claims", "evidenceReferences", "recordFiles", "sourceMetadataFiles")
    Assert-SwiftUIColorRGBInteger $packet.schemaVersion "review.schemaVersion" 1 1
    Assert-SwiftUIMaterialFields $packet.selection "Review selection" -Strings @("preciseIdentifier", "comparison", "closure") -Numbers @("declarationOccurrences") -Booleans @("standaloneNativeUniverse")
    Assert-SwiftUIColorRGBInteger $packet.selection.declarationOccurrences "review.selection.declarationOccurrences" 4 4
    Assert-SwiftUIMaterialFields $packet.sourceCapture "Review source capture" -Strings @("captureManifestSha256", "captureStatusSha256", "baselineManifestSha256")
    Assert-SwiftUIMaterialFields $packet.sourceAudit "Review source audit" -Strings @("manifestSha256", "sealSha256", "reviewStatus")
    Assert-SwiftUIMaterialFields $packet.windowsSource "Review Windows source" -Strings @("commit") -Arrays @("files")
    if ($packet.schemaVersion -ne 1 -or $packet.evidenceKind -cne "unreviewed-api-review-unit" -or
        $packet.status -cne "awaiting-declaration-source-and-behavior-review" -or $packet.reviewStatus -cne "unreviewed" -or
        $packet.selection.preciseIdentifier -cne $PreciseIdentifier -or $packet.selection.comparison -cne "ordinal-exact" -or
        $packet.selection.closure -cne "all-occurrences-and-source-or-target-incident-relationships" -or $packet.selection.standaloneNativeUniverse -ne $false) { throw "RGB_REVIEW_PACKET_IDENTITY_INVALID" }
    Assert-SwiftUIColorRGBArray $packet.claims "review.claims" 3 3
    $claims = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($claim in $packet.claims) {
        Assert-SwiftUIColorRGBObject $claim "review.claim" @("claimId", "kind", "status", "evidenceRefs")
        Assert-SwiftUIColorRGBString $claim.kind "review.claim.kind"
        Assert-SwiftUIColorRGBString $claim.status "review.claim.status"
        if ($claim.kind -cnotin @("declaration", "source-compatibility", "behavior") -or -not $claims.Add($claim.kind) -or $claim.status -cne "unverified" -or $claim.claimId -cne $claim.kind) { throw "RGB_REVIEW_CLAIM_MUST_REMAIN_UNVERIFIED" }
        Assert-SwiftUIColorRGBArray $claim.evidenceRefs "review.claim.evidenceRefs" 0 0
    }
    Assert-SwiftUIColorRGBArray $packet.evidenceReferences "review.evidenceReferences" 0 0
    if ($null -eq $NativeCapture.manifest.sdk -or $packet.baselineId -cne $NativeCapture.manifest.sdk.baselineId -or $packet.sourceAudit.reviewStatus -cne "unreviewed" -or
        $packet.sourceCapture.captureManifestSha256 -cne $NativeCapture.manifest.sdk.files.capture.sha256 -or
        $packet.sourceCapture.captureStatusSha256 -cne $NativeCapture.manifest.sdk.files.status.sha256 -or
        $packet.sourceCapture.baselineManifestSha256 -cne $NativeCapture.manifest.sdk.files.baseline.sha256 -or
        $packet.windowsSource.commit -cne $WindowsCapture.manifest.source.commit) { throw "RGB_REVIEW_SOURCE_PROVENANCE_MISMATCH" }
    $expectedNames = @("native/identity.ndjson", "native/occurrences.ndjson", "native/relationships.ndjson", "context/graph-fields.ndjson", "context/partitions.ndjson", "context/inventory-facts.ndjson", "context/interface-facts.ndjson", "context/overlay-facts.ndjson", "context/candidate-queues.ndjson")
    Assert-SwiftUIColorRGBArray $packet.recordFiles "review.recordFiles" 9 9
    $seen = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    [long]$totalBytes = 0
    foreach ($file in $packet.recordFiles) {
        if ($file.path -cnotin $expectedNames -or -not $seen.Add($file.path)) { throw "RGB_REVIEW_RECORD_SET_MISMATCH" }
        $record = [pscustomobject]@{ evidenceFile = $file.path; bytes = $file.bytes; sha256 = $file.sha256 }
        [void](Assert-SwiftUIColorRGBFileRecord $PacketRoot $record 536870912)
        $totalBytes += $file.bytes
        if ($totalBytes -gt 1073741824) { throw "RGB_REVIEW_BYTE_LIMIT" }
    }
    Assert-SwiftUIColorRGBArray $packet.sourceMetadataFiles "review.sourceMetadataFiles" 1 256
    $metadataNames = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($file in $packet.sourceMetadataFiles) {
        Assert-SwiftUIMaterialFields $file "Review metadata file" -Strings @("path", "sha256", "kind") -Numbers @("bytes")
        if (-not $metadataNames.Add($file.path)) { throw "RGB_REVIEW_DUPLICATE_METADATA_FILE" }
        $record = [pscustomobject]@{ evidenceFile = $file.path; bytes = $file.bytes; sha256 = $file.sha256 }
        [void](Assert-SwiftUIColorRGBFileRecord $PacketRoot $record 134217728)
        $totalBytes += $file.bytes
        if ($totalBytes -gt 1073741824) { throw "RGB_REVIEW_BYTE_LIMIT" }
    }
    foreach ($binding in @(
        @("source-audit-manifest", $packet.sourceAudit.manifestSha256), @("source-audit-seal", $packet.sourceAudit.sealSha256),
        @("capture-manifest", $NativeCapture.manifest.sdk.files.capture.sha256), @("capture-status", $NativeCapture.manifest.sdk.files.status.sha256),
        @("capture-seal", $NativeCapture.manifest.sdk.files.seal.sha256), @("captured-baseline-manifest", $NativeCapture.manifest.sdk.files.baseline.sha256)
    )) {
        $matching = @($packet.sourceMetadataFiles | Where-Object { $_.kind -ceq $binding[0] })
        if ($matching.Count -ne 1 -or $matching[0].sha256 -cne $binding[1]) { throw "RGB_REVIEW_COPIED_METADATA_BINDING_MISMATCH" }
    }
    $auditSeal = @($packet.sourceMetadataFiles | Where-Object { $_.kind -ceq "source-audit-seal" })[0]
    if ((Read-SwiftUIColorRGBText (Get-SwiftUIColorRGBEvidencePath $PacketRoot $auditSeal.path) 1024).Trim() -cne "$($packet.sourceAudit.manifestSha256)  audit.json") { throw "RGB_REVIEW_SOURCE_AUDIT_SEAL_MISMATCH" }
    $windowsFiles = [System.Collections.Generic.List[object]]::new()
    Assert-SwiftUIColorRGBArray $packet.windowsSource.files "review.windowsSource.files" 1 256
    foreach ($file in $packet.windowsSource.files) {
        Assert-SwiftUIMaterialFields $file "Review Windows file" -Strings @("path", "blobOid", "sha256", "copiedPath") -Numbers @("bytes")
        $record = [pscustomobject]@{ evidenceFile = $file.copiedPath; bytes = $file.bytes; sha256 = $file.sha256 }
        $copied = Assert-SwiftUIColorRGBFileRecord $PacketRoot $record 33554432
        if ((Get-SwiftUIColorRGBSourceByteIdentity $copied $file.blobOid) -cne "git-blob-exact") { throw "RGB_REVIEW_SOURCE_NOT_EXACT_GIT_BLOB" }
        $match = @($WindowsCapture.manifest.source.buildInputs | Where-Object { $_.path -ceq $file.path })
        if ($match.Count -ne 1 -or $match[0].gitBlob -cne $file.blobOid) { throw "RGB_REVIEW_WINDOWS_BLOB_MISMATCH" }
        $windowsFiles.Add([pscustomobject]@{ path = $file.path; blobOid = $file.blobOid; packetSha256 = $file.sha256; compiledPhysicalSha256 = $match[0].file.sha256; byteIdentity = $match[0].byteIdentity })
    }
    $occurrencePath = Get-SwiftUIColorRGBEvidencePath $PacketRoot "native/occurrences.ndjson"
    # Only this selected, bounded packet stream is parsed. No inventory or
    # source-wide occurrence stream is opened or reconstructed here.
    $text = Read-SwiftUIColorRGBText $occurrencePath 16777216
    $occurrences = [System.Collections.Generic.List[object]]::new()
    $keys = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($line in ($text -split "`n")) {
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        if ($line.Length -gt 2097152) { throw "RGB_REVIEW_OCCURRENCE_LINE_LIMIT" }
        $row = ConvertFrom-SwiftUIColorRGBJsonText -Text $line
        if ($row.preciseIdentifier -cne $PreciseIdentifier -or $row.requestedModule -cnotin @("SwiftUI", "SwiftUICore") -or
            $row.target -cnotin @("arm64-apple-macosx26.5", "x86_64-apple-macosx26.5")) { throw "RGB_REVIEW_OCCURRENCE_IDENTITY_MISMATCH" }
        Assert-SwiftUIColorRGBInteger $row.symbolIndex "review.occurrence.symbolIndex" 0 10000000
        $expectedPath = "graphs/$($row.target)/$($row.requestedModule)/$($row.requestedModule).symbols.json"
        if ($row.graphPath -cne $expectedPath -or -not $keys.Add("$($row.graphPath):$($row.symbolIndex):$PreciseIdentifier")) { throw "RGB_REVIEW_OCCURRENCE_KEY_INVALID" }
        $occurrences.Add([pscustomobject]@{ graphPath = $row.graphPath; symbolIndex = $row.symbolIndex; preciseIdentifier = $row.preciseIdentifier; requestedModule = $row.requestedModule; target = $row.target })
        if ($occurrences.Count -gt 256) { throw "RGB_REVIEW_OCCURRENCE_COUNT_LIMIT" }
    }
    if ($occurrences.Count -ne 4 -or $packet.selection.declarationOccurrences -ne $occurrences.Count) { throw "RGB_REVIEW_OCCURRENCE_COVERAGE_MISMATCH" }
    foreach ($target in @("arm64-apple-macosx26.5", "x86_64-apple-macosx26.5")) {
        foreach ($module in @("SwiftUI", "SwiftUICore")) {
            if (@($occurrences | Where-Object { $_.target -ceq $target -and $_.requestedModule -ceq $module }).Count -ne 1) { throw "RGB_REVIEW_OCCURRENCE_PARTITION_MISSING" }
        }
    }
    foreach ($field in @("manifestSha256", "sealSha256")) { if ($packet.sourceAudit.$field -isnot [string] -or $packet.sourceAudit.$field -cnotmatch '^[0-9a-f]{64}$') { throw "RGB_REVIEW_AUDIT_HASH_INVALID" } }
    if ((Get-SwiftUIColorRGBHash $manifestPath) -cne $manifestHash) { throw "RGB_REVIEW_PACKET_CHANGED" }
    return [pscustomobject]@{
        state = "linked-unverified"; packetRoot = $PacketRoot; packetManifestSha256 = $manifestHash
        packetSealSha256 = Get-SwiftUIColorRGBHash $sealPath; preciseIdentifier = $PreciseIdentifier
        sourceCaptureManifestSha256 = $packet.sourceCapture.captureManifestSha256
        sourceAuditManifestSha256 = $packet.sourceAudit.manifestSha256; sourceAuditSealSha256 = $packet.sourceAudit.sealSha256
        occurrenceKeyDefinition = "packet and source-audit hashes plus graphPath, symbolIndex, preciseIdentifier"
        occurrences = @($occurrences.ToArray()); windowsCommit = $packet.windowsSource.commit; windowsFiles = @($windowsFiles.ToArray())
        validationScope = "packet hashes and explicit occurrence/source association only; not full ledger semantic closure or Windows declaration approval"
        declarationReview = "unverified"; sourceReview = "unverified"; behaviorReview = "unverified"
    }
}
