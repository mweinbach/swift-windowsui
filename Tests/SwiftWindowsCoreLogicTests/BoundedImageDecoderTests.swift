import CDirect2DInterop
import Foundation
import SwiftWindowsCore
import SwiftWindowsGraphics
import XCTest

@testable import SwiftWindowsUI
@testable import WinSwiftUI

final class BoundedImageDecoderTests: XCTestCase {
    func testNativeAdmissionClearsOutputsBeforeInspectingInvalidInput() {
        var result = SWU_BoundedImageResult(
            pixels: UnsafeMutableRawPointer(bitPattern: 1), width: 3, height: 4,
            bytes_per_row: 12, source_width: 3, source_height: 4)
        XCTAssertEqual(SWU_DecodeBoundedImage(nil, 0, 1, &result), Int32(SWU_BOUNDED_IMAGE_INVALID_DATA))
        assertEmpty(result)
        var byte: UInt8 = 0
        XCTAssertEqual(
            SWU_DecodeBoundedImage(&byte, UInt32(BoundedImageDecoder.maximumEncodedBytes + 1), 1, &result),
            Int32(SWU_BOUNDED_IMAGE_ENCODED_LIMIT))
        assertEmpty(result)
        for edge: UInt32 in [0, 1025, .max] {
            XCTAssertEqual(SWU_DecodeBoundedImage(&byte, 1, edge, &result), Int32(SWU_BOUNDED_IMAGE_OUTPUT_LIMIT))
            assertEmpty(result)
        }
        XCTAssertEqual(
            SWU_DecodeBoundedImageFirstFrame(&byte, UInt32(BoundedImageDecoder.maximumEncodedBytes + 1), &result),
            Int32(SWU_BOUNDED_IMAGE_ENCODED_LIMIT))
        assertEmpty(result)
    }

    func testPNGDecodesRealColorAndExplicitPremultipliedAlpha() async throws {
        let data = MediaImageTestFixtures.png(
            width: 2, height: 1, rgba: [255, 0, 0, 128, 17, 231, 89, 0], declaresSRGB: true)
        let image = try await decode(data)

        XCTAssertEqual(image.bitmap.width, 2)
        XCTAssertEqual(image.bitmap.height, 1)
        XCTAssertEqual(image.bitmap.bytesPerRow, 8)
        XCTAssertEqual(image.bitmap.format, .bgra8Premultiplied)
        XCTAssertEqual(Array(image.bitmap.pixels), [0, 0, 128, 128, 0, 0, 0, 0])
        XCTAssertEqual(image.sourcePixelWidth, 2)
        XCTAssertEqual(image.sourcePixelHeight, 1)
        XCTAssertNoThrow(try image.bitmap.validate())
    }

    func testScalingInterpolatesPremultipliedPixelsWithoutTransparentColorBleed() async throws {
        let data = MediaImageTestFixtures.png(width: 2, height: 1, rgba: [255, 0, 0, 255, 0, 0, 255, 0])
        let image = try await decode(data, edge: 1)
        let bytes = Array(image.bitmap.pixels)

        XCTAssertEqual(image.bitmap.width, 1)
        XCTAssertEqual(image.bitmap.height, 1)
        XCTAssertEqual(bytes.count, 4)
        XCTAssertEqual(bytes[0], 0, "Transparent blue must not contaminate the filtered color.")
        XCTAssertEqual(bytes[1], 0)
        XCTAssertEqual(bytes[2], bytes[3])
        XCTAssertTrue((127...128).contains(Int(bytes[3])))
    }

    func testBMPRealRasterIsDownsampledWithoutUpscalingSmallImages() async throws {
        let data = MediaImageTestFixtures.bmp(width: 30, height: 20, gray: 90)
        let small = try await decode(data, edge: 9)
        XCTAssertEqual(small.bitmap.width, 9)
        XCTAssertEqual(small.bitmap.height, 6)
        XCTAssertEqual(small.bitmap.pixels.count, 9 * 6 * 4)
        XCTAssertTrue(
            Array(small.bitmap.pixels).enumerated().allSatisfy { $0.element == ($0.offset % 4 == 3 ? 255 : 90) })
        let original = try await decode(data, edge: 100)
        XCTAssertEqual(original.bitmap.width, 30)
        XCTAssertEqual(original.bitmap.height, 20)
    }

    func testJPEGAppliesEveryEXIFOrientationToActualPixels() async throws {
        // Six independently encoded constant 8x8 grayscale blocks form a 2x3
        // asymmetric raster. Expected order is a coordinate oracle, not WIC output.
        let orders: [[UInt8]] = [
            [30, 60, 90, 120, 180, 220], [60, 30, 120, 90, 220, 180],
            [220, 180, 120, 90, 60, 30], [180, 220, 90, 120, 30, 60],
            [30, 90, 180, 60, 120, 220], [180, 90, 30, 220, 120, 60],
            [220, 120, 60, 180, 90, 30], [60, 120, 220, 30, 90, 180],
        ]
        for orientation in 1...8 {
            let image = try await decode(MediaImageTestFixtures.jpeg(orientation: UInt16(orientation)))
            let columns = orientation >= 5 ? 3 : 2
            let rows = orientation >= 5 ? 2 : 3
            XCTAssertEqual(image.sourcePixelWidth, columns * 8)
            XCTAssertEqual(image.sourcePixelHeight, rows * 8)
            XCTAssertEqual(image.bitmap.width, Int32(columns * 8))
            XCTAssertEqual(image.bitmap.height, Int32(rows * 8))
            for row in 0..<rows {
                for column in 0..<columns {
                    let index = (row * 8 + 4) * Int(image.bitmap.bytesPerRow) + (column * 8 + 4) * 4
                    let expected = Int(orders[orientation - 1][row * columns + column])
                    for channel in 0..<3 {
                        XCTAssertLessThanOrEqual(abs(Int(image.bitmap.pixels[index + channel]) - expected), 1)
                    }
                    XCTAssertEqual(image.bitmap.pixels[index + 3], 255)
                }
            }
        }
    }

    func testStrictPolicyRejectsBadOrientationAnimationAndOtherFormats() async {
        await assertFailure(.invalidOrientation, data: MediaImageTestFixtures.jpeg(orientation: 9))
        await assertFailure(.unsupportedFrameCount, data: MediaImageTestFixtures.animatedPNG())
        await assertFailure(.unsupportedFrameCount, data: MediaImageTestFixtures.jpeg(multiPicture: true))
        await assertFailure(.unsupportedFormat, data: MediaImageTestFixtures.gif)
    }

    func testEncodedSourcePixelAndOutputLimitsAreIndependent() async {
        await assertFailure(.invalidData, data: Data())
        await assertFailure(.encodedImageTooLarge, data: Data(repeating: 0, count: 8_388_609))
        await assertFailure(
            .sourceImageTooLarge, data: MediaImageTestFixtures.png(width: 4001, height: 4000, rgba: [0, 0, 0, 255]))
        let tiny = MediaImageTestFixtures.png(width: 1, height: 1, rgba: [0, 0, 0, 255])
        for edge in [Int.min, -1, 0, 1025, Int.max] {
            await assertFailure(.invalidPixelDimension, data: tiny, edge: edge)
        }
    }

    func testMalformedAndTruncatedEncodedDataCannotProducePixels() async {
        let png = MediaImageTestFixtures.png(width: 1, height: 1, rgba: [255, 20, 0, 255])
        for data in [Data([0, 1, 2, 3]), Data(png.prefix(12)), Data(png.dropLast())] {
            do {
                _ = try await decode(data)
                XCTFail("Malformed image must not produce a thumbnail.")
            } catch { XCTAssertTrue(error is BoundedImageDecodingError) }
        }
    }

    func testLegacyPolicyPreservesFirstFrameFormatsFullSizeAndStraightAlpha() async throws {
        let gif = try await decodeFirstFrame(MediaImageTestFixtures.gif)
        XCTAssertEqual(gif.bitmap.width, 1)
        XCTAssertEqual(gif.bitmap.height, 1)
        XCTAssertEqual(gif.bitmap.format, .bgra8Straight)
        let large = try await decodeFirstFrame(MediaImageTestFixtures.bmp(width: 1200, height: 2, gray: 71))
        XCTAssertEqual(large.bitmap.width, 1200)
        XCTAssertEqual(large.bitmap.height, 2)
        XCTAssertEqual(large.bitmap.pixels.count, 1200 * 2 * 4)
        let transparent = try await decodeFirstFrame(
            MediaImageTestFixtures.png(width: 1, height: 1, rgba: [255, 0, 0, 128]))
        XCTAssertEqual(Array(transparent.bitmap.pixels), [0, 0, 255, 128])
    }

    func testLegacyPolicyKeepsRawEXIFOrientationAndDoesNotFallbackFromStrict() async throws {
        let data = MediaImageTestFixtures.jpeg(orientation: 6)
        let raw = try await decodeFirstFrame(data)
        XCTAssertEqual(raw.bitmap.width, 16)
        XCTAssertEqual(raw.bitmap.height, 24)
        XCTAssertLessThanOrEqual(abs(Int(raw.bitmap.pixels[0]) - 30), 1)
        let oriented = try await decode(data)
        XCTAssertEqual(oriented.bitmap.width, 24)
        XCTAssertEqual(oriented.bitmap.height, 16)
        await assertFailure(.unsupportedFormat, data: MediaImageTestFixtures.gif)
    }

    func testLegacyPolicyAcceptsTheFirstFrameOfAnActualTwoFrameGIF() async throws {
        let single = try await decodeFirstFrame(MediaImageTestFixtures.gif)
        let multiple = try await decodeFirstFrame(MediaImageTestFixtures.twoFrameGIF)
        XCTAssertEqual(multiple.bitmap, single.bitmap)
    }

    func testLegacyPolicyRejectsEncodedAndDecodedExcessWithoutThumbnailFallback() async {
        for data in [
            Data(repeating: 0, count: 8_388_609),
            MediaImageTestFixtures.png(width: 4001, height: 4000, rgba: [0, 0, 0, 255]),
        ] {
            do {
                _ = try await decodeFirstFrame(data)
                XCTFail("Legacy policy must reject excess input, not silently thumbnail it.")
            } catch {
                XCTAssertTrue(
                    error as? BoundedImageDecodingError == .encodedImageTooLarge
                        || error as? BoundedImageDecodingError == .sourceImageTooLarge)
            }
        }
    }

    func testPreCancelledWorkerDoesNotDecodeOrPublish() async {
        let task = Task.detached {
            withUnsafeCurrentTask { $0?.cancel() }
            return try BoundedImageDecoder.decode(MediaImageTestFixtures.gif)
        }
        do {
            _ = try await task.value
            XCTFail("A pre-cancelled worker must report cancellation before format errors.")
        } catch { XCTAssertTrue(error is CancellationError) }
    }

    @MainActor
    func testPublicDecodedValueUsesExistingRetainedBitmapPathAndOwnsItsBytes() async throws {
        let decoded = try await Task.detached {
            try DecodedImage(data: MediaImageTestFixtures.png(width: 1, height: 1, rgba: [255, 0, 0, 128]))
        }.value
        var externalCopy = decoded.pixelData
        externalCopy[0] = 99
        let runtime = RetainedViewRuntime(root: ViewNode())
        let context = ViewBuildContext(canvasSizeProvider: { Size(width: 20, height: 20) }, invalidateHandler: {})
        let node = decoded.image.makeComponent(context: context).makeNode(runtime: runtime)
        let bitmap = try XCTUnwrap(node.bitmapSurface)
        XCTAssertEqual(bitmap.format, .bgra8Premultiplied)
        XCTAssertEqual(Array(bitmap.pixels), [0, 0, 128, 128])
        XCTAssertEqual(decoded.byteCount, 4)
    }

    private func decode(_ data: Data, edge: Int = 1024) async throws -> BoundedDecodedImage {
        try await Task.detached { try BoundedImageDecoder.decode(data, maximumPixelDimension: edge) }.value
    }

    private func decodeFirstFrame(_ data: Data) async throws -> BoundedDecodedImage {
        try await Task.detached { try BoundedImageDecoder.decodeFirstFrame(data) }.value
    }

    private func assertFailure(_ expected: BoundedImageDecodingError, data: Data, edge: Int = 1024) async {
        do {
            _ = try await decode(data, edge: edge)
            XCTFail("Expected \(expected).")
        } catch { XCTAssertEqual(error as? BoundedImageDecodingError, expected) }
    }

    private func assertEmpty(_ result: SWU_BoundedImageResult) {
        XCTAssertNil(result.pixels)
        XCTAssertEqual(result.width, 0)
        XCTAssertEqual(result.height, 0)
        XCTAssertEqual(result.bytes_per_row, 0)
        XCTAssertEqual(result.source_width, 0)
        XCTAssertEqual(result.source_height, 0)
    }
}

/// Actual, deterministic encoded image fixtures. The tiny JPEG encodes six
/// constant grayscale DCT blocks; it does not depend on a platform encoder.
enum MediaImageTestFixtures {
    // The two-byte LZW payload 44 01 includes complete clear, pixel, and EOI
    // codes; the shorter common one-byte payload ends in the middle of EOI.
    static let gif = Data(base64Encoded: "R0lGODlhAQABAIAAAAAAAP///yH5BAEAAAAALAAAAAABAAEAAAICRAEAOw==")!

    static var twoFrameGIF: Data {
        // Header + logical screen + two-entry global palette occupy 19 bytes.
        // Duplicate the complete control/image block before the final trailer.
        var data = Data(gif.dropLast())
        data.append(gif.subdata(in: 19..<gif.count - 1))
        data.append(0x3B)
        return data
    }

    static func png(width: UInt32, height: UInt32, rgba: [UInt8], declaresSRGB: Bool = false) -> Data {
        var result = Data([137, 80, 78, 71, 13, 10, 26, 10])
        var header = bigEndian(width) + bigEndian(height)
        header += [8, 6, 0, 0, 0]
        result.append(pngChunk("IHDR", header))
        if declaresSRGB { result.append(pngChunk("sRGB", [0])) }
        var raw: [UInt8] = []
        let rowBytes = Int(width) * 4
        // A deliberately mismatched oversized IHDR fixture keeps only its actual
        // one-pixel payload. Its source cap must be checked before CopyPixels.
        if rgba.count == rowBytes * Int(height) {
            for row in 0..<Int(height) { raw += [0] + Array(rgba[row * rowBytes..<(row + 1) * rowBytes]) }
        } else {
            raw = [0] + rgba
        }
        var compressed: [UInt8] = [0x78, 0x01]
        var offset = 0
        while offset < raw.count {
            let count = min(65_535, raw.count - offset)
            compressed.append(offset + count == raw.count ? 1 : 0)
            compressed += littleEndian(UInt16(count)) + littleEndian(~UInt16(count))
            compressed += raw[offset..<offset + count]
            offset += count
        }
        var sum1: UInt32 = 1
        var sum2: UInt32 = 0
        for byte in raw {
            sum1 = (sum1 + UInt32(byte)) % 65_521
            sum2 = (sum2 + sum1) % 65_521
        }
        compressed += bigEndian((sum2 << 16) | sum1)
        result.append(pngChunk("IDAT", compressed))
        result.append(pngChunk("IEND", []))
        return result
    }

    static func animatedPNG() -> Data {
        // Admission marker witness, not a complete APNG animation fixture.
        var data = png(width: 1, height: 1, rgba: [0, 0, 0, 255])
        data.insert(contentsOf: pngChunk("acTL", bigEndian(2) + bigEndian(0)), at: 33)
        return data
    }

    static func bmp(width: Int, height: Int, gray: UInt8) -> Data {
        let rowBytes = (width * 3 + 3) / 4 * 4
        let size = 54 + rowBytes * height
        var bytes = [UInt8](repeating: 0, count: size)
        func put(_ value: UInt32, at offset: Int) {
            bytes.replaceSubrange(offset..<offset + 4, with: littleEndian(value))
        }
        bytes[0] = 66
        bytes[1] = 77
        put(UInt32(size), at: 2)
        put(54, at: 10)
        put(40, at: 14)
        put(UInt32(width), at: 18)
        put(UInt32(height), at: 22)
        bytes[26] = 1
        bytes[28] = 24
        put(UInt32(rowBytes * height), at: 34)
        for row in 0..<height {
            for column in 0..<width * 3 { bytes[54 + row * rowBytes + column] = gray }
        }
        return Data(bytes)
    }

    static func jpeg(orientation: UInt16 = 1, multiPicture: Bool = false) -> Data {
        var bytes: [UInt8] = [0xFF, 0xD8]
        func segment(_ marker: UInt8, _ payload: [UInt8]) {
            let size = UInt16(payload.count + 2)
            bytes += [0xFF, marker, UInt8(size >> 8), UInt8(size & 255)] + payload
        }
        var exif = Array("Exif\0\0".utf8) + [73, 73, 42, 0, 8, 0, 0, 0, 1, 0]
        exif += [0x12, 0x01, 3, 0, 1, 0, 0, 0] + littleEndian(orientation) + [0, 0, 0, 0, 0, 0]
        segment(0xE1, exif)
        // Admission marker witness, not a full MP Index/second-image MPO file.
        if multiPicture { segment(0xE2, [77, 80, 70, 0]) }
        segment(0xDB, [0] + Array(repeating: 1, count: 64))
        segment(0xC0, [8, 0, 24, 0, 16, 1, 1, 0x11, 0])
        var dcCounts = [UInt8](repeating: 0, count: 16)
        dcCounts[3] = 12
        let acCounts: [UInt8] = [1] + Array(repeating: 0, count: 15)
        segment(0xC4, [0] + dcCounts + Array(0...11) + [0x10] + acCounts + [0])
        segment(0xDA, [1, 1, 0, 0, 63, 0])
        var accumulator: UInt8 = 0
        var used = 0
        func appendBits(_ value: Int, count: Int) {
            for shift in (0..<count).reversed() {
                accumulator = (accumulator << 1) | UInt8((value >> shift) & 1)
                used += 1
                if used == 8 {
                    bytes.append(accumulator)
                    if accumulator == 0xFF { bytes.append(0) }
                    accumulator = 0
                    used = 0
                }
            }
        }
        var previous = 0
        for gray in [30, 60, 90, 120, 180, 220] {
            let dc = 8 * (gray - 128)
            let difference = dc - previous
            previous = dc
            var category = 0
            var magnitude = abs(difference)
            while magnitude > 0 {
                category += 1
                magnitude >>= 1
            }
            appendBits(category, count: 4)
            appendBits(difference < 0 ? difference + (1 << category) - 1 : difference, count: category)
            appendBits(0, count: 1)  // the sole AC symbol is EOB
        }
        if used > 0 { appendBits((1 << (8 - used)) - 1, count: 8 - used) }
        bytes += [0xFF, 0xD9]
        return Data(bytes)
    }

    private static func pngChunk(_ type: String, _ payload: [UInt8]) -> Data {
        let content = Array(type.utf8) + payload
        var crc: UInt32 = 0xFFFF_FFFF
        for byte in content {
            crc ^= UInt32(byte)
            for _ in 0..<8 { crc = (crc >> 1) ^ (crc & 1 == 0 ? 0 : 0xEDB8_8320) }
        }
        return Data(bigEndian(UInt32(payload.count)) + content + bigEndian(crc ^ 0xFFFF_FFFF))
    }

    private static func bigEndian(_ value: UInt32) -> [UInt8] {
        [UInt8((value >> 24) & 255), UInt8((value >> 16) & 255), UInt8((value >> 8) & 255), UInt8(value & 255)]
    }

    private static func littleEndian(_ value: UInt32) -> [UInt8] { Array(bigEndian(value).reversed()) }
    private static func littleEndian(_ value: UInt16) -> [UInt8] { [UInt8(value & 255), UInt8(value >> 8)] }
}
