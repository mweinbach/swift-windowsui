import SwiftWindowsCore

public typealias GPUIDrawOrder = UInt32

struct GPUIPrimitiveOrdering: Equatable, Comparable, Sendable {
    var primitiveIndex: Int
    var order: GPUIDrawOrder
    var paintIndex: UInt32

    static func < (lhs: Self, rhs: Self) -> Bool {
        if lhs.order != rhs.order {
            return lhs.order < rhs.order
        }
        if lhs.paintIndex != rhs.paintIndex {
            return lhs.paintIndex < rhs.paintIndex
        }
        return lhs.primitiveIndex < rhs.primitiveIndex
    }
}

public enum GPUILayerBatch: Equatable, Sendable {
    case shadows(Range<Int>)
    case quads(Range<Int>)
    case glyphs(Range<Int>)
    case pixelGlyphs(Range<Int>)
    case images(Range<Int>)
}

public struct GPUILayerBatchIterator: IteratorProtocol, Sendable {
    private let shadowOrderings: [GPUIPrimitiveOrdering]
    private let quadOrderings: [GPUIPrimitiveOrdering]
    private let glyphOrderings: [GPUIPrimitiveOrdering]
    private let pixelGlyphOrderings: [GPUIPrimitiveOrdering]
    private let imageOrderings: [GPUIPrimitiveOrdering]

    private var shadowsStart = 0
    private var quadsStart = 0
    private var glyphsStart = 0
    private var pixelGlyphsStart = 0
    private var imagesStart = 0

    init(
        shadowOrderings: [GPUIPrimitiveOrdering],
        quadOrderings: [GPUIPrimitiveOrdering],
        glyphOrderings: [GPUIPrimitiveOrdering],
        pixelGlyphOrderings: [GPUIPrimitiveOrdering],
        imageOrderings: [GPUIPrimitiveOrdering]
    ) {
        self.shadowOrderings = shadowOrderings
        self.quadOrderings = quadOrderings
        self.glyphOrderings = glyphOrderings
        self.pixelGlyphOrderings = pixelGlyphOrderings
        self.imageOrderings = imageOrderings
    }

    public mutating func next() -> GPUILayerBatch? {
        var heads: [(order: GPUIDrawOrder, kind: GPUIPaintPrimitiveKind)] = []
        if shadowsStart < shadowOrderings.count {
            heads.append((shadowOrderings[shadowsStart].order, .shadow))
        }
        if quadsStart < quadOrderings.count {
            heads.append((quadOrderings[quadsStart].order, .quad))
        }
        if glyphsStart < glyphOrderings.count {
            heads.append((glyphOrderings[glyphsStart].order, .glyph))
        }
        if pixelGlyphsStart < pixelGlyphOrderings.count {
            heads.append((pixelGlyphOrderings[pixelGlyphsStart].order, .pixelGlyph))
        }
        if imagesStart < imageOrderings.count {
            heads.append((imageOrderings[imagesStart].order, .image))
        }

        guard let current = heads.min(by: {
            if $0.order != $1.order {
                return $0.order < $1.order
            }
            return $0.kind.sortRank < $1.kind.sortRank
        }) else {
            return nil
        }

        switch current.kind {
        case .shadow:
            let start = shadowsStart
            let order = shadowOrderings[start].order
            while shadowsStart < shadowOrderings.count, shadowOrderings[shadowsStart].order == order {
                shadowsStart += 1
            }
            return .shadows(start..<shadowsStart)
        case .quad:
            let start = quadsStart
            let order = quadOrderings[start].order
            while quadsStart < quadOrderings.count, quadOrderings[quadsStart].order == order {
                quadsStart += 1
            }
            return .quads(start..<quadsStart)
        case .glyph:
            let start = glyphsStart
            let order = glyphOrderings[start].order
            while glyphsStart < glyphOrderings.count, glyphOrderings[glyphsStart].order == order {
                glyphsStart += 1
            }
            return .glyphs(start..<glyphsStart)
        case .pixelGlyph:
            let start = pixelGlyphsStart
            let order = pixelGlyphOrderings[start].order
            while pixelGlyphsStart < pixelGlyphOrderings.count, pixelGlyphOrderings[pixelGlyphsStart].order == order {
                pixelGlyphsStart += 1
            }
            return .pixelGlyphs(start..<pixelGlyphsStart)
        case .image:
            let start = imagesStart
            let order = imageOrderings[start].order
            while imagesStart < imageOrderings.count, imageOrderings[imagesStart].order == order {
                imagesStart += 1
            }
            return .images(start..<imagesStart)
        }
    }
}

struct GPUIBoundsTree: Sendable {
    private static let maxChildren = 12

    private struct Node: Sendable {
        var bounds: Rect
        var maxOrder: GPUIDrawOrder
        var kind: Kind
    }

    private enum Kind: Sendable {
        case leaf(order: GPUIDrawOrder)
        case internalNode(children: [Int])
    }

    private var nodes: [Node] = []
    private var root: Int?
    private var maxLeaf: Int?
    private var insertPath: [Int] = []
    private var searchStack: [Int] = []

    mutating func clear() {
        nodes.removeAll(keepingCapacity: false)
        root = nil
        maxLeaf = nil
        insertPath.removeAll(keepingCapacity: false)
        searchStack.removeAll(keepingCapacity: false)
    }

    mutating func insert(_ newBounds: Rect) -> GPUIDrawOrder {
        let maxIntersecting = findMaxOrdering(intersecting: newBounds)
        let order = maxIntersecting + 1
        let newLeafIndex = insertLeaf(bounds: newBounds, order: order)

        if let currentMaxLeaf = maxLeaf {
            if nodes[currentMaxLeaf].maxOrder < order {
                maxLeaf = newLeafIndex
            }
        } else {
            maxLeaf = newLeafIndex
        }

        return order
    }

    private mutating func findMaxOrdering(intersecting query: Rect) -> GPUIDrawOrder {
        guard let root else {
            return 0
        }

        if let maxLeaf {
            let node = nodes[maxLeaf]
            if query.intersects(node.bounds) {
                return node.maxOrder
            }
        }

        searchStack.removeAll(keepingCapacity: true)
        searchStack.append(root)

        var maxFound: GPUIDrawOrder = 0
        while let nodeIndex = searchStack.popLast() {
            let node = nodes[nodeIndex]
            if node.maxOrder <= maxFound {
                continue
            }
            if !query.intersects(node.bounds) {
                continue
            }

            switch node.kind {
            case .leaf(let order):
                maxFound = max(maxFound, order)
            case .internalNode(let children):
                for childIndex in children where nodes[childIndex].maxOrder > maxFound {
                    searchStack.append(childIndex)
                }
            }
        }

        return maxFound
    }

    private mutating func insertLeaf(bounds: Rect, order: GPUIDrawOrder) -> Int {
        let newLeafIndex = nodes.count
        nodes.append(Node(bounds: bounds, maxOrder: order, kind: .leaf(order: order)))

        guard let root else {
            self.root = newLeafIndex
            return newLeafIndex
        }

        if case .leaf = nodes[root].kind {
            let rootBounds = nodes[root].bounds
            let rootOrder = nodes[root].maxOrder
            let children = orderedChildren(first: root, firstOrder: rootOrder, second: newLeafIndex, secondOrder: order)
            let newRootIndex = nodes.count
            nodes.append(Node(
                bounds: rootBounds.union(bounds),
                maxOrder: max(rootOrder, order),
                kind: .internalNode(children: children)
            ))
            self.root = newRootIndex
            return newLeafIndex
        }

        insertPath.removeAll(keepingCapacity: true)
        var currentIndex = root

        while true {
            let current = nodes[currentIndex]
            guard case .internalNode(let children) = current.kind else {
                fatalError("Bounds tree traversal reached leaf unexpectedly")
            }

            insertPath.append(currentIndex)

            var bestChildIndex = children[0]
            var bestChildPosition = 0
            var bestCost = bounds.union(nodes[bestChildIndex].bounds).halfPerimeter

            for (position, childIndex) in children.enumerated().dropFirst() {
                let cost = bounds.union(nodes[childIndex].bounds).halfPerimeter
                if cost < bestCost {
                    bestCost = cost
                    bestChildIndex = childIndex
                    bestChildPosition = position
                }
            }

            if case .leaf = nodes[bestChildIndex].kind {
                if children.count < Self.maxChildren {
                    var updatedChildren = children
                    updatedChildren.append(newLeafIndex)
                    updatedChildren = reorderChildrenByMaxOrder(updatedChildren)
                    nodes[currentIndex].kind = .internalNode(children: updatedChildren)
                    nodes[currentIndex].bounds = nodes[currentIndex].bounds.union(bounds)
                    nodes[currentIndex].maxOrder = max(nodes[currentIndex].maxOrder, order)
                    break
                }

                let siblingBounds = nodes[bestChildIndex].bounds
                let siblingOrder = nodes[bestChildIndex].maxOrder
                let newInternalIndex = nodes.count
                nodes.append(Node(
                    bounds: siblingBounds.union(bounds),
                    maxOrder: max(siblingOrder, order),
                    kind: .internalNode(children: orderedChildren(
                        first: bestChildIndex,
                        firstOrder: siblingOrder,
                        second: newLeafIndex,
                        secondOrder: order
                    ))
                ))

                var updatedChildren = children
                updatedChildren[bestChildPosition] = newInternalIndex
                updatedChildren = reorderChildrenByMaxOrder(updatedChildren)
                nodes[currentIndex].kind = .internalNode(children: updatedChildren)
                nodes[currentIndex].bounds = unionBounds(of: updatedChildren)
                nodes[currentIndex].maxOrder = updatedChildren.map { nodes[$0].maxOrder }.max() ?? 0
                break
            }

            currentIndex = bestChildIndex
        }

        updateAncestors()
        return newLeafIndex
    }

    private mutating func updateAncestors() {
        for nodeIndex in insertPath.reversed() {
            guard case .internalNode(let children) = nodes[nodeIndex].kind else {
                continue
            }

            let reorderedChildren = reorderChildrenByMaxOrder(children)
            nodes[nodeIndex].kind = .internalNode(children: reorderedChildren)
            nodes[nodeIndex].bounds = unionBounds(of: reorderedChildren)
            nodes[nodeIndex].maxOrder = reorderedChildren.map { nodes[$0].maxOrder }.max() ?? 0
        }
    }

    private func unionBounds(of children: [Int]) -> Rect {
        var iterator = children.makeIterator()
        guard let first = iterator.next() else {
            return .zero
        }

        var bounds = nodes[first].bounds
        while let child = iterator.next() {
            bounds = bounds.union(nodes[child].bounds)
        }
        return bounds
    }

    private func orderedChildren(
        first: Int,
        firstOrder: GPUIDrawOrder,
        second: Int,
        secondOrder: GPUIDrawOrder
    ) -> [Int] {
        if firstOrder <= secondOrder {
            return [first, second]
        }
        return [second, first]
    }

    private func reorderChildrenByMaxOrder(_ children: [Int]) -> [Int] {
        children.sorted { lhs, rhs in
            let lhsOrder = nodes[lhs].maxOrder
            let rhsOrder = nodes[rhs].maxOrder
            if lhsOrder != rhsOrder {
                return lhsOrder < rhsOrder
            }
            return lhs < rhs
        }
    }
}

private extension Rect {
    func intersects(_ other: Rect) -> Bool {
        intersected(with: other) != nil
    }

    func union(_ other: Rect) -> Rect {
        guard !isEmpty else { return other }
        guard !other.isEmpty else { return self }
        let left = min(minX, other.minX)
        let top = min(minY, other.minY)
        let right = max(maxX, other.maxX)
        let bottom = max(maxY, other.maxY)
        return Rect(x: left, y: top, width: right - left, height: bottom - top)
    }

    var halfPerimeter: Double {
        size.width + size.height
    }
}

extension GPUIPaintPrimitiveKind {
    var sortRank: Int {
        switch self {
        case .shadow: return 0
        case .quad: return 1
        case .glyph: return 2
        case .pixelGlyph: return 3
        case .image: return 4
        }
    }
}
