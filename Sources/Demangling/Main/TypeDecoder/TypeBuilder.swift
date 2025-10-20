/// Protocol for building types from mangled nodes
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

    // Get mangling flavor
    func getManglingFlavor() -> ManglingFlavor

    // Create type declarations
    func createTypeDecl(_ node: Node, _ typeAlias: inout Bool) -> BuiltTypeDecl?
    func createProtocolDecl(_ node: Node) -> BuiltProtocolDecl?

    // Create nominal types
    func createNominalType(_ typeDecl: BuiltTypeDecl, _ parent: BuiltType?) -> BuiltType
    func createBoundGenericType(_ typeDecl: BuiltTypeDecl, _ args: [BuiltType], _ parent: BuiltType?) -> BuiltType
    func createTypeAliasType(_ typeDecl: BuiltTypeDecl, _ parent: BuiltType?) -> BuiltType

    // Create metatypes
    func createMetatypeType(_ instance: BuiltType, _ repr: ImplMetatypeRepresentation?) -> BuiltType
    func createExistentialMetatypeType(_ instance: BuiltType, _ repr: ImplMetatypeRepresentation?) -> BuiltType

    // Create protocol compositions and existentials
    func createProtocolCompositionType(_ protocols: [BuiltProtocolDecl], _ superclass: BuiltType?, _ isClassBound: Bool, _ forRequirement: Bool) -> BuiltType
    func createProtocolCompositionType(_ protocol: BuiltProtocolDecl, _ superclass: BuiltType?, _ isClassBound: Bool, _ forRequirement: Bool) -> BuiltType
    func createConstrainedExistentialType(_ base: BuiltType, _ requirements: [BuiltRequirement], _ inverseRequirements: [BuiltInverseRequirement]) -> BuiltType
    func createSymbolicExtendedExistentialType(_ shapeNode: Node, _ args: [BuiltType]) -> BuiltType

    // Create function types
    func createFunctionType(
        _ parameters: [FunctionParam<BuiltType>],
        _ result: BuiltType,
        _ flags: FunctionTypeFlags,
        _ extFlags: ExtendedFunctionTypeFlags,
        _ diffKind: FunctionMetadataDifferentiabilityKind,
        _ globalActorType: BuiltType?,
        _ thrownErrorType: BuiltType?
    ) -> BuiltType

    func createImplFunctionType(
        _ calleeConvention: ImplParameterConvention,
        _ coroutineKind: ImplCoroutineKind,
        _ parameters: [ImplFunctionParam<BuiltType>],
        _ yields: [ImplFunctionYield<BuiltType>],
        _ results: [ImplFunctionResult<BuiltType>],
        _ errorResult: ImplFunctionResult<BuiltType>?,
        _ flags: ImplFunctionTypeFlags
    ) -> BuiltType

    // Create tuple and pack types
    func createTupleType(_ elements: [BuiltType], _ labels: [String?]) -> BuiltType
    func createPackType(_ elements: [BuiltType]) -> BuiltType
    func createSILPackType(_ elements: [BuiltType], _ isElementAddress: Bool) -> BuiltType
    func createExpandedPackElement(_ type: BuiltType) -> BuiltType

    // Create generic types
    func createGenericTypeParameterType(_ depth: Int, _ index: Int) -> BuiltType
    func createDependentMemberType(_ member: String, _ base: BuiltType) -> BuiltType
    func createDependentMemberType(_ member: String, _ base: BuiltType, _ protocol: BuiltProtocolDecl) -> BuiltType

    // Create reference types
    func createUnownedStorageType(_ base: BuiltType) -> BuiltType
    func createUnmanagedStorageType(_ base: BuiltType) -> BuiltType
    func createWeakStorageType(_ base: BuiltType) -> BuiltType

    // Create SIL types
    func createSILBoxType(_ base: BuiltType) -> BuiltType
    func createSILBoxTypeWithLayout(
        _ fields: [BuiltSILBoxField],
        _ substitutions: [BuiltSubstitution],
        _ requirements: [BuiltRequirement],
        _ inverseRequirements: [BuiltInverseRequirement]
    ) -> BuiltType

    // Create special types
    func createDynamicSelfType(_ base: BuiltType) -> BuiltType
    func createOpaqueType(_ descriptor: Node, _ genericArgs: [ArraySlice<BuiltType>], _ ordinal: Int) -> BuiltType
    func resolveOpaqueType(_ descriptor: Node, _ genericArgs: [ArraySlice<BuiltType>], _ ordinal: UInt64) -> BuiltType
    func createBuiltinType(_ name: String, _ mangledName: String) -> BuiltType

    // Create sugared types
    func createOptionalType(_ base: BuiltType) -> BuiltType
    func createArrayType(_ element: BuiltType) -> BuiltType
    func createDictionaryType(_ key: BuiltType, _ value: BuiltType) -> BuiltType
    func createInlineArrayType(_ count: BuiltType, _ element: BuiltType) -> BuiltType

    // Create integer types
    func createIntegerType(_ value: Int) -> BuiltType
    func createNegativeIntegerType(_ value: Int) -> BuiltType

    // Create builtin array types
    func createBuiltinFixedArrayType(_ size: BuiltType, _ element: BuiltType) -> BuiltType

    // Objective-C support
    #if canImport(ObjectiveC)
    func createObjCClassType(_ name: String) -> BuiltType
    func createObjCProtocolDecl(_ name: String) -> BuiltProtocolDecl
    func createBoundGenericObjCClassType(_ name: String, _ args: [BuiltType]) -> BuiltType
    #endif

    // Requirements and layout constraints
    func createInverseRequirement(_ subjectType: BuiltType, _ kind: InvertibleProtocolKind) -> BuiltInverseRequirement
    func getLayoutConstraint(_ kind: LayoutConstraintKind) -> BuiltLayoutConstraint
    func getLayoutConstraintWithSizeAlign(_ kind: LayoutConstraintKind, _ size: Int, _ alignment: Int) -> BuiltLayoutConstraint

    // Check if type is existential
    func isExistential(_ type: BuiltType) -> Bool

    // Pack expansion support
    func beginPackExpansion(_ countType: BuiltType) -> Int
    func advancePackExpansion(_ index: Int)
    func endPackExpansion()

    // Generic parameter management
    func pushGenericParams(_ parameterPacks: [(Int, Int)])
    func popGenericParams()
}
