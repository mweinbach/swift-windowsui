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

    // A callback receives one complete JSON record, never a graph or a gathered
    // identifier group. Json retains every field; InventoryJson is only the
    // existing inventory projection used to reconcile that separate artifact.
    public sealed class RawGraphRecord {
        public GraphInput Graph;
        public string Kind;
        public string Name;
        public long Index;
        public string PreciseIdentifier;
        public string Json;
        public string InventoryJson;
    }

    public sealed class GraphVisitSummary {
        public string GraphRecord;
        public string Sha256;
        public InventorySummary Statistics;
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
        // Small PowerShell metadata cannot represent case-aliased object keys.
        // Validate those inputs before trusting a parsed projection; raw native
        // graphs and ledger mixins retain their existing ordinal JSON rules.
        public void ValidateMetadataValue(int depth) {
            White();
            if (depth > MaximumDepth) Fail("Metadata JSON nesting exceeds 256 levels");
            if (Peek() == '{') {
                Expect('{');
                HashSet<string> names = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
                if (!Consume('}')) {
                    do {
                        string name = PropertyName();
                        if (!names.Add(name)) Fail("Duplicate or ambiguous metadata object member '" + name + "'");
                        ValidateMetadataValue(depth + 1);
                    } while (Consume(','));
                    Expect('}');
                }
            } else if (Peek() == '[') {
                Expect('[');
                if (!Consume(']')) {
                    do { ValidateMetadataValue(depth + 1); } while (Consume(','));
                    Expect(']');
                }
            } else SkipValue();
        }
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
        private static string Symbol(Dictionary<string, string> symbol, GraphInput graph, long index, int maximum, out string identifier) {
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
                TextWriter relationships, InventorySummary summary, int maximum, out string rawHash,
                Action<RawGraphRecord> visitor = null) {
            string metadata = null, module = null;
            long symbolCount = 0, relationshipCount = 0, rootFieldIndex = 0;
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
                                        string rawSymbol = visitor == null ? null : input.RawValue();
                                        Dictionary<string, string> fields = visitor == null ? input.ObjectFields() :
                                            JsonInput.Fields(rawSymbol, graph.RelativePath + "/symbol", maximum);
                                        string occurrence = Symbol(fields, graph, symbolCount, maximum, out identifier);
                                        if (payloads != null) {
                                            long offset = payloads.BaseStream.Position;
                                            payloads.Write(occurrence);
                                            index.Add(identifier, summary.DeclarationOccurrences, offset);
                                        }
                                        if (visitor != null) visitor(new RawGraphRecord { Graph = graph, Kind = "symbol",
                                            Index = symbolCount, PreciseIdentifier = identifier, Json = rawSymbol, InventoryJson = occurrence });
                                        symbolCount++; summary.DeclarationOccurrences++;
                                    } else {
                                        string raw = input.RawValue();
                                        Dictionary<string, string> fields = JsonInput.Fields(raw, graph.RelativePath + "/relationship", maximum);
                                        foreach (string required in new string[] { "kind", "source", "target" })
                                            RequiredString(fields, required, "Relationship " + relationshipCount + " in '" + graph.RelativePath + "'", maximum);
                                        string occurrence = "{\"graphPath\":" + Quote(graph.RelativePath) +
                                            ",\"relationshipIndex\":" + Number(relationshipCount) + ",\"relationship\":" + raw + "}";
                                        if (relationships != null) {
                                            if (summary.RelationshipOccurrences != 0) relationships.Write(',');
                                            relationships.Write(occurrence);
                                        }
                                        if (visitor != null) visitor(new RawGraphRecord { Graph = graph, Kind = "relationship",
                                            Index = relationshipCount, Json = raw, InventoryJson = occurrence });
                                        relationshipCount++; summary.RelationshipOccurrences++;
                                    }
                                    input.EndRecord();
                                } while (input.Consume(','));
                                input.Expect(']');
                            }
                        } else if (property == "metadata" || property == "module") {
                            input.StartRecord();
                            string raw = input.RawValue();
                            if (property == "metadata") metadata = raw;
                            else module = raw;
                            if (visitor != null) visitor(new RawGraphRecord { Graph = graph, Kind = "graph-field",
                                Name = property, Index = rootFieldIndex, Json = raw });
                            input.EndRecord();
                        } else if (visitor != null) {
                            input.StartRecord();
                            visitor(new RawGraphRecord { Graph = graph, Kind = "graph-field", Name = property,
                                Index = rootFieldIndex, Json = input.RawValue() });
                            input.EndRecord();
                        } else input.SkipValue();
                        rootFieldIndex++;
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

        public static GraphVisitSummary VisitGraph(GraphInput graph, Action<RawGraphRecord> visitor,
                int maximumRecordCharacters) {
            if (graph == null || visitor == null) throw new ArgumentNullException("graph/visitor");
            if (maximumRecordCharacters < 1024 || maximumRecordCharacters > 134217728)
                throw new ArgumentOutOfRangeException("maximumRecordCharacters");
            InventorySummary summary = new InventorySummary();
            string hash;
            string record = ReadGraph(graph, null, null, null, summary, maximumRecordCharacters, out hash, visitor);
            summary.Graphs = 1;
            return new GraphVisitSummary { GraphRecord = record, Sha256 = hash, Statistics = summary };
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
public sealed class AuditTextInput {
        public string Path;
        public string RelativePath;
        public string Module;
        public string Sha256;
        public string CaptureRecordJson;
    }

    public sealed class AuditLedgerOptions {
        public string BaselineId;
        public GraphInput[] Graphs;
        public string InventoryPath;
        public string InventorySha256;
        public string GraphSetSha256;
        public long ExpectedGraphs;
        public long ExpectedPreciseSymbols;
        public long ExpectedDeclarations;
        public long ExpectedRelationships;
        public AuditTextInput[] Interfaces;
        public AuditTextInput[] Overlays;
        public string[] QueueFamilies;
        public string OutputDirectory;
        public long SortChunkBytes = 16777216;
        public int MergeFanIn = 16;
        public int MaximumRecordCharacters = 33554432;
    }

    public sealed class AuditLedgerSummary {
        public InventorySummary Inventory = new InventorySummary();
        public long GraphFieldFacts;
        public long InventoryFacts;
        public long InterfaceFiles;
        public long InterfaceLines;
        public long OverlayFiles;
        public long OverlayLines;
        public long QueueRecords;
        public long LargestTextLineCharacters;
        public string[] RecordFiles;
    }

    internal sealed class AuditGraphState {
        public GraphInput Input;
        public long FirstSymbol;
        public long SymbolCount;
        public byte[] RecordDigest;
    }

    // The audit is additive: raw symbols and relationships are retained, while
    // the existing inventory is independently streamed and reconciled. No
    // Windows matching, Swift parsing, or behavioral classification occurs here.
    public static class AuditLedgerWriter {
        private static readonly UTF8Encoding UTF8 = new UTF8Encoding(false, true);
        internal static readonly string[] Families = new string[] {
            "view-builder", "binding-projections", "image-resizing", "long-press", "file-export"
        };
        private static readonly string[] Files = new string[] {
            "identities.ndjson", "occurrences.ndjson", "relationships.ndjson", "graph-fields.ndjson",
            "partitions.ndjson", "inventory-facts.ndjson", "interface-facts.ndjson",
            "overlay-facts.ndjson", "candidate-queues.ndjson"
        };
        private static string Q(string value) { return InventoryWriter.Quote(value); }
        private static string N(long value) { return value.ToString(CultureInfo.InvariantCulture); }
        private static string Hex(byte[] value) { return BitConverter.ToString(value).Replace("-", "").ToLowerInvariant(); }
        private static byte[] Digest(string value) {
            using (SHA256 hash = SHA256.Create()) { return hash.ComputeHash(UTF8.GetBytes(value)); }
        }
        private static bool Equal(byte[] first, byte[] second) {
            if (first.Length != second.Length) return false;
            for (int index = 0; index < first.Length; index++) if (first[index] != second[index]) return false;
            return true;
        }
        private static StreamWriter Writer(string path) {
            StreamWriter result = new StreamWriter(new FileStream(path, FileMode.CreateNew,
                FileAccess.Write, FileShare.None, 65536), UTF8, 65536);
            result.NewLine = "\n"; return result;
        }
        private static string Required(Dictionary<string, string> fields, string name) {
            string result;
            if (!fields.TryGetValue(name, out result)) throw new InvalidDataException("Missing inventory field '" + name + "'.");
            return result;
        }
        private static string Text(Dictionary<string, string> fields, string name, int maximum) {
            return JsonInput.DecodeString(Required(fields, name), name, maximum);
        }
        private static long Integer(Dictionary<string, string> fields, string name) {
            long result;
            if (!Int64.TryParse(Required(fields, name), NumberStyles.None, CultureInfo.InvariantCulture, out result))
                throw new InvalidDataException("Expected a nonnegative Int64 inventory count/index for '" + name + "'.");
            return result;
        }
        private static string Canonical(string raw, string[] required, string[] optional, int maximum) {
            Dictionary<string, string> fields = JsonInput.Fields(raw, "inventory projection", maximum);
            StringBuilder output = new StringBuilder("{");
            int count = 0;
            foreach (string name in required) {
                if (count++ != 0) output.Append(',');
                output.Append(Q(name)).Append(':').Append(Required(fields, name));
            }
            foreach (string name in optional) if (fields.ContainsKey(name)) {
                if (count++ != 0) output.Append(',');
                output.Append(Q(name)).Append(':').Append(fields[name]);
            }
            if (count != fields.Count) throw new InvalidDataException("Unexpected inventory projection fields; review the inventory schema before auditing it.");
            return output.Append('}').ToString();
        }
        private static string SymbolProjection(string raw, int maximum) {
            return Canonical(raw, new string[] { "graphPath", "symbolIndex", "requestedModule", "target",
                "interfaceLanguage", "kind", "pathComponents", "names", "accessLevel" },
                new string[] { "availability", "declarationFragments", "swiftGenerics", "swiftExtension" }, maximum);
        }
        private static string GraphProjection(string raw, int maximum) {
            return Canonical(raw, new string[] { "path", "sha256", "requestedModule", "target", "metadata",
                "module", "symbolCount", "relationshipCount" }, new string[0], maximum);
        }
        private static string RelationshipProjection(string raw, int maximum) {
            return Canonical(raw, new string[] { "graphPath", "relationshipIndex", "relationship" },
                new string[0], maximum);
        }
        internal static int QueueMask(string raw, int maximum) {
            Dictionary<string, string> fields = JsonInput.Fields(raw, "candidate queue symbol", maximum);
            string path;
            if (!fields.TryGetValue("pathComponents", out path) || path == "null" || path.Length == 0 || path[0] != '[') return 0;
            JsonInput input = new JsonInput(new StringReader(path), "pathComponents", maximum);
            string first = null, second = null, last = null;
            int count = 0;
            input.Expect('[');
            if (!input.Consume(']')) {
                do {
                    string value = input.RawValue();
                    if (value.Length == 0 || value[0] != '"') return 0;
                    last = JsonInput.DecodeString(value, "path component", maximum);
                    if (count == 0) first = last;
                    if (count == 1) second = last;
                    count++;
                } while (input.Consume(','));
                input.Expect(']');
            }
            input.EndDocument();
            int mask = 0;
            if (first == "ViewBuilder" || (first == "View" && (count == 1 || last == "body"))) mask |= 1;
            if (first == "Binding") mask |= 2;
            if (first == "Image" && (count == 1 || second == "ResizingMode" ||
                    last.StartsWith("resizable(", StringComparison.Ordinal))) mask |= 4;
            if (first == "LongPressGesture" || (first == "View" &&
                    last.StartsWith("onLongPressGesture(", StringComparison.Ordinal))) mask |= 8;
            if (first == "FileDocument" || first == "FileDocumentReadConfiguration" ||
                    first == "FileDocumentWriteConfiguration" || first == "ReferenceFileDocument" ||
                    (first == "View" && last.StartsWith("fileExporter(", StringComparison.Ordinal))) mask |= 16;
            return mask;
        }
        internal static int SelectedQueues(string[] names) {
            if (names == null) return 31;
            int mask = 0;
            foreach (string name in names) {
                int index = Array.IndexOf(Families, name);
                if (index < 0) throw new InvalidDataException("Unknown candidate queue family '" + name + "'.");
                mask |= 1 << index;
            }
            return mask;
        }
        private static void RequireDigest(BinaryReader expected, string value, string context) {
            byte[] bytes = expected.ReadBytes(32);
            if (bytes.Length != 32 || !Equal(bytes, Digest(value)))
                throw new InvalidDataException("Inventory does not match raw " + context + ".");
        }

        internal static void ValidateInventory(AuditLedgerOptions options, AuditLedgerSummary result,
                List<AuditGraphState> graphs, string sortedIndex, string symbolDigests,
                string relationshipDigests, string factsPath) {
            int maximum = options.MaximumRecordCharacters;
            Dictionary<string, AuditGraphState> graphByPath = new Dictionary<string, AuditGraphState>(StringComparer.Ordinal);
            foreach (AuditGraphState graph in graphs) graphByPath.Add(graph.Input.RelativePath, graph);
            HashSet<string> rootFields = new HashSet<string>(StringComparer.Ordinal);
            Dictionary<string, string> header = new Dictionary<string, string>(StringComparer.Ordinal);
            long graphCount = 0, symbolCount = 0, occurrenceCount = 0, relationshipCount = 0;
            using (RunReader identities = new RunReader(sortedIndex, maximum))
            using (BinaryReader expectedSymbols = new BinaryReader(File.OpenRead(symbolDigests)))
            using (BinaryReader expectedRelationships = new BinaryReader(File.OpenRead(relationshipDigests)))
            using (StreamWriter facts = Writer(factsPath))
            using (FileStream source = new FileStream(options.InventoryPath, FileMode.Open, FileAccess.Read, FileShare.Read, 65536))
            using (SHA256 hash = SHA256.Create())
            using (CryptoStream hashed = new CryptoStream(source, hash, CryptoStreamMode.Read))
            using (StreamReader reader = new StreamReader(hashed, UTF8, false, 65536)) {
                JsonInput input = new JsonInput(reader, options.InventoryPath, maximum);
                input.SkipUTF8BOM(); input.Expect('{');
                if (!input.Consume('}')) {
                    do {
                        string property = input.PropertyName();
                        // The schema has a bounded header. Unknown fields are
                        // written immediately instead of being accumulated here.
                        bool known = property == "graphs" || property == "symbols" || property == "relationships" ||
                            property == "schemaVersion" || property == "baselineId" || property == "counts" ||
                            property == "graphSetSha256" || property == "evidenceKind" || property == "rawGraphsAreAuthoritative" ||
                            property == "behaviorConformance" || property == "completeness" || property == "crossImportOverlayCompleteness";
                        if (known && !rootFields.Add(property)) throw new InvalidDataException("Duplicate inventory field '" + property + "'.");
                        if (property == "graphs") {
                            input.Expect('[');
                            if (!input.Consume(']')) {
                                do {
                                    input.StartRecord(); string raw = input.RawValue(); input.EndRecord();
                                    if (graphCount >= graphs.Count || !Equal(Digest(GraphProjection(raw, maximum)), graphs[(int)graphCount].RecordDigest))
                                        throw new InvalidDataException("Inventory graph partition metadata/hash does not match raw graphs.");
                                    graphCount++;
                                } while (input.Consume(','));
                                input.Expect(']');
                            }
                        } else if (property == "symbols") {
                            input.Expect('[');
                            if (!input.Consume(']')) {
                                do {
                                    if (identities.Current == null) throw new InvalidDataException("Inventory has duplicate or extra precise identifiers.");
                                    string expectedId = identities.Current.Identifier;
                                    bool sawId = false, sawOccurrences = false;
                                    long groupCount = 0;
                                    input.Expect('{');
                                    if (!input.Consume('}')) {
                                        do {
                                            string member = input.PropertyName();
                                            if (member == "preciseIdentifier") {
                                                if (sawId) throw new InvalidDataException("Duplicate inventory preciseIdentifier field.");
                                                sawId = true; input.StartRecord();
                                                string identifier = JsonInput.DecodeString(input.RawValue(), "preciseIdentifier", maximum);
                                                input.EndRecord();
                                                if (!String.Equals(identifier, expectedId, StringComparison.Ordinal))
                                                    throw new InvalidDataException("Inventory precise identifiers are missing, duplicated, changed or out of ordinal order.");
                                            } else if (member == "occurrences") {
                                                if (sawOccurrences) throw new InvalidDataException("Duplicate inventory occurrences array.");
                                                sawOccurrences = true; input.Expect('[');
                                                if (!input.Consume(']')) {
                                                    do {
                                                        input.StartRecord(); string raw = input.RawValue(); input.EndRecord();
                                                        Dictionary<string, string> fields = JsonInput.Fields(raw, "inventory occurrence", maximum);
                                                        AuditGraphState graph;
                                                        string path = Text(fields, "graphPath", maximum);
                                                        long symbolIndex = Integer(fields, "symbolIndex");
                                                        if (!graphByPath.TryGetValue(path, out graph) || symbolIndex >= graph.SymbolCount ||
                                                                identities.Current == null || identities.Current.Identifier != expectedId ||
                                                                identities.Current.Sequence != graph.FirstSymbol + symbolIndex)
                                                            throw new InvalidDataException("Inventory occurrence identity/path/index is missing, duplicated or changed.");
                                                        expectedSymbols.BaseStream.Position = identities.Current.Offset;
                                                        RequireDigest(expectedSymbols, SymbolProjection(raw, maximum), "symbol projection");
                                                        identities.Advance(); groupCount++; occurrenceCount++;
                                                    } while (input.Consume(','));
                                                    input.Expect(']');
                                                }
                                            } else {
                                                throw new InvalidDataException("Unexpected inventory identity-group field; review the inventory schema.");
                                            }
                                        } while (input.Consume(','));
                                        input.Expect('}');
                                    }
                                    if (!sawId || !sawOccurrences || groupCount == 0 ||
                                            (identities.Current != null && identities.Current.Identifier == expectedId))
                                        throw new InvalidDataException("Inventory has an incomplete or duplicate precise identifier group.");
                                    symbolCount++;
                                } while (input.Consume(','));
                                input.Expect(']');
                            }
                        } else if (property == "relationships") {
                            input.Expect('[');
                            if (!input.Consume(']')) {
                                do {
                                    input.StartRecord(); string raw = input.RawValue(); input.EndRecord();
                                    RequireDigest(expectedRelationships, RelationshipProjection(raw, maximum), "relationship");
                                    relationshipCount++;
                                } while (input.Consume(','));
                                input.Expect(']');
                            }
                        } else {
                            input.StartRecord(); string raw = input.RawValue(); input.EndRecord();
                            facts.WriteLine("{\"reviewStatus\":\"unreviewed\",\"field\":" + Q(property) + ",\"value\":" + raw + "}");
                            result.InventoryFacts++;
                            if (known) header.Add(property, raw);
                        }
                    } while (input.Consume(','));
                    input.Expect('}');
                }
                input.EndDocument();
                if (Hex(hash.Hash) != options.InventorySha256) throw new InvalidDataException("Inventory SHA-256 does not match the successful capture.");
                if (identities.Current != null || expectedRelationships.BaseStream.Position != expectedRelationships.BaseStream.Length ||
                        graphCount != graphs.Count || symbolCount != result.Inventory.PreciseSymbols ||
                        occurrenceCount != result.Inventory.DeclarationOccurrences || relationshipCount != result.Inventory.RelationshipOccurrences)
                    throw new InvalidDataException("Inventory does not account for every raw graph, identity, occurrence and relationship.");
                foreach (string name in new string[] { "graphs", "symbols", "relationships", "schemaVersion", "baselineId",
                        "counts", "graphSetSha256", "evidenceKind", "rawGraphsAreAuthoritative", "behaviorConformance",
                        "completeness", "crossImportOverlayCompleteness" })
                    if (!rootFields.Contains(name)) throw new InvalidDataException("Missing inventory field '" + name + "'.");
                if (Required(header, "schemaVersion") != "1" || Text(header, "baselineId", maximum) != options.BaselineId ||
                        Text(header, "graphSetSha256", maximum) != result.Inventory.GraphSetSha256 ||
                        Text(header, "evidenceKind", maximum) != "compiler-exported-api-inventory-only" ||
                        Text(header, "behaviorConformance", maximum) != "not-verified" ||
                        Text(header, "completeness", maximum) != "requires-public-interface-and-documentation-audit" ||
                        Text(header, "crossImportOverlayCompleteness", maximum) != "requires-declaration-and-interface-audit" ||
                        Required(header, "rawGraphsAreAuthoritative") != "true")
                    throw new InvalidDataException("Inventory baseline/schema/provenance is incompatible with the captured raw graphs.");
                Dictionary<string, string> counts = JsonInput.Fields(Required(header, "counts"), "inventory counts", maximum);
                if (Integer(counts, "graphs") != graphCount || Integer(counts, "preciseSymbols") != symbolCount ||
                        Integer(counts, "declarationOccurrences") != occurrenceCount || Integer(counts, "relationshipOccurrences") != relationshipCount)
                    throw new InvalidDataException("Inventory declared counts do not match its streamed records.");
                result.Inventory.InventorySha256 = Hex(hash.Hash);
                result.Inventory.LargestRecordCharacters = Math.Max(result.Inventory.LargestRecordCharacters, input.LargestRecordCharacters);
            }
        }

        internal static bool ReadTextLine(StreamReader reader, int maximum, out string text, out string ending) {
            StringBuilder value = new StringBuilder();
            ending = "";
            while (true) {
                int character = reader.Read();
                if (character < 0) { text = value.ToString(); return value.Length != 0; }
                if (character == '\r' || character == '\n') {
                    ending = character == '\r' ? "\r" : "\n";
                    if (character == '\r' && reader.Peek() == '\n') { reader.Read(); ending = "\r\n"; }
                    text = value.ToString(); return true;
                }
                if (value.Length >= maximum) throw new InvalidDataException("Interface/overlay line exceeds MaximumRecordCharacters; increase the explicit budget, never truncate it.");
                value.Append((char)character);
            }
        }
        internal static long WriteTextFacts(AuditTextInput[] files, string output, string kind,
                AuditLedgerSummary summary, int maximum) {
            long lines = 0;
            using (StreamWriter writer = Writer(output)) {
                string previous = null;
                foreach (AuditTextInput file in files) {
                    if (previous != null && StringComparer.Ordinal.Compare(previous, file.RelativePath) >= 0)
                        throw new InvalidDataException("Interface/overlay paths must be unique and ordinally sorted.");
                    previous = file.RelativePath;
                    JsonInput.Fields(file.CaptureRecordJson, "captured interface/overlay record", maximum);
                    JsonInput metadata = new JsonInput(new StringReader(file.CaptureRecordJson), "captured text-file record", maximum);
                    metadata.StartRecord();
                    string metadataJson = metadata.RawValue();
                    metadata.EndRecord(); metadata.EndDocument();
                    writer.WriteLine("{\"reviewStatus\":\"unreviewed\",\"factKind\":" + Q(kind + "-file") +
                        ",\"path\":" + Q(file.RelativePath) + ",\"module\":" + Q(file.Module) +
                        ",\"sha256\":" + Q(file.Sha256) + ",\"captureRecord\":" + metadataJson + "}");
                    long number = 0;
                    using (FileStream source = new FileStream(file.Path, FileMode.Open, FileAccess.Read, FileShare.Read, 65536))
                    using (SHA256 hash = SHA256.Create())
                    using (CryptoStream hashed = new CryptoStream(source, hash, CryptoStreamMode.Read))
                    using (StreamReader reader = new StreamReader(hashed, UTF8, false, 65536)) {
                        string text, ending;
                        while (ReadTextLine(reader, maximum, out text, out ending)) {
                            number++; lines++;
                            summary.LargestTextLineCharacters = Math.Max(summary.LargestTextLineCharacters, text.Length);
                            writer.WriteLine("{\"reviewStatus\":\"unreviewed\",\"factKind\":" + Q(kind + "-source-line") +
                                ",\"path\":" + Q(file.RelativePath) + ",\"line\":" + N(number) +
                                ",\"text\":" + Q(text) + ",\"lineEnding\":" + Q(ending) + "}");
                        }
                        if (Hex(hash.Hash) != file.Sha256) throw new InvalidDataException("Interface/overlay SHA-256 changed while reading '" + file.RelativePath + "'.");
                    }
                }
            }
            return lines;
        }

        public static AuditLedgerSummary Write(AuditLedgerOptions options) {
            if (options == null || options.Graphs == null || options.Interfaces == null || options.Overlays == null)
                throw new ArgumentNullException("options/graphs/interfaces/overlays");
            if (options.SortChunkBytes < 1024 || options.SortChunkBytes > 1073741824L ||
                    options.MergeFanIn < 2 || options.MergeFanIn > 64 ||
                    options.MaximumRecordCharacters < 1024 || options.MaximumRecordCharacters > 134217728)
                throw new ArgumentOutOfRangeException("Invalid explicit audit resource budgets.");
            if (!Directory.Exists(options.OutputDirectory)) throw new DirectoryNotFoundException("Audit staging directory does not exist.");
            int selectedQueues = SelectedQueues(options.QueueFamilies);
            AuditLedgerSummary result = new AuditLedgerSummary();
            result.RecordFiles = (string[])Files.Clone();
            string spool = Path.Combine(options.OutputDirectory, ".audit-index-" + Guid.NewGuid().ToString("N"));
            if (Directory.Exists(spool) || File.Exists(spool)) throw new IOException("Audit index scratch already exists.");
            Directory.CreateDirectory(spool);
            string symbolDigests = Path.Combine(spool, "symbol-digests.bin");
            string relationshipDigests = Path.Combine(spool, "relationship-digests.bin");
            ExternalIndex index = new ExternalIndex(spool, options.SortChunkBytes,
                options.MaximumRecordCharacters, options.MergeFanIn, result.Inventory);
            List<AuditGraphState> states = new List<AuditGraphState>();
            using (BinaryWriter symbolHashes = new BinaryWriter(new FileStream(symbolDigests, FileMode.CreateNew)))
            using (BinaryWriter relationshipHashes = new BinaryWriter(new FileStream(relationshipDigests, FileMode.CreateNew)))
            using (StreamWriter occurrences = Writer(Path.Combine(options.OutputDirectory, "occurrences.ndjson")))
            using (StreamWriter relationships = Writer(Path.Combine(options.OutputDirectory, "relationships.ndjson")))
            using (StreamWriter graphFields = Writer(Path.Combine(options.OutputDirectory, "graph-fields.ndjson")))
            using (StreamWriter partitions = Writer(Path.Combine(options.OutputDirectory, "partitions.ndjson")))
            using (SHA256 graphSet = SHA256.Create()) {
                string previous = null;
                foreach (GraphInput graph in options.Graphs) {
                    if (previous != null && StringComparer.Ordinal.Compare(previous, graph.RelativePath) >= 0)
                        throw new InvalidDataException("Audit graph paths must be unique and ordinally sorted.");
                    previous = graph.RelativePath;
                    AuditGraphState state = new AuditGraphState { Input = graph, FirstSymbol = result.Inventory.DeclarationOccurrences };
                    GraphVisitSummary visited = InventoryWriter.VisitGraph(graph, delegate(RawGraphRecord record) {
                        string provenance = "\"reviewStatus\":\"unreviewed\",\"graphPath\":" + Q(graph.RelativePath) +
                            ",\"requestedModule\":" + Q(graph.RequestedModule) + ",\"target\":" + Q(graph.Target);
                        if (record.Kind == "symbol") {
                            long offset = symbolHashes.BaseStream.Position;
                            symbolHashes.Write(Digest(record.InventoryJson));
                            symbolHashes.Write(QueueMask(record.Json, options.MaximumRecordCharacters));
                            index.Add(record.PreciseIdentifier, result.Inventory.DeclarationOccurrences, offset);
                            occurrences.WriteLine("{" + provenance + ",\"symbolIndex\":" + N(record.Index) +
                                ",\"preciseIdentifier\":" + Q(record.PreciseIdentifier) + ",\"symbol\":" + record.Json + "}");
                            result.Inventory.DeclarationOccurrences++;
                        } else if (record.Kind == "relationship") {
                            relationshipHashes.Write(Digest(record.InventoryJson));
                            relationships.WriteLine("{" + provenance + ",\"relationshipIndex\":" + N(record.Index) +
                                ",\"relationship\":" + record.Json + "}");
                            result.Inventory.RelationshipOccurrences++;
                        } else {
                            graphFields.WriteLine("{" + provenance + ",\"rootFieldIndex\":" + N(record.Index) +
                                ",\"field\":" + Q(record.Name) + ",\"value\":" + record.Json + "}");
                            result.GraphFieldFacts++;
                        }
                    }, options.MaximumRecordCharacters);
                    state.SymbolCount = visited.Statistics.DeclarationOccurrences;
                    state.RecordDigest = Digest(visited.GraphRecord); states.Add(state);
                    partitions.WriteLine("{\"reviewStatus\":\"unreviewed\",\"graph\":" + visited.GraphRecord + "}");
                    result.Inventory.Graphs++; result.Inventory.InputBytes += visited.Statistics.InputBytes;
                    result.Inventory.LargestRecordCharacters = Math.Max(result.Inventory.LargestRecordCharacters, visited.Statistics.LargestRecordCharacters);
                    byte[] line = UTF8.GetBytes(graph.RelativePath + "\t" + visited.Sha256 + "\n");
                    graphSet.TransformBlock(line, 0, line.Length, null, 0);
                }
                graphSet.TransformFinalBlock(new byte[0], 0, 0);
                result.Inventory.GraphSetSha256 = Hex(graphSet.Hash);
            }
            string sortedIndex = index.Finish();
            if (result.Inventory.GraphSetSha256 != options.GraphSetSha256 ||
                    result.Inventory.Graphs != options.ExpectedGraphs || result.Inventory.PreciseSymbols != options.ExpectedPreciseSymbols ||
                    result.Inventory.DeclarationOccurrences != options.ExpectedDeclarations || result.Inventory.RelationshipOccurrences != options.ExpectedRelationships)
                throw new InvalidDataException("Successful capture counts/graphSetSha256 do not match every raw graph record.");
            ValidateInventory(options, result, states, sortedIndex, symbolDigests, relationshipDigests,
                Path.Combine(options.OutputDirectory, "inventory-facts.ndjson"));
            using (RunReader sorted = new RunReader(sortedIndex, options.MaximumRecordCharacters))
            using (BinaryReader payloads = new BinaryReader(File.OpenRead(symbolDigests)))
            using (StreamWriter identities = Writer(Path.Combine(options.OutputDirectory, "identities.ndjson")))
            using (StreamWriter queues = Writer(Path.Combine(options.OutputDirectory, "candidate-queues.ndjson"))) {
                while (sorted.Current != null) {
                    string identifier = sorted.Current.Identifier;
                    long count = 0; int queuesForIdentity = 0;
                    do {
                        payloads.BaseStream.Position = sorted.Current.Offset + 32;
                        queuesForIdentity |= payloads.ReadInt32();
                        count++; sorted.Advance();
                    } while (sorted.Current != null && sorted.Current.Identifier == identifier);
                    result.Inventory.LargestOccurrenceGroup = Math.Max(result.Inventory.LargestOccurrenceGroup, count);
                    identities.WriteLine("{\"reviewStatus\":\"unreviewed\",\"preciseIdentifier\":" + Q(identifier) +
                        ",\"occurrenceCount\":" + N(count) + "}");
                    for (int family = 0; family < Families.Length; family++) if ((queuesForIdentity & selectedQueues & (1 << family)) != 0) {
                        queues.WriteLine("{\"reviewStatus\":\"unreviewed\",\"selection\":\"lexical-candidate-only\",\"family\":" +
                            Q(Families[family]) + ",\"preciseIdentifier\":" + Q(identifier) + "}");
                        result.QueueRecords++;
                    }
                }
            }
            result.InterfaceFiles = options.Interfaces.Length;
            result.InterfaceLines = WriteTextFacts(options.Interfaces, Path.Combine(options.OutputDirectory, "interface-facts.ndjson"),
                "interface", result, options.MaximumRecordCharacters);
            result.OverlayFiles = options.Overlays.Length;
            result.OverlayLines = WriteTextFacts(options.Overlays, Path.Combine(options.OutputDirectory, "overlay-facts.ndjson"),
                "overlay", result, options.MaximumRecordCharacters);
            // The caller publishes only a complete staging directory. This
            // generated, checked child is the only scratch removed here.
            if (Path.GetDirectoryName(Path.GetFullPath(spool)) != Path.GetFullPath(options.OutputDirectory) ||
                    (File.GetAttributes(spool) & FileAttributes.ReparsePoint) != 0)
                throw new IOException("Refusing unsafe audit index scratch cleanup.");
            Directory.Delete(spool, true);
            foreach (string name in Files) result.Inventory.OutputBytes += new FileInfo(Path.Combine(options.OutputDirectory, name)).Length;
            return result;
        }
    }

    public sealed class AuditReviewFileInput {
        public string Path, RelativePath, Sha256;
        public long Bytes;
    }
    public sealed class AuditReviewOptions {
        public AuditLedgerOptions Ledger;
        public AuditReviewFileInput[] Files;
        public string PreciseIdentifier, OutputDirectory;
    }
    public sealed class AuditReviewSummary {
        public AuditLedgerSummary Verified = new AuditLedgerSummary();
        public long SelectedOccurrences, IncidentRelationships, LedgerInputBytes;
        public string[] RecordFiles;
    }
    internal sealed class AuditReviewRow {
        public string Raw, Ending;
        public Dictionary<string, string> Fields;
    }

    // A review packet never infers an identifier from a spelling. Read every
    // sealed ledger row and pair it with the original bounded graph visitor.
    // Preserve selected row bytes (including JSON spellings and line endings),
    // and reuse the existing inventory/text reconciliation, not a new parser.
    public static class AuditReviewPacketWriter {
        private static readonly UTF8Encoding UTF8 = new UTF8Encoding(false, true);
        public static void ValidateMetadataObject(string text, int maximum) {
            if (text == null || maximum < 1024 || maximum > 134217728)
                throw new ArgumentOutOfRangeException("MaximumMetadataBytes");
            JsonInput input = new JsonInput(new StringReader(text), "review metadata", maximum);
            input.SkipUTF8BOM(); input.White();
            if (input.Peek() != '{') throw new InvalidDataException("Review metadata must have a JSON object root.");
            input.StartRecord(); input.ValidateMetadataValue(0); input.EndRecord(); input.EndDocument();
        }
        private static string Hex(byte[] bytes) { return BitConverter.ToString(bytes).Replace("-", "").ToLowerInvariant(); }
        private static byte[] Digest(string text) {
            using (SHA256 hash = SHA256.Create()) { return hash.ComputeHash(UTF8.GetBytes(text)); }
        }
        private static string Required(Dictionary<string, string> fields, string name) {
            string value;
            if (!fields.TryGetValue(name, out value)) throw new InvalidDataException("Missing ledger field '" + name + "'.");
            return value;
        }
        private static string Text(Dictionary<string, string> fields, string name, int maximum) {
            return JsonInput.DecodeString(Required(fields, name), name, maximum);
        }
        private static long Integer(Dictionary<string, string> fields, string name) {
            long value;
            if (!Int64.TryParse(Required(fields, name), NumberStyles.None, CultureInfo.InvariantCulture, out value))
                throw new InvalidDataException("Ledger count/index must be a nonnegative Int64: " + name);
            return value;
        }
        private static StreamWriter Writer(string path) {
            StreamWriter result = new StreamWriter(new FileStream(path, FileMode.CreateNew, FileAccess.Write, FileShare.None), UTF8, 65536);
            result.NewLine = "\n"; return result;
        }
        private static void CopyRow(StreamWriter writer, AuditReviewRow row) { writer.Write(row.Raw); writer.Write(row.Ending); }
        private static void Provenance(AuditReviewRow row, GraphInput graph, int maximum) {
            if (Text(row.Fields, "graphPath", maximum) != graph.RelativePath ||
                    Text(row.Fields, "requestedModule", maximum) != graph.RequestedModule ||
                    Text(row.Fields, "target", maximum) != graph.Target)
                throw new InvalidDataException("Ledger row has the wrong graph/module/target provenance.");
        }
        private static void VerifyFile(AuditReviewFileInput expected, string actualPath) {
            using (FileStream input = new FileStream(actualPath, FileMode.Open, FileAccess.Read, FileShare.Read, 65536))
            using (SHA256 hash = SHA256.Create()) {
                if (input.Length != expected.Bytes || Hex(hash.ComputeHash(input)) != expected.Sha256)
                    throw new InvalidDataException("Ledger size/SHA-256 mismatch: " + expected.RelativePath);
            }
        }
        private sealed class Rows : IDisposable {
            private readonly AuditReviewFileInput file;
            private readonly int maximum;
            private readonly FileStream stream;
            private readonly SHA256 hash;
            private readonly CryptoStream hashed;
            private readonly StreamReader reader;
            private bool ended;
            public Rows(AuditReviewFileInput input, int limit) {
                file = input; maximum = limit;
                stream = new FileStream(file.Path, FileMode.Open, FileAccess.Read, FileShare.Read, 65536);
                if (stream.Length != file.Bytes) { stream.Dispose(); throw new InvalidDataException("Ledger byte count changed: " + file.RelativePath); }
                hash = SHA256.Create();
                hashed = new CryptoStream(stream, hash, CryptoStreamMode.Read);
                reader = new StreamReader(hashed, UTF8, false, 65536);
            }
            public AuditReviewRow Next() {
                if (ended) return null;
                string raw, ending;
                if (!AuditLedgerWriter.ReadTextLine(reader, maximum, out raw, out ending)) {
                    ended = true;
                    if (Hex(hash.Hash) != file.Sha256) throw new InvalidDataException("Ledger SHA-256 mismatch: " + file.RelativePath);
                    return null;
                }
                if (raw.Length == 0 || ending.Length == 0)
                    throw new InvalidDataException("Empty or truncated NDJSON record; every ledger row must end with a newline: " + file.RelativePath);
                Dictionary<string, string> fields = JsonInput.Fields(raw, file.RelativePath, maximum);
                if (Text(fields, "reviewStatus", maximum) != "unreviewed")
                    throw new InvalidDataException("Ledger records must remain unreviewed: " + file.RelativePath);
                return new AuditReviewRow { Raw = raw, Ending = ending, Fields = fields };
            }
            public AuditReviewRow Need() {
                AuditReviewRow row = Next();
                if (row == null) throw new InvalidDataException("Missing/truncated ledger record: " + file.RelativePath);
                return row;
            }
            public void End() {
                if (Next() != null) throw new InvalidDataException("Duplicate or extra ledger record: " + file.RelativePath);
            }
            public void Dispose() { reader.Dispose(); hashed.Dispose(); stream.Dispose(); hash.Dispose(); }
        }
        public static AuditReviewSummary Write(AuditReviewOptions options) {
            if (options == null || options.Ledger == null || String.IsNullOrWhiteSpace(options.PreciseIdentifier))
                throw new ArgumentException("A ledger and one exact precise identifier are required.");
            AuditLedgerOptions ledger = options.Ledger;
            int maximum = ledger.MaximumRecordCharacters;
            if (maximum < 1024 || maximum > 134217728 || options.PreciseIdentifier.Length > maximum)
                throw new ArgumentOutOfRangeException("MaximumRecordCharacters");
            Dictionary<string, AuditReviewFileInput> files = new Dictionary<string, AuditReviewFileInput>(StringComparer.Ordinal);
            foreach (AuditReviewFileInput file in options.Files) files.Add(file.RelativePath, file);
            string[] names = new string[] { "identities.ndjson", "occurrences.ndjson", "relationships.ndjson", "graph-fields.ndjson",
                "partitions.ndjson", "inventory-facts.ndjson", "interface-facts.ndjson", "overlay-facts.ndjson", "candidate-queues.ndjson" };
            if (files.Count != names.Length) throw new InvalidDataException("A complete nine-stream ledger is required.");
            foreach (string name in names) if (!files.ContainsKey(name)) throw new InvalidDataException("Missing ledger stream: " + name);
            AuditReviewSummary result = new AuditReviewSummary();
            foreach (AuditReviewFileInput file in files.Values) result.LedgerInputBytes = checked(result.LedgerInputBytes + file.Bytes);
            string native = Path.Combine(options.OutputDirectory, "native");
            string context = Path.Combine(options.OutputDirectory, "context");
            Directory.CreateDirectory(native); Directory.CreateDirectory(context);
            string spool = Path.Combine(options.OutputDirectory, ".review-index-" + Guid.NewGuid().ToString("N"));
            if (Directory.Exists(spool) || File.Exists(spool)) throw new IOException("Review scratch already exists.");
            Directory.CreateDirectory(spool);
            string symbolDigests = Path.Combine(spool, "symbols.bin"), relationshipDigests = Path.Combine(spool, "relationships.bin");
            ExternalIndex index = new ExternalIndex(spool, ledger.SortChunkBytes, maximum, ledger.MergeFanIn, result.Verified.Inventory);
            List<AuditGraphState> states = new List<AuditGraphState>();
            using (Rows occurrences = new Rows(files["occurrences.ndjson"], maximum))
            using (Rows relationships = new Rows(files["relationships.ndjson"], maximum))
            using (Rows fields = new Rows(files["graph-fields.ndjson"], maximum))
            using (Rows partitions = new Rows(files["partitions.ndjson"], maximum))
            using (BinaryWriter symbolHashes = new BinaryWriter(new FileStream(symbolDigests, FileMode.CreateNew)))
            using (BinaryWriter relationshipHashes = new BinaryWriter(new FileStream(relationshipDigests, FileMode.CreateNew)))
            using (StreamWriter selectedOccurrences = Writer(Path.Combine(native, "occurrences.ndjson")))
            using (StreamWriter selectedRelationships = Writer(Path.Combine(native, "relationships.ndjson")))
            using (StreamWriter contextFields = Writer(Path.Combine(context, "graph-fields.ndjson")))
            using (StreamWriter contextPartitions = Writer(Path.Combine(context, "partitions.ndjson")))
            using (SHA256 graphSet = SHA256.Create()) {
                string previous = null;
                foreach (GraphInput graph in ledger.Graphs) {
                    if (previous != null && StringComparer.Ordinal.Compare(previous, graph.RelativePath) >= 0)
                        throw new InvalidDataException("Graph partitions are duplicated or out of order.");
                    previous = graph.RelativePath;
                    AuditGraphState state = new AuditGraphState { Input = graph, FirstSymbol = result.Verified.Inventory.DeclarationOccurrences };
                    GraphVisitSummary visited = InventoryWriter.VisitGraph(graph, delegate(RawGraphRecord record) {
                        if (record.Kind == "symbol") {
                            AuditReviewRow row = occurrences.Need(); Provenance(row, graph, maximum);
                            if (Integer(row.Fields, "symbolIndex") != record.Index ||
                                    Text(row.Fields, "preciseIdentifier", maximum) != record.PreciseIdentifier ||
                                    Required(row.Fields, "symbol") != record.Json)
                                throw new InvalidDataException("Missing, duplicated or changed raw declaration occurrence.");
                            long offset = symbolHashes.BaseStream.Position;
                            symbolHashes.Write(Digest(record.InventoryJson));
                            symbolHashes.Write(AuditLedgerWriter.QueueMask(record.Json, maximum));
                            index.Add(record.PreciseIdentifier, result.Verified.Inventory.DeclarationOccurrences, offset);
                            if (record.PreciseIdentifier == options.PreciseIdentifier) {
                                CopyRow(selectedOccurrences, row); result.SelectedOccurrences++;
                            }
                            result.Verified.Inventory.DeclarationOccurrences++;
                        } else if (record.Kind == "relationship") {
                            AuditReviewRow row = relationships.Need(); Provenance(row, graph, maximum);
                            if (Integer(row.Fields, "relationshipIndex") != record.Index || Required(row.Fields, "relationship") != record.Json)
                                throw new InvalidDataException("Missing, duplicated or changed raw relationship.");
                            relationshipHashes.Write(Digest(record.InventoryJson));
                            Dictionary<string, string> relation = JsonInput.Fields(record.Json, "relationship", maximum);
                            if (Text(relation, "source", maximum) == options.PreciseIdentifier ||
                                    Text(relation, "target", maximum) == options.PreciseIdentifier) {
                                CopyRow(selectedRelationships, row); result.IncidentRelationships++;
                            }
                            result.Verified.Inventory.RelationshipOccurrences++;
                        } else {
                            AuditReviewRow row = fields.Need(); Provenance(row, graph, maximum);
                            if (Integer(row.Fields, "rootFieldIndex") != record.Index ||
                                    Text(row.Fields, "field", maximum) != record.Name || Required(row.Fields, "value") != record.Json)
                                throw new InvalidDataException("Missing, duplicated or changed graph context field.");
                            CopyRow(contextFields, row); result.Verified.GraphFieldFacts++;
                        }
                    }, maximum);
                    AuditReviewRow partition = partitions.Need();
                    if (Required(partition.Fields, "graph") != visited.GraphRecord)
                        throw new InvalidDataException("Partition context differs from the authoritative raw graph.");
                    CopyRow(contextPartitions, partition);
                    state.SymbolCount = visited.Statistics.DeclarationOccurrences; state.RecordDigest = Digest(visited.GraphRecord); states.Add(state);
                    result.Verified.Inventory.Graphs++; result.Verified.Inventory.InputBytes += visited.Statistics.InputBytes;
                    result.Verified.Inventory.LargestRecordCharacters = Math.Max(result.Verified.Inventory.LargestRecordCharacters, visited.Statistics.LargestRecordCharacters);
                    byte[] line = UTF8.GetBytes(graph.RelativePath + "\t" + visited.Sha256 + "\n");
                    graphSet.TransformBlock(line, 0, line.Length, null, 0);
                }
                occurrences.End(); relationships.End(); fields.End(); partitions.End();
                graphSet.TransformFinalBlock(new byte[0], 0, 0);
                result.Verified.Inventory.GraphSetSha256 = Hex(graphSet.Hash);
            }
            string sortedIndex = index.Finish();
            if (result.Verified.Inventory.GraphSetSha256 != ledger.GraphSetSha256 ||
                    result.Verified.Inventory.Graphs != ledger.ExpectedGraphs ||
                    result.Verified.Inventory.PreciseSymbols != ledger.ExpectedPreciseSymbols ||
                    result.Verified.Inventory.DeclarationOccurrences != ledger.ExpectedDeclarations ||
                    result.Verified.Inventory.RelationshipOccurrences != ledger.ExpectedRelationships)
                throw new InvalidDataException("Complete capture counts and graph-set hash do not match the ledger.");
            AuditLedgerWriter.ValidateInventory(ledger, result.Verified, states, sortedIndex, symbolDigests, relationshipDigests,
                Path.Combine(context, "inventory-facts.ndjson"));
            using (Rows identities = new Rows(files["identities.ndjson"], maximum))
            using (Rows queues = new Rows(files["candidate-queues.ndjson"], maximum))
            using (RunReader sorted = new RunReader(sortedIndex, maximum))
            using (BinaryReader payloads = new BinaryReader(File.OpenRead(symbolDigests)))
            using (StreamWriter identity = Writer(Path.Combine(native, "identity.ndjson")))
            using (StreamWriter contextQueues = Writer(Path.Combine(context, "candidate-queues.ndjson"))) {
                int selectedQueues = AuditLedgerWriter.SelectedQueues(ledger.QueueFamilies);
                bool found = false;
                while (sorted.Current != null) {
                    string identifier = sorted.Current.Identifier;
                    long count = 0; int masks = 0;
                    do {
                        payloads.BaseStream.Position = sorted.Current.Offset + 32;
                        masks |= payloads.ReadInt32(); count++; sorted.Advance();
                    } while (sorted.Current != null && sorted.Current.Identifier == identifier);
                    result.Verified.Inventory.LargestOccurrenceGroup = Math.Max(result.Verified.Inventory.LargestOccurrenceGroup, count);
                    AuditReviewRow row = identities.Need();
                    if (Text(row.Fields, "preciseIdentifier", maximum) != identifier || Integer(row.Fields, "occurrenceCount") != count)
                        throw new InvalidDataException("Identity rows are missing, duplicated, ambiguous or have the wrong occurrence count.");
                    if (identifier == options.PreciseIdentifier) {
                        if (found || count != result.SelectedOccurrences) throw new InvalidDataException("Ambiguous selected identity or incomplete occurrences.");
                        found = true; CopyRow(identity, row);
                    }
                    for (int family = 0; family < AuditLedgerWriter.Families.Length; family++) if ((masks & selectedQueues & (1 << family)) != 0) {
                        AuditReviewRow queue = queues.Need();
                        if (Text(queue.Fields, "preciseIdentifier", maximum) != identifier ||
                                Text(queue.Fields, "family", maximum) != AuditLedgerWriter.Families[family] ||
                                Text(queue.Fields, "selection", maximum) != "lexical-candidate-only")
                            throw new InvalidDataException("Candidate queue records differ from the complete ledger.");
                        CopyRow(contextQueues, queue); result.Verified.QueueRecords++;
                    }
                }
                identities.End(); queues.End();
                if (!found || result.SelectedOccurrences == 0) throw new InvalidDataException("Exact precise identifier was not found in the complete ledger.");
            }
            result.Verified.InterfaceFiles = ledger.Interfaces.Length;
            result.Verified.InterfaceLines = AuditLedgerWriter.WriteTextFacts(ledger.Interfaces, Path.Combine(context, "interface-facts.ndjson"),
                "interface", result.Verified, maximum);
            result.Verified.OverlayFiles = ledger.Overlays.Length;
            result.Verified.OverlayLines = AuditLedgerWriter.WriteTextFacts(ledger.Overlays, Path.Combine(context, "overlay-facts.ndjson"),
                "overlay", result.Verified, maximum);
            foreach (string name in new string[] { "inventory-facts.ndjson", "interface-facts.ndjson", "overlay-facts.ndjson" }) {
                VerifyFile(files[name], files[name].Path);
                VerifyFile(files[name], Path.Combine(context, name));
            }
            if (Path.GetDirectoryName(Path.GetFullPath(spool)) != Path.GetFullPath(options.OutputDirectory) ||
                    (File.GetAttributes(spool) & FileAttributes.ReparsePoint) != 0)
                throw new IOException("Refusing unsafe review scratch cleanup.");
            Directory.Delete(spool, true);
            result.RecordFiles = new string[] { "native/identity.ndjson", "native/occurrences.ndjson", "native/relationships.ndjson",
                "context/graph-fields.ndjson", "context/partitions.ndjson", "context/inventory-facts.ndjson",
                "context/interface-facts.ndjson", "context/overlay-facts.ndjson", "context/candidate-queues.ndjson" };
            foreach (string name in result.RecordFiles) result.Verified.Inventory.OutputBytes += new FileInfo(Path.Combine(options.OutputDirectory, name)).Length;
            return result;
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
