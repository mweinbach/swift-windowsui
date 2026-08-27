/// Synchronous transaction scope shared by binding writes and the retained
/// runtime. Keeping the existing context in Core lets bindings carry state
/// updates without depending on the renderer or Windows host.
@MainActor
public enum TransactionContext {
    public static var current: Transaction?
    public static var animation: (duration: Double, easing: AnimationEasing)?

    /// Applies a transaction only for the duration of a mutation, including
    /// synchronous observation and reconciliation. Nested and throwing calls
    /// restore both the full transaction and the legacy animation context.
    public static func withValue<Result>(
        _ transaction: Transaction, _ body: () throws -> Result
    ) rethrows -> Result {
        let previous = current
        let previousAnimation = animation
        current = transaction
        animation =
            transaction.disablesAnimations
            ? nil : transaction.animation.map { ($0.duration, $0.easing) }
        defer {
            current = previous
            animation = previousAnimation
        }
        return try body()
    }
}
