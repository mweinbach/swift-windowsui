import Foundation
import XCTest

@testable import SwiftWindowsUI

/// Native writer fixtures only: no FileBrowser, runtime, actor hop, or process
/// environment mutation. These tests do not qualify a File14 execution.
final class RetainedConstructionDiagnosticsTests: XCTestCase {
    func testAbsentAndEmptyConfigurationDoNotOpenAFile() throws {
        let fixture = try TraceFileFixture()
        defer { fixture.remove() }
        XCTAssertNil(RetainedConstructionDiagnostics.configuredWriter(path: nil))
        XCTAssertNil(RetainedConstructionDiagnostics.configuredWriter(path: ""))
        XCTAssertEqual(try Data(contentsOf: fixture.file), Data())
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: fixture.directory.path), ["trace.jsonl"])
    }

    func testExplicitConfigurationWritesOnlyTheProvidedEmptyFile() throws {
        let fixture = try TraceFileFixture()
        defer { fixture.remove() }
        let untouched = fixture.directory.appendingPathComponent("untouched.jsonl")
        try Data().write(to: untouched, options: .withoutOverwriting)
        let writer = try XCTUnwrap(RetainedConstructionDiagnostics.configuredWriter(path: fixture.file.path))
        defer { writer.close() }
        XCTAssertNotNil(writer.record("explicit.configuration"))
        XCTAssertEqual(
            try readRecords(fixture.file).map { $0["event"] as? String }, ["trace.open", "explicit.configuration"])
        XCTAssertEqual(try Data(contentsOf: untouched), Data())
    }

    func testCompleteLinesAreVisibleBeforeWriterCloseOrProcessExit() throws {
        let fixture = try TraceFileFixture()
        defer { fixture.remove() }
        let writer = try RetainedConstructionTraceWriter(path: fixture.file.path)
        defer { writer.close() }
        let span = try XCTUnwrap(writer.record("operation.enter", runtime: 17, birth: 2))
        XCTAssertNotNil(writer.record("operation.returned", span: span, runtime: 17, birth: 2))

        // Read using an independent handle while the writer is still active.
        // No synchronization/flush, close, sleep, or process exit precedes it.
        let records = try readRecords(fixture.file)
        XCTAssertEqual(writer.status, .active)
        XCTAssertEqual(records.map { $0["event"] as? String }, ["trace.open", "operation.enter", "operation.returned"])
        XCTAssertEqual(records.compactMap { ($0["sequence"] as? NSNumber)?.uint64Value }, [1, 2, 3])
        XCTAssertEqual((records.last?["span"] as? NSNumber)?.uint64Value, span)
        XCTAssertEqual(writer.bytesWritten, try Data(contentsOf: fixture.file).count)
    }

    func testMissingRelativeAndDirectoryPathsAreRejectedWithoutCreation() throws {
        let fixture = try TraceFileFixture()
        defer { fixture.remove() }
        let missing = fixture.directory.appendingPathComponent("missing.jsonl")
        XCTAssertThrowsError(try RetainedConstructionTraceWriter(path: missing.path))
        XCTAssertThrowsError(try RetainedConstructionTraceWriter(path: "relative-file14-trace.jsonl"))
        XCTAssertThrowsError(try RetainedConstructionTraceWriter(path: fixture.directory.path))
        XCTAssertNil(RetainedConstructionDiagnostics.configuredWriter(path: missing.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: missing.path))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: fixture.directory.path), ["trace.jsonl"])
    }

    func testNonemptyFileIsRejectedWithoutReplacingEvidence() throws {
        let fixture = try TraceFileFixture()
        defer { fixture.remove() }
        let original = Data("existing evidence\n".utf8)
        try original.write(to: fixture.file)
        XCTAssertThrowsError(try RetainedConstructionTraceWriter(path: fixture.file.path))
        XCTAssertNil(RetainedConstructionDiagnostics.configuredWriter(path: fixture.file.path))
        XCTAssertEqual(try Data(contentsOf: fixture.file), original)
    }

    func testBoundedCapWritesOnePartialTerminalRecordAndDisablesFurtherWrites() throws {
        let fixture = try TraceFileFixture()
        defer { fixture.remove() }
        let limit = 1_024
        let writer = try RetainedConstructionTraceWriter(path: fixture.file.path, byteLimit: limit)
        defer { writer.close() }
        for _ in 0..<64 { writer.record("bounded.sample", runtime: 17, birth: 2, node: 99) }
        XCTAssertEqual(writer.status, .capReached)
        let before = try Data(contentsOf: fixture.file)
        let records = try readRecords(fixture.file)
        XCTAssertLessThanOrEqual(before.count, limit)
        XCTAssertEqual(records.filter { $0["event"] as? String == "trace.capReached" }.count, 1)
        XCTAssertEqual(records.last?["event"] as? String, "trace.capReached")
        XCTAssertEqual(records.last?["coverage"] as? String, "PARTIAL")
        XCTAssertNil(writer.record("must.not.appear"))
        XCTAssertEqual(try Data(contentsOf: fixture.file), before)
        XCTAssertEqual(writer.bytesWritten, before.count)
    }

    func testOversizedMetadataEndsWithPartialInsteadOfSilentlyTruncating() throws {
        let fixture = try TraceFileFixture()
        defer { fixture.remove() }
        let writer = try RetainedConstructionTraceWriter(path: fixture.file.path)
        defer { writer.close() }
        XCTAssertNil(writer.record("case.enter", caseID: 11, caseName: String(repeating: "x", count: 2_049)))
        XCTAssertEqual(writer.status, .recordRejected)
        let records = try readRecords(fixture.file)
        XCTAssertEqual(records.map { $0["event"] as? String }, ["trace.open", "trace.recordRejected"])
        XCTAssertEqual(records.last?["coverage"] as? String, "PARTIAL")
        XCTAssertNil(writer.record("must.not.appear"))
        XCTAssertEqual(try readRecords(fixture.file).count, 2)
    }

    func testThrownWriteErrorIsStickyAndDoesNotFabricateACompletion() throws {
        let fixture = try TraceFileFixture()
        defer { fixture.remove() }
        let nativeFile = try FileHandle(forWritingTo: fixture.file)
        defer { try? nativeFile.close() }
        let writer = try RetainedConstructionTraceWriter(ownedFile: nativeFile, byteLimit: 2_048)
        defer { writer.close() }
        let span = try XCTUnwrap(writer.record("operation.enter"))
        let before = try Data(contentsOf: fixture.file)

        // Closing between calls exercises FileHandle's thrown invalid-handle
        // error. It does not prove partial OS-write recovery or abrupt-exit
        // durability, and introduces no race or callback/scheduling seam.
        try nativeFile.close()
        XCTAssertNil(writer.record("operation.returned", span: span))
        XCTAssertEqual(writer.status, .writeFailed)
        XCTAssertNil(writer.record("must.not.appear"))
        XCTAssertEqual(try Data(contentsOf: fixture.file), before)
        XCTAssertEqual(writer.bytesWritten, before.count)
        writer.close()
        XCTAssertEqual(writer.status, .writeFailed)
    }

    func testRuntimeBirthTokensDistinguishReusedNativeAddressesWithoutAnOwnerMap() throws {
        let fixture = try TraceFileFixture()
        defer { fixture.remove() }
        let writer = try RetainedConstructionTraceWriter(path: fixture.file.path)
        defer { writer.close() }
        let first = try XCTUnwrap(writer.runtimeTrace(nativeID: 17))
        XCTAssertNotNil(first.record("first.runtime"))
        let second = try XCTUnwrap(writer.runtimeTrace(nativeID: 17))
        XCTAssertNotNil(second.record("second.runtime"))
        let records = try readRecords(fixture.file)
        let births = records.filter { $0["event"] as? String == "runtime.birth" }
        XCTAssertEqual(births.count, 2)
        let tokens = births.compactMap { ($0["sequence"] as? NSNumber)?.uint64Value }
        XCTAssertEqual(Set(tokens).count, 2)
        XCTAssertEqual(births.compactMap { ($0["runtime"] as? NSNumber)?.uint64Value }, [17, 17])
        let firstToken = try XCTUnwrap(tokens.first)
        let secondToken = try XCTUnwrap(tokens.dropFirst().first)
        let firstRecord = try XCTUnwrap(records.first { $0["event"] as? String == "first.runtime" })
        let secondRecord = try XCTUnwrap(records.first { $0["event"] as? String == "second.runtime" })
        XCTAssertEqual((firstRecord["birth"] as? NSNumber)?.uint64Value, firstToken)
        XCTAssertEqual((secondRecord["birth"] as? NSNumber)?.uint64Value, secondToken)
    }

    func testCaseMetadataEscapingPreservesOneCompleteLine() throws {
        let fixture = try TraceFileFixture()
        defer { fixture.remove() }
        let writer = try RetainedConstructionTraceWriter(path: fixture.file.path)
        defer { writer.close() }
        let name = "metadata \"quoted\" \\ slash\n\r\t\0 café 👩🏽‍💻"
        XCTAssertNotNil(writer.record("case.enter", caseID: 123, caseName: name))
        let records = try readRecords(fixture.file)
        XCTAssertEqual(records.count, 2)
        XCTAssertEqual(records.last?["caseName"] as? String, name)
        XCTAssertEqual(records.compactMap { ($0["version"] as? NSNumber)?.intValue }, [1, 1])
    }

    func testInvalidCapsDoNotWriteAHeaderOrTruncateTheEmptyFile() throws {
        let fixture = try TraceFileFixture()
        defer { fixture.remove() }
        for limit in [511, RetainedConstructionTraceWriter.maximumFileBytes + 1] {
            XCTAssertThrowsError(try RetainedConstructionTraceWriter(path: fixture.file.path, byteLimit: limit))
            XCTAssertEqual(try Data(contentsOf: fixture.file), Data())
        }
    }

    private func readRecords(_ file: URL) throws -> [[String: Any]] {
        let data = try Data(contentsOf: file)
        XCTAssertEqual(data.last, 0x0A, "only newline-terminated records are complete")
        return try data.split(separator: 0x0A).map { line in
            try XCTUnwrap(JSONSerialization.jsonObject(with: Data(line)) as? [String: Any])
        }
    }
}

private struct TraceFileFixture {
    let directory: URL
    let file: URL

    init() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("file14-writer-\(UUID().uuidString)")
        file = directory.appendingPathComponent("trace.jsonl")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        try Data().write(to: file, options: .withoutOverwriting)
    }

    func remove() {
        // This immutable URL was created above, never received from an env var
        // or supplied path. Cleanup is restricted to this fixture's directory.
        try? FileManager.default.removeItem(at: directory)
    }
}
