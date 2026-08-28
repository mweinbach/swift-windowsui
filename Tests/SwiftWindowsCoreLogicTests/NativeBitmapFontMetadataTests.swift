import Foundation
import WinSDK
import XCTest

@testable import SwiftWindowsUI

/// These objects implement only the named COM prefixes that the metadata reader
/// uses. No installed fonts, DirectWrite factory, or filesystem are consulted.
/// Each fixture owns one reference; callbacks count every temporary COM reference.
private final class BitmapMetadataCOMState {
    var references: ULONG = 1
    var addRefs = 0
    var releases = 0
    var overReleased = false
    var queryCalls = 0
    var expectedQueryIID: GUID?
    var queryIIDMatches: [Bool] = []
    var queryResult: UnsafeMutableRawPointer?
    var queryHRESULT: HRESULT = 0
    var interfaceCalls = 0
    var interfaceResult: UnsafeMutableRawPointer?
    var interfaceHRESULT: HRESULT = 0
    var faceNamesResult: UnsafeMutableRawPointer?
    var faceNamesHRESULT: HRESULT = 0
    var forwardedFaces: [UnsafeMutableRawPointer?] = []
    var localizedCount: UINT32 = 1
    var localeFound = true
    var localeIndex: UINT32 = 0
    var localeHRESULT: HRESULT = 0
    var requestedLocales: [String] = []
    var nameUnits: [WCHAR] = []
    var reportedNameLength: UINT32?
    var nameLengthHRESULT: HRESULT = 0
    var nameHRESULT: HRESULT = 0
    var nameLengthCalls = 0
    var nameCalls = 0
    var requestedNameIndices: [UINT32] = []
    var countCalls = 0
    var fillCalls = 0
    var files: [UnsafeMutableRawPointer?] = []
    var queriedCount: UINT32?
    var filledCount: UINT32?
    var countHRESULT: HRESULT = 0
    var fillHRESULT: HRESULT = 0
    var faceIndex: UINT32 = 0
    var simulations: UINT32 = 0
    var keyCalls = 0
    var key: UnsafeRawPointer?
    var keyLength: UINT32 = 4
    var keyHRESULT: HRESULT = 0
    var pathLengthCalls = 0
    var pathCalls = 0
    var path: [WCHAR] = []
    var reportedPathLength: UINT32?
    var pathLengthHRESULT: HRESULT = 0
    var pathHRESULT: HRESULT = 0
    var keyOwner: BitmapMetadataCOMState?
    var keyOwnerReferencesDuringUse: [ULONG] = []
    var receivedKeyLengths: [UINT32] = []
    var receivedKeysMatchOwner: [Bool] = []
}

private struct BitmapMetadataCOMStorage {
    var vtable: UnsafeMutableRawPointer
    var context: UnsafeMutableRawPointer
}

private final class BitmapMetadataCOMObject<Table> {
    let state = BitmapMetadataCOMState()
    private let table: UnsafeMutablePointer<Table>
    private let storage: UnsafeMutablePointer<BitmapMetadataCOMStorage>

    var rawPointer: UnsafeMutableRawPointer { UnsafeMutableRawPointer(storage) }

    init(_ value: Table) {
        table = .allocate(capacity: 1)
        storage = .allocate(capacity: 1)
        table.initialize(to: value)
        storage.initialize(
            to: BitmapMetadataCOMStorage(
                vtable: UnsafeMutableRawPointer(table),
                context: Unmanaged.passUnretained(state).toOpaque()))
    }

    func assertBalanced(file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(state.references, 1, file: file, line: line)
        XCTAssertEqual(state.addRefs, state.releases, file: file, line: line)
        XCTAssertFalse(state.overReleased, file: file, line: line)
    }

    deinit {
        storage.deinitialize(count: 1)
        storage.deallocate()
        table.deinitialize(count: 1)
        table.deallocate()
    }
}

private func bitmapMetadataState(_ pointer: UnsafeMutableRawPointer?) -> BitmapMetadataCOMState {
    let storage = pointer!.assumingMemoryBound(to: BitmapMetadataCOMStorage.self)
    return Unmanaged<BitmapMetadataCOMState>.fromOpaque(storage.pointee.context).takeUnretainedValue()
}

private func bitmapMetadataAddRef(_ pointer: UnsafeMutableRawPointer?) -> ULONG {
    let state = bitmapMetadataState(pointer)
    state.addRefs += 1
    state.references += 1
    return state.references
}

private func bitmapMetadataRelease(_ pointer: UnsafeMutableRawPointer?) -> ULONG {
    let state = bitmapMetadataState(pointer)
    state.releases += 1
    if state.references <= 1 { state.overReleased = true }
    if state.references > 0 { state.references -= 1 }
    return state.references
}

private func bitmapMetadataQueryInterface(
    _ pointer: UnsafeMutableRawPointer?, _ iid: UnsafePointer<GUID>?,
    _ output: UnsafeMutablePointer<UnsafeMutableRawPointer?>?
) -> HRESULT {
    let state = bitmapMetadataState(pointer)
    state.queryCalls += 1
    output?.pointee = nil
    if let expected = state.expectedQueryIID {
        let matches =
            iid.map { actual in
                withUnsafeBytes(of: expected) { expectedBytes in
                    withUnsafeBytes(of: actual.pointee) { expectedBytes.elementsEqual($0) }
                }
            } ?? false
        state.queryIIDMatches.append(matches)
        if !matches { return HRESULT(bitPattern: 0x8000_4002) }
    }
    guard state.queryHRESULT >= 0, let result = state.queryResult else {
        return state.queryHRESULT < 0 ? state.queryHRESULT : HRESULT(bitPattern: 0x8000_4002)
    }
    _ = bitmapMetadataAddRef(result)
    output?.pointee = result
    return state.queryHRESULT
}

private func bitmapMetadataGetInterface(
    _ pointer: UnsafeMutableRawPointer?, _ output: UnsafeMutablePointer<UnsafeMutableRawPointer?>?
) -> HRESULT {
    let state = bitmapMetadataState(pointer)
    state.interfaceCalls += 1
    output?.pointee = nil
    if let result = state.interfaceResult {
        _ = bitmapMetadataAddRef(result)
        output?.pointee = result
    }
    return state.interfaceHRESULT
}

private func bitmapMetadataGetFontFromFace(
    _ pointer: UnsafeMutableRawPointer?, _ face: UnsafeMutableRawPointer?,
    _ output: UnsafeMutablePointer<UnsafeMutableRawPointer?>?
) -> HRESULT {
    bitmapMetadataState(pointer).forwardedFaces.append(face)
    return bitmapMetadataGetInterface(pointer, output)
}

private func bitmapMetadataGetFaceNames(
    _ pointer: UnsafeMutableRawPointer?, _ output: UnsafeMutablePointer<UnsafeMutableRawPointer?>?
) -> HRESULT {
    let state = bitmapMetadataState(pointer)
    output?.pointee = nil
    if let result = state.faceNamesResult {
        _ = bitmapMetadataAddRef(result)
        output?.pointee = result
    }
    return state.faceNamesHRESULT
}

private func bitmapMetadataGetLocalizedCount(_ pointer: UnsafeMutableRawPointer?) -> UINT32 {
    bitmapMetadataState(pointer).localizedCount
}

private func bitmapMetadataFindLocale(
    _ pointer: UnsafeMutableRawPointer?, _ locale: UnsafePointer<WCHAR>?,
    _ index: UnsafeMutablePointer<UINT32>?, _ exists: UnsafeMutablePointer<WindowsBool>?
) -> HRESULT {
    let state = bitmapMetadataState(pointer)
    if let locale { state.requestedLocales.append(String(decodingCString: locale, as: UTF16.self)) }
    index?.pointee = state.localeIndex
    exists?.pointee = WindowsBool(state.localeFound)
    return state.localeHRESULT
}

private func bitmapMetadataGetNameLength(
    _ pointer: UnsafeMutableRawPointer?, _ index: UINT32, _ length: UnsafeMutablePointer<UINT32>?
) -> HRESULT {
    let state = bitmapMetadataState(pointer)
    state.nameLengthCalls += 1
    state.requestedNameIndices.append(index)
    length?.pointee = state.reportedNameLength ?? UINT32(max(0, state.nameUnits.count - 1))
    return state.nameLengthHRESULT
}

private func bitmapMetadataGetName(
    _ pointer: UnsafeMutableRawPointer?, _ index: UINT32,
    _ output: UnsafeMutablePointer<WCHAR>?, _ capacity: UINT32
) -> HRESULT {
    let state = bitmapMetadataState(pointer)
    state.nameCalls += 1
    state.requestedNameIndices.append(index)
    if let output {
        for offset in 0..<min(Int(capacity), state.nameUnits.count) { output[offset] = state.nameUnits[offset] }
    }
    return state.nameHRESULT
}

private func bitmapMetadataGetFiles(
    _ pointer: UnsafeMutableRawPointer?, _ count: UnsafeMutablePointer<UINT32>?,
    _ output: UnsafeMutablePointer<UnsafeMutableRawPointer?>?
) -> HRESULT {
    let state = bitmapMetadataState(pointer)
    guard let output else {
        state.countCalls += 1
        count?.pointee = state.queriedCount ?? UINT32(state.files.count)
        return state.countHRESULT
    }
    state.fillCalls += 1
    let capacity = Int(count?.pointee ?? 0)
    for index in 0..<min(capacity, state.files.count) {
        if let result = state.files[index] { _ = bitmapMetadataAddRef(result) }
        output[index] = state.files[index]
    }
    count?.pointee = state.filledCount ?? UINT32(state.files.count)
    return state.fillHRESULT
}

private func bitmapMetadataGetIndex(_ pointer: UnsafeMutableRawPointer?) -> UINT32 {
    bitmapMetadataState(pointer).faceIndex
}

private func bitmapMetadataGetSimulations(_ pointer: UnsafeMutableRawPointer?) -> UINT32 {
    bitmapMetadataState(pointer).simulations
}

private func bitmapMetadataGetReferenceKey(
    _ pointer: UnsafeMutableRawPointer?, _ key: UnsafeMutablePointer<UnsafeRawPointer?>?,
    _ length: UnsafeMutablePointer<UINT32>?
) -> HRESULT {
    let state = bitmapMetadataState(pointer)
    state.keyCalls += 1
    key?.pointee = state.key
    length?.pointee = state.keyLength
    return state.keyHRESULT
}

private func bitmapMetadataGetPathLength(
    _ pointer: UnsafeMutableRawPointer?, _ key: UnsafeRawPointer?, _ keyLength: UINT32,
    _ length: UnsafeMutablePointer<UINT32>?
) -> HRESULT {
    let state = bitmapMetadataState(pointer)
    state.pathLengthCalls += 1
    state.receivedKeyLengths.append(keyLength)
    if let owner = state.keyOwner {
        state.keyOwnerReferencesDuringUse.append(owner.references)
        state.receivedKeysMatchOwner.append(owner.key == key)
    }
    length?.pointee = state.reportedPathLength ?? UINT32(max(0, state.path.count - 1))
    return state.pathLengthHRESULT
}

private func bitmapMetadataGetPath(
    _ pointer: UnsafeMutableRawPointer?, _ key: UnsafeRawPointer?, _ keyLength: UINT32,
    _ output: UnsafeMutablePointer<WCHAR>?, _ capacity: UINT32
) -> HRESULT {
    let state = bitmapMetadataState(pointer)
    state.pathCalls += 1
    state.receivedKeyLengths.append(keyLength)
    if let owner = state.keyOwner {
        state.keyOwnerReferencesDuringUse.append(owner.references)
        state.receivedKeysMatchOwner.append(owner.key == key)
    }
    if let output {
        for index in 0..<min(Int(capacity), state.path.count) { output[index] = state.path[index] }
    }
    return state.pathHRESULT
}

private final class BitmapMetadataFileFixture {
    let file: BitmapMetadataCOMObject<SwiftWindowsUI.IDWriteFontFileVtbl>
    let loader: BitmapMetadataCOMObject<SwiftWindowsUI.IDWriteFontFileLoaderVtbl>
    let localLoader: BitmapMetadataCOMObject<SwiftWindowsUI.IDWriteLocalFontFileLoaderVtbl>
    private let key: UnsafeMutablePointer<UInt8>
    private let keyCapacity: Int

    init(path: String) {
        file = BitmapMetadataCOMObject(
            SwiftWindowsUI.IDWriteFontFileVtbl(
                QueryInterface: bitmapMetadataQueryInterface, AddRef: bitmapMetadataAddRef,
                Release: bitmapMetadataRelease, GetReferenceKey: bitmapMetadataGetReferenceKey,
                GetLoader: bitmapMetadataGetInterface))
        loader = BitmapMetadataCOMObject(
            SwiftWindowsUI.IDWriteFontFileLoaderVtbl(
                QueryInterface: bitmapMetadataQueryInterface, AddRef: bitmapMetadataAddRef,
                Release: bitmapMetadataRelease, CreateStreamFromKey: nil))
        localLoader = BitmapMetadataCOMObject(
            SwiftWindowsUI.IDWriteLocalFontFileLoaderVtbl(
                QueryInterface: bitmapMetadataQueryInterface, AddRef: bitmapMetadataAddRef,
                Release: bitmapMetadataRelease, CreateStreamFromKey: nil,
                GetFilePathLengthFromKey: bitmapMetadataGetPathLength, GetFilePathFromKey: bitmapMetadataGetPath))
        let capacity = 65_536
        keyCapacity = capacity
        key = .allocate(capacity: capacity)
        key.initialize(repeating: 0xA7, count: capacity)
        file.state.key = UnsafeRawPointer(key)
        file.state.interfaceResult = loader.rawPointer
        loader.state.queryResult = localLoader.rawPointer
        loader.state.expectedQueryIID = iidIDWriteLocalFontFileLoader
        localLoader.state.path = Array(path.utf16) + [0]
        localLoader.state.keyOwner = file.state
    }

    func assertBalanced(file sourceFile: StaticString = #filePath, line: UInt = #line) {
        file.assertBalanced(file: sourceFile, line: line)
        loader.assertBalanced(file: sourceFile, line: line)
        localLoader.assertBalanced(file: sourceFile, line: line)
    }

    deinit {
        key.deinitialize(count: keyCapacity)
        key.deallocate()
    }
}

private final class BitmapMetadataNamesFixture {
    let collection: BitmapMetadataCOMObject<SwiftWindowsUI.IDWriteFontCollectionVtbl>
    let font: BitmapMetadataCOMObject<SwiftWindowsUI.IDWriteFontVtbl>
    let family: BitmapMetadataCOMObject<SwiftWindowsUI.IDWriteFontFamilyVtbl>
    let familyNames: BitmapMetadataCOMObject<SwiftWindowsUI.IDWriteLocalizedStringsVtbl>
    let faceNames: BitmapMetadataCOMObject<SwiftWindowsUI.IDWriteLocalizedStringsVtbl>

    init(familyName: String = "Fixture Family", faceName: String = "Regular") {
        collection = BitmapMetadataCOMObject(
            SwiftWindowsUI.IDWriteFontCollectionVtbl(
                QueryInterface: bitmapMetadataQueryInterface, AddRef: bitmapMetadataAddRef,
                Release: bitmapMetadataRelease, GetFontFamilyCount: nil, GetFontFamily: nil,
                FindFamilyName: { _, _, _, _ in HRESULT(bitPattern: 0x8000_4001) },
                GetFontFromFontFace: bitmapMetadataGetFontFromFace))
        font = BitmapMetadataCOMObject(
            SwiftWindowsUI.IDWriteFontVtbl(
                QueryInterface: bitmapMetadataQueryInterface, AddRef: bitmapMetadataAddRef,
                Release: bitmapMetadataRelease, GetFontFamily: bitmapMetadataGetInterface,
                GetWeight: nil, GetStretch: nil, GetStyle: nil, IsSymbolFont: nil,
                GetFaceNames: bitmapMetadataGetFaceNames))
        family = BitmapMetadataCOMObject(
            SwiftWindowsUI.IDWriteFontFamilyVtbl(
                QueryInterface: bitmapMetadataQueryInterface, AddRef: bitmapMetadataAddRef,
                Release: bitmapMetadataRelease, GetFontCollection: nil, GetFontCount: nil, GetFont: nil,
                GetFamilyNames: bitmapMetadataGetInterface))
        let stringsTable = SwiftWindowsUI.IDWriteLocalizedStringsVtbl(
            QueryInterface: bitmapMetadataQueryInterface, AddRef: bitmapMetadataAddRef,
            Release: bitmapMetadataRelease, GetCount: bitmapMetadataGetLocalizedCount,
            FindLocaleName: bitmapMetadataFindLocale, GetLocaleNameLength: nil, GetLocaleName: nil,
            GetStringLength: bitmapMetadataGetNameLength, GetString: bitmapMetadataGetName)
        familyNames = BitmapMetadataCOMObject(stringsTable)
        faceNames = BitmapMetadataCOMObject(stringsTable)
        collection.state.interfaceResult = font.rawPointer
        font.state.interfaceResult = family.rawPointer
        font.state.faceNamesResult = faceNames.rawPointer
        family.state.interfaceResult = familyNames.rawPointer
        familyNames.state.nameUnits = Array(familyName.utf16) + [0]
        faceNames.state.nameUnits = Array(faceName.utf16) + [0]
    }

    func assertBalanced(file: StaticString = #filePath, line: UInt = #line) {
        collection.assertBalanced(file: file, line: line)
        XCTAssertEqual(collection.state.addRefs, 0, "The system collection is borrowed", file: file, line: line)
        font.assertBalanced(file: file, line: line)
        family.assertBalanced(file: file, line: line)
        familyNames.assertBalanced(file: file, line: line)
        faceNames.assertBalanced(file: file, line: line)
    }
}

private final class BitmapMetadataFixture {
    let face: BitmapMetadataCOMObject<SwiftWindowsUI.IDWriteFontFaceVtbl>
    let files: [BitmapMetadataFileFixture]

    init(paths: [String] = [#"C:\Diagnostic\Fonts\fixture.ttf"#]) {
        face = BitmapMetadataCOMObject(
            SwiftWindowsUI.IDWriteFontFaceVtbl(
                QueryInterface: bitmapMetadataQueryInterface, AddRef: bitmapMetadataAddRef,
                Release: bitmapMetadataRelease, GetType: { _ in 0 }, GetFiles: bitmapMetadataGetFiles,
                GetIndex: bitmapMetadataGetIndex, GetSimulations: bitmapMetadataGetSimulations))
        files = paths.map { BitmapMetadataFileFixture(path: $0) }
        face.state.files = files.map { $0.file.rawPointer }
    }

    @MainActor
    func resolve(
        approvedDirectories: [NativeBitmapFontDirectory]? = nil,
        systemCollection: UnsafeMutableRawPointer? = nil
    ) -> NativeBitmapFontFaceMetadata {
        var handle = NativeFontFaceHandle(face.rawPointer)
        let result = NativeBitmapFontMetadataResolver.resolve(
            handle!, systemCollection: systemCollection,
            approvedDirectories: approvedDirectories ?? [
                NativeBitmapFontDirectory(scope: .systemFonts, path: #"C:\Diagnostic\Fonts"#),
                NativeBitmapFontDirectory(scope: .userFonts, path: #"C:\Profiles\Example\Fonts"#),
            ])
        handle = nil
        return result
    }

    func assertBalanced(file: StaticString = #filePath, line: UInt = #line) {
        face.assertBalanced(file: file, line: line)
        for fixture in files { fixture.assertBalanced(file: file, line: line) }
    }
}

final class NativeBitmapFontMetadataTests: XCTestCase {
    func testApprovedFilesKeepScopeBasenameAndPhysicalFaceIndex() async {
        await MainActor.run {
            let fixture = BitmapMetadataFixture(
                paths: [#"c:\DIAGNOSTIC\Fonts\Fixture.TTF"#, #"C:\Profiles\Example\Fonts\collection.ttc"#])
            fixture.face.state.faceIndex = 7
            fixture.face.state.simulations = 3
            let metadata = fixture.resolve()
            XCTAssertEqual(metadata.faceIndex, 7)
            XCTAssertEqual(metadata.simulations, 3)
            XCTAssertEqual(metadata.status, .partial, "Unimplemented axes must not become fully observed")
            XCTAssertEqual(metadata.filesStatus, .observed)
            XCTAssertEqual(metadata.files.count, 2)
            XCTAssertEqual(metadata.files.first?.status, .observed)
            XCTAssertEqual(metadata.files.first?.scope, .systemFonts)
            XCTAssertEqual(metadata.files.first?.basename, "Fixture.TTF")
            XCTAssertEqual(metadata.files.last?.scope, .userFonts)
            XCTAssertEqual(metadata.files.last?.basename, "collection.ttc")
            XCTAssertNil(metadata.familyName)
            XCTAssertNil(metadata.faceName)
            XCTAssertEqual(metadata.namesStatus, .unavailable)
            XCTAssertNil(metadata.axes)
            XCTAssertEqual(metadata.axesStatus, .notImplemented)
            fixture.assertBalanced()
            XCTAssertEqual(fixture.face.state.addRefs, 1, "Only the owning handle retains the observed face")
            for file in fixture.files {
                XCTAssertEqual(file.file.state.addRefs, 1)
                XCTAssertEqual(file.loader.state.addRefs, 1)
                XCTAssertEqual(file.localLoader.state.addRefs, 1)
                XCTAssertEqual(file.loader.state.queryIIDMatches, [true])
                XCTAssertEqual(file.localLoader.state.keyOwnerReferencesDuringUse, [2, 2])
                XCTAssertEqual(file.localLoader.state.receivedKeyLengths, [4, 4])
                XCTAssertEqual(file.localLoader.state.receivedKeysMatchOwner, [true, true])
            }
        }
    }

    func testExcessiveFileCountsAreRejectedBeforeRequestingPointers() async {
        await MainActor.run {
            for count in [UINT32(9), UINT32.max] {
                let fixture = BitmapMetadataFixture()
                fixture.face.state.queriedCount = count
                let metadata = fixture.resolve()
                XCTAssertEqual(metadata.filesStatus, .limitExceeded)
                XCTAssertTrue(metadata.files.isEmpty)
                XCTAssertEqual(fixture.face.state.countCalls, 1)
                XCTAssertEqual(fixture.face.state.fillCalls, 0)
                XCTAssertEqual(fixture.files[0].file.state.keyCalls, 0)
                fixture.assertBalanced()
            }
        }
    }

    func testZeroFileCountStaysInvalidWithoutRequestingAnArray() async {
        await MainActor.run {
            let fixture = BitmapMetadataFixture(paths: [])
            let metadata = fixture.resolve()
            XCTAssertEqual(metadata.filesStatus, .invalidValue)
            XCTAssertTrue(metadata.files.isEmpty)
            XCTAssertEqual(fixture.face.state.fillCalls, 0)
            fixture.assertBalanced()
        }
    }

    func testMaximumFileAndReferenceKeyCountsRemainUsable() async {
        await MainActor.run {
            let fixture = BitmapMetadataFixture(
                paths: (0..<8).map { #"C:\Diagnostic\Fonts\fixture"# + String($0) + ".ttf" })
            for file in fixture.files { file.file.state.keyLength = 65_536 }
            let metadata = fixture.resolve()
            XCTAssertEqual(metadata.filesStatus, .observed)
            XCTAssertEqual(metadata.files.count, 8)
            XCTAssertTrue(metadata.files.allSatisfy { $0.status == .observed })
            for file in fixture.files {
                XCTAssertEqual(file.localLoader.state.receivedKeyLengths, [65_536, 65_536])
                XCTAssertEqual(file.localLoader.state.receivedKeysMatchOwner, [true, true])
            }
            fixture.assertBalanced()
        }
    }

    func testFileCountFailureDoesNotRequestFilePointers() async {
        await MainActor.run {
            let fixture = BitmapMetadataFixture()
            fixture.face.state.countHRESULT = HRESULT(bitPattern: 0x8000_4005)
            let metadata = fixture.resolve()
            XCTAssertEqual(metadata.filesStatus, .failed)
            XCTAssertEqual(fixture.face.state.fillCalls, 0)
            fixture.assertBalanced()
        }
    }

    func testFileArrayFailureReleasesEveryReturnedReference() async {
        await MainActor.run {
            let fixture = BitmapMetadataFixture(paths: [
                #"C:\Diagnostic\Fonts\one.ttf"#, #"C:\Diagnostic\Fonts\two.otf"#,
            ])
            fixture.face.state.fillHRESULT = HRESULT(bitPattern: 0x8000_4005)
            let metadata = fixture.resolve()
            XCTAssertEqual(metadata.filesStatus, .failed)
            XCTAssertEqual(fixture.face.state.fillCalls, 1)
            for file in fixture.files {
                XCTAssertEqual(file.file.state.addRefs, 1)
                XCTAssertEqual(file.file.state.keyCalls, 0)
            }
            fixture.assertBalanced()
        }
    }

    func testIncreasingFileCountNeverReadsBeyondTheAllocatedArray() async {
        await MainActor.run {
            let fixture = BitmapMetadataFixture()
            fixture.face.state.filledCount = 2
            let metadata = fixture.resolve()
            XCTAssertEqual(metadata.filesStatus, .invalidValue)
            XCTAssertEqual(fixture.files[0].file.state.keyCalls, 0)
            fixture.assertBalanced()
        }
    }

    func testDecreasingFileCountStillReleasesTheEntireOriginalArray() async {
        await MainActor.run {
            let fixture = BitmapMetadataFixture(paths: [
                #"C:\Diagnostic\Fonts\one.ttf"#, #"C:\Diagnostic\Fonts\two.ttf"#,
            ])
            fixture.face.state.filledCount = 1
            let metadata = fixture.resolve()
            XCTAssertEqual(metadata.filesStatus, .invalidValue)
            XCTAssertTrue(metadata.files.isEmpty)
            for file in fixture.files {
                XCTAssertEqual(file.file.state.addRefs, 1)
                XCTAssertEqual(file.file.state.releases, 1)
                XCTAssertEqual(file.file.state.keyCalls, 0)
            }
            fixture.assertBalanced()
        }
    }

    func testDuplicateFilePointersReleaseOneReferencePerReturnedSlot() async {
        await MainActor.run {
            let fixture = BitmapMetadataFixture()
            let file = fixture.files[0]
            fixture.face.state.files = [file.file.rawPointer, file.file.rawPointer]
            let metadata = fixture.resolve()
            XCTAssertEqual(metadata.filesStatus, .observed)
            XCTAssertEqual(metadata.files.count, 2)
            XCTAssertEqual(file.file.state.addRefs, 2)
            XCTAssertEqual(file.file.state.releases, 2)
            XCTAssertEqual(file.localLoader.state.keyOwnerReferencesDuringUse, [3, 3, 3, 3])
            fixture.assertBalanced()
        }
    }

    func testMissingFilePointerCannotBecomeObservedAttribution() async {
        await MainActor.run {
            let fixture = BitmapMetadataFixture()
            fixture.face.state.files = [nil]
            let metadata = fixture.resolve()
            XCTAssertNotEqual(metadata.filesStatus, .observed)
            XCTAssertFalse(metadata.files.contains { $0.status == .observed })
            XCTAssertEqual(fixture.files[0].file.state.keyCalls, 0)
            fixture.assertBalanced()
        }
    }

    func testInvalidReferenceKeysStopBeforeLoaderLookup() async {
        await MainActor.run {
            for length in [UINT32(0), 65_537, UINT32.max] {
                let fixture = BitmapMetadataFixture()
                fixture.files[0].file.state.keyLength = length
                let metadata = fixture.resolve()
                XCTAssertEqual(metadata.filesStatus, .partial)
                XCTAssertEqual(metadata.files.first?.status, length == 0 ? .invalidValue : .limitExceeded)
                XCTAssertEqual(fixture.files[0].file.state.interfaceCalls, 0)
                fixture.assertBalanced()
            }
            let fixture = BitmapMetadataFixture()
            fixture.files[0].file.state.key = nil
            XCTAssertEqual(fixture.resolve().files.first?.status, .invalidValue)
            XCTAssertEqual(fixture.files[0].file.state.interfaceCalls, 0)
            fixture.assertBalanced()
        }
    }

    func testReferenceKeyAndLoaderFailuresPreserveTheirDistinctStatus() async {
        await MainActor.run {
            let keyFailure = BitmapMetadataFixture()
            keyFailure.files[0].file.state.keyHRESULT = HRESULT(bitPattern: 0x8000_4005)
            XCTAssertEqual(keyFailure.resolve().files.first?.status, .failed)
            XCTAssertEqual(keyFailure.files[0].file.state.interfaceCalls, 0)
            keyFailure.assertBalanced()

            let loaderFailure = BitmapMetadataFixture()
            loaderFailure.files[0].file.state.interfaceHRESULT = HRESULT(bitPattern: 0x8000_4005)
            XCTAssertEqual(loaderFailure.resolve().files.first?.status, .failed)
            XCTAssertEqual(loaderFailure.files[0].loader.state.addRefs, 1)
            XCTAssertEqual(loaderFailure.files[0].loader.state.releases, 1)
            XCTAssertEqual(loaderFailure.files[0].loader.state.queryCalls, 0)
            loaderFailure.assertBalanced()

            let nilLoader = BitmapMetadataFixture()
            nilLoader.files[0].file.state.interfaceResult = nil
            XCTAssertEqual(nilLoader.resolve().files.first?.status, .invalidValue)
            nilLoader.assertBalanced()

            let queryFailure = BitmapMetadataFixture()
            queryFailure.files[0].loader.state.queryHRESULT = HRESULT(bitPattern: 0x8000_4005)
            XCTAssertEqual(queryFailure.resolve().files.first?.status, .failed)
            XCTAssertEqual(queryFailure.files[0].localLoader.state.pathLengthCalls, 0)
            queryFailure.assertBalanced()
        }
    }

    func testCustomLoaderIsExplicitlyNonlocalAndReleased() async {
        await MainActor.run {
            let fixture = BitmapMetadataFixture()
            fixture.files[0].loader.state.queryResult = nil
            let metadata = fixture.resolve()
            XCTAssertEqual(metadata.files.first?.status, .nonlocalOrCustom)
            XCTAssertNil(metadata.files.first?.scope)
            XCTAssertNil(metadata.files.first?.basename)
            XCTAssertEqual(fixture.files[0].loader.state.queryCalls, 1)
            XCTAssertEqual(fixture.files[0].localLoader.state.pathLengthCalls, 0)
            fixture.assertBalanced()
        }
    }

    func testOversizedPathsAreRejectedBeforeFetchingTheirContents() async {
        await MainActor.run {
            for length in [UINT32(1_025), UINT32.max] {
                let fixture = BitmapMetadataFixture()
                fixture.files[0].localLoader.state.reportedPathLength = length
                let metadata = fixture.resolve()
                XCTAssertEqual(metadata.files.first?.status, .limitExceeded)
                XCTAssertNil(metadata.files.first?.basename)
                XCTAssertEqual(fixture.files[0].localLoader.state.pathCalls, 0)
                fixture.assertBalanced()
            }
        }
    }

    func testMalformedUTF16PathsAndTerminatorMismatchesAreRejected() async {
        await MainActor.run {
            let malformedUnits: [[WCHAR]] = [
                [0], [0xD800, 0], [65, 0, 66, 0], [65, 66],
            ]
            for units in malformedUnits {
                let fixture = BitmapMetadataFixture()
                fixture.files[0].localLoader.state.path = units
                let metadata = fixture.resolve()
                XCTAssertEqual(metadata.files.first?.status, .invalidValue)
                XCTAssertNil(metadata.files.first?.scope)
                XCTAssertNil(metadata.files.first?.basename)
                fixture.assertBalanced()
            }
        }
    }

    func testPathFailuresReleaseBothLoaderInterfaces() async {
        await MainActor.run {
            for failLength in [true, false] {
                let fixture = BitmapMetadataFixture()
                if failLength {
                    fixture.files[0].localLoader.state.pathLengthHRESULT = HRESULT(bitPattern: 0x8000_4005)
                } else {
                    fixture.files[0].localLoader.state.pathHRESULT = HRESULT(bitPattern: 0x8000_4005)
                }
                let metadata = fixture.resolve()
                XCTAssertEqual(metadata.files.first?.status, .failed)
                XCTAssertNil(metadata.files.first?.basename)
                fixture.assertBalanced()
            }
        }
    }

    func testOnlySafeDirectChildrenOfApprovedDirectoriesAreDisclosed() async {
        await MainActor.run {
            let rejected = [
                #"C:\Private\Secrets\personal.ttf"#, #"C:\Diagnostic\Fonts2\personal.ttf"#,
                #"C:\Diagnostic\Fonts\nested\personal.ttf"#, #"C:\Diagnostic\Fonts\..\personal.ttf"#,
                #"C:\Diagnostic\Fonts\face.ttf:private"#, #"C:\Diagnostic\Fonts\face.exe"#,
                #"C:\Diagnostic\Fonts\face.ttf."#, #"C:\Diagnostic\Fonts\face.ttf "#,
                #"C:\Diagnostic\Fonts\CON.ttf"#, #"C:Diagnostic\Fonts\face.ttf"#,
                #"C:\Diagnostic\Fonts\CON .ttf"#, #"C:\Diagnostic\Fonts\COM1 .ttf"#,
                #"\Diagnostic\Fonts\face.ttf"#, #"\\server\share\face.ttf"#,
                #"\\?\C:\Diagnostic\Fonts\face.ttf"#, #"fixture.ttf"#,
            ]
            for path in rejected {
                let fixture = BitmapMetadataFixture(paths: [path])
                let metadata = fixture.resolve()
                XCTAssertNotEqual(metadata.files.first?.status, .observed, path)
                XCTAssertNil(metadata.files.first?.scope, path)
                XCTAssertNil(metadata.files.first?.basename, path)
                fixture.assertBalanced()
            }
            let fixture = BitmapMetadataFixture()
            let metadata = fixture.resolve(approvedDirectories: [])
            XCTAssertEqual(metadata.files.first?.status, .unavailable)
            XCTAssertNil(metadata.files.first?.basename)
            fixture.assertBalanced()
        }
    }

    func testCanonicallyEquivalentUnicodeDirectoriesAreNotTheSameApprovedPath() async {
        await MainActor.run {
            let root = NativeBitmapFontDirectory(scope: .systemFonts, path: "C:\\Caf\u{00E9}\\Fonts")
            let reference = NativeBitmapFontMetadataResolver.approvedReference(
                path: "C:\\Cafe\u{0301}\\Fonts\\fixture.ttf", approvedDirectories: [root])
            XCTAssertEqual(reference.status, .notApproved)
            XCTAssertNil(reference.scope)
            XCTAssertNil(reference.basename)
        }
    }

    func testNamesComeFromTheObservedFaceAndUseTheResolvedLocaleIndex() async {
        await MainActor.run {
            let fixture = BitmapMetadataFixture()
            let names = BitmapMetadataNamesFixture()
            names.familyNames.state.localizedCount = 2
            names.familyNames.state.localeIndex = 1
            names.faceNames.state.localeFound = false
            names.faceNames.state.localeIndex = .max
            let metadata = fixture.resolve(systemCollection: names.collection.rawPointer)
            XCTAssertEqual(metadata.namesStatus, .observed)
            XCTAssertEqual(metadata.familyName, "Fixture Family")
            XCTAssertEqual(metadata.faceName, "Regular")
            XCTAssertEqual(metadata.status, .partial)
            XCTAssertEqual(names.collection.state.forwardedFaces, [fixture.face.rawPointer])
            XCTAssertEqual(names.familyNames.state.requestedLocales, ["en-us"])
            XCTAssertEqual(names.faceNames.state.requestedLocales, ["en-us"])
            XCTAssertEqual(names.familyNames.state.requestedNameIndices, [1, 1])
            XCTAssertEqual(names.faceNames.state.requestedNameIndices, [0, 0], "A missing locale selects index zero")
            XCTAssertEqual(names.font.state.addRefs, 1)
            XCTAssertEqual(names.family.state.addRefs, 1)
            XCTAssertEqual(names.familyNames.state.addRefs, 1)
            XCTAssertEqual(names.faceNames.state.addRefs, 1)
            names.assertBalanced()
            fixture.assertBalanced()
        }
    }

    func testCollectionNonmemberIsDistinctFromFailureAndReleasesReturnedFont() async {
        await MainActor.run {
            let cases: [(HRESULT, NativeBitmapFontMetadataStatus)] = [
                (HRESULT(bitPattern: 0x8898_5002), .notInSystemCollection),
                (HRESULT(bitPattern: 0x8000_4005), .failed),
            ]
            for (hresult, expected) in cases {
                let fixture = BitmapMetadataFixture()
                let names = BitmapMetadataNamesFixture()
                names.collection.state.interfaceHRESULT = hresult
                let metadata = fixture.resolve(systemCollection: names.collection.rawPointer)
                XCTAssertEqual(metadata.namesStatus, expected)
                XCTAssertNil(metadata.familyName)
                XCTAssertNil(metadata.faceName)
                XCTAssertEqual(metadata.filesStatus, .observed, "Name lookup failure cannot erase file observations")
                XCTAssertEqual(names.collection.state.forwardedFaces, [fixture.face.rawPointer])
                XCTAssertEqual(names.font.state.addRefs, 1)
                XCTAssertEqual(names.font.state.releases, 1)
                XCTAssertEqual(names.font.state.interfaceCalls, 0)
                names.assertBalanced()
                fixture.assertBalanced()
            }
        }
    }

    func testSuccessfulCollectionLookupWithoutAFontIsInvalid() async {
        await MainActor.run {
            let fixture = BitmapMetadataFixture()
            let names = BitmapMetadataNamesFixture()
            names.collection.state.interfaceResult = nil
            let metadata = fixture.resolve(systemCollection: names.collection.rawPointer)
            XCTAssertEqual(metadata.namesStatus, .invalidValue)
            XCTAssertNil(metadata.familyName)
            XCTAssertNil(metadata.faceName)
            XCTAssertEqual(names.collection.state.forwardedFaces, [fixture.face.rawPointer])
            XCTAssertEqual(names.font.state.addRefs, 0)
            names.assertBalanced()
            fixture.assertBalanced()
        }
    }

    func testFailedFamilyLookupKeepsIndependentFaceNameAndReleasesFamily() async {
        await MainActor.run {
            let fixture = BitmapMetadataFixture()
            let names = BitmapMetadataNamesFixture()
            names.font.state.interfaceHRESULT = HRESULT(bitPattern: 0x8000_4005)
            let metadata = fixture.resolve(systemCollection: names.collection.rawPointer)
            XCTAssertEqual(metadata.namesStatus, .partial)
            XCTAssertNil(metadata.familyName)
            XCTAssertEqual(metadata.faceName, "Regular")
            XCTAssertEqual(names.family.state.addRefs, 1)
            XCTAssertEqual(names.family.state.releases, 1)
            XCTAssertEqual(names.familyNames.state.addRefs, 0)
            XCTAssertEqual(names.faceNames.state.addRefs, 1)
            names.assertBalanced()
            fixture.assertBalanced()
        }
    }

    func testMaximumNameLengthIsObservedButLargerLengthsAreNotRead() async {
        await MainActor.run {
            let fixture = BitmapMetadataFixture()
            let names = BitmapMetadataNamesFixture(
                familyName: String(repeating: "F", count: 512), faceName: String(repeating: "R", count: 512))
            let metadata = fixture.resolve(systemCollection: names.collection.rawPointer)
            XCTAssertEqual(metadata.namesStatus, .observed)
            XCTAssertEqual(metadata.familyName?.utf16.count, 512)
            XCTAssertEqual(metadata.faceName?.utf16.count, 512)
            names.assertBalanced()
            fixture.assertBalanced()

            for length in [UINT32(513), UINT32.max] {
                let boundedFixture = BitmapMetadataFixture()
                let boundedNames = BitmapMetadataNamesFixture()
                boundedNames.familyNames.state.reportedNameLength = length
                boundedNames.faceNames.state.reportedNameLength = length
                let bounded = boundedFixture.resolve(systemCollection: boundedNames.collection.rawPointer)
                XCTAssertEqual(bounded.namesStatus, .limitExceeded)
                XCTAssertNil(bounded.familyName)
                XCTAssertNil(bounded.faceName)
                XCTAssertEqual(boundedNames.familyNames.state.nameCalls, 0)
                XCTAssertEqual(boundedNames.faceNames.state.nameCalls, 0)
                boundedNames.assertBalanced()
                boundedFixture.assertBalanced()
            }
        }
    }

    func testEmptyLocalizedCollectionsAndNamesRemainUnavailable() async {
        await MainActor.run {
            for emptyCollection in [true, false] {
                let fixture = BitmapMetadataFixture()
                let names = BitmapMetadataNamesFixture(familyName: "", faceName: "")
                if emptyCollection {
                    names.familyNames.state.localizedCount = 0
                    names.faceNames.state.localizedCount = 0
                }
                let metadata = fixture.resolve(systemCollection: names.collection.rawPointer)
                XCTAssertEqual(metadata.namesStatus, .unavailable)
                XCTAssertNil(metadata.familyName)
                XCTAssertNil(metadata.faceName)
                XCTAssertEqual(names.familyNames.state.nameCalls, 0)
                XCTAssertEqual(names.faceNames.state.nameCalls, 0)
                if emptyCollection {
                    XCTAssertTrue(names.familyNames.state.requestedLocales.isEmpty)
                    XCTAssertTrue(names.faceNames.state.requestedLocales.isEmpty)
                }
                names.assertBalanced()
                fixture.assertBalanced()
            }
        }
    }

    func testLocaleIndexOutsideTheReportedCountIsNeverRead() async {
        await MainActor.run {
            let fixture = BitmapMetadataFixture()
            let names = BitmapMetadataNamesFixture()
            names.familyNames.state.localeIndex = 1
            names.faceNames.state.localeIndex = .max
            let metadata = fixture.resolve(systemCollection: names.collection.rawPointer)
            XCTAssertEqual(metadata.namesStatus, .invalidValue)
            XCTAssertNil(metadata.familyName)
            XCTAssertNil(metadata.faceName)
            XCTAssertEqual(names.familyNames.state.nameLengthCalls, 0)
            XCTAssertEqual(names.faceNames.state.nameLengthCalls, 0)
            names.assertBalanced()
            fixture.assertBalanced()
        }
    }

    func testMalformedNamesCannotEnterMetadata() async {
        await MainActor.run {
            let malformedUnits: [[WCHAR]] = [
                [0xD800, 0], [65, 0, 66, 0], [65, 66], [65, 10, 66, 0],
            ]
            for units in malformedUnits {
                let fixture = BitmapMetadataFixture()
                let names = BitmapMetadataNamesFixture()
                names.familyNames.state.nameUnits = units
                names.faceNames.state.nameUnits = units
                let metadata = fixture.resolve(systemCollection: names.collection.rawPointer)
                XCTAssertEqual(metadata.namesStatus, .invalidValue)
                XCTAssertNil(metadata.familyName)
                XCTAssertNil(metadata.faceName)
                names.assertBalanced()
                fixture.assertBalanced()
            }
        }
    }

    func testPathLikeFamilyAndFaceLabelsCannotEnterMetadata() async throws {
        try await MainActor.run {
            let labels = [
                #"C:\Users\private-font-marker\face.ttf"#,
                #"\\server\private-font-marker\face.ttf"#,
                "/Users/private-font-marker/face.otf",
                "private-font-marker:Regular",
                "private-font-marker/Regular",
                "private-font-marker\\Regular",
                "private-font-marker/\u{0301}Regular",
            ]
            for label in labels {
                let fixture = BitmapMetadataFixture()
                let names = BitmapMetadataNamesFixture(familyName: label, faceName: label)
                let metadata = fixture.resolve(systemCollection: names.collection.rawPointer)
                XCTAssertEqual(metadata.namesStatus, .invalidValue)
                XCTAssertNil(metadata.familyName)
                XCTAssertNil(metadata.faceName)
                XCTAssertEqual(metadata.filesStatus, .observed)
                let encoded = String(decoding: try JSONEncoder().encode(metadata), as: UTF8.self)
                XCTAssertFalse(encoded.contains("private-font-marker"))
                names.assertBalanced()
                fixture.assertBalanced()
            }
        }
    }

    func testRejectedPathLabelDoesNotDiscardIndependentSafeFontName() async throws {
        try await MainActor.run {
            for rejectFamily in [true, false] {
                let fixture = BitmapMetadataFixture()
                let pathLabel = #"C:\Users\private-font-marker\face.ttf"#
                let names = BitmapMetadataNamesFixture(
                    familyName: rejectFamily ? pathLabel : "Fixture Family",
                    faceName: rejectFamily ? "Regular" : pathLabel)
                let metadata = fixture.resolve(systemCollection: names.collection.rawPointer)
                XCTAssertEqual(metadata.namesStatus, .partial)
                XCTAssertEqual(metadata.familyName, rejectFamily ? nil : "Fixture Family")
                XCTAssertEqual(metadata.faceName, rejectFamily ? "Regular" : nil)
                let encoded = String(decoding: try JSONEncoder().encode(metadata), as: UTF8.self)
                XCTAssertFalse(encoded.contains("private-font-marker"))
                names.assertBalanced()
                fixture.assertBalanced()
            }
        }
    }

    func testLocalizedNameFailuresReleaseEveryOwnedInterface() async {
        await MainActor.run {
            for stage in ["strings", "locale", "length", "read"] {
                let fixture = BitmapMetadataFixture()
                let names = BitmapMetadataNamesFixture()
                let failure = HRESULT(bitPattern: 0x8000_4005)
                switch stage {
                case "strings":
                    names.family.state.interfaceHRESULT = failure
                    names.font.state.faceNamesHRESULT = failure
                case "locale":
                    names.familyNames.state.localeHRESULT = failure
                    names.faceNames.state.localeHRESULT = failure
                case "length":
                    names.familyNames.state.nameLengthHRESULT = failure
                    names.faceNames.state.nameLengthHRESULT = failure
                default:
                    names.familyNames.state.nameHRESULT = failure
                    names.faceNames.state.nameHRESULT = failure
                }
                let metadata = fixture.resolve(systemCollection: names.collection.rawPointer)
                XCTAssertEqual(metadata.namesStatus, .failed, stage)
                XCTAssertNil(metadata.familyName, stage)
                XCTAssertNil(metadata.faceName, stage)
                XCTAssertEqual(names.familyNames.state.addRefs, 1)
                XCTAssertEqual(names.familyNames.state.releases, 1)
                XCTAssertEqual(names.faceNames.state.addRefs, 1)
                XCTAssertEqual(names.faceNames.state.releases, 1)
                names.assertBalanced()
                fixture.assertBalanced()
            }
        }
    }

    func testMetadataEncodingDoesNotExposeFullPathsOrReferenceKeys() async throws {
        try await MainActor.run {
            let fixture = BitmapMetadataFixture(paths: [#"C:\Profiles\Example\Fonts\fixture.ttf"#])
            let metadata = fixture.resolve()
            let data = try JSONEncoder().encode(metadata)
            let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
            let encoded = String(decoding: data, as: UTF8.self)
            XCTAssertFalse(encoded.contains("Profiles"))
            XCTAssertFalse(encoded.contains("Example"))
            XCTAssertFalse(encoded.contains("referenceKey"))
            XCTAssertFalse(encoded.contains("rawPointer"))
            XCTAssertTrue(
                Set(object.keys).isSubset(
                    of: Set([
                        "status", "familyName", "faceName", "namesStatus", "faceIndex", "simulations",
                        "files", "filesStatus", "axes", "axesStatus",
                    ])))
            let files = try XCTUnwrap(object["files"] as? [[String: Any]])
            XCTAssertEqual(Set(try XCTUnwrap(files.first).keys), Set(["status", "scope", "basename"]))
            XCTAssertEqual(files.first?["basename"] as? String, "fixture.ttf")
            fixture.assertBalanced()
        }
    }
}
