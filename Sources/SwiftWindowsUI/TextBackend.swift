import SwiftWindowsCore
import WinSDK

public enum TextBackendKind: String, Equatable, Sendable {
    case pixelFont
    case directWriteReady

    public var displayName: String {
        switch self {
        case .pixelFont:
            return "PIXEL FONT"
        case .directWriteReady:
            return "DWRITE READY"
        }
    }
}

public struct TextBackendCapabilities: Equatable, Sendable {
    public var backend: TextBackendKind
    public var dwriteLibraryLoaded: Bool
    public var dwriteCreateFactoryAvailable: Bool

    public init(backend: TextBackendKind, dwriteLibraryLoaded: Bool, dwriteCreateFactoryAvailable: Bool) {
        self.backend = backend
        self.dwriteLibraryLoaded = dwriteLibraryLoaded
        self.dwriteCreateFactoryAvailable = dwriteCreateFactoryAvailable
    }
}

protocol TextLibraryLoading {
    func loadLibrary(named name: String) -> HMODULE?
    func unloadLibrary(_ module: HMODULE)
    func loadSymbol(named name: String, from module: HMODULE) -> FARPROC?
}

struct Win32TextLibraryLoader: TextLibraryLoading {
    func loadLibrary(named name: String) -> HMODULE? {
        var wideName = Array(name.utf16)
        wideName.append(0)
        return wideName.withUnsafeBufferPointer { buffer in
            LoadLibraryW(buffer.baseAddress)
        }
    }

    func unloadLibrary(_ module: HMODULE) {
        FreeLibrary(module)
    }

    func loadSymbol(named name: String, from module: HMODULE) -> FARPROC? {
        name.withCString { GetProcAddress(module, $0) }
    }
}

@MainActor
public enum TextSystem {
    public static func capabilities() -> TextBackendCapabilities {
        capabilities(loader: Win32TextLibraryLoader())
    }

    static func capabilities(loader: TextLibraryLoading) -> TextBackendCapabilities {
        guard let module = loader.loadLibrary(named: "dwrite.dll") else {
            return TextBackendCapabilities(backend: .pixelFont, dwriteLibraryLoaded: false, dwriteCreateFactoryAvailable: false)
        }

        defer { loader.unloadLibrary(module) }

        let hasFactory = loader.loadSymbol(named: "DWriteCreateFactory", from: module) != nil
        return TextBackendCapabilities(
            backend: hasFactory ? .directWriteReady : .pixelFont,
            dwriteLibraryLoaded: true,
            dwriteCreateFactoryAvailable: hasFactory
        )
    }
}
