import SwiftWindowsCore

public struct LayoutConstraints: Equatable, Sendable {
    public var minWidth: Double
    public var maxWidth: Double
    public var minHeight: Double
    public var maxHeight: Double

    public init(minWidth: Double = 0, maxWidth: Double = .infinity, minHeight: Double = 0, maxHeight: Double = .infinity) {
        self.minWidth = minWidth
        self.maxWidth = maxWidth
        self.minHeight = minHeight
        self.maxHeight = maxHeight
    }

    public static let unconstrained = LayoutConstraints()
}

public struct LayoutMeasurement: Equatable, Sendable {
    public var size: Size

    public init(size: Size) {
        self.size = size
    }
}

public protocol LayoutNode {
    func measure(in constraints: LayoutConstraints) -> LayoutMeasurement
}

public struct FixedLayoutBox: LayoutNode, Equatable, Sendable {
    public var preferredSize: Size

    public init(preferredSize: Size) {
        self.preferredSize = preferredSize
    }

    public func measure(in constraints: LayoutConstraints) -> LayoutMeasurement {
        LayoutMeasurement(
            size: Size(
                width: min(max(preferredSize.width, constraints.minWidth), constraints.maxWidth),
                height: min(max(preferredSize.height, constraints.minHeight), constraints.maxHeight)
            )
        )
    }
}
