import Foundation

/// Keeps original numeric storage and nonfinite payloads without emitting
/// nonstandard JSON numbers, clamping, or substituting a finite value.
struct RGBNumericRecord: Codable, Sendable {
    let kind: String
    let value: Double?
    let storage: String
    let bitPattern: String

    init(_ value: Float) {
        self.kind = Self.kind(of: Double(value))
        self.value = value.isFinite ? Double(value) : nil
        self.storage = "float32"
        self.bitPattern = Self.hex(value.bitPattern, digits: 8)
    }

    init(_ value: Double) {
        self.kind = Self.kind(of: value)
        self.value = value.isFinite ? value : nil
        self.storage = "float64"
        self.bitPattern = Self.hex(value.bitPattern, digits: 16)
    }

    private static func kind(of value: Double) -> String {
        if value.isFinite { return "finite" }
        if value.isNaN { return "nan" }
        return value.sign == .minus ? "negative-infinity" : "positive-infinity"
    }

    private static func hex<T: BinaryInteger>(_ value: T, digits: Int) -> String {
        let string = String(value, radix: 16)
        return String(repeating: "0", count: max(0, digits - string.count)) + string
    }

    private enum CodingKeys: String, CodingKey {
        case kind, value, storage, bitPattern
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(kind, forKey: .kind)
        try container.encode(value, forKey: .value)
        try container.encode(storage, forKey: .storage)
        try container.encode(bitPattern, forKey: .bitPattern)
    }
}

struct RGBConstructorInput: Codable, Sendable {
    let red: RGBNumericRecord
    let green: RGBNumericRecord
    let blue: RGBNumericRecord
    let opacity: RGBNumericRecord

    init(_ fixture: RGBConstructorCase) {
        red = RGBNumericRecord(fixture.red)
        green = RGBNumericRecord(fixture.green)
        blue = RGBNumericRecord(fixture.blue)
        opacity = RGBNumericRecord(fixture.opacity)
    }
}

struct RGBEncodedComponents: Codable, Sendable {
    let red: RGBNumericRecord
    let green: RGBNumericRecord
    let blue: RGBNumericRecord
    let alpha: RGBNumericRecord

    init(red: Float, green: Float, blue: Float, alpha: Float) {
        self.red = RGBNumericRecord(red)
        self.green = RGBNumericRecord(green)
        self.blue = RGBNumericRecord(blue)
        self.alpha = RGBNumericRecord(alpha)
    }

    init(red: Double, green: Double, blue: Double, alpha: Double) {
        self.red = RGBNumericRecord(red)
        self.green = RGBNumericRecord(green)
        self.blue = RGBNumericRecord(blue)
        self.alpha = RGBNumericRecord(alpha)
    }
}

struct RGBLinearComponents: Codable, Sendable {
    let red: RGBNumericRecord
    let green: RGBNumericRecord
    let blue: RGBNumericRecord

    init(red: Float, green: Float, blue: Float) {
        self.red = RGBNumericRecord(red)
        self.green = RGBNumericRecord(green)
        self.blue = RGBNumericRecord(blue)
    }
}

struct RGBAppKitSpaceRecord: Codable, Sendable {
    let targetColorSpace: String
    let actualColorSpaceName: String
    let colorSpaceModel: String
    let componentCount: Int?
    let targetIdentityMatches: Bool

    private enum CodingKeys: String, CodingKey {
        case targetColorSpace, actualColorSpaceName, colorSpaceModel, componentCount, targetIdentityMatches
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(targetColorSpace, forKey: .targetColorSpace)
        try container.encode(actualColorSpaceName, forKey: .actualColorSpaceName)
        try container.encode(colorSpaceModel, forKey: .colorSpaceModel)
        try container.encode(componentCount, forKey: .componentCount)
        try container.encode(targetIdentityMatches, forKey: .targetIdentityMatches)
    }
}

struct RGBObservation: Codable, Sendable {
    let environment: String
    let status: String
    let reason: String?
    let encodedRGBA: RGBEncodedComponents?
    let linearRGB: RGBLinearComponents?
    let appKit: RGBAppKitSpaceRecord?

    static func observed(
        environment: String,
        encodedRGBA: RGBEncodedComponents,
        linearRGB: RGBLinearComponents? = nil,
        appKit: RGBAppKitSpaceRecord? = nil
    ) -> RGBObservation {
        RGBObservation(
            environment: environment, status: "observed", reason: nil,
            encodedRGBA: encodedRGBA, linearRGB: linearRGB, appKit: appKit)
    }

    static func unsupported(reason: String, appKit: RGBAppKitSpaceRecord? = nil) -> RGBObservation {
        RGBObservation(
            environment: "none", status: "unsupported", reason: reason,
            encodedRGBA: nil, linearRGB: nil, appKit: appKit)
    }

    private enum CodingKeys: String, CodingKey {
        case environment, status, reason, encodedRGBA, linearRGB, appKit
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(environment, forKey: .environment)
        try container.encode(status, forKey: .status)
        try container.encode(reason, forKey: .reason)
        try container.encode(encodedRGBA, forKey: .encodedRGBA)
        try container.encode(linearRGB, forKey: .linearRGB)
        try container.encode(appKit, forKey: .appKit)
    }
}

struct RGBCaseRecord: Codable, Sendable {
    let caseId: String
    let domain: String
    let sourceSpace: String
    let input: RGBConstructorInput
    let observations: [RGBObservation]

    init(_ fixture: RGBConstructorCase, observations: [RGBObservation]) {
        caseId = fixture.id
        domain = fixture.domain.rawValue
        sourceSpace = fixture.space.rawValue
        input = RGBConstructorInput(fixture)
        self.observations = observations
    }
}

struct RGBRuntimeRecord: Codable, Sendable {
    let processId: Int32
    let processArchitecture: String
    let operatingSystemVersion: String
    let operatingSystemVersionString: String

    static func current() -> RGBRuntimeRecord {
        #if arch(x86_64)
            let architecture = "x86_64"
        #elseif arch(arm64)
            let architecture = "arm64"
        #else
            let architecture = "unsupported"
        #endif
        let process = ProcessInfo.processInfo
        let version = process.operatingSystemVersion
        return RGBRuntimeRecord(
            processId: process.processIdentifier,
            processArchitecture: architecture,
            operatingSystemVersion: "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)",
            operatingSystemVersionString: process.operatingSystemVersionString)
    }
}

struct RGBObservationReport: Codable, Sendable {
    let schemaVersion: Int
    let protocolId: String
    let caseSetId: String
    let componentEncoding: String
    let collectionStatus: String
    let runId: String
    let observer: String
    let platform: String
    let runtime: RGBRuntimeRecord
    let cases: [RGBCaseRecord]

    init(runId: String, observer: String, cases: [RGBCaseRecord]) {
        schemaVersion = 1
        protocolId = RGBConstructorCase.protocolID
        caseSetId = RGBConstructorCase.caseSetID
        componentEncoding = "extended-srgb-encoded-unpremultiplied"
        collectionStatus = "complete"
        self.runId = runId
        self.observer = observer
        #if os(Windows)
            platform = "windows"
        #elseif os(macOS)
            platform = "macos"
        #else
            platform = "unsupported"
        #endif
        runtime = .current()
        self.cases = cases
    }
}
