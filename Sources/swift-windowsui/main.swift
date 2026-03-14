import SwiftWindowsUI
import SwiftWindowsRendererD3D11

@main
struct SwiftWindowsUIDemo {
    static func main() {
        do {
            _ = try FoundationApp(renderer: D3D11Renderer()).run()
        } catch {
            print("Failed to start Swift Windows UI foundation: \(error)")
        }
    }
}
