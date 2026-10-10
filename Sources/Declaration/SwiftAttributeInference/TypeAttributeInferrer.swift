import SwiftDeclaration
import MachOSwiftSection
import Demangling

/// Infers type-level Swift attributes by analyzing a `TypeDefinition`'s members and metadata flags.
///
/// Detectable attributes:
/// - `@propertyWrapper`: type has a `wrappedValue` stored field or computed variable
/// - `@resultBuilder`: type has a `static buildBlock` method
/// - `@dynamicMemberLookup`: type has `subscript(dynamicMember:)`
/// - `@dynamicCallable`: type has a `dynamicallyCall` method
/// - `@objc(Name)` / `@_objcRuntimeName(Name)`: class the source renamed for
///   the ObjC runtime, as `index(in:)` read it off the class metadata
/// - `@globalActor`: type conforms to `GlobalActor` protocol
///
/// The member-based checks read the type's own members only. A `buildBlock`,
/// `subscript(dynamicMember:)` or `dynamicallyCall` declared in an extension
/// is not seen — the indexer keeps extensions in its own buckets, not on the
/// definition — so such a type prints without the attribute. (Earlier
/// versions also walked `TypeDefinition.extensions`, which nothing ever
/// fills; evolution proposal `concurrent-definition-printing` removed
/// those reads.)
///
/// The printer calls `infer(for:)` once per print and keeps the result
/// local; it is never stored on the definition.
public struct TypeAttributeInferrer: Sendable {
    public init() {}

    /// Infers all applicable type-level attributes for the given type definition.
    ///
    /// - Parameter typeDefinition: The type definition to analyze.
    /// - Returns: A sorted array of inferred `SwiftAttribute` values.
    public func infer(for typeDefinition: TypeDefinition) -> [SwiftAttribute] {
        var attributes: [SwiftAttribute] = []

        // Member-based attribute inference
        inferPropertyWrapper(typeDefinition: typeDefinition, into: &attributes)
        inferResultBuilder(typeDefinition: typeDefinition, into: &attributes)
        inferDynamicMemberLookup(typeDefinition: typeDefinition, into: &attributes)
        inferDynamicCallable(typeDefinition: typeDefinition, into: &attributes)

        // Conformance-based attributes
        inferGlobalActor(typeDefinition: typeDefinition, into: &attributes)

        // Class-specific attributes
        inferObjCType(typeDefinition: typeDefinition, into: &attributes)

        return attributes.sorted()
    }

    // MARK: - Detection Predicates (static for testability)

    /// Checks whether the type has a `wrappedValue` stored field or computed variable,
    /// which is the characteristic member of a `@propertyWrapper` type.
    static func hasWrappedValueMember(fields: [FieldDefinition], variables: [VariableDefinition]) -> Bool {
        fields.contains { $0.name == "wrappedValue" }
            || variables.contains { $0.name == "wrappedValue" }
    }

    /// Checks whether the type has a `static buildBlock` method,
    /// which is the characteristic member of a `@resultBuilder` type.
    static func hasBuildBlockMethod(staticFunctions: [FunctionDefinition]) -> Bool {
        staticFunctions.contains { $0.name == "buildBlock" }
    }

    /// Checks whether the type has a `subscript(dynamicMember:)`,
    /// which is the characteristic subscript of a `@dynamicMemberLookup` type.
    ///
    /// Detection performs a recursive preorder search of the subscript's demangled node tree
    /// for a `.labelList` node whose first child has `.text == "dynamicMember"`.
    /// The node tree is `global → getter → subscript → [context, labelList, type]`,
    /// so a recursive search is needed since `.labelList` is not a direct child of the root.
    static func hasDynamicMemberSubscript(subscripts: [SubscriptDefinition], staticSubscripts: [SubscriptDefinition]) -> Bool {
        let allSubscripts = subscripts + staticSubscripts
        return allSubscripts.contains { subscriptDefinition in
            // Use Node's preorder traversal (recursive) instead of .children (direct only)
            subscriptDefinition.node
                .first(of: .labelList)?
                .children.first?.text == "dynamicMember"
        }
    }

    /// Checks whether the type has a `dynamicallyCall` method,
    /// which is the characteristic method of a `@dynamicCallable` type.
    static func hasDynamicallyCallMethod(functions: [FunctionDefinition], staticFunctions: [FunctionDefinition]) -> Bool {
        let allFunctions = functions + staticFunctions
        return allFunctions.contains { $0.name == "dynamicallyCall" }
    }

    /// The suffix used to match the `GlobalActor` protocol in conformance names.
    /// Matches both `Swift.GlobalActor` (fully qualified) and `GlobalActor` (unqualified).
    private static let globalActorProtocolSuffix = "GlobalActor"

    /// Checks whether the type conforms to the `GlobalActor` protocol,
    /// which indicates the type is annotated with `@globalActor`.
    static func conformsToGlobalActor(conformingProtocolNames: Set<String>) -> Bool {
        conformingProtocolNames.contains { protocolName in
            protocolName == globalActorProtocolSuffix || protocolName.hasSuffix(".\(globalActorProtocolSuffix)")
        }
    }

    // MARK: - Private Inference Methods

    private func inferPropertyWrapper(typeDefinition: TypeDefinition, into attributes: inout [SwiftAttribute]) {
        if Self.hasWrappedValueMember(fields: typeDefinition.fields, variables: typeDefinition.variables) {
            attributes.append(.propertyWrapper)
        }
    }

    private func inferResultBuilder(typeDefinition: TypeDefinition, into attributes: inout [SwiftAttribute]) {
        if Self.hasBuildBlockMethod(staticFunctions: typeDefinition.staticFunctions) {
            attributes.append(.resultBuilder)
        }
    }

    private func inferDynamicMemberLookup(typeDefinition: TypeDefinition, into attributes: inout [SwiftAttribute]) {
        if Self.hasDynamicMemberSubscript(subscripts: typeDefinition.subscripts, staticSubscripts: typeDefinition.staticSubscripts) {
            attributes.append(.dynamicMemberLookup)
        }
    }

    private func inferDynamicCallable(typeDefinition: TypeDefinition, into attributes: inout [SwiftAttribute]) {
        if Self.hasDynamicallyCallMethod(functions: typeDefinition.functions, staticFunctions: typeDefinition.staticFunctions) {
            attributes.append(.dynamicCallable)
        }
    }

    private func inferGlobalActor(typeDefinition: TypeDefinition, into attributes: inout [SwiftAttribute]) {
        if Self.conformsToGlobalActor(conformingProtocolNames: typeDefinition.conformingProtocolNames) {
            attributes.append(.globalActor)
        }
    }

    /// The renamed class's attribute (evolution proposal
    /// `objc-custom-class-name`). The flag and the name live in the class
    /// metadata, not the descriptor; `TypeDefinition.index(in:)` has already
    /// read them, together with the object model that decides the spelling.
    /// The printer adds the name in parentheses.
    private func inferObjCType(typeDefinition: TypeDefinition, into attributes: inout [SwiftAttribute]) {
        switch typeDefinition.customObjCClassName?.attribute {
        case .objc:
            attributes.append(.objcType)
        case .objcRuntimeName:
            attributes.append(.objcRuntimeName)
        case nil:
            break
        }
    }
}
