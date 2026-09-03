import Foundation
import WinSwiftUI

struct WorkbenchPreferences: Codable, Equatable {
    var displayName = "Operator"
    var showSavedProfileDetails = true

    func validated() throws -> Self {
        let name = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name.count <= 64 else {
            throw WorkbenchError.message("Display name must contain 1 to 64 characters.")
        }
        return Self(displayName: name, showSavedProfileDetails: showSavedProfileDetails)
    }
}

enum WorkbenchError: Error, CustomStringConvertible {
    case message(String)

    var description: String {
        switch self {
        case .message(let message): return message
        }
    }
}

@MainActor
final class WorkbenchModel: ObservableObject {
    private static let maximumSettingsBytes = 65_536

    @Published var selectedPage = 0
    @Published var displayName = "Operator"
    @Published var showSavedProfileDetails = true
    @Published private(set) var savedPreferences = WorkbenchPreferences()
    @Published private(set) var parentRevision = 0
    @Published private(set) var status = "No saved settings yet."
    @Published private(set) var errorMessage: String?

    private let settingsURL: URL?
    private let write: (Data, URL) throws -> Void

    static var applicationSettingsURL: URL? {
        guard let directory = ProcessInfo.processInfo.environment["LOCALAPPDATA"],
            !directory.isEmpty
        else { return nil }
        return URL(fileURLWithPath: directory, isDirectory: true)
            .appendingPathComponent("SwiftWindowsUI.GPUWorkbench", isDirectory: true)
            .appendingPathComponent("settings.json")
    }

    init(
        settingsURL: URL?,
        write: @escaping (Data, URL) throws -> Void = { data, url in
            try data.write(to: url, options: .atomic)
        }
    ) {
        self.settingsURL = settingsURL
        self.write = write
        guard let settingsURL else {
            errorMessage = "LOCALAPPDATA is unavailable. Settings cannot be saved."
            return
        }
        if FileManager.default.fileExists(atPath: settingsURL.path) {
            reload()
        }
    }

    func rebuildParent() {
        parentRevision += 1
    }

    func save() {
        do {
            guard let settingsURL else {
                throw WorkbenchError.message("LOCALAPPDATA is unavailable. Settings cannot be saved.")
            }
            let preferences = try WorkbenchPreferences(
                displayName: displayName, showSavedProfileDetails: showSavedProfileDetails
            ).validated()
            // Never silently overwrite a corrupt file. Repair or move it and
            // retry; a failed save leaves both the on-disk bytes and draft alone.
            if FileManager.default.fileExists(atPath: settingsURL.path) {
                _ = try readPreferences(at: settingsURL)
            }
            try FileManager.default.createDirectory(
                at: settingsURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(preferences)
            try write(data, settingsURL)
            savedPreferences = preferences
            displayName = preferences.displayName
            status = "Settings saved."
            errorMessage = nil
        } catch {
            errorMessage = "Save failed; draft kept. \(error)"
        }
    }

    func reload() {
        do {
            guard let settingsURL else {
                throw WorkbenchError.message("LOCALAPPDATA is unavailable.")
            }
            let preferences = try readPreferences(at: settingsURL)
            savedPreferences = preferences
            displayName = preferences.displayName
            showSavedProfileDetails = preferences.showSavedProfileDetails
            status = "Saved settings loaded."
            errorMessage = nil
        } catch {
            errorMessage = "Load failed; current draft and file kept. \(error)"
        }
    }

    private func readPreferences(at url: URL) throws -> WorkbenchPreferences {
        do {
            let handle = try FileHandle(forReadingFrom: url)
            defer { try? handle.close() }
            let data = try handle.read(upToCount: Self.maximumSettingsBytes + 1) ?? Data()
            guard data.count <= Self.maximumSettingsBytes else {
                throw WorkbenchError.message("The settings file exceeds the 64 KiB limit.")
            }
            return try JSONDecoder().decode(WorkbenchPreferences.self, from: data).validated()
        } catch {
            throw WorkbenchError.message(
                "Cannot read \(url.path): \(error). Repair or move the file, then retry.")
        }
    }
}
