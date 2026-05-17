import Foundation

#if os(Windows)
    import WinSDK
#endif

func defaultOpenURL(_ url: URL) -> Bool {
    #if os(Windows)
        let urlString = url.absoluteString
        return withWideString("open") { operation in
            withWideString(urlString) { target in
                let result = ShellExecuteW(nil, operation, target, nil, nil, SW_SHOWNORMAL)
                return Int(bitPattern: result) > 32
            }
        }
    #else
        return false
    #endif
}
#if os(Windows)
    private func withWideString<Result>(_ string: String, _ body: (UnsafePointer<WCHAR>) -> Result) -> Result {
        var wide = Array(string.utf16)
        wide.append(0)
        return wide.withUnsafeBufferPointer { buffer in
            body(buffer.baseAddress!)
        }
    }
#endif
