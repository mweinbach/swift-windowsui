/// Rejection is distinct from a valid empty root. The caller keeps ownership of
/// the existing root build or window request and its normal terminal cleanup.
enum RootViewContentResult<Value> {
    case value(Value)
    case unavailable
}

/// Scope only the synchronous value factory, before component construction.
/// The original owner is checked on both sides of this indivisible callback;
/// the helper does not cancel arbitrary application work inside the callback.
@MainActor
func evaluateRootViewContent<Value>(
    in context: ViewBuildContext, while isCurrent: @MainActor () -> Bool, _ content: @MainActor () -> Value
) -> RootViewContentResult<Value> {
    guard isCurrent() else { return .unavailable }
    let value = ViewBuildContextScope.withCurrent(context) { content() }
    guard isCurrent() else { return .unavailable }
    return .value(value)
}
