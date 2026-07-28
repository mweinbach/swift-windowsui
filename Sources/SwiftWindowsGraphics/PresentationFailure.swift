/// Renderer-neutral vocabulary for "the presentation path failed" and "the
/// presentation path is in an unusual state".
///
/// The host's fallback policy used to receive `String(describing: error)` and
/// nothing else, so it could not tell a lost GPU from an image it could not
/// upload from a capability the machine will never have — and applied one
/// permanent-downgrade rule to all three. These types are the missing
/// distinction, expressed where every backend can produce it and the host can
/// consume it without knowing which backend it is talking to.

/// What a render backend believes went wrong, in terms the host's recovery
/// policy can act on.
public enum PresentationFailureKind: String, Equatable, Sendable {
    /// The GPU device was removed, reset or hung. The backend itself is
    /// fine; its device is not. Recreating it is the correct response and
    /// the backend attempts that first — this kind only reaches the host
    /// once bounded recovery has been exhausted.
    case deviceLost
    /// A momentary failure (an allocation that did not fit, a resource still
    /// in use). Retrying later is reasonable.
    case transient
    /// This particular scene could not be rendered — an image that will not
    /// upload, a glyph atlas that never arrived. Retrying the *same* scene
    /// will fail the same way, so a recovery policy must not treat a
    /// success-then-fail cycle as progress.
    case sceneContent
    /// The machine cannot do this at all (no adapter, missing feature level,
    /// unsupported format). Retrying is pointless.
    case permanent
}

/// An error that classifies itself for the host's recovery policy.
///
/// Backends conform their own error types; anything that does not conform is
/// treated as ``PresentationFailureKind/transient``, which is the historical
/// behaviour (retry with backoff).
public protocol ClassifiedPresentationFailure: Error {
    var presentationFailureKind: PresentationFailureKind { get }
}

extension PresentationFailureKind {
    /// Classification for any error crossing a backend boundary.
    public static func classifying(_ error: Error) -> PresentationFailureKind {
        (error as? ClassifiedPresentationFailure)?.presentationFailureKind ?? .transient
    }
}

/// What the backend needs the host's frame loop to know after a render.
///
/// Both fields describe the *last* completed render, and both are cleared by
/// the next present that reaches the screen normally.
public struct PresentationState: Equatable, Sendable {
    /// The last present reported the window fully occluded. Flip-model
    /// `Present` returns immediately instead of blocking on vsync in that
    /// state, so an unthrottled frame loop burns CPU and GPU drawing frames
    /// nobody can see.
    public var isOccluded: Bool
    /// The backend rebuilt its device and the last frame did not reach the
    /// screen. Static content would otherwise stay blank until the next user
    /// interaction, so the host must schedule one more frame.
    public var needsImmediateRepaint: Bool

    public init(isOccluded: Bool = false, needsImmediateRepaint: Bool = false) {
        self.isOccluded = isOccluded
        self.needsImmediateRepaint = needsImmediateRepaint
    }
}
