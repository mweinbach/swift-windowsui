import Foundation
import SwiftWindowsGraphics
import SwiftWindowsRendererD3D11
import WinSwiftUI

@main
enum GPUWorkbenchMain {
    @MainActor
    static func main() throws {
        if Array(CommandLine.arguments.dropFirst()) == ["--check-deployment"] {
            let receipt = try WorkbenchResources.checkDeployment()
            let data = try JSONEncoder().encode(receipt)
            print(String(decoding: data, as: UTF8.self))
            return
        }
        WorkbenchApplication.main()
    }
}

@MainActor
struct WorkbenchApplication: App {
    private let model: WorkbenchModel

    init() {
        model = WorkbenchModel(settingsURL: WorkbenchModel.applicationSettingsURL)
    }

    static func renderBackendFactory() -> RenderBackendFactory {
        D3D11RenderBackendFactory()
    }

    var body: some Scene {
        WindowGroup("GPU Workbench") {
            WorkbenchRoot(model: model)
        }
    }
}
