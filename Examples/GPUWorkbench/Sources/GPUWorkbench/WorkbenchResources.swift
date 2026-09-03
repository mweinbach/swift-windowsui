import Foundation

enum WorkbenchResources {
    struct DeploymentReceipt: Encodable {
        let check = "GPUWorkbench.deployment.v1"
        let executable: String
        let bundle: String
        let image: String
        let imageByteCount: Int
        let checksNativePresentation = false
    }

    static func checkDeployment() throws -> DeploymentReceipt {
        guard let executable = Bundle.main.executableURL else {
            throw WorkbenchError.message("Cannot locate the running executable.")
        }
        let executableURL = executable.resolvingSymlinksInPath().standardizedFileURL
        let bundleURL = Bundle.module.bundleURL.resolvingSymlinksInPath().standardizedFileURL
        let packageDirectory = executableURL.deletingLastPathComponent()
        guard
            bundleURL.deletingLastPathComponent().path.caseInsensitiveCompare(packageDirectory.path)
                == .orderedSame
        else {
            throw WorkbenchError.message(
                "Resource bundle resolved outside the executable directory: \(bundleURL.path)")
        }
        guard let imageURL = Bundle.module.url(forResource: "gpu-workbench-mark", withExtension: "png")
        else { throw WorkbenchError.message("Missing bundled gpu-workbench-mark.png.") }
        let image = imageURL.resolvingSymlinksInPath().standardizedFileURL
        guard image.deletingLastPathComponent() == bundleURL else {
            throw WorkbenchError.message("Image resolved outside the packaged resource bundle.")
        }
        let data = try Data(contentsOf: image)
        guard data.starts(with: [137, 80, 78, 71, 13, 10, 26, 10]) else {
            throw WorkbenchError.message("Bundled image does not have a PNG signature.")
        }
        // Byte identity is checked by the staging manifest. This signature and
        // path check is not image decoding or proof that a GPU drew the image.
        return DeploymentReceipt(
            executable: executableURL.path, bundle: bundleURL.path,
            image: image.path, imageByteCount: data.count)
    }
}
