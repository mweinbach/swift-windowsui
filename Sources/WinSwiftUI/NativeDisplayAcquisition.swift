import Foundation
import SwiftWindowsGraphics
import WinSDK

struct NativeDisplayAcquisitionConfiguration: Equatable, Sendable {
    let outputPath: String

    enum Failure: Error { case invalidArguments, invalidPath, clockUnavailable }

    /// No environment variable, inferred benchmark mode, or automatic opt-in.
    /// Accept one drive-qualified absolute path, not a device/UNC namespace;
    /// this is not a claim that the selected drive is a physical local disk.
    static func parse(arguments: [String]) throws -> Self? {
        let flag = "--native-display-journal"
        let indices = arguments.indices.filter { arguments[$0] == flag }
        guard !arguments.contains(where: { $0.hasPrefix(flag + "=") }) else { throw Failure.invalidArguments }
        guard !indices.isEmpty else { return nil }
        guard indices.count == 1, let index = indices.first, index + 1 < arguments.count else {
            throw Failure.invalidArguments
        }
        let path = arguments[index + 1]
        guard (4...4000).contains(path.utf16.count) else { throw Failure.invalidPath }
        let units = Array(path.utf16)
        guard !units.contains(0),
            (65...90).contains(units[0]) || (97...122).contains(units[0]),
            units[1] == 58, units[2] == 92 || units[2] == 47
        else { throw Failure.invalidPath }
        let components = path.dropFirst(3).split(whereSeparator: { $0 == "\\" || $0 == "/" })
        guard !components.isEmpty, path.last != "\\", path.last != "/" else { throw Failure.invalidPath }
        for component in components {
            guard component != ".", component != "..", component.last != ".", component.last != " ",
                !component.contains(where: { ":*?\"<>|".contains($0) || $0.asciiValue.map { $0 < 32 } == true })
            else { throw Failure.invalidPath }
            let stem = component.split(separator: ".", omittingEmptySubsequences: false)[0].uppercased()
            let deviceNames = ["CON", "PRN", "AUX", "NUL", "CONIN$", "CONOUT$"]
            let deviceDigits = ["1", "2", "3", "4", "5", "6", "7", "8", "9", "¹", "²", "³"]
            let numberedDevice = deviceDigits.contains { stem == "COM\($0)" || stem == "LPT\($0)" }
            guard !deviceNames.contains(stem), !numberedDevice else { throw Failure.invalidPath }
        }
        return Self(outputPath: path)
    }
}

/// Only the native composition root creates and retires this session. The
/// recorder can cross A/N; neither this session nor its writer crosses into a
/// command, renderer, callback queue, or native resource owner.
@MainActor
final class NativeDisplayAcquisitionSession {
    let recorder: NativeDisplayAcquisition.Recorder
    private let outputPath: String
    private var retired = false

    init(recorder: NativeDisplayAcquisition.Recorder, outputPath: String) {
        self.recorder = recorder
        self.outputPath = outputPath
    }

    static func makeIfRequested(arguments: [String]) throws -> NativeDisplayAcquisitionSession? {
        guard let configuration = try NativeDisplayAcquisitionConfiguration.parse(arguments: arguments) else {
            return nil
        }
        var frequency = LARGE_INTEGER()
        guard QueryPerformanceFrequency(&frequency), frequency.QuadPart > 0 else {
            throw NativeDisplayAcquisitionConfiguration.Failure.clockUnavailable
        }
        let processID = GetCurrentProcessId()
        let recorder = try NativeDisplayAcquisition.Recorder(
            sessionID: UUID(), processID: processID, frequency: UInt64(frequency.QuadPart)
        ) {
            var counter = LARGE_INTEGER()
            guard QueryPerformanceCounter(&counter), counter.QuadPart >= 0 else { return nil }
            let threadID = GetCurrentThreadId()
            guard threadID != 0 else { return nil }
            return NativeDisplayAcquisition.Sample(
                ticks: UInt64(counter.QuadPart), processID: GetCurrentProcessId(), threadID: threadID)
        }
        return NativeDisplayAcquisitionSession(recorder: recorder, outputPath: configuration.outputPath)
    }

    static func forHost(
        _ recorder: NativeDisplayAcquisition.Recorder?, isPrimary: Bool, usesNativePresentation: Bool
    ) -> NativeDisplayAcquisition.Recorder? {
        isPrimary && usesNativePresentation ? recorder : nil
    }

    /// False is deliberately not a cleanup attempt: a runNative throw may
    /// precede a join while native owners still hold resources. Do not snapshot
    /// or write in that case, even when the recorder currently looks empty.
    /// The writer is synchronous, nonescaping, and called at most once.
    @discardableResult
    func retire(successfullyJoined: Bool) -> String? {
        retire(successfullyJoined: successfullyJoined, write: Self.writeJournal)
    }

    @discardableResult
    func retire(
        successfullyJoined: Bool, write: (String, Data) throws -> Void
    ) -> String? {
        guard !retired else { return nil }
        retired = true
        guard successfullyJoined else {
            recorder.abandon()
            return nil
        }
        do {
            let snapshot = try recorder.finishAfterDrain()
            let data = try snapshot.encoded()
            try write(outputPath, data)
            return nil
        } catch {
            recorder.abandon()
            return "Native display journal was not published: \(error)"
        }
    }

    private struct WriteFailure: Error {
        let operation: String
        let code: DWORD
    }

    /// A new temporary sibling is written only after all producers have joined.
    /// A same-directory move without replace publishes the complete document;
    /// an existing requested path is never truncated. Any temporary cleanup is
    /// limited to the one file created by this invocation.
    private static func writeJournal(path: String, data: Data) throws {
        guard data.count <= NativeDisplayAcquisition.maximumEncodedBytes else {
            throw NativeDisplayAcquisition.CaptureError.encodedByteLimit
        }
        let temporary = path + "." + UUID().uuidString + ".partial"
        let temporaryUTF16 = Array(temporary.utf16) + [0]
        let handle = temporaryUTF16.withUnsafeBufferPointer {
            CreateFileW(
                $0.baseAddress, DWORD(GENERIC_WRITE), 0, nil, DWORD(CREATE_NEW), DWORD(FILE_ATTRIBUTE_NORMAL), nil)
        }
        guard let handle, handle != INVALID_HANDLE_VALUE else {
            let code = GetLastError()
            throw WriteFailure(operation: "CreateFileW", code: code)
        }
        var handleClosed = false
        var published = false
        defer {
            if !handleClosed { _ = CloseHandle(handle) }
            if !published { temporaryUTF16.withUnsafeBufferPointer { _ = DeleteFileW($0.baseAddress) } }
        }
        guard GetFileType(handle) == DWORD(FILE_TYPE_DISK) else {
            throw WriteFailure(operation: "Journal destination is not a file", code: 0)
        }
        var written: DWORD = 0
        let success = data.withUnsafeBytes { buffer in
            WriteFile(handle, buffer.baseAddress, DWORD(data.count), &written, nil)
        }
        guard success else {
            let code = GetLastError()
            throw WriteFailure(operation: "WriteFile", code: code)
        }
        guard written == DWORD(data.count) else { throw WriteFailure(operation: "WriteFile short write", code: 0) }
        handleClosed = true
        guard CloseHandle(handle) else {
            let code = GetLastError()
            throw WriteFailure(operation: "CloseHandle", code: code)
        }
        let destinationUTF16 = Array(path.utf16) + [0]
        let moved = temporaryUTF16.withUnsafeBufferPointer { source in
            destinationUTF16.withUnsafeBufferPointer { destination in
                MoveFileExW(source.baseAddress, destination.baseAddress, 0)
            }
        }
        guard moved else {
            let code = GetLastError()
            throw WriteFailure(operation: "MoveFileExW", code: code)
        }
        published = true
    }
}
