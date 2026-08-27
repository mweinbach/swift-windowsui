import Foundation

/// Portable report values only. These observations neither alter the native
/// capture nor establish what a compositor used to produce its pixels.
enum MaterialDiagnosticMetadata {
    struct EnvironmentValues: Encodable, Equatable {
        let reduceTransparency: Bool
        let reduceMotion: Bool
        let colorScheme: String
        let colorSchemeContrast: String
        let displayScale: Double
    }

    struct EnvironmentObservation: Encodable, Equatable {
        private(set) var bodyEvaluationCount = 0
        private(set) var latestBodyEvaluationUTC: String?
        private(set) var values: EnvironmentValues?

        var status: String { values == nil ? "unobserved" : "observed" }

        mutating func record(_ values: EnvironmentValues, timestampUTC: String) {
            bodyEvaluationCount += 1
            latestBodyEvaluationUTC = timestampUTC
            self.values = values
        }

        private enum CodingKeys: String, CodingKey {
            case status, bodyEvaluationCount, latestBodyEvaluationUTC, values
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(status, forKey: .status)
            try container.encode(bodyEvaluationCount, forKey: .bodyEvaluationCount)
            // Explicit nulls distinguish an unobserved environment from false
            // accessibility flags, or from the fixture's requested defaults.
            try container.encode(latestBodyEvaluationUTC, forKey: .latestBodyEvaluationUTC)
            try container.encode(values, forKey: .values)
        }
    }

    struct SystemAccessibility: Encodable, Equatable {
        let reduceTransparency: Bool
        let increaseContrast: Bool
        let reduceMotion: Bool
    }

    struct Application: Encodable, Equatable {
        let activationPolicy: String
        let isActive: Bool
        let isHidden: Bool
        let isRunning: Bool
    }

    struct Rectangle: Encodable, Equatable {
        let x: Double
        let y: Double
        let width: Double
        let height: Double
    }

    struct Window: Encodable, Equatable {
        let isVisible: Bool
        let isMiniaturized: Bool
        let isKeyWindow: Bool
        let isMainWindow: Bool
        let occlusionStateVisible: Bool
        let backingScaleFactor: Double
    }

    struct Host: Encodable, Equatable {
        let hasWindow: Bool
        let hasSuperview: Bool
        let isHidden: Bool
        let isHiddenOrHasHiddenAncestor: Bool
        let isFlipped: Bool
        let effectiveAppearance: String
        let frame: Rectangle
        let bounds: Rectangle
        let visibleRect: Rectangle
        let convertedBackingBounds: Rectangle
        let wantsLayer: Bool
        let hasLayer: Bool
        let layerContentsScale: Double?
        let window: Window?
    }

    struct Snapshot: Encodable, Equatable {
        let timestampUTC: String
        let systemAccessibility: SystemAccessibility
        let swiftUIEnvironment: EnvironmentObservation
        let application: Application
        let host: Host
    }

    struct Bitmap: Encodable, Equatable {
        let pixelWidth: Int
        let pixelHeight: Int
        let logicalWidth: Double
        let logicalHeight: Double
        let bitsPerSample: Int
        let samplesPerPixel: Int
        let hasAlpha: Bool
        let isPlanar: Bool
        let bitsPerPixel: Int
        let bytesPerRow: Int
        let bitmapFormatRawValue: UInt
        let colorSpaceName: String
    }

    struct BitmapRecommendation: Encodable, Equatable {
        let bitmap: Bitmap?
        var status: String { bitmap == nil ? "unavailable" : "observed" }

        private enum CodingKeys: String, CodingKey {
            case status, bitmap
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(status, forKey: .status)
            try container.encode(bitmap, forKey: .bitmap)
        }
    }

    struct Capture: Encodable, Equatable {
        let schemaVersion = 1
        let observationScope =
            "before/after the synchronous cache, encode, and measurement attempt; SwiftUI values are the last body observation, not compositor state"
        let recommendedBitmapScope =
            "bitmapImageRepForCachingDisplay(in:) sampled after the attempt; metadata only, not used for capture"
        let before: Snapshot
        let after: Snapshot
        let cacheDisplayCompleted: Bool
        let recommendedBitmap: BitmapRecommendation
    }
}
