import SwiftWindowsCore

/// A construction-time description of the rectangle path and its point insets.
/// It contains no authored shape, callback, paint owner, or build context.
struct RetainedRectangleTrimGeometry: Sendable {
    enum Resolution: Equatable, Sendable {
        case unavailable
        case rejected
        case rectangle(insets: [Double])
    }

    private enum Admission: Sendable {
        case unavailable
        case rejected
        case rectangle
    }

    /// Balanced immutable blocks share scalar storage between descriptor copies.
    /// A prepend merges equal-sized blocks, with the new outer block first.
    /// No block has more than 16 child edges from its root to a scalar leaf.
    private final class InsetBlock: Sendable {
        enum Contents: Sendable {
            case amount(Double)
            case pair(outer: InsetBlock, inner: InsetBlock)
        }

        let count: Int
        let contents: Contents

        init(amount: Double) {
            count = 1
            contents = .amount(amount)
        }

        init(outer: InsetBlock, inner: InsetBlock) {
            count = outer.count + inner.count
            contents = .pair(outer: outer, inner: inner)
        }
    }

    // This is a descriptor bound, not a change to PathTrimming's input or work
    // limits. Zero insets count too; none are combined or omitted here.
    static let maximumInsetOperations = 65_536
    static let unavailable = Self(admission: .unavailable)
    static let rejected = Self(admission: .rejected)
    static let rectangle = Self(admission: .rectangle)

    private let admission: Admission
    private let operationCount: Int
    private let blocks: [InsetBlock]

    private init(admission: Admission, operationCount: Int = 0, blocks: [InsetBlock] = []) {
        self.admission = admission
        self.operationCount = operationCount
        self.blocks = blocks
    }

    func prependingInset(_ amount: Double) -> Self {
        // An unknown shape stays on its existing path. Rejection of a known
        // rectangle is sticky and must never become an unavailable descriptor.
        guard case .rectangle = admission else { return self }
        guard amount.isFinite, operationCount < Self.maximumInsetOperations else { return .rejected }

        var carry = InsetBlock(amount: amount)
        var consumed = 0
        while consumed < blocks.count, blocks[consumed].count == carry.count {
            carry = InsetBlock(outer: carry, inner: blocks[consumed])
            consumed += 1
        }
        // Only the at-most-17 root references are copied, never the preceding
        // scalar sequence. AnyShape erasure just shares these immutable roots.
        var result = [carry]
        result.append(contentsOf: blocks.dropFirst(consumed))
        return Self(admission: .rectangle, operationCount: operationCount + 1, blocks: result)
    }

    /// Flatten once when the trimmed component is constructed. Its layout
    /// receiver retains this scalar array, not the authored shape or a tree.
    func resolve() -> Resolution {
        switch admission {
        case .unavailable: return .unavailable
        case .rejected: return .rejected
        case .rectangle: break
        }

        var insets: [Double] = []
        insets.reserveCapacity(operationCount)
        var pending: [InsetBlock] = []
        for root in blocks {
            pending.append(root)
            while let block = pending.popLast() {
                switch block.contents {
                case .amount(let amount): insets.append(amount)
                case .pair(let outer, let inner):
                    pending.append(inner)
                    pending.append(outer)
                }
            }
        }
        return .rectangle(insets: insets)
    }

    /// Match InsetShape.path's ordered arithmetic, including reversed rectangle
    /// edges when the derived width or height is negative. Rendering rejects
    /// nonfinite intermediates instead of retrying the unit-rectangle route.
    static func path(in bounds: Rect, insets: [Double]) -> Path? {
        func finite(_ rect: Rect) -> Bool {
            rect.origin.x.isFinite && rect.origin.y.isFinite
                && rect.size.width.isFinite && rect.size.height.isFinite
                && rect.maxX.isFinite && rect.maxY.isFinite
        }

        guard insets.count <= maximumInsetOperations, finite(bounds) else { return nil }
        var rect = bounds
        for amount in insets {
            guard amount.isFinite else { return nil }
            let next = Rect(
                origin: Point(x: rect.minX + amount, y: rect.minY + amount),
                size: Size(width: rect.size.width - amount * 2, height: rect.size.height - amount * 2))
            guard finite(next) else { return nil }
            rect = next
        }
        return Path(rect)
    }
}

@MainActor
protocol RetainedRectangleTrimGeometryProvider {
    var retainedRectangleTrimGeometry: RetainedRectangleTrimGeometry { get }
}

@MainActor
func resolvedRectangleTrimGeometry<S: Shape>(for shape: S) -> RetainedRectangleTrimGeometry {
    (shape as? any RetainedRectangleTrimGeometryProvider)?.retainedRectangleTrimGeometry ?? .unavailable
}
