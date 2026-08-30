import CDirect2DInterop
import Foundation
import SwiftWindowsGraphics

public enum BoundedImageDecodingError: Error, Equatable, Sendable, LocalizedError {
    case invalidData
    case encodedImageTooLarge
    case sourceImageTooLarge
    case invalidPixelDimension
    case unsupportedFormat
    case unsupportedFrameCount
    case invalidOrientation
    case colorConversionFailed
    case decodingFailed

    public var errorDescription: String? {
        switch self {
        case .invalidData: return "The image data is empty, malformed, or incomplete."
        case .encodedImageTooLarge: return "The image exceeds the 8 MiB encoded data limit."
        case .sourceImageTooLarge: return "The image exceeds the 16 million source pixel limit."
        case .invalidPixelDimension: return "The requested image edge must be between 1 and 1024 pixels."
        case .unsupportedFormat: return "Only PNG, JPEG, and BMP images are supported."
        case .unsupportedFrameCount: return "Animated and multi-picture images are not supported."
        case .invalidOrientation: return "The JPEG has an invalid EXIF orientation."
        case .colorConversionFailed: return "The image color profile cannot be converted to sRGB."
        case .decodingFailed: return "The image could not be decoded."
        }
    }
}

/// An owned, renderer-neutral result. The explicit bitmap format distinguishes
/// media sRGB/PBGRA thumbnails from raw-color/straight-BGRA compatibility frames.
public struct BoundedDecodedImage: Sendable {
    public let bitmap: BitmapSurface
    public let sourcePixelWidth: Int
    public let sourcePixelHeight: Int
}

/// Synchronous worker API. It neither dispatches work nor retains a cache.
/// Cancellation before/after WIC cannot interrupt a codec call already running.
/// The media policy converts reported profiles; absent/unsupported WIC color
/// contexts are assumed sRGB. Absent/unsupported JPEG metadata means orientation
/// 1. Format/frame/bounds admission is strict, not universal metadata conformance.
public enum BoundedImageDecoder {
    public static let maximumEncodedBytes = 8_388_608
    public static let maximumSourcePixels = 16_000_000
    public static let maximumDecodedBytes = 64_000_000
    public static let maximumPixelDimension = 1024

    public static func decode(_ data: Data, maximumPixelDimension: Int = 1024) throws -> BoundedDecodedImage {
        try decode(data, maximumPixelDimension: maximumPixelDimension, firstFrame: false)
    }

    /// Bounded Windows compatibility adaptation for existing image loaders:
    /// first frame of any installed WIC format, full dimensions, unmodified
    /// orientation/color, and straight alpha. Never a strict-media fallback.
    public static func decodeFirstFrame(_ data: Data) throws -> BoundedDecodedImage {
        try decode(data, maximumPixelDimension: 0, firstFrame: true)
    }

    private static func decode(_ data: Data, maximumPixelDimension: Int, firstFrame: Bool) throws -> BoundedDecodedImage
    {
        try Task.checkCancellation()
        guard !data.isEmpty else { throw BoundedImageDecodingError.invalidData }
        guard data.count <= maximumEncodedBytes, let encodedCount = UInt32(exactly: data.count) else {
            throw BoundedImageDecodingError.encodedImageTooLarge
        }
        if !firstFrame, !(1...Self.maximumPixelDimension).contains(maximumPixelDimension) {
            throw BoundedImageDecodingError.invalidPixelDimension
        }
        guard let requestedDimension = UInt32(exactly: maximumPixelDimension) else {
            throw BoundedImageDecodingError.invalidPixelDimension
        }

        var result = SWU_BoundedImageResult()
        let status = data.withUnsafeBytes { bytes -> Int32 in
            let pointer = bytes.bindMemory(to: UInt8.self).baseAddress
            if firstFrame { return SWU_DecodeBoundedImageFirstFrame(pointer, encodedCount, &result) }
            return SWU_DecodeBoundedImage(pointer, encodedCount, requestedDimension, &result)
        }
        defer { if let pixels = result.pixels { SWU_FreeImagePixels(pixels) } }
        try Task.checkCancellation()
        switch Int(status) {
        case Int(SWU_BOUNDED_IMAGE_OK): break
        case Int(SWU_BOUNDED_IMAGE_INVALID_DATA): throw BoundedImageDecodingError.invalidData
        case Int(SWU_BOUNDED_IMAGE_ENCODED_LIMIT): throw BoundedImageDecodingError.encodedImageTooLarge
        case Int(SWU_BOUNDED_IMAGE_SOURCE_LIMIT): throw BoundedImageDecodingError.sourceImageTooLarge
        case Int(SWU_BOUNDED_IMAGE_OUTPUT_LIMIT): throw BoundedImageDecodingError.invalidPixelDimension
        case Int(SWU_BOUNDED_IMAGE_UNSUPPORTED_FORMAT): throw BoundedImageDecodingError.unsupportedFormat
        case Int(SWU_BOUNDED_IMAGE_MULTIPLE_FRAMES): throw BoundedImageDecodingError.unsupportedFrameCount
        case Int(SWU_BOUNDED_IMAGE_INVALID_ORIENTATION): throw BoundedImageDecodingError.invalidOrientation
        case Int(SWU_BOUNDED_IMAGE_COLOR_FAILED): throw BoundedImageDecodingError.colorConversionFailed
        default: throw BoundedImageDecodingError.decodingFailed
        }

        let width = Int(result.width)
        let height = Int(result.height)
        let pitch = Int(result.bytes_per_row)
        let sourceWidth = Int(result.source_width)
        let sourceHeight = Int(result.source_height)
        let sourceCount = sourceWidth.multipliedReportingOverflow(by: sourceHeight)
        let expectedPitch = width.multipliedReportingOverflow(by: 4)
        let byteCount = pitch.multipliedReportingOverflow(by: height)
        guard let pixels = result.pixels, width > 0, height > 0,
            firstFrame || (width <= maximumPixelDimension && height <= maximumPixelDimension),
            sourceWidth > 0, sourceHeight > 0,
            !sourceCount.overflow, sourceCount.partialValue <= maximumSourcePixels,
            !expectedPitch.overflow, pitch == expectedPitch.partialValue,
            !byteCount.overflow, byteCount.partialValue > 0,
            byteCount.partialValue <= maximumDecodedBytes,
            firstFrame || byteCount.partialValue <= Self.maximumPixelDimension * Self.maximumPixelDimension * 4,
            !firstFrame || (width == sourceWidth && height == sourceHeight)
        else { throw BoundedImageDecodingError.decodingFailed }
        // Copy before releasing the C allocation. No COM/codec object or borrowed
        // pointer crosses an actor boundary or is retained by BitmapSurface.
        let ownedPixels = Data(bytes: pixels, count: byteCount.partialValue)
        try Task.checkCancellation()
        let bitmap = BitmapSurface(
            width: result.width, height: result.height, bytesPerRow: result.bytes_per_row,
            pixels: ownedPixels, format: firstFrame ? .bgra8Straight : .bgra8Premultiplied)
        try bitmap.validate()
        return BoundedDecodedImage(bitmap: bitmap, sourcePixelWidth: sourceWidth, sourcePixelHeight: sourceHeight)
    }
}
