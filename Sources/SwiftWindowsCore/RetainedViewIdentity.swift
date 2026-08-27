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
