import Foundation
import SwiftWindowsCore
import WinSDK
import XCTest

@testable import SwiftWindowsPlatform

/// Hostile-input tests for the hand-laid native buffer code behind the
/// file-list clipboard (`CF_HDROP`) and shell file drops (`WM_DROPFILES`).
/// The payload blocks arrive from other processes, so every parse must fail
/// closed on truncated, oversized, unterminated, or odd-length buffers.
/// Tests drive the pure validator directly — no live OS handles receive
/// hostile input.
final class DropFilesPayloadHardeningTests: XCTestCase {

    // MARK: - Payload builders

    /// Builds a DROPFILES block exactly as `Win32ClipboardFileStore.copyFiles`
    /// lays it out (20-byte header, wide strings, double-null terminator).
    private func widePayload(paths: [String], fWide: UInt32 = 1) -> [UInt8] {
        var data = Data(count: 20)
        data.withUnsafeMutableBytes { bytes in
            bytes.storeBytes(of: UInt32(20), toByteOffset: 0, as: UInt32.self)
            bytes.storeBytes(of: fWide, toByteOffset: 16, as: UInt32.self)
        }
        for path in paths {
            var units = Array(path.utf16)
            units.append(0)
            units.withUnsafeBytes { data.append(contentsOf: $0) }
        }
        data.append(contentsOf: [0, 0])
        return Array(data)
    }

    /// Same layout with the `pFiles` offset overwritten (for hostile offsets).
    private func widePayload(paths: [String], pFiles: UInt32) -> [UInt8] {
        var bytes = widePayload(paths: paths)
        bytes.withUnsafeMutableBytes { raw in
            raw.storeBytes(of: pFiles, toByteOffset: 0, as: UInt32.self)
        }
        return bytes
    }

    private func ansiPayload(paths: [String]) -> [UInt8] {
        var data = Data(count: 20)
        data.withUnsafeMutableBytes { bytes in
            bytes.storeBytes(of: UInt32(20), toByteOffset: 0, as: UInt32.self)
            bytes.storeBytes(of: UInt32(0), toByteOffset: 16, as: UInt32.self)  // fWide = FALSE
        }
        for path in paths {
            data.append(contentsOf: path.utf8)
            data.append(0)
        }
        data.append(0)
        return Array(data)
    }

    private func isWellFormed(_ bytes: [UInt8]) -> Bool {
        bytes.withUnsafeBufferPointer { buffer in
            DropFilesPayloadValidator.isWellFormedPayload(UnsafeRawBufferPointer(buffer))
        }
    }

    // MARK: - Well-formed payloads

    func testValidatorAcceptsPayloadBuiltLikeTheWriteSide() async {
        let bytes = widePayload(paths: ["C:\\data\\a.txt", "D:\\photos\\b c.png"])
        XCTAssertTrue(isWellFormed(bytes))
    }

    func testValidatorAcceptsZeroFiles() async {
        XCTAssertTrue(isWellFormed(widePayload(paths: [])))
        XCTAssertTrue(isWellFormed(ansiPayload(paths: [])))
    }

    func testValidatorAcceptsAnsiPayload() async {
        XCTAssertTrue(isWellFormed(ansiPayload(paths: ["C:\\data\\a.txt"])))
    }

    func testValidatorAcceptsAnsiPayloadAtOddOffset() async {
        var bytes = ansiPayload(paths: ["C:\\data\\a.txt"])
        bytes.insert(0xA5, at: 20)
        bytes.withUnsafeMutableBytes { raw in
            raw.storeBytes(of: UInt32(21), toByteOffset: 0, as: UInt32.self)
        }

        XCTAssertTrue(isWellFormed(bytes))
    }

    // MARK: - Truncated / undersized blocks

    func testValidatorRejectsTruncatedHeader() async {
        let bytes = widePayload(paths: ["C:\\a.txt"])
        XCTAssertFalse(isWellFormed(Array(bytes.prefix(10))))
        XCTAssertFalse(isWellFormed(Array(bytes.prefix(19))))
    }

    func testValidatorRejectsHeaderOnlyBlock() async {
        // Full 20-byte header but no room for even the empty-list terminator.
        XCTAssertFalse(isWellFormed(Array(widePayload(paths: []).prefix(20))))
    }

    func testValidatorRejectsUnterminatedList() async {
        // Drop the final double-null: the last string's list has no
        // empty-string terminator.
        let bytes = widePayload(paths: ["C:\\a.txt"])
        XCTAssertFalse(isWellFormed(Array(bytes.dropLast(2))))
    }

    func testValidatorRejectsListWithNoTerminatorsAtAll() async {
        var bytes = widePayload(paths: ["C:\\a.txt"])
        // Strip every null byte past the header.
        bytes = Array(bytes.prefix(20)) + bytes.dropFirst(20).filter { $0 != 0 }
        XCTAssertFalse(isWellFormed(bytes))
    }

    func testValidatorRejectsOddByteCountCuttingIntoTerminator() async {
        // Dropping one byte leaves the final code unit halved; the walk must
        // not read past the block.
        let bytes = widePayload(paths: ["C:\\a.txt"])
        XCTAssertEqual(bytes.count % 2, 0)
        XCTAssertFalse(isWellFormed(Array(bytes.dropLast(1))))
    }

    // MARK: - Hostile pFiles offsets

    func testValidatorRejectsZeroPFilesOffset() async {
        XCTAssertFalse(isWellFormed(widePayload(paths: ["C:\\a.txt"], pFiles: 0)))
    }

    func testValidatorRejectsPFilesInsideHeader() async {
        XCTAssertFalse(isWellFormed(widePayload(paths: ["C:\\a.txt"], pFiles: 8)))
    }

    func testValidatorRejectsUnalignedWidePFilesOffsetWithoutTrapping() async {
        XCTAssertFalse(isWellFormed(widePayload(paths: ["C:\\a.txt"], pFiles: 21)))
    }

    func testValidatorRejectsHugePFilesOffset() async {
        XCTAssertFalse(isWellFormed(widePayload(paths: ["C:\\a.txt"], pFiles: 0xFFFF_FFFF)))
        XCTAssertFalse(isWellFormed(widePayload(paths: ["C:\\a.txt"], pFiles: 0x8000_0000)))
    }

    func testValidatorRejectsPFilesExactlyAtEndOfBlock() async {
        let bytes = widePayload(paths: ["C:\\a.txt"])
        XCTAssertFalse(isWellFormed(widePayload(paths: ["C:\\a.txt"], pFiles: UInt32(bytes.count))))
    }

    // MARK: - Garbage blocks

    func testValidatorRejectsAllZeroBlock() async {
        XCTAssertFalse(isWellFormed([UInt8](repeating: 0, count: 64)))
    }

    func testValidatorRejectsAllFFBlock() async {
        XCTAssertFalse(isWellFormed([UInt8](repeating: 0xFF, count: 64)))
    }

    // MARK: - Live-handle validation (own allocations only, no hostile OS input)

    func testHandleValidationFailsClosedOnUndersizedAllocation() async {
        guard let hGlobal = GlobalAlloc(UINT(GMEM_MOVEABLE), SIZE_T(8)) else {
            XCTFail("GlobalAlloc failed")
            return
        }
        defer { GlobalFree(hGlobal) }
        XCTAssertFalse(DropFilesPayloadValidator.hasWellFormedPayload(hGlobal))
    }

    func testHandleValidationAcceptsWellFormedAllocation() async {
        let bytes = widePayload(paths: ["C:\\a.txt"])
        guard let hGlobal = GlobalAlloc(UINT(GMEM_MOVEABLE), SIZE_T(bytes.count)) else {
            XCTFail("GlobalAlloc failed")
            return
        }
        defer { GlobalFree(hGlobal) }
        guard let ptr = GlobalLock(hGlobal) else {
            XCTFail("GlobalLock failed")
            return
        }
        bytes.withUnsafeBufferPointer { source in
            ptr.bindMemory(to: UInt8.self, capacity: bytes.count)
                .initialize(from: source.baseAddress!, count: bytes.count)
        }
        GlobalUnlock(hGlobal)
        XCTAssertTrue(DropFilesPayloadValidator.hasWellFormedPayload(hGlobal))
    }

    // MARK: - Bounded clipboard text decode

    @MainActor
    private static func decode(_ units: [UTF16.CodeUnit]) -> String {
        units.withUnsafeBufferPointer { buffer in
            ClipboardManager.decodeNullTerminatedUTF16(buffer)
        }
    }

    private func decodeOnMainActor(_ units: [UTF16.CodeUnit]) async -> String {
        await MainActor.run { Self.decode(units) }
    }

    func testDecodeToleratesMissingNullTerminator() async {
        // A CF_UNICODETEXT block without a terminator must decode in full
        // instead of scanning past the allocation.
        let decoded = await decodeOnMainActor(Array("hello".utf16))
        XCTAssertEqual(decoded, "hello")
    }

    func testDecodeStopsAtEmbeddedNull() async {
        var units = Array("ab".utf16)
        units.append(0)
        units.append(contentsOf: Array("cd".utf16))
        let decoded = await decodeOnMainActor(units)
        XCTAssertEqual(decoded, "ab")
    }

    func testDecodeHandlesEmptyBuffer() async {
        let decoded = await decodeOnMainActor([])
        XCTAssertEqual(decoded, "")
    }

    func testDecodeHandlesUnpairedSurrogatesWithoutCrashing() async {
        // String(decoding:as:) substitutes the replacement character; the
        // contract is survival, not fidelity.
        let decoded = await decodeOnMainActor([0xD800, 0x41, 0xDC00])
        XCTAssertEqual(decoded.count, 3)
    }
}
