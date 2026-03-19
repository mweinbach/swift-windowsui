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

public enum StackDistribution: Equatable, Sendable {
    /// Default: pack items with explicit spacing.
    case fill
    /// Equal space between items, no space at edges.
    case spaceBetween
    /// Equal space around items (half-size space at edges).
    case spaceAround
    /// Equal space including edges.
    case spaceEvenly
}

public struct FlexItem: Equatable, Sendable {
    /// Proportion of remaining space to absorb when items underflow.
    public var flexGrow: Double
    /// Proportion of excess to shed when items overflow.
    public var flexShrink: Double

    public init(flexGrow: Double = 0, flexShrink: Double = 1) {
        self.flexGrow = flexGrow
        self.flexShrink = flexShrink
    }

    public static let `default` = FlexItem()
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

// MARK: - Grid Layout

public struct GridLayout: Equatable, Sendable {
    public var columns: Int
    public var rowSpacing: Double
    public var columnSpacing: Double
    public var padding: EdgeInsets
    /// Optional explicit column widths. When provided, these widths are used
    /// instead of equal division. The array count should match `columns`.
    /// If a width is 0 or negative it receives an equal share of remaining space.
    public var columnWidths: [Double]?

    public init(
        columns: Int,
        rowSpacing: Double = 0,
        columnSpacing: Double = 0,
        padding: EdgeInsets = .zero,
        columnWidths: [Double]? = nil
    ) {
        self.columns = max(columns, 1)
        self.rowSpacing = rowSpacing
        self.columnSpacing = columnSpacing
        self.padding = padding
        self.columnWidths = columnWidths
    }

    /// Resolve the width of each column for a given available content width.
    public func resolvedColumnWidths(for availableWidth: Double) -> [Double] {
        let totalColumnSpacing = Double(max(columns - 1, 0)) * columnSpacing
        let usableWidth = max(0, availableWidth - totalColumnSpacing)

        guard let explicitWidths = columnWidths, !explicitWidths.isEmpty else {
            let equalWidth = columns > 0 ? usableWidth / Double(columns) : usableWidth
            return Array(repeating: equalWidth, count: columns)
        }

        // Pad or trim explicit widths to match column count
        var widths = Array(explicitWidths.prefix(columns))
        while widths.count < columns {
            widths.append(0)
        }

        // Sum of positive explicit widths
        let fixedTotal = widths.filter { $0 > 0 }.reduce(0, +)
        let flexCount = widths.filter { $0 <= 0 }.count

        if flexCount > 0 {
            let remaining = max(0, usableWidth - fixedTotal)
            let flexWidth = remaining / Double(flexCount)
            widths = widths.map { $0 > 0 ? $0 : flexWidth }
        }

        return widths
    }
}
