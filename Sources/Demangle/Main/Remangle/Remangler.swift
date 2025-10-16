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
    func mangle(_ node: Node) -> RemanglerResult<String> {
        clearBuffer()

        let error = mangleNode(node, depth: 0)

        if error.isSuccess {
            return .success(buffer)
        } else {
            return .failure(error)
        }
    }

    /// Remangle a node tree into a mangled string (throwing version)
    func mangleThrows(_ node: Node) throws -> String {
        let result = mangle(node)
        return try result.get()
    }

    // MARK: - Core Mangling

    /// Main entry point for mangling a single node
    func mangleNode(_ node: Node, depth: Int) -> RemanglerError {
        // Check recursion depth
        if depth > Self.maxDepth {
            return .tooComplex(node)
        }

        // Dispatch to specific handler based on node kind
        switch node.kind {
        case .global:
            return mangleGlobal(node, depth: depth)
        case .suffix:
            return mangleSuffix(node, depth: depth)
        case .type:
            return mangleType(node, depth: depth)
        case .typeMangling:
            return mangleTypeMangling(node, depth: depth)
        case .typeList:
            return mangleTypeList(node, depth: depth)
        case .structure:
            return mangleStructure(node, depth: depth)
        case .class:
            return mangleClass(node, depth: depth)
        case .enum:
            return mangleEnum(node, depth: depth)
        case .protocol:
            return mangleProtocol(node, depth: depth)
        case .typeAlias:
            return mangleTypeAlias(node, depth: depth)
        case .otherNominalType:
            return mangleOtherNominalType(node, depth: depth)
        case .functionType:
            return mangleFunctionType(node, depth: depth)
        case .argumentTuple:
            return mangleArgumentTuple(node, depth: depth)
        case .returnType:
            return mangleReturnType(node, depth: depth)
        case .labelList:
            return mangleLabelList(node, depth: depth)
        case .boundGenericStructure:
            return mangleBoundGenericStructure(node, depth: depth)
        case .boundGenericClass:
            return mangleBoundGenericClass(node, depth: depth)
        case .boundGenericEnum:
            return mangleBoundGenericEnum(node, depth: depth)
        case .boundGenericProtocol:
            return mangleBoundGenericProtocol(node, depth: depth)
        case .boundGenericTypeAlias:
            return mangleBoundGenericTypeAlias(node, depth: depth)
        case .identifier:
            return mangleIdentifier(node, depth: depth)
        case .privateDeclName:
            return manglePrivateDeclName(node, depth: depth)
        case .localDeclName:
            return mangleLocalDeclName(node, depth: depth)
        case .module:
            return mangleModule(node, depth: depth)
        case .extension:
            return mangleExtension(node, depth: depth)
        case .declContext:
            return mangleDeclContext(node, depth: depth)
        case .anonymousContext:
            return mangleAnonymousContext(node, depth: depth)
        case .function:
            return mangleFunction(node, depth: depth)
        case .allocator:
            return mangleAllocator(node, depth: depth)
        case .constructor:
            return mangleConstructor(node, depth: depth)
        case .destructor:
            return mangleDestructor(node, depth: depth)
        case .getter:
            return mangleGetter(node, depth: depth)
        case .setter:
            return mangleSetter(node, depth: depth)
        case .explicitClosure:
            return mangleExplicitClosure(node, depth: depth)
        case .implicitClosure:
            return mangleImplicitClosure(node, depth: depth)
        case .builtinTypeName:
            return mangleBuiltinTypeName(node, depth: depth)
        case .dynamicSelf:
            return mangleDynamicSelf(node, depth: depth)
        case .errorType:
            return mangleErrorType(node, depth: depth)
        case .tuple:
            return mangleTuple(node, depth: depth)
        case .tupleElement:
            return mangleTupleElement(node, depth: depth)
        case .tupleElementName:
            return mangleTupleElementName(node, depth: depth)
        case .dependentGenericParamType:
            return mangleDependentGenericParamType(node, depth: depth)
        case .dependentMemberType:
            return mangleDependentMemberType(node, depth: depth)
        case .protocolList:
            return mangleProtocolList(node, depth: depth)
        case .protocolListWithClass:
            return mangleProtocolListWithClass(node, depth: depth)
        case .protocolListWithAnyObject:
            return mangleProtocolListWithAnyObject(node, depth: depth)
        case .metatype:
            return mangleMetatype(node, depth: depth)
        case .existentialMetatype:
            return mangleExistentialMetatype(node, depth: depth)
        case .shared:
            return mangleShared(node, depth: depth)
        case .owned:
            return mangleOwned(node, depth: depth)
        case .weak:
            return mangleWeak(node, depth: depth)
        case .unowned:
            return mangleUnowned(node, depth: depth)
        case .unmanaged:
            return mangleUnmanaged(node, depth: depth)
        case .inOut:
            return mangleInOut(node, depth: depth)
        case .number:
            return mangleNumber(node, depth: depth)
        case .index:
            return mangleIndex(node, depth: depth)
        case .variable:
            return mangleVariable(node, depth: depth)
        case .subscript:
            return mangleSubscript(node, depth: depth)
        case .didSet:
            return mangleDidSet(node, depth: depth)
        case .willSet:
            return mangleWillSet(node, depth: depth)
        case .readAccessor:
            return mangleReadAccessor(node, depth: depth)
        case .modifyAccessor:
            return mangleModifyAccessor(node, depth: depth)
        case .thinFunctionType:
            return mangleThinFunctionType(node, depth: depth)
        case .noEscapeFunctionType:
            return mangleNoEscapeFunctionType(node, depth: depth)
        case .autoClosureType:
            return mangleAutoClosureType(node, depth: depth)
        case .escapingAutoClosureType:
            return mangleEscapingAutoClosureType(node, depth: depth)
        case .uncurriedFunctionType:
            return mangleUncurriedFunctionType(node, depth: depth)
        case .protocolWitness:
            return mangleProtocolWitness(node, depth: depth)
        case .protocolWitnessTable:
            return mangleProtocolWitnessTable(node, depth: depth)
        case .protocolWitnessTableAccessor:
            return mangleProtocolWitnessTableAccessor(node, depth: depth)
        case .valueWitness:
            return mangleValueWitness(node, depth: depth)
        case .valueWitnessTable:
            return mangleValueWitnessTable(node, depth: depth)
        case .typeMetadata:
            return mangleTypeMetadata(node, depth: depth)
        case .typeMetadataAccessFunction:
            return mangleTypeMetadataAccessFunction(node, depth: depth)
        case .fullTypeMetadata:
            return mangleFullTypeMetadata(node, depth: depth)
        case .metaclass:
            return mangleMetaclass(node, depth: depth)
        case .static:
            return mangleStatic(node, depth: depth)
        case .initializer:
            return mangleInitializer(node, depth: depth)
        case .prefixOperator:
            return manglePrefixOperator(node, depth: depth)
        case .postfixOperator:
            return manglePostfixOperator(node, depth: depth)
        case .infixOperator:
            return mangleInfixOperator(node, depth: depth)
        case .dependentGenericSignature:
            return mangleDependentGenericSignature(node, depth: depth)
        case .dependentGenericType:
            return mangleDependentGenericType(node, depth: depth)
        case .throwsAnnotation:
            return mangleThrowsAnnotation(node, depth: depth)
        case .asyncAnnotation:
            return mangleAsyncAnnotation(node, depth: depth)
        case .emptyList:
            return mangleEmptyList(node, depth: depth)
        case .firstElementMarker:
            return mangleFirstElementMarker(node, depth: depth)
        case .variadicMarker:
            return mangleVariadicMarker(node, depth: depth)
        case .enumCase:
            return mangleEnumCase(node, depth: depth)
        case .fieldOffset:
            return mangleFieldOffset(node, depth: depth)
        case .boundGenericFunction:
            return mangleBoundGenericFunction(node, depth: depth)
        case .boundGenericOtherNominalType:
            return mangleBoundGenericOtherNominalType(node, depth: depth)
        case .associatedType:
            return mangleAssociatedType(node, depth: depth)
        case .associatedTypeRef:
            return mangleAssociatedTypeRef(node, depth: depth)
        case .associatedTypeDescriptor:
            return mangleAssociatedTypeDescriptor(node, depth: depth)
        case .associatedConformanceDescriptor:
            return mangleAssociatedConformanceDescriptor(node, depth: depth)
        case .associatedTypeMetadataAccessor:
            return mangleAssociatedTypeMetadataAccessor(node, depth: depth)
        case .assocTypePath:
            return mangleAssocTypePath(node, depth: depth)
        case .associatedTypeGenericParamRef:
            return mangleAssociatedTypeGenericParamRef(node, depth: depth)
        case .protocolConformance:
            return mangleProtocolConformance(node, depth: depth)
        case .concreteProtocolConformance:
            return mangleConcreteProtocolConformance(node, depth: depth)
        case .protocolConformanceDescriptor:
            return mangleProtocolConformanceDescriptor(node, depth: depth)
        case .baseConformanceDescriptor:
            return mangleBaseConformanceDescriptor(node, depth: depth)
        case .dependentAssociatedConformance:
            return mangleDependentAssociatedConformance(node, depth: depth)
        case .retroactiveConformance:
            return mangleRetroactiveConformance(node, depth: depth)
        case .nominalTypeDescriptor:
            return mangleNominalTypeDescriptor(node, depth: depth)
        case .nominalTypeDescriptorRecord:
            return mangleNominalTypeDescriptorRecord(node, depth: depth)
        case .protocolDescriptor:
            return mangleProtocolDescriptor(node, depth: depth)
        case .protocolDescriptorRecord:
            return mangleProtocolDescriptorRecord(node, depth: depth)
        case .typeMetadataCompletionFunction:
            return mangleTypeMetadataCompletionFunction(node, depth: depth)
        case .typeMetadataDemanglingCache:
            return mangleTypeMetadataDemanglingCache(node, depth: depth)
        case .typeMetadataInstantiationCache:
            return mangleTypeMetadataInstantiationCache(node, depth: depth)
        case .typeMetadataLazyCache:
            return mangleTypeMetadataLazyCache(node, depth: depth)
        case .classMetadataBaseOffset:
            return mangleClassMetadataBaseOffset(node, depth: depth)
        case .genericTypeMetadataPattern:
            return mangleGenericTypeMetadataPattern(node, depth: depth)
        case .protocolWitnessTablePattern:
            return mangleProtocolWitnessTablePattern(node, depth: depth)
        case .genericProtocolWitnessTable:
            return mangleGenericProtocolWitnessTable(node, depth: depth)
        case .genericProtocolWitnessTableInstantiationFunction:
            return mangleGenericProtocolWitnessTableInstantiationFunction(node, depth: depth)
        case .resilientProtocolWitnessTable:
            return mangleResilientProtocolWitnessTable(node, depth: depth)
        case .protocolSelfConformanceWitness:
            return mangleProtocolSelfConformanceWitness(node, depth: depth)
        case .baseWitnessTableAccessor:
            return mangleBaseWitnessTableAccessor(node, depth: depth)
        case .outlinedCopy:
            return mangleOutlinedCopy(node, depth: depth)
        case .outlinedConsume:
            return mangleOutlinedConsume(node, depth: depth)
        case .outlinedRetain:
            return mangleOutlinedRetain(node, depth: depth)
        case .outlinedRelease:
            return mangleOutlinedRelease(node, depth: depth)
        case .outlinedDestroy:
            return mangleOutlinedDestroy(node, depth: depth)
        case .outlinedInitializeWithTake:
            return mangleOutlinedInitializeWithTake(node, depth: depth)
        case .outlinedInitializeWithCopy:
            return mangleOutlinedInitializeWithCopy(node, depth: depth)
        case .outlinedAssignWithTake:
            return mangleOutlinedAssignWithTake(node, depth: depth)
        case .outlinedAssignWithCopy:
            return mangleOutlinedAssignWithCopy(node, depth: depth)
        case .outlinedVariable:
            return mangleOutlinedVariable(node, depth: depth)
        case .outlinedBridgedMethod:
            return mangleOutlinedBridgedMethod(node, depth: depth)
        case .pack:
            return manglePack(node, depth: depth)
        case .packElement:
            return manglePackElement(node, depth: depth)
        case .packElementLevel:
            return manglePackElementLevel(node, depth: depth)
        case .packExpansion:
            return manglePackExpansion(node, depth: depth)
        case .silPackDirect:
            return mangleSILPackDirect(node, depth: depth)
        case .silPackIndirect:
            return mangleSILPackIndirect(node, depth: depth)
        case .genericSpecialization:
            return mangleGenericSpecialization(node, depth: depth)
        case .genericPartialSpecialization:
            return mangleGenericPartialSpecialization(node, depth: depth)
        case .genericSpecializationParam:
            return mangleGenericSpecializationParam(node, depth: depth)
        case .functionSignatureSpecialization:
            return mangleFunctionSignatureSpecialization(node, depth: depth)
        case .genericTypeParamDecl:
            return mangleGenericTypeParamDecl(node, depth: depth)
        case .dependentGenericParamCount:
            return mangleDependentGenericParamCount(node, depth: depth)
        case .dependentGenericParamPackMarker:
            return mangleDependentGenericParamPackMarker(node, depth: depth)
        case .implFunctionType:
            return mangleImplFunctionType(node, depth: depth)
        case .implParameter:
            return mangleImplParameter(node, depth: depth)
        case .implResult:
            return mangleImplResult(node, depth: depth)
        case .implYield:
            return mangleImplYield(node, depth: depth)
        case .implErrorResult:
            return mangleImplErrorResult(node, depth: depth)
        case .implConvention:
            return mangleImplConvention(node, depth: depth)
        case .implFunctionConvention:
            return mangleImplFunctionConvention(node, depth: depth)
        case .implFunctionAttribute:
            return mangleImplFunctionAttribute(node, depth: depth)
        case .implEscaping:
            return mangleImplEscaping(node, depth: depth)
        case .implDifferentiabilityKind:
            return mangleImplDifferentiabilityKind(node, depth: depth)
        case .implCoroutineKind:
            return mangleImplCoroutineKind(node, depth: depth)
        case .implParameterIsolated:
            return mangleImplParameterIsolated(node, depth: depth)
        case .implParameterSending:
            return mangleImplParameterSending(node, depth: depth)
        case .implSendingResult:
            return mangleImplSendingResult(node, depth: depth)
        case .implPatternSubstitutions:
            return mangleImplPatternSubstitutions(node, depth: depth)
        case .implInvocationSubstitutions:
            return mangleImplInvocationSubstitutions(node, depth: depth)
        case .accessibleFunctionRecord:
            return mangleAccessibleFunctionRecord(node, depth: depth)
        case .anonymousDescriptor:
            return mangleAnonymousDescriptor(node, depth: depth)
        case .extensionDescriptor:
            return mangleExtensionDescriptor(node, depth: depth)
        case .methodDescriptor:
            return mangleMethodDescriptor(node, depth: depth)
        case .moduleDescriptor:
            return mangleModuleDescriptor(node, depth: depth)
        case .propertyDescriptor:
            return manglePropertyDescriptor(node, depth: depth)
        case .protocolConformanceDescriptorRecord:
            return mangleProtocolConformanceDescriptorRecord(node, depth: depth)
        case .protocolRequirementsBaseDescriptor:
            return mangleProtocolRequirementsBaseDescriptor(node, depth: depth)
        case .protocolSelfConformanceDescriptor:
            return mangleProtocolSelfConformanceDescriptor(node, depth: depth)
        case .protocolSelfConformanceWitnessTable:
            return mangleProtocolSelfConformanceWitnessTable(node, depth: depth)
        case .protocolSymbolicReference:
            return mangleProtocolSymbolicReference(node, depth: depth)
        case .typeSymbolicReference:
            return mangleTypeSymbolicReference(node, depth: depth)
        case .objectiveCProtocolSymbolicReference:
            return mangleObjectiveCProtocolSymbolicReference(node, depth: depth)
        case .opaqueType:
            return mangleOpaqueType(node, depth: depth)
        case .opaqueReturnType:
            return mangleOpaqueReturnType(node, depth: depth)
        case .opaqueReturnTypeOf:
            return mangleOpaqueReturnTypeOf(node, depth: depth)
        case .opaqueReturnTypeIndex:
            return mangleOpaqueReturnTypeIndex(node, depth: depth)
        case .opaqueReturnTypeParent:
            return mangleOpaqueReturnTypeParent(node, depth: depth)
        case .opaqueTypeDescriptor:
            return mangleOpaqueTypeDescriptor(node, depth: depth)
        case .opaqueTypeDescriptorAccessor:
            return mangleOpaqueTypeDescriptorAccessor(node, depth: depth)
        case .opaqueTypeDescriptorAccessorImpl:
            return mangleOpaqueTypeDescriptorAccessorImpl(node, depth: depth)
        case .opaqueTypeDescriptorAccessorKey:
            return mangleOpaqueTypeDescriptorAccessorKey(node, depth: depth)
        case .opaqueTypeDescriptorAccessorVar:
            return mangleOpaqueTypeDescriptorAccessorVar(node, depth: depth)
        case .opaqueTypeDescriptorRecord:
            return mangleOpaqueTypeDescriptorRecord(node, depth: depth)
        case .opaqueTypeDescriptorSymbolicReference:
            return mangleOpaqueTypeDescriptorSymbolicReference(node, depth: depth)
        case .propertyWrapperBackingInitializer:
            return manglePropertyWrapperBackingInitializer(node, depth: depth)
        case .propertyWrapperInitFromProjectedValue:
            return manglePropertyWrapperInitFromProjectedValue(node, depth: depth)
        case .curryThunk:
            return mangleCurryThunk(node, depth: depth)
        case .dispatchThunk:
            return mangleDispatchThunk(node, depth: depth)
        case .reabstractionThunk:
            return mangleReabstractionThunk(node, depth: depth)
        case .reabstractionThunkHelper:
            return mangleReabstractionThunkHelper(node, depth: depth)
        case .reabstractionThunkHelperWithSelf:
            return mangleReabstractionThunkHelperWithSelf(node, depth: depth)
        case .reabstractionThunkHelperWithGlobalActor:
            return mangleReabstractionThunkHelperWithGlobalActor(node, depth: depth)
        case .partialApplyForwarder:
            return manglePartialApplyForwarder(node, depth: depth)
        case .partialApplyObjCForwarder:
            return manglePartialApplyObjCForwarder(node, depth: depth)
        case .macro:
            return mangleMacro(node, depth: depth)
        case .macroExpansionLoc:
            return mangleMacroExpansionLoc(node, depth: depth)
        case .macroExpansionUniqueName:
            return mangleMacroExpansionUniqueName(node, depth: depth)
        case .freestandingMacroExpansion:
            return mangleFreestandingMacroExpansion(node, depth: depth)
        case .accessorAttachedMacroExpansion:
            return mangleAccessorAttachedMacroExpansion(node, depth: depth)
        case .memberAttributeAttachedMacroExpansion:
            return mangleMemberAttributeAttachedMacroExpansion(node, depth: depth)
        case .memberAttachedMacroExpansion:
            return mangleMemberAttachedMacroExpansion(node, depth: depth)
        case .peerAttachedMacroExpansion:
            return manglePeerAttachedMacroExpansion(node, depth: depth)
        case .conformanceAttachedMacroExpansion:
            return mangleConformanceAttachedMacroExpansion(node, depth: depth)
        case .extensionAttachedMacroExpansion:
            return mangleExtensionAttachedMacroExpansion(node, depth: depth)
        case .bodyAttachedMacroExpansion:
            return mangleBodyAttachedMacroExpansion(node, depth: depth)
        case .asyncFunctionPointer:
            return mangleAsyncFunctionPointer(node, depth: depth)
        case .asyncRemoved:
            return mangleAsyncRemoved(node, depth: depth)
        case .asyncAwaitResumePartialFunction:
            return mangleAsyncAwaitResumePartialFunction(node, depth: depth)
        case .asyncSuspendResumePartialFunction:
            return mangleAsyncSuspendResumePartialFunction(node, depth: depth)
        case .backDeploymentFallback:
            return mangleBackDeploymentFallback(node, depth: depth)
        case .backDeploymentThunk:
            return mangleBackDeploymentThunk(node, depth: depth)
        case .builtinTupleType:
            return mangleBuiltinTupleType(node, depth: depth)
        case .builtinFixedArray:
            return mangleBuiltinFixedArray(node, depth: depth)
        case .cFunctionPointer:
            return mangleCFunctionPointer(node, depth: depth)
        case .clangType:
            return mangleClangType(node, depth: depth)
        case .objCBlock:
            return mangleObjCBlock(node, depth: depth)
        case .escapingObjCBlock:
            return mangleEscapingObjCBlock(node, depth: depth)
        case .objCAttribute:
            return mangleObjCAttribute(node, depth: depth)
        case .objCAsyncCompletionHandlerImpl:
            return mangleObjCAsyncCompletionHandlerImpl(node, depth: depth)
        case .objCMetadataUpdateFunction:
            return mangleObjCMetadataUpdateFunction(node, depth: depth)
        case .objCResilientClassStub:
            return mangleObjCResilientClassStub(node, depth: depth)
        case .fullObjCResilientClassStub:
            return mangleFullObjCResilientClassStub(node, depth: depth)
        case .compileTimeConst:
            return mangleCompileTimeConst(node, depth: depth)
        case .constValue:
            return mangleConstValue(node, depth: depth)
        case .concurrentFunctionType:
            return mangleConcurrentFunctionType(node, depth: depth)
        case .globalActorFunctionType:
            return mangleGlobalActorFunctionType(node, depth: depth)
        case .isolatedAnyFunctionType:
            return mangleIsolatedAnyFunctionType(node, depth: depth)
        case .nonIsolatedCallerFunctionType:
            return mangleNonIsolatedCallerFunctionType(node, depth: depth)
        case .sendingResultFunctionType:
            return mangleSendingResultFunctionType(node, depth: depth)
        case .constrainedExistential:
            return mangleConstrainedExistential(node, depth: depth)
        case .constrainedExistentialSelf:
            return mangleConstrainedExistentialSelf(node, depth: depth)
        case .extendedExistentialTypeShape:
            return mangleExtendedExistentialTypeShape(node, depth: depth)
        case .symbolicExtendedExistentialType:
            return mangleSymbolicExtendedExistentialType(node, depth: depth)
        case .coroFunctionPointer:
            return mangleCoroFunctionPointer(node, depth: depth)
        case .coroutineContinuationPrototype:
            return mangleCoroutineContinuationPrototype(node, depth: depth)
        case .deallocator:
            return mangleDeallocator(node, depth: depth)
        case .isolatedDeallocator:
            return mangleIsolatedDeallocator(node, depth: depth)
        case .defaultArgumentInitializer:
            return mangleDefaultArgumentInitializer(node, depth: depth)
        case .defaultOverride:
            return mangleDefaultOverride(node, depth: depth)
        case .dependentAssociatedTypeRef:
            return mangleDependentAssociatedTypeRef(node, depth: depth)
        case .dependentGenericInverseConformanceRequirement:
            return mangleDependentGenericInverseConformanceRequirement(node, depth: depth)
        case .dependentProtocolConformanceOpaque:
            return mangleDependentProtocolConformanceOpaque(node, depth: depth)
        case .dependentProtocolConformanceRoot:
            return mangleDependentProtocolConformanceRoot(node, depth: depth)
        case .dependentProtocolConformanceInherited:
            return mangleDependentProtocolConformanceInherited(node, depth: depth)
        case .dependentProtocolConformanceAssociated:
            return mangleDependentProtocolConformanceAssociated(node, depth: depth)
        case .dependentPseudogenericSignature:
            return mangleDependentPseudogenericSignature(node, depth: depth)
        case .dependentGenericParamValueMarker:
            return mangleDependentGenericParamValueMarker(node, depth: depth)
        case .autoDiffFunction:
            return mangleAutoDiffFunction(node, depth: depth)
        case .autoDiffDerivativeVTableThunk:
            return mangleAutoDiffDerivativeVTableThunk(node, depth: depth)
        case .autoDiffFunctionKind:
            return mangleAutoDiffFunctionKind(node, depth: depth)
        case .autoDiffSubsetParametersThunk:
            return mangleAutoDiffSubsetParametersThunk(node, depth: depth)
        case .differentiabilityWitness:
            return mangleDifferentiabilityWitness(node, depth: depth)
        case .differentiableFunctionType:
            return mangleDifferentiableFunctionType(node, depth: depth)
        case .noDerivative:
            return mangleNoDerivative(node, depth: depth)
        case .directMethodReferenceAttribute:
            return mangleDirectMethodReferenceAttribute(node, depth: depth)
        case .directness:
            return mangleDirectness(node, depth: depth)
        case .droppedArgument:
            return mangleDroppedArgument(node, depth: depth)
        case .dynamicAttribute:
            return mangleDynamicAttribute(node, depth: depth)
        case .nonObjCAttribute:
            return mangleNonObjCAttribute(node, depth: depth)
        case .distributedAccessor:
            return mangleDistributedAccessor(node, depth: depth)
        case .distributedThunk:
            return mangleDistributedThunk(node, depth: depth)
        case .dynamicallyReplaceableFunctionImpl:
            return mangleDynamicallyReplaceableFunctionImpl(node, depth: depth)
        case .dynamicallyReplaceableFunctionKey:
            return mangleDynamicallyReplaceableFunctionKey(node, depth: depth)
        case .dynamicallyReplaceableFunctionVar:
            return mangleDynamicallyReplaceableFunctionVar(node, depth: depth)
        case .globalGetter:
            return mangleGlobalGetter(node, depth: depth)
        case .globalVariableOnceDeclList:
            return mangleGlobalVariableOnceDeclList(node, depth: depth)
        case .globalVariableOnceFunction:
            return mangleGlobalVariableOnceFunction(node, depth: depth)
        case .globalVariableOnceToken:
            return mangleGlobalVariableOnceToken(node, depth: depth)
        case .hasSymbolQuery:
            return mangleHasSymbolQuery(node, depth: depth)
        case .iVarDestroyer:
            return mangleIVarDestroyer(node, depth: depth)
        case .iVarInitializer:
            return mangleIVarInitializer(node, depth: depth)
        case .implErasedIsolation:
            return mangleImplErasedIsolation(node, depth: depth)
        case .implParameterImplicitLeading:
            return mangleImplParameterImplicitLeading(node, depth: depth)
        case .implFunctionConventionName:
            return mangleImplFunctionConventionName(node, depth: depth)
        case .implParameterResultDifferentiability:
            return mangleImplParameterResultDifferentiability(node, depth: depth)
        case .indexSubset:
            return mangleIndexSubset(node, depth: depth)
        case .integer:
            return mangleInteger(node, depth: depth)
        case .negativeInteger:
            return mangleNegativeInteger(node, depth: depth)
        case .unknownIndex:
            return mangleUnknownIndex(node, depth: depth)
        case .initAccessor:
            return mangleInitAccessor(node, depth: depth)
        case .modify2Accessor:
            return mangleModify2Accessor(node, depth: depth)
        case .read2Accessor:
            return mangleRead2Accessor(node, depth: depth)
        case .materializeForSet:
            return mangleMaterializeForSet(node, depth: depth)
        case .nativeOwningAddressor:
            return mangleNativeOwningAddressor(node, depth: depth)
        case .nativeOwningMutableAddressor:
            return mangleNativeOwningMutableAddressor(node, depth: depth)
        case .nativePinningAddressor:
            return mangleNativePinningAddressor(node, depth: depth)
        case .nativePinningMutableAddressor:
            return mangleNativePinningMutableAddressor(node, depth: depth)
        case .owningAddressor:
            return mangleOwningAddressor(node, depth: depth)
        case .owningMutableAddressor:
            return mangleOwningMutableAddressor(node, depth: depth)
        case .unsafeAddressor:
            return mangleUnsafeAddressor(node, depth: depth)
        case .unsafeMutableAddressor:
            return mangleUnsafeMutableAddressor(node, depth: depth)
        case .inlinedGenericFunction:
            return mangleInlinedGenericFunction(node, depth: depth)
        case .genericPartialSpecializationNotReAbstracted:
            return mangleGenericPartialSpecializationNotReAbstracted(node, depth: depth)
        case .genericSpecializationInResilienceDomain:
            return mangleGenericSpecializationInResilienceDomain(node, depth: depth)
        case .genericSpecializationNotReAbstracted:
            return mangleGenericSpecializationNotReAbstracted(node, depth: depth)
        case .genericSpecializationPrespecialized:
            return mangleGenericSpecializationPrespecialized(node, depth: depth)
        case .specializationPassID:
            return mangleSpecializationPassID(node, depth: depth)
        case .isSerialized:
            return mangleIsSerialized(node, depth: depth)
        case .isolated:
            return mangleIsolated(node, depth: depth)
        case .sending:
            return mangleSending(node, depth: depth)
        case .keyPathGetterThunkHelper:
            return mangleKeyPathGetterThunkHelper(node, depth: depth)
        case .keyPathSetterThunkHelper:
            return mangleKeyPathSetterThunkHelper(node, depth: depth)
        case .keyPathEqualsThunkHelper:
            return mangleKeyPathEqualsThunkHelper(node, depth: depth)
        case .keyPathHashThunkHelper:
            return mangleKeyPathHashThunkHelper(node, depth: depth)
        case .keyPathAppliedMethodThunkHelper:
            return mangleKeyPathAppliedMethodThunkHelper(node, depth: depth)
        case .metadataInstantiationCache:
            return mangleMetadataInstantiationCache(node, depth: depth)
        case .metatypeRepresentation:
            return mangleMetatypeRepresentation(node, depth: depth)
        case .methodLookupFunction:
            return mangleMethodLookupFunction(node, depth: depth)
        case .mergedFunction:
            return mangleMergedFunction(node, depth: depth)
        case .noncanonicalSpecializedGenericTypeMetadataCache:
            return mangleNoncanonicalSpecializedGenericTypeMetadataCache(node, depth: depth)
        case .relatedEntityDeclName:
            return mangleRelatedEntityDeclName(node, depth: depth)
        case .silBoxType:
            return mangleSILBoxType(node, depth: depth)
        case .silBoxTypeWithLayout:
            return mangleSILBoxTypeWithLayout(node, depth: depth)
        case .silBoxLayout:
            return mangleSILBoxLayout(node, depth: depth)
        case .silBoxImmutableField:
            return mangleSILBoxImmutableField(node, depth: depth)
        case .silBoxMutableField:
            return mangleSILBoxMutableField(node, depth: depth)
        case .silThunkIdentity:
            return mangleSILThunkIdentity(node, depth: depth)
        case .sugaredArray:
            return mangleSugaredArray(node, depth: depth)
        case .sugaredDictionary:
            return mangleSugaredDictionary(node, depth: depth)
        case .sugaredOptional:
            return mangleSugaredOptional(node, depth: depth)
        case .sugaredParen:
            return mangleSugaredParen(node, depth: depth)
        case .typedThrowsAnnotation:
            return mangleTypedThrowsAnnotation(node, depth: depth)
        case .uniquable:
            return mangleUniquable(node, depth: depth)
        case .vTableAttribute:
            return mangleVTableAttribute(node, depth: depth)
        case .vTableThunk:
            return mangleVTableThunk(node, depth: depth)
        case .outlinedEnumGetTag:
            return mangleOutlinedEnumGetTag(node, depth: depth)
        case .outlinedEnumProjectDataForLoad:
            return mangleOutlinedEnumProjectDataForLoad(node, depth: depth)
        case .outlinedEnumTagStore:
            return mangleOutlinedEnumTagStore(node, depth: depth)
        case .outlinedReadOnlyObject:
            return mangleOutlinedReadOnlyObject(node, depth: depth)
        case .outlinedDestroyNoValueWitness:
            return mangleOutlinedDestroyNoValueWitness(node, depth: depth)
        case .outlinedInitializeWithCopyNoValueWitness:
            return mangleOutlinedInitializeWithCopyNoValueWitness(node, depth: depth)
        case .outlinedAssignWithTakeNoValueWitness:
            return mangleOutlinedAssignWithTakeNoValueWitness(node, depth: depth)
        case .outlinedAssignWithCopyNoValueWitness:
            return mangleOutlinedAssignWithCopyNoValueWitness(node, depth: depth)
        case .packProtocolConformance:
            return manglePackProtocolConformance(node, depth: depth)
        case .accessorFunctionReference:
            return mangleAccessorFunctionReference(node, depth: depth)
        case .anyProtocolConformanceList:
            return mangleAnyProtocolConformanceList(node, depth: depth)
        case .associatedTypeWitnessTableAccessor:
            return mangleAssociatedTypeWitnessTableAccessor(node, depth: depth)
        case .autoDiffSelfReorderingReabstractionThunk:
            return mangleAutoDiffSelfReorderingReabstractionThunk(node, depth: depth)
        case .canonicalPrespecializedGenericTypeCachingOnceToken:
            return mangleCanonicalPrespecializedGenericTypeCachingOnceToken(node, depth: depth)
        case .canonicalSpecializedGenericMetaclass:
            return mangleCanonicalSpecializedGenericMetaclass(node, depth: depth)
        case .canonicalSpecializedGenericTypeMetadataAccessFunction:
            return mangleCanonicalSpecializedGenericTypeMetadataAccessFunction(node, depth: depth)
        case .constrainedExistentialRequirementList:
            return mangleConstrainedExistentialRequirementList(node, depth: depth)
        case .defaultAssociatedConformanceAccessor:
            return mangleDefaultAssociatedConformanceAccessor(node, depth: depth)
        case .defaultAssociatedTypeMetadataAccessor:
            return mangleDefaultAssociatedTypeMetadataAccessor(node, depth: depth)
        case .dependentGenericConformanceRequirement:
            return mangleDependentGenericConformanceRequirement(node, depth: depth)
        case .dependentGenericLayoutRequirement:
            return mangleDependentGenericLayoutRequirement(node, depth: depth)
        case .dependentGenericSameShapeRequirement:
            return mangleDependentGenericSameShapeRequirement(node, depth: depth)
        case .dependentGenericSameTypeRequirement:
            return mangleDependentGenericSameTypeRequirement(node, depth: depth)
        case .functionSignatureSpecializationParam:
            return mangleFunctionSignatureSpecializationParam(node, depth: depth)
        case .functionSignatureSpecializationReturn:
            return mangleFunctionSignatureSpecializationReturn(node, depth: depth)
        case .functionSignatureSpecializationParamKind:
            return mangleFunctionSignatureSpecializationParamKind(node, depth: depth)
        case .functionSignatureSpecializationParamPayload:
            return mangleFunctionSignatureSpecializationParamPayload(node, depth: depth)
        case .keyPathUnappliedMethodThunkHelper:
            return mangleKeyPathUnappliedMethodThunkHelper(node, depth: depth)
        case .lazyProtocolWitnessTableAccessor:
            return mangleLazyProtocolWitnessTableAccessor(node, depth: depth)
        case .lazyProtocolWitnessTableCacheVariable:
            return mangleLazyProtocolWitnessTableCacheVariable(node, depth: depth)
        case .noncanonicalSpecializedGenericTypeMetadata:
            return mangleNoncanonicalSpecializedGenericTypeMetadata(node, depth: depth)
        case .nonUniqueExtendedExistentialTypeShapeSymbolicReference:
            return mangleNonUniqueExtendedExistentialTypeShapeSymbolicReference(node, depth: depth)
        case .outlinedInitializeWithTakeNoValueWitness:
            return mangleOutlinedInitializeWithTakeNoValueWitness(node, depth: depth)
        case .predefinedObjCAsyncCompletionHandlerImpl:
            return manglePredefinedObjCAsyncCompletionHandlerImpl(node, depth: depth)
        case .protocolConformanceRefInTypeModule:
            return mangleProtocolConformanceRefInTypeModule(node, depth: depth)
        case .protocolConformanceRefInProtocolModule:
            return mangleProtocolConformanceRefInProtocolModule(node, depth: depth)
        case .protocolConformanceRefInOtherModule:
            return mangleProtocolConformanceRefInOtherModule(node, depth: depth)
        case .reflectionMetadataAssocTypeDescriptor:
            return mangleReflectionMetadataAssocTypeDescriptor(node, depth: depth)
        case .reflectionMetadataBuiltinDescriptor:
            return mangleReflectionMetadataBuiltinDescriptor(node, depth: depth)
        case .reflectionMetadataFieldDescriptor:
            return mangleReflectionMetadataFieldDescriptor(node, depth: depth)
        case .reflectionMetadataSuperclassDescriptor:
            return mangleReflectionMetadataSuperclassDescriptor(node, depth: depth)
        case .silThunkHopToMainActorIfNeeded:
            return mangleSILThunkHopToMainActorIfNeeded(node, depth: depth)
        case .sugaredInlineArray:
            return mangleSugaredInlineArray(node, depth: depth)
        case .typeMetadataInstantiationFunction:
            return mangleTypeMetadataInstantiationFunction(node, depth: depth)
        case .typeMetadataSingletonInitializationCache:
            return mangleTypeMetadataSingletonInitializationCache(node, depth: depth)
        case .uniqueExtendedExistentialTypeShapeSymbolicReference:
            return mangleUniqueExtendedExistentialTypeShapeSymbolicReference(node, depth: depth)
        }
    }

    // MARK: - Helper Methods

    /// Mangle child nodes in order
    func mangleChildNodes(_ node: Node, depth: Int) -> RemanglerError {
        for child in node.children {
            let result = mangleNode(child, depth: depth + 1)
            if !result.isSuccess {
                return result
            }
        }
        return .success
    }

    /// Mangle child nodes in reverse order
    func mangleChildNodesReversed(_ node: Node, depth: Int) -> RemanglerError {
        for child in node.children.reversed() {
            let result = mangleNode(child, depth: depth + 1)
            if !result.isSuccess {
                return result
            }
        }
        return .success
    }

    /// Mangle a single child node
    func mangleSingleChildNode(_ node: Node, depth: Int) -> RemanglerError {
        guard node.children.count == 1 else {
            return .multipleChildNodes(node)
        }
        return mangleNode(node.children[0], depth: depth + 1)
    }

    /// Mangle a specific child by index
    func mangleChildNode(_ node: Node, at index: Int, depth: Int) -> RemanglerError {
        guard index < node.children.count else {
            return .missingChildNode(node, expectedIndex: index)
        }
        return mangleNode(node.children[index], depth: depth + 1)
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
        case "AutoreleasingUnsafeMutablePointer": return "A"  // ObjC interop
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
