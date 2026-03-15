import SwiftWindowsApp

@main
struct SwiftWindowsUIDemo {
    static func main() {
        do {
            _ = try SwiftWindowsApplication.makeFoundationApp().run()
        } catch {
            print("Failed to start Swift Windows UI foundation: \(error)")
        }
    }
}
