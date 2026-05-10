import Foundation
import SwiftWindowsCore
import SwiftWindowsDemo
import SwiftWindowsGraphics
import WinSwiftUI

@main
struct SwiftWindowsUISnapshotTool {
    @MainActor
    static func main() throws {
        let options = try SnapshotOptions.parse(CommandLine.arguments.dropFirst())
        let model = DemoDashboardModel()
        let view = DemoRootView(model: model)
        let snapshot = WinSwiftUIRendererSnapshotter.snapshot(
            of: view,
            size: IntSize(width: Int32(options.width), height: Int32(options.height)),
            displayScale: options.displayScale
        )

        let bitmap: BitmapSurface
        switch options.mode {
        case .scene:
            bitmap = GPUIRawSceneRasterizer.rasterize(snapshot.scene, size: snapshot.size)
        case .frame:
            bitmap = GPUIRawSceneRasterizer.rasterize(snapshot.frame, size: snapshot.size)
        }

        try writeBGRA32BMP(bitmap, to: options.outputURL)
        print("Snapshot=\(options.outputURL.path)")
        print("Mode=\(options.mode.rawValue)")
        print("Size=\(bitmap.width)x\(bitmap.height)")
        print("ScenePrimitives=\(snapshot.scene.primitiveCount)")
        print("FrameCommands=\(snapshot.frame.commands.count)")
    }
}

private struct SnapshotOptions {
    var outputURL: URL
    var width: Int
    var height: Int
    var displayScale: Double
    var mode: SnapshotMode

    static func parse<S: Sequence>(_ arguments: S) throws -> SnapshotOptions where S.Element == String {
        var output = URL(fileURLWithPath: "artifacts/demo-screenshot.bmp")
        var width = 1280
        var height = 720
        var displayScale = 1.0
        var mode = SnapshotMode.scene

        var iterator = Array(arguments).makeIterator()
        while let argument = iterator.next() {
            switch argument {
            case "--output", "-o":
                output = URL(fileURLWithPath: try requireValue(after: argument, from: &iterator))
            case "--width":
                width = try parsePositiveInt(try requireValue(after: argument, from: &iterator), name: argument)
            case "--height":
                height = try parsePositiveInt(try requireValue(after: argument, from: &iterator), name: argument)
            case "--scale":
                displayScale = try parsePositiveDouble(try requireValue(after: argument, from: &iterator), name: argument)
            case "--mode":
                let value = try requireValue(after: argument, from: &iterator)
                guard let parsed = SnapshotMode(rawValue: value) else {
                    throw SnapshotError.invalidArgument("--mode must be scene or frame.")
                }
                mode = parsed
            case "--help", "-h":
                throw SnapshotError.help
            default:
                throw SnapshotError.invalidArgument("Unknown argument: \(argument)")
            }
        }

        if output.pathExtension.lowercased() != "bmp" {
            output.deletePathExtension()
            output.appendPathExtension("bmp")
        }

        return SnapshotOptions(outputURL: output, width: width, height: height, displayScale: displayScale, mode: mode)
    }

    private static func requireValue(after argument: String, from iterator: inout IndexingIterator<[String]>) throws -> String {
        guard let value = iterator.next(), !value.hasPrefix("--") else {
            throw SnapshotError.invalidArgument("Missing value after \(argument).")
        }
        return value
    }

    private static func parsePositiveInt(_ value: String, name: String) throws -> Int {
        guard let parsed = Int(value), parsed > 0 else {
            throw SnapshotError.invalidArgument("\(name) must be a positive integer.")
        }
        return parsed
    }

    private static func parsePositiveDouble(_ value: String, name: String) throws -> Double {
        guard let parsed = Double(value), parsed > 0 else {
            throw SnapshotError.invalidArgument("\(name) must be a positive number.")
        }
        return parsed
    }
}

private enum SnapshotMode: String {
    case scene
    case frame
}

private enum SnapshotError: Error, CustomStringConvertible {
    case help
    case invalidArgument(String)

    var description: String {
        switch self {
        case .help:
            return """
            Usage: swift-windowsui-snapshot [--output path.bmp] [--width px] [--height px] [--scale factor] [--mode scene|frame]
            """
        case .invalidArgument(let message):
            return message
        }
    }
}

private func writeBGRA32BMP(_ bitmap: BitmapSurface, to url: URL) throws {
    let width = max(1, Int(bitmap.width))
    let height = max(1, Int(bitmap.height))
    let bytesPerPixel = 4
    let rowBytes = width * bytesPerPixel
    let sourceBytesPerRow = max(rowBytes, Int(bitmap.bytesPerRow))
    let pixelDataSize = rowBytes * height
    let fileHeaderSize = 14
    let dibHeaderSize = 40
    let pixelOffset = fileHeaderSize + dibHeaderSize
    let fileSize = pixelOffset + pixelDataSize

    try FileManager.default.createDirectory(
        at: url.deletingLastPathComponent(),
        withIntermediateDirectories: true
    )

    var data = Data()
    data.reserveCapacity(fileSize)
    data.append(contentsOf: [0x42, 0x4d])
    data.appendUInt32LE(UInt32(fileSize))
    data.appendUInt16LE(0)
    data.appendUInt16LE(0)
    data.appendUInt32LE(UInt32(pixelOffset))
    data.appendUInt32LE(UInt32(dibHeaderSize))
    data.appendInt32LE(Int32(width))
    data.appendInt32LE(Int32(height))
    data.appendUInt16LE(1)
    data.appendUInt16LE(32)
    data.appendUInt32LE(0)
    data.appendUInt32LE(UInt32(pixelDataSize))
    data.appendInt32LE(2835)
    data.appendInt32LE(2835)
    data.appendUInt32LE(0)
    data.appendUInt32LE(0)

    for row in stride(from: height - 1, through: 0, by: -1) {
        let offset = row * sourceBytesPerRow
        let end = offset + rowBytes
        if end <= bitmap.pixels.count {
            data.append(bitmap.pixels[offset..<end])
        } else {
            data.append(contentsOf: Array(repeating: 0, count: rowBytes))
        }
    }

    try data.write(to: url, options: .atomic)
}

private extension Data {
    mutating func appendUInt16LE(_ value: UInt16) {
        append(contentsOf: [UInt8(value & 0xff), UInt8((value >> 8) & 0xff)])
    }

    mutating func appendUInt32LE(_ value: UInt32) {
        append(contentsOf: [
            UInt8(value & 0xff),
            UInt8((value >> 8) & 0xff),
            UInt8((value >> 16) & 0xff),
            UInt8((value >> 24) & 0xff),
        ])
    }

    mutating func appendInt32LE(_ value: Int32) {
        appendUInt32LE(UInt32(bitPattern: value))
    }
}
