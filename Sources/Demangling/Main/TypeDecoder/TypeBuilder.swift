// Protocol for building types from mangled nodes

public protocol TypeBuilder {
    associatedtype BuiltType
    associatedtype BuiltTypeDecl
    associatedtype BuiltProtocolDecl
    associatedtype BuiltSILBoxField
    associatedtype BuiltSubstitution
    associatedtype BuiltRequirement
    associatedtype BuiltInverseRequirement
    associatedtype BuiltLayoutConstraint
    associatedtype BuiltGenericSignature
    associatedtype BuiltSubstitutionMap

    func decodeMangledType(node: Node?, forRequirement: Bool) throws(TypeLookupError) -> BuiltType

    /// Get mangling flavor
    func getManglingFlavor() -> ManglingFlavor

    func createRequirement(kind: RequirementKind, subjectType: BuiltType, constraintType: BuiltType) -> BuiltRequirement

    func createRequirement(kind: RequirementKind, subjectType: BuiltType, layout: BuiltLayoutConstraint) -> BuiltRequirement

    func createSubstitution(firstType: BuiltType, secondType: BuiltType) -> BuiltSubstitution

    func createSILBoxField(type: BuiltType, isMutable: Bool) -> BuiltSILBoxField

    // Create type declarations
    func createTypeDecl(node: Node, typeAlias: inout Bool) -> BuiltTypeDecl?
    func createProtocolDecl(node: Node) -> BuiltProtocolDecl?

    // Create nominal types
    func createNominalType(typeDecl: BuiltTypeDecl, parent: BuiltType?) -> BuiltType
    func createBoundGenericType(typeDecl: BuiltTypeDecl, args: [BuiltType], parent: BuiltType?) -> BuiltType
    func createTypeAliasType(typeDecl: BuiltTypeDecl, parent: BuiltType?) -> BuiltType

    // Create metatypes
    func createMetatypeType(instance: BuiltType, repr: ImplMetatypeRepresentation?) -> BuiltType
    func createExistentialMetatypeType(instance: BuiltType, repr: ImplMetatypeRepresentation?) -> BuiltType

    // Create protocol compositions and existentials
    func createProtocolCompositionType(protocols: [BuiltProtocolDecl], superclass: BuiltType?, isClassBound: Bool, forRequirement: Bool) -> BuiltType
    func createProtocolCompositionType(protocol: BuiltProtocolDecl, superclass: BuiltType?, isClassBound: Bool, forRequirement: Bool) -> BuiltType
    func createConstrainedExistentialType(base: BuiltType, requirements: [BuiltRequirement], inverseRequirements: [BuiltInverseRequirement]) -> BuiltType
    func createSymbolicExtendedExistentialType(shapeNode: Node, args: [BuiltType]) -> BuiltType

    /// Create function types
    func createFunctionType(
        parameters: [FunctionParam<BuiltType>],
        result: BuiltType,
        flags: FunctionTypeFlags,
        extFlags: ExtendedFunctionTypeFlags,
        diffKind: FunctionMetadataDifferentiabilityKind,
        globalActorType: BuiltType?,
        thrownErrorType: BuiltType?
    ) -> BuiltType

    func createImplFunctionType(
        calleeConvention: ImplParameterConvention,
        coroutineKind: ImplCoroutineKind,
        parameters: [ImplFunctionParam<BuiltType>],
        yields: [ImplFunctionYield<BuiltType>],
        results: [ImplFunctionResult<BuiltType>],
        errorResult: ImplFunctionResult<BuiltType>?,
        flags: ImplFunctionTypeFlags
    ) -> BuiltType

    // Create tuple and pack types
    func createTupleType(elements: [BuiltType], labels: [String?]) -> BuiltType
    func createPackType(elements: [BuiltType]) -> BuiltType
    func createSILPackType(elements: [BuiltType], isElementAddress: Bool) -> BuiltType
    func createExpandedPackElement(type: BuiltType) -> BuiltType

    // Create generic types
    func createGenericTypeParameterType(depth: Int, index: Int) -> BuiltType
    func createDependentMemberType(member: String, base: BuiltType) -> BuiltType
    func createDependentMemberType(member: String, base: BuiltType, protocol: BuiltProtocolDecl) -> BuiltType

    // Create reference types
    func createUnownedStorageType(base: BuiltType) -> BuiltType
    func createUnmanagedStorageType(base: BuiltType) -> BuiltType
    func createWeakStorageType(base: BuiltType) -> BuiltType

    // Create SIL types
    func createSILBoxType(base: BuiltType) -> BuiltType
    func createSILBoxTypeWithLayout(
        fields: [BuiltSILBoxField],
        substitutions: [BuiltSubstitution],
        requirements: [BuiltRequirement],
        inverseRequirements: [BuiltInverseRequirement]
    ) -> BuiltType

    // Create special types
    func createDynamicSelfType(base: BuiltType) -> BuiltType
    func createOpaqueType(descriptor: Node, genericArgs: [ArraySlice<BuiltType>], ordinal: Int) -> BuiltType
    func resolveOpaqueType(descriptor: Node, genericArgs: [ArraySlice<BuiltType>], ordinal: UInt64) -> BuiltType
    func createBuiltinType(name: String, mangledName: String) -> BuiltType

    // Create sugared types
    func createOptionalType(base: BuiltType) -> BuiltType
    func createArrayType(element: BuiltType) -> BuiltType
    func createDictionaryType(key: BuiltType, value: BuiltType) -> BuiltType
    func createInlineArrayType(count: BuiltType, element: BuiltType) -> BuiltType

    // Create integer types
    func createIntegerType(value: Int) -> BuiltType
    func createNegativeIntegerType(value: Int) -> BuiltType

    /// Create builtin array types
    func createBuiltinFixedArrayType(size: BuiltType, element: BuiltType) -> BuiltType

    // Objective-C support
    #if canImport(ObjectiveC)
    func createObjCClassType(name: String) -> BuiltType
    func createObjCProtocolDecl(name: String) -> BuiltProtocolDecl
    func createBoundGenericObjCClassType(name: String, args: [BuiltType]) -> BuiltType
    #endif

    // Requirements and layout constraints
    func createInverseRequirement(subjectType: BuiltType, kind: InvertibleProtocolKind) -> BuiltInverseRequirement
    func getLayoutConstraint(kind: LayoutConstraintKind) -> BuiltLayoutConstraint
    func getLayoutConstraintWithSizeAlign(kind: LayoutConstraintKind, size: Int, alignment: Int) -> BuiltLayoutConstraint

    /// Check if type is existential
    func isExistential(type: BuiltType) -> Bool

    // Pack expansion support
    func beginPackExpansion(countType: BuiltType) -> Int
    func advancePackExpansion(index: Int)
    func endPackExpansion()

    // Generic parameter management
    func pushGenericParams(parameterPacks: [(Int, Int)])
    func popGenericParams()
}
