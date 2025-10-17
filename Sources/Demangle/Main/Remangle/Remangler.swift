/// Swift name remangler - converts a demangling parse tree back into a mangled string.
///
/// This is useful for tools which want to extract or modify subtrees from mangled strings.
/// The remangler follows the same mangling conventions as the Swift compiler.
final class Remangler: RemanglerBase {
    // MARK: - Constants

    /// Maximum recursion depth to prevent stack overflow
    static let maxDepth = 1024

    /// Maximum number of substitution words
    static let maxNumWords = 26

    // MARK: - Properties

    /// Callback for resolving symbolic references
    var symbolicReferenceResolver: SymbolicReferenceResolver?

    /// Whether to use Punycode encoding for non-ASCII identifiers
    private let _usePunycode: Bool

    override var usePunycode: Bool {
        return _usePunycode
    }

    let substMerging: Mangle.SubstitutionMerging

    let flavor = ManglingFlavor.default

    // MARK: - Initialization

    init(usePunycode: Bool = true) {
        self._usePunycode = usePunycode
        self.substMerging = Mangle.SubstitutionMerging()
        super.init()
    }

    // MARK: - Public API

    /// Remangle a node tree into a mangled string
    func mangle(_ node: Node) throws(RemanglerError) -> String {
        clearBuffer()
        try mangleNode(node, depth: 0)
        return buffer
    }

    // MARK: - Core Mangling

    /// Main entry point for mangling a single node
    func mangleNode(_ node: Node, depth: Int) throws(RemanglerError) {
        // Check recursion depth
        if depth > Self.maxDepth {
            throw .tooComplex(node)
        }

        // Dispatch to specific handler based on node kind
        switch node.kind {
        case .global:
            try mangleGlobal(node, depth: depth)
        case .suffix:
            try mangleSuffix(node, depth: depth)
        case .type:
            try mangleType(node, depth: depth)
        case .typeMangling:
            try mangleTypeMangling(node, depth: depth)
        case .typeList:
            try mangleTypeList(node, depth: depth)
        case .structure:
            try mangleStructure(node, depth: depth)
        case .class:
            try mangleClass(node, depth: depth)
        case .enum:
            try mangleEnum(node, depth: depth)
        case .protocol:
            try mangleProtocol(node, depth: depth)
        case .typeAlias:
            try mangleTypeAlias(node, depth: depth)
        case .otherNominalType:
            try mangleOtherNominalType(node, depth: depth)
        case .functionType:
            try mangleFunctionType(node, depth: depth)
        case .argumentTuple:
            try mangleArgumentTuple(node, depth: depth)
        case .returnType:
            try mangleReturnType(node, depth: depth)
        case .labelList:
            try mangleLabelList(node, depth: depth)
        case .boundGenericStructure:
            try mangleBoundGenericStructure(node, depth: depth)
        case .boundGenericClass:
            try mangleBoundGenericClass(node, depth: depth)
        case .boundGenericEnum:
            try mangleBoundGenericEnum(node, depth: depth)
        case .boundGenericProtocol:
            try mangleBoundGenericProtocol(node, depth: depth)
        case .boundGenericTypeAlias:
            try mangleBoundGenericTypeAlias(node, depth: depth)
        case .identifier:
            try mangleIdentifier(node, depth: depth)
        case .privateDeclName:
            try manglePrivateDeclName(node, depth: depth)
        case .localDeclName:
            try mangleLocalDeclName(node, depth: depth)
        case .module:
            try mangleModule(node, depth: depth)
        case .extension:
            try mangleExtension(node, depth: depth)
        case .declContext:
            try mangleDeclContext(node, depth: depth)
        case .anonymousContext:
            try mangleAnonymousContext(node, depth: depth)
        case .function:
            try mangleFunction(node, depth: depth)
        case .allocator:
            try mangleAllocator(node, depth: depth)
        case .constructor:
            try mangleConstructor(node, depth: depth)
        case .destructor:
            try mangleDestructor(node, depth: depth)
        case .getter:
            try mangleGetter(node, depth: depth)
        case .setter:
            try mangleSetter(node, depth: depth)
        case .explicitClosure:
            try mangleExplicitClosure(node, depth: depth)
        case .implicitClosure:
            try mangleImplicitClosure(node, depth: depth)
        case .builtinTypeName:
            try mangleBuiltinTypeName(node, depth: depth)
        case .dynamicSelf:
            try mangleDynamicSelf(node, depth: depth)
        case .errorType:
            try mangleErrorType(node, depth: depth)
        case .tuple:
            try mangleTuple(node, depth: depth)
        case .tupleElement:
            try mangleTupleElement(node, depth: depth)
        case .tupleElementName:
            try mangleTupleElementName(node, depth: depth)
        case .dependentGenericParamType:
            try mangleDependentGenericParamType(node, depth: depth)
        case .dependentMemberType:
            try mangleDependentMemberType(node, depth: depth)
        case .protocolList:
            try mangleProtocolList(node, depth: depth)
        case .protocolListWithClass:
            try mangleProtocolListWithClass(node, depth: depth)
        case .protocolListWithAnyObject:
            try mangleProtocolListWithAnyObject(node, depth: depth)
        case .metatype:
            try mangleMetatype(node, depth: depth)
        case .existentialMetatype:
            try mangleExistentialMetatype(node, depth: depth)
        case .shared:
            try mangleShared(node, depth: depth)
        case .owned:
            try mangleOwned(node, depth: depth)
        case .weak:
            try mangleWeak(node, depth: depth)
        case .unowned:
            try mangleUnowned(node, depth: depth)
        case .unmanaged:
            try mangleUnmanaged(node, depth: depth)
        case .inOut:
            try mangleInOut(node, depth: depth)
        case .number:
            try mangleNumber(node, depth: depth)
        case .index:
            try mangleIndex(node, depth: depth)
        case .variable:
            try mangleVariable(node, depth: depth)
        case .subscript:
            try mangleSubscript(node, depth: depth)
        case .didSet:
            try mangleDidSet(node, depth: depth)
        case .willSet:
            try mangleWillSet(node, depth: depth)
        case .readAccessor:
            try mangleReadAccessor(node, depth: depth)
        case .modifyAccessor:
            try mangleModifyAccessor(node, depth: depth)
        case .thinFunctionType:
            try mangleThinFunctionType(node, depth: depth)
        case .noEscapeFunctionType:
            try mangleNoEscapeFunctionType(node, depth: depth)
        case .autoClosureType:
            try mangleAutoClosureType(node, depth: depth)
        case .escapingAutoClosureType:
            try mangleEscapingAutoClosureType(node, depth: depth)
        case .uncurriedFunctionType:
            try mangleUncurriedFunctionType(node, depth: depth)
        case .protocolWitness:
            try mangleProtocolWitness(node, depth: depth)
        case .protocolWitnessTable:
            try mangleProtocolWitnessTable(node, depth: depth)
        case .protocolWitnessTableAccessor:
            try mangleProtocolWitnessTableAccessor(node, depth: depth)
        case .valueWitness:
            try mangleValueWitness(node, depth: depth)
        case .valueWitnessTable:
            try mangleValueWitnessTable(node, depth: depth)
        case .typeMetadata:
            try mangleTypeMetadata(node, depth: depth)
        case .typeMetadataAccessFunction:
            try mangleTypeMetadataAccessFunction(node, depth: depth)
        case .fullTypeMetadata:
            try mangleFullTypeMetadata(node, depth: depth)
        case .metaclass:
            try mangleMetaclass(node, depth: depth)
        case .static:
            try mangleStatic(node, depth: depth)
        case .initializer:
            try mangleInitializer(node, depth: depth)
        case .prefixOperator:
            try manglePrefixOperator(node, depth: depth)
        case .postfixOperator:
            try manglePostfixOperator(node, depth: depth)
        case .infixOperator:
            try mangleInfixOperator(node, depth: depth)
        case .dependentGenericSignature:
            try mangleDependentGenericSignature(node, depth: depth)
        case .dependentGenericType:
            try mangleDependentGenericType(node, depth: depth)
        case .throwsAnnotation:
            try mangleThrowsAnnotation(node, depth: depth)
        case .asyncAnnotation:
            try mangleAsyncAnnotation(node, depth: depth)
        case .emptyList:
            try mangleEmptyList(node, depth: depth)
        case .firstElementMarker:
            try mangleFirstElementMarker(node, depth: depth)
        case .variadicMarker:
            try mangleVariadicMarker(node, depth: depth)
        case .enumCase:
            try mangleEnumCase(node, depth: depth)
        case .fieldOffset:
            try mangleFieldOffset(node, depth: depth)
        case .boundGenericFunction:
            try mangleBoundGenericFunction(node, depth: depth)
        case .boundGenericOtherNominalType:
            try mangleBoundGenericOtherNominalType(node, depth: depth)
        case .associatedType:
            try mangleAssociatedType(node, depth: depth)
        case .associatedTypeRef:
            try mangleAssociatedTypeRef(node, depth: depth)
        case .associatedTypeDescriptor:
            try mangleAssociatedTypeDescriptor(node, depth: depth)
        case .associatedConformanceDescriptor:
            try mangleAssociatedConformanceDescriptor(node, depth: depth)
        case .associatedTypeMetadataAccessor:
            try mangleAssociatedTypeMetadataAccessor(node, depth: depth)
        case .assocTypePath:
            try mangleAssocTypePath(node, depth: depth)
        case .associatedTypeGenericParamRef:
            try mangleAssociatedTypeGenericParamRef(node, depth: depth)
        case .protocolConformance:
            try mangleProtocolConformance(node, depth: depth)
        case .concreteProtocolConformance:
            try mangleConcreteProtocolConformance(node, depth: depth)
        case .protocolConformanceDescriptor:
            try mangleProtocolConformanceDescriptor(node, depth: depth)
        case .baseConformanceDescriptor:
            try mangleBaseConformanceDescriptor(node, depth: depth)
        case .dependentAssociatedConformance:
            try mangleDependentAssociatedConformance(node, depth: depth)
        case .retroactiveConformance:
            try mangleRetroactiveConformance(node, depth: depth)
        case .nominalTypeDescriptor:
            try mangleNominalTypeDescriptor(node, depth: depth)
        case .nominalTypeDescriptorRecord:
            try mangleNominalTypeDescriptorRecord(node, depth: depth)
        case .protocolDescriptor:
            try mangleProtocolDescriptor(node, depth: depth)
        case .protocolDescriptorRecord:
            try mangleProtocolDescriptorRecord(node, depth: depth)
        case .typeMetadataCompletionFunction:
            try mangleTypeMetadataCompletionFunction(node, depth: depth)
        case .typeMetadataDemanglingCache:
            try mangleTypeMetadataDemanglingCache(node, depth: depth)
        case .typeMetadataInstantiationCache:
            try mangleTypeMetadataInstantiationCache(node, depth: depth)
        case .typeMetadataLazyCache:
            try mangleTypeMetadataLazyCache(node, depth: depth)
        case .classMetadataBaseOffset:
            try mangleClassMetadataBaseOffset(node, depth: depth)
        case .genericTypeMetadataPattern:
            try mangleGenericTypeMetadataPattern(node, depth: depth)
        case .protocolWitnessTablePattern:
            try mangleProtocolWitnessTablePattern(node, depth: depth)
        case .genericProtocolWitnessTable:
            try mangleGenericProtocolWitnessTable(node, depth: depth)
        case .genericProtocolWitnessTableInstantiationFunction:
            try mangleGenericProtocolWitnessTableInstantiationFunction(node, depth: depth)
        case .resilientProtocolWitnessTable:
            try mangleResilientProtocolWitnessTable(node, depth: depth)
        case .protocolSelfConformanceWitness:
            try mangleProtocolSelfConformanceWitness(node, depth: depth)
        case .baseWitnessTableAccessor:
            try mangleBaseWitnessTableAccessor(node, depth: depth)
        case .outlinedCopy:
            try mangleOutlinedCopy(node, depth: depth)
        case .outlinedConsume:
            try mangleOutlinedConsume(node, depth: depth)
        case .outlinedRetain:
            try mangleOutlinedRetain(node, depth: depth)
        case .outlinedRelease:
            try mangleOutlinedRelease(node, depth: depth)
        case .outlinedDestroy:
            try mangleOutlinedDestroy(node, depth: depth)
        case .outlinedInitializeWithTake:
            try mangleOutlinedInitializeWithTake(node, depth: depth)
        case .outlinedInitializeWithCopy:
            try mangleOutlinedInitializeWithCopy(node, depth: depth)
        case .outlinedAssignWithTake:
            try mangleOutlinedAssignWithTake(node, depth: depth)
        case .outlinedAssignWithCopy:
            try mangleOutlinedAssignWithCopy(node, depth: depth)
        case .outlinedVariable:
            try mangleOutlinedVariable(node, depth: depth)
        case .outlinedBridgedMethod:
            try mangleOutlinedBridgedMethod(node, depth: depth)
        case .pack:
            try manglePack(node, depth: depth)
        case .packElement:
            try manglePackElement(node, depth: depth)
        case .packElementLevel:
            try manglePackElementLevel(node, depth: depth)
        case .packExpansion:
            try manglePackExpansion(node, depth: depth)
        case .silPackDirect:
            try mangleSILPackDirect(node, depth: depth)
        case .silPackIndirect:
            try mangleSILPackIndirect(node, depth: depth)
        case .genericSpecialization:
            try mangleGenericSpecialization(node, depth: depth)
        case .genericPartialSpecialization:
            try mangleGenericPartialSpecialization(node, depth: depth)
        case .genericSpecializationParam:
            try mangleGenericSpecializationParam(node, depth: depth)
        case .functionSignatureSpecialization:
            try mangleFunctionSignatureSpecialization(node, depth: depth)
        case .genericTypeParamDecl:
            try mangleGenericTypeParamDecl(node, depth: depth)
        case .dependentGenericParamCount:
            try mangleDependentGenericParamCount(node, depth: depth)
        case .dependentGenericParamPackMarker:
            try mangleDependentGenericParamPackMarker(node, depth: depth)
        case .implFunctionType:
            try mangleImplFunctionType(node, depth: depth)
        case .implParameter:
            try mangleImplParameter(node, depth: depth)
        case .implResult:
            try mangleImplResult(node, depth: depth)
        case .implYield:
            try mangleImplYield(node, depth: depth)
        case .implErrorResult:
            try mangleImplErrorResult(node, depth: depth)
        case .implConvention:
            try mangleImplConvention(node, depth: depth)
        case .implFunctionConvention:
            try mangleImplFunctionConvention(node, depth: depth)
        case .implFunctionAttribute:
            try mangleImplFunctionAttribute(node, depth: depth)
        case .implEscaping:
            try mangleImplEscaping(node, depth: depth)
        case .implDifferentiabilityKind:
            try mangleImplDifferentiabilityKind(node, depth: depth)
        case .implCoroutineKind:
            try mangleImplCoroutineKind(node, depth: depth)
        case .implParameterIsolated:
            try mangleImplParameterIsolated(node, depth: depth)
        case .implParameterSending:
            try mangleImplParameterSending(node, depth: depth)
        case .implSendingResult:
            try mangleImplSendingResult(node, depth: depth)
        case .implPatternSubstitutions:
            try mangleImplPatternSubstitutions(node, depth: depth)
        case .implInvocationSubstitutions:
            try mangleImplInvocationSubstitutions(node, depth: depth)
        case .accessibleFunctionRecord:
            try mangleAccessibleFunctionRecord(node, depth: depth)
        case .anonymousDescriptor:
            try mangleAnonymousDescriptor(node, depth: depth)
        case .extensionDescriptor:
            try mangleExtensionDescriptor(node, depth: depth)
        case .methodDescriptor:
            try mangleMethodDescriptor(node, depth: depth)
        case .moduleDescriptor:
            try mangleModuleDescriptor(node, depth: depth)
        case .propertyDescriptor:
            try manglePropertyDescriptor(node, depth: depth)
        case .protocolConformanceDescriptorRecord:
            try mangleProtocolConformanceDescriptorRecord(node, depth: depth)
        case .protocolRequirementsBaseDescriptor:
            try mangleProtocolRequirementsBaseDescriptor(node, depth: depth)
        case .protocolSelfConformanceDescriptor:
            try mangleProtocolSelfConformanceDescriptor(node, depth: depth)
        case .protocolSelfConformanceWitnessTable:
            try mangleProtocolSelfConformanceWitnessTable(node, depth: depth)
        case .protocolSymbolicReference:
            try mangleProtocolSymbolicReference(node, depth: depth)
        case .typeSymbolicReference:
            try mangleTypeSymbolicReference(node, depth: depth)
        case .objectiveCProtocolSymbolicReference:
            try mangleObjectiveCProtocolSymbolicReference(node, depth: depth)
        case .opaqueType:
            try mangleOpaqueType(node, depth: depth)
        case .opaqueReturnType:
            try mangleOpaqueReturnType(node, depth: depth)
        case .opaqueReturnTypeOf:
            try mangleOpaqueReturnTypeOf(node, depth: depth)
        case .opaqueReturnTypeIndex:
            try mangleOpaqueReturnTypeIndex(node, depth: depth)
        case .opaqueReturnTypeParent:
            try mangleOpaqueReturnTypeParent(node, depth: depth)
        case .opaqueTypeDescriptor:
            try mangleOpaqueTypeDescriptor(node, depth: depth)
        case .opaqueTypeDescriptorAccessor:
            try mangleOpaqueTypeDescriptorAccessor(node, depth: depth)
        case .opaqueTypeDescriptorAccessorImpl:
            try mangleOpaqueTypeDescriptorAccessorImpl(node, depth: depth)
        case .opaqueTypeDescriptorAccessorKey:
            try mangleOpaqueTypeDescriptorAccessorKey(node, depth: depth)
        case .opaqueTypeDescriptorAccessorVar:
            try mangleOpaqueTypeDescriptorAccessorVar(node, depth: depth)
        case .opaqueTypeDescriptorRecord:
            try mangleOpaqueTypeDescriptorRecord(node, depth: depth)
        case .opaqueTypeDescriptorSymbolicReference:
            try mangleOpaqueTypeDescriptorSymbolicReference(node, depth: depth)
        case .propertyWrapperBackingInitializer:
            try manglePropertyWrapperBackingInitializer(node, depth: depth)
        case .propertyWrapperInitFromProjectedValue:
            try manglePropertyWrapperInitFromProjectedValue(node, depth: depth)
        case .curryThunk:
            try mangleCurryThunk(node, depth: depth)
        case .dispatchThunk:
            try mangleDispatchThunk(node, depth: depth)
        case .reabstractionThunk:
            try mangleReabstractionThunk(node, depth: depth)
        case .reabstractionThunkHelper:
            try mangleReabstractionThunkHelper(node, depth: depth)
        case .reabstractionThunkHelperWithSelf:
            try mangleReabstractionThunkHelperWithSelf(node, depth: depth)
        case .reabstractionThunkHelperWithGlobalActor:
            try mangleReabstractionThunkHelperWithGlobalActor(node, depth: depth)
        case .partialApplyForwarder:
            try manglePartialApplyForwarder(node, depth: depth)
        case .partialApplyObjCForwarder:
            try manglePartialApplyObjCForwarder(node, depth: depth)
        case .macro:
            try mangleMacro(node, depth: depth)
        case .macroExpansionLoc:
            try mangleMacroExpansionLoc(node, depth: depth)
        case .macroExpansionUniqueName:
            try mangleMacroExpansionUniqueName(node, depth: depth)
        case .freestandingMacroExpansion:
            try mangleFreestandingMacroExpansion(node, depth: depth)
        case .accessorAttachedMacroExpansion:
            try mangleAccessorAttachedMacroExpansion(node, depth: depth)
        case .memberAttributeAttachedMacroExpansion:
            try mangleMemberAttributeAttachedMacroExpansion(node, depth: depth)
        case .memberAttachedMacroExpansion:
            try mangleMemberAttachedMacroExpansion(node, depth: depth)
        case .peerAttachedMacroExpansion:
            try manglePeerAttachedMacroExpansion(node, depth: depth)
        case .conformanceAttachedMacroExpansion:
            try mangleConformanceAttachedMacroExpansion(node, depth: depth)
        case .extensionAttachedMacroExpansion:
            try mangleExtensionAttachedMacroExpansion(node, depth: depth)
        case .bodyAttachedMacroExpansion:
            try mangleBodyAttachedMacroExpansion(node, depth: depth)
        case .asyncFunctionPointer:
            try mangleAsyncFunctionPointer(node, depth: depth)
        case .asyncRemoved:
            try mangleAsyncRemoved(node, depth: depth)
        case .asyncAwaitResumePartialFunction:
            try mangleAsyncAwaitResumePartialFunction(node, depth: depth)
        case .asyncSuspendResumePartialFunction:
            try mangleAsyncSuspendResumePartialFunction(node, depth: depth)
        case .backDeploymentFallback:
            try mangleBackDeploymentFallback(node, depth: depth)
        case .backDeploymentThunk:
            try mangleBackDeploymentThunk(node, depth: depth)
        case .builtinTupleType:
            try mangleBuiltinTupleType(node, depth: depth)
        case .builtinFixedArray:
            try mangleBuiltinFixedArray(node, depth: depth)
        case .cFunctionPointer:
            try mangleCFunctionPointer(node, depth: depth)
        case .clangType:
            try mangleClangType(node, depth: depth)
        case .objCBlock:
            try mangleObjCBlock(node, depth: depth)
        case .escapingObjCBlock:
            try mangleEscapingObjCBlock(node, depth: depth)
        case .objCAttribute:
            try mangleObjCAttribute(node, depth: depth)
        case .objCAsyncCompletionHandlerImpl:
            try mangleObjCAsyncCompletionHandlerImpl(node, depth: depth)
        case .objCMetadataUpdateFunction:
            try mangleObjCMetadataUpdateFunction(node, depth: depth)
        case .objCResilientClassStub:
            try mangleObjCResilientClassStub(node, depth: depth)
        case .fullObjCResilientClassStub:
            try mangleFullObjCResilientClassStub(node, depth: depth)
        case .compileTimeConst:
            try mangleCompileTimeConst(node, depth: depth)
        case .constValue:
            try mangleConstValue(node, depth: depth)
        case .concurrentFunctionType:
            try mangleConcurrentFunctionType(node, depth: depth)
        case .globalActorFunctionType:
            try mangleGlobalActorFunctionType(node, depth: depth)
        case .isolatedAnyFunctionType:
            try mangleIsolatedAnyFunctionType(node, depth: depth)
        case .nonIsolatedCallerFunctionType:
            try mangleNonIsolatedCallerFunctionType(node, depth: depth)
        case .sendingResultFunctionType:
            try mangleSendingResultFunctionType(node, depth: depth)
        case .constrainedExistential:
            try mangleConstrainedExistential(node, depth: depth)
        case .constrainedExistentialSelf:
            try mangleConstrainedExistentialSelf(node, depth: depth)
        case .extendedExistentialTypeShape:
            try mangleExtendedExistentialTypeShape(node, depth: depth)
        case .symbolicExtendedExistentialType:
            try mangleSymbolicExtendedExistentialType(node, depth: depth)
        case .coroFunctionPointer:
            try mangleCoroFunctionPointer(node, depth: depth)
        case .coroutineContinuationPrototype:
            try mangleCoroutineContinuationPrototype(node, depth: depth)
        case .deallocator:
            try mangleDeallocator(node, depth: depth)
        case .isolatedDeallocator:
            try mangleIsolatedDeallocator(node, depth: depth)
        case .defaultArgumentInitializer:
            try mangleDefaultArgumentInitializer(node, depth: depth)
        case .defaultOverride:
            try mangleDefaultOverride(node, depth: depth)
        case .dependentAssociatedTypeRef:
            try mangleDependentAssociatedTypeRef(node, depth: depth)
        case .dependentGenericInverseConformanceRequirement:
            try mangleDependentGenericInverseConformanceRequirement(node, depth: depth)
        case .dependentProtocolConformanceOpaque:
            try mangleDependentProtocolConformanceOpaque(node, depth: depth)
        case .dependentProtocolConformanceRoot:
            try mangleDependentProtocolConformanceRoot(node, depth: depth)
        case .dependentProtocolConformanceInherited:
            try mangleDependentProtocolConformanceInherited(node, depth: depth)
        case .dependentProtocolConformanceAssociated:
            try mangleDependentProtocolConformanceAssociated(node, depth: depth)
        case .dependentPseudogenericSignature:
            try mangleDependentPseudogenericSignature(node, depth: depth)
        case .dependentGenericParamValueMarker:
            try mangleDependentGenericParamValueMarker(node, depth: depth)
        case .autoDiffFunction:
            try mangleAutoDiffFunction(node, depth: depth)
        case .autoDiffDerivativeVTableThunk:
            try mangleAutoDiffDerivativeVTableThunk(node, depth: depth)
        case .autoDiffFunctionKind:
            try mangleAutoDiffFunctionKind(node, depth: depth)
        case .autoDiffSubsetParametersThunk:
            try mangleAutoDiffSubsetParametersThunk(node, depth: depth)
        case .differentiabilityWitness:
            try mangleDifferentiabilityWitness(node, depth: depth)
        case .differentiableFunctionType:
            try mangleDifferentiableFunctionType(node, depth: depth)
        case .noDerivative:
            try mangleNoDerivative(node, depth: depth)
        case .directMethodReferenceAttribute:
            try mangleDirectMethodReferenceAttribute(node, depth: depth)
        case .directness:
            try mangleDirectness(node, depth: depth)
        case .droppedArgument:
            try mangleDroppedArgument(node, depth: depth)
        case .dynamicAttribute:
            try mangleDynamicAttribute(node, depth: depth)
        case .nonObjCAttribute:
            try mangleNonObjCAttribute(node, depth: depth)
        case .distributedAccessor:
            try mangleDistributedAccessor(node, depth: depth)
        case .distributedThunk:
            try mangleDistributedThunk(node, depth: depth)
        case .dynamicallyReplaceableFunctionImpl:
            try mangleDynamicallyReplaceableFunctionImpl(node, depth: depth)
        case .dynamicallyReplaceableFunctionKey:
            try mangleDynamicallyReplaceableFunctionKey(node, depth: depth)
        case .dynamicallyReplaceableFunctionVar:
            try mangleDynamicallyReplaceableFunctionVar(node, depth: depth)
        case .globalGetter:
            try mangleGlobalGetter(node, depth: depth)
        case .globalVariableOnceDeclList:
            try mangleGlobalVariableOnceDeclList(node, depth: depth)
        case .globalVariableOnceFunction:
            try mangleGlobalVariableOnceFunction(node, depth: depth)
        case .globalVariableOnceToken:
            try mangleGlobalVariableOnceToken(node, depth: depth)
        case .hasSymbolQuery:
            try mangleHasSymbolQuery(node, depth: depth)
        case .iVarDestroyer:
            try mangleIVarDestroyer(node, depth: depth)
        case .iVarInitializer:
            try mangleIVarInitializer(node, depth: depth)
        case .implErasedIsolation:
            try mangleImplErasedIsolation(node, depth: depth)
        case .implParameterImplicitLeading:
            try mangleImplParameterImplicitLeading(node, depth: depth)
        case .implFunctionConventionName:
            try mangleImplFunctionConventionName(node, depth: depth)
        case .implParameterResultDifferentiability:
            try mangleImplParameterResultDifferentiability(node, depth: depth)
        case .indexSubset:
            try mangleIndexSubset(node, depth: depth)
        case .integer:
            try mangleInteger(node, depth: depth)
        case .negativeInteger:
            try mangleNegativeInteger(node, depth: depth)
        case .unknownIndex:
            try mangleUnknownIndex(node, depth: depth)
        case .initAccessor:
            try mangleInitAccessor(node, depth: depth)
        case .modify2Accessor:
            try mangleModify2Accessor(node, depth: depth)
        case .read2Accessor:
            try mangleRead2Accessor(node, depth: depth)
        case .materializeForSet:
            try mangleMaterializeForSet(node, depth: depth)
        case .nativeOwningAddressor:
            try mangleNativeOwningAddressor(node, depth: depth)
        case .nativeOwningMutableAddressor:
            try mangleNativeOwningMutableAddressor(node, depth: depth)
        case .nativePinningAddressor:
            try mangleNativePinningAddressor(node, depth: depth)
        case .nativePinningMutableAddressor:
            try mangleNativePinningMutableAddressor(node, depth: depth)
        case .owningAddressor:
            try mangleOwningAddressor(node, depth: depth)
        case .owningMutableAddressor:
            try mangleOwningMutableAddressor(node, depth: depth)
        case .unsafeAddressor:
            try mangleUnsafeAddressor(node, depth: depth)
        case .unsafeMutableAddressor:
            try mangleUnsafeMutableAddressor(node, depth: depth)
        case .inlinedGenericFunction:
            try mangleInlinedGenericFunction(node, depth: depth)
        case .genericPartialSpecializationNotReAbstracted:
            try mangleGenericPartialSpecializationNotReAbstracted(node, depth: depth)
        case .genericSpecializationInResilienceDomain:
            try mangleGenericSpecializationInResilienceDomain(node, depth: depth)
        case .genericSpecializationNotReAbstracted:
            try mangleGenericSpecializationNotReAbstracted(node, depth: depth)
        case .genericSpecializationPrespecialized:
            try mangleGenericSpecializationPrespecialized(node, depth: depth)
        case .specializationPassID:
            try mangleSpecializationPassID(node, depth: depth)
        case .isSerialized:
            try mangleIsSerialized(node, depth: depth)
        case .isolated:
            try mangleIsolated(node, depth: depth)
        case .sending:
            try mangleSending(node, depth: depth)
        case .keyPathGetterThunkHelper:
            try mangleKeyPathGetterThunkHelper(node, depth: depth)
        case .keyPathSetterThunkHelper:
            try mangleKeyPathSetterThunkHelper(node, depth: depth)
        case .keyPathEqualsThunkHelper:
            try mangleKeyPathEqualsThunkHelper(node, depth: depth)
        case .keyPathHashThunkHelper:
            try mangleKeyPathHashThunkHelper(node, depth: depth)
        case .keyPathAppliedMethodThunkHelper:
            try mangleKeyPathAppliedMethodThunkHelper(node, depth: depth)
        case .metadataInstantiationCache:
            try mangleMetadataInstantiationCache(node, depth: depth)
        case .metatypeRepresentation:
            try mangleMetatypeRepresentation(node, depth: depth)
        case .methodLookupFunction:
            try mangleMethodLookupFunction(node, depth: depth)
        case .mergedFunction:
            try mangleMergedFunction(node, depth: depth)
        case .noncanonicalSpecializedGenericTypeMetadataCache:
            try mangleNoncanonicalSpecializedGenericTypeMetadataCache(node, depth: depth)
        case .relatedEntityDeclName:
            try mangleRelatedEntityDeclName(node, depth: depth)
        case .silBoxType:
            try mangleSILBoxType(node, depth: depth)
        case .silBoxTypeWithLayout:
            try mangleSILBoxTypeWithLayout(node, depth: depth)
        case .silBoxLayout:
            try mangleSILBoxLayout(node, depth: depth)
        case .silBoxImmutableField:
            try mangleSILBoxImmutableField(node, depth: depth)
        case .silBoxMutableField:
            try mangleSILBoxMutableField(node, depth: depth)
        case .silThunkIdentity:
            try mangleSILThunkIdentity(node, depth: depth)
        case .sugaredArray:
            try mangleSugaredArray(node, depth: depth)
        case .sugaredDictionary:
            try mangleSugaredDictionary(node, depth: depth)
        case .sugaredOptional:
            try mangleSugaredOptional(node, depth: depth)
        case .sugaredParen:
            try mangleSugaredParen(node, depth: depth)
        case .typedThrowsAnnotation:
            try mangleTypedThrowsAnnotation(node, depth: depth)
        case .uniquable:
            try mangleUniquable(node, depth: depth)
        case .vTableAttribute:
            try mangleVTableAttribute(node, depth: depth)
        case .vTableThunk:
            try mangleVTableThunk(node, depth: depth)
        case .outlinedEnumGetTag:
            try mangleOutlinedEnumGetTag(node, depth: depth)
        case .outlinedEnumProjectDataForLoad:
            try mangleOutlinedEnumProjectDataForLoad(node, depth: depth)
        case .outlinedEnumTagStore:
            try mangleOutlinedEnumTagStore(node, depth: depth)
        case .outlinedReadOnlyObject:
            try mangleOutlinedReadOnlyObject(node, depth: depth)
        case .outlinedDestroyNoValueWitness:
            try mangleOutlinedDestroyNoValueWitness(node, depth: depth)
        case .outlinedInitializeWithCopyNoValueWitness:
            try mangleOutlinedInitializeWithCopyNoValueWitness(node, depth: depth)
        case .outlinedAssignWithTakeNoValueWitness:
            try mangleOutlinedAssignWithTakeNoValueWitness(node, depth: depth)
        case .outlinedAssignWithCopyNoValueWitness:
            try mangleOutlinedAssignWithCopyNoValueWitness(node, depth: depth)
        case .packProtocolConformance:
            try manglePackProtocolConformance(node, depth: depth)
        case .accessorFunctionReference:
            try mangleAccessorFunctionReference(node, depth: depth)
        case .anyProtocolConformanceList:
            try mangleAnyProtocolConformanceList(node, depth: depth)
        case .associatedTypeWitnessTableAccessor:
            try mangleAssociatedTypeWitnessTableAccessor(node, depth: depth)
        case .autoDiffSelfReorderingReabstractionThunk:
            try mangleAutoDiffSelfReorderingReabstractionThunk(node, depth: depth)
        case .canonicalPrespecializedGenericTypeCachingOnceToken:
            try mangleCanonicalPrespecializedGenericTypeCachingOnceToken(node, depth: depth)
        case .canonicalSpecializedGenericMetaclass:
            try mangleCanonicalSpecializedGenericMetaclass(node, depth: depth)
        case .canonicalSpecializedGenericTypeMetadataAccessFunction:
            try mangleCanonicalSpecializedGenericTypeMetadataAccessFunction(node, depth: depth)
        case .constrainedExistentialRequirementList:
            try mangleConstrainedExistentialRequirementList(node, depth: depth)
        case .defaultAssociatedConformanceAccessor:
            try mangleDefaultAssociatedConformanceAccessor(node, depth: depth)
        case .defaultAssociatedTypeMetadataAccessor:
            try mangleDefaultAssociatedTypeMetadataAccessor(node, depth: depth)
        case .dependentGenericConformanceRequirement:
            try mangleDependentGenericConformanceRequirement(node, depth: depth)
        case .dependentGenericLayoutRequirement:
            try mangleDependentGenericLayoutRequirement(node, depth: depth)
        case .dependentGenericSameShapeRequirement:
            try mangleDependentGenericSameShapeRequirement(node, depth: depth)
        case .dependentGenericSameTypeRequirement:
            try mangleDependentGenericSameTypeRequirement(node, depth: depth)
        case .functionSignatureSpecializationParam:
            try mangleFunctionSignatureSpecializationParam(node, depth: depth)
        case .functionSignatureSpecializationReturn:
            try mangleFunctionSignatureSpecializationReturn(node, depth: depth)
        case .functionSignatureSpecializationParamKind:
            try mangleFunctionSignatureSpecializationParamKind(node, depth: depth)
        case .functionSignatureSpecializationParamPayload:
            try mangleFunctionSignatureSpecializationParamPayload(node, depth: depth)
        case .keyPathUnappliedMethodThunkHelper:
            try mangleKeyPathUnappliedMethodThunkHelper(node, depth: depth)
        case .lazyProtocolWitnessTableAccessor:
            try mangleLazyProtocolWitnessTableAccessor(node, depth: depth)
        case .lazyProtocolWitnessTableCacheVariable:
            try mangleLazyProtocolWitnessTableCacheVariable(node, depth: depth)
        case .noncanonicalSpecializedGenericTypeMetadata:
            try mangleNoncanonicalSpecializedGenericTypeMetadata(node, depth: depth)
        case .nonUniqueExtendedExistentialTypeShapeSymbolicReference:
            try mangleNonUniqueExtendedExistentialTypeShapeSymbolicReference(node, depth: depth)
        case .outlinedInitializeWithTakeNoValueWitness:
            try mangleOutlinedInitializeWithTakeNoValueWitness(node, depth: depth)
        case .predefinedObjCAsyncCompletionHandlerImpl:
            try manglePredefinedObjCAsyncCompletionHandlerImpl(node, depth: depth)
        case .protocolConformanceRefInTypeModule:
            try mangleProtocolConformanceRefInTypeModule(node, depth: depth)
        case .protocolConformanceRefInProtocolModule:
            try mangleProtocolConformanceRefInProtocolModule(node, depth: depth)
        case .protocolConformanceRefInOtherModule:
            try mangleProtocolConformanceRefInOtherModule(node, depth: depth)
        case .reflectionMetadataAssocTypeDescriptor:
            try mangleReflectionMetadataAssocTypeDescriptor(node, depth: depth)
        case .reflectionMetadataBuiltinDescriptor:
            try mangleReflectionMetadataBuiltinDescriptor(node, depth: depth)
        case .reflectionMetadataFieldDescriptor:
            try mangleReflectionMetadataFieldDescriptor(node, depth: depth)
        case .reflectionMetadataSuperclassDescriptor:
            try mangleReflectionMetadataSuperclassDescriptor(node, depth: depth)
        case .silThunkHopToMainActorIfNeeded:
            try mangleSILThunkHopToMainActorIfNeeded(node, depth: depth)
        case .sugaredInlineArray:
            try mangleSugaredInlineArray(node, depth: depth)
        case .typeMetadataInstantiationFunction:
            try mangleTypeMetadataInstantiationFunction(node, depth: depth)
        case .typeMetadataSingletonInitializationCache:
            try mangleTypeMetadataSingletonInitializationCache(node, depth: depth)
        case .uniqueExtendedExistentialTypeShapeSymbolicReference:
            try mangleUniqueExtendedExistentialTypeShapeSymbolicReference(node, depth: depth)
        }
    }

    // MARK: - Helper Methods

    /// Mangle child nodes in order
    func mangleChildNodes(_ node: Node, depth: Int) throws(RemanglerError) {
        for child in node.children {
            try mangleNode(child, depth: depth + 1)
        }
    }

    /// Mangle child nodes in reverse order
    func mangleChildNodesReversed(_ node: Node, depth: Int) throws(RemanglerError) {
        for child in node.children.reversed() {
            try mangleNode(child, depth: depth + 1)
        }
    }

    /// Mangle a single child node
    func mangleSingleChildNode(_ node: Node, depth: Int) throws(RemanglerError) {
        guard node.children.count == 1 else {
            throw .multipleChildNodes(node)
        }
        try mangleNode(node.children[0], depth: depth + 1)
    }

    /// Mangle a specific child by index
    func mangleChildNode(_ node: Node, at index: Int, depth: Int) throws(RemanglerError) {
        guard index < node.children.count else {
            throw .missingChildNode(node, expectedIndex: index)
        }
        try mangleNode(node.children[index], depth: depth + 1)
    }

    /// Get a single child, skipping Type wrapper if present
    func skipType(_ node: Node) -> Node {
        if node.kind == .type && node.children.count == 1 {
            return node.children[0]
        }
        return node
    }

    /// Result of substitution lookup
    struct SubstitutionResult {
        let entry: SubstitutionEntry
        let found: Bool
    }

    /// Try to use a substitution for a node (C++ compatible version)
    ///
    /// Returns both the entry and whether a substitution was found.
    /// The entry is always populated, so caller can add it to the substitution table if not found.
    func trySubstitution(_ node: Node, treatAsIdentifier: Bool = false) -> SubstitutionResult {
        // First try standard substitutions (Swift stdlib types)
        if mangleStandardSubstitution(node) {
            // For standard substitutions, create a placeholder entry
            let entry = entryForNode(node, treatAsIdentifier: treatAsIdentifier)
            return SubstitutionResult(entry: entry, found: true)
        }

        // Create substitution entry (always created, like C++)
        let entry = entryForNode(node, treatAsIdentifier: treatAsIdentifier)

        // Look for existing substitution
        guard let index = findSubstitution(entry) else {
            return SubstitutionResult(entry: entry, found: false)
        }

        // Emit substitution reference
        if index >= 26 {
            append("A")
            mangleIndex(index - 26)
        } else {
            let substChar = Character(UnicodeScalar(UInt8(ascii: "A") + UInt8(index)))
            let subst = String(substChar)
            // Try to merge with previous substitution
            if !substMerging.tryMergeSubst(self, subst: subst, isStandardSubst: false) {
                // If merge failed, output normally
                append("A")
                append(subst)
            }
        }

        return SubstitutionResult(entry: entry, found: true)
    }

    /// Try to mangle as a standard Swift stdlib type
    func mangleStandardSubstitution(_ node: Node) -> Bool {
        // Only applies to nominal types
        guard node.kind == .structure || node.kind == .class ||
            node.kind == .enum || node.kind == .protocol else {
            return false
        }

        // Must be in Swift module
        guard node.children.count >= 2 else { return false }
        guard let firstChild = node.children.first,
              firstChild.kind == .module,
              firstChild.text == "Swift" else {
            return false
        }

        // Ignore private stdlib names
        guard node.children[1].kind == .identifier,
              let typeName = node.children[1].text else {
            return false
        }

        // Check for standard type substitutions
        if let subst = getStandardTypeSubstitution(typeName, allowConcurrencyManglings: true) {
            // Try to merge with previous substitution
            if !substMerging.tryMergeSubst(self, subst: subst, isStandardSubst: true) {
                // If merge failed, output normally
                append("S")
                append(subst)
            }
            return true
        }

        return false
    }

    /// Get standard type substitution string
    ///
    /// Based on StandardTypesMangling.def from Swift compiler
    private func getStandardTypeSubstitution(_ name: String, allowConcurrencyManglings: Bool = true) -> String? {
        // Standard types (Structure, Enum, Protocol)
        switch name {
        // Structures
        case "AutoreleasingUnsafeMutablePointer": return "A" // ObjC interop
        case "Array": return "a"
        case "Bool": return "b"
        case "Dictionary": return "D"
        case "Double": return "d"
        case "Float": return "f"
        case "Set": return "h"
        case "DefaultIndices": return "I"
        case "Int": return "i"
        case "Character": return "J"
        case "ClosedRange": return "N"
        case "Range": return "n"
        case "ObjectIdentifier": return "O"
        case "UnsafePointer": return "P"
        case "UnsafeMutablePointer": return "p"
        case "UnsafeBufferPointer": return "R"
        case "UnsafeMutableBufferPointer": return "r"
        case "String": return "S"
        case "Substring": return "s"
        case "UInt": return "u"
        case "UnsafeRawPointer": return "V"
        case "UnsafeMutableRawPointer": return "v"
        case "UnsafeRawBufferPointer": return "W"
        case "UnsafeMutableRawBufferPointer": return "w"
        // Enums
        case "Optional": return "q"
        // Protocols
        case "BinaryFloatingPoint": return "B"
        case "Encodable": return "E"
        case "Decodable": return "e"
        case "FloatingPoint": return "F"
        case "RandomNumberGenerator": return "G"
        case "Hashable": return "H"
        case "Numeric": return "j"
        case "BidirectionalCollection": return "K"
        case "RandomAccessCollection": return "k"
        case "Comparable": return "L"
        case "Collection": return "l"
        case "MutableCollection": return "M"
        case "RangeReplaceableCollection": return "m"
        case "Equatable": return "Q"
        case "Sequence": return "T"
        case "IteratorProtocol": return "t"
        case "UnsignedInteger": return "U"
        case "RangeExpression": return "X"
        case "Strideable": return "x"
        case "RawRepresentable": return "Y"
        case "StringProtocol": return "y"
        case "SignedInteger": return "Z"
        case "BinaryInteger": return "z"
        default:
            // Concurrency types (Swift 5.5+)
            // These use 'c' prefix: Sc<MANGLING>
            if allowConcurrencyManglings {
                switch name {
                case "Actor": return "cA"
                case "CheckedContinuation": return "cC"
                case "UnsafeContinuation": return "cc"
                case "CancellationError": return "cE"
                case "UnownedSerialExecutor": return "ce"
                case "Executor": return "cF"
                case "SerialExecutor": return "cf"
                case "TaskGroup": return "cG"
                case "ThrowingTaskGroup": return "cg"
                case "TaskExecutor": return "ch"
                case "AsyncIteratorProtocol": return "cI"
                case "AsyncSequence": return "ci"
                case "UnownedJob": return "cJ"
                case "MainActor": return "cM"
                case "TaskPriority": return "cP"
                case "AsyncStream": return "cS"
                case "AsyncThrowingStream": return "cs"
                case "Task": return "cT"
                case "UnsafeCurrentTask": return "ct"
                default:
                    return nil
                }
            }
            return nil
        }
    }
}
