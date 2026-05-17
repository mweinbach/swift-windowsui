public enum DigitalCrownRotationalSensitivity: Sendable, Equatable, Hashable {
    case low, medium, high
}

public struct RetainedDigitalCrownRotation: Sendable, Equatable {
    public var value: Double
    public var minValue: Double
    public var maxValue: Double
    public var sensitivity: DigitalCrownRotationalSensitivity
    public var isContinuous: Bool
    public var isHapticFeedbackEnabled: Bool

    public init(
        value: Double = 0, minValue: Double = 0, maxValue: Double = 1,
        sensitivity: DigitalCrownRotationalSensitivity = .medium, isContinuous: Bool = false,
        isHapticFeedbackEnabled: Bool = true
    ) {
        self.value = value
        self.minValue = minValue
        self.maxValue = maxValue
        self.sensitivity = sensitivity
        self.isContinuous = isContinuous
        self.isHapticFeedbackEnabled = isHapticFeedbackEnabled
    }
}
