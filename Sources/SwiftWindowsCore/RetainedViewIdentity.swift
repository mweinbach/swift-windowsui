/// A declarative view's typed path within its retained host.
///
/// Structural segments remain distinct from user keys so that flattening a
/// builder's output does not erase its original child or branch boundaries.
/// This value describes identity; it does not own property storage or lifetime.
public struct RetainedViewIdentity: Hashable {
    public let segments: [Segment]

    public init(segments: [Segment] = []) {
        self.segments = segments
    }

    public func appending(_ segment: Segment) -> RetainedViewIdentity {
        RetainedViewIdentity(segments: segments + [segment])
    }

    public func appending(contentsOf segments: [Segment]) -> RetainedViewIdentity {
        RetainedViewIdentity(segments: self.segments + segments)
    }

    /// Managed construction must stop after each authored key callback. Array's
    /// synthesized Hashable implementation cannot observe a revoked receipt
    /// between two keys, including identities wrapped as framework keys.
    public func checkedHash(into hasher: inout Hasher, isCurrent: () -> Bool) -> Bool {
        guard isCurrent() else { return false }
        hasher.combine(segments.count)
        for segment in segments {
            guard segment.checkedHash(into: &hasher, isCurrent: isCurrent) else { return false }
        }
        return isCurrent()
    }

    public func checkedEquals(_ other: RetainedViewIdentity, isCurrent: () -> Bool) -> Bool? {
        guard isCurrent() else { return nil }
        guard segments.count == other.segments.count else { return false }
        return checkedHasPrefix(other, isCurrent: isCurrent)
    }

    public func checkedHasPrefix(_ prefix: RetainedViewIdentity, isCurrent: () -> Bool) -> Bool? {
        guard isCurrent() else { return nil }
        guard segments.count >= prefix.segments.count else { return false }
        for index in prefix.segments.indices {
            guard let equal = segments[index].checkedEquals(prefix.segments[index], isCurrent: isCurrent) else {
                return nil
            }
            if !equal { return false }
        }
        return isCurrent() ? true : nil
    }

    /// A user key retains both its declared type and its Hashable value.
    /// String descriptions, including identical descriptions from different
    /// key types, never determine equality.
    public struct Key: Hashable {
        private let typeIdentifier: ObjectIdentifier
        private let value: AnyHashable

        public init<ID: Hashable>(_ value: ID) {
            self.typeIdentifier = ObjectIdentifier(ID.self)
            self.value = AnyHashable(value)
        }

        public func checkedHash(into hasher: inout Hasher, isCurrent: () -> Bool) -> Bool {
            guard isCurrent() else { return false }
            hasher.combine(typeIdentifier)
            if let identity = value.base as? RetainedViewIdentity {
                return identity.checkedHash(into: &hasher, isCurrent: isCurrent)
            }
            if let key = value.base as? Key {
                return key.checkedHash(into: &hasher, isCurrent: isCurrent)
            }
            if let segment = value.base as? Segment {
                return segment.checkedHash(into: &hasher, isCurrent: isCurrent)
            }
            value.hash(into: &hasher)
            return isCurrent()
        }

        public func checkedEquals(_ other: Key, isCurrent: () -> Bool) -> Bool? {
            guard isCurrent() else { return nil }
            guard typeIdentifier == other.typeIdentifier else { return false }
            if let identity = value.base as? RetainedViewIdentity,
                let otherIdentity = other.value.base as? RetainedViewIdentity
            {
                return identity.checkedEquals(otherIdentity, isCurrent: isCurrent)
            }
            if let key = value.base as? Key, let otherKey = other.value.base as? Key {
                return key.checkedEquals(otherKey, isCurrent: isCurrent)
            }
            if let segment = value.base as? Segment, let otherSegment = other.value.base as? Segment {
                return segment.checkedEquals(otherSegment, isCurrent: isCurrent)
            }
            let equal = value == other.value
            return isCurrent() ? equal : nil
        }
    }

    public enum Segment: Hashable {
        case view(ObjectIdentifier)
        case role(Role)
        case slot(Int)
        case branch(Bool)
        case iteration(Int)
        case occurrence(Int)
        case keyed(Key)
        case explicit(Key)

        fileprivate func checkedHash(into hasher: inout Hasher, isCurrent: () -> Bool) -> Bool {
            guard isCurrent() else { return false }
            switch self {
            case .keyed(let key):
                hasher.combine(0)
                return key.checkedHash(into: &hasher, isCurrent: isCurrent)
            case .explicit(let key):
                hasher.combine(1)
                return key.checkedHash(into: &hasher, isCurrent: isCurrent)
            default:
                hasher.combine(2)
                hasher.combine(self)
                return isCurrent()
            }
        }

        fileprivate func checkedEquals(_ other: Segment, isCurrent: () -> Bool) -> Bool? {
            guard isCurrent() else { return nil }
            switch (self, other) {
            case (.keyed(let lhs), .keyed(let rhs)), (.explicit(let lhs), .explicit(let rhs)):
                return lhs.checkedEquals(rhs, isCurrent: isCurrent)
            case (.keyed, _), (.explicit, _), (_, .keyed), (_, .explicit):
                return false
            default:
                return self == other
            }
        }
    }

    /// Separates independent child builders belonging to the same view.
    public enum Role: Hashable {
        case body
        case content
        case modifier
        case modifierBody
        case header
        case footer
        case title
        case icon
        case description
        case label
        case value
        case actions
        case background
        case overlay
        case mask
        case safeAreaInset
        case toolbar
        case presentation
        case sidebar
        case detail
        case destination
        case page
        case menu
        case columnHeader
        case row
        case column
        case geometryContent
    }
}
