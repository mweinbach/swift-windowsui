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
    public var dwriteFactoryCreationSucceeded: Bool

    public init(
        backend: TextBackendKind,
        dwriteLibraryLoaded: Bool,
        dwriteCreateFactoryAvailable: Bool,
        dwriteFactoryCreationSucceeded: Bool
    ) {
        self.backend = backend
        self.dwriteLibraryLoaded = dwriteLibraryLoaded
        self.dwriteCreateFactoryAvailable = dwriteCreateFactoryAvailable
        self.dwriteFactoryCreationSucceeded = dwriteFactoryCreationSucceeded
    }

    public var renderingLabel: String {
        dwriteFactoryCreationSucceeded ? "GDI + DWRITE" : "GDI TEXT"
    }
}

protocol TextLibraryLoading {
    func loadLibrary(named name: String) -> HMODULE?
    func unloadLibrary(_ module: HMODULE)
    func loadSymbol(named name: String, from module: HMODULE) -> FARPROC?
    func createDWriteFactory(from module: HMODULE, iid: UnsafePointer<GUID>) -> (HRESULT, UnsafeMutableRawPointer?)?
    func releaseFactory(_ rawPointer: UnsafeMutableRawPointer)
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

    func createDWriteFactory(from module: HMODULE, iid: UnsafePointer<GUID>) -> (HRESULT, UnsafeMutableRawPointer?)? {
        guard let symbol = loadSymbol(named: "DWriteCreateFactory", from: module) else {
            return nil
        }

        let function = unsafeBitCast(symbol, to: DWriteCreateFactoryProc.self)
        var factoryRaw: UnsafeMutableRawPointer?
        let hr = function(dwriteFactoryTypeShared, iid, &factoryRaw)
        return (hr, factoryRaw)
    }

    func releaseFactory(_ rawPointer: UnsafeMutableRawPointer) {
        releaseIUnknown(rawPointer)
    }
}

@MainActor
public enum TextSystem {
    public static func capabilities() -> TextBackendCapabilities {
        capabilities(loader: Win32TextLibraryLoader())
    }

    static func capabilities(loader: TextLibraryLoading) -> TextBackendCapabilities {
        guard let module = loader.loadLibrary(named: "dwrite.dll") else {
            return TextBackendCapabilities(
                backend: .pixelFont,
                dwriteLibraryLoaded: false,
                dwriteCreateFactoryAvailable: false,
                dwriteFactoryCreationSucceeded: false
            )
        }

        defer { loader.unloadLibrary(module) }

        let hasFactory = loader.loadSymbol(named: "DWriteCreateFactory", from: module) != nil
        guard hasFactory else {
            return TextBackendCapabilities(
                backend: .pixelFont,
                dwriteLibraryLoaded: true,
                dwriteCreateFactoryAvailable: false,
                dwriteFactoryCreationSucceeded: false
            )
        }

        var iid = iidIDWriteFactory
        let factoryResult = withUnsafePointer(to: &iid) { loader.createDWriteFactory(from: module, iid: $0) }
        let didCreateFactory = factoryResult?.0 == sOk && factoryResult?.1 != nil

        if let factoryRaw = factoryResult?.1 {
            loader.releaseFactory(factoryRaw)
        }

        return TextBackendCapabilities(
            backend: didCreateFactory ? .directWriteReady : .pixelFont,
            dwriteLibraryLoaded: true,
            dwriteCreateFactoryAvailable: hasFactory,
            dwriteFactoryCreationSucceeded: didCreateFactory
        )
    }
}

private typealias DWriteCreateFactoryProc = @convention(c) (UINT32, UnsafePointer<GUID>, UnsafeMutablePointer<UnsafeMutableRawPointer?>) -> HRESULT

private let dwriteFactoryTypeShared: UINT32 = 0
private let sOk: HRESULT = 0

private let iidIDWriteFactory: GUID = {
    var guid = GUID()
    guid.Data1 = 0xB859EE5A
    guid.Data2 = 0xD838
    guid.Data3 = 0x4B5B
    guid.Data4 = (0xA2, 0xE8, 0x1A, 0xDC, 0x7D, 0x93, 0xDB, 0x48)
    return guid
}()

private func releaseIUnknown(_ rawPointer: UnsafeMutableRawPointer) {
    let unknown = rawPointer.assumingMemoryBound(to: IUnknown.self)
    _ = unknown.pointee.lpVtbl.pointee.Release(unknown)
}
