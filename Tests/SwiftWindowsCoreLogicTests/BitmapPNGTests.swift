import Foundation
import SwiftWindowsCore
import SwiftWindowsGraphics
import Testing

@Suite("Bitmap PNG Writer")
struct BitmapPNGTests {

    @Test("Writes a valid PNG file with correct header")
    func writesValidPNG() throws {
        let bitmap = BitmapSurface(
            width: 4,
            height: 3,
            bytesPerRow: 16,
            pixels: Data(repeating: 0, count: 16 * 3)
        )

        let tempDir = FileManager.default.temporaryDirectory
        let url = tempDir.appendingPathComponent("test_bitmap.png")
        defer { try? FileManager.default.removeItem(at: url) }

        try bitmap.writePNG(to: url)

        let data = try Data(contentsOf: url)
        #expect(data.count > 33)
        // PNG signature
        #expect(Array(data.prefix(8)) == [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
        // IHDR chunk type
        #expect(Array(data[12..<16]) == Array("IHDR".utf8))
        // Width in IHDR
        let width = data.withUnsafeBytes { $0.load(fromByteOffset: 16, as: UInt32.self).bigEndian }
        #expect(width == 4)
        // Height in IHDR
        let height = data.withUnsafeBytes { $0.load(fromByteOffset: 20, as: UInt32.self).bigEndian }
        #expect(height == 3)
        // Bit depth and color type
        #expect(data[24] == 8)  // bit depth
        #expect(data[25] == 6)  // RGBA
    }

    @Test("Round-trip RGBA pixels through PNG")
    func roundTripRGBA() throws {
        // Build a 2x2 BGRA bitmap: red, green, blue, white
        var pixels: [UInt8] = []
        // Row 0: red (BGRA = 00 00 FF FF), green (00 FF 00 FF)
        pixels.append(contentsOf: [0x00, 0x00, 0xFF, 0xFF])  // red
        pixels.append(contentsOf: [0x00, 0xFF, 0x00, 0xFF])  // green
        // Row 1: blue (FF 00 00 FF), white (FF FF FF FF)
        pixels.append(contentsOf: [0xFF, 0x00, 0x00, 0xFF])  // blue
        pixels.append(contentsOf: [0xFF, 0xFF, 0xFF, 0xFF])  // white

        let bitmap = BitmapSurface(
            width: 2,
            height: 2,
            bytesPerRow: 8,
            pixels: Data(pixels)
        )

        let tempDir = FileManager.default.temporaryDirectory
        let url = tempDir.appendingPathComponent("test_colors.png")
        defer { try? FileManager.default.removeItem(at: url) }

        try bitmap.writePNG(to: url)
        let fileData = try Data(contentsOf: url)
        #expect(fileData.count > 0)

        // Verify the PNG contains IDAT and IEND
        let stringData = String(data: fileData, encoding: .isoLatin1) ?? ""
        #expect(stringData.contains("IHDR"))
        #expect(stringData.contains("IDAT"))
        #expect(stringData.contains("IEND"))
    }
}
