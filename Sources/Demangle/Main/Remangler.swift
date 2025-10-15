/// Swift name remangler - converts a demangling parse tree back into a mangled string.
///
/// This is useful for tools which want to extract or modify subtrees from mangled strings.
/// The remangler follows the same mangling conventions as the Swift compiler.
public final class Remangler: RemanglerBase {
    // MARK: - Constants

    /// Maximum recursion depth to prevent stack overflow
    internal static let maxDepth = 1024

    /// Maximum number of substitution words
    internal static let maxNumWords = 26

    // MARK: - Properties

    /// Callback for resolving symbolic references
    var symbolicReferenceResolver: SymbolicReferenceResolver?

    /// Whether to use Punycode encoding for non-ASCII identifiers
    let usePunycode: Bool

    let substMerging: Mangle.SubstitutionMerging

    // MARK: - Initialization

    public init(usePunycode: Bool = true) {
        self.usePunycode = usePunycode
        self.substMerging = Mangle.SubstitutionMerging()
        super.init()
    }

    // MARK: - Public API

    /// Remangle a node tree into a mangled string
    public func mangle(_ node: Node) -> RemanglerResult<String> {
        clearBuffer()

        let error = mangleNode(node, depth: 0)

        if error.isSuccess {
            return .success(buffer)
        } else {
            return .failure(error)
        }
    }

    /// Remangle a node tree into a mangled string (throwing version)
    public func mangleThrows(_ node: Node) throws -> String {
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
        // Top-level nodes
        case .global:
            return mangleGlobal(node, depth: depth)
        case .suffix:
            return mangleSuffix(node, depth: depth)

        // Type nodes
        case .type:
            return mangleType(node, depth: depth)
        case .typeMangling:
            return mangleTypeMangling(node, depth: depth)
        case .typeList:
            return mangleTypeList(node, depth: depth)

        // Nominal types
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

        // Function types
        case .functionType:
            return mangleFunctionType(node, depth: depth)
        case .argumentTuple:
            return mangleArgumentTuple(node, depth: depth)
        case .returnType:
            return mangleReturnType(node, depth: depth)
        case .labelList:
            return mangleLabelList(node, depth: depth)

        // Generic types
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

        // Identifiers
        case .identifier:
            return mangleIdentifier(node, depth: depth)
        case .privateDeclName:
            return manglePrivateDeclName(node, depth: depth)
        case .localDeclName:
            return mangleLocalDeclName(node, depth: depth)

        // Module and context
        case .module:
            return mangleModule(node, depth: depth)
        case .extension:
            return mangleExtension(node, depth: depth)
        case .declContext:
            return mangleDeclContext(node, depth: depth)
        case .anonymousContext:
            return mangleAnonymousContext(node, depth: depth)

        // Functions and methods
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

        // Built-in types and special types
        case .builtinTypeName:
            return mangleBuiltinTypeName(node, depth: depth)
        case .dynamicSelf:
            return mangleDynamicSelf(node, depth: depth)
        case .errorType:
            return mangleErrorType(node, depth: depth)

        // Tuple types
        case .tuple:
            return mangleTuple(node, depth: depth)
        case .tupleElement:
            return mangleTupleElement(node, depth: depth)
        case .tupleElementName:
            return mangleTupleElementName(node, depth: depth)

        // Dependent types
        case .dependentGenericParamType:
            return mangleDependentGenericParamType(node, depth: depth)
        case .dependentMemberType:
            return mangleDependentMemberType(node, depth: depth)

        // Protocol composition
        case .protocolList:
            return mangleProtocolList(node, depth: depth)
        case .protocolListWithClass:
            return mangleProtocolListWithClass(node, depth: depth)
        case .protocolListWithAnyObject:
            return mangleProtocolListWithAnyObject(node, depth: depth)

        // Metatypes
        case .metatype:
            return mangleMetatype(node, depth: depth)
        case .existentialMetatype:
            return mangleExistentialMetatype(node, depth: depth)

        // Attributes and modifiers
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

        // Numbers and indices
        case .number:
            return mangleNumber(node, depth: depth)
        case .index:
            return mangleIndexNode(node, depth: depth)

        // Variables and storage
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

        // Special function types
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

        // Witness tables and metadata
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

        // Static members
        case .static:
            return mangleStatic(node, depth: depth)

        // Initializers
        case .initializer:
            return mangleInitializer(node, depth: depth)

        // Operators
        case .prefixOperator:
            return manglePrefixOperator(node, depth: depth)
        case .postfixOperator:
            return manglePostfixOperator(node, depth: depth)
        case .infixOperator:
            return mangleInfixOperator(node, depth: depth)

        // Generic signature
        case .dependentGenericSignature:
            return mangleDependentGenericSignature(node, depth: depth)
        case .dependentGenericType:
            return mangleDependentGenericType(node, depth: depth)

        // Throwing and async
        case .throwsAnnotation:
            return mangleThrowsAnnotation(node, depth: depth)
        case .asyncAnnotation:
            return mangleAsyncAnnotation(node, depth: depth)

        // List markers
        case .emptyList:
            return mangleEmptyList(node, depth: depth)
        case .firstElementMarker:
            return mangleFirstElementMarker(node, depth: depth)
        case .variadicMarker:
            return mangleVariadicMarker(node, depth: depth)

        // Additional important nodes
        case .enumCase:
            return mangleEnumCase(node, depth: depth)
        case .fieldOffset:
            return mangleFieldOffset(node, depth: depth)

        // Bound generic types
        case .boundGenericFunction:
            return mangleBoundGenericFunction(node, depth: depth)
        case .boundGenericOtherNominalType:
            return mangleBoundGenericOtherNominalType(node, depth: depth)

        // Associated types
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

        // Protocol conformance
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

        // Metadata descriptors
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

        // Witness tables
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

        // Outlined operations
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

        // Pack support
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

        // Generic specialization
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

        // Impl function type
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

        // Descriptor/Record types
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

        // Opaque types
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

        // Thunk types
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

        // Macro support
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

        // Default case for unsupported nodes
        default:
            return .unsupportedNodeKind(node)
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

    /// Try to use a substitution for a node
    @discardableResult
    func trySubstitution(_ node: Node, treatAsIdentifier: Bool = false) -> Bool {
        // First try standard substitutions (Swift stdlib types)
        if mangleStandardSubstitution(node) {
            return true
        }

        // Create substitution entry
        let entry = entryForNode(node, treatAsIdentifier: treatAsIdentifier)

        // Look for existing substitution
        guard let index = findSubstitution(entry) else {
            return false
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

        return true
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
