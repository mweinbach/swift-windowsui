import Foundation
import SwiftWindowsCore
import SwiftWindowsGraphics
import SwiftWindowsUI
import Testing

@testable import WinSwiftUI

// MARK: - Render to Bitmap

@MainActor
func renderNodeToBitmap(
    _ node: ViewNode,
    size: IntSize = IntSize(width: 100, height: 100),
    clearColor: Color = .black,
    displayScale: Double = 1
) -> BitmapSurface {
    let scene = ScenePainter.paint(
        root: node,
        clearColor: clearColor,
        surfaceSize: Size(width: Double(size.width), height: Double(size.height)),
        displayScale: displayScale
    )
    return GPUIRawSceneRasterizer.rasterize(scene, size: size)
}

@MainActor
func renderViewToBitmap<V: View>(
    _ view: V,
    size: IntSize = IntSize(width: 100, height: 100),
    clearColor: Color = Color(red: 0.07, green: 0.10, blue: 0.14, alpha: 1.0),
    displayScale: Double = 1
) -> BitmapSurface {
    let snapshot = WinSwiftUIRendererSnapshotter.snapshot(
        of: view,
        size: size,
        displayScale: displayScale,
        clearColor: clearColor
    )
    return GPUIRawSceneRasterizer.rasterize(snapshot.scene, size: snapshot.size)
}

// MARK: - Pixel Extraction

extension BitmapSurface {
    func pixelOffset(x: Int, y: Int) -> Int {
        (y * Int(width) + x) * 4
    }

    func colorAt(x: Int, y: Int) -> Color? {
        guard x >= 0, y >= 0, x < Int(width), y < Int(height) else {
            return nil
        }
        let offset = pixelOffset(x: x, y: y)
        guard offset + 3 < pixels.count else { return nil }
        return Color(
            red: Float(pixels[offset + 2]) / 255,
            green: Float(pixels[offset + 1]) / 255,
            blue: Float(pixels[offset]) / 255,
            alpha: Float(pixels[offset + 3]) / 255
        )
    }
}

// MARK: - Pixel Assertions

@MainActor
func assertPixel(
    _ bitmap: BitmapSurface,
    x: Int,
    y: Int,
    color expected: Color,
    tolerance: Float = 2 / 255
) {
    guard let actual = bitmap.colorAt(x: x, y: y) else {
        Issue.record("Coordinate (\(x), \(y)) out of bounds")
        return
    }
    let dr = abs(actual.red - expected.red)
    let dg = abs(actual.green - expected.green)
    let db = abs(actual.blue - expected.blue)
    let da = abs(actual.alpha - expected.alpha)
    #expect(
        dr <= tolerance && dg <= tolerance && db <= tolerance && da <= tolerance,
        "Pixel (\(x), \(y)) expected \(expected) but got \(actual)")
}

@MainActor
func assertRegionColor(
    _ bitmap: BitmapSurface,
    x: Int,
    y: Int,
    width: Int,
    height: Int,
    color expected: Color,
    tolerance: Float = 2 / 255
) {
    for py in y..<(y + height) {
        for px in x..<(x + width) {
            assertPixel(bitmap, x: px, y: py, color: expected, tolerance: tolerance)
        }
    }
}

@MainActor
func assertAllPixels(
    _ bitmap: BitmapSurface,
    color expected: Color,
    tolerance: Float = 2 / 255
) {
    let w = Int(bitmap.width)
    let h = Int(bitmap.height)
    for py in 0..<h {
        for px in 0..<w {
            assertPixel(bitmap, x: px, y: py, color: expected, tolerance: tolerance)
        }
    }
}

// MARK: - Reference Images

@MainActor
func referenceImageURL(name: String) -> URL {
    let dir = URL(fileURLWithPath: #file)
        .deletingLastPathComponent()
        .appendingPathComponent("ReferenceImages")
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir.appendingPathComponent("\(name).bmp")
}

@MainActor
func saveReferenceImage(_ bitmap: BitmapSurface, name: String) throws {
    let url = referenceImageURL(name: name)
    try writeBGRA32BMP(bitmap, to: url)
}

@MainActor
func loadReferenceImage(name: String) -> BitmapSurface? {
    let url = referenceImageURL(name: name)
    guard FileManager.default.fileExists(atPath: url.path) else { return nil }
    guard let data = try? Data(contentsOf: url) else { return nil }
    guard data.count >= 54 else { return nil }

    let width = Int32(littleEndian: data.withUnsafeBytes { $0.load(fromByteOffset: 18, as: Int32.self) })
    let height = Int32(littleEndian: data.withUnsafeBytes { $0.load(fromByteOffset: 22, as: Int32.self) })
    let rowBytes = Int(width) * 4
    let pixelOffset = Int(data.withUnsafeBytes { $0.load(fromByteOffset: 10, as: UInt32.self) })
    let expectedSize = rowBytes * Int(height)

    guard data.count >= pixelOffset + expectedSize else { return nil }
    var pixels = Data()
    pixels.reserveCapacity(expectedSize)
    for row in stride(from: Int(height) - 1, through: 0, by: -1) {
        let srcOffset = pixelOffset + row * rowBytes
        pixels.append(data[srcOffset..<(srcOffset + rowBytes)])
    }
    return BitmapSurface(width: width, height: height, bytesPerRow: Int32(rowBytes), pixels: pixels)
}

@MainActor
func compareToReference(
    _ bitmap: BitmapSurface,
    name: String,
    tolerance: Float = 2 / 255,
    recordMissingReference: Bool = true,
) {
    if let reference = loadReferenceImage(name: name) {
        let w = min(Int(bitmap.width), Int(reference.width))
        let h = min(Int(bitmap.height), Int(reference.height))
        for y in 0..<h {
            for x in 0..<w {
                guard let actual = bitmap.colorAt(x: x, y: y),
                    let expected = reference.colorAt(x: x, y: y)
                else { continue }
                let dr = abs(actual.red - expected.red)
                let dg = abs(actual.green - expected.green)
                let db = abs(actual.blue - expected.blue)
                let da = abs(actual.alpha - expected.alpha)
                #expect(
                    dr <= tolerance && dg <= tolerance && db <= tolerance && da <= tolerance,
                    "Pixel (\(x), \(y)) differs from reference \(name)")
            }
        }
    } else if recordMissingReference {
        try? saveReferenceImage(bitmap, name: name)
        Issue.record("Recorded new reference image: \(name).bmp")
    } else {
        Issue.record("Missing reference image: \(name).bmp")
    }
}

// MARK: - BMP I/O (copied from snapshot tool for test reuse)

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

    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)

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

extension Data {
    fileprivate mutating func appendUInt16LE(_ value: UInt16) {
        append(contentsOf: [UInt8(value & 0xff), UInt8((value >> 8) & 0xff)])
    }
    fileprivate mutating func appendUInt32LE(_ value: UInt32) {
        append(contentsOf: [
            UInt8(value & 0xff),
            UInt8((value >> 8) & 0xff),
            UInt8((value >> 16) & 0xff),
            UInt8((value >> 24) & 0xff),
        ])
    }
    fileprivate mutating func appendInt32LE(_ value: Int32) {
        appendUInt32LE(UInt32(bitPattern: value))
    }
}
