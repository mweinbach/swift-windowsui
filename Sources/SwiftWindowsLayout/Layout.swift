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

// MARK: - Flex Properties

public struct FlexProperties: Equatable, Sendable {
    /// Shorthand flex factor. When non-nil, sets both grow and shrink.
    public var flex: Double?
    /// How much this item should grow relative to siblings when extra space is available.
    public var grow: Double
    /// How much this item should shrink relative to siblings when space is insufficient.
    public var shrink: Double

    public init(flex: Double? = nil, grow: Double = 0, shrink: Double = 1) {
        self.flex = flex
        self.grow = flex ?? grow
        self.shrink = flex ?? shrink
    }

    public static let `default` = FlexProperties()
}

// MARK: - Stack Types

public enum StackAxis: Equatable, Sendable {
    case horizontal
    case vertical
}

public enum StackCrossAlignment: Equatable, Sendable {
    case leading
    case center
    case trailing
    case firstTextBaseline
    case lastTextBaseline
    case customHorizontal(String)
    case customVertical(String)
    case stretch
}

public enum StackMainAlignment: Equatable, Sendable {
    case start
    case center
    case end
}

public enum StackDistribution: Equatable, Sendable {
    /// Children fill available space according to their flex properties.
    case fill
    /// Equal spacing between children; no spacing before first or after last.
    case spaceBetween
    /// Equal spacing around each child (half-space at edges).
    case spaceAround
    /// Equal spacing between and around children (uniform gaps).
    case spaceEvenly
}

public struct StackLayout: Equatable, Sendable {
    public var axis: StackAxis
    public var spacing: Double
    public var padding: EdgeInsets
    public var alignment: StackCrossAlignment
    public var mainAlignment: StackMainAlignment
    public var distribution: StackDistribution

    public init(
        axis: StackAxis,
        spacing: Double = 0,
        padding: EdgeInsets = .zero,
        alignment: StackCrossAlignment = .leading,
        mainAlignment: StackMainAlignment = .start,
        distribution: StackDistribution = .fill
    ) {
        self.axis = axis
        self.spacing = spacing
        self.padding = padding
        self.alignment = alignment
        self.mainAlignment = mainAlignment
        self.distribution = distribution
    }

    public static func horizontal(
        spacing: Double = 0,
        padding: EdgeInsets = .zero,
        alignment: StackCrossAlignment = .center,
        mainAlignment: StackMainAlignment = .start,
        distribution: StackDistribution = .fill
    ) -> StackLayout {
        StackLayout(axis: .horizontal, spacing: spacing, padding: padding, alignment: alignment, mainAlignment: mainAlignment, distribution: distribution)
    }

    public static func vertical(
        spacing: Double = 0,
        padding: EdgeInsets = .zero,
        alignment: StackCrossAlignment = .leading,
        mainAlignment: StackMainAlignment = .start,
        distribution: StackDistribution = .fill
    ) -> StackLayout {
        StackLayout(axis: .vertical, spacing: spacing, padding: padding, alignment: alignment, mainAlignment: mainAlignment, distribution: distribution)
    }
}

// MARK: - Grid Layout

public struct GridLayout: Equatable, Sendable {
    public var columns: Int
    public var rowSpacing: Double
    public var columnSpacing: Double
    public var padding: EdgeInsets

    public init(
        columns: Int,
        rowSpacing: Double = 0,
        columnSpacing: Double = 0,
        padding: EdgeInsets = .zero
    ) {
        self.columns = max(columns, 1)
        self.rowSpacing = rowSpacing
        self.columnSpacing = columnSpacing
        self.padding = padding
    }

    /// Convenience initializer using uniform spacing for both axes.
    public init(
        columns: Int,
        spacing: Double,
        padding: EdgeInsets = .zero
    ) {
        self.init(columns: columns, rowSpacing: spacing, columnSpacing: spacing, padding: padding)
    }
}

// MARK: - Layout Node Protocol

public protocol LayoutNode {
    func measure(in constraints: LayoutConstraints) -> LayoutMeasurement
}

// MARK: - Aspect Ratio Constraint

public enum AspectRatioMode: Equatable, Sendable {
    /// Fit within the constraints while preserving aspect ratio.
    case fit
    /// Fill the constraints while preserving aspect ratio.
    case fill
}

public struct AspectRatioConstraint: LayoutNode, Equatable, Sendable {
    public var ratio: Double
    public var mode: AspectRatioMode

    public init(ratio: Double, mode: AspectRatioMode = .fit) {
        self.ratio = ratio
        self.mode = mode
    }

    /// Convenience: create from width/height.
    public init(width: Double, height: Double, mode: AspectRatioMode = .fit) {
        self.ratio = height != 0 ? width / height : 1
        self.mode = mode
    }

    public func measure(in constraints: LayoutConstraints) -> LayoutMeasurement {
        guard ratio > 0 else {
            return LayoutMeasurement(size: .zero)
        }

        let maxW = constraints.maxWidth.isFinite ? constraints.maxWidth : 1_000_000
        let maxH = constraints.maxHeight.isFinite ? constraints.maxHeight : 1_000_000

        let widthFromHeight = maxH * ratio
        let heightFromWidth = maxW / ratio

        let resultSize: Size
        switch mode {
        case .fit:
            if widthFromHeight <= maxW {
                resultSize = Size(width: widthFromHeight, height: maxH)
            } else {
                resultSize = Size(width: maxW, height: heightFromWidth)
            }
        case .fill:
            if widthFromHeight >= maxW {
                resultSize = Size(width: widthFromHeight, height: maxH)
            } else {
                resultSize = Size(width: maxW, height: heightFromWidth)
            }
        }

        return LayoutMeasurement(
            size: Size(
                width: min(max(resultSize.width, constraints.minWidth), constraints.maxWidth),
                height: min(max(resultSize.height, constraints.minHeight), constraints.maxHeight)
            )
        )
    }
}

// MARK: - Fixed Layout Box

public struct FixedLayoutBox: LayoutNode, Equatable, Sendable {
    public var preferredSize: Size
    public var flex: FlexProperties

    public init(preferredSize: Size, flex: FlexProperties = .default) {
        self.preferredSize = preferredSize
        self.flex = flex
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
