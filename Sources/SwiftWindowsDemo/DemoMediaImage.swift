import Foundation

#if canImport(SwiftUI)
    import CoreGraphics
    import ImageIO
    import SwiftUI
#else
    import WinSwiftUI
#endif

public enum DemoMediaImageError: Error, Equatable, Sendable, LocalizedError {
    case invalidFileURL
    case notRegularFile
    case invalidData
    case encodedImageTooLarge
    case sourceImageTooLarge
    case invalidPixelDimension
    case unsupportedFormat
    case unsupportedFrameCount
    case invalidOrientation
    case colorConversionFailed
    case decodingFailed
    case busy
    case closed

    public var errorDescription: String? {
        switch self {
        case .invalidFileURL: return "Choose an absolute local file URL without credentials or URL parameters."
        case .notRegularFile: return "Only regular image files are supported, not folders or symbolic links."
        case .invalidData: return "The image data is empty, malformed, or incomplete."
        case .encodedImageTooLarge: return "The image exceeds the 8 MiB encoded data limit."
        case .sourceImageTooLarge: return "The image exceeds the 16 million source pixel limit."
        case .invalidPixelDimension: return "The requested image edge must be between 1 and 1024 pixels."
        case .unsupportedFormat: return "Only PNG, JPEG, and BMP images are supported."
        case .unsupportedFrameCount: return "Animated and multi-picture images are not supported."
        case .invalidOrientation: return "The JPEG has an invalid EXIF orientation."
        case .colorConversionFailed: return "The image color profile cannot be converted to sRGB."
        case .decodingFailed: return "The image could not be decoded."
        case .busy: return "Both image workers are still occupied. Retry when a worker has finished."
        case .closed: return "This image service has been closed."
        }
    }
}

/// The platform service owns the decoded pixels. Shared view code composes only
/// `image.resizable().scaledToFit()` and the normal public Image modifiers.
/// Windows converts reported profiles and assumes sRGB when WIC color contexts
/// are absent/unsupported; absent/unsupported JPEG metadata means orientation 1.
/// ImageIO uses its reported source color/EXIF information. Cross-OS metadata
/// and color conformance require native qualification beyond this value model.
public struct DemoMediaImage: Sendable {
    public let pixelWidth: Int
    public let pixelHeight: Int
    /// Source dimensions after reported JPEG EXIF orientation is applied.
    public let sourcePixelWidth: Int
    public let sourcePixelHeight: Int
    public let byteCount: Int

    #if canImport(SwiftUI)
        private let storage: DemoMediaCGImage
    #else
        private let storage: DecodedImage
    #endif

    @MainActor public var image: Image {
        #if canImport(SwiftUI)
            Image(decorative: storage.image, scale: 1)
        #else
            storage.image
        #endif
    }

    // Source tests compare real decoded content, not successful phase metadata.
    var pixelData: Data {
        #if canImport(SwiftUI)
            storage.pixels as Data
        #else
            storage.pixelData
        #endif
    }

    /// Runs on the service's worker, never while evaluating a view body.
    static func decode(_ data: Data, maximumPixelDimension: Int) throws -> Self {
        try Task.checkCancellation()
        guard !data.isEmpty else { throw DemoMediaImageError.invalidData }
        guard data.count <= DemoMediaImageService.maximumEncodedBytes else {
            throw DemoMediaImageError.encodedImageTooLarge
        }
        guard (1...DemoMediaImageService.maximumPixelDimension).contains(maximumPixelDimension) else {
            throw DemoMediaImageError.invalidPixelDimension
        }
        #if canImport(SwiftUI)
            return try decodeWithImageIO(data, maximumPixelDimension: maximumPixelDimension)
        #else
            do {
                let decoded = try DecodedImage(data: data, maximumPixelDimension: maximumPixelDimension)
                return Self(
                    pixelWidth: decoded.pixelWidth, pixelHeight: decoded.pixelHeight,
                    sourcePixelWidth: decoded.sourcePixelWidth, sourcePixelHeight: decoded.sourcePixelHeight,
                    byteCount: decoded.byteCount, storage: decoded)
            } catch let error as ImageDecodingError {
                switch error {
                case .invalidData: throw DemoMediaImageError.invalidData
                case .encodedImageTooLarge: throw DemoMediaImageError.encodedImageTooLarge
                case .sourceImageTooLarge: throw DemoMediaImageError.sourceImageTooLarge
                case .invalidPixelDimension: throw DemoMediaImageError.invalidPixelDimension
                case .unsupportedFormat: throw DemoMediaImageError.unsupportedFormat
                case .unsupportedFrameCount: throw DemoMediaImageError.unsupportedFrameCount
                case .invalidOrientation: throw DemoMediaImageError.invalidOrientation
                case .colorConversionFailed: throw DemoMediaImageError.colorConversionFailed
                case .decodingFailed: throw DemoMediaImageError.decodingFailed
                }
            }
        #endif
    }

    #if canImport(SwiftUI)
        private static func decodeWithImageIO(_ data: Data, maximumPixelDimension: Int) throws -> Self {
            try admitStaticContainer(data)
            guard
                let source = CGImageSourceCreateWithData(
                    data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
                let type = CGImageSourceGetType(source) as String?
            else { throw DemoMediaImageError.invalidData }
            let isJPEG = type == "public.jpeg"
            guard isJPEG || type == "public.png" || type == "com.microsoft.bmp" else {
                throw DemoMediaImageError.unsupportedFormat
            }
            guard CGImageSourceGetCount(source) == 1 else { throw DemoMediaImageError.unsupportedFrameCount }
            guard let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
                let widthNumber = properties[kCGImagePropertyPixelWidth] as? NSNumber,
                let heightNumber = properties[kCGImagePropertyPixelHeight] as? NSNumber,
                let rawWidth = Int(exactly: widthNumber.int64Value),
                let rawHeight = Int(exactly: heightNumber.int64Value), rawWidth > 0, rawHeight > 0
            else { throw DemoMediaImageError.invalidData }
            let sourcePixels = rawWidth.multipliedReportingOverflow(by: rawHeight)
            guard !sourcePixels.overflow, sourcePixels.partialValue <= DemoMediaImageService.maximumSourcePixels else {
                throw DemoMediaImageError.sourceImageTooLarge
            }
            let orientation = isJPEG ? (properties[kCGImagePropertyOrientation] as? NSNumber)?.intValue ?? 1 : 1
            guard (1...8).contains(orientation) else { throw DemoMediaImageError.invalidOrientation }
            let sourceWidth = orientation >= 5 ? rawHeight : rawWidth
            let sourceHeight = orientation >= 5 ? rawWidth : rawHeight
            let size = try thumbnailSize(width: sourceWidth, height: sourceHeight, edge: maximumPixelDimension)
            let pitch = size.width.multipliedReportingOverflow(by: 4)
            let byteCount = pitch.partialValue.multipliedReportingOverflow(by: size.height)
            guard !pitch.overflow, !byteCount.overflow, byteCount.partialValue > 0,
                byteCount.partialValue <= DemoMediaImageService.maximumPixelDimension
                    * DemoMediaImageService.maximumPixelDimension * 4
            else { throw DemoMediaImageError.invalidPixelDimension }
            try Task.checkCancellation()
            guard
                let thumbnail = CGImageSourceCreateThumbnailAtIndex(
                    source, 0,
                    [
                        kCGImageSourceCreateThumbnailFromImageAlways: true,
                        kCGImageSourceCreateThumbnailWithTransform: isJPEG,
                        kCGImageSourceThumbnailMaxPixelSize: maximumPixelDimension,
                        kCGImageSourceShouldCacheImmediately: true,
                    ] as CFDictionary)
            else { throw DemoMediaImageError.decodingFailed }
            try Task.checkCancellation()
            guard thumbnail.width > 0, thumbnail.height > 0,
                thumbnail.width <= maximumPixelDimension, thumbnail.height <= maximumPixelDimension,
                let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)
            else { throw DemoMediaImageError.colorConversionFailed }
            // Re-own the final raster, not ImageIO's lazy decoder/source. Quartz
            // converts the declared source color space into explicit sRGB PBGRA.
            var pixels = Data(count: byteCount.partialValue)
            let bitmapInfo = CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue
            try pixels.withUnsafeMutableBytes { bytes in
                guard
                    let context = CGContext(
                        data: bytes.baseAddress, width: size.width, height: size.height, bitsPerComponent: 8,
                        bytesPerRow: pitch.partialValue, space: colorSpace, bitmapInfo: bitmapInfo)
                else { throw DemoMediaImageError.decodingFailed }
                context.interpolationQuality = .high
                context.draw(
                    thumbnail,
                    in: CGRect(x: 0, y: 0, width: CGFloat(size.width), height: CGFloat(size.height)))
            }
            try Task.checkCancellation()
            // Keep one explicit CFData raster shared with the provider. Do not
            // retain both Swift Data and its bridge and assume zero-copy bridging.
            let ownedPixels = pixels as CFData
            let ownedByteCount = CFDataGetLength(ownedPixels)
            guard ownedByteCount == byteCount.partialValue,
                let provider = CGDataProvider(data: ownedPixels),
                let image = CGImage(
                    width: size.width, height: size.height, bitsPerComponent: 8, bitsPerPixel: 32,
                    bytesPerRow: pitch.partialValue, space: colorSpace, bitmapInfo: CGBitmapInfo(rawValue: bitmapInfo),
                    provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
            else { throw DemoMediaImageError.decodingFailed }
            return Self(
                pixelWidth: size.width, pixelHeight: size.height,
                sourcePixelWidth: sourceWidth, sourcePixelHeight: sourceHeight,
                byteCount: ownedByteCount, storage: DemoMediaCGImage(image: image, pixels: ownedPixels))
        }

        private static func thumbnailSize(width: Int, height: Int, edge: Int) throws -> (width: Int, height: Int) {
            guard width > edge || height > edge else { return (width, height) }
            let major = max(width, height)
            let minor = min(width, height)
            let product = minor.multipliedReportingOverflow(by: edge)
            let rounded = product.partialValue.addingReportingOverflow(major / 2)
            guard !product.overflow, !rounded.overflow else { throw DemoMediaImageError.sourceImageTooLarge }
            let small = max(1, rounded.partialValue / major)
            return width >= height ? (edge, small) : (small, edge)
        }

        /// Keep ImageIO's admission equal to WIC even if it exposes APNG/MPO as
        /// one default frame. All offsets are bounded by the admitted 8 MiB.
        private static func admitStaticContainer(_ data: Data) throws {
            let bytes = [UInt8](data)
            if bytes.starts(with: [137, 80, 78, 71, 13, 10, 26, 10]) {
                var offset = 8
                while offset < bytes.count {
                    guard bytes.count - offset >= 12 else { throw DemoMediaImageError.invalidData }
                    let length = bytes[offset..<offset + 4].reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
                    guard let count = Int(exactly: length), count <= bytes.count - offset - 12 else {
                        throw DemoMediaImageError.invalidData
                    }
                    let type = Array(bytes[offset + 4..<offset + 8])
                    if type == Array("acTL".utf8) { throw DemoMediaImageError.unsupportedFrameCount }
                    offset += count + 12
                    if type == Array("IEND".utf8) {
                        guard count == 0, offset == bytes.count else { throw DemoMediaImageError.invalidData }
                        return
                    }
                }
                throw DemoMediaImageError.invalidData
            }
            if bytes.starts(with: [0xFF, 0xD8]) {
                var offset = 2
                while offset < bytes.count {
                    guard bytes[offset] == 0xFF else { throw DemoMediaImageError.invalidData }
                    offset += 1
                    while offset < bytes.count, bytes[offset] == 0xFF { offset += 1 }
                    guard offset < bytes.count else { throw DemoMediaImageError.invalidData }
                    let marker = bytes[offset]
                    offset += 1
                    if marker == 0xDA || marker == 0xD9 { return }
                    if marker == 0x01 || (0xD0...0xD7).contains(marker) { continue }
                    guard marker != 0, bytes.count - offset >= 2 else { throw DemoMediaImageError.invalidData }
                    let length = Int(bytes[offset]) * 256 + Int(bytes[offset + 1])
                    guard length >= 2, length <= bytes.count - offset else { throw DemoMediaImageError.invalidData }
                    if marker == 0xE2, length >= 6, bytes[offset + 2..<offset + 6].elementsEqual([77, 80, 70, 0]) {
                        throw DemoMediaImageError.unsupportedFrameCount
                    }
                    offset += length
                }
                throw DemoMediaImageError.invalidData
            }
        }
    #endif
}

#if canImport(SwiftUI)
    /// The CGImage provider retains this exact immutable CFData raster, not a
    /// lazy ImageIO source. The box neither retains a second Swift Data bridge
    /// nor mutates either value or exports writable pointers.
    private final class DemoMediaCGImage: @unchecked Sendable {
        let image: CGImage
        let pixels: CFData

        init(image: CGImage, pixels: CFData) {
            self.image = image
            self.pixels = pixels
        }
    }
#endif
