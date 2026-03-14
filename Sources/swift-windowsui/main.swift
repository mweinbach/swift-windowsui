import SwiftWindowsUI

@main
struct SwiftWindowsUIDemo {
    static func main() {
        do {
            _ = try FoundationApp().run()
        } catch {
            print("Failed to start Swift Windows UI foundation: \(error)")
        }
    }
}
