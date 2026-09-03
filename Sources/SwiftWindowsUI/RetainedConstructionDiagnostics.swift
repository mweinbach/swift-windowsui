import Foundation

/// An opt-in diagnostic resource, never an owner, admission proof, or current case.
/// The runner supplies one exclusively created, empty file in its attempt directory.
package enum RetainedConstructionDiagnostics {
    package static let environmentKey = "SWIFT_WINDOWSUI_FILE14_TRACE_FILE"
    static let validationCountersEnvironmentKey = "SWIFT_WINDOWSUI_KEYBOARD_VALIDATION_COUNTERS"
    static let validationCountersFlag = ProcessInfo.processInfo.environment[validationCountersEnvironmentKey]

    @MainActor
    static func validationCounters(
        for trace: RetainedConstructionTrace?, flag: String?
    ) -> RetainedConstructionValidationCounters? {
        guard trace != nil, flag == "1" else { return nil }
        return RetainedConstructionValidationCounters()
    }

    /// Read once. The absent-variable path allocates no writer, lock, or observer.
    package static let writer = configuredWriter(path: ProcessInfo.processInfo.environment[environmentKey])

    /// Explicit configuration also lets writer tests avoid changing the process environment.
    package static func configuredWriter(path: String?) -> RetainedConstructionTraceWriter? {
        guard let path, !path.isEmpty else { return nil }
        return try? RetainedConstructionTraceWriter(path: path)
    }
}

/// Every mutable field, native write, and close is protected by `lock`. Neither
/// a file handle nor mutable state escapes the production initializer. Records
/// contain only scalars and XCTest metadata; no application callback is invoked
/// while locked. This is the sole unchecked conformance in this diagnostic.
package final class RetainedConstructionTraceWriter: @unchecked Sendable {
    package enum Status: Sendable, Equatable {
        case active
        case capReached
        case recordRejected
        case writeFailed
        case closed
    }

    enum OpenError: Error {
        case invalidPath
        case notRegularFile
        case nonemptyFile
        case invalidLimit
        case headerWriteFailed
    }

    package static let maximumFileBytes = 64 * 1_024 * 1_024
    private static let terminalReserve = 256
    private static let maximumRecordBytes = 16 * 1_024
    private static let maximumCaseNameBytes = 2_048

    private let lock = NSLock()
    private let byteLimit: Int
    private var file: FileHandle?
    private var sequence: UInt64 = 0
    private var writtenBytes = 0
    private var currentStatus = Status.active

    package var status: Status {
        lock.lock()
        defer { lock.unlock() }
        return currentStatus
    }

    package var bytesWritten: Int {
        lock.lock()
        defer { lock.unlock() }
        return writtenBytes
    }

    /// Opens without creation, truncation, or replacement. A second size check
    /// on the opened handle rejects a file populated between stat and open.
    package convenience init(
        path: String, byteLimit: Int = RetainedConstructionTraceWriter.maximumFileBytes
    ) throws {
        guard Self.isAbsolutePath(path), !path.utf8.contains(0) else { throw OpenError.invalidPath }
        let attributes = try FileManager.default.attributesOfItem(atPath: path)
        guard attributes[.type] as? FileAttributeType == .typeRegular else { throw OpenError.notRegularFile }
        guard (attributes[.size] as? NSNumber)?.uint64Value == 0 else { throw OpenError.nonemptyFile }
        let file = try FileHandle(forWritingTo: URL(fileURLWithPath: path))
        do {
            guard try file.seekToEnd() == 0 else { throw OpenError.nonemptyFile }
            try self.init(ownedFile: file, byteLimit: byteLimit)
        } catch {
            try? file.close()
            throw error
        }
    }

    /// Internal native-handle seam for a synchronous writer regression only.
    /// Production passes exclusive ownership from the validated path above.
    /// A test may close its original handle between calls to induce a real
    /// write failure, but must never access it concurrently with this writer.
    init(ownedFile: FileHandle, byteLimit: Int) throws {
        guard (Self.terminalReserve * 2...Self.maximumFileBytes).contains(byteLimit) else {
            throw OpenError.invalidLimit
        }
        self.byteLimit = byteLimit
        file = ownedFile
        let fields = Data(
            "\"event\":\"trace.open\",\"pid\":\(ProcessInfo.processInfo.processIdentifier),\"byteLimit\":\(byteLimit)"
                .utf8)
        guard append(fields: fields) != nil else { throw OpenError.headerWriteFailed }
    }

    deinit {
        lock.lock()
        defer { lock.unlock() }
        closeLocked()
    }

    /// Only explicit writer fixtures close a sink. The process sink remains
    /// available for late runtime events after the class observer is removed.
    func close() {
        lock.lock()
        defer { lock.unlock() }
        if currentStatus == .active { currentStatus = .closed }
        closeLocked()
    }

    /// Returns the sequence of a completed write, suitable as a span or birth
    /// token. No token is returned for an absent, rejected, or partial write.
    @discardableResult
    package func record(
        _ event: StaticString, span: UInt64? = nil, runtime: UInt? = nil, birth: UInt64? = nil,
        host: UInt? = nil, node: UInt? = nil, caseID: UInt? = nil, caseName: String? = nil
    ) -> UInt64? {
        guard status == .active else { return nil }
        guard event.utf8CodeUnitCount <= 128,
            caseName.map({ $0.utf8.prefix(Self.maximumCaseNameBytes + 1).count <= Self.maximumCaseNameBytes })
                != false
        else {
            rejectRecord()
            return nil
        }
        // Finish metadata escaping before taking the writer lock. The small
        // sequence prefix is added under the lock, where its value is assigned.
        var fields = "\"event\":\(Self.quoted(String(describing: event)))"
        if let span { fields += ",\"span\":\(span)" }
        if let runtime { fields += ",\"runtime\":\(runtime)" }
        if let birth { fields += ",\"birth\":\(birth)" }
        if let host { fields += ",\"host\":\(host)" }
        if let node { fields += ",\"node\":\(node)" }
        if let caseID { fields += ",\"caseID\":\(caseID)" }
        if let caseName { fields += ",\"caseName\":\(Self.quoted(caseName))" }
        let data = Data(fields.utf8)
        guard data.count <= Self.maximumRecordBytes else {
            rejectRecord()
            return nil
        }
        return append(fields: data)
    }

    /// Fixed scalar metadata is formatted only at a phase boundary.
    @discardableResult
    func recordValidationPhase(
        _ event: StaticString, span: UInt64? = nil, runtime: UInt, birth: UInt64,
        host: UInt? = nil, node: UInt? = nil, monotonicSeconds: Double,
        snapshot: RetainedConstructionValidationCounters.Snapshot, partial: Bool
    ) -> UInt64? {
        guard status == .active else { return nil }
        guard event.utf8CodeUnitCount <= 128, monotonicSeconds.isFinite else {
            rejectRecord()
            return nil
        }
        var fields = "\"event\":\(Self.quoted(String(describing: event)))"
        if let span { fields += ",\"span\":\(span)" }
        fields += ",\"runtime\":\(runtime),\"birth\":\(birth)"
        if let host { fields += ",\"host\":\(host)" }
        if let node { fields += ",\"node\":\(node)" }
        fields += ",\"monotonicSeconds\":\(monotonicSeconds),\"validationCounts\":{\(snapshot.jsonFields)}"
        fields += ",\"coverage\":\(Self.quoted(partial ? "PARTIAL" : "OBSERVED"))"
        let data = Data(fields.utf8)
        guard data.count <= Self.maximumRecordBytes else {
            rejectRecord()
            return nil
        }
        return append(fields: data)
    }

    package func runtimeTrace(nativeID: UInt) -> RetainedConstructionTrace? {
        guard let birth = record("runtime.birth", runtime: nativeID) else { return nil }
        return RetainedConstructionTrace(writer: self, runtimeID: nativeID, birth: birth)
    }

    private func append(fields: Data) -> UInt64? {
        lock.lock()
        defer { lock.unlock() }
        guard currentStatus == .active else { return nil }
        let next = sequence.addingReportingOverflow(1)
        guard !next.overflow else {
            currentStatus = .recordRejected
            closeLocked()
            return nil
        }
        let line = Self.line(sequence: next.partialValue, fields: fields)
        guard line.count <= byteLimit - Self.terminalReserve - writtenBytes else {
            finishPartialLocked(event: "trace.capReached", status: .capReached)
            return nil
        }
        guard writeLocked(line) else { return nil }
        sequence = next.partialValue
        return sequence
    }

    private func rejectRecord() {
        lock.lock()
        defer { lock.unlock() }
        guard currentStatus == .active else { return }
        finishPartialLocked(event: "trace.recordRejected", status: .recordRejected)
    }

    /// Ordinary records always leave this much room. The terminal record is
    /// complete and explicitly PARTIAL; reaching the cap never claims a pass.
    private func finishPartialLocked(event: StaticString, status: Status) {
        let next = sequence.addingReportingOverflow(1)
        guard !next.overflow else {
            currentStatus = .recordRejected
            closeLocked()
            return
        }
        let fields = Data("\"event\":\"\(event)\",\"coverage\":\"PARTIAL\"".utf8)
        let line = Self.line(sequence: next.partialValue, fields: fields)
        guard line.count <= Self.terminalReserve, line.count <= byteLimit - writtenBytes else {
            currentStatus = .recordRejected
            closeLocked()
            return
        }
        guard writeLocked(line) else { return }
        sequence = next.partialValue
        currentStatus = status
        closeLocked()
    }

    private func writeLocked(_ line: Data) -> Bool {
        guard let file else { return false }
        do {
            // One synchronous FileHandle API call, not stdout or a delayed
            // logger. Foundation may issue multiple OS writes; readers accept
            // only complete lines, never assume in-progress writes are atomic.
            try file.write(contentsOf: line)
            writtenBytes += line.count
            return true
        } catch {
            // A failed write may have a partial final line. Do not append a
            // guessed terminal record or retry; the reader must mark PARTIAL.
            currentStatus = .writeFailed
            closeLocked()
            return false
        }
    }

    private func closeLocked() {
        try? file?.close()
        file = nil
    }

    private static func line(sequence: UInt64, fields: Data) -> Data {
        var line = Data("{\"version\":1,\"sequence\":\(sequence),".utf8)
        line.append(fields)
        line.append(contentsOf: [0x7D, 0x0A])
        return line
    }

    private static func quoted(_ string: String) -> String {
        var result = "\""
        for scalar in string.unicodeScalars {
            switch scalar.value {
            case 0x22: result += "\\\""
            case 0x5C: result += "\\\\"
            case 0..<0x20:
                let digits = String(scalar.value, radix: 16)
                result += "\\u" + String(repeating: "0", count: 4 - digits.count) + digits
            default: result.unicodeScalars.append(scalar)
            }
        }
        return result + "\""
    }

    private static func isAbsolutePath(_ path: String) -> Bool {
        #if os(Windows)
            // The attempt file is local. Accept a full drive path, including
            // Foundation's optional leading slash, not drive-relative or UNC.
            let prefix = Array(path.utf8.prefix(4))
            let offset = prefix.first == 0x2F ? 1 : 0
            guard prefix.count >= offset + 3 else { return false }
            let drive = prefix[offset]
            return ((0x41...0x5A).contains(drive) || (0x61...0x7A).contains(drive))
                && prefix[offset + 1] == 0x3A
                && (prefix[offset + 2] == 0x2F || prefix[offset + 2] == 0x5C)
        #else
            return path.hasPrefix("/")
        #endif
    }
}

/// A runtime keeps only its native address, a unique scalar birth token, and
/// the writer. This value never retains the runtime, a node, or a view payload.
package struct RetainedConstructionTrace: Sendable {
    private let writer: RetainedConstructionTraceWriter
    private let runtimeID: UInt
    private let birth: UInt64

    fileprivate init(writer: RetainedConstructionTraceWriter, runtimeID: UInt, birth: UInt64) {
        self.writer = writer
        self.runtimeID = runtimeID
        self.birth = birth
    }

    @discardableResult
    func recordValidationPhase(
        _ event: StaticString, span: UInt64? = nil, host: UInt? = nil, node: UInt? = nil,
        monotonicSeconds: Double, snapshot: RetainedConstructionValidationCounters.Snapshot, partial: Bool
    ) -> UInt64? {
        writer.recordValidationPhase(
            event, span: span, runtime: runtimeID, birth: birth, host: host, node: node,
            monotonicSeconds: monotonicSeconds, snapshot: snapshot, partial: partial)
    }

    @discardableResult
    package func record(_ event: StaticString, span: UInt64? = nil, host: UInt? = nil, node: UInt? = nil) -> UInt64? {
        writer.record(event, span: span, runtime: runtimeID, birth: birth, host: host, node: node)
    }
}
