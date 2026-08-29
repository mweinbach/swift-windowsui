import Foundation
import SwiftWindowsCore
import WinSDK

/// Inputs copied before leaving the UI actor. Native pointers and buffers are
/// created only when the owning native window executes the command.
package enum NativeDialogRequest: Sendable {
    case openFile(
        allowedExtensions: [String]?, allowsMultipleSelection: Bool,
        defaultDirectory: URL?, title: String?)
    case saveFile(
        defaultFilename: String?, allowedExtensions: [String]?,
        defaultDirectory: URL?, title: String?)
    case color(initial: Color)
    case recycleFiles([URL])
    case openURL(operation: String, target: String)

    var validationFailure: NativeDialogFailure? {
        if case .openURL(let operation, let target) = self {
            guard !operation.isEmpty, !target.isEmpty,
                [operation, target].allSatisfy({ value in
                    value.unicodeScalars.allSatisfy { !CharacterSet.controlCharacters.contains($0) }
                })
            else { return .invalidShellTarget }
            return nil
        }
        guard case .recycleFiles(let urls) = self else { return nil }
        guard !urls.isEmpty else { return .invalidFileURL }
        for url in urls {
            guard url.isFileURL, !url.path(percentEncoded: false).utf16.contains(0) else {
                return .invalidFileURL
            }
            // Foundation's filesystem path drops a URL authority. Native UNC
            // file URLs carry their server/share in the path instead.
            if let host = url.host(percentEncoded: true), !host.isEmpty, host.lowercased() != "localhost" {
                return .invalidFileURL
            }
        }
        return nil
    }
}

package enum NativeDialogFailure: Error, LocalizedError, Equatable, Sendable {
    case ownerUnavailable
    case native(operation: String, code: UInt32)
    case invalidSelection
    case invalidFileURL
    case invalidShellTarget
    case operationAborted
    case unexpectedResult
    case transport(NativeWindowOwnerFailure)

    package var errorDescription: String? {
        switch self {
        case .ownerUnavailable:
            return "The window requesting this dialog is no longer available."
        case .native(let operation, let code):
            return "Windows could not complete \(operation) (error \(code))."
        case .invalidSelection:
            return "The dialog returned an invalid selection."
        case .invalidFileURL:
            return "Every recycle-bin item must be a valid filesystem URL."
        case .invalidShellTarget:
            return "The shell request must contain a valid operation and target."
        case .operationAborted:
            return "Windows did not complete every requested recycle-bin operation."
        case .unexpectedResult:
            return "The native dialog returned a result for a different request."
        case .transport(let failure):
            return "The native dialog owner could not complete the request: \(failure)."
        }
    }

    /// Preserve the established file-dialog error surface for its callers.
    var fileDialogError: Error {
        switch self {
        case .ownerUnavailable: return FileDialogError.ownerUnavailable
        case .native(_, let code): return FileDialogError.nativeFailure(code)
        case .invalidSelection: return FileDialogError.invalidSelection
        default: return self
        }
    }
}

package enum NativeDialogResponse: Sendable {
    case selectedFiles([URL])
    case selectedColor(Color)
    case recycled
    case openedURL
    case cancelled
    case failed(NativeDialogFailure)
    /// Actor-side delivery was revoked. This is not a native cancellation.
    case revoked

    package static func openURLResult(_ rawResult: UInt) -> NativeDialogResponse {
        guard rawResult > 32 else {
            return .failed(.native(operation: "ShellExecuteW", code: UInt32(rawResult)))
        }
        return .openedURL
    }
}

/// The production executor has no actor state. A value-only injected executor
/// lets tests exercise command ownership without opening a window or dialog.
package struct NativeDialogExecutor: Sendable {
    let perform: @Sendable (NativeDialogRequest, NativeWindowHandle) -> NativeDialogResponse

    package init(
        perform: @escaping @Sendable (NativeDialogRequest, NativeWindowHandle) -> NativeDialogResponse
    ) {
        self.perform = perform
    }

    package static let live = NativeDialogExecutor { request, handle in
        guard let owner = HWND(bitPattern: Int(bitPattern: handle.rawValue)) else {
            return .failed(.ownerUnavailable)
        }
        switch request {
        case .openFile(let extensions, let multiple, let directory, let title):
            return Win32NativeDialogOperations.fileDialog(
                isSave: false, defaultFilename: nil, allowedExtensions: extensions,
                allowsMultipleSelection: multiple, defaultDirectory: directory,
                title: title, owner: owner)
        case .saveFile(let filename, let extensions, let directory, let title):
            return Win32NativeDialogOperations.fileDialog(
                isSave: true, defaultFilename: filename, allowedExtensions: extensions,
                allowsMultipleSelection: false, defaultDirectory: directory,
                title: title, owner: owner)
        case .color(let initial):
            return Win32NativeDialogOperations.colorDialog(initial: initial, owner: owner)
        case .recycleFiles(let urls):
            return Win32NativeDialogOperations.recycleFiles(urls, owner: owner)
        case .openURL(let operation, let target):
            return Win32NativeDialogOperations.openURL(operation: operation, target: target, owner: owner)
        }
    }
}

package struct NativeDialogCommand: NativeWindowOwnerCommand {
    package let windowKey: NativeWindowKey
    package let requestID: NativeWindowRequestID
    let request: NativeDialogRequest
    let executor: NativeDialogExecutor
    let reply: NativeWindowReply<NativeDialogResponse>
    package var commandReply: NativeWindowCommandReply { reply.commandReply }

    package init(
        windowKey: NativeWindowKey, requestID: NativeWindowRequestID = NativeWindowRequestID(),
        request: NativeDialogRequest, executor: NativeDialogExecutor = .live,
        reply: NativeWindowReply<NativeDialogResponse>
    ) {
        self.windowKey = windowKey
        self.requestID = requestID
        self.request = request
        self.executor = executor
        self.reply = reply
    }

    package func execute(in context: any NativeWindowOwnerContext) throws {
        let surface = context.surface
        guard surface.key == windowKey else {
            reject(.staleWindow)
            return
        }
        guard let handle = surface.descriptor.windowHandle, handle.rawValue != 0 else {
            reply.complete(.success(.failed(.ownerUnavailable)))
            return
        }
        // Validate the whole copied request before any native effect. The
        // legacy path-list builder must not silently submit a valid subset.
        if let failure = request.validationFailure {
            reply.complete(.success(.failed(failure)))
            return
        }
        // The owner defers destruction and nested command delivery until this
        // entire synchronous call, buffer decoding and modal scope unwind.
        let result = context.withNativeModal {
            executor.perform(request, handle)
        }
        reply.complete(.success(result))
    }

    package func reject(_ failure: NativeWindowOwnerFailure) {
        reply.complete(.failure(failure))
    }
}

private enum Win32NativeDialogOperations {
    static func openURL(operation: String, target: String, owner: HWND) -> NativeDialogResponse {
        let operationBuffer = Array(operation.utf16) + [0]
        let targetBuffer = Array(target.utf16) + [0]
        return operationBuffer.withUnsafeBufferPointer { operationPointer in
            targetBuffer.withUnsafeBufferPointer { targetPointer in
                let result = ShellExecuteW(
                    owner, operationPointer.baseAddress, targetPointer.baseAddress, nil, nil, SW_SHOWNORMAL)
                return NativeDialogResponse.openURLResult(UInt(bitPattern: result))
            }
        }
    }

    static func fileDialog(
        isSave: Bool, defaultFilename: String?, allowedExtensions: [String]?,
        allowsMultipleSelection: Bool, defaultDirectory: URL?, title: String?, owner: HWND
    ) -> NativeDialogResponse {
        var buffer = [WCHAR](repeating: 0, count: 4096)
        if let defaultFilename {
            for (index, unit) in defaultFilename.utf16.prefix(buffer.count - 1).enumerated() {
                buffer[index] = unit
            }
        }
        let flags: DWORD
        if isSave {
            flags = DWORD(OFN_OVERWRITEPROMPT | OFN_EXPLORER)
        } else {
            flags =
                DWORD(OFN_FILEMUSTEXIST | OFN_EXPLORER)
                | (allowsMultipleSelection ? DWORD(OFN_ALLOWMULTISELECT) : 0)
        }
        let failure: NativeDialogResponse? = Win32FileDialogProvider.withConfiguredDialog(
            fileBuffer: &buffer, allowedExtensions: allowedExtensions,
            defaultDirectory: defaultDirectory, title: title, flags: flags, ownerHandle: owner
        ) { configuration in
            let accepted = isSave ? GetSaveFileNameW(&configuration) : GetOpenFileNameW(&configuration)
            guard accepted else {
                // The error belongs to this FALSE result. No other call or
                // buffer cleanup may intervene before the sample.
                let code = CommDlgExtendedError()
                return code == 0
                    ? .cancelled
                    : .failed(.native(operation: isSave ? "GetSaveFileNameW" : "GetOpenFileNameW", code: code))
            }
            return nil
        }
        if let failure { return failure }
        let urls = Win32FileDialogProvider.selectedFileURLs(
            from: buffer, allowsMultipleSelection: allowsMultipleSelection)
        guard !urls.isEmpty, !isSave || urls.count == 1 else { return .failed(.invalidSelection) }
        return .selectedFiles(urls)
    }

    static func colorDialog(initial: Color, owner: HWND) -> NativeDialogResponse {
        guard [initial.red, initial.green, initial.blue, initial.alpha].allSatisfy({ $0.isFinite }) else {
            return .failed(.invalidSelection)
        }
        func channel(_ value: Float) -> DWORD {
            DWORD(Int((min(max(value, 0), 1) * 255).rounded()))
        }
        var customColors = [DWORD](repeating: 0x00FF_FFFF, count: 16)
        var chooser = CHOOSECOLORW()
        chooser.lStructSize = DWORD(MemoryLayout<CHOOSECOLORW>.size)
        chooser.hwndOwner = owner
        chooser.rgbResult = channel(initial.red) | (channel(initial.green) << 8) | (channel(initial.blue) << 16)
        chooser.Flags = DWORD(0x0000_0001 | 0x0000_0002)
        return customColors.withUnsafeMutableBufferPointer { buffer in
            chooser.lpCustColors = buffer.baseAddress
            guard ChooseColorW(&chooser) else {
                let code = CommDlgExtendedError()
                return code == 0 ? .cancelled : .failed(.native(operation: "ChooseColorW", code: code))
            }
            return .selectedColor(
                Color(
                    red: Float(chooser.rgbResult & 0xFF) / 255,
                    green: Float((chooser.rgbResult >> 8) & 0xFF) / 255,
                    blue: Float((chooser.rgbResult >> 16) & 0xFF) / 255,
                    alpha: initial.alpha))
        }
    }

    static func recycleFiles(_ urls: [URL], owner: HWND) -> NativeDialogResponse {
        guard let buffer = FileDialogManager.makeRecycleSourceList(urls.map { $0.path }) else {
            return .failed(.invalidSelection)
        }
        return buffer.withUnsafeBufferPointer { source in
            guard let address = source.baseAddress else { return .failed(.invalidSelection) }
            var operation = SHFILEOPSTRUCTW()
            operation.hwnd = owner
            operation.wFunc = UINT(FO_DELETE)
            operation.pFrom = address
            operation.fFlags = FILEOP_FLAGS(UInt16(FOF_ALLOWUNDO | FOF_NOCONFIRMATION))
            let result = SHFileOperationW(&operation)
            guard result == 0 else {
                return .failed(.native(operation: "SHFileOperationW", code: UInt32(bitPattern: result)))
            }
            guard !operation.fAnyOperationsAborted else { return .failed(.operationAborted) }
            return .recycled
        }
    }
}
