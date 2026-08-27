import Foundation

#if canImport(SwiftUI)
    import SwiftUI
#else
    import WinSwiftUI
#endif

/// Storage is injected so live applications can persist preferences while
/// snapshots and tests never read or overwrite a user's settings.
@MainActor
public struct DemoSettingsStore {
    public static let maximumDataSize = 65_536

    private let loadData: () throws -> Data?
    private let saveData: (Data) throws -> Void

    public init(load: @escaping () throws -> Data?, save: @escaping (Data) throws -> Void) {
        loadData = load
        saveData = save
    }

    func load() throws -> Data? {
        let data = try loadData()
        if let data, data.count > Self.maximumDataSize {
            throw DemoSettingsStoreError.oversizedData
        }
        return data
    }

    func save(_ data: Data) throws {
        guard data.count <= Self.maximumDataSize else {
            throw DemoSettingsStoreError.oversizedData
        }
        try saveData(data)
    }

    /// A separate store is created for every call. Sharing the returned value
    /// deliberately shares its saved data, which also supports restart tests.
    public static func inMemory(initialData: Data? = nil) -> Self {
        var data = initialData
        return Self(load: { data }, save: { data = $0 })
    }

    /// Files are replaced atomically only after encoding and validation succeed.
    /// Failed writes leave the model dirty and the previous file intact.
    public static func file(at url: URL) -> Self {
        Self(
            load: {
                let handle: FileHandle
                do {
                    handle = try FileHandle(forReadingFrom: url)
                } catch let error as CocoaError
                    where error.code == .fileReadNoSuchFile || error.code == .fileNoSuchFile
                {
                    return nil
                }
                defer { try? handle.close() }
                // A size check followed by Data(contentsOf:) can race a growing
                // file. Bound the read itself, including one overflow byte.
                return try handle.read(upToCount: Self.maximumDataSize + 1) ?? Data()
            },
            save: { data in
                try FileManager.default.createDirectory(
                    at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                try data.write(to: url, options: .atomic)
            }
        )
    }

    /// The executable opts into a real per-user store. A missing system folder
    /// is an explicit load/save failure, never a silent temporary-file fallback.
    public static var application: Self {
        guard let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        else {
            return Self(
                load: { throw DemoSettingsStoreError.unavailableApplicationSupport },
                save: { _ in throw DemoSettingsStoreError.unavailableApplicationSupport }
            )
        }
        return .file(at: directory.appendingPathComponent("SwiftWindowsUI/Demo/settings.json"))
    }
}

enum DemoSettingsStoreError: LocalizedError {
    case oversizedData
    case unsupportedVersion
    case invalidValues
    case unavailableApplicationSupport

    var errorDescription: String? {
        switch self {
        case .oversizedData:
            return "The settings file exceeds the 64 KiB limit."
        case .unsupportedVersion:
            return "The settings file uses an unsupported format version."
        case .invalidValues:
            return "The settings file contains invalid values."
        case .unavailableApplicationSupport:
            return "The system application support folder is unavailable."
        }
    }
}

/// The persisted schema contains application data only; it has no renderer or
/// platform types. Version changes require an explicit migration.
struct DemoSettingsRecord: Codable, Equatable {
    var version = 1
    var displayName: String
    var theme: String
    var itemsPerPage: Int
    var animationsEnabled: Bool
    var soundEffectsEnabled: Bool
    var shareUsageData: Bool
    var fontScale: Double
    var accent: Accent

    struct Accent: Codable, Equatable {
        var red: Float
        var green: Float
        var blue: Float
        var opacity: Float
    }

    func validate() throws {
        guard version == 1 else { throw DemoSettingsStoreError.unsupportedVersion }
        guard displayName.contains(where: { !$0.isWhitespace }), displayName.count <= 200,
            ["system", "light", "dark"].contains(theme), (1...100).contains(itemsPerPage),
            fontScale.isFinite, (0.8...1.4).contains(fontScale),
            // Preserve ordinary extended RGB colors without allowing hostile
            // persisted magnitudes to overflow downstream color arithmetic.
            accent.red.isFinite, (-16...16).contains(accent.red),
            accent.green.isFinite, (-16...16).contains(accent.green),
            accent.blue.isFinite, (-16...16).contains(accent.blue),
            accent.opacity.isFinite, (0...1).contains(accent.opacity)
        else {
            throw DemoSettingsStoreError.invalidValues
        }
    }
}
