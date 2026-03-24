import SwiftWindowsCore

/// Determines when the scene painter should split into a new rendering layer.
/// Layers ensure correct visual ordering when primitives are batched by type.
///
/// When rendering, all quads in a layer are drawn together, then all glyphs.
/// Siblings with different zIndex values must be painted in separate layers so
/// that higher-zIndex content draws on top of the entire lower-zIndex subtree.
public struct GPUILayerStack: Sendable {

    /// A decision about whether to split rendering into multiple layers.
    public struct LayerSplitResult: Sendable, Equatable {
        /// Groups of sibling indices, each group rendered in its own layer.
        /// If all siblings have the same zIndex, returns a single group.
        public var groups: [[Int]]
    }

    /// Analyze siblings and determine layer grouping.
    ///
    /// - Parameter siblingZIndices: The zIndex value for each sibling (in tree order).
    /// - Returns: Groups of sibling indices. Each group should be painted in a separate layer.
    ///
    /// Example: siblings with zIndices [0, 0, 1, 0, 1] produces groups [[0,1,3], [2,4]].
    /// Group 0 (zIndex=0 siblings) is painted in layer N, group 1 (zIndex=1) in layer N+1.
    public static func splitSiblings(zIndices: [Int]) -> LayerSplitResult {
        guard !zIndices.isEmpty else {
            return LayerSplitResult(groups: [[]])
        }

        // Group sibling indices by their zIndex value.
        var buckets: [Int: [Int]] = [:]
        for (index, z) in zIndices.enumerated() {
            buckets[z, default: []].append(index)
        }

        // Single zIndex — no splitting needed.
        if buckets.count == 1 {
            return LayerSplitResult(groups: [Array(zIndices.indices)])
        }

        // Sort groups by ascending zIndex.
        let sortedKeys = buckets.keys.sorted()
        let groups = sortedKeys.map { buckets[$0]! }
        return LayerSplitResult(groups: groups)
    }

    /// Determine if a node requires its own compositing layer.
    ///
    /// Reasons a node might need its own layer:
    /// - opacity < 1.0 AND has children (group opacity compositing)
    /// - has a blur effect
    ///
    /// Notes:
    /// - A transform alone does not require a layer (transforms can be applied per-primitive).
    /// - Opacity without children does not require a layer (single-element opacity is fine).
    ///
    /// - Parameters:
    ///   - opacity: Node's opacity (0.0-1.0)
    ///   - hasChildren: Whether the node has child nodes
    ///   - hasBlur: Whether the node has a blur effect
    ///   - hasTransform: Whether the node has a non-identity transform
    /// - Returns: true if this node needs its own compositing layer
    public static func needsCompositingLayer(
        opacity: Float,
        hasChildren: Bool,
        hasBlur: Bool,
        hasTransform: Bool
    ) -> Bool {
        if opacity < 1.0 && hasChildren { return true }
        if hasBlur { return true }
        return false
    }
}
