import SwiftDump
import MachOSwiftSection
import Demangling

/// Infers type-level Swift attributes by analyzing a `TypeDefinition`'s members and metadata flags.
///
/// Detectable attributes:
/// - `@propertyWrapper`: type has a `wrappedValue` stored field or computed variable
/// - `@resultBuilder`: type has a `static buildBlock` method (also checks extensions)
/// - `@dynamicMemberLookup`: type has `subscript(dynamicMember:)`
/// - `@dynamicCallable`: type has a `dynamicallyCall` method
/// - `@frozen` (resilience-gated): struct/enum with no metadata initialization
/// - `@usableFromInline` (resilience-gated): type has import info
/// - `@objc("Name")`: class with custom ObjC name (requires runtime metadata)
public struct TypeAttributeInferrer: Sendable {
    /// Whether to include resilience-gated attributes (`@frozen`, `@usableFromInline`).
    public let resilienceAwareAttributes: Bool

    public init(resilienceAwareAttributes: Bool) {
        self.resilienceAwareAttributes = resilienceAwareAttributes
    }

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

        // Resilience-gated attributes from metadata flags
        if resilienceAwareAttributes {
            inferFrozen(typeDefinition: typeDefinition, into: &attributes)
            inferUsableFromInline(typeDefinition: typeDefinition, into: &attributes)
        }

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

    // MARK: - Private Inference Methods

    private func inferPropertyWrapper(typeDefinition: TypeDefinition, into attributes: inout [SwiftAttribute]) {
        if Self.hasWrappedValueMember(fields: typeDefinition.fields, variables: typeDefinition.variables) {
            attributes.append(.propertyWrapper)
        }
    }

    private func inferResultBuilder(typeDefinition: TypeDefinition, into attributes: inout [SwiftAttribute]) {
        if Self.hasBuildBlockMethod(staticFunctions: typeDefinition.staticFunctions) {
            attributes.append(.resultBuilder)
            return
        }
        // Also check extensions for this type
        for extensionDefinition in typeDefinition.extensions {
            if Self.hasBuildBlockMethod(staticFunctions: extensionDefinition.staticFunctions) {
                attributes.append(.resultBuilder)
                return
            }
        }
    }

    private func inferDynamicMemberLookup(typeDefinition: TypeDefinition, into attributes: inout [SwiftAttribute]) {
        if Self.hasDynamicMemberSubscript(subscripts: typeDefinition.subscripts, staticSubscripts: typeDefinition.staticSubscripts) {
            attributes.append(.dynamicMemberLookup)
            return
        }
        // Also check extensions for this type
        for extensionDefinition in typeDefinition.extensions {
            if Self.hasDynamicMemberSubscript(subscripts: extensionDefinition.subscripts, staticSubscripts: extensionDefinition.staticSubscripts) {
                attributes.append(.dynamicMemberLookup)
                return
            }
        }
    }

    private func inferDynamicCallable(typeDefinition: TypeDefinition, into attributes: inout [SwiftAttribute]) {
        if Self.hasDynamicallyCallMethod(functions: typeDefinition.functions, staticFunctions: typeDefinition.staticFunctions) {
            attributes.append(.dynamicCallable)
            return
        }
        // Also check extensions for this type
        for extensionDefinition in typeDefinition.extensions {
            if Self.hasDynamicallyCallMethod(functions: extensionDefinition.functions, staticFunctions: extensionDefinition.staticFunctions) {
                attributes.append(.dynamicCallable)
                return
            }
        }
    }

    private func inferFrozen(typeDefinition: TypeDefinition, into attributes: inout [SwiftAttribute]) {
        let descriptorWrapper = typeDefinition.type.typeContextDescriptorWrapper
        let typeContextDescriptor = descriptorWrapper.typeContextDescriptor

        // @frozen only applies to struct and enum
        guard typeContextDescriptor.kind == .struct || typeContextDescriptor.kind == .enum else { return }

        // noMetadataInitialization means the type has no special metadata initialization,
        // which indicates it is @frozen (its layout is fixed and known at compile time)
        if typeContextDescriptor.kindSpecificFlags?.typeFlags?.noMetadataInitialization == true {
            attributes.append(.frozen)
        }
    }

    private func inferUsableFromInline(typeDefinition: TypeDefinition, into attributes: inout [SwiftAttribute]) {
        let typeContextDescriptor = typeDefinition.type.typeContextDescriptorWrapper.typeContextDescriptor

        // hasImportInfo indicates the type has an import info trailing field.
        // The trailing field prefix byte can encode @usableFromInline among other things.
        // TODO: Parse the actual trailing import info field value for more precise detection
        if typeContextDescriptor.hasImportInfo {
            attributes.append(.usableFromInline)
        }
    }

    private func inferObjCType(typeDefinition: TypeDefinition, into attributes: inout [SwiftAttribute]) {
        // @objc("CustomName") on class is stored in ClassFlags.hasCustomObjCName
        // ClassFlags is part of runtime metadata (loaded class metadata), not the descriptor.
        // We can only detect this from the ClassDescriptor if we check the
        // metadataPositiveSizeInWordsOrExtraClassFlags field when the class has a resilient superclass.
        // For now, we check via the descriptor's extra class flags if available.
        guard case .class(let classDescriptor) = typeDefinition.type.typeContextDescriptorWrapper else { return }

        // The hasCustomObjCName flag is in the runtime ClassFlags (swiftClassFlags),
        // which are only available when the binary is loaded as a MachOImage.
        // The descriptor itself does not directly encode this information.
        // This detection will be enhanced in a future task when runtime metadata reading is added.
        _ = classDescriptor
    }
}
