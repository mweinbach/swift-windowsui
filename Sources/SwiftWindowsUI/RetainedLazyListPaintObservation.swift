import SwiftWindowsCore

/// Native observations taken before the ordinary painter can call application
/// code. The runtime pairs this with its presentation mutation revision; a
/// completed paint may only reuse these original witnesses and poses.
@MainActor
final class RetainedLazyListPaintObservation {
    @MainActor
    struct Entry {
        weak var node: ViewNode?
        let attachment: RetainedLazyListAttachmentProof
        let identity: RetainedLazyListViewIdentityProof
        let initialOpacity: Double
        let initialTransform: Transform2D
        let initialPaintAlphasAreUnit: Bool
        let canvasAlpha: RetainedLazyListCanvasPaintAlpha?

        fileprivate init(node: ViewNode) {
            self.node = node
            attachment = node.captureLazyListAttachmentProof()
            identity = node.captureLazyListIdentityProof()
            initialOpacity = node.opacity
            initialTransform = node.transform
            initialPaintAlphasAreUnit = RetainedLazyListPaintAlpha.isUnit(in: node)
            canvasAlpha = node.captureLazyListCanvasPaintAlpha()
        }

        var isCurrent: Bool { attachment.isCurrent && identity.isCurrent }

        var permitsInheritedOpacityProjection: Bool {
            initialPaintAlphasAreUnit && (canvasAlpha?.permitsProjection ?? true)
        }
    }

    private let completion: RetainedLazyListAdoptionCompletion
    private let entries: [ObjectIdentifier: Entry]

    init?(root: ViewNode) {
        guard let completion = RetainedLazyListAdoptionCompletion(of: root), completion.isCurrent else {
            return nil
        }
        var pending = [(node: root, depth: 0)]
        var entries: [ObjectIdentifier: Entry] = [:]
        while let (node, depth) = pending.popLast() {
            let identity = ObjectIdentifier(node)
            guard depth <= ViewNode.maximumTraversalDepth, entries[identity] == nil else { return nil }
            entries[identity] = Entry(node: node)
            for child in node.children {
                guard child.parent === node, child.hasSameLazyListRuntime(as: node) else { return nil }
                pending.append((child, depth + 1))
            }
        }
        guard completion.isCurrent else { return nil }
        self.completion = completion
        self.entries = entries
    }

    var isCurrent: Bool { completion.isCurrent }

    /// The caller checks the complete observation once before its callback-free
    /// recording walk. Lookup checks this node again without repeatedly walking
    /// the whole physical tree, and never creates a replacement proof.
    func entry(for node: ViewNode) -> Entry? {
        guard let entry = entries[ObjectIdentifier(node)], entry.node === node, entry.isCurrent else { return nil }
        return entry
    }
}

/// One Canvas assignment on one physical attachment. The painter captures this
/// native object before invoking the existing callback, so old output cannot
/// certify a replacement assignment or attachment. No command is retained.
@MainActor
final class RetainedLazyListCanvasPaintAlpha {
    private var hasRecorded = false
    private var remainedUnit = true

    var permitsProjection: Bool { hasRecorded && remainedUnit }

    func record(_ operations: [CanvasGraphicsContext.Operation]) {
        hasRecorded = true
        // Several isolated or nested paints can use the same callback. An
        // unsupported occurrence cannot be overwritten by a later valid one.
        if remainedUnit { remainedUnit = RetainedLazyListPaintAlpha.isUnit(in: operations) }
    }
}
