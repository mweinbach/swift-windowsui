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

public enum StackAxis: Equatable, Sendable {
    case horizontal
    case vertical
}

public enum StackCrossAlignment: Equatable, Sendable {
    case leading
    case center
    case trailing
    case stretch
}

public enum StackMainAlignment: Equatable, Sendable {
    case start
    case center
    case end
}

public struct StackLayout: Equatable, Sendable {
    public var axis: StackAxis
    public var spacing: Double
    public var padding: EdgeInsets
    public var alignment: StackCrossAlignment
    public var mainAlignment: StackMainAlignment

    public init(
        axis: StackAxis,
        spacing: Double = 0,
        padding: EdgeInsets = .zero,
        alignment: StackCrossAlignment = .leading,
        mainAlignment: StackMainAlignment = .start
    ) {
        self.axis = axis
        self.spacing = spacing
        self.padding = padding
        self.alignment = alignment
        self.mainAlignment = mainAlignment
    }

    public static func horizontal(
        spacing: Double = 0,
        padding: EdgeInsets = .zero,
        alignment: StackCrossAlignment = .center,
        mainAlignment: StackMainAlignment = .start
    ) -> StackLayout {
        StackLayout(axis: .horizontal, spacing: spacing, padding: padding, alignment: alignment, mainAlignment: mainAlignment)
    }

    public static func vertical(
        spacing: Double = 0,
        padding: EdgeInsets = .zero,
        alignment: StackCrossAlignment = .leading,
        mainAlignment: StackMainAlignment = .start
    ) -> StackLayout {
        StackLayout(axis: .vertical, spacing: spacing, padding: padding, alignment: alignment, mainAlignment: mainAlignment)
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
