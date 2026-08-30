import Foundation
@preconcurrency import XCTest

@testable import SwiftWindowsDemo

/// Semantic preparation only: these cases use built-in bytes and the production
/// decoder, without rendering, file I/O, dialogs, or sleep/yield polling.
@MainActor
final class DemoFileBrowserGalleryPreparationTests: XCTestCase {
    func testAwaitWithoutAnActiveReadDoesNotResumeTheModel() async {
        let gate = DemoFilePreviewGate()
        let model = DemoFileBrowserModel(service: gate.service)
        defer {
            model.close()
            gate.close()
        }
        let initial = model.snapshot

        await model.awaitCurrentPreviewRead()

        XCTAssertEqual(model.snapshot, initial)
        XCTAssertEqual(model.preview, .idle)
        XCTAssertFalse(model.isActive)
        XCTAssertFalse(model.isReading)
        XCTAssertTrue(gate.snapshot.starts.isEmpty)
    }

    func testLoadedSampleIsReadyAfterAwaitingTheProductionRead() async throws {
        let model = await prepareSample(id: "sample:welcome")
        defer { model.close() }

        XCTAssertEqual(model.selectedID, "sample:welcome")
        XCTAssertEqual(model.records, DemoFileBrowserRecord.samples)
        XCTAssertTrue(model.isActive)
        XCTAssertFalse(model.isReading)
        XCTAssertFalse(model.isImporterPresented)
        guard case .ready(let preview) = model.preview,
            case .sample(let bytes) = model.selectedRecord?.source
        else { return XCTFail("The real sample read must publish a loaded preview.") }
        XCTAssertGreaterThan(preview.byteCount, 0)
        XCTAssertEqual(preview.byteCount, bytes.count)
        XCTAssertEqual(Data(preview.text.utf8), bytes)
        XCTAssertTrue(preview.text.hasPrefix("Local file preview\n"))
    }

    func testEmptySampleRemainsReadyWithZeroBytes() async {
        let model = await prepareSample(id: "sample:empty")
        defer { model.close() }

        XCTAssertEqual(model.selectedID, "sample:empty")
        XCTAssertEqual(model.records, DemoFileBrowserRecord.samples)
        XCTAssertEqual(model.preview, .ready(DemoFilePreview(text: "", byteCount: 0)))
        XCTAssertTrue(model.isActive)
        XCTAssertFalse(model.isReading)
        XCTAssertFalse(model.isImporterPresented)
    }

    func testInvalidSamplePublishesTheProductionDecoderFailure() async {
        let model = await prepareSample(id: "sample:invalid")
        defer { model.close() }

        XCTAssertEqual(model.selectedID, "sample:invalid")
        XCTAssertEqual(model.records, DemoFileBrowserRecord.samples)
        XCTAssertEqual(model.preview, .failed(DemoFilePreviewServiceError.invalidUTF8.localizedDescription))
        XCTAssertTrue(model.isActive)
        XCTAssertFalse(model.isReading)
        XCTAssertFalse(model.isImporterPresented)
    }

    private func prepareSample(id: String) async -> DemoFileBrowserModel {
        let model = DemoFileBrowserModel(
            service: DemoFilePreviewService { source in
                guard case .sample(let bytes) = source else {
                    throw DemoFilePreviewServiceError.invalidFileURL
                }
                return bytes
            })
        _ = model.select(id: id)
        model.resume()
        await model.awaitCurrentPreviewRead()
        return model
    }
}
