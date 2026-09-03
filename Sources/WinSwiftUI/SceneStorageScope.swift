/// Values owned by one managed window. The scope string remains diagnostic;
/// identity is this object, so reusing a string cannot revive a closed scene.
@MainActor
final class SceneStorageScope {
    private(set) var isRetired = false
    private var values: [String: Any] = [:]

    /// Revocation must precede other host cleanup that can release user code.
    func revoke() {
        isRetired = true
    }

    func releaseValues() {
        guard isRetired else { return }
        let releasedValues = values
        values = [:]
        // Payload deinitializers may reenter storage. Publish the empty table
        // first, and release outside the dictionary's exclusive mutation.
        withExtendedLifetime(releasedValues) {}
    }

    func value<Value>(for key: String, default defaultValue: Value) -> Value {
        guard !isRetired else { return defaultValue }
        return values[key] as? Value ?? defaultValue
    }

    func optionalValue<Value>(for key: String) -> Value? {
        guard !isRetired else { return nil }
        return values[key] as? Value
    }

    func setValue<Value>(_ value: Value, for key: String) {
        guard !isRetired else { return }
        let displacedValue = values[key]
        values[key] = value
        withExtendedLifetime(displacedValue) {}
    }

    func removeValue(for key: String) {
        guard !isRetired else { return }
        let displacedValue = values[key]
        values[key] = nil
        withExtendedLifetime(displacedValue) {}
    }
}
