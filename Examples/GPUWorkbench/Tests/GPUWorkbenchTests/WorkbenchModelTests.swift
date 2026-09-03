import Foundation
import XCTest

@testable import GPUWorkbench

@MainActor
final class WorkbenchModelTests: XCTestCase {
    func testSavedSettingsSurviveNewModel() async throws {
        try withSettingsURL { url in
            let model = WorkbenchModel(settingsURL: url)
            model.displayName = "  Ada  "
            model.showSavedProfileDetails = false
            model.save()
            XCTAssertNil(model.errorMessage)
            XCTAssertEqual(model.displayName, "Ada")
            let restarted = WorkbenchModel(settingsURL: url)
            XCTAssertEqual(restarted.displayName, "Ada")
            XCTAssertFalse(restarted.showSavedProfileDetails)
            XCTAssertEqual(restarted.savedPreferences, model.savedPreferences)
        }
    }

    func testInvalidDraftDoesNotReplaceSavedFile() async throws {
        try withSettingsURL { url in
            let model = WorkbenchModel(settingsURL: url)
            model.save()
            let original = try Data(contentsOf: url)
            model.displayName = "   "
            model.save()
            XCTAssertNotNil(model.errorMessage)
            XCTAssertEqual(model.displayName, "   ")
            XCTAssertEqual(try Data(contentsOf: url), original)
        }
    }

    func testCorruptReloadPreservesDraftAndCanRecoverAfterRepair() async throws {
        try withSettingsURL { url in
            let model = WorkbenchModel(settingsURL: url)
            model.save()
            let original = try Data(contentsOf: url)
            let corrupt = Data("not JSON".utf8)
            try corrupt.write(to: url)
            model.displayName = "Unsaved edit"
            model.showSavedProfileDetails = false
            model.reload()
            XCTAssertNotNil(model.errorMessage)
            XCTAssertEqual(model.displayName, "Unsaved edit")
            XCTAssertFalse(model.showSavedProfileDetails)
            XCTAssertEqual(try Data(contentsOf: url), corrupt)
            try original.write(to: url)
            model.reload()
            XCTAssertNil(model.errorMessage)
            XCTAssertEqual(model.displayName, "Operator")
            XCTAssertTrue(model.showSavedProfileDetails)
        }
    }

    func testSaveRefusesToOverwriteCorruptSettings() async throws {
        try withSettingsURL { url in
            let corrupt = Data("unreadable settings".utf8)
            try corrupt.write(to: url)
            let model = WorkbenchModel(settingsURL: url)
            XCTAssertNotNil(model.errorMessage)
            model.displayName = "Keep draft"
            model.save()
            XCTAssertNotNil(model.errorMessage)
            XCTAssertEqual(model.displayName, "Keep draft")
            XCTAssertEqual(try Data(contentsOf: url), corrupt)
        }
    }

    func testWriteFailurePreservesSavedFileAndDraftThenRetrySucceeds() async throws {
        try withSettingsURL { url in
            WorkbenchModel(settingsURL: url).save()
            let original = try Data(contentsOf: url)
            var failWrite = true
            let model = WorkbenchModel(settingsURL: url) { data, destination in
                if failWrite { throw WorkbenchError.message("Injected write denial") }
                try data.write(to: destination, options: .atomic)
            }
            model.displayName = "Grace"
            model.save()
            XCTAssertNotNil(model.errorMessage)
            XCTAssertEqual(model.displayName, "Grace")
            XCTAssertEqual(try Data(contentsOf: url), original)
            failWrite = false
            model.save()
            XCTAssertNil(model.errorMessage)
            XCTAssertEqual(WorkbenchModel(settingsURL: url).displayName, "Grace")
        }
    }

    func testMissingPerUserDirectoryDoesNotDiscardDraft() async throws {
        let model = WorkbenchModel(settingsURL: nil)
        model.displayName = "Unsaved"
        model.save()
        XCTAssertNotNil(model.errorMessage)
        XCTAssertEqual(model.displayName, "Unsaved")
    }

    private func withSettingsURL(_ body: (URL) throws -> Void) throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("GPUWorkbenchTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: directory) }
        try body(directory.appendingPathComponent("settings.json"))
    }
}
