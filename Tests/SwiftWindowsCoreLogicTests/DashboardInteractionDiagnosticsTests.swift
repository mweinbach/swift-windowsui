import Foundation
@preconcurrency import XCTest

@testable import SwiftWindowsUI

/// Local diagnostic resources only. No Dashboard body, runtime, observer registration,
/// process environment mutation, task, sleep, or performance claim is involved.
@MainActor
final class DashboardInteractionDiagnosticsTests: XCTestCase {
    private let methodName = "testInitialPreviewKeepsTheExistingChartAndFocusableInputControls"

    func testAbsentAndEmptyDashboardConfigurationDoNotOpenAFile() async throws {
        let fixture = try DashboardTraceFileFixture()
        defer { fixture.remove() }
        XCTAssertNil(DashboardInteractionDiagnostics.configuredWriter(path: nil))
        XCTAssertNil(DashboardInteractionDiagnostics.configuredWriter(path: ""))
        XCTAssertNil(DashboardInteractionDiagnostics.record("fixture.init.enter", writer: nil))
        XCTAssertEqual(try Data(contentsOf: fixture.file), Data())
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: fixture.directory.path), ["trace.jsonl"])
    }

    func testDashboardConfigurationUsesOnlyItsExplicitEmptySink() async throws {
        let fixture = try DashboardTraceFileFixture()
        defer { fixture.remove() }
        let untouched = fixture.directory.appendingPathComponent("untouched.jsonl")
        try Data().write(to: untouched, options: .withoutOverwriting)
        let environmentBefore = ProcessInfo.processInfo.environment
        let writer = try XCTUnwrap(DashboardInteractionDiagnostics.configuredWriter(path: fixture.file.path))
        defer { writer.close() }
        XCTAssertEqual(DashboardInteractionDiagnostics.environmentKey, "SWIFT_WINDOWSUI_DASHBOARD_UI11_TRACE_FILE")
        XCTAssertNotEqual(
            DashboardInteractionDiagnostics.environmentKey, RetainedConstructionDiagnostics.environmentKey)
        XCTAssertEqual(RetainedConstructionTraceWriter.maximumFileBytes, 67_108_864)
        XCTAssertNotNil(DashboardInteractionDiagnostics.record("fixture.init.enter", writer: writer))
        XCTAssertEqual(try records(fixture.file).map { $0["event"] as? String }, ["trace.open", "fixture.init.enter"])
        XCTAssertEqual(try Data(contentsOf: untouched), Data())
        XCTAssertEqual(ProcessInfo.processInfo.environment, environmentBefore)
    }

    func testObserverFiltersOtherClassesAndKeepsActualCaseMetadata() async throws {
        let fixture = try DashboardTraceFileFixture()
        defer { fixture.remove() }
        let writer = try RetainedConstructionTraceWriter(path: fixture.file.path)
        defer { writer.close() }
        let observer = DashboardInteractionTraceObserver(writer: writer)
        let other = XCTestCase(name: methodName, testClosure: { _ in })
        observer.testCaseWillStart(other)
        observer.testCaseDidFinish(other)
        XCTAssertEqual(try records(fixture.file).count, 1)

        // Construction stores an inert closure; neither case nor its async body is run.
        let actual = DemoDashboardDataInteractionTests(name: methodName, testClosure: { _ in })
        observer.testCaseWillStart(actual)
        observer.testCaseDidFinish(actual)
        let observed = try records(fixture.file)
        XCTAssertEqual(observed.map { $0["event"] as? String }, ["trace.open", "case.enter", "case.exit"])
        XCTAssertEqual(observed.last?["caseName"] as? String, actual.name)
        XCTAssertEqual(
            (observed.last?["caseID"] as? NSNumber)?.uint64Value,
            UInt64(UInt(bitPattern: ObjectIdentifier(actual))))
    }

    func testCallbackBodyAndFinishEventsRemainDistinct() async throws {
        let fixture = try DashboardTraceFileFixture()
        defer { fixture.remove() }
        let writer = try RetainedConstructionTraceWriter(path: fixture.file.path)
        defer { writer.close() }
        let observer = DashboardInteractionTraceObserver(writer: writer)
        let actual = DemoDashboardDataInteractionTests(name: methodName, testClosure: { _ in })
        observer.recordRegistered()
        observer.testCaseWillStart(actual)
        DashboardInteractionDiagnostics.recordBodyEntry(actual, writer: writer)
        observer.testCaseDidFinish(actual)
        observer.recordRemoved()
        let observed = try records(fixture.file)
        XCTAssertEqual(
            observed.map { $0["event"] as? String },
            [
                "trace.open", "observer.registered", "case.enter", "case.body.enter", "case.exit", "observer.removed",
            ])
        XCTAssertEqual(observed.compactMap { ($0["sequence"] as? NSNumber)?.uint64Value }, [1, 2, 3, 4, 5, 6])
        XCTAssertEqual(observed.filter { $0["caseName"] as? String == actual.name }.count, 3)
        XCTAssertFalse(observed.contains { $0["passed"] != nil || $0["result"] != nil })
    }

    func testCaseMetadataRecordingDoesNotRetainTheTestCase() async throws {
        let fixture = try DashboardTraceFileFixture()
        defer { fixture.remove() }
        let writer = try RetainedConstructionTraceWriter(path: fixture.file.path)
        defer { writer.close() }
        let observer = DashboardInteractionTraceObserver(writer: writer)
        var actual: DemoDashboardDataInteractionTests? = DemoDashboardDataInteractionTests(
            name: methodName, testClosure: { _ in })
        weak var weakCase: XCTestCase? = actual
        if let actual {
            observer.testCaseWillStart(actual)
            DashboardInteractionDiagnostics.recordBodyEntry(actual, writer: writer)
            observer.testCaseDidFinish(actual)
        }
        actual = nil
        XCTAssertNil(weakCase)
        XCTAssertEqual(writer.status, .active)
        XCTAssertEqual(try records(fixture.file).count, 4)
        // Keep the writer/observer alive after the weak check without another test object.
        observer.recordRemoved()
    }

    func testPhasePairsAreVisibleWithDistinctSpansBeforeClose() async throws {
        let fixture = try DashboardTraceFileFixture()
        defer { fixture.remove() }
        let writer = try RetainedConstructionTraceWriter(path: fixture.file.path)
        defer { writer.close() }
        var tokens: [UInt64] = []
        for _ in 0..<2 {
            let first = try XCTUnwrap(
                DashboardInteractionDiagnostics.record("fixture.render.first.enter", writer: writer))
            XCTAssertNotNil(
                DashboardInteractionDiagnostics.record("fixture.render.first.returned", span: first, writer: writer))
            let second = try XCTUnwrap(
                DashboardInteractionDiagnostics.record("fixture.render.second.enter", writer: writer))
            XCTAssertNotNil(
                DashboardInteractionDiagnostics.record("fixture.render.second.returned", span: second, writer: writer))
            tokens.append(contentsOf: [first, second])
        }
        // Independent handle read while active: no flush, close, sleep or exit.
        let observed = try records(fixture.file)
        XCTAssertEqual(writer.status, .active)
        XCTAssertEqual(Set(tokens).count, 4)
        XCTAssertEqual(observed.compactMap { ($0["span"] as? NSNumber)?.uint64Value }, tokens)
        XCTAssertEqual(writer.bytesWritten, try Data(contentsOf: fixture.file).count)
    }

    func testInvalidAndNonemptySinksDoNotChangeCallerControlFlow() async throws {
        let fixture = try DashboardTraceFileFixture()
        defer { fixture.remove() }
        let original = Data("preserved evidence\n".utf8)
        try original.write(to: fixture.file)
        let missing = fixture.directory.appendingPathComponent("missing.jsonl")
        for path in ["relative-dashboard-trace.jsonl", missing.path, fixture.directory.path, fixture.file.path] {
            let writer = DashboardInteractionDiagnostics.configuredWriter(path: path)
            defer { writer?.close() }
            XCTAssertNil(writer)
            XCTAssertNil(DashboardInteractionDiagnostics.record("fixture.init.enter", writer: writer))
            // No diagnostic failure escapes or changes execution of this following statement.
            XCTAssertEqual(try Data(contentsOf: fixture.file), original)
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: missing.path))
    }

    func testCapOrWriteFailureDisablesMarkersWithoutFabricatingReturn() async throws {
        let capped = try DashboardTraceFileFixture()
        defer { capped.remove() }
        let capWriter = try RetainedConstructionTraceWriter(path: capped.file.path, byteLimit: 1_024)
        defer { capWriter.close() }
        for _ in 0..<128 {
            let span = DashboardInteractionDiagnostics.record("fixture.render.first.enter", writer: capWriter)
            DashboardInteractionDiagnostics.record("fixture.render.first.returned", span: span, writer: capWriter)
        }
        XCTAssertEqual(capWriter.status, .capReached)
        let cappedBytes = try Data(contentsOf: capped.file)
        XCTAssertEqual(try records(capped.file).last?["event"] as? String, "trace.capReached")
        XCTAssertNil(DashboardInteractionDiagnostics.record("fixture.init.returned", span: 1, writer: capWriter))
        XCTAssertEqual(try Data(contentsOf: capped.file), cappedBytes)

        let failed = try DashboardTraceFileFixture()
        defer { failed.remove() }
        let nativeFile = try FileHandle(forWritingTo: failed.file)
        defer { try? nativeFile.close() }
        let failedWriter = try RetainedConstructionTraceWriter(ownedFile: nativeFile, byteLimit: 2_048)
        defer { failedWriter.close() }
        let span = try XCTUnwrap(
            DashboardInteractionDiagnostics.record("fixture.components.enter", writer: failedWriter))
        let before = try Data(contentsOf: failed.file)
        // Existing sequential native-handle seam; no concurrent access or synthetic success.
        try nativeFile.close()
        XCTAssertNil(
            DashboardInteractionDiagnostics.record("fixture.components.returned", span: span, writer: failedWriter))
        XCTAssertEqual(failedWriter.status, .writeFailed)
        XCTAssertEqual(try Data(contentsOf: failed.file), before)
        XCTAssertFalse(try records(failed.file).contains { $0["event"] as? String == "fixture.components.returned" })
    }

    private func records(_ file: URL) throws -> [[String: Any]] {
        let data = try Data(contentsOf: file)
        XCTAssertEqual(data.last, 0x0A)
        return try data.split(separator: 0x0A).map {
            try XCTUnwrap(JSONSerialization.jsonObject(with: Data($0)) as? [String: Any])
        }
    }
}

private struct DashboardTraceFileFixture {
    let directory: URL
    let file: URL

    init() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "dashboard-writer-\(UUID().uuidString)")
        file = directory.appendingPathComponent("trace.jsonl")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        try Data().write(to: file, options: .withoutOverwriting)
    }

    func remove() {
        // This immutable directory was created here and is never supplied by an environment key.
        try? FileManager.default.removeItem(at: directory)
    }
}
