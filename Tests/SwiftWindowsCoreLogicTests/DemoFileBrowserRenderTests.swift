import Foundation
import SwiftWindowsCore
import XCTest

@testable import SwiftWindowsDemo
@testable import SwiftWindowsUI
@testable import WinSwiftUI

/// The same shared template, preparation, dimensions, and appearance as the
/// three retained gallery entries. No file URL, dialog, or test-only view state.
@MainActor
final class DemoFileBrowserRenderTests: XCTestCase {
    func testLoadedSamplePaintsEveryFileNameInTheFirstRetainedScene() async throws {
        try await assertFileRows(selectedID: "sample:welcome")
    }

    func testEmptySamplePaintsEveryFileNameInTheFirstRetainedScene() async throws {
        try await assertFileRows(selectedID: "sample:empty")
    }

    func testInvalidUTF8SamplePaintsEveryFileNameInTheFirstRetainedScene() async throws {
        try await assertFileRows(selectedID: "sample:invalid")
    }

    private func assertFileRows(
        selectedID: String, file: StaticString = #filePath, line: UInt = #line
    ) async throws {
        let model = DemoFileBrowserModel(
            service: DemoFilePreviewService { source in
                guard case .sample(let bytes) = source else {
                    throw DemoFilePreviewServiceError.invalidFileURL
                }
                return bytes
            })
        defer { model.close() }
        _ = model.select(id: selectedID)
        model.resume()
        await model.awaitCurrentPreviewRead()
        XCTAssertEqual(model.selectedID, selectedID, file: file, line: line)
        XCTAssertEqual(model.records, DemoFileBrowserRecord.samples, file: file, line: line)
        XCTAssertFalse(model.isReading, file: file, line: line)
        if selectedID == "sample:invalid" {
            XCTAssertEqual(
                model.preview, .failed(DemoFilePreviewServiceError.invalidUTF8.localizedDescription),
                file: file, line: line)
        } else if case .ready(let preview) = model.preview,
            case .sample(let bytes) = model.selectedRecord?.source
        {
            XCTAssertEqual(Data(preview.text.utf8), bytes, file: file, line: line)
        } else {
            XCTFail("The production sample read must finish before rendering", file: file, line: line)
        }

        let result = WinSwiftUIRendererSnapshotter.snapshot(
            of: DemoFileBrowserTemplate(model: model).frame(width: 800, height: 480),
            size: IntSize(width: 800, height: 480), displayScale: 1, colorScheme: .dark)
        let list = try RetainedListPaintAssertions.list(in: result.runtime.root, file: file, line: line)
        let adapter = try XCTUnwrap(list.retainedLazyListAdapter, file: file, line: line)
        XCTAssertGreaterThan(result.runtime.geometryReaderResolveCount, 0, file: file, line: line)
        XCTAssertTrue(adapter.ownsAttachment(list), file: file, line: line)
        XCTAssertTrue(
            try XCTUnwrap(list.retainedSubtreeBuildLease, file: file, line: line).canBuild,
            file: file, line: line)
        XCTAssertEqual(adapter.logicalRecordCount, model.records.count, file: file, line: line)
        try RetainedListPaintAssertions.labels(
            model.records.map(\.name), in: list, scene: result.scene, size: result.size, file: file, line: line)
    }
}
