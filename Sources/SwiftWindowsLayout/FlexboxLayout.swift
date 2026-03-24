import SwiftWindowsCore

public enum FlexboxEngine {
    public struct LayoutInput: Sendable {
        public var containerWidth: Double
        public var containerHeight: Double
        public var style: FlexStyle
        public var children: [ChildInput]

        public struct ChildInput: Sendable {
            public var itemStyle: FlexItemStyle
            public var intrinsicWidth: Double
            public var intrinsicHeight: Double

            public init(
                itemStyle: FlexItemStyle = FlexItemStyle(),
                intrinsicWidth: Double = 0,
                intrinsicHeight: Double = 0
            ) {
                self.itemStyle = itemStyle
                self.intrinsicWidth = intrinsicWidth
                self.intrinsicHeight = intrinsicHeight
            }
        }

        public init(
            containerWidth: Double,
            containerHeight: Double,
            style: FlexStyle,
            children: [ChildInput]
        ) {
            self.containerWidth = containerWidth
            self.containerHeight = containerHeight
            self.style = style
            self.children = children
        }
    }

    public struct ChildLayout: Sendable, Equatable {
        public var x: Double
        public var y: Double
        public var width: Double
        public var height: Double

        public init(x: Double, y: Double, width: Double, height: Double) {
            self.x = x
            self.y = y
            self.width = width
            self.height = height
        }
    }

    /// Compute child layouts for a flex container.
    public static func layout(_ input: LayoutInput) -> [ChildLayout] {
        let children = input.children
        guard !children.isEmpty else { return [] }

        let style = input.style
        let padding = style.padding

        let contentWidth = max(0, input.containerWidth - padding.leading - padding.trailing)
        let contentHeight = max(0, input.containerHeight - padding.top - padding.bottom)

        let isRow = style.direction == .row || style.direction == .rowReverse
        let isReversed = style.direction == .rowReverse || style.direction == .columnReverse

        let mainExtent = isRow ? contentWidth : contentHeight
        let crossExtent = isRow ? contentHeight : contentWidth

        // Step 1: Determine base sizes from basis/intrinsic sizes
        var mainSizes = children.map { child -> Double in
            switch child.itemStyle.basis {
            case .fixed(let value):
                return value
            case .auto:
                return isRow ? child.intrinsicWidth : child.intrinsicHeight
            }
        }

        var crossSizes = children.map { child -> Double in
            isRow ? child.intrinsicHeight : child.intrinsicWidth
        }

        // Step 2: Compute total gaps
        let totalGap = children.count > 1 ? style.gap * Double(children.count - 1) : 0
        let availableMain = max(0, mainExtent - totalGap)

        // Step 3: Distribute remaining space via grow / shrink
        let totalBaseMain = mainSizes.reduce(0, +)

        if totalBaseMain < availableMain {
            // Grow
            let remaining = availableMain - totalBaseMain
            let totalGrow = children.reduce(0.0) { $0 + $1.itemStyle.grow }
            if totalGrow > 0 {
                var leftover = remaining
                for i in children.indices {
                    guard children[i].itemStyle.grow > 0 else { continue }
                    let share: Double
                    if i == children.count - 1 {
                        share = leftover
                    } else {
                        share = remaining * (children[i].itemStyle.grow / totalGrow)
                        leftover -= share
                    }
                    mainSizes[i] += share
                }
            }
        } else if totalBaseMain > availableMain {
            // Shrink
            let deficit = totalBaseMain - availableMain
            let totalShrink = children.reduce(0.0) { $0 + $1.itemStyle.shrink }
            if totalShrink > 0 {
                var leftover = deficit
                for i in children.indices {
                    guard children[i].itemStyle.shrink > 0 else { continue }
                    let share: Double
                    if i == children.count - 1 {
                        share = leftover
                    } else {
                        share = deficit * (children[i].itemStyle.shrink / totalShrink)
                        leftover -= share
                    }
                    mainSizes[i] = max(0, mainSizes[i] - share)
                }
            }
        }

        // Step 4: Position on main axis via justifyContent
        let usedMain = mainSizes.reduce(0, +) + totalGap
        let freeMain = max(0, mainExtent - usedMain)

        let mainStart: Double
        let effectiveGap: Double

        switch style.justifyContent {
        case .flexStart:
            mainStart = 0
            effectiveGap = style.gap
        case .flexEnd:
            mainStart = freeMain
            effectiveGap = style.gap
        case .center:
            mainStart = freeMain * 0.5
            effectiveGap = style.gap
        case .spaceBetween:
            mainStart = 0
            if children.count > 1 {
                let itemsTotal = mainSizes.reduce(0, +)
                let freeSpace = max(0, mainExtent - itemsTotal)
                effectiveGap = freeSpace / Double(children.count - 1)
            } else {
                effectiveGap = 0
            }
        case .spaceAround:
            let itemsTotal = mainSizes.reduce(0, +)
            let freeSpace = max(0, mainExtent - itemsTotal)
            let slotSpace = children.count > 0 ? freeSpace / Double(children.count) : 0
            mainStart = slotSpace * 0.5
            effectiveGap = slotSpace
        case .spaceEvenly:
            let itemsTotal = mainSizes.reduce(0, +)
            let freeSpace = max(0, mainExtent - itemsTotal)
            let slotSpace = children.count > 0 ? freeSpace / Double(children.count + 1) : 0
            mainStart = slotSpace
            effectiveGap = slotSpace
        }

        // Step 5: Build positions
        var mainPositions = [Double](repeating: 0, count: children.count)
        var cursor = mainStart
        for i in children.indices {
            mainPositions[i] = cursor
            cursor += mainSizes[i] + effectiveGap
        }

        // Step 6: Position on cross axis via alignItems/alignSelf
        var crossPositions = [Double](repeating: 0, count: children.count)
        for i in children.indices {
            let alignment = resolvedCrossAlignment(
                itemAlign: children[i].itemStyle.alignSelf,
                containerAlign: style.alignItems
            )

            switch alignment {
            case .stretch:
                crossSizes[i] = crossExtent
                crossPositions[i] = 0
            case .flexStart:
                crossPositions[i] = 0
            case .flexEnd:
                crossPositions[i] = crossExtent - crossSizes[i]
            case .center:
                crossPositions[i] = (crossExtent - crossSizes[i]) * 0.5
            }
        }

        // Step 7: Handle reverse and convert to x/y
        if isReversed {
            for i in children.indices {
                mainPositions[i] = mainExtent - mainPositions[i] - mainSizes[i]
            }
        }

        var results = [ChildLayout](repeating: ChildLayout(x: 0, y: 0, width: 0, height: 0), count: children.count)
        for i in children.indices {
            let mainPos = mainPositions[i]
            let crossPos = crossPositions[i]
            let mainSize = mainSizes[i]
            let crossSize = crossSizes[i]

            if isRow {
                results[i] = ChildLayout(
                    x: padding.leading + mainPos,
                    y: padding.top + crossPos,
                    width: mainSize,
                    height: crossSize
                )
            } else {
                results[i] = ChildLayout(
                    x: padding.leading + crossPos,
                    y: padding.top + mainPos,
                    width: crossSize,
                    height: mainSize
                )
            }
        }

        return results
    }

    private static func resolvedCrossAlignment(
        itemAlign: AlignSelf?,
        containerAlign: AlignItems
    ) -> AlignItems {
        guard let itemAlign, itemAlign != .auto else {
            return containerAlign
        }

        switch itemAlign {
        case .auto:
            return containerAlign
        case .flexStart:
            return .flexStart
        case .flexEnd:
            return .flexEnd
        case .center:
            return .center
        case .stretch:
            return .stretch
        }
    }
}
