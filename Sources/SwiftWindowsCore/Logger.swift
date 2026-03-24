// Gap 8: Render Logger — replaces silent fallbacks with observable logging

public enum LogLevel: Int, Comparable, Sendable {
    case debug = 0
    case info = 1
    case warning = 2
    case error = 3

    public static func < (lhs: LogLevel, rhs: LogLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

public enum RenderLogger {
    @MainActor public static var minimumLevel: LogLevel = .warning
    @MainActor public static var handler: (@Sendable (LogLevel, String, String, Int) -> Void)?

    @MainActor
    public static func log(
        _ level: LogLevel,
        _ message: @autoclosure () -> String,
        file: String = #fileID,
        line: Int = #line
    ) {
        guard level >= minimumLevel else { return }
        let msg = message()
        handler?(level, msg, file, line)
        #if DEBUG
        print("[\(level)] \(file):\(line) \(msg)")
        #endif
    }
}
