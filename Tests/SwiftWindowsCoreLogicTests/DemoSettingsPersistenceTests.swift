import Foundation
import SwiftWindowsCore
import XCTest

@testable import SwiftWindowsDemo
@testable import SwiftWindowsUI
@testable import WinSwiftUI

@MainActor
final class DemoSettingsPersistenceTests: XCTestCase {
    private enum StoreFailure: Error {
        case unavailable
    }

    private func temporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SwiftWindowsUI-SettingsTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func validRecord() throws -> DemoSettingsRecord {
        let store = DemoSettingsStore.inMemory()
        DemoDashboardModel(settingsStore: store).saveSettings()
        return try JSONDecoder().decode(DemoSettingsRecord.self, from: XCTUnwrap(store.load()))
    }

    func testFileStoreRestoresEveryPreferenceAfterRestart() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("nested/settings.json")
        let store = DemoSettingsStore.file(at: url)
        let model = DemoDashboardModel(settingsStore: store)
        XCTAssertNil(model.settingsPersistenceError, "A first launch without a file is not a load failure")

        model.displayName = "Renée 日本語"
        model.theme = .dark
        model.itemsPerPage = 25
        model.animationsEnabled = false
        model.soundEffectsEnabled = true
        model.shareUsageData = false
        model.fontScale = 1.3
        model.accentColor = Color(Color.Resolved(red: 0.2, green: 0.4, blue: 0.6, opacity: 0.8))
        model.saveSettings()

        XCTAssertNil(model.settingsPersistenceError)
        XCTAssertTrue(model.hasSavedSettings)
        XCTAssertFalse(model.hasUnsavedSettings)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))

        let restored = DemoDashboardModel(settingsStore: .file(at: url))
        XCTAssertEqual(restored.displayName, model.displayName)
        XCTAssertEqual(restored.theme, model.theme)
        XCTAssertEqual(restored.itemsPerPage, model.itemsPerPage)
        XCTAssertEqual(restored.animationsEnabled, model.animationsEnabled)
        XCTAssertEqual(restored.soundEffectsEnabled, model.soundEffectsEnabled)
        XCTAssertEqual(restored.shareUsageData, model.shareUsageData)
        XCTAssertEqual(restored.fontScale, model.fontScale)
        XCTAssertEqual(restored.accentColor, model.accentColor)
        XCTAssertTrue(restored.hasSavedSettings)
        XCTAssertFalse(restored.hasUnsavedSettings)
        XCTAssertEqual(restored.settingsStatusMessage, "All changes saved")
    }

    func testUnsavedEditsAndDefaultSnapshotModelsNeverChangeStoredPreferences() async throws {
        let store = DemoSettingsStore.inMemory()
        let model = DemoDashboardModel(settingsStore: store)
        model.displayName = "Saved profile"
        model.saveSettings()
        let savedData = try XCTUnwrap(store.load())
        model.displayName = "Unsaved profile"

        XCTAssertEqual(try store.load(), savedData)
        XCTAssertEqual(DemoDashboardModel(settingsStore: store).displayName, "Saved profile")
        XCTAssertEqual(DemoDashboardModel().displayName, "Operator")
        XCTAssertFalse(DemoDashboardModel().hasSavedSettings)
        XCTAssertTrue(model.hasUnsavedSettings)
    }

    func testFailedWritePreservesSavedFileAndDirtyStateThenRetrySucceeds() async throws {
        var persisted: Data?
        var shouldFail = false
        let store = DemoSettingsStore(
            load: { persisted },
            save: { data in
                if shouldFail { throw StoreFailure.unavailable }
                persisted = data
            }
        )
        let model = DemoDashboardModel(settingsStore: store)
        model.displayName = "Previous"
        model.saveSettings()
        let oldData = try XCTUnwrap(persisted)
        shouldFail = true
        model.displayName = "Next"
        model.saveSettings()

        XCTAssertEqual(persisted, oldData)
        XCTAssertTrue(model.hasUnsavedSettings)
        XCTAssertTrue(model.hasSavedSettings, "An earlier successful save remains recorded")
        XCTAssertEqual(model.lastAction, "Settings save failed")
        XCTAssertTrue(model.settingsStatusMessage.contains("Could not save settings"))
        XCTAssertEqual(DemoDashboardModel(settingsStore: store).displayName, "Previous")

        shouldFail = false
        model.saveSettings()
        XCTAssertNil(model.settingsPersistenceError)
        XCTAssertFalse(model.hasUnsavedSettings)
        XCTAssertEqual(DemoDashboardModel(settingsStore: store).displayName, "Next")
    }

    func testFirstWriteFailureNeverReportsSaved() async {
        let store = DemoSettingsStore(load: { nil }, save: { _ in throw StoreFailure.unavailable })
        let model = DemoDashboardModel(settingsStore: store)
        model.displayName = "Unsaved"
        model.saveSettings()
        XCTAssertFalse(model.hasSavedSettings)
        XCTAssertTrue(model.hasUnsavedSettings)
        XCTAssertNotNil(model.settingsPersistenceError)
    }

    func testMalformedOrUnavailableDataShowsDefaultsWithoutOverwritingSource() async throws {
        let malformed = Data("{not settings".utf8)
        let store = DemoSettingsStore.inMemory(initialData: malformed)
        let model = DemoDashboardModel(settingsStore: store)
        XCTAssertEqual(model.displayName, "Operator")
        XCTAssertFalse(model.hasSavedSettings)
        XCTAssertTrue(model.settingsStatusMessage.contains("Could not load settings"))
        XCTAssertEqual(try store.load(), malformed)

        model.resetSettings()
        XCTAssertTrue(model.settingsStatusMessage.contains("Could not load settings"))
        XCTAssertEqual(try store.load(), malformed, "Reset is an edit, not a successful disk operation")

        model.saveSettings()
        XCTAssertNil(model.settingsPersistenceError)
        XCTAssertTrue(model.hasSavedSettings)
        XCTAssertNoThrow(try JSONDecoder().decode(DemoSettingsRecord.self, from: XCTUnwrap(store.load())))

        let unavailable = DemoDashboardModel(
            settingsStore: .init(load: { throw StoreFailure.unavailable }, save: { _ in }))
        XCTAssertTrue(unavailable.settingsStatusMessage.contains("Could not load settings"))
        XCTAssertFalse(unavailable.hasSavedSettings)
    }

    func testUnsupportedSchemaAndInvalidValuesAreRejectedBeforeApplyingAnyField() async throws {
        let base = try validRecord()
        var variants: [DemoSettingsRecord] = []
        var record = base
        record.version = 2
        variants.append(record)
        record = base
        record.displayName = "   "
        variants.append(record)
        record = base
        record.theme = "unknown"
        variants.append(record)
        record = base
        record.itemsPerPage = 0
        variants.append(record)
        record = base
        record.itemsPerPage = Int.max
        variants.append(record)
        record = base
        record.fontScale = 100
        variants.append(record)
        record = base
        record.accent.opacity = -1
        variants.append(record)
        record = base
        record.accent.red = .greatestFiniteMagnitude
        variants.append(record)

        for record in variants {
            let data = try JSONEncoder().encode(record)
            let store = DemoSettingsStore.inMemory(initialData: data)
            let model = DemoDashboardModel(settingsStore: store)
            XCTAssertNotNil(model.settingsPersistenceError)
            XCTAssertFalse(model.hasSavedSettings)
            XCTAssertEqual(model.displayName, "Operator")
            XCTAssertEqual(model.itemsPerPage, 10)
            XCTAssertEqual(model.theme, .system)
            XCTAssertEqual(model.fontScale, 1)
            XCTAssertEqual(try store.load(), data)
        }
    }

    func testOversizedFilesAndInjectedStoresAreBounded() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("settings.json")
        let oversized = Data(repeating: 0x20, count: DemoSettingsStore.maximumDataSize + 1)
        try oversized.write(to: url)
        XCTAssertThrowsError(try DemoSettingsStore.file(at: url).load())
        XCTAssertThrowsError(try DemoSettingsStore.inMemory(initialData: oversized).load())
        var didSave = false
        let store = DemoSettingsStore(load: { nil }, save: { _ in didSave = true })
        XCTAssertThrowsError(try store.save(oversized))
        XCTAssertFalse(didSave)
        XCTAssertNotNil(DemoDashboardModel(settingsStore: .file(at: url)).settingsPersistenceError)
    }

    func testInvalidFormDoesNotWriteAndReportsActionableValidation() async throws {
        var writes = 0
        let store = DemoSettingsStore(load: { nil }, save: { _ in writes += 1 })
        let model = DemoDashboardModel(settingsStore: store)
        model.itemsPerPage = 0
        model.saveSettings()
        XCTAssertEqual(model.settingsStatusMessage, "Items per page must be between 1 and 100")
        model.itemsPerPage = 10
        model.fontScale = .nan
        model.saveSettings()
        XCTAssertEqual(model.settingsStatusMessage, "Font scale must be between 80% and 140%")
        model.fontScale = 1
        model.displayName = String(repeating: "a", count: 201)
        model.saveSettings()
        XCTAssertEqual(model.settingsStatusMessage, "Display name must be at most 200 characters")
        XCTAssertEqual(writes, 0)
        XCTAssertFalse(model.hasSavedSettings)
    }

    func testResetIsAnUnsavedEditUntilExplicitSave() async throws {
        let store = DemoSettingsStore.inMemory()
        let model = DemoDashboardModel(settingsStore: store)
        model.displayName = "Custom"
        model.theme = .light
        model.saveSettings()
        model.resetSettings()
        XCTAssertTrue(model.hasUnsavedSettings)
        XCTAssertEqual(DemoDashboardModel(settingsStore: store).displayName, "Custom")
        model.saveSettings()
        let restored = DemoDashboardModel(settingsStore: store)
        XCTAssertEqual(restored.displayName, "Operator")
        XCTAssertEqual(restored.theme, .system)
        XCTAssertFalse(restored.hasUnsavedSettings)
        XCTAssertTrue(restored.hasSavedSettings)
    }

    func testAtomicReplacementAndRealWriteFailure() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("settings.json")
        let store = DemoSettingsStore.file(at: url)
        try store.save(Data("old".utf8))
        try store.save(Data("new".utf8))
        XCTAssertEqual(try store.load(), Data("new".utf8))

        // A file used as the parent is a deterministic failure on both Windows
        // and macOS; it does not depend on privilege-sensitive chmod behavior.
        let failedStore = DemoSettingsStore.file(at: url.appendingPathComponent("settings.json"))
        XCTAssertThrowsError(try failedStore.save(Data("cannot write".utf8)))
        XCTAssertEqual(try store.load(), Data("new".utf8))
    }

    func testKeyboardSavePersistsThroughPublicTemplateAndFailureIsVisible() async throws {
        let store = DemoSettingsStore.inMemory()
        let model = DemoDashboardModel(settingsStore: store)
        model.selectedScreen = .settings
        model.displayName = "Keyboard save"
        let snapshot = WinSwiftUIRendererSnapshotter.snapshot(
            of: DemoRootView(model: model), size: IntSize(width: 800, height: 600), colorScheme: .dark)
        snapshot.runtime.keyDown(KeyboardEvent(keyCode: 0x53, modifiers: [.control]))
        XCTAssertEqual(DemoDashboardModel(settingsStore: store).displayName, "Keyboard save")

        let failing = DemoDashboardModel(
            settingsStore: .init(load: { nil }, save: { _ in throw StoreFailure.unavailable }))
        failing.selectedScreen = .settings
        failing.displayName = "Unwritten"
        failing.saveSettings()
        let failureSnapshot = WinSwiftUIRendererSnapshotter.snapshot(
            of: DemoRootView(model: failing), size: IntSize(width: 800, height: 600), colorScheme: .dark)
        var nodes = [failureSnapshot.runtime.root]
        var foundFailure = false
        var foundSampleDisclosure = false
        while let node = nodes.popLast() {
            foundFailure = foundFailure || node.text?.contains("Could not save settings") == true
            foundSampleDisclosure =
                foundSampleDisclosure || node.text == "Sample preference; this demo sends no telemetry"
            nodes.append(contentsOf: node.children)
        }
        XCTAssertTrue(foundFailure, "The error must be in the rendered, accessible view tree")
        XCTAssertTrue(foundSampleDisclosure, "Saved sample flags must not claim a working telemetry integration")
        XCTAssertTrue(failing.hasUnsavedSettings)
    }

    func testSettingsWindowShortcutUsesWindowsCommaKeyAndInjectedSceneAction() async {
        var openedSettings = 0
        let model = DemoDashboardModel()
        let view = DemoRootView(model: model)
            .environment(\.openSettings, OpenSettingsAction { openedSettings += 1 })
        let snapshot = WinSwiftUIRendererSnapshotter.snapshot(
            of: view, size: IntSize(width: 800, height: 600), colorScheme: .dark)
        snapshot.runtime.keyDown(KeyboardEvent(keyCode: 0xBC, modifiers: [.control]))
        XCTAssertEqual(openedSettings, 1)
        snapshot.runtime.keyDown(KeyboardEvent(keyCode: 0x2C, modifiers: [.control]))
        XCTAssertEqual(openedSettings, 1, "The Unicode value of comma is the unrelated Print Screen virtual key")
        XCTAssertEqual(KeyEquivalent(unicodeScalarLiteral: ",").retainedKeyCode, 0xBC)
        XCTAssertEqual(KeyEquivalent(".").retainedKeyCode, 0xBE)
    }

    func testIndependentSettingsTemplateUsesSameModelAndValidation() async {
        let model = DemoDashboardModel()
        model.displayName = " "
        let snapshot = WinSwiftUIRendererSnapshotter.snapshot(
            of: DemoSettingsTemplate(model: model), size: IntSize(width: 640, height: 480), colorScheme: .dark)
        var nodes = [snapshot.runtime.root]
        var foundValidation = false
        while let node = nodes.popLast() {
            foundValidation = foundValidation || node.text == "Enter a display name before saving"
            nodes.append(contentsOf: node.children)
        }
        XCTAssertTrue(foundValidation)
    }
}
