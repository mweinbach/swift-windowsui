import Foundation
import SwiftWindowsGraphics
import SwiftWindowsUI

public typealias ImageDecodingError = BoundedImageDecodingError

/// A bounded, immutable decoded image for explicitly owned asynchronous loaders.
/// Construct it on a worker; compose its ordinary public `image` on MainActor.
/// This does not use the named-resource ImageLoader or AsyncImage caches.
/// Reported color profiles are converted; absent/unsupported WIC contexts are
/// assumed sRGB. Reported JPEG EXIF is normalized; absent/unsupported metadata
/// means orientation 1. These are explicit Windows adaptation limits.
public struct DecodedImage: Sendable {
    public static let maximumEncodedBytes = BoundedImageDecoder.maximumEncodedBytes
    public static let maximumSourcePixels = BoundedImageDecoder.maximumSourcePixels
    public static let maximumPixelDimension = BoundedImageDecoder.maximumPixelDimension

    private let storage: BoundedDecodedImage

    public init(data: Data, maximumPixelDimension: Int = 1024) throws {
        storage = try BoundedImageDecoder.decode(data, maximumPixelDimension: maximumPixelDimension)
    }

    public var pixelWidth: Int { Int(storage.bitmap.width) }
    public var pixelHeight: Int { Int(storage.bitmap.height) }
    public var sourcePixelWidth: Int { storage.sourcePixelWidth }
    public var sourcePixelHeight: Int { storage.sourcePixelHeight }
    public var byteCount: Int { storage.bitmap.pixels.count }
    /// Owned premultiplied BGRA8 in sRGB, assuming sRGB when WIC cannot report
    /// a source profile. Pixels are tightly packed in raster row order.
    public var pixelData: Data { storage.bitmap.pixels }

    @MainActor public var image: Image { Image(bitmap: storage.bitmap) }
}
