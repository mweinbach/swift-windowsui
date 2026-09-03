/// Immutable native IDs used only to represent a visited set. They do not
/// certify a live parent, role, attachment, runtime, or selected-content path.
@MainActor
final class RetainedPaintAncestryBuffer {
    fileprivate let identifiers: [ObjectIdentifier]

    init?(identifiers: [ObjectIdentifier]) {
        guard !identifiers.isEmpty else { return nil }
        var seen = Set<ObjectIdentifier>()
        for identifier in identifiers {
            guard seen.insert(identifier).inserted else { return nil }
        }
        self.identifiers = identifiers
    }

    func prefix(startingAt identifier: ObjectIdentifier) -> RetainedPaintAncestryPrefix? {
        guard let start = identifiers.firstIndex(of: identifier) else { return nil }
        return RetainedPaintAncestryPrefix(buffer: self, start: start, end: identifiers.count)
    }
}

/// The starting index can skip selected descendants recorded before the
/// physical node. Only the validated buffer can construct this scalar view.
@MainActor
struct RetainedPaintAncestryPrefix {
    private let buffer: RetainedPaintAncestryBuffer
    private let start: Int
    private let end: Int

    fileprivate init(buffer: RetainedPaintAncestryBuffer, start: Int, end: Int) {
        self.buffer = buffer
        self.start = start
        self.end = end
    }

    var count: Int { end - start }

    subscript(relativeIndex: Int) -> ObjectIdentifier {
        precondition(relativeIndex >= 0 && relativeIndex < count)
        return buffer.identifiers[start + relativeIndex]
    }
}

/// Each live ancestry walk gets a fresh tracker. Matching an immutable unique
/// prefix needs no Set allocation; divergence reconstructs exactly the visited
/// IDs and permanently uses ordinary Set insertion semantics thereafter.
@MainActor
struct RetainedPaintAncestryVisitSet {
    private let prefix: RetainedPaintAncestryPrefix?
    private var matchedCount = 0
    private var fallback: Set<ObjectIdentifier>?

    init(prefix: RetainedPaintAncestryPrefix? = nil) {
        self.prefix = prefix
    }

    mutating func insert(_ identifier: ObjectIdentifier) -> (inserted: Bool, memberAfterInsert: ObjectIdentifier) {
        if let result = fallback?.insert(identifier) { return result }
        if let prefix, matchedCount < prefix.count, prefix[matchedCount] == identifier {
            matchedCount += 1
            return (inserted: true, memberAfterInsert: identifier)
        }
        var visited = Set<ObjectIdentifier>()
        if let prefix {
            var index = 0
            while index < matchedCount {
                visited.insert(prefix[index])
                index += 1
            }
        }
        let result = visited.insert(identifier)
        fallback = visited
        return result
    }
}
