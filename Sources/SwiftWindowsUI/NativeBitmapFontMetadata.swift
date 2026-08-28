import CDirect2DInterop
import Foundation
import WinSDK

/// States describe observations, not font-profile or pixel qualification.
public enum NativeBitmapFontMetadataStatus: String, Codable, Equatable, Sendable {
    case observed
    case partial
    case unavailable
    case failed
    case limitExceeded = "limit-exceeded"
    case invalidValue = "invalid-value"
    case notInSystemCollection = "not-in-system-collection"
    case nonlocalOrCustom = "nonlocal-or-custom"
    case notApproved = "not-approved"
    case notImplemented = "not-implemented"
}

public enum NativeBitmapFontFileScope: String, Codable, Equatable, Sendable {
    case systemFonts = "system-fonts"
    case userFonts = "user-fonts"
}

/// An observed DirectWrite local-file reference, with its private path removed.
/// A later collector must validate its own opened file before reading any bytes.
public struct NativeBitmapFontFileReference: Codable, Equatable, Sendable {
    public let status: NativeBitmapFontMetadataStatus
    public let scope: NativeBitmapFontFileScope?
    public let basename: String?

    init(
        status: NativeBitmapFontMetadataStatus,
        scope: NativeBitmapFontFileScope? = nil,
        basename: String? = nil
    ) {
        self.status = status
        self.scope = scope
        self.basename = basename
    }
}

public struct NativeBitmapFontAxisValue: Codable, Equatable, Sendable {
    public let tag: UInt32
    public let value: Float
}

/// Bounded physical-face metadata from a retained bitmap callback face.
/// No pointer, text, glyph, cache identifier, or absolute path is a value field.
public struct NativeBitmapFontFaceMetadata: Codable, Equatable, Sendable {
    public let status: NativeBitmapFontMetadataStatus
    public let familyName: String?
    public let faceName: String?
    public let namesStatus: NativeBitmapFontMetadataStatus
    public let faceIndex: UInt32?
    public let simulations: UInt32?
    public let files: [NativeBitmapFontFileReference]
    public let filesStatus: NativeBitmapFontMetadataStatus
    public let axes: [NativeBitmapFontAxisValue]?
    public let axesStatus: NativeBitmapFontMetadataStatus

    init(
        status: NativeBitmapFontMetadataStatus,
        familyName: String? = nil,
        faceName: String? = nil,
        namesStatus: NativeBitmapFontMetadataStatus = .unavailable,
        faceIndex: UInt32? = nil,
        simulations: UInt32? = nil,
        files: [NativeBitmapFontFileReference] = [],
        filesStatus: NativeBitmapFontMetadataStatus = .unavailable,
        axes: [NativeBitmapFontAxisValue]? = nil,
        axesStatus: NativeBitmapFontMetadataStatus = .notImplemented
    ) {
        self.status = status
        self.familyName = familyName
        self.faceName = faceName
        self.namesStatus = namesStatus
        self.faceIndex = faceIndex
        self.simulations = simulations
        self.files = files
        self.filesStatus = filesStatus
        self.axes = axes
        self.axesStatus = axesStatus
    }
}

/// Private roots used only to redact an observed loader path. These strings
/// are never serialized and do not authorize a later collector's file reads.
struct NativeBitmapFontDirectory {
    var scope: NativeBitmapFontFileScope
    var path: String
}

@MainActor
enum NativeBitmapFontMetadataResolver {
    static let maximumFiles = 8
    static let maximumNameUnits = 512
    static let maximumPathUnits = 1_024
    static let maximumReferenceKeyBytes: UInt32 = 65_536
    static let maximumAxes = 32

    /// Called only by an explicitly enabled attribution session, after Draw.
    /// The caller owns the face handle; this function never consumes it.
    static func resolve(_ face: NativeFontFaceHandle) -> NativeBitmapFontFaceMetadata {
        let directories = observedDirectories()
        let loader = Win32TextLibraryLoader()
        guard let module = loader.loadLibrary(named: "dwrite.dll") else {
            return resolve(face, systemCollection: nil, approvedDirectories: directories)
        }
        defer { loader.unloadLibrary(module) }

        var iid = iidIDWriteFactory
        let factoryResult = withUnsafePointer(to: &iid) {
            loader.createDWriteFactory(from: module, iid: $0)
        }
        let factoryRaw = factoryResult?.1
        defer { releaseMetadataCOM(factoryRaw) }
        guard let factoryResult, isSuccess(factoryResult.0), let factoryRaw else {
            return resolve(face, systemCollection: nil, approvedDirectories: directories)
        }
        let factory = factoryRaw.assumingMemoryBound(to: IDWriteFactory.self)
        guard let vtable = factory.pointee.lpVtbl else {
            return resolve(face, systemCollection: nil, approvedDirectories: directories)
        }
        var collectionRaw: UnsafeMutableRawPointer?
        let hr = vtable.pointee.GetSystemFontCollection(factoryRaw, &collectionRaw, WindowsBool(false))
        defer { releaseMetadataCOM(collectionRaw) }
        return resolve(
            face, systemCollection: isSuccess(hr) ? collectionRaw : nil,
            approvedDirectories: directories)
    }

    /// Borrowed collection and injected roots keep fake-COM tests independent
    /// of installed fonts, filesystem access, and production renderer state.
    static func resolve(
        _ face: NativeFontFaceHandle,
        systemCollection: UnsafeMutableRawPointer?,
        approvedDirectories: [NativeBitmapFontDirectory]
    ) -> NativeBitmapFontFaceMetadata {
        withExtendedLifetime(face) {
            let raw = face.rawPointer
            let fontFace = raw.assumingMemoryBound(to: IDWriteFontFace.self)
            guard let vtable = fontFace.pointee.lpVtbl else {
                return NativeBitmapFontFaceMetadata(status: .invalidValue)
            }
            let faceIndex = vtable.pointee.GetIndex(raw)
            let simulations = vtable.pointee.GetSimulations(raw)
            let fileResult = fileReferences(
                raw, vtable: vtable.pointee, approvedDirectories: approvedDirectories)
            let nameResult = names(raw, systemCollection: systemCollection)
            // Axes are intentionally unresolved. An observed zero-axis set is not
            // interchangeable with a missing IDWriteFontFace5 implementation.
            return NativeBitmapFontFaceMetadata(
                status: .partial,
                familyName: nameResult.family, faceName: nameResult.face,
                namesStatus: nameResult.status, faceIndex: faceIndex, simulations: simulations,
                files: fileResult.files, filesStatus: fileResult.status,
                axes: nil, axesStatus: .notImplemented)
        }
    }

    private static func fileReferences(
        _ face: UnsafeMutableRawPointer,
        vtable: IDWriteFontFaceVtbl,
        approvedDirectories: [NativeBitmapFontDirectory]
    ) -> (files: [NativeBitmapFontFileReference], status: NativeBitmapFontMetadataStatus) {
        var count: UINT32 = 0
        guard isSuccess(vtable.GetFiles(face, &count, nil)) else { return ([], .failed) }
        guard count > 0 else { return ([], .invalidValue) }
        guard count <= UInt32(maximumFiles) else { return ([], .limitExceeded) }
        let capacity = count
        var files = [UnsafeMutableRawPointer?](repeating: nil, count: Int(capacity))
        // Every returned pointer owns a reference, including duplicates. Keep
        // the allocation's original bounds even if a failed call changes count.
        defer {
            for file in files { releaseMetadataCOM(file) }
        }
        let hr = files.withUnsafeMutableBufferPointer { vtable.GetFiles(face, &count, $0.baseAddress) }
        guard isSuccess(hr) else { return ([], .failed) }
        guard count == capacity, files.allSatisfy({ $0 != nil }) else { return ([], .invalidValue) }
        let records = files.compactMap { raw in
            raw.map { fileReference($0, approvedDirectories: approvedDirectories) }
        }
        return (records, records.allSatisfy { $0.status == .observed } ? .observed : .partial)
    }

    private static func fileReference(
        _ raw: UnsafeMutableRawPointer,
        approvedDirectories: [NativeBitmapFontDirectory]
    ) -> NativeBitmapFontFileReference {
        let file = raw.assumingMemoryBound(to: IDWriteFontFile.self)
        guard let vtable = file.pointee.lpVtbl else { return .init(status: .invalidValue) }
        var key: UnsafeRawPointer?
        var keySize: UINT32 = 0
        guard isSuccess(vtable.pointee.GetReferenceKey(raw, &key, &keySize)) else {
            return .init(status: .failed)
        }
        guard let key, keySize > 0 else { return .init(status: .invalidValue) }
        guard keySize <= maximumReferenceKeyBytes else { return .init(status: .limitExceeded) }
        var loaderRaw: UnsafeMutableRawPointer?
        let loaderHR = vtable.pointee.GetLoader(raw, &loaderRaw)
        defer { releaseMetadataCOM(loaderRaw) }
        guard isSuccess(loaderHR) else { return .init(status: .failed) }
        guard let loaderRaw else { return .init(status: .invalidValue) }
        let loader = loaderRaw.assumingMemoryBound(to: IDWriteFontFileLoader.self)
        guard let loaderVtable = loader.pointee.lpVtbl else { return .init(status: .invalidValue) }
        var localRaw: UnsafeMutableRawPointer?
        var iid = iidIDWriteLocalFontFileLoader
        let localHR = withUnsafePointer(to: &iid) {
            loaderVtable.pointee.QueryInterface(loaderRaw, $0, &localRaw)
        }
        defer { releaseMetadataCOM(localRaw) }
        guard isSuccess(localHR) else {
            return .init(status: localHR == HRESULT(bitPattern: 0x8000_4002) ? .nonlocalOrCustom : .failed)
        }
        guard let localRaw else { return .init(status: .invalidValue) }
        let local = localRaw.assumingMemoryBound(to: IDWriteLocalFontFileLoader.self)
        guard let localVtable = local.pointee.lpVtbl else { return .init(status: .invalidValue) }
        var length: UINT32 = 0
        guard isSuccess(localVtable.pointee.GetFilePathLengthFromKey(localRaw, key, keySize, &length)) else {
            return .init(status: .failed)
        }
        guard length > 0 else { return .init(status: .invalidValue) }
        guard length <= UInt32(maximumPathUnits) else { return .init(status: .limitExceeded) }
        var units = [WCHAR](repeating: 0xFFFF, count: Int(length) + 1)
        let hr = units.withUnsafeMutableBufferPointer {
            localVtable.pointee.GetFilePathFromKey(localRaw, key, keySize, $0.baseAddress, length + 1)
        }
        guard isSuccess(hr) else { return .init(status: .failed) }
        guard units.last == 0, !units.dropLast().contains(0),
            let path = String(validating: units.dropLast(), as: UTF16.self)
        else { return .init(status: .invalidValue) }
        return approvedReference(path: path, approvedDirectories: approvedDirectories)
    }

    /// Redaction only: admit a direct child of an OS-supplied root. Aliases are
    /// not normalized into an approval. The collector independently validates
    /// the final path and identity of the same handle it uses for hashing.
    static func approvedReference(
        path: String, approvedDirectories: [NativeBitmapFontDirectory]
    ) -> NativeBitmapFontFileReference {
        guard path.utf16.count <= maximumPathUnits else { return .init(status: .limitExceeded) }
        guard let components = directDrivePathComponents(path), let basename = components.last,
            safeBasename(basename)
        else { return .init(status: .notApproved) }
        guard !approvedDirectories.isEmpty else { return .init(status: .unavailable) }
        let parent = components.dropLast().joined(separator: "\\")
        for directory in approvedDirectories.prefix(2) {
            guard let root = directDrivePathComponents(directory.path) else { continue }
            if equalDirectoryPath(parent, root.joined(separator: "\\")) {
                return .init(status: .observed, scope: directory.scope, basename: basename)
            }
        }
        return .init(status: .notApproved)
    }

    private static func equalDirectoryPath(_ left: String, _ right: String) -> Bool {
        // Swift String equality folds canonical Unicode equivalents; Windows
        // path comparison must not approve a different UTF-16 directory name.
        let leftUnits = Array(left.utf16)
        let rightUnits = Array(right.utf16)
        return leftUnits.withUnsafeBufferPointer { leftBuffer in
            rightUnits.withUnsafeBufferPointer { rightBuffer in
                CompareStringOrdinal(
                    leftBuffer.baseAddress, Int32(leftBuffer.count),
                    rightBuffer.baseAddress, Int32(rightBuffer.count), true) == 2
            }
        }
    }

    private static func directDrivePathComponents(_ path: String) -> [String]? {
        guard path.utf16.count <= maximumPathUnits else { return nil }
        let units = Array(path.utf16)
        guard units.count >= 4, units.count <= maximumPathUnits,
            (65...90).contains(units[0]) || (97...122).contains(units[0]),
            units[1] == 58, units[2] == 92,
            !units.contains(where: { $0 < 32 || $0 == 127 || $0 == 47 })
        else { return nil }
        let parts = path.split(separator: "\\", omittingEmptySubsequences: false).map(String.init)
        guard parts.count >= 2,
            parts.dropFirst().allSatisfy({
                !$0.isEmpty && $0 != "." && $0 != ".."
                    && !$0.hasSuffix(".") && !$0.hasSuffix(" ")
                    && !$0.contains(where: { ":*?\"<>|~".contains($0) })
            })
        else { return nil }
        return parts
    }

    private static func safeBasename(_ value: String) -> Bool {
        guard !value.isEmpty, value.utf16.count <= 255, !value.contains(".."),
            !value.hasSuffix("."), !value.hasSuffix(" "),
            value.unicodeScalars.allSatisfy({ scalar in
                scalar.value >= 32 && scalar.value != 127
                    && !CharacterSet.controlCharacters.contains(scalar)
                    && !"\\/:*?\"<>|~".unicodeScalars.contains(scalar)
            }),
            let separator = value.lastIndex(of: ".")
        else { return false }
        let ext = value[value.index(after: separator)...].lowercased()
        guard ["ttf", "otf", "ttc"].contains(ext) else { return false }
        let stem = value[..<separator].split(separator: ".", omittingEmptySubsequences: false).first ?? ""
        guard !stem.hasSuffix(" ") else { return false }
        let upper = stem.uppercased()
        guard !["CON", "PRN", "AUX", "NUL", "CLOCK$", "CONIN$", "CONOUT$"].contains(upper) else { return false }
        if upper.count == 4,
            upper.hasPrefix("COM") || upper.hasPrefix("LPT"),
            let last = upper.last, "123456789¹²³".contains(last)
        {
            return false
        }
        return !stem.isEmpty
    }

    private static func names(
        _ face: UnsafeMutableRawPointer, systemCollection: UnsafeMutableRawPointer?
    ) -> (family: String?, face: String?, status: NativeBitmapFontMetadataStatus) {
        guard let systemCollection else { return (nil, nil, .unavailable) }
        let collection = systemCollection.assumingMemoryBound(to: IDWriteFontCollection.self)
        guard let vtable = collection.pointee.lpVtbl else { return (nil, nil, .invalidValue) }
        var fontRaw: UnsafeMutableRawPointer?
        let hr = vtable.pointee.GetFontFromFontFace(systemCollection, face, &fontRaw)
        defer { releaseMetadataCOM(fontRaw) }
        guard isSuccess(hr) else {
            // DWRITE_E_NOFONT: the observed physical face is not in this
            // collection. Other COM failures are not a membership verdict.
            return (nil, nil, hr == HRESULT(bitPattern: 0x8898_5002) ? .notInSystemCollection : .failed)
        }
        guard let fontRaw else { return (nil, nil, .invalidValue) }
        let font = fontRaw.assumingMemoryBound(to: IDWriteFont.self)
        guard let fontVtable = font.pointee.lpVtbl else { return (nil, nil, .invalidValue) }
        var familyRaw: UnsafeMutableRawPointer?
        let familyHR = fontVtable.pointee.GetFontFamily(fontRaw, &familyRaw)
        defer { releaseMetadataCOM(familyRaw) }
        let familyResult: (String?, NativeBitmapFontMetadataStatus)
        if isSuccess(familyHR), let familyRaw {
            let family = familyRaw.assumingMemoryBound(to: IDWriteFontFamily.self)
            if let familyVtable = family.pointee.lpVtbl {
                familyResult = localizedName(owner: familyRaw, getStrings: familyVtable.pointee.GetFamilyNames)
            } else {
                familyResult = (nil, .invalidValue)
            }
        } else {
            familyResult = (nil, isSuccess(familyHR) ? .invalidValue : .failed)
        }
        let faceResult = localizedName(owner: fontRaw, getStrings: fontVtable.pointee.GetFaceNames)
        if familyResult.1 == .observed, faceResult.1 == .observed {
            return (familyResult.0, faceResult.0, .observed)
        }
        if familyResult.0 != nil || faceResult.0 != nil {
            return (familyResult.0, faceResult.0, .partial)
        }
        return (nil, nil, familyResult.1 == faceResult.1 ? familyResult.1 : .partial)
    }

    private static func localizedName(
        owner: UnsafeMutableRawPointer, getStrings: DWGetInterfaceProc
    ) -> (String?, NativeBitmapFontMetadataStatus) {
        var stringsRaw: UnsafeMutableRawPointer?
        let hr = getStrings(owner, &stringsRaw)
        defer { releaseMetadataCOM(stringsRaw) }
        guard isSuccess(hr) else { return (nil, .failed) }
        guard let stringsRaw else { return (nil, .invalidValue) }
        let strings = stringsRaw.assumingMemoryBound(to: IDWriteLocalizedStrings.self)
        guard let vtable = strings.pointee.lpVtbl else { return (nil, .invalidValue) }
        let count = vtable.pointee.GetCount(stringsRaw)
        guard count > 0 else { return (nil, .unavailable) }
        var index: UINT32 = 0
        var exists = WindowsBool(false)
        let locale = Array("en-us".utf16) + [0]
        let localeHR = locale.withUnsafeBufferPointer {
            vtable.pointee.FindLocaleName(stringsRaw, $0.baseAddress, &index, &exists)
        }
        guard isSuccess(localeHR) else { return (nil, .failed) }
        if !exists.boolValue { index = 0 }
        guard index < count else { return (nil, .invalidValue) }
        var length: UINT32 = 0
        guard isSuccess(vtable.pointee.GetStringLength(stringsRaw, index, &length)) else { return (nil, .failed) }
        guard length > 0 else { return (nil, .unavailable) }
        guard length <= UInt32(maximumNameUnits) else { return (nil, .limitExceeded) }
        var units = [WCHAR](repeating: 0xFFFF, count: Int(length) + 1)
        let readHR = units.withUnsafeMutableBufferPointer {
            vtable.pointee.GetString(stringsRaw, index, $0.baseAddress, length + 1)
        }
        guard isSuccess(readHR) else { return (nil, .failed) }
        // Font labels are untrusted metadata and must not smuggle a path into
        // the otherwise path-free report.
        guard units.last == 0, !units.dropLast().contains(0),
            let value = String(validating: units.dropLast(), as: UTF16.self),
            !value.unicodeScalars.contains(where: {
                CharacterSet.controlCharacters.contains($0) || "\\/:".unicodeScalars.contains($0)
            })
        else { return (nil, .invalidValue) }
        return (value, .observed)
    }

    private static func releaseMetadataCOM(_ raw: UnsafeMutableRawPointer?) {
        guard let raw else { return }
        let unknown = raw.assumingMemoryBound(to: IUnknown.self)
        _ = unknown.pointee.lpVtbl.pointee.Release(unknown)
    }

    private static func observedDirectories() -> [NativeBitmapFontDirectory] {
        var directories: [NativeBitmapFontDirectory] = []
        var system = [WCHAR](repeating: 0, count: maximumPathUnits + 1)
        let length = system.withUnsafeMutableBufferPointer {
            GetSystemWindowsDirectoryW($0.baseAddress, UINT($0.count))
        }
        if length > 0, length < UInt32(system.count),
            let path = String(validating: system.prefix(Int(length)), as: UTF16.self)
        {
            directories.append(.init(scope: .systemFonts, path: path + "\\Fonts"))
        }
        if let local = localApplicationDataDirectory() {
            directories.append(.init(scope: .userFonts, path: local + "\\Microsoft\\Windows\\Fonts"))
        }
        return directories
    }

    private static func localApplicationDataDirectory() -> String? {
        // Resolve the OS known folder, not an overridable environment variable.
        // Load from System32 and keep the optional Shell API out of the target's
        // link dependencies. Signature/IID: shlobj_core.h and KnownFolders.h.
        let libraryName = Array("shell32.dll".utf16) + [0]
        guard
            let library = libraryName.withUnsafeBufferPointer({
                LoadLibraryExW($0.baseAddress, nil, DWORD(0x0000_0800))
            })
        else { return nil }
        defer { FreeLibrary(library) }
        guard let symbol = "SHGetKnownFolderPath".withCString({ GetProcAddress(library, $0) }) else { return nil }
        let getFolder = unsafeBitCast(symbol, to: MetadataKnownFolderProc.self)
        var folderID = makeGUID(
            data1: 0xF1B3_2785, data2: 0x6FBA, data3: 0x4FCF,
            data4: (0x9D, 0x55, 0x7B, 0x8E, 0x7F, 0x15, 0x70, 0x91))
        var path: UnsafeMutablePointer<WCHAR>?
        let hr = withUnsafePointer(to: &folderID) { getFolder($0, 0, nil, &path) }
        defer { if let path { CoTaskMemFree(path) } }
        guard isSuccess(hr), let path else { return nil }
        var length = 0
        while length <= maximumPathUnits, path[length] != 0 { length += 1 }
        guard length > 0, length <= maximumPathUnits else { return nil }
        return String(validating: UnsafeBufferPointer(start: path, count: length), as: UTF16.self)
    }
}

private typealias MetadataKnownFolderProc =
    @convention(c) (
        UnsafePointer<GUID>?, DWORD, HANDLE?, UnsafeMutablePointer<UnsafeMutablePointer<WCHAR>?>?
    ) -> HRESULT

/// A bounded observation of a new stream associated with an actual callback face.
/// It does not attest to every byte cached or rasterized before the observation.
/// V2 records are output-only. The separate report reader validates imports;
/// decoding a transport record here would not establish capture provenance.
public struct NativeBitmapFontFaceEvidenceV2: Encodable, Equatable, Sendable {
    public let faceType: UInt32?
    public let axes: [NativeBitmapFontAxisValue]?
    public let axesStatus: NativeBitmapFontMetadataStatus
    public let hasVariations: Bool?
    public let files: [NativeBitmapFontFileEvidenceV2]
    public let filesStatus: NativeBitmapFontMetadataStatus

    public init(
        faceType: UInt32? = nil,
        axes: [NativeBitmapFontAxisValue]? = nil,
        axesStatus: NativeBitmapFontMetadataStatus = .unavailable,
        hasVariations: Bool? = nil,
        files: [NativeBitmapFontFileEvidenceV2] = [],
        filesStatus: NativeBitmapFontMetadataStatus = .unavailable
    ) {
        self.faceType = faceType
        self.axes = axes
        self.axesStatus = axesStatus
        self.hasVariations = hasVariations
        self.files = files
        self.filesStatus = filesStatus
    }
}

public struct NativeBitmapFontFileEvidenceV2: Encodable, Equatable, Sendable {
    public let index: UInt32
    public let reference: NativeBitmapFontFileReference
    public let status: NativeBitmapFontMetadataStatus
    public let operation: String
    public let codeDomain: String
    public let code: Int32?
    public let streamLength: UInt64?
    public let requestedBytes: UInt64
    public let readBytes: UInt64
    public let sha256: String?
    public let observationKind: String
    public let loadedBytesDigest: String

    public init(
        index: UInt32,
        reference: NativeBitmapFontFileReference,
        status: NativeBitmapFontMetadataStatus,
        operation: String,
        codeDomain: String = "none",
        code: Int32? = nil,
        streamLength: UInt64? = nil,
        requestedBytes: UInt64 = 0,
        readBytes: UInt64 = 0,
        sha256: String? = nil
    ) {
        self.index = index
        self.reference = reference
        self.status = status
        self.operation = operation
        self.codeDomain = codeDomain
        self.code = code
        self.streamLength = streamLength
        self.requestedBytes = requestedBytes
        self.readBytes = readBytes
        self.sha256 = sha256
        observationKind = "face-file-stream-at-observation"
        loadedBytesDigest = "not-observed"
    }
}

/// These limits are fixed; a caller cannot expand a capture's read allowance.
/// Requested bytes include a failed fragment request. Read bytes include a
/// successful fragment even when hashing or final identity checks later fail.
public struct NativeBitmapFontStreamBudget: Equatable, Sendable {
    public static let maximumFileBytes: UInt64 = 16_777_216
    public static let maximumSessionBytes: UInt64 = 67_108_864
    public static let fragmentBytes: UInt64 = 65_536

    public private(set) var requestedBytes: UInt64 = 0
    public private(set) var readBytes: UInt64 = 0
    private var stopped = false

    public init() {}

    var remainingRequestedBytes: UInt64 {
        stopped ? 0 : Self.maximumSessionBytes - requestedBytes
    }

    mutating func account(requested: UInt64, read: UInt64) -> Bool {
        guard read <= requested, requested <= remainingRequestedBytes else {
            stop()
            return false
        }
        requestedBytes += requested
        readBytes += read
        return true
    }

    mutating func stop() {
        // Malformed bridge output cannot grant another read allowance. Do not
        // invent byte counts to express that the remaining work was stopped.
        stopped = true
    }
}

extension NativeBitmapFontMetadataResolver {
    /// The C++ boundary uses SDK-declared COM interfaces. In particular, it does
    /// not extend the handwritten V1 face vtable to guess a Face5 layout.
    static func resolveV2(
        _ face: NativeFontFaceHandle, budget: inout NativeBitmapFontStreamBudget
    ) -> NativeBitmapFontFaceEvidenceV2 {
        var raw = SWU_BitmapFontFaceEvidenceV2()
        var axes = [SWU_BitmapFontAxisValueV2](
            repeating: SWU_BitmapFontAxisValueV2(), count: maximumAxes)
        var files = [SWU_BitmapFontFileEvidenceV2](
            repeating: SWU_BitmapFontFileEvidenceV2(), count: maximumFiles)
        let remaining = budget.remainingRequestedBytes
        withExtendedLifetime(face) {
            axes.withUnsafeMutableBufferPointer { axisBuffer in
                files.withUnsafeMutableBufferPointer { fileBuffer in
                    SWU_BitmapObserveFontFaceV2(
                        face.rawPointer, remaining, &raw,
                        axisBuffer.baseAddress, UInt32(axisBuffer.count),
                        fileBuffer.baseAddress, UInt32(fileBuffer.count))
                }
            }
        }
        return projectV2(raw, axes: axes, files: files, budget: &budget)
    }

    /// Pure conversion is also the test seam. It cannot replace native path
    /// approval, install a custom loader, or increase a production read budget.
    static func projectV2(
        _ raw: SWU_BitmapFontFaceEvidenceV2,
        axes: [SWU_BitmapFontAxisValueV2],
        files: [SWU_BitmapFontFileEvidenceV2],
        budget: inout NativeBitmapFontStreamBudget
    ) -> NativeBitmapFontFaceEvidenceV2 {
        let faceType = raw.has_face_type == 1 && raw.face_type <= 7 ? raw.face_type : nil
        let variations: Bool? =
            raw.has_variations_value == 1 && raw.has_variations <= 1
            ? raw.has_variations == 1 : nil
        let axisResult = projectAxesV2(raw, axes: axes)

        func result(
            _ values: [NativeBitmapFontFileEvidenceV2], _ status: NativeBitmapFontMetadataStatus
        ) -> NativeBitmapFontFaceEvidenceV2 {
            .init(
                faceType: faceType, axes: axisResult.0, axesStatus: axisResult.1,
                hasVariations: variations, files: values, filesStatus: status)
        }

        guard raw.has_face_type <= 1, raw.has_variations_value <= 1,
            raw.file_count <= UInt32(maximumFiles), Int(raw.file_count) <= files.count,
            let filesStatus = streamStatusV2(raw.files_status)
        else {
            budget.stop()
            return result([], .invalidValue)
        }
        var values: [NativeBitmapFontFileEvidenceV2] = []
        var requested: UInt64 = 0
        var read: UInt64 = 0
        for index in 0..<Int(raw.file_count) {
            guard let file = projectFileV2(files[index], expectedIndex: UInt32(index)) else {
                budget.stop()
                return result([], .invalidValue)
            }
            // Each per-file count was bounded before these additions, and
            // there can be at most eight files.
            requested += file.requestedBytes
            read += file.readBytes
            values.append(file)
        }
        guard requested == raw.requested_bytes, read == raw.read_bytes,
            requested <= NativeBitmapFontStreamBudget.maximumSessionBytes,
            read <= requested,
            budget.account(requested: requested, read: read)
        else {
            budget.stop()
            return result([], .invalidValue)
        }
        if values.isEmpty {
            return result([], filesStatus == .observed ? .invalidValue : filesStatus)
        }
        let aggregate: NativeBitmapFontMetadataStatus =
            values.allSatisfy { $0.status == .observed } ? .observed : .partial
        return result(values, filesStatus == aggregate ? aggregate : .invalidValue)
    }

    private static func projectAxesV2(
        _ raw: SWU_BitmapFontFaceEvidenceV2, axes: [SWU_BitmapFontAxisValueV2]
    ) -> ([NativeBitmapFontAxisValue]?, NativeBitmapFontMetadataStatus) {
        guard let status = streamStatusV2(raw.axes_status) else { return (nil, .invalidValue) }
        guard status == .observed else {
            return (nil, raw.axis_count == 0 ? status : .invalidValue)
        }
        guard raw.axis_count <= UInt32(maximumAxes), Int(raw.axis_count) <= axes.count,
            raw.has_variations_value == 1, raw.has_variations <= 1
        else { return (nil, .invalidValue) }
        var tags: Set<UInt32> = []
        var values: [NativeBitmapFontAxisValue] = []
        for axis in axes.prefix(Int(raw.axis_count)) {
            guard validAxisTagV2(axis.tag), axis.value.isFinite, tags.insert(axis.tag).inserted else {
                return (nil, .invalidValue)
            }
            values.append(.init(tag: axis.tag, value: axis.value))
        }
        // Supported zero-axis metadata is an observed empty array. It is not
        // interchangeable with the absence of the optional Face5 interface.
        return (values, .observed)
    }

    static func validAxisTagV2(_ tag: UInt32) -> Bool {
        // DWRITE_MAKE_FONT_AXIS_TAG stores the first ASCII character in the
        // low byte. OpenType axis tags start with a letter and permit only
        // letters, digits, and trailing spaces in the remaining positions.
        func isLetter(_ byte: UInt32) -> Bool {
            (65...90).contains(byte) || (97...122).contains(byte)
        }
        guard isLetter(tag & 0xFF) else { return false }
        var foundSpace = false
        for shift in [8, 16, 24] {
            let byte = (tag >> shift) & 0xFF
            if byte == 32 {
                foundSpace = true
            } else if foundSpace || !(isLetter(byte) || (48...57).contains(byte)) {
                return false
            }
        }
        return true
    }

    private static func projectFileV2(
        _ raw: SWU_BitmapFontFileEvidenceV2, expectedIndex: UInt32
    ) -> NativeBitmapFontFileEvidenceV2? {
        guard raw.index == expectedIndex,
            let status = streamStatusV2(raw.status),
            let referenceStatus = streamStatusV2(raw.reference_status),
            Int(raw.operation) < streamOperationNamesV2.count,
            Int(raw.code_domain) < streamCodeDomainNamesV2.count,
            raw.has_code <= 1, raw.has_stream_length <= 1, raw.has_sha256 <= 1,
            raw.requested_bytes <= NativeBitmapFontStreamBudget.maximumFileBytes,
            raw.read_bytes <= raw.requested_bytes
        else { return nil }
        guard raw.code_domain == 0 ? raw.has_code == 0 && raw.code == 0 : raw.has_code == 1 else {
            return nil
        }
        let operation = streamOperationNamesV2[Int(raw.operation)]
        let domain = streamCodeDomainNamesV2[Int(raw.code_domain)]
        let reference: NativeBitmapFontFileReference
        if referenceStatus == .observed {
            guard raw.basename_length > 0, raw.basename_length <= 255,
                raw.scope == 1 || raw.scope == 2
            else { return nil }
            let units = withUnsafeBytes(of: raw.basename) { Array($0.bindMemory(to: UInt16.self)) }
            let length = Int(raw.basename_length)
            guard length < units.count, units[length] == 0, !units.prefix(length).contains(0),
                let basename = String(validating: units.prefix(length), as: UTF16.self), safeBasename(basename)
            else { return nil }
            reference = .init(
                status: .observed, scope: raw.scope == 1 ? .systemFonts : .userFonts, basename: basename)
        } else {
            guard raw.scope == 0, raw.basename_length == 0 else { return nil }
            reference = .init(status: referenceStatus)
        }
        let length: UInt64? = raw.has_stream_length == 1 ? raw.stream_length : nil
        guard raw.has_stream_length == 1 || raw.stream_length == 0,
            raw.requested_bytes == 0 || (length != nil && raw.requested_bytes <= length!),
            raw.operation >= 10 || length == nil,
            raw.operation >= 13 || raw.requested_bytes == 0
        else { return nil }
        if let length, length == 0 {
            guard status == .invalidValue, operation == "get-stream-size", raw.requested_bytes == 0 else {
                return nil
            }
        }
        if let length, length > NativeBitmapFontStreamBudget.maximumFileBytes {
            guard status == .limitExceeded, operation == "check-byte-budget", raw.requested_bytes == 0 else {
                return nil
            }
        }
        let digest: String?
        if status == .observed {
            guard operation == "complete", reference.status == .observed,
                domain == "none", raw.has_code == 0, raw.has_sha256 == 1,
                let length, length > 0, length <= NativeBitmapFontStreamBudget.maximumFileBytes,
                raw.requested_bytes == length, raw.read_bytes == length
            else { return nil }
            digest = withUnsafeBytes(of: raw.sha256) { bytes in
                bytes.map { String(format: "%02x", $0) }.joined()
            }
        } else {
            guard operation != "complete", raw.has_sha256 == 0 else { return nil }
            if status == .nonlocalOrCustom {
                guard operation == "query-local-loader", reference.status == .nonlocalOrCustom,
                    length == nil, raw.requested_bytes == 0, raw.read_bytes == 0
                else { return nil }
            }
            digest = nil
        }
        return .init(
            index: raw.index, reference: reference, status: status,
            operation: operation, codeDomain: domain, code: raw.has_code == 1 ? raw.code : nil,
            streamLength: length, requestedBytes: raw.requested_bytes, readBytes: raw.read_bytes,
            sha256: digest)
    }

    private static func streamStatusV2(_ value: UInt32) -> NativeBitmapFontMetadataStatus? {
        let statuses: [NativeBitmapFontMetadataStatus] = [
            .observed, .partial, .unavailable, .failed, .limitExceeded,
            .invalidValue, .notInSystemCollection, .nonlocalOrCustom, .notApproved, .notImplemented,
        ]
        return Int(value) < statuses.count ? statuses[Int(value)] : nil
    }

    static let streamOperationNamesV2 = [
        "not-started", "get-files", "get-reference-key", "get-loader", "query-local-loader",
        "get-local-path", "validate-local-path", "open-local-file", "verify-local-file",
        "create-stream", "get-stream-size", "check-byte-budget", "initialize-sha256",
        "read-stream-fragment", "hash-stream-fragment", "finish-sha256", "verify-local-file-after", "complete",
    ]

    private static let streamCodeDomainNamesV2 = ["none", "hresult", "win32", "ntstatus"]
}
