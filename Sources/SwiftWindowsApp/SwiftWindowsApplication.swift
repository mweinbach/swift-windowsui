import SwiftWindowsUI

@MainActor
public enum SwiftWindowsApplication {
    public static func makeFoundationApp() -> FoundationApp {
        FoundationApp()
    }
}
