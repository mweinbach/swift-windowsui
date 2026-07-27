import Foundation

#if os(Windows)
    import WinSDK
#endif

/// Executes a resolved URL target against the OS shell. The production
/// default is `ShellExecuteOpenURLExecutor`, which calls `ShellExecuteW`;
/// tests inject a fake so nothing is launched from the test runner.
protocol OpenURLShellExecutor {
    func execute(operation: String, target: String) -> Bool
}

#if os(Windows)
    final class ShellExecuteOpenURLExecutor: OpenURLShellExecutor {
        func execute(operation: String, target: String) -> Bool {
            withWideString(operation) { operationWide in
                withWideString(target) { targetWide in
                    let result = ShellExecuteW(nil, operationWide, targetWide, nil, nil, SW_SHOWNORMAL)
                    return Int(bitPattern: result) > 32
                }
            }
        }
    }
#else
    final class ShellExecuteOpenURLExecutor: OpenURLShellExecutor {
        func execute(operation _: String, target _: String) -> Bool { false }
    }
#endif

/// Active shell executor; swap in tests, restore afterwards.
@MainActor
var openURLShellExecutor: OpenURLShellExecutor = ShellExecuteOpenURLExecutor()

@MainActor
func defaultOpenURL(_ url: URL) -> Bool {
    guard let target = shellTarget(for: url) else { return false }
    return openURLShellExecutor.execute(operation: "open", target: target)
}

/// Resolves `url` to the string handed to the shell. `http(s)`, `mailto` and
/// other scheme URLs pass through unchanged; file URLs are converted to a
/// plain filesystem path because `ShellExecuteW` does not reliably resolve
/// `file:` URIs. Returns `nil` for empty or control-character-laden targets
/// so malformed input fails closed instead of reaching the shell.
func shellTarget(for url: URL) -> String? {
    if url.isFileURL {
        var path = url.path
        // Some Foundation builds surface Windows file URLs as "/C:/...";
        // the shell needs the bare "C:/..." form.
        if path.count > 2, path.hasPrefix("/"),
            path[path.index(after: path.startIndex)].isLetter,
            path[path.index(path.startIndex, offsetBy: 2)] == ":"
        {
            path.removeFirst()
        }
        return sanitizedShellTarget(path)
    }
    return sanitizedShellTarget(url.absoluteString)
}

/// Trims whitespace and rejects empty or control-character-laden targets so
/// malformed input fails closed instead of reaching the shell.
func sanitizedShellTarget(_ raw: String) -> String? {
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }
    guard trimmed.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) }) else {
        return nil
    }
    return trimmed
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
