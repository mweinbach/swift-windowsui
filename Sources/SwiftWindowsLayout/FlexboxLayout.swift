import SwiftWindowsCore

public enum FlexboxEngine {

    // MARK: - Input / Output Types

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
            style: FlexStyle = FlexStyle(),
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

    // MARK: - Layout Algorithm

    public static func layout(_ input: LayoutInput) -> [ChildLayout] {
        let children = input.children
        guard !children.isEmpty else { return [] }

        let style = input.style
        let pad = style.padding
        let isRow = style.direction == .row || style.direction == .rowReverse
        let isReverse = style.direction == .rowReverse || style.direction == .columnReverse

        // Available space after padding
        let availableMain: Double
        let availableCross: Double
        if isRow {
            availableMain = max(0, input.containerWidth - pad.leading - pad.trailing)
            availableCross = max(0, input.containerHeight - pad.top - pad.bottom)
        } else {
            availableMain = max(0, input.containerHeight - pad.top - pad.bottom)
            availableCross = max(0, input.containerWidth - pad.leading - pad.trailing)
        }

        // Step 1: Compute base main size for each child
        let baseSizes: [Double] = children.map { child in
            switch child.itemStyle.basis {
            case .fixed(let v):
                return v
            case .auto:
                return isRow ? child.intrinsicWidth : child.intrinsicHeight
            }
        }

        // Step 2: Collect into flex lines
        let lines: [FlexLine]
        if style.wrap == .noWrap {
            let indices = Array(0..<children.count)
            lines = [FlexLine(childIndices: indices)]
        } else {
            lines = buildLines(
                baseSizes: baseSizes,
                gap: style.gap,
                availableMain: availableMain
            )
        }

        // Step 3: Lay out each line
        var results = [ChildLayout](repeating: ChildLayout(x: 0, y: 0, width: 0, height: 0), count: children.count)
        var crossOffset: Double = 0

        let effectiveLines: [FlexLine]
        if style.wrap == .wrapReverse {
            effectiveLines = lines.reversed()
        } else {
            effectiveLines = lines
        }

        for line in effectiveLines {
            let lineResult = layoutLine(
                line: line,
                children: children,
                baseSizes: baseSizes,
                availableMain: availableMain,
                availableCross: availableCross,
                isRow: isRow,
                isReverse: isReverse,
                style: style,
                crossOffset: crossOffset,
                isSingleLine: lines.count == 1
            )

            crossOffset += lineResult.lineCrossSize + style.gap

            for (index, childLayout) in lineResult.layouts {
                results[index] = childLayout
            }
        }

        return results
    }

    // MARK: - Internal Types

    private struct FlexLine {
        var childIndices: [Int]
    }

    private struct LineResult {
        var layouts: [(index: Int, layout: ChildLayout)]
        var lineCrossSize: Double
    }

    // MARK: - Line Building

    private static func buildLines(
        baseSizes: [Double],
        gap: Double,
        availableMain: Double
    ) -> [FlexLine] {
        var lines: [FlexLine] = []
        var currentLine: [Int] = []
        var currentMainSize: Double = 0

        for i in 0..<baseSizes.count {
            let itemSize = baseSizes[i]
            let gapBefore = currentLine.isEmpty ? 0 : gap

            if !currentLine.isEmpty && (currentMainSize + gapBefore + itemSize) > availableMain {
                lines.append(FlexLine(childIndices: currentLine))
                currentLine = [i]
                currentMainSize = itemSize
            } else {
                currentMainSize += gapBefore + itemSize
                currentLine.append(i)
            }
        }

        if !currentLine.isEmpty {
            lines.append(FlexLine(childIndices: currentLine))
        }

        return lines
    }

    // MARK: - Per-Line Layout

    private static func layoutLine(
        line: FlexLine,
        children: [LayoutInput.ChildInput],
        baseSizes: [Double],
        availableMain: Double,
        availableCross: Double,
        isRow: Bool,
        isReverse: Bool,
        style: FlexStyle,
        crossOffset: Double,
        isSingleLine: Bool
    ) -> LineResult {
        let indices = line.childIndices
        let count = indices.count
        guard count > 0 else { return LineResult(layouts: [], lineCrossSize: 0) }

        let gap = style.gap
        let pad = style.padding

        // Resolve flexible sizes
        let totalGaps = gap * Double(count - 1)
        let lineBaseSizes = indices.map { baseSizes[$0] }
        let sumBase = lineBaseSizes.reduce(0, +)
        let remaining = availableMain - sumBase - totalGaps

        var resolvedMainSizes: [Double] = lineBaseSizes

        if remaining > 0 {
            let totalGrow = indices.map { children[$0].itemStyle.grow }.reduce(0, +)
            if totalGrow > 0 {
                for (i, idx) in indices.enumerated() {
                    let grow = children[idx].itemStyle.grow
                    resolvedMainSizes[i] = max(0, lineBaseSizes[i] + remaining * (grow / totalGrow))
                }
            }
        } else if remaining < 0 {
            let totalShrink = indices.map { children[$0].itemStyle.shrink }.reduce(0, +)
            if totalShrink > 0 {
                for (i, idx) in indices.enumerated() {
                    let shrink = children[idx].itemStyle.shrink
                    resolvedMainSizes[i] = max(0, lineBaseSizes[i] + remaining * (shrink / totalShrink))
                }
            }
        }

        // Determine cross sizes and compute line cross size
        let intrinsicCrossSizes: [Double] = indices.map { idx in
            isRow ? children[idx].intrinsicHeight : children[idx].intrinsicWidth
        }

        let lineCrossSize: Double
        if isSingleLine {
            lineCrossSize = availableCross
        } else {
            lineCrossSize = intrinsicCrossSizes.max() ?? 0
        }

        // Position on main axis using justifyContent
        let usedMain = resolvedMainSizes.reduce(0, +)
        let mainPositions = computeMainPositions(
            justifyContent: style.justifyContent,
            availableMain: availableMain,
            usedMain: usedMain,
            gap: gap,
            count: count,
            itemSizes: resolvedMainSizes
        )

        // Build child layouts
        var layouts: [(index: Int, layout: ChildLayout)] = []

        for (i, idx) in indices.enumerated() {
            let mainPos = mainPositions[i]
            let mainSize = resolvedMainSizes[i]

            // Resolve effective alignment for this child
            let effectiveAlign: AlignItems
            switch children[idx].itemStyle.alignSelf {
            case .flexStart: effectiveAlign = .flexStart
            case .flexEnd: effectiveAlign = .flexEnd
            case .center: effectiveAlign = .center
            case .stretch: effectiveAlign = .stretch
            case .auto, nil: effectiveAlign = style.alignItems
            }

            let childCrossSize: Double
            let crossPos: Double

            switch effectiveAlign {
            case .stretch:
                childCrossSize = lineCrossSize
                crossPos = crossOffset
            case .flexStart:
                childCrossSize = intrinsicCrossSizes[i]
                crossPos = crossOffset
            case .flexEnd:
                childCrossSize = intrinsicCrossSizes[i]
                crossPos = crossOffset + lineCrossSize - childCrossSize
            case .center:
                childCrossSize = intrinsicCrossSizes[i]
                crossPos = crossOffset + (lineCrossSize - childCrossSize) / 2
            }

            // Convert main/cross positions to x/y
            let finalMainPos: Double
            if isReverse {
                finalMainPos = availableMain - mainPos - mainSize
            } else {
                finalMainPos = mainPos
            }

            let x: Double
            let y: Double
            let w: Double
            let h: Double

            if isRow {
                x = finalMainPos + pad.leading
                y = crossPos + pad.top
                w = mainSize
                h = childCrossSize
            } else {
                x = crossPos + pad.leading
                y = finalMainPos + pad.top
                w = childCrossSize
                h = mainSize
            }

            layouts.append((index: idx, layout: ChildLayout(x: x, y: y, width: w, height: h)))
        }

        return LineResult(layouts: layouts, lineCrossSize: lineCrossSize)
    }

    // MARK: - Main Axis Positioning

    private static func computeMainPositions(
        justifyContent: JustifyContent,
        availableMain: Double,
        usedMain: Double,
        gap: Double,
        count: Int,
        itemSizes: [Double]
    ) -> [Double] {
        guard count > 0 else { return [] }

        let freeSpace = availableMain - usedMain

        switch justifyContent {
        case .flexStart:
            return accumulatePositions(itemSizes: itemSizes, startOffset: 0, gap: gap)

        case .flexEnd:
            let totalGaps = gap * Double(count - 1)
            let startOffset = freeSpace - totalGaps
            return accumulatePositions(itemSizes: itemSizes, startOffset: startOffset, gap: gap)

        case .center:
            let totalGaps = gap * Double(count - 1)
            let startOffset = (freeSpace - totalGaps) / 2
            return accumulatePositions(itemSizes: itemSizes, startOffset: startOffset, gap: gap)

        case .spaceBetween:
            if count == 1 {
                return [0]
            }
            let spaceBetween = freeSpace / Double(count - 1)
            return accumulatePositions(itemSizes: itemSizes, startOffset: 0, gap: spaceBetween)

        case .spaceAround:
            let spacePerItem = freeSpace / Double(count)
            let halfSpace = spacePerItem / 2
            return accumulatePositions(itemSizes: itemSizes, startOffset: halfSpace, gap: spacePerItem)

        case .spaceEvenly:
            let spaceBetween = freeSpace / Double(count + 1)
            return accumulatePositions(itemSizes: itemSizes, startOffset: spaceBetween, gap: spaceBetween)
        }
    }

    private static func accumulatePositions(
        itemSizes: [Double],
        startOffset: Double,
        gap: Double
    ) -> [Double] {
        var positions: [Double] = []
        positions.reserveCapacity(itemSizes.count)
        var pos = startOffset
        for (i, size) in itemSizes.enumerated() {
            positions.append(pos)
            if i < itemSizes.count - 1 {
                pos += size + gap
            }
        }
        return positions
    }
}
