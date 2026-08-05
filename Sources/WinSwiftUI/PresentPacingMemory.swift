import Foundation

// MARK: - Present-pacing memory

/// Persists the present-pacing watchdog's verdict across sessions, so a
/// machine whose compositor blocks paced presents pathologically stops paying
/// the evidence bar at every launch.
///
/// The watchdog (`PresentPacingPolicy`) deliberately demands ~1.5 s of
/// consecutive blocked presents before it takes the pacing job away from the
/// display — the bar that protects a healthy machine from a trigger-happy
/// watchdog. On a machine that is broken *every* session, that bar is a
/// slideshow replayed at every launch: measured here as ~1.5 s at 4 fps
/// before the first smooth frame. The verdict is a property of the
/// adapter+display pair, not of the session, so it is keyed that way and
/// remembered.
///
/// The memory is advisory, never load-bearing: a remembered verdict starts
/// the session self-paced *with an immediate recovery probe*, so a display
/// that was fixed since last session gets the pacing job back within one
/// probe and the entry is dropped (`setRemembersSelfPacing(false)` removes
/// it). A machine that was always healthy never writes a file at all.
///
/// Lives in the host layer on purpose. `PresentPacingPolicy` stays a
/// renderer-neutral value type with no clock, no threads and no I/O; this
/// type owns the file, and the host owns when it is consulted.
@MainActor
final class PresentPacingMemoryStore {
    /// One remembered verdict. `updatedAt` is seconds since 1970, recorded so
    /// a support conversation can tell a decision made this morning from one
    /// made before a driver update; nothing ages entries out automatically —
    /// the immediate probe on adoption is what keeps a stale entry from
    /// costing more than one confirmation.
    struct Entry: Codable, Equatable {
        var requiresSelfPacing: Bool
        var updatedAt: Double
    }

    private let fileURL: URL
    private let now: () -> Double
    /// In-memory mirror of the file, loaded once. Every read after the first
    /// is a dictionary lookup, and writes only touch the disk when an entry
    /// actually changes — this is consulted from the frame loop's bookkeeping.
    private var cachedEntries: [String: Entry]?

    init(fileURL: URL, now: @escaping () -> Double = { Date().timeIntervalSince1970 }) {
        self.fileURL = fileURL
        self.now = now
    }

    /// The per-user store the production composition uses:
    /// `%LOCALAPPDATA%\swift-windowsui\present-pacing.json`. Registry-free and
    /// per-user by construction; falls back to the temporary directory when
    /// the environment is too strange to have a local app-data folder.
    static let standard = PresentPacingMemoryStore(fileURL: defaultFileURL())

    static func defaultFileURL() -> URL {
        let base: URL
        if let localAppData = ProcessInfo.processInfo.environment["LOCALAPPDATA"], !localAppData.isEmpty {
            base = URL(fileURLWithPath: localAppData)
        } else {
            base = FileManager.default.temporaryDirectory
        }
        return
            base
            .appendingPathComponent("swift-windowsui", isDirectory: true)
            .appendingPathComponent("present-pacing.json", isDirectory: false)
    }

    /// Whether a previous session decided this adapter+display pair needs
    /// self-pacing.
    func remembersSelfPacing(forKey key: String) -> Bool {
        entries()[key]?.requiresSelfPacing == true
    }

    /// Records the current verdict. `true` writes (or refreshes) the entry;
    /// `false` *removes* it, so healthy machines converge on no file rather
    /// than a file full of reassurances. No-ops — recording what is already
    /// recorded — never touch the disk.
    func setRemembersSelfPacing(_ remembered: Bool, forKey key: String) {
        var current = entries()
        if remembered {
            guard current[key]?.requiresSelfPacing != true else {
                return
            }
            current[key] = Entry(requiresSelfPacing: true, updatedAt: now())
        } else {
            guard current.removeValue(forKey: key) != nil else {
                return
            }
        }
        cachedEntries = current
        persist(current)
    }

    // MARK: - File plumbing

    private func entries() -> [String: Entry] {
        if let cachedEntries {
            return cachedEntries
        }

        let loaded = Self.load(from: fileURL)
        cachedEntries = loaded
        return loaded
    }

    /// A missing file is a machine that never needed the memory; a corrupt
    /// one is treated the same way — the cost of forgetting is one re-earned
    /// engagement, while the cost of trusting garbage is unbounded.
    private static func load(from fileURL: URL) -> [String: Entry] {
        guard let data = try? Data(contentsOf: fileURL) else {
            return [:]
        }
        return (try? JSONDecoder().decode([String: Entry].self, from: data)) ?? [:]
    }

    private func persist(_ entries: [String: Entry]) {
        do {
            if entries.isEmpty {
                if FileManager.default.fileExists(atPath: fileURL.path) {
                    try FileManager.default.removeItem(at: fileURL)
                }
                return
            }

            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(entries).write(to: fileURL, options: .atomic)
        } catch {
            // A store that cannot write costs the next launch its smooth
            // start, nothing more. Never worth failing a frame over.
        }
    }
}
