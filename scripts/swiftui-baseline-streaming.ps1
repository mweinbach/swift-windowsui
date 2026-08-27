# The same bounded implementation runs on Windows PowerShell 5.1 and PowerShell 7.
# It uses only the runtime's C# compiler and standard .NET IO/cryptography APIs.
# Do not replace this with a whole-file JSON DOM: a single SDK graph exceeds 1 GB.
function Initialize-SwiftUIBaselineStreaming {
    $source = @'
using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Security.Cryptography;
using System.Text;

namespace SwiftUIBaseline.Streaming {
    public sealed class GraphInput {
        public string Path;
        public string RelativePath;
        public string RequestedModule;
        public string Target;
        public bool Primary;
    }

    public sealed class InventorySummary {
        public long Graphs;
        public long PreciseSymbols;
        public long DeclarationOccurrences;
        public long RelationshipOccurrences;
        public string GraphSetSha256;
        public string InventorySha256;
        public long InputBytes;
        public long OutputBytes;
        public long LargestRecordCharacters;
        public long PeakBufferedIndexBytes;
        public int PeakBufferedIndexRecords;
        public long InitialSortRuns;
        public int MergePasses;
        public int PeakOpenRunReaders;
        public long LargestOccurrenceGroup;
    }

    // This is a JSON grammar reader, not a brace/line splitter. Nested values are
    // retained as JSON text: numbers, null, empty arrays, unknown members and
    // escaped strings never pass through PowerShell's lossy/large object graph.
    internal sealed class JsonInput {
        private readonly TextReader reader;
        private readonly string text;
        private readonly string context;
        private readonly int maximumRecordCharacters;
        private readonly char[] buffer;
        private int index;
        private int available;
        private long position;
        private long recordStart = -1;
        public long LargestRecordCharacters;
        private const int MaximumDepth = 256;

        public JsonInput(TextReader input, string source, int maximum) {
            reader = input; context = source; maximumRecordCharacters = maximum;
            buffer = new char[65536];
        }
        private JsonInput(string input, string source, int maximum) {
            text = input; context = source; maximumRecordCharacters = maximum;
        }
        public int Peek() {
            if (text != null) return index < text.Length ? text[index] : -1;
            if (index == available) {
                available = reader.Read(buffer, 0, buffer.Length); index = 0;
                if (available == 0) return -1;
            }
            return buffer[index];
        }
        private int Take() {
            int value = Peek();
            if (value < 0) Fail("Unexpected end of JSON");
            index++; position++;
            if (recordStart >= 0 && position - recordStart > maximumRecordCharacters)
                Fail("JSON record exceeds MaximumRecordCharacters=" + maximumRecordCharacters +
                    "; increase the explicit resource budget, never truncate a declaration");
            return value;
        }
        public void White() {
            int value;
            while ((value = Peek()) == ' ' || value == '\t' || value == '\r' || value == '\n') Take();
        }
        public void Expect(char value) {
            White();
            if (Take() != value) Fail("Expected '" + value + "'");
        }
        public bool Consume(char value) {
            White();
            if (Peek() != value) return false;
            Take(); return true;
        }
        public void StartRecord() { White(); recordStart = position; }
        public void EndRecord() {
            LargestRecordCharacters = Math.Max(LargestRecordCharacters, position - recordStart);
            recordStart = -1;
        }
        public void EndDocument() {
            White();
            if (Peek() != -1) Fail("Trailing content after JSON document");
        }
        public void SkipUTF8BOM() { if (Peek() == 0xfeff) Take(); }
        private void Fail(string message) {
            throw new InvalidDataException(message + " in '" + context + "' at character " +
                position.ToString(CultureInfo.InvariantCulture) + ".");
        }
        private void Append(StringBuilder target, char value) {
            if (target == null) return;
            if (target.Length >= maximumRecordCharacters)
                Fail("JSON value exceeds MaximumRecordCharacters=" + maximumRecordCharacters);
            target.Append(value);
        }
        private static int Hex(int value) {
            if (value >= '0' && value <= '9') return value - '0';
            if (value >= 'a' && value <= 'f') return value - 'a' + 10;
            if (value >= 'A' && value <= 'F') return value - 'A' + 10;
            return -1;
        }
        private string String(StringBuilder raw, bool decode) {
            if (Take() != '"') Fail("Expected JSON string");
            Append(raw, '"');
            StringBuilder decoded = decode ? new StringBuilder() : null;
            while (true) {
                int value = Take(); Append(raw, (char)value);
                if (value == '"') break;
                if (value < 0x20) Fail("Unescaped control character in JSON string");
                if (value == '\\') {
                    value = Take(); Append(raw, (char)value);
                    switch (value) {
                        case '"': case '\\': case '/': break;
                        case 'b': value = '\b'; break;
                        case 'f': value = '\f'; break;
                        case 'n': value = '\n'; break;
                        case 'r': value = '\r'; break;
                        case 't': value = '\t'; break;
                        case 'u':
                            value = 0;
                            for (int digit = 0; digit < 4; digit++) {
                                int next = Take(); Append(raw, (char)next);
                                int hex = Hex(next);
                                if (hex < 0) Fail("Invalid JSON Unicode escape");
                                value = value * 16 + hex;
                            }
                            break;
                        default: Fail("Invalid JSON string escape"); break;
                    }
                }
                if (decoded != null) Append(decoded, (char)value);
            }
            return decoded == null ? null : decoded.ToString();
        }
        public string PropertyName() {
            White(); string result = String(null, true); Expect(':'); return result;
        }
        private void Literal(string expected, StringBuilder raw) {
            foreach (char value in expected) {
                if (Take() != value) Fail("Invalid JSON literal");
                Append(raw, value);
            }
        }
        private static bool Digit(int value) { return value >= '0' && value <= '9'; }
        private void Number(StringBuilder raw) {
            if (Peek() == '-') Append(raw, (char)Take());
            int value = Peek();
            if (value == '0') Append(raw, (char)Take());
            else {
                if (value < '1' || value > '9') Fail("Invalid JSON number");
                do { Append(raw, (char)Take()); } while (Digit(Peek()));
            }
            if (Peek() == '.') {
                Append(raw, (char)Take());
                if (!Digit(Peek())) Fail("JSON fraction requires digits");
                do { Append(raw, (char)Take()); } while (Digit(Peek()));
            }
            if (Peek() == 'e' || Peek() == 'E') {
                Append(raw, (char)Take());
                if (Peek() == '+' || Peek() == '-') Append(raw, (char)Take());
                if (!Digit(Peek())) Fail("JSON exponent requires digits");
                do { Append(raw, (char)Take()); } while (Digit(Peek()));
            }
        }
        private void Value(StringBuilder raw, int depth) {
            White();
            if (depth > MaximumDepth) Fail("JSON nesting exceeds 256 levels");
            switch (Peek()) {
                case '{':
                    Append(raw, (char)Take()); White();
                    if (Peek() != '}') {
                        while (true) {
                            String(raw, false); Expect(':'); Append(raw, ':');
                            Value(raw, depth + 1); White();
                            if (Peek() != ',') break;
                            Append(raw, (char)Take()); White();
                        }
                    }
                    Expect('}'); Append(raw, '}'); break;
                case '[':
                    Append(raw, (char)Take()); White();
                    if (Peek() != ']') {
                        while (true) {
                            Value(raw, depth + 1); White();
                            if (Peek() != ',') break;
                            Append(raw, (char)Take());
                        }
                    }
                    Expect(']'); Append(raw, ']'); break;
                case '"': String(raw, false); break;
                case 't': Literal("true", raw); break;
                case 'f': Literal("false", raw); break;
                case 'n': Literal("null", raw); break;
                default: Number(raw); break;
            }
        }
        public string RawValue() {
            StringBuilder result = new StringBuilder(); Value(result, 0); return result.ToString();
        }
        public void SkipValue() { Value(null, 0); }
        public Dictionary<string, string> ObjectFields() {
            Dictionary<string, string> result = new Dictionary<string, string>(StringComparer.Ordinal);
            Expect('{');
            if (Consume('}')) return result;
            do {
                string name = PropertyName();
                if (result.ContainsKey(name)) Fail("Duplicate object member '" + name + "'");
                result.Add(name, RawValue());
            } while (Consume(','));
            Expect('}'); return result;
        }
        public static Dictionary<string, string> Fields(string raw, string context, int maximum) {
            JsonInput input = new JsonInput(raw, context, maximum);
            Dictionary<string, string> result = input.ObjectFields(); input.EndDocument(); return result;
        }
        public static string DecodeString(string raw, string context, int maximum) {
            if (raw == null || raw.Length == 0 || raw[0] != '"')
                throw new InvalidDataException("Expected string in '" + context + "'.");
            JsonInput input = new JsonInput(raw, context, maximum);
            string result = input.String(null, true); input.EndDocument(); return result;
        }
    }

    internal sealed class IndexEntry {
        public string Identifier;
        public long Sequence;
        public long Offset;
        public static int Compare(IndexEntry first, IndexEntry second) {
            int identifier = StringComparer.Ordinal.Compare(first.Identifier, second.Identifier);
            return identifier == 0 ? first.Sequence.CompareTo(second.Sequence) : identifier;
        }
        public void Write(BinaryWriter writer) {
            // UTF-16 code units preserve .NET ordinal identity, including escaped
            // controls/surrogates. UTF-8 byte order is not StringComparer.Ordinal.
            writer.Write(Identifier.Length);
            byte[] bytes = new byte[checked(Identifier.Length * 2)];
            for (int index = 0; index < Identifier.Length; index++) {
                bytes[index * 2] = (byte)Identifier[index];
                bytes[index * 2 + 1] = (byte)(Identifier[index] >> 8);
            }
            writer.Write(bytes); writer.Write(Sequence); writer.Write(Offset);
        }
        public static IndexEntry Read(BinaryReader reader, int maximum) {
            if (reader.BaseStream.Position == reader.BaseStream.Length) return null;
            int length = reader.ReadInt32();
            if (length < 0 || length > maximum) throw new InvalidDataException("Invalid sorted-run identifier length.");
            byte[] bytes = reader.ReadBytes(checked(length * 2));
            if (bytes.Length != length * 2) throw new EndOfStreamException("Truncated sorted-run identifier.");
            char[] characters = new char[length];
            for (int index = 0; index < length; index++)
                characters[index] = (char)(bytes[index * 2] | bytes[index * 2 + 1] << 8);
            return new IndexEntry { Identifier = new string(characters), Sequence = reader.ReadInt64(), Offset = reader.ReadInt64() };
        }
    }

    internal sealed class RunReader : IDisposable {
        public readonly BinaryReader Reader;
        public IndexEntry Current;
        private readonly int maximum;
        public RunReader(string path, int limit) {
            maximum = limit;
            Reader = new BinaryReader(new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.Read, 65536));
            try { Advance(); } catch { Reader.Dispose(); throw; }
        }
        public void Advance() { Current = IndexEntry.Read(Reader, maximum); }
        public void Dispose() { Reader.Dispose(); }
    }

    internal sealed class ExternalIndex {
        private readonly string directory;
        private readonly long chunkBudget;
        private readonly int maximum;
        private readonly int fanIn;
        private readonly InventorySummary summary;
        private readonly List<IndexEntry> entries = new List<IndexEntry>();
        private long estimatedBytes;
        private long runCount;
        public ExternalIndex(string root, long budget, int recordMaximum, int readers, InventorySummary result) {
            directory = root; chunkBudget = budget; maximum = recordMaximum; fanIn = readers; summary = result;
        }
        private string RunPath(int pass, long run) {
            return System.IO.Path.Combine(directory, "index-p" + pass.ToString("D3", CultureInfo.InvariantCulture) +
                "-r" + run.ToString("D12", CultureInfo.InvariantCulture) + ".bin");
        }
        public void Add(string identifier, long sequence, long offset) {
            long estimate = checked(192L + identifier.Length * 2L);
            if (entries.Count != 0 && estimatedBytes + estimate > chunkBudget) Flush();
            entries.Add(new IndexEntry { Identifier = identifier, Sequence = sequence, Offset = offset });
            estimatedBytes += estimate;
            summary.PeakBufferedIndexBytes = Math.Max(summary.PeakBufferedIndexBytes, estimatedBytes);
            summary.PeakBufferedIndexRecords = Math.Max(summary.PeakBufferedIndexRecords, entries.Count);
            if (estimatedBytes >= chunkBudget) Flush();
        }
        private void Flush() {
            if (entries.Count == 0) return;
            entries.Sort(IndexEntry.Compare);
            using (BinaryWriter writer = new BinaryWriter(new FileStream(RunPath(0, runCount),
                    FileMode.CreateNew, FileAccess.Write, FileShare.None, 65536)))
                foreach (IndexEntry entry in entries) entry.Write(writer);
            runCount++; entries.Clear(); estimatedBytes = 0;
        }
        public string Finish() {
            Flush(); summary.InitialSortRuns = runCount;
            if (runCount == 0) {
                using (FileStream empty = new FileStream(RunPath(0, 0), FileMode.CreateNew)) { }
                return RunPath(0, 0);
            }
            int pass = 0;
            while (runCount > 1) {
                long outputRun = 0;
                for (long first = 0; first < runCount; first += fanIn) {
                    int count = (int)Math.Min(fanIn, runCount - first);
                    List<RunReader> readers = new List<RunReader>(count);
                    try {
                        for (int item = 0; item < count; item++) readers.Add(new RunReader(RunPath(pass, first + item), maximum));
                        summary.PeakOpenRunReaders = Math.Max(summary.PeakOpenRunReaders, readers.Count);
                        using (BinaryWriter writer = new BinaryWriter(new FileStream(RunPath(pass + 1, outputRun),
                                FileMode.CreateNew, FileAccess.Write, FileShare.None, 65536))) {
                            while (true) {
                                RunReader next = null;
                                foreach (RunReader candidate in readers)
                                    if (candidate.Current != null && (next == null || IndexEntry.Compare(candidate.Current, next.Current) < 0))
                                        next = candidate;
                                if (next == null) break;
                                next.Current.Write(writer); next.Advance();
                            }
                        }
                    } finally { foreach (RunReader reader in readers) reader.Dispose(); }
                    for (int item = 0; item < count; item++) File.Delete(RunPath(pass, first + item));
                    outputRun++;
                }
                runCount = outputRun; pass++;
            }
            summary.MergePasses = pass;
            string finalPath = RunPath(pass, 0);
            using (RunReader reader = new RunReader(finalPath, maximum)) {
                string previous = null;
                while (reader.Current != null) {
                    if (!String.Equals(previous, reader.Current.Identifier, StringComparison.Ordinal)) summary.PreciseSymbols++;
                    previous = reader.Current.Identifier; reader.Advance();
                }
            }
            return finalPath;
        }
    }

    public static class InventoryWriter {
        public static string SourceHash;
        private static readonly UTF8Encoding UTF8 = new UTF8Encoding(false, true);
        private static string Number(long value) { return value.ToString(CultureInfo.InvariantCulture); }
        private static string HashText(byte[] value) { return BitConverter.ToString(value).Replace("-", "").ToLowerInvariant(); }
        public static string Quote(string value) {
            StringBuilder result = new StringBuilder("\"");
            foreach (char character in value) {
                switch (character) {
                    case '"': result.Append("\\\""); break;
                    case '\\': result.Append("\\\\"); break;
                    case '\b': result.Append("\\b"); break;
                    case '\f': result.Append("\\f"); break;
                    case '\n': result.Append("\\n"); break;
                    case '\r': result.Append("\\r"); break;
                    case '\t': result.Append("\\t"); break;
                    default:
                        if (character < 0x20 || Char.IsSurrogate(character)) result.Append("\\u" + ((int)character).ToString("x4", CultureInfo.InvariantCulture));
                        else result.Append(character);
                        break;
                }
            }
            result.Append('"'); return result.ToString();
        }
        private static string Raw(Dictionary<string, string> fields, string name) {
            string value; return fields.TryGetValue(name, out value) ? value : "null";
        }
        private static void Field(StringBuilder output, string name, string raw) {
            if (output.Length > 1) output.Append(',');
            output.Append(Quote(name)).Append(':').Append(raw);
        }
        private static string RequiredString(Dictionary<string, string> fields, string name, string context, int maximum) {
            string raw;
            if (!fields.TryGetValue(name, out raw) || raw == "null") throw new InvalidDataException(context + " is missing '" + name + "'.");
            string value = JsonInput.DecodeString(raw, context + "/" + name, maximum);
            if (String.IsNullOrWhiteSpace(value)) throw new InvalidDataException(context + " is missing '" + name + "'.");
            return value;
        }
        private static string Symbol(JsonInput input, GraphInput graph, long index, int maximum, out string identifier) {
            Dictionary<string, string> symbol = input.ObjectFields();
            Dictionary<string, string> identity;
            try {
                identity = JsonInput.Fields(Raw(symbol, "identifier"), graph.RelativePath + "/identifier", maximum);
                identifier = RequiredString(identity, "precise", "Symbol " + index + " in '" + graph.RelativePath + "'", maximum);
            } catch (InvalidDataException error) {
                throw new InvalidDataException("Symbol " + index + " in '" + graph.RelativePath + "' has no precise identifier. " + error.Message, error);
            }
            StringBuilder result = new StringBuilder("{");
            Field(result, "graphPath", Quote(graph.RelativePath));
            Field(result, "symbolIndex", Number(index));
            Field(result, "requestedModule", Quote(graph.RequestedModule));
            Field(result, "target", Quote(graph.Target));
            Field(result, "interfaceLanguage", Raw(identity, "interfaceLanguage"));
            foreach (string name in new string[] { "kind", "pathComponents", "names", "accessLevel" }) Field(result, name, Raw(symbol, name));
            foreach (string name in new string[] { "availability", "declarationFragments", "swiftGenerics", "swiftExtension" })
                if (symbol.ContainsKey(name)) Field(result, name, symbol[name]);
            return result.Append('}').ToString();
        }
        private static void ValidateModule(string raw, GraphInput graph, long symbols, int maximum) {
            Dictionary<string, string> module = JsonInput.Fields(raw, graph.RelativePath + "/module", maximum);
            string name = RequiredString(module, "name", graph.RelativePath + "/module", maximum);
            if (graph.Primary && (name != graph.RequestedModule || symbols == 0))
                throw new InvalidDataException("Primary graph '" + graph.RelativePath + "' is empty or names the wrong module.");
            Dictionary<string, string> platform = JsonInput.Fields(Raw(module, "platform"), graph.RelativePath + "/platform", maximum);
            string architecture = RequiredString(platform, "architecture", graph.RelativePath + "/platform", maximum);
            string expected = graph.Target.Split('-')[0];
            // LLVM's canonical Triple spelling for the arm64 target is aarch64.
            // Keep the observed module object unchanged in the inventory.
            if (architecture != expected && !(expected == "arm64" && architecture == "aarch64"))
                throw new InvalidDataException("Graph '" + graph.RelativePath + "' has the wrong architecture for '" + graph.Target + "'.");
            Dictionary<string, string> operatingSystem = JsonInput.Fields(Raw(platform, "operatingSystem"), graph.RelativePath + "/operatingSystem", maximum);
            string os = RequiredString(operatingSystem, "name", graph.RelativePath + "/operatingSystem", maximum);
            if (os != "macosx" && os != "macos") throw new InvalidDataException("Graph '" + graph.RelativePath + "' is not a macOS desktop graph.");
        }
        private static string ReadGraph(GraphInput graph, BinaryWriter payloads, ExternalIndex index,
                TextWriter relationships, InventorySummary summary, int maximum, out string rawHash) {
            string metadata = null, module = null;
            long symbolCount = 0, relationshipCount = 0;
            HashSet<string> properties = new HashSet<string>(StringComparer.Ordinal);
            using (FileStream source = new FileStream(graph.Path, FileMode.Open, FileAccess.Read, FileShare.Read, 65536))
            using (SHA256 hash = SHA256.Create())
            using (CryptoStream hashed = new CryptoStream(source, hash, CryptoStreamMode.Read))
            using (StreamReader reader = new StreamReader(hashed, UTF8, false, 65536)) {
                summary.InputBytes += source.Length;
                JsonInput input = new JsonInput(reader, graph.RelativePath, maximum);
                input.SkipUTF8BOM(); input.Expect('{');
                if (!input.Consume('}')) {
                    do {
                        string property = input.PropertyName();
                        bool known = property == "metadata" || property == "module" || property == "symbols" || property == "relationships";
                        if (known && !properties.Add(property)) throw new InvalidDataException("Duplicate graph member '" + property + "' in '" + graph.RelativePath + "'.");
                        if (property == "symbols" || property == "relationships") {
                            input.Expect('[');
                            if (!input.Consume(']')) {
                                do {
                                    input.StartRecord();
                                    if (property == "symbols") {
                                        string identifier;
                                        string occurrence = Symbol(input, graph, symbolCount, maximum, out identifier);
                                        long offset = payloads.BaseStream.Position;
                                        payloads.Write(occurrence);
                                        index.Add(identifier, summary.DeclarationOccurrences, offset);
                                        symbolCount++; summary.DeclarationOccurrences++;
                                    } else {
                                        string raw = input.RawValue();
                                        Dictionary<string, string> fields = JsonInput.Fields(raw, graph.RelativePath + "/relationship", maximum);
                                        foreach (string required in new string[] { "kind", "source", "target" })
                                            RequiredString(fields, required, "Relationship " + relationshipCount + " in '" + graph.RelativePath + "'", maximum);
                                        if (summary.RelationshipOccurrences != 0) relationships.Write(',');
                                        relationships.Write("{\"graphPath\":" + Quote(graph.RelativePath) +
                                            ",\"relationshipIndex\":" + Number(relationshipCount) + ",\"relationship\":");
                                        relationships.Write(raw); relationships.Write('}');
                                        relationshipCount++; summary.RelationshipOccurrences++;
                                    }
                                    input.EndRecord();
                                } while (input.Consume(','));
                                input.Expect(']');
                            }
                        } else if (property == "metadata" || property == "module") {
                            input.StartRecord();
                            if (property == "metadata") metadata = input.RawValue();
                            else module = input.RawValue();
                            input.EndRecord();
                        } else input.SkipValue();
                    } while (input.Consume(','));
                    input.Expect('}');
                }
                input.EndDocument();
                summary.LargestRecordCharacters = Math.Max(summary.LargestRecordCharacters, input.LargestRecordCharacters);
                if (metadata == null || metadata == "null" || module == null || module == "null" ||
                        !properties.Contains("symbols") || !properties.Contains("relationships"))
                    throw new InvalidDataException("Malformed symbol graph '" + graph.RelativePath + "': expected metadata, module, symbols array, and relationships array.");
                ValidateModule(module, graph, symbolCount, maximum);
                // EndDocument has consumed through EOF, finalizing CryptoStream's
                // hash of exactly the bytes the parser read (BOM and whitespace too).
                rawHash = HashText(hash.Hash);
            }
            return "{\"path\":" + Quote(graph.RelativePath) + ",\"sha256\":" + Quote(rawHash) +
                ",\"requestedModule\":" + Quote(graph.RequestedModule) + ",\"target\":" + Quote(graph.Target) +
                ",\"metadata\":" + metadata + ",\"module\":" + module + ",\"symbolCount\":" + Number(symbolCount) +
                ",\"relationshipCount\":" + Number(relationshipCount) + "}";
        }
        private static void CopyText(string path, TextWriter destination) {
            char[] buffer = new char[65536];
            using (StreamReader reader = new StreamReader(path, UTF8, false, buffer.Length)) {
                int count; while ((count = reader.Read(buffer, 0, buffer.Length)) != 0) destination.Write(buffer, 0, count);
            }
        }
        private static void WriteInventory(string path, string baselineId, string graphs, string relationships,
                string payloadPath, string sortedIndex, InventorySummary summary, int maximum) {
            using (StreamWriter writer = new StreamWriter(new FileStream(path, FileMode.CreateNew, FileAccess.Write, FileShare.None, 65536), UTF8, 65536)) {
                writer.Write("{\"schemaVersion\":1,\"baselineId\":" + Quote(baselineId) +
                    ",\"evidenceKind\":\"compiler-exported-api-inventory-only\",\"completeness\":\"requires-public-interface-and-documentation-audit\"" +
                    ",\"behaviorConformance\":\"not-verified\",\"crossImportOverlayCompleteness\":\"requires-declaration-and-interface-audit\"" +
                    ",\"symbolIdentity\":\"case-sensitive identifier.precise; occurrences retained across targets and re-exports\",\"rawGraphsAreAuthoritative\":true" +
                    ",\"counts\":{\"graphs\":" + Number(summary.Graphs) + ",\"preciseSymbols\":" + Number(summary.PreciseSymbols) +
                    ",\"declarationOccurrences\":" + Number(summary.DeclarationOccurrences) + ",\"relationshipOccurrences\":" + Number(summary.RelationshipOccurrences) +
                    "},\"graphSetSha256\":" + Quote(summary.GraphSetSha256) + ",\"graphs\":[");
                CopyText(graphs, writer); writer.Write("],\"symbols\":[");
                using (RunReader reader = new RunReader(sortedIndex, maximum))
                using (BinaryReader payloads = new BinaryReader(new FileStream(payloadPath, FileMode.Open, FileAccess.Read, FileShare.Read, 65536), UTF8)) {
                    string previous = null;
                    long groupSize = 0;
                    while (reader.Current != null) {
                        IndexEntry entry = reader.Current;
                        if (!String.Equals(previous, entry.Identifier, StringComparison.Ordinal)) {
                            if (previous != null) writer.Write("]},");
                            writer.Write("{\"preciseIdentifier\":" + Quote(entry.Identifier) + ",\"occurrences\":[");
                            previous = entry.Identifier; groupSize = 0;
                        } else writer.Write(',');
                        if (entry.Offset < 0 || entry.Offset >= payloads.BaseStream.Length) throw new InvalidDataException("Invalid declaration payload offset.");
                        payloads.BaseStream.Position = entry.Offset;
                        writer.Write(payloads.ReadString());
                        groupSize++; summary.LargestOccurrenceGroup = Math.Max(summary.LargestOccurrenceGroup, groupSize);
                        reader.Advance();
                    }
                    if (previous != null) writer.Write("]}");
                }
                writer.Write("],\"relationships\":["); CopyText(relationships, writer); writer.Write("]}\n");
            }
        }
        public static InventorySummary Write(string baselineId, GraphInput[] graphs, string outputPath,
                long sortChunkBytes, int mergeFanIn, int maximumRecordCharacters) {
            if (sortChunkBytes < 1024 || sortChunkBytes > 1073741824L || mergeFanIn < 2 || mergeFanIn > 64 ||
                    maximumRecordCharacters < 1024 || maximumRecordCharacters > 134217728)
                throw new ArgumentOutOfRangeException("Invalid explicit inventory resource budgets.");
            outputPath = Path.GetFullPath(outputPath);
            string parent = Path.GetDirectoryName(outputPath);
            if (!Directory.Exists(parent)) throw new DirectoryNotFoundException("Inventory output parent must already exist.");
            if (File.Exists(outputPath) || Directory.Exists(outputPath)) throw new IOException("Inventory output already exists; no evidence is overwritten.");
            string leaf = ".swiftui-index-" + Guid.NewGuid().ToString("N");
            string scratch = Path.GetFullPath(Path.Combine(parent, leaf));
            if (Directory.Exists(scratch) || File.Exists(scratch)) throw new IOException("Inventory scratch path already exists.");
            Directory.CreateDirectory(scratch);
            Exception originalFailure = null;
            try {
                InventorySummary summary = new InventorySummary();
                ExternalIndex index = new ExternalIndex(scratch, sortChunkBytes, maximumRecordCharacters, mergeFanIn, summary);
                string payloadPath = Path.Combine(scratch, "declarations.bin");
                string graphPath = Path.Combine(scratch, "graphs.json-fragments");
                string relationshipPath = Path.Combine(scratch, "relationships.json-fragments");
                using (BinaryWriter payloads = new BinaryWriter(new FileStream(payloadPath, FileMode.CreateNew, FileAccess.Write, FileShare.None, 65536), UTF8))
                using (StreamWriter graphRecords = new StreamWriter(graphPath, false, UTF8, 65536))
                using (StreamWriter relationships = new StreamWriter(relationshipPath, false, UTF8, 65536))
                using (SHA256 graphSet = SHA256.Create()) {
                    string previous = null;
                    foreach (GraphInput graph in graphs) {
                        if (previous != null && StringComparer.Ordinal.Compare(previous, graph.RelativePath) >= 0)
                            throw new InvalidDataException("Graph paths must be unique and ordinally sorted.");
                        previous = graph.RelativePath;
                        string hash;
                        string record = ReadGraph(graph, payloads, index, relationships, summary, maximumRecordCharacters, out hash);
                        if (summary.Graphs != 0) graphRecords.Write(',');
                        graphRecords.Write(record); summary.Graphs++;
                        byte[] hashLine = UTF8.GetBytes(graph.RelativePath + "\t" + hash + "\n");
                        graphSet.TransformBlock(hashLine, 0, hashLine.Length, null, 0);
                    }
                    graphSet.TransformFinalBlock(new byte[0], 0, 0);
                    summary.GraphSetSha256 = HashText(graphSet.Hash);
                }
                string sortedIndex = index.Finish();
                string temporaryOutput = Path.Combine(scratch, "inventory.json");
                WriteInventory(temporaryOutput, baselineId, graphPath, relationshipPath, payloadPath, sortedIndex, summary, maximumRecordCharacters);
                using (FileStream result = new FileStream(temporaryOutput, FileMode.Open, FileAccess.Read, FileShare.Read))
                using (SHA256 hash = SHA256.Create()) {
                    summary.OutputBytes = result.Length;
                    summary.InventorySha256 = HashText(hash.ComputeHash(result));
                }
                // Same filesystem, publish only a complete file, never overwrite.
                File.Move(temporaryOutput, outputPath);
                return summary;
            } catch (Exception error) {
                originalFailure = error;
                throw;
            } finally {
                // Only this invocation's checked, newly-created sibling scratch
                // directory is removable. Never follow a substituted directory link.
                try {
                    string resolved = Path.GetFullPath(scratch);
                    if (Path.GetDirectoryName(resolved) != parent || Path.GetFileName(resolved) != leaf ||
                            (File.GetAttributes(resolved) & FileAttributes.ReparsePoint) != 0)
                        throw new IOException("Refusing unsafe inventory scratch cleanup: " + resolved);
                    Directory.Delete(resolved, true);
                } catch (Exception cleanupFailure) {
                    if (originalFailure != null) throw new AggregateException("Inventory failed and owned scratch cleanup also failed.", originalFailure, cleanupFailure);
                    throw;
                }
            }
        }
    }
}
'@
    $sourceHash = Get-SwiftUIBaselineTextHash -Text $source
    if ($null -eq ("SwiftUIBaseline.Streaming.InventoryWriter" -as [type])) {
        Add-Type -TypeDefinition $source -Language CSharp -ErrorAction Stop
        [SwiftUIBaseline.Streaming.InventoryWriter]::SourceHash = $sourceHash
    } elseif ([SwiftUIBaseline.Streaming.InventoryWriter]::SourceHash -cne $sourceHash) {
        throw "The loaded SwiftUI inventory implementation differs from this source. Start a fresh PowerShell process."
    }
}
