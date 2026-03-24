import SwiftWindowsCore

// MARK: - Flexbox Enums

public enum FlexDirection: Sendable, Equatable {
    case row, rowReverse, column, columnReverse
}

public enum FlexWrap: Sendable, Equatable {
    case noWrap, wrap, wrapReverse
}

public enum JustifyContent: Sendable, Equatable {
    case flexStart, flexEnd, center, spaceBetween, spaceAround, spaceEvenly
}

public enum AlignItems: Sendable, Equatable {
    case flexStart, flexEnd, center, stretch
}

public enum AlignSelf: Sendable, Equatable {
    case auto, flexStart, flexEnd, center, stretch
}

public enum FlexBasis: Sendable, Equatable {
    case auto
    case fixed(Double)
}

// MARK: - Flex Container Style

public struct FlexStyle: Sendable, Equatable {
    public var direction: FlexDirection
    public var wrap: FlexWrap
    public var justifyContent: JustifyContent
    public var alignItems: AlignItems
    public var gap: Double
    public var padding: EdgeInsets

    public init(
        direction: FlexDirection = .row,
        wrap: FlexWrap = .noWrap,
        justifyContent: JustifyContent = .flexStart,
        alignItems: AlignItems = .stretch,
        gap: Double = 0,
        padding: EdgeInsets = .zero
    ) {
        self.direction = direction
        self.wrap = wrap
        self.justifyContent = justifyContent
        self.alignItems = alignItems
        self.gap = gap
        self.padding = padding
    }
}

// MARK: - Flex Item Style

public struct FlexItemStyle: Sendable, Equatable {
    public var grow: Double
    public var shrink: Double
    public var basis: FlexBasis
    public var alignSelf: AlignSelf?

    public init(
        grow: Double = 0,
        shrink: Double = 1,
        basis: FlexBasis = .auto,
        alignSelf: AlignSelf? = nil
    ) {
        self.grow = grow
        self.shrink = shrink
        self.basis = basis
        self.alignSelf = alignSelf
    }
}
