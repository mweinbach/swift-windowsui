@_spi(Reflection) import Swift
import SwiftWindowsCore

/// A property declaration within one mounted owner. Concrete payload types
/// distinguish successive values stored in existential declarations.
struct StatePropertySlot: Hashable {
    let declaration: [AnyKeyPath]
    let concreteTypes: [ObjectIdentifier]

    init(declaration: [AnyKeyPath] = [], concreteTypes: [ObjectIdentifier] = []) {
        self.declaration = declaration
        self.concreteTypes = concreteTypes
    }
}

@MainActor
protocol MountedDynamicProperty: DynamicProperty {
    mutating func install(in owner: StateMountOwner, at slot: StatePropertySlot)
    func isInstalled(in owner: StateMountOwner, at slot: StatePropertySlot) -> Bool
}

/// An explicitly understood leaf whose stored implementation details are not
/// dynamic-property composition. Framework conformers used in immutable
/// declarations must have a no-op update that needs no local writeback.
@MainActor
protocol NonOwningDynamicProperty: DynamicProperty {}

struct DynamicPropertyInstallationError: Error, Equatable, CustomStringConvertible {
    enum Reason: String, Sendable {
        case ownerUnavailable
        case metadataUnavailable
        case unsupportedValueKind
        case incompleteFieldCoverage
        case ambiguousFieldMetadata
        case immutableProperty
        case ambiguousPropertySlot
        case changedPropertyType
        case mutatedDynamicProperty
    }

    let reason: Reason
    let type: String
    let declaration: [String]
    let detail: String

    var description: String {
        let location = declaration.isEmpty ? type : declaration.joined(separator: " -> ")
        return "Dynamic property installation \(reason.rawValue) at \(location): \(detail)"
    }
}

/// Typed local-copy installation for the pinned Swift 6.3 reflection SPI.
/// The caller must qualify runtime reflection metadata in every consumer module.
/// A local canary cannot detect a stripped zero-size consumer type: a genuine
/// empty struct and missing descriptors for zero-size fields are indistinguishable.
/// Reflection names are not required; declarations use typed key paths.
/// Custom updates may write installed values, but replacing dynamic-property
/// declarations during update is unsupported and invalidates the candidate.
@MainActor
enum DynamicPropertyInstaller {
    // Only immutable metadata/key-path plans are cached. No source values,
    // installed copies, owners, cells, or value-dependent existential plans.
    private static var fieldPlans: [ObjectIdentifier: Any] = [:]
    private static var hasValidatedMetadataCanary = false

    static func install<Root>(_ source: Root, in owner: StateMountOwner) throws -> Root {
        let slot = StatePropertySlot(concreteTypes: [ObjectIdentifier(Root.self)])
        guard let epoch = owner.installationEpoch else {
            throw failure(.ownerUnavailable, type: Root.self, at: slot, "The owner has no active build epoch")
        }
        let installation = Installation(owner: owner, epoch: epoch)
        try requireActive(installation, at: slot, type: Root.self)
        try validateMetadataCanary()
        var owningSlots: Set<StatePropertySlot> = []
        let plan = try prepare(source, at: slot, owningSlots: &owningSlots)
        try requireActive(installation, at: slot, type: Root.self)
        return try plan.apply(source, installation)
    }

    private struct Installation {
        let owner: StateMountOwner
        let epoch: StateMountEpoch
    }

    private struct PreparedValue<Value> {
        let apply: @MainActor (Value, Installation) throws -> Value
        let validate: @MainActor (Value, Installation) throws -> Void
    }

    private struct PreparedField<Root> {
        let apply: @MainActor (inout Root, Installation) throws -> Void
        let validate: @MainActor (Root, Installation) throws -> Void
    }

    private struct ReflectedField<Root> {
        let keyPath: PartialKeyPath<Root>
    }

    private struct FieldPlan<Root> {
        let fields: [ReflectedField<Root>]
    }

    private struct FieldMetadata {
        let offset: Int
        let type: Any.Type
        let kind: _MetadataKind
    }

    private struct TypeEnvelope<Value> {
        var value: Value
    }

    private struct MetadataCanary {
        var value: Int
        let flag: Bool
        var callback: () -> Void
    }

    private static func prepare<Value>(
        _ source: Value, at slot: StatePropertySlot, owningSlots: inout Set<StatePropertySlot>
    ) throws -> PreparedValue<Value> {
        let kind = try metadataKind(of: Value.self, at: slot)
        guard kind == .struct else {
            throw failure(
                .unsupportedValueKind, type: Value.self, at: slot,
                "Independent local-copy installation requires a struct; reflected kind is \(kind)")
        }

        if Value.self is any MountedDynamicProperty.Type {
            guard owningSlots.insert(slot).inserted else {
                throw failure(
                    .ambiguousPropertySlot, type: Value.self, at: slot,
                    "Distinct owning declarations have equal key paths and concrete type paths")
            }
            let validate: @MainActor (Value, Installation) throws -> Void = { value, installation in
                try requireActive(installation, at: slot, type: Value.self)
                guard let property = value as? any MountedDynamicProperty else {
                    throw changedType(Value.self, at: slot)
                }
                let matches = property.isInstalled(in: installation.owner, at: slot)
                try requireActive(installation, at: slot, type: Value.self)
                guard matches else { throw mutatedProperty(Value.self, at: slot) }
            }
            return PreparedValue(
                apply: { value, installation in
                    try requireActive(installation, at: slot, type: Value.self)
                    guard var property = value as? any MountedDynamicProperty else {
                        throw changedType(Value.self, at: slot)
                    }
                    property.install(in: installation.owner, at: slot)
                    try requireActive(installation, at: slot, type: Value.self)
                    property.update()
                    try requireActive(installation, at: slot, type: Value.self)
                    guard let installed = property as? Value else { throw changedType(Value.self, at: slot) }
                    try validate(installed, installation)
                    return installed
                }, validate: validate)
        }

        let fields: [PreparedField<Value>]
        if Value.self is any NonOwningDynamicProperty.Type {
            fields = []
        } else {
            let metadata = try fieldPlan(of: Value.self, at: slot)
            fields = try metadata.fields.map { field in
                let stored: Any = source[keyPath: field.keyPath]
                // A conditional cast may unwrap Optional or AnyHashable. Only
                // the exact stored payload can declare dynamic composition.
                guard Swift.type(of: stored) is any DynamicProperty.Type else {
                    return PreparedField(
                        apply: { _, _ in },
                        validate: { root, installation in
                            try requireActive(installation, at: slot, type: Value.self)
                            let current: Any = root[keyPath: field.keyPath]
                            guard !(Swift.type(of: current) is any DynamicProperty.Type) else {
                                throw mutatedProperty(Swift.type(of: current), at: slot)
                            }
                        })
                }
                guard let property = stored as? any DynamicProperty else {
                    throw changedType(Swift.type(of: stored), at: slot)
                }

                // Open the declared value type, not the concrete payload type:
                // WritableKeyPath<Root, Concrete> cannot write an existential
                // declaration even when its current payload is Concrete.
                @MainActor
                func open<Field>(_ declaredType: Field.Type) throws -> PreparedField<Value> {
                    if let writable = field.keyPath as? WritableKeyPath<Value, Field> {
                        return try prepareField(
                            property, writable: writable, parent: slot, owningSlots: &owningSlots)
                    }
                    guard let readOnly = field.keyPath as? KeyPath<Value, Field> else {
                        throw failure(
                            .incompleteFieldCoverage, type: declaredType, at: slot,
                            "The reflected declaration did not provide its declared typed key path")
                    }
                    return try prepareReadOnlyField(
                        property, keyPath: readOnly, parent: slot, owningSlots: &owningSlots)
                }
                return try _openExistential(type(of: field.keyPath).valueType, do: open)
            }
        }

        let validate: @MainActor (Value, Installation) throws -> Void = { value, installation in
            try requireActive(installation, at: slot, type: Value.self)
            for field in fields { try field.validate(value, installation) }
        }
        return PreparedValue(
            apply: { value, installation in
                var copy = value
                for field in fields {
                    try requireActive(installation, at: slot, type: Value.self)
                    try field.apply(&copy, installation)
                }
                if Value.self is any DynamicProperty.Type {
                    try requireActive(installation, at: slot, type: Value.self)
                    guard var property = copy as? any DynamicProperty else { throw changedType(Value.self, at: slot) }
                    property.update()
                    try requireActive(installation, at: slot, type: Value.self)
                    guard let updated = property as? Value else { throw changedType(Value.self, at: slot) }
                    copy = updated
                }
                // Custom update may change ordinary values, but cannot replace an
                // installed declaration or introduce an unvalidated owning leaf.
                try validate(copy, installation)
                return copy
            }, validate: validate)
    }

    private static func prepareField<Root, Field, Property: DynamicProperty>(
        _ property: Property, writable: WritableKeyPath<Root, Field>, parent: StatePropertySlot,
        owningSlots: inout Set<StatePropertySlot>
    ) throws -> PreparedField<Root> {
        let slot = StatePropertySlot(
            declaration: parent.declaration + [writable],
            concreteTypes: parent.concreteTypes + [ObjectIdentifier(Property.self)])
        let plan = try prepare(property, at: slot, owningSlots: &owningSlots)
        return PreparedField(
            apply: { root, installation in
                try requireActive(installation, at: slot, type: Property.self)
                let stored: Any = root[keyPath: writable]
                guard Swift.type(of: stored) == Property.self, let current = stored as? Property else {
                    throw changedType(Property.self, at: slot)
                }
                let installed = try plan.apply(current, installation)
                try requireActive(installation, at: slot, type: Property.self)
                guard let field = installed as? Field else { throw changedType(Property.self, at: slot) }
                root[keyPath: writable] = field
            },
            validate: { root, installation in
                try requireActive(installation, at: slot, type: Property.self)
                let stored: Any = root[keyPath: writable]
                guard Swift.type(of: stored) == Property.self, let current = stored as? Property else {
                    throw mutatedProperty(Property.self, at: slot)
                }
                try plan.validate(current, installation)
            })
    }

    private static func prepareReadOnlyField<Root, Field, Property: DynamicProperty>(
        _ property: Property, keyPath: KeyPath<Root, Field>, parent: StatePropertySlot,
        owningSlots: inout Set<StatePropertySlot>
    ) throws -> PreparedField<Root> {
        let slot = StatePropertySlot(
            declaration: parent.declaration + [keyPath],
            concreteTypes: parent.concreteTypes + [ObjectIdentifier(Property.self)])
        guard Property.self is any NonOwningDynamicProperty.Type,
            !(Property.self is any MountedDynamicProperty.Type)
        else {
            throw failure(
                .immutableProperty, type: Field.self, at: slot,
                "Owning and custom DynamicProperty declarations require typed writable access")
        }
        let plan = try prepare(property, at: slot, owningSlots: &owningSlots)
        return PreparedField(
            apply: { root, installation in
                try requireActive(installation, at: slot, type: Property.self)
                let stored: Any = root[keyPath: keyPath]
                guard Swift.type(of: stored) == Property.self, let current = stored as? Property else {
                    throw changedType(Property.self, at: slot)
                }
                // Known framework leaves, such as stored let bindings, have
                // no-op updates. Evaluate the validated copy without writing
                // through an immutable declaration or granting it a location.
                _ = try plan.apply(current, installation)
                try requireActive(installation, at: slot, type: Property.self)
            },
            validate: { root, installation in
                try requireActive(installation, at: slot, type: Property.self)
                let stored: Any = root[keyPath: keyPath]
                guard Swift.type(of: stored) == Property.self, let current = stored as? Property else {
                    throw mutatedProperty(Property.self, at: slot)
                }
                try plan.validate(current, installation)
            })
    }

    private static func metadataKind<Value>(of type: Value.Type, at slot: StatePropertySlot) throws -> _MetadataKind {
        var kinds: [_MetadataKind] = []
        let complete = _forEachField(of: TypeEnvelope<Value>.self) { _, _, _, kind in
            kinds.append(kind)
            return true
        }
        guard complete, kinds.count == 1, let kind = kinds.first else {
            throw failure(.metadataUnavailable, type: type, at: slot, "The typed metadata envelope was unavailable")
        }
        return kind
    }

    private static func fieldPlan<Root>(of type: Root.Type, at slot: StatePropertySlot) throws -> FieldPlan<Root> {
        if let cached = fieldPlans[ObjectIdentifier(type)] as? FieldPlan<Root> { return cached }
        var metadata: [FieldMetadata] = []
        let fieldsComplete = _forEachField(of: type) { _, offset, fieldType, kind in
            metadata.append(FieldMetadata(offset: offset, type: fieldType, kind: kind))
            return true
        }
        guard fieldsComplete else {
            throw failure(.incompleteFieldCoverage, type: type, at: slot, "Stored-field metadata enumeration stopped")
        }
        guard !metadata.isEmpty || MemoryLayout<Root>.size == 0 else {
            throw failure(
                .metadataUnavailable, type: type, at: slot,
                "A nonempty value reported no fields; runtime reflection metadata is required")
        }

        var keyPaths: [PartialKeyPath<Root>] = []
        // Swift 6.3 exposes ignoreUnknown as mutable static storage. The pinned
        // bit avoids accessing that shared variable; coverage is checked below.
        let options = _EachFieldOptions(rawValue: 1 << 1)
        let pathsComplete = _forEachFieldWithKeyPath(of: type, options: options) { _, keyPath in
            keyPaths.append(keyPath)
            return true
        }
        guard pathsComplete else {
            throw failure(.incompleteFieldCoverage, type: type, at: slot, "Typed key-path enumeration stopped")
        }

        var fields: [ReflectedField<Root>] = []
        var cursor = 0
        for field in metadata {
            // Swift's runtime substitutes Void when field-type demangling
            // fails, with no failure bit exposed by either reflection SPI.
            // This deliberately also diagnoses genuinely stored Void fields.
            guard ObjectIdentifier(field.type) != ObjectIdentifier(Void.self) else {
                throw failure(
                    .ambiguousFieldMetadata, type: type, at: slot,
                    "A stored Void field and unresolved field-type metadata cannot be distinguished")
            }
            if keyPaths.indices.contains(cursor) {
                let keyPath = keyPaths[cursor]
                if ObjectIdentifier(Swift.type(of: keyPath).valueType) == ObjectIdentifier(field.type),
                    MemoryLayout<Root>.offset(of: keyPath) == field.offset
                {
                    fields.append(ReflectedField(keyPath: keyPath))
                    cursor += 1
                    continue
                }
            }
            // Function values cannot conform to DynamicProperty. Non-strong
            // Optional fields are also omitted by this SPI; only exclude them
            // when the Optional itself has no DynamicProperty conformance.
            if field.kind == .function { continue }
            if field.kind == .optional, !(field.type is any DynamicProperty.Type) { continue }
            throw failure(
                .incompleteFieldCoverage, type: type, at: slot,
                "No typed key path covers stored field type \(String(reflecting: field.type)) at offset \(field.offset)"
            )
        }
        guard cursor == keyPaths.count else {
            throw failure(
                .incompleteFieldCoverage, type: type, at: slot, "Key paths exceeded the stored-field inventory")
        }
        let plan = FieldPlan(fields: fields)
        fieldPlans[ObjectIdentifier(type)] = plan
        return plan
    }

    private static func validateMetadataCanary() throws {
        guard !hasValidatedMetadataCanary else { return }
        let slot = StatePropertySlot(concreteTypes: [ObjectIdentifier(MetadataCanary.self)])
        guard try metadataKind(of: MetadataCanary.self, at: slot) == .struct else {
            throw failure(.metadataUnavailable, type: MetadataCanary.self, at: slot, "Unexpected adapter metadata kind")
        }
        let plan = try fieldPlan(of: MetadataCanary.self, at: slot)
        guard plan.fields.count == 2,
            plan.fields[0].keyPath == \MetadataCanary.value,
            plan.fields[1].keyPath == \MetadataCanary.flag,
            plan.fields[0].keyPath is WritableKeyPath<MetadataCanary, Int>,
            !(plan.fields[1].keyPath is WritableKeyPath<MetadataCanary, Bool>)
        else {
            throw failure(.metadataUnavailable, type: MetadataCanary.self, at: slot, "Adapter metadata canary failed")
        }
        hasValidatedMetadataCanary = true
    }

    private static func requireActive(_ installation: Installation, at slot: StatePropertySlot, type: Any.Type) throws {
        guard installation.owner.installationEpoch === installation.epoch else {
            throw failure(.ownerUnavailable, type: type, at: slot, "The owner closed, retired, or left its build epoch")
        }
    }

    private static func mutatedProperty(_ type: Any.Type, at slot: StatePropertySlot)
        -> DynamicPropertyInstallationError
    {
        failure(
            .mutatedDynamicProperty, type: type, at: slot,
            "DynamicProperty.update replaced an installed declaration or introduced a different dynamic property")
    }

    private static func changedType(_ type: Any.Type, at slot: StatePropertySlot) -> DynamicPropertyInstallationError {
        failure(
            .changedPropertyType, type: type, at: slot, "The property no longer matches its validated concrete type")
    }

    private static func failure(
        _ reason: DynamicPropertyInstallationError.Reason, type: Any.Type, at slot: StatePropertySlot, _ detail: String
    ) -> DynamicPropertyInstallationError {
        DynamicPropertyInstallationError(
            reason: reason, type: String(reflecting: type),
            declaration: slot.declaration.map { keyPath in
                // AnyKeyPath.description traps in Swift 6.3 when consumer
                // field names are stripped. Type metadata remains available.
                let root = String(reflecting: Swift.type(of: keyPath).rootType)
                let value = String(reflecting: Swift.type(of: keyPath).valueType)
                return "\(root) -> \(value)"
            },
            detail: detail)
    }
}
