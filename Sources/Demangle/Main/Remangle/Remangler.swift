/// Swift name remangler - converts a demangling parse tree back into a mangled string.
///
/// This is useful for tools which want to extract or modify subtrees from mangled strings.
/// The remangler follows the same mangling conventions as the Swift compiler.
final class Remangler {
    // MARK: - Constants

    /// Capacity of the hash-based node hash cache (must be power of 2)
    private static let hashHashCapacity = 512

    /// Maximum number of probes in hash table before giving up
    private static let hashHashMaxProbes = 8

    /// Capacity of inline substitution array (avoids heap allocation for common case)
    private static let inlineSubstCapacity = 16

    /// Maximum recursion depth to prevent stack overflow
    private static let maxDepth = 1024

    /// Maximum number of words to track (matches C++ MaxNumWords = 26)
    private static let maxNumWords = 26

    // MARK: - Properties

    let usePunycode: Bool

    let flavor = ManglingFlavor.default

    var symbolicReferenceResolver: SymbolicReferenceResolver?

    private let substMerging: SubstitutionMerging = .init()

    /// List of all words seen so far in the mangled string
    private var words: [SubstitutionWord] = []

    /// List of word replacements in the current identifier
    private var substWordsInIdent: [WordReplacement] = []

    /// Output buffer for mangled string
    private var buffer: String = ""

    /// Hash table for caching node hashes (avoids expensive recursive computation)
    private var hashHash: [SubstitutionEntry?] = Array(repeating: nil, count: hashHashCapacity)

    /// Inline storage for first 16 substitutions (fast path, no heap allocation)
    private var inlineSubstitutions: [SubstitutionEntry] = []

    /// Overflow storage for substitutions beyond inline capacity
    private var overflowSubstitutions: [SubstitutionEntry: UInt64] = [:]

    // MARK: - Initialization

    init(usePunycode: Bool) {
        self.usePunycode = usePunycode
        inlineSubstitutions.reserveCapacity(Self.inlineSubstCapacity)
    }

    // MARK: - Buffer Management

    /// Append a string to the output buffer
    private func append(_ string: String) {
        buffer.append(string)
    }

    /// Append a character to the output buffer
    private func append(_ char: Character) {
        buffer.append(char)
    }

    /// Append an integer to the output buffer
    private func append(_ value: UInt64) {
        buffer.append(String(value))
    }

    /// Reset the buffer to a previous position (index-based)
    private func resetBuffer(to position: String.Index) {
        buffer = String(buffer[..<position])
    }

    /// Reset the buffer to a previous position (count-based)
    private func resetBuffer(to position: Int) {
        let idx = buffer.index(buffer.startIndex, offsetBy: position)
        buffer = String(buffer[..<idx])
    }

    /// Get current buffer position
    private var bufferPosition: String.Index {
        return buffer.endIndex
    }

    /// Clear the buffer
    private func clearBuffer() {
        buffer = ""
    }

    // MARK: - Hash Computation

    /// Compute hash for a node, with caching to avoid expensive recursion
    private func hashForNode(_ node: Node, treatAsIdentifier: Bool = false) -> Int {
        var hash = 0

        if treatAsIdentifier {
            // Treat as identifier regardless of actual kind
            hash = combineHash(hash, Node.Kind.identifier.hashValue)

            if let text = node.text {
                // Handle operator character translation for operators
                if node.kind.isOperatorKind {
                    for char in text {
                        hash = combineHash(hash, translateOperatorChar(char).hashValue)
                    }
                } else {
                    for char in text {
                        hash = combineHash(hash, char.hashValue)
                    }
                }
            }
        } else {
            // Use actual node kind
            hash = combineHash(hash, node.kind.hashValue)

            // Combine index or text
            if let index = node.index {
                hash = combineHash(hash, Int(index))
            } else if let text = node.text {
                for char in text {
                    hash = combineHash(hash, char.hashValue)
                }
            }

            // Recursively hash children
            for child in node.children {
                let childEntry = entryForNode(child, treatAsIdentifier: treatAsIdentifier)
                hash = combineHash(hash, childEntry.storedHash)
            }
        }

        return hash
    }

    /// Combine two hash values
    private func combineHash(_ currentHash: Int, _ newValue: Int) -> Int {
        return 33 &* currentHash &+ newValue
    }

    /// Translate operator character for mangling
    /// Based on Swift's ManglingUtils.cpp translateOperatorChar
    private func translateOperatorChar(_ char: Character) -> Character {
        switch char {
        case "&": return "a" // 'and'
        case "@": return "c" // 'commercial at sign'
        case "/": return "d" // 'divide'
        case "=": return "e" // 'equal'
        case ">": return "g" // 'greater'
        case "<": return "l" // 'less'
        case "*": return "m" // 'multiply'
        case "!": return "n" // 'negate'
        case "|": return "o" // 'or'
        case "+": return "p" // 'plus'
        case "?": return "q" // 'question'
        case "%": return "r" // 'remainder'
        case "-": return "s" // 'subtract'
        case "~": return "t" // 'tilde'
        case "^": return "x" // 'xor'
        case ".": return "z" // 'zperiod'
        default: return char
        }
    }

    // MARK: - Substitution Entry Creation

    /// Create a SubstitutionEntry for a node, using the hash cache
    private func entryForNode(_ node: Node, treatAsIdentifier: Bool = false) -> SubstitutionEntry {
        // Compute hash of node pointer + treatment flag for cache lookup
        let ident = treatAsIdentifier ? 4 : 0
        let nodeHash = nodePointerHash(node) &+ ident

        // Linear probing with limited attempts
        for probe in 0 ..< Self.hashHashMaxProbes {
            let index = (nodeHash &+ probe) & (Self.hashHashCapacity - 1)

            if let cachedEntry = hashHash[index] {
                if cachedEntry.matches(node: node, treatAsIdentifier: treatAsIdentifier) {
                    // Cache hit
                    return cachedEntry
                }
            } else {
                // Cache miss - compute hash and store
                let hash = hashForNode(node, treatAsIdentifier: treatAsIdentifier)
                let entry = SubstitutionEntry(node: node, storedHash: hash, treatAsIdentifier: treatAsIdentifier)
                hashHash[index] = entry
                return entry
            }
        }

        // Hash table full at this location - compute without caching
        let hash = hashForNode(node, treatAsIdentifier: treatAsIdentifier)
        return SubstitutionEntry(node: node, storedHash: hash, treatAsIdentifier: treatAsIdentifier)
    }

    /// Compute a hash from a node pointer (for cache indexing)
    private func nodePointerHash(_ node: Node) -> Int {
        // Use ObjectIdentifier for pointer-like hashing
        let objectId = ObjectIdentifier(node)
        let prime = objectId.hashValue &* 2043

        // Rotate for better distribution (simulate pointer alignment patterns)
        return rotateHash(prime, by: 12)
    }

    /// Rotate hash bits
    private func rotateHash(_ value: Int, by shift: Int) -> Int {
        let bits = MemoryLayout<Int>.size * 8
        return (value >> shift) | (value << (bits - shift))
    }

    // MARK: - Substitution Management

    /// Find a substitution and return its index, or nil if not found
    private func findSubstitution(_ entry: SubstitutionEntry) -> UInt64? {
        // First search in inline substitutions (fast path)
        if let index = inlineSubstitutions.firstIndex(of: entry) {
            return UInt64(index)
        }

        // Then search in overflow substitutions
        if let index = overflowSubstitutions[entry] {
            return index
        }

        return nil
    }

    /// Add a substitution to the table
    private func addSubstitution(_ entry: SubstitutionEntry) {
        // Don't add duplicate substitutions
        if findSubstitution(entry) != nil {
            return
        }

        if inlineSubstitutions.count < Self.inlineSubstCapacity {
            // Still room in inline storage
            inlineSubstitutions.append(entry)
        } else {
            // Need to use overflow storage
            let index = overflowSubstitutions.count + Self.inlineSubstCapacity
            overflowSubstitutions[entry] = UInt64(index)
        }
    }

    /// Get total number of substitutions
    private var substitutionCount: Int {
        return inlineSubstitutions.count + overflowSubstitutions.count
    }

    /// Try to use an existing substitution for a node
    ///
    /// - Parameters:
    ///   - entry: The substitution entry to check
    /// - Returns: true if substitution was found and used, false otherwise
    private func trySubstitution(_ entry: SubstitutionEntry) -> Bool {
        guard let index = findSubstitution(entry) else {
            return false
        }

        // Mangle the substitution reference
        if index >= 26 {
            // Large index: "A" + mangleIndex(index - 26)
            append("A")
            mangleIndex(index - 26)
        } else {
            // Small index: "A" + character
            append("A")
            let char = Character(UnicodeScalar(UInt8(ascii: "A") + UInt8(index)))
            append(char)
        }
        return true
    }

    // MARK: - Helper Methods

    /// Mangle an index value
    ///
    /// Indices are mangled as:
    /// - 0 -> '_'
    /// - n -> '(n-1)_'
    private func mangleIndex(_ value: UInt64) {
        if value == 0 {
            append("_")
        } else {
            append(value &- 1)
            append("_")
        }
    }

    /// Mangle a list separator
    private func mangleListSeparator(_ isFirstItem: inout Bool) {
        if isFirstItem {
            append("_")
            isFirstItem = false
        }
    }

    /// Mangle end of list
    private func mangleEndOfList(_ isFirstItem: Bool) {
        if isFirstItem {
            append("y")
        }
    }

    // MARK: - Word Substitution Helpers

    /// Check if a character can start a word
    private func isWordStart(_ ch: Character) -> Bool {
        return !ch.isNumber && ch != "_" && ch != "\0"
    }

    /// Check if a character (following prevCh) defines the end of a word
    private func isWordEnd(_ ch: Character, _ prevCh: Character) -> Bool {
        if ch == "_" || ch == "\0" {
            return true
        }
        if !prevCh.isUppercase && ch.isUppercase {
            return true
        }
        return false
    }

    /// Add a word to the words list
    private func addWord(_ word: SubstitutionWord) {
        words.append(word)
    }

    /// Add a word replacement to the current identifier
    private func addSubstWordInIdent(_ repl: WordReplacement) {
        substWordsInIdent.append(repl)
    }

    /// Clear word replacements for the current identifier
    private func clearSubstWordsInIdent() {
        substWordsInIdent.removeAll(keepingCapacity: true)
    }

    // MARK: - Public API

    /// Remangle a node tree into a mangled string
    func mangle(_ node: Node) throws(ManglingError) -> String {
        clearBuffer()
        try mangle(node, depth: 0)
        return buffer
    }

    // MARK: - Core Mangling

    /// Main entry point for mangling a single node
    private func mangle(_ node: Node, depth: Int) throws(ManglingError) {
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
    private func mangleChildNodes(_ node: Node, depth: Int) throws(ManglingError) {
        for child in node.children {
            try mangle(child, depth: depth + 1)
        }
    }

    /// Mangle child nodes in reverse order
    private func mangleChildNodesReversed(_ node: Node, depth: Int) throws(ManglingError) {
        for child in node.children.reversed() {
            try mangle(child, depth: depth + 1)
        }
    }

    /// Mangle a single child node
    private func mangleSingleChildNode(_ node: Node, depth: Int) throws(ManglingError) {
        guard node.children.count == 1 else {
            throw .multipleChildNodes(node)
        }
        try mangle(node.children[0], depth: depth + 1)
    }

    /// Mangle a specific child by index
    private func mangleChildNode(_ node: Node, at index: Int, depth: Int) throws(ManglingError) {
        guard index < node.children.count else {
            throw .missingChildNode(node, expectedIndex: index)
        }
        try mangle(node.children[index], depth: depth + 1)
    }

    /// Get a single child, skipping Type wrapper if present
    private func skipType(_ node: Node) -> Node {
        if node.kind == .type && node.children.count == 1 {
            return node.children[0]
        }
        return node
    }

    /// Result of substitution lookup
    private struct SubstitutionResult {
        let entry: SubstitutionEntry
        let found: Bool
    }

    /// Try to use a substitution for a node (C++ compatible version)
    ///
    /// Returns both the entry and whether a substitution was found.
    /// The entry is always populated, so caller can add it to the substitution table if not found.
    private func trySubstitution(_ node: Node, treatAsIdentifier: Bool = false) -> SubstitutionResult {
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
    private func mangleStandardSubstitution(_ node: Node) -> Bool {
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

/// Extension containing specific node kind handlers
extension Remangler {
    // MARK: - Top-Level Nodes

    private func mangleGlobal(_ node: Node, depth: Int) throws(ManglingError) {
        switch flavor {
        case .default:
            append("_$s")
        case .embedded:
            append("_$e")
        }

        // Check if we need to mangle children in reverse order
        var mangleInReverseOrder = false

        for (index, child) in node.children.enumerated() {
            // Check if this child requires reverse order processing
            switch child.kind {
            case .functionSignatureSpecialization,
                 .genericSpecialization,
                 .genericSpecializationPrespecialized,
                 .genericSpecializationNotReAbstracted,
                 .genericSpecializationInResilienceDomain,
                 .inlinedGenericFunction,
                 .genericPartialSpecialization,
                 .genericPartialSpecializationNotReAbstracted,
                 .outlinedBridgedMethod,
                 .outlinedVariable,
                 .outlinedReadOnlyObject,
                 .objCAttribute,
                 .nonObjCAttribute,
                 .dynamicAttribute,
                 .vTableAttribute,
                 .directMethodReferenceAttribute,
                 .mergedFunction,
                 .distributedThunk,
                 .distributedAccessor,
                 .dynamicallyReplaceableFunctionKey,
                 .dynamicallyReplaceableFunctionImpl,
                 .dynamicallyReplaceableFunctionVar,
                 .asyncFunctionPointer,
                 .asyncAwaitResumePartialFunction,
                 .asyncSuspendResumePartialFunction,
                 .accessibleFunctionRecord,
                 .backDeploymentThunk,
                 .backDeploymentFallback,
                 .hasSymbolQuery,
                 .coroFunctionPointer,
                 .defaultOverride:
                mangleInReverseOrder = true

            default:
                // Mangle the current child
                try mangle(child, depth: depth + 1)

                // If we need reverse order, mangle all previous children in reverse
                if mangleInReverseOrder {
                    var reverseIndex = index
                    while reverseIndex != 0 {
                        reverseIndex -= 1
                        try mangle(node[safeChild: reverseIndex], depth: depth + 1)
                    }
                    mangleInReverseOrder = false
                }
            }
        }
    }

    private func mangleSuffix(_ node: Node, depth: Int) throws(ManglingError) {
        // Suffix is appended as-is
        if let text = node.text {
            append(text)
        }
    }

    // MARK: - Specialization Helpers

    /// Check if a node is specialized (has bound generics in its context chain)
    private func isSpecialized(_ node: Node) -> Bool {
        switch node.kind {
        case .boundGenericStructure,
             .boundGenericEnum,
             .boundGenericClass,
             .boundGenericOtherNominalType,
             .boundGenericTypeAlias,
             .boundGenericProtocol,
             .boundGenericFunction,
             .constrainedExistential:
            return true

        case .structure,
             .enum,
             .class,
             .typeAlias,
             .otherNominalType,
             .protocol,
             .function,
             .allocator,
             .constructor,
             .destructor,
             .variable,
             .subscript,
             .explicitClosure,
             .implicitClosure,
             .initializer,
             .propertyWrapperBackingInitializer,
             .propertyWrapperInitFromProjectedValue,
             .defaultArgumentInitializer,
             .getter,
             .setter,
             .willSet,
             .didSet,
             .readAccessor,
             .modifyAccessor,
             .unsafeAddressor,
             .unsafeMutableAddressor,
             .static:
            return node.children.count > 0 && isSpecialized(node.children[0])

        case .extension:
            return node.children.count > 1 && isSpecialized(node.children[1])

        default:
            return false
        }
    }

    /// Get the unspecialized version of a node (removes BoundGeneric wrappers)
    private func getUnspecialized(_ node: Node) -> Node? {
        var numToCopy = 2

        switch node.kind {
        case .function,
             .getter,
             .setter,
             .willSet,
             .didSet,
             .readAccessor,
             .modifyAccessor,
             .unsafeAddressor,
             .unsafeMutableAddressor,
             .allocator,
             .constructor,
             .destructor,
             .variable,
             .subscript,
             .explicitClosure,
             .implicitClosure,
             .initializer,
             .propertyWrapperBackingInitializer,
             .propertyWrapperInitFromProjectedValue,
             .defaultArgumentInitializer,
             .static:
            numToCopy = node.children.count
            fallthrough

        case .structure,
             .enum,
             .class,
             .typeAlias,
             .otherNominalType:
            guard node.children.count > 0 else { return nil }

            let result = Node(kind: node.kind)
            var parentOrModule = node.children[0]
            if isSpecialized(parentOrModule) {
                guard let unspec = getUnspecialized(parentOrModule) else { return nil }
                parentOrModule = unspec
            }
            result.addChild(parentOrModule)
            for idx in 1 ..< numToCopy {
                if idx < node.children.count {
                    result.addChild(node.children[idx])
                }
            }
            return result

        case .boundGenericStructure,
             .boundGenericEnum,
             .boundGenericClass,
             .boundGenericProtocol,
             .boundGenericOtherNominalType,
             .boundGenericTypeAlias:
            guard node.children.count > 0 else { return nil }
            let unboundType = node.children[0]
            guard unboundType.kind == .type, unboundType.children.count > 0 else { return nil }
            let nominalType = unboundType.children[0]
            if isSpecialized(nominalType) {
                return getUnspecialized(nominalType)
            }
            return nominalType

        case .constrainedExistential:
            guard node.children.count > 0 else { return nil }
            let unboundType = node.children[0]
            guard unboundType.kind == .type else { return nil }
            return unboundType

        case .boundGenericFunction:
            guard node.children.count > 0 else { return nil }
            let unboundFunction = node.children[0]
            guard unboundFunction.kind == .function || unboundFunction.kind == .constructor else {
                return nil
            }
            if isSpecialized(unboundFunction) {
                return getUnspecialized(unboundFunction)
            }
            return unboundFunction

        case .extension:
            guard node.children.count >= 2 else { return nil }
            let parent = node.children[1]
            if !isSpecialized(parent) {
                return node
            }
            guard let unspec = getUnspecialized(parent) else { return nil }
            let result = Node(kind: .extension)
            result.addChild(node.children[0])
            result.addChild(unspec)
            if node.children.count == 3 {
                result.addChild(node.children[2])
            }
            return result

        default:
            return nil
        }
    }

    /// Mangle generic arguments from a context chain
    private func mangleGenericArgs(_ node: Node, separator: inout Character, depth: Int, fullSubstitutionMap: Bool = false) throws(ManglingError) {
        var fullSubst = fullSubstitutionMap

        switch node.kind {
        case .protocol,
             .structure,
             .enum,
             .class,
             .typeAlias:
            // TypeAlias always uses full substitution map
            if node.kind == .typeAlias {
                fullSubst = true
            }

            try mangleGenericArgs(node[safeChild: 0], separator: &separator, depth: depth + 1, fullSubstitutionMap: fullSubst)
            append(String(separator))
            separator = "_"

        case .function,
             .getter,
             .setter,
             .willSet,
             .didSet,
             .readAccessor,
             .modifyAccessor,
             .unsafeAddressor,
             .unsafeMutableAddressor,
             .allocator,
             .constructor,
             .destructor,
             .variable,
             .subscript,
             .explicitClosure,
             .implicitClosure,
             .defaultArgumentInitializer,
             .initializer,
             .propertyWrapperBackingInitializer,
             .propertyWrapperInitFromProjectedValue,
             .static:
            // Only process these if fullSubstitutionMap is true
            if !fullSubst {
                break
            }

            try mangleGenericArgs(node[safeChild: 0], separator: &separator, depth: depth + 1, fullSubstitutionMap: fullSubst)

            // Only add separator if this node consumes generic args
            if nodeConsumesGenericArgs(node) {
                append(String(separator))
                separator = "_"
            }

        case .boundGenericStructure,
             .boundGenericEnum,
             .boundGenericClass,
             .boundGenericProtocol,
             .boundGenericOtherNominalType,
             .boundGenericTypeAlias:
            // BoundGenericTypeAlias always uses full substitution map
            if node.kind == .boundGenericTypeAlias {
                fullSubst = true
            }

            let unboundType = try node[safeChild: 0]
            let nominalType = try unboundType[safeChild: 0]
            let parentOrModule = try nominalType[safeChild: 0]
            try mangleGenericArgs(parentOrModule, separator: &separator, depth: depth + 1, fullSubstitutionMap: fullSubst)
            append(String(separator))
            separator = "_"
            // Mangle type arguments from TypeList (child 1)
            try mangleChildNodes(node[safeChild: 1], depth: depth + 1)

        case .constrainedExistential:
            append(String(separator))
            separator = "_"
            try mangleChildNodes(node[safeChild: 1], depth: depth + 1)

        case .boundGenericFunction:
            fullSubst = true

            let unboundFunction = try node[safeChild: 0]
            let parentOrModule = try unboundFunction[safeChild: 0]
            try mangleGenericArgs(parentOrModule, separator: &separator, depth: depth + 1, fullSubstitutionMap: fullSubst)
            append(String(separator))
            separator = "_"
            try mangleChildNodes(node[safeChild: 1], depth: depth + 1)

        case .extension:
            try mangleGenericArgs(node[safeChild: 1], separator: &separator, depth: depth + 1, fullSubstitutionMap: fullSubst)

        default:
            break
        }
    }

    /// Check if a node consumes generic arguments
    private func nodeConsumesGenericArgs(_ node: Node) -> Bool {
        switch node.kind {
        case .variable,
             .subscript,
             .implicitClosure,
             .explicitClosure,
             .defaultArgumentInitializer,
             .initializer,
             .propertyWrapperBackingInitializer,
             .propertyWrapperInitFromProjectedValue,
             .static:
            return false
        default:
            return true
        }
    }

    // MARK: - Type Nodes

    private func mangleType(_ node: Node, depth: Int) throws(ManglingError) {
        try mangleSingleChildNode(node, depth: depth + 1)
    }

    private func mangleTypeMangling(_ node: Node, depth: Int) throws(ManglingError) {
        // TypeMangling only outputs children and 'D' suffix
        // The '_$s' prefix is output by the Global node
        try mangleChildNodes(node, depth: depth + 1)
        append("D")
    }

    private func mangleTypeList(_ node: Node, depth: Int) throws(ManglingError) {
        // Type list with proper list separators
        var isFirst = true
        for child in node.children {
            try mangle(child, depth: depth + 1)
            mangleListSeparator(&isFirst)
        }
        mangleEndOfList(isFirst)
    }

    // MARK: - Nominal Types

    private func mangleStructure(_ node: Node, depth: Int) throws(ManglingError) {
        try mangleAnyNominalType(node, depth: depth + 1)
    }

    private func mangleClass(_ node: Node, depth: Int) throws(ManglingError) {
        try mangleAnyNominalType(node, depth: depth + 1)
    }

    private func mangleEnum(_ node: Node, depth: Int) throws(ManglingError) {
        try mangleAnyNominalType(node, depth: depth + 1)
    }

    private func mangleProtocol(_ node: Node, depth: Int) throws(ManglingError) {
        try mangleAnyGenericType(node, typeOp: "P", depth: depth + 1)
    }

    private func mangleTypeAlias(_ node: Node, depth: Int) throws(ManglingError) {
        try mangleAnyNominalType(node, depth: depth + 1)
    }

    // MARK: - Bound Generic Types

    private func mangleBoundGenericStructure(_ node: Node, depth: Int) throws(ManglingError) {
        try mangleAnyNominalType(node, depth: depth + 1)
    }

    private func mangleBoundGenericClass(_ node: Node, depth: Int) throws(ManglingError) {
        try mangleAnyNominalType(node, depth: depth + 1)
    }

    private func mangleBoundGenericEnum(_ node: Node, depth: Int) throws(ManglingError) {
        let enumNode = try node[safeChild: 0][safeChild: 0]
        assert(enumNode.kind == .enum)
        let moduleNode = try enumNode[safeChild: 0]
        let identNode = try enumNode[safeChild: 1]
        if moduleNode.kind == .module, moduleNode.text == "Swift",
           identNode.kind == .identifier, identNode.text == "Optional" {
            // This is Swift.Optional - use sugar form
            let substResult = trySubstitution(node)
            if substResult.found {
                return
            }

            try mangleSingleChildNode(node[safeChild: 1], depth: depth + 1)

            append("Sg")

            // Add to substitution table (use entry from trySubstitution)
            addSubstitution(substResult.entry)
            return
        }

        // Not Optional - use standard bound generic mangling
        try mangleAnyNominalType(node, depth: depth + 1)
    }

    // MARK: - Function Types

    private func mangleFunctionType(_ node: Node, depth: Int) throws(ManglingError) {
        // Function type: reverse children (result comes first in mangling)
        try mangleFunctionSignature(node, depth: depth + 1)
        append("c")
    }

    private func mangleFunctionSignature(_ node: Node, depth: Int) throws(ManglingError) {
        try mangleChildNodesReversed(node, depth: depth)
    }

    private func mangleArgumentTuple(_ node: Node, depth: Int) throws(ManglingError) {
        let child = try skipType(node[safeChild: 0])

        if child.kind == .tuple, child.children.count == 0 {
            append("y")
            return
        }

        try mangle(child, depth: depth + 1)
    }

    private func mangleReturnType(_ node: Node, depth: Int) throws(ManglingError) {
        // Return type uses same logic as ArgumentTuple
        try mangleArgumentTuple(node, depth: depth + 1)
    }

    // MARK: - Functions and Methods

    private func mangleFunction(_ node: Node, depth: Int) throws(ManglingError) {
        // Mangle context (child 0)
        try mangleChildNode(node, at: 0, depth: depth + 1)

        try mangleChildNode(node, at: 1, depth: depth + 1)

        let hasLabels = try node[safeChild: 2].kind == .labelList

        let funcTypeNode = try node[safeChild: hasLabels ? 3 : 2][safeChild: 0]

        if hasLabels {
            try mangleChildNode(node, at: 2, depth: depth + 1)
        }

        if funcTypeNode.kind == .dependentGenericType {
            try mangleFunctionSignature(funcTypeNode[safeChild: 1][safeChild: 0], depth: depth + 1)
            try mangleChildNode(funcTypeNode, at: 0, depth: depth + 1)
        } else {
            try mangleFunctionSignature(funcTypeNode, depth: depth + 1)
        }

        append("F")
    }

    private func mangleAllocator(_ node: Node, depth: Int) throws(ManglingError) {
        try mangleAnyConstructor(node, kindOp: "C", depth: depth + 1)
    }

    private func mangleConstructor(_ node: Node, depth: Int) throws(ManglingError) {
        try mangleAnyConstructor(node, kindOp: "c", depth: depth)
    }

    private func mangleDestructor(_ node: Node, depth: Int) throws(ManglingError) {
        try mangleChildNodes(node, depth: depth + 1)
        append("fd")
    }

    private func mangleGetter(_ node: Node, depth: Int) throws(ManglingError) {
        try mangleAbstractStorage(node.firstChild, accessorCode: "g", depth: depth + 1)
    }

    private func mangleSetter(_ node: Node, depth: Int) throws(ManglingError) {
        try mangleAbstractStorage(node.firstChild, accessorCode: "s", depth: depth + 1)
    }

    private func mangleAbstractStorage(_ node: Node, accessorCode: String, depth: Int) throws(ManglingError) {
        try mangleChildNodes(node, depth: depth + 1)

        // Output storage kind marker
        switch node.kind {
        case .subscript:
            append("i")
        case .variable:
            append("v")
        default:
            throw .invalidNodeStructure(node, message: "Not a storage node")
        }

        // Output accessor code
        append(accessorCode)
    }

    // MARK: - Identifiers and Names

    private func mangleIdentifier(_ node: Node, depth: Int) throws(ManglingError) {
        mangleIdentifierImpl(node, isOperator: false)
    }

    private func manglePrivateDeclName(_ node: Node, depth: Int) throws(ManglingError) {
        try mangleChildNodesReversed(node, depth: depth + 1)
        append(node.numberOfChildren == 1 ? "Ll" : "LL")
    }

    private func mangleLocalDeclName(_ node: Node, depth: Int) throws(ManglingError) {
        try mangleChildNode(node, at: 1, depth: depth + 1)

        append("L")

        try mangleChildNode(node, at: 0, depth: depth + 1)
    }

    private func mangleIdentifierImpl(_ node: Node, isOperator: Bool) {
        // Get the text from the node
        guard let text = node.text else {
            // This shouldn't happen, but handle gracefully
            return
        }

        // Try to use an existing substitution
        let substResult = trySubstitution(node, treatAsIdentifier: true)
        if substResult.found {
            return
        }

        // Mangle the identifier text
        let processedText: String
        if isOperator {
            processedText = Self.translateOperator(text)
        } else {
            processedText = text
        }
        
        // Use the shared Mangle.mangleIdentifier implementation
        Self.mangleIdentifier(self, processedText)

        // Add this node to the substitution table
        addSubstitution(substResult.entry)
    }

    private func encodePunycode(_ text: String) -> String? {
        // Use the Punycode encoding implementation
        // mapNonSymbolChars: true to handle non-symbol characters
        return Punycode.encodePunycode(text, mapNonSymbolChars: true)
    }

    // MARK: - Module and Context

    private func mangleModule(_ node: Node, depth: Int) throws(ManglingError) {
        guard let name = node.text else {
            throw .invalidNodeStructure(node, message: "Module has no text")
        }

        // Handle special module names with shortcuts
        if name == stdlibName {
            append("s")
        } else if name == objcModule {
            append("So")
        } else if name == cModule {
            append("SC")
        } else {
            // Module name - use identifier mangling (which handles substitution)
            try mangleIdentifier(node, depth: depth)
        }
    }

    private func mangleExtension(_ node: Node, depth: Int) throws(ManglingError) {
        // Extension: extended type (child 1), extending module (child 0), optional generic signature (child 2)
        guard node.children.count >= 2 else {
            throw .invalidNodeStructure(node, message: "Extension needs at least 2 children")
        }

        // Mangle child 1 (the extended type) first
        try mangleChildNode(node, at: 1, depth: depth + 1)

        // Then mangle child 0 (the extending module)
        try mangleChildNode(node, at: 0, depth: depth + 1)

        // If there's a third child (generic signature), mangle it
        if node.children.count == 3 {
            try mangleChildNode(node, at: 2, depth: depth + 1)
        }

        append("E")
    }

    // MARK: - Built-in Types

    private func mangleBuiltinTypeName(_ node: Node, depth: Int) throws(ManglingError) {
        guard let name = node.text else {
            throw .invalidNodeStructure(node, message: "BuiltinTypeName has no text")
        }

        append("B")

        // Handle special builtin types (matching C++ order and logic)
        if name == "Builtin.BridgeObject" {
            append("b")
        } else if name == "Builtin.UnsafeValueBuffer" {
            append("B")
        } else if name == "Builtin.UnknownObject" {
            append("O")
        } else if name == "Builtin.NativeObject" {
            append("o")
        } else if name == "Builtin.RawPointer" {
            append("p")
        } else if name == "Builtin.RawUnsafeContinuation" {
            append("c")
        } else if name == "Builtin.Job" {
            append("j")
        } else if name == "Builtin.DefaultActorStorage" {
            append("D")
        } else if name == "Builtin.NonDefaultDistributedActorStorage" {
            append("d")
        } else if name == "Builtin.Executor" {
            append("e")
        } else if name == "Builtin.SILToken" {
            append("t")
        } else if name == "Builtin.IntLiteral" {
            append("I")
        } else if name == "Builtin.Word" {
            append("w")
        } else if name == "Builtin.PackIndex" {
            append("P")
        } else if name.hasPrefix("Builtin.Int") {
            // Int types: Builtin.Int<width>
            let width = name.dropFirst("Builtin.Int".count)
            append("i\(width)_")
        } else if name.hasPrefix("Builtin.FPIEEE") {
            // Float types: Builtin.FPIEEE<width>
            let width = name.dropFirst("Builtin.FPIEEE".count)
            append("f\(width)_")
        } else if name.hasPrefix("Builtin.Vec") {
            // Vector type: Builtin.Vec<count>x<element>
            // Example: Builtin.Vec4xInt32 or Builtin.Vec4xFPIEEE32
            let rest = String(name.dropFirst("Builtin.Vec".count))
            if let xIndex = rest.firstIndex(of: "x") {
                let count = rest[..<xIndex]
                let element = rest[rest.index(after: xIndex)...]

                // Determine element type
                if element == "RawPointer" {
                    append("p")
                } else if element.hasPrefix("FPIEEE") {
                    let width = element.dropFirst("FPIEEE".count)
                    append("f\(width)_")
                } else if element.hasPrefix("Int") {
                    let width = element.dropFirst("Int".count)
                    append("i\(width)_")
                } else {
                    throw .unexpectedBuiltinVectorType(node)
                }
                append("Bv\(count)_")
            } else {
                throw .unexpectedBuiltinVectorType(node)
            }
        } else {
            throw .unexpectedBuiltinType(node)
        }
    }

    // MARK: - Tuple Types

    private func mangleTuple(_ node: Node, depth: Int) throws(ManglingError) {
        // Use mangleTypeList which handles proper list separators
        try mangleTypeList(node, depth: depth + 1)
        append("t")
    }

    private func mangleTupleElement(_ node: Node, depth: Int) throws(ManglingError) {
        // Tuple element: optional label + type
        // C++ uses mangleChildNodesReversed, so mangle in reverse order: type, then label
        try mangleChildNodesReversed(node, depth: depth + 1)
    }

    // MARK: - Dependent Types

    private func mangleDependentGenericParamType(_ node: Node, depth: Int) throws(ManglingError) {
        if node.children.count == 2,
           let paramDepth = try node[safeChild: 0].index,
           let paramIndex = try node[safeChild: 1].index,
           paramDepth == 0, paramIndex == 0 {
            append("x")
            return
        }

        append("q")
        try mangleDependentGenericParamIndex(node)
    }

    private func mangleDependentMemberType(_ node: Node, depth: Int) throws(ManglingError) {
        // Call mangleConstrainedType to handle the whole chain with substitutions
        let (numMembers, paramIdx) = try mangleConstrainedType(node, depth: depth + 1)

        // Based on chain size, output the appropriate suffix
        switch numMembers {
        case -1:
            // Substitution was used - nothing more to output
            break

        case 0:
            // Error case - shouldn't happen with valid dependent member types
            throw .invalidNodeStructure(node, message: "WrongDependentMemberType")

        case 1:
            // Single member access
            append("Q")
            if let dependentBase = paramIdx {
                try mangleDependentGenericParamIndex(dependentBase, nonZeroPrefix: "y", zeroOp: "z")
            } else {
                append("x")
            }

        default:
            // Multiple member accesses
            append("Q")
            if let dependentBase = paramIdx {
                try mangleDependentGenericParamIndex(dependentBase, nonZeroPrefix: "Y", zeroOp: "Z")
            } else {
                append("X")
            }
        }
    }

    // MARK: - Protocol Composition

    /// Helper function for mangling protocol lists with optional superclass or AnyObject
    private func mangleProtocolList(_ protocols: Node, superclass: Node?, hasExplicitAnyObject: Bool, depth: Int) throws(ManglingError) {
        let typeList = try protocols.firstChild

        // Mangle each protocol
        var isFirst = true
        for child in typeList.children {
            try manglePureProtocol(child, depth: depth + 1)
            mangleListSeparator(&isFirst)
        }

        mangleEndOfList(isFirst)

        // Append suffix based on type
        if let superclass = superclass {
            try mangleType(superclass, depth: depth + 1)
            append("Xc")
        } else if hasExplicitAnyObject {
            append("Xl")
        } else {
            append("p")
        }
    }

    private func mangleProtocolList(_ node: Node, depth: Int) throws(ManglingError) {
        try mangleProtocolList(node, superclass: nil, hasExplicitAnyObject: false, depth: depth + 1)
    }

    private func mangleProtocolListWithClass(_ node: Node, depth: Int) throws(ManglingError) {
        try mangleProtocolList(node[safeChild: 0], superclass: node[safeChild: 1], hasExplicitAnyObject: false, depth: depth + 1)
    }

    private func mangleProtocolListWithAnyObject(_ node: Node, depth: Int) throws(ManglingError) {
        try mangleProtocolList(node[safeChild: 0], superclass: nil, hasExplicitAnyObject: true, depth: depth + 1)
    }

    // MARK: - Metatypes

    private func mangleMetatype(_ node: Node, depth: Int) throws(ManglingError) {
        if try node.firstChild.kind == .metatypeRepresentation {
            try mangleChildNode(node, at: 1, depth: depth + 1)
            append("XM")
            try mangleChildNode(node, at: 0, depth: depth + 1)
        } else {
            // Normal case: output single child + "m"
            try mangleSingleChildNode(node, depth: depth + 1)
            append("m")
        }
    }

    private func mangleExistentialMetatype(_ node: Node, depth: Int) throws(ManglingError) {
        if try node.firstChild.kind == .metatypeRepresentation {
            try mangleChildNode(node, at: 1, depth: depth + 1)
            append("Xm")
            try mangleChildNode(node, at: 0, depth: depth + 1)
        } else {
            try mangleSingleChildNode(node, depth: depth)
            append("Xp")
        }
    }

    // MARK: - Attributes and Modifiers

    private func mangleInOut(_ node: Node, depth: Int) throws(ManglingError) {
        try mangleSingleChildNode(node, depth: depth)
        append("z")
    }

    private func mangleShared(_ node: Node, depth: Int) throws(ManglingError) {
        try mangleSingleChildNode(node, depth: depth)
        append("h")
    }

    private func mangleOwned(_ node: Node, depth: Int) throws(ManglingError) {
        try mangleSingleChildNode(node, depth: depth)
        append("n")
    }

    // MARK: - Numbers and Indices

    private func mangleNumber(_ node: Node, depth: Int) throws(ManglingError) {
        guard let index = node.index else {
            throw .invalidNodeStructure(node, message: "Number has no index")
        }
        mangleIndex(index)
    }

    // MARK: - Bound Generic Types (Additional)

    private func mangleBoundGenericProtocol(_ node: Node, depth: Int) throws(ManglingError) {
        try mangleAnyNominalType(node, depth: depth + 1)
    }

    private func mangleBoundGenericTypeAlias(_ node: Node, depth: Int) throws(ManglingError) {
        try mangleAnyNominalType(node, depth: depth + 1)
    }

    // MARK: - Variables and Storage

    private func mangleVariable(_ node: Node, depth: Int) throws(ManglingError) {
        try mangleAbstractStorage(node, accessorCode: "p", depth: depth + 1)
    }

    private func mangleSubscript(_ node: Node, depth: Int) throws(ManglingError) {
        try mangleAbstractStorage(node, accessorCode: "p", depth: depth + 1)
    }

    private func mangleDidSet(_ node: Node, depth: Int) throws(ManglingError) {
        try mangleAbstractStorage(node[safeChild: 0], accessorCode: "W", depth: depth + 1)
    }

    private func mangleWillSet(_ node: Node, depth: Int) throws(ManglingError) {
        try mangleAbstractStorage(node[safeChild: 0], accessorCode: "w", depth: depth + 1)
    }

    private func mangleReadAccessor(_ node: Node, depth: Int) throws(ManglingError) {
        try mangleAbstractStorage(node[safeChild: 0], accessorCode: "r", depth: depth + 1)
    }

    private func mangleModifyAccessor(_ node: Node, depth: Int) throws(ManglingError) {
        try mangleAbstractStorage(node[safeChild: 0], accessorCode: "M", depth: depth + 1)
    }

    // MARK: - Reference Storage

    private func mangleWeak(_ node: Node, depth: Int) throws(ManglingError) {
        try mangleSingleChildNode(node, depth: depth + 1)
        append("Xw")
    }

    private func mangleUnowned(_ node: Node, depth: Int) throws(ManglingError) {
        try mangleSingleChildNode(node, depth: depth + 1)
        append("Xo")
    }

    private func mangleUnmanaged(_ node: Node, depth: Int) throws(ManglingError) {
        try mangleSingleChildNode(node, depth: depth + 1)
        append("Xu")
    }

    // MARK: - Special Function Types

    private func mangleThinFunctionType(_ node: Node, depth: Int) throws(ManglingError) {
        try mangleFunctionSignature(node, depth: depth + 1)
        append("Xf")
    }

    private func mangleNoEscapeFunctionType(_ node: Node, depth: Int) throws(ManglingError) {
        try mangleChildNodesReversed(node, depth: depth + 1)
        append("XE")
    }

    private func mangleAutoClosureType(_ node: Node, depth: Int) throws(ManglingError) {
        try mangleChildNodesReversed(node, depth: depth + 1)
        append("XK")
    }

    private func mangleEscapingAutoClosureType(_ node: Node, depth: Int) throws(ManglingError) {
        try mangleChildNodesReversed(node, depth: depth + 1)
        append("XA")
    }

    private func mangleUncurriedFunctionType(_ node: Node, depth: Int) throws(ManglingError) {
        try mangleFunctionSignature(node, depth: depth + 1)
        append("c")
    }

    // MARK: - Protocol and Type References

    private func mangleProtocolWitness(_ node: Node, depth: Int) throws(ManglingError) {
        try mangleChildNodes(node, depth: depth + 1)
        append("TW")
    }

    private func mangleProtocolWitnessTable(_ node: Node, depth: Int) throws(ManglingError) {
        try mangleSingleChildNode(node, depth: depth + 1)
        append("WP")
    }

    private func mangleProtocolWitnessTableAccessor(_ node: Node, depth: Int) throws(ManglingError) {
        try mangleSingleChildNode(node, depth: depth + 1)
        append("Wa")
    }

    private func mangleValueWitness(_ node: Node, depth: Int) throws(ManglingError) {
        // Convert index to ValueWitnessKind
        let rawValue = try node.firstChild.index
        guard let rawValue, let kind = ValueWitnessKind(rawValue: rawValue) else {
            throw .invalidNodeStructure(node, message: "Invalid ValueWitnessKind index: \(rawValue as Any)")
        }

        // Mangle the type (second child)
        try mangleChildNode(node, at: 1, depth: depth + 1)

        // Append "w" + code
        append("w")
        append(kind.code)
    }

    private func mangleValueWitnessTable(_ node: Node, depth: Int) throws(ManglingError) {
        try mangleSingleChildNode(node, depth: depth + 1)
        append("WV")
    }

    // MARK: - Metadata

    private func mangleTypeMetadata(_ node: Node, depth: Int) throws(ManglingError) {
        try mangleSingleChildNode(node, depth: depth + 1)
        append("N")
    }

    private func mangleTypeMetadataAccessFunction(_ node: Node, depth: Int) throws(ManglingError) {
        try mangleSingleChildNode(node, depth: depth + 1)
        append("Ma")
    }

    private func mangleFullTypeMetadata(_ node: Node, depth: Int) throws(ManglingError) {
        try mangleSingleChildNode(node, depth: depth + 1)
        append("Mf")
    }

    private func mangleMetaclass(_ node: Node, depth: Int) throws(ManglingError) {
        try mangleChildNodes(node, depth: depth + 1)
        append("Mm")
    }

    // MARK: - Static and Class Members

    private func mangleStatic(_ node: Node, depth: Int) throws(ManglingError) {
        try mangleSingleChildNode(node, depth: depth + 1)
        append("Z")
    }

    // MARK: - Initializers

    private func mangleInitializer(_ node: Node, depth: Int) throws(ManglingError) {
        try mangleChildNodes(node, depth: depth + 1)
        append("fi")
    }

    // MARK: - Operators

    private func manglePrefixOperator(_ node: Node, depth: Int) throws(ManglingError) {
        mangleIdentifierImpl(node, isOperator: true)
        append("op")
    }

    private func manglePostfixOperator(_ node: Node, depth: Int) throws(ManglingError) {
        mangleIdentifierImpl(node, isOperator: true)
        append("oP")
    }

    private func mangleInfixOperator(_ node: Node, depth: Int) throws(ManglingError) {
        mangleIdentifierImpl(node, isOperator: true)
        append("oi")
    }

    // MARK: - Generic Signature

    private func mangleDependentGenericSignature(_ node: Node, depth: Int) throws(ManglingError) {
        // First, separate param counts from requirements
        var paramCountEnd = 0

        for (idx, child) in node.children.enumerated() {
            if child.kind == .dependentGenericParamCount {
                paramCountEnd = idx + 1
            } else {
                // It's a requirement - mangle it
                try mangleChildNode(node, at: idx, depth: depth + 1)
            }
        }

        if paramCountEnd == 1, try node[safeChild: 0].index == 1 {
            append("l")
            return
        }

        append("r")
        for index in 0 ..< paramCountEnd {
            let count = try node[safeChild: index]
            if let countIndex = count.index, countIndex > 0 {
                mangleIndex(countIndex - 1)
            } else {
                append("z")
            }
        }
        append("l")
    }

    private func mangleDependentGenericType(_ node: Node, depth: Int) throws(ManglingError) {
        // Mangle children in reverse order (type, then generic signature)
        try mangleChildNodesReversed(node, depth: depth + 1)
        append("u")
    }

    // MARK: - Throwing and Async

    private func mangleThrowsAnnotation(_ node: Node, depth: Int) throws(ManglingError) {
        append("K")
    }

    private func mangleAsyncAnnotation(_ node: Node, depth: Int) throws(ManglingError) {
        append("Ya")
    }

    // MARK: - Context

    private func mangleDeclContext(_ node: Node, depth: Int) throws(ManglingError) {
        try mangleSingleChildNode(node, depth: depth + 1)
    }

    private func mangleAnonymousContext(_ node: Node, depth: Int) throws(ManglingError) {
        try mangleChildNode(node, at: 1, depth: depth + 1)
        try mangleChildNode(node, at: 0, depth: depth + 1)

        if node.numberOfChildren >= 3 {
            try mangleTypeList(node[safeChild: 2], depth: depth + 1)
        } else {
            append("y")
        }

        append("XZ")
    }

    // MARK: - Other Nominal Type

    private func mangleOtherNominalType(_ node: Node, depth: Int) throws(ManglingError) {
        try mangleAnyNominalType(node, depth: depth + 1)
    }

    // MARK: - Closures

    private func mangleExplicitClosure(_ node: Node, depth: Int) throws(ManglingError) {
        try mangleChildNode(node, at: 0, depth: depth + 1) // context
        try mangleChildNode(node, at: 2, depth: depth + 1) // type
        append("fU")
        try mangleChildNode(node, at: 1, depth: depth + 1)
    }

    private func mangleImplicitClosure(_ node: Node, depth: Int) throws(ManglingError) {
        try mangleChildNode(node, at: 0, depth: depth + 1) // context
        try mangleChildNode(node, at: 2, depth: depth + 1) // type
        append("fu")
        try mangleChildNode(node, at: 1, depth: depth + 1) // index
    }

    // MARK: - Label List and Tuple Element Name

    private func mangleLabelList(_ node: Node, depth: Int) throws(ManglingError) {
        // LabelList contains identifiers or empty placeholders
        // Labels are mangled sequentially WITHOUT separators (unlike TypeList)
        if node.children.isEmpty {
            append("y")
        } else {
            try mangleChildNodes(node, depth: depth + 1)
        }
    }

    private func mangleTupleElementName(_ node: Node, depth: Int) throws(ManglingError) {
        try mangleIdentifier(node, depth: depth + 1)
    }

    // MARK: - Special Types

    private func mangleDynamicSelf(_ node: Node, depth: Int) throws(ManglingError) {
        try mangleSingleChildNode(node, depth: depth)
        append("XD")
    }

    private func mangleErrorType(_ node: Node, depth: Int) throws(ManglingError) {
        append("Xe")
    }

    // MARK: - List Markers

    private func mangleEmptyList(_ node: Node, depth: Int) throws(ManglingError) {
        append("y")
    }

    private func mangleFirstElementMarker(_ node: Node, depth: Int) throws(ManglingError) {
        append("_")
    }

    private func mangleVariadicMarker(_ node: Node, depth: Int) throws(ManglingError) {
        append("d")
    }

    // MARK: - Field and Enum

    private func mangleFieldOffset(_ node: Node, depth: Int) throws(ManglingError) {
        try mangleChildNode(node, at: 1, depth: depth + 1) // variable
        append("Wv")
        try mangleChildNode(node, at: 0, depth: depth + 1) // directness
    }

    private func mangleEnumCase(_ node: Node, depth: Int) throws(ManglingError) {
        try mangleSingleChildNode(node, depth: depth + 1) // enum case
        append("WC")
    }

    // MARK: - Generic Support (High Priority)

    /// Mangle any nominal type (generic or not)
    private func mangleAnyNominalType(_ node: Node, depth: Int) throws(ManglingError) {
        if depth > Self.maxDepth {
            throw .tooComplex(node)
        }

        // Check if this is a specialized type
        if isSpecialized(node) {
            // Try substitution first
            let substResult = trySubstitution(node)
            if substResult.found {
                return
            }

            // Get unspecialized version
            guard let unboundType = getUnspecialized(node) else {
                throw .invalidNodeStructure(node, message: "Cannot get unspecialized type")
            }

            // Mangle unbound type
            try mangleAnyNominalType(unboundType, depth: depth + 1)

            // Mangle generic arguments
            var separator: Character = "y"
            try mangleGenericArgs(node, separator: &separator, depth: depth + 1)

            // Handle retroactive conformances if present
            if node.numberOfChildren == 3 {
                let listNode = try node[safeChild: 2]
                for child in listNode.children {
                    try mangle(child, depth: depth + 1)
                }
            }

            append("G")

            // Add to substitutions (use entry from trySubstitution)
            addSubstitution(substResult.entry)
            return
        }

        // Handle non-specialized nominal types
        switch node.kind {
        case .structure:
            try mangleAnyGenericType(node, typeOp: "V", depth: depth)
        case .enum:
            try mangleAnyGenericType(node, typeOp: "O", depth: depth)
        case .class:
            try mangleAnyGenericType(node, typeOp: "C", depth: depth)
        case .otherNominalType:
            try mangleAnyGenericType(node, typeOp: "XY", depth: depth)
        case .typeAlias:
            try mangleAnyGenericType(node, typeOp: "a", depth: depth)
        case .typeSymbolicReference:
            try mangleTypeSymbolicReference(node, depth: depth)
        default:
            throw .invalidNodeStructure(node, message: "Not a nominal type")
        }
    }

    /// Mangle any generic type with a given type operator
    private func mangleAnyGenericType(_ node: Node, typeOp: String, depth: Int) throws(ManglingError) {
        // Try substitution first
        let substResult = trySubstitution(node)
        if substResult.found {
            return
        }

        // Mangle child nodes
        try mangleChildNodes(node, depth: depth + 1)

        // Append type operator
        append(typeOp)

        // Add to substitutions (use entry from trySubstitution)
        addSubstitution(substResult.entry)
    }

    // MARK: - Constructor Support

    /// Mangle any constructor (constructor, allocator, etc.)
    private func mangleAnyConstructor(_ node: Node, kindOp: Character, depth: Int) throws(ManglingError) {
        try mangleChildNodes(node, depth: depth + 1)
        append("f")
        append(kindOp)
    }

    // MARK: - Bound Generic Function

    private func mangleBoundGenericFunction(_ node: Node, depth: Int) throws(ManglingError) {
        // Try substitution first
        let substResult = trySubstitution(node)
        if substResult.found {
            return
        }

        // Get unspecialized function
        guard let unboundFunction = getUnspecialized(node) else {
            throw .invalidNodeStructure(node, message: "Cannot get unspecialized function")
        }

        // Mangle the unbound function
        try mangleFunction(unboundFunction, depth: depth + 1)

        // Mangle generic arguments
        var separator: Character = "y"
        try mangleGenericArgs(node, separator: &separator, depth: depth + 1)

        append("G")

        // Add to substitutions (use entry from trySubstitution)
        addSubstitution(substResult.entry)
    }

    private func mangleBoundGenericOtherNominalType(_ node: Node, depth: Int) throws(ManglingError) {
        try mangleAnyNominalType(node, depth: depth + 1)
    }

    // MARK: - Associated Types

    private func mangleAssociatedType(_ node: Node, depth: Int) throws(ManglingError) {
        // Associated types are not directly mangleable
        throw .unsupportedNodeKind(node)
    }

    private func mangleAssociatedTypeRef(_ node: Node, depth: Int) throws(ManglingError) {
        // Try substitution first
        let substResult = trySubstitution(node)
        if substResult.found {
            return
        }

        try mangleChildNodes(node, depth: depth + 1)

        append("Qa")

        // Add to substitutions (use entry from trySubstitution)
        addSubstitution(substResult.entry)
    }

    private func mangleAssociatedTypeDescriptor(_ node: Node, depth: Int) throws(ManglingError) {
        try mangleChildNodes(node, depth: depth + 1)
        append("Tl")
    }

    private func mangleAssociatedConformanceDescriptor(_ node: Node, depth: Int) throws(ManglingError) {
        try mangle(node[safeChild: 0], depth: depth + 1)
        try mangle(node[safeChild: 1], depth: depth + 1)
        try manglePureProtocol(node[safeChild: 2], depth: depth + 1)
        append("Tn")
    }

    private func mangleAssociatedTypeMetadataAccessor(_ node: Node, depth: Int) throws(ManglingError) {
        try mangleChildNodes(node, depth: depth + 1)
        append("Wt")
    }

    private func mangleAssocTypePath(_ node: Node, depth: Int) throws(ManglingError) {
        // Mangle path to associated type
        var firstElem = true
        for child in node.children {
            try mangle(child, depth: depth + 1)
            mangleListSeparator(&firstElem)
        }
    }

    private func mangleAssociatedTypeGenericParamRef(_ node: Node, depth: Int) throws(ManglingError) {
        try mangleType(node[safeChild: 0], depth: depth + 1)

        try mangleAssocTypePath(node[safeChild: 1], depth: depth + 1)

        append("MXA")
    }

    // MARK: - Protocol Conformance

    private func mangleProtocolConformance(_ node: Node, depth: Int) throws(ManglingError) {
        var ty = try getChildOfType(node[safeChild: 0])

        var genSig: Node? = nil

        if ty.kind == .dependentGenericType {
            genSig = try ty.firstChild
            ty = try ty[safeChild: 1]
        }

        // Mangle type
        try mangle(ty, depth: depth + 1)

        // Mangle module if present (4th child)
        if node.numberOfChildren == 4 {
            try mangleChildNode(node, at: 3, depth: depth + 1)
        }

        // Mangle protocol
        try manglePureProtocol(node[safeChild: 1], depth: depth + 1)

        // Mangle conformance reference
        try mangleChildNode(node, at: 2, depth: depth + 1)

        // Mangle generic signature if present
        if let genSig = genSig {
            try mangle(genSig, depth: depth + 1)
        }
    }

    private func mangleConcreteProtocolConformance(_ node: Node, depth: Int) throws(ManglingError) {
        try mangleType(node[safeChild: 0], depth: depth + 1)
        try mangle(node[safeChild: 1], depth: depth + 1)
        if node.numberOfChildren > 2 {
            try mangleAnyProtocolConformanceList(node[safeChild: 2], depth: depth + 1)
        } else {
            append("y")
        }
        append("HC")
    }

    private func mangleProtocolConformanceDescriptor(_ node: Node, depth: Int) throws(ManglingError) {
        try mangleProtocolConformance(node[safeChild: 0], depth: depth + 1)
        append("Mc")
    }

    private func mangleAnyProtocolConformance(_ node: Node, depth: Int) throws(ManglingError) {
        // Dispatch to specific conformance handler
        switch node.kind {
        case .concreteProtocolConformance:
            try mangleConcreteProtocolConformance(node, depth: depth + 1)
        case .packProtocolConformance:
            try manglePackProtocolConformance(node, depth: depth + 1)
        case .dependentProtocolConformanceRoot:
            try mangleDependentProtocolConformanceRoot(node, depth: depth + 1)
        case .dependentProtocolConformanceInherited:
            try mangleDependentProtocolConformanceInherited(node, depth: depth + 1)
        case .dependentProtocolConformanceAssociated:
            try mangleDependentProtocolConformanceAssociated(node, depth: depth + 1)
        case .dependentProtocolConformanceOpaque:
            try mangleDependentProtocolConformanceOpaque(node, depth: depth + 1)
        default: break
        }
    }

    /// Mangle a pure protocol (without wrapper)
    private func manglePureProtocol(_ node: Node, depth: Int) throws(ManglingError) {
        let proto = skipType(node)

        // Try standard substitution
        if mangleStandardSubstitution(proto) {
            return
        }

        try mangleChildNodes(proto, depth: depth + 1)
    }

    private func getChildOfType(_ node: Node) -> Node {
        assert(node.kind == .type)
        assert(node.children.count == 1)
        return node.children[0]
    }

    // MARK: - Metadata Descriptors

    private func mangleNominalTypeDescriptor(_ node: Node, depth: Int) throws(ManglingError) {
        try mangleSingleChildNode(node, depth: depth + 1)
        append("Mn")
    }

    private func mangleNominalTypeDescriptorRecord(_ node: Node, depth: Int) throws(ManglingError) {
        try mangleSingleChildNode(node, depth: depth + 1)
        append("Hn")
    }

    private func mangleProtocolDescriptor(_ node: Node, depth: Int) throws(ManglingError) {
        try manglePureProtocol(node[safeChild: 0], depth: depth + 1)
        append("Mp")
    }

    private func mangleProtocolDescriptorRecord(_ node: Node, depth: Int) throws(ManglingError) {
        try manglePureProtocol(node[safeChild: 0], depth: depth + 1)
        append("Hr")
    }

    private func mangleTypeMetadataCompletionFunction(_ node: Node, depth: Int) throws(ManglingError) {
        try mangleSingleChildNode(node, depth: depth + 1)
        append("Mr")
    }

    private func mangleTypeMetadataDemanglingCache(_ node: Node, depth: Int) throws(ManglingError) {
        try mangleSingleChildNode(node, depth: depth + 1)
        append("MD")
    }

    private func mangleTypeMetadataInstantiationCache(_ node: Node, depth: Int) throws(ManglingError) {
        try mangleSingleChildNode(node, depth: depth + 1)
        append("MI")
    }

    private func mangleTypeMetadataLazyCache(_ node: Node, depth: Int) throws(ManglingError) {
        try mangleChildNodes(node, depth: depth + 1)
        append("ML")
    }

    private func mangleClassMetadataBaseOffset(_ node: Node, depth: Int) throws(ManglingError) {
        try mangleSingleChildNode(node, depth: depth + 1)
        append("Mo")
    }

    private func mangleGenericTypeMetadataPattern(_ node: Node, depth: Int) throws(ManglingError) {
        try mangleSingleChildNode(node, depth: depth + 1)
        append("MP")
    }

    private func mangleProtocolWitnessTablePattern(_ node: Node, depth: Int) throws(ManglingError) {
        try mangleSingleChildNode(node, depth: depth + 1)
        append("Wp")
    }

    private func mangleGenericProtocolWitnessTable(_ node: Node, depth: Int) throws(ManglingError) {
        try mangleSingleChildNode(node, depth: depth + 1)
        append("WG")
    }

    private func mangleGenericProtocolWitnessTableInstantiationFunction(_ node: Node, depth: Int) throws(ManglingError) {
        try mangleSingleChildNode(node, depth: depth + 1)
        append("WI")
    }

    private func mangleResilientProtocolWitnessTable(_ node: Node, depth: Int) throws(ManglingError) {
        try mangleSingleChildNode(node, depth: depth + 1)
        append("Wr")
    }

    private func mangleProtocolSelfConformanceWitness(_ node: Node, depth: Int) throws(ManglingError) {
        try mangleSingleChildNode(node, depth: depth + 1)
        append("TS")
    }

    private func mangleBaseWitnessTableAccessor(_ node: Node, depth: Int) throws(ManglingError) {
        try mangleChildNodes(node, depth: depth + 1)
        append("Wb")
    }

    private func mangleBaseConformanceDescriptor(_ node: Node, depth: Int) throws(ManglingError) {
        try mangle(node[safeChild: 0], depth: depth + 1)
        try manglePureProtocol(node[safeChild: 1], depth: depth + 1)
        append("Tb")
    }

    private func mangleDependentAssociatedConformance(_ node: Node, depth: Int) throws(ManglingError) {
        try mangleType(node[safeChild: 0], depth: depth + 1)
        try manglePureProtocol(node[safeChild: 1], depth: depth + 1)
    }

    private func mangleRetroactiveConformance(_ node: Node, depth: Int) throws(ManglingError) {
        try mangleAnyProtocolConformance(node[safeChild: 1], depth: depth + 1)
        append("g")
        if let index = try node[safeChild: 0].index {
            mangleIndex(index)
        }
    }

    // MARK: - Outlined Operations (High Priority)

    private func mangleOutlinedCopy(_ node: Node, depth: Int) throws(ManglingError) {
        try mangleChildNodes(node, depth: depth + 1)
        append("WOy")
    }

    private func mangleOutlinedConsume(_ node: Node, depth: Int) throws(ManglingError) {
        try mangleChildNodes(node, depth: depth + 1)
        append("WOe")
    }

    private func mangleOutlinedRetain(_ node: Node, depth: Int) throws(ManglingError) {
        try mangleChildNodes(node, depth: depth + 1)
        append("WOr")
    }

    private func mangleOutlinedRelease(_ node: Node, depth: Int) throws(ManglingError) {
        try mangleChildNodes(node, depth: depth + 1)
        append("WOs")
    }

    private func mangleOutlinedDestroy(_ node: Node, depth: Int) throws(ManglingError) {
        try mangleChildNodes(node, depth: depth + 1)
        append("WOh")
    }

    private func mangleOutlinedInitializeWithTake(_ node: Node, depth: Int) throws(ManglingError) {
        try mangleChildNodes(node, depth: depth + 1)
        append("WOb")
    }

    private func mangleOutlinedInitializeWithCopy(_ node: Node, depth: Int) throws(ManglingError) {
        try mangleChildNodes(node, depth: depth + 1)
        append("WOc")
    }

    private func mangleOutlinedAssignWithTake(_ node: Node, depth: Int) throws(ManglingError) {
        try mangleChildNodes(node, depth: depth + 1)
        append("WOd")
    }

    private func mangleOutlinedAssignWithCopy(_ node: Node, depth: Int) throws(ManglingError) {
        try mangleChildNodes(node, depth: depth + 1)
        append("WOf")
    }

    private func mangleOutlinedVariable(_ node: Node, depth: Int) throws(ManglingError) {
        append("Tv")
        if let index = node.index {
            mangleIndex(index)
        }
    }

    private func mangleOutlinedEnumGetTag(_ node: Node, depth: Int) throws(ManglingError) {
        try mangleChildNodes(node, depth: depth + 1)
        append("WOg")
    }

    private func mangleOutlinedEnumProjectDataForLoad(_ node: Node, depth: Int) throws(ManglingError) {
        if node.numberOfChildren == 2 {
            let ty = try node[safeChild: 0]
            try mangle(ty, depth: depth + 1)
            append("WOj")
            if let index = try node[safeChild: 1].index {
                mangleIndex(index)
            }

        } else {
            let ty = try node[safeChild: 0]
            try mangle(ty, depth: depth + 1)
            let sig = try node[safeChild: 1]
            try mangle(sig, depth: depth + 1)
            append("WOj")
            if let index = try node[safeChild: 2].index {
                mangleIndex(index)
            }
        }
    }

    private func mangleOutlinedEnumTagStore(_ node: Node, depth: Int) throws(ManglingError) {
        if node.numberOfChildren == 2 {
            let ty = try node[safeChild: 0]
            try mangle(ty, depth: depth + 1)
            append("WOi")
            if let index = try node[safeChild: 1].index {
                mangleIndex(index)
            }

        } else {
            let ty = try node[safeChild: 0]
            try mangle(ty, depth: depth + 1)
            let sig = try node[safeChild: 1]
            try mangle(sig, depth: depth + 1)
            append("WOi")
            if let index = try node[safeChild: 2].index {
                mangleIndex(index)
            }
        }
    }

    /// No ValueWitness variants
    private func mangleOutlinedDestroyNoValueWitness(_ node: Node, depth: Int) throws(ManglingError) {
        try mangleChildNodes(node, depth: depth + 1)
        append("WOH")
    }

    private func mangleOutlinedInitializeWithCopyNoValueWitness(_ node: Node, depth: Int) throws(ManglingError) {
        try mangleChildNodes(node, depth: depth + 1)
        append("WOC")
    }

    private func mangleOutlinedAssignWithTakeNoValueWitness(_ node: Node, depth: Int) throws(ManglingError) {
        try mangleChildNodes(node, depth: depth + 1)
        append("WOD")
    }

    private func mangleOutlinedAssignWithCopyNoValueWitness(_ node: Node, depth: Int) throws(ManglingError) {
        try mangleChildNodes(node, depth: depth + 1)
        append("WOF")
    }

    private func mangleOutlinedBridgedMethod(_ node: Node, depth: Int) throws(ManglingError) {
        append("Te")
        append(node.text ?? "")
        append("_")
    }

    private func mangleOutlinedReadOnlyObject(_ node: Node, depth: Int) throws(ManglingError) {
        append("Tv")
        if let index = node.index {
            mangleIndex(index)
        }
        append("r")
    }

    // MARK: - Pack Support (High Priority)

    private func manglePack(_ node: Node, depth: Int) throws(ManglingError) {
        try mangleTypeList(node, depth: depth + 1)
        append("QP")
    }

    private func manglePackElement(_ node: Node, depth: Int) throws(ManglingError) {
        try mangleChildNode(node, at: 0, depth: depth + 1)
        append("Qe")
        try mangleChildNode(node, at: 1, depth: depth + 1)
    }

    private func manglePackElementLevel(_ node: Node, depth: Int) throws(ManglingError) {
        // PackElementLevel: just mangle the index
        if let index = node.index {
            mangleIndex(index)
        }
    }

    private func manglePackExpansion(_ node: Node, depth: Int) throws(ManglingError) {
        try mangleChildNodes(node, depth: depth + 1)
        append("Qp")
    }

    private func manglePackProtocolConformance(_ node: Node, depth: Int) throws(ManglingError) {
        try mangleAnyProtocolConformanceList(node[safeChild: 0], depth: depth + 1)
        append("HX")
    }

    private func mangleSILPackDirect(_ node: Node, depth: Int) throws(ManglingError) {
        try mangleTypeList(node, depth: depth + 1)
        append("Qsd")
    }

    private func mangleSILPackIndirect(_ node: Node, depth: Int) throws(ManglingError) {
        try mangleTypeList(node, depth: depth + 1)
        append("QSi")
    }

    // MARK: - Generic Specialization

    private func mangleGenericSpecialization(_ node: Node, depth: Int) throws(ManglingError) {
        try mangleGenericSpecializationNode(node, specKind: "g", depth: depth)
    }

    private func mangleGenericPartialSpecialization(_ node: Node, depth: Int) throws(ManglingError) {
        for child in node.children {
            if child.kind == .genericSpecializationParam {
                try mangleChildNode(child, at: 0, depth: depth + 1)
                break
            }
        }
        append(node.kind == .genericPartialSpecializationNotReAbstracted ? "TP" : "Tp")
        for child in node.children {
            if child.kind != .genericSpecializationParam {
                try mangle(child, depth: depth + 1)
            }
        }
    }

    private func mangleGenericSpecializationNode(_ node: Node, specKind: String, depth: Int) throws(ManglingError) {
        var firstParam = true
        for child in node.children {
            if child.isKind(of: .genericSpecializationParam) {
                try mangleChildNode(child, at: 0, depth: depth + 1)
                mangleListSeparator(&firstParam)
            }
        }

        append("T")

        for child in node.children {
            if child.isKind(of: .droppedArgument) {
                try mangle(child, depth: depth + 1)
            }
        }

        append(specKind)

        for child in node.children {
            if child.kind != .genericSpecializationParam, child.kind != .droppedArgument {
                try mangle(child, depth: depth + 1)
            }
        }
    }

    private func mangleGenericSpecializationParam(_ node: Node, depth: Int) throws(ManglingError) {
        throw .unsupportedNodeKind(node)
    }

    private func mangleFunctionSignatureSpecialization(_ node: Node, depth: Int) throws(ManglingError) {
        for param in node.children {
            if param.kind == .functionSignatureSpecializationParam, param.numberOfChildren > 0, let rawValue = try param[safeChild: 0].index, let kind = FunctionSigSpecializationParamKind(rawValue: rawValue) {
                switch kind {
                case .constantPropFunction,
                     .constantPropGlobal:
                    try mangleIdentifier(param[safeChild: 1], depth: depth + 1)
                case .constantPropString:
                    var textNd = try param[safeChild: 2]
                    let text = textNd.text
                    if let text, !text.isEmpty, Remangler.isDigit(text.first!) || text.first == "_" {
                        var buffer = "_"
                        buffer.append(text)
                        buffer.append(text.count.description)
                        textNd = Node(kind: .identifier, contents: .text(buffer))
                    }
                    try mangleIdentifier(textNd, depth: depth + 1)
                case .closureProp,
                     .constantPropKeyPath:
                    try mangleIdentifier(param[safeChild: 1], depth: depth + 1)
                    var i = 2
                    let e = param.numberOfChildren
                    while i != e {
                        try mangleType(param[safeChild: i], depth: depth + 1)
                        i += 1
                    }
                default:
                    break
                }
            }
        }
        append("Tf")
        var returnValMangled = false
        for child in node.children {
            if child.kind == .functionSignatureSpecializationReturn {
                append("_")
                returnValMangled = true
            }
            try mangle(child, depth: depth + 1)
            if child.kind == .specializationPassID, let index = node.index {
                append(index)
            }
        }
        if !returnValMangled {
            append("_n")
        }
    }

    private func mangleGenericTypeParamDecl(_ node: Node, depth: Int) throws(ManglingError) {
        try mangleChildNodes(node, depth: depth + 1)
        append("fp")
    }

    private func mangleDependentGenericParamCount(_ node: Node, depth: Int) throws(ManglingError) {
        throw .unsupportedNodeKind(node)
    }

    private func mangleDependentGenericParamPackMarker(_ node: Node, depth: Int) throws(ManglingError) {
        // DependentGenericParamPackMarker: output "Rv" then mangle the param index
        guard node.numberOfChildren == 1,
              try node[safeChild: 0].kind == .type else {
            throw .invalidNodeStructure(node, message: "DependentGenericParamPackMarker needs Type child")
        }
        append("Rv")
        try mangleDependentGenericParamIndex(node[safeChild: 0][safeChild: 0])
    }

    private func mangleDependentGenericParamValueMarker(_ node: Node, depth: Int) throws(ManglingError) {
        assert(node.numberOfChildren == 2)
        assert(node.children[0].children[0].kind == .dependentGenericParamType)
        assert(node.children[1].kind == .type)
        try mangleType(node[safeChild: 1], depth: depth + 1)
        append("RV")
        try mangleDependentGenericParamIndex(node[safeChild: 0][safeChild: 0])
    }

    // MARK: - Impl Function Type (High Priority)

    private func mangleImplFunctionType(_ node: Node, depth: Int) throws(ManglingError) {
        var pseudoGeneric = ""
        var genSig: Node? = nil
        var patternSubs: Node? = nil
        var invocationSubs: Node? = nil

        // First pass: find special children and mangle parameter/result types
        for child in node.children {
            switch child.kind {
            case .implParameter,
                 .implResult,
                 .implYield,
                 .implErrorResult:
                // Mangle type (last child of parameter/result node)
                guard child.numberOfChildren >= 2 else {
                    throw .invalidNodeStructure(child, message: "Impl parameter/result needs at least 2 children")
                }
                try mangle(child.children.last!, depth: depth + 1)

            case .dependentPseudogenericSignature:
                pseudoGeneric = "P"
                genSig = child
                fallthrough

            case .dependentGenericSignature:
                genSig = child

            case .implPatternSubstitutions:
                patternSubs = child

            case .implInvocationSubstitutions:
                invocationSubs = child

            default:
                break
            }
        }

        // Output generic signature if present
        if let genSig = genSig {
            try mangle(genSig, depth: depth + 1)
        }

        // Mangle invocation substitutions if present
        if let invocationSubs = invocationSubs {
            append("y")
            try mangleChildNodes(invocationSubs[safeChild: 0], depth: depth + 1)
            if invocationSubs.numberOfChildren >= 2 {
                try mangleRetroactiveConformance(invocationSubs[safeChild: 1], depth: depth + 1)
            }
        }

        // Mangle pattern substitutions if present
        if let patternSubs = patternSubs {
            try mangle(patternSubs[safeChild: 0], depth: depth + 1)
            append("y")
            try mangleChildNodes(patternSubs[safeChild: 1], depth: depth + 1)
            if patternSubs.numberOfChildren >= 3 {
                let retroactiveConf = try patternSubs[safeChild: 2]
                if retroactiveConf.kind == .typeList {
                    try mangleChildNodes(retroactiveConf, depth: depth + 1)
                } else {
                    try mangleRetroactiveConformance(retroactiveConf, depth: depth + 1)
                }
            }
        }

        append("I")

        if patternSubs != nil {
            append("s")
        }
        if invocationSubs != nil {
            append("I")
        }

        append(pseudoGeneric)

        for child in node.children {
            switch child.kind {
            case .implDifferentiabilityKind:
                try append(child.character)
            case .implEscaping:
                append("e")
            case .implErasedIsolation:
                append("A")
            case .implSendingResult:
                append("T")
            case .implConvention:
                let convCh: String? = switch child.text {
                case "@callee_unowned": "y"
                case "@callee_guaranteed": "g"
                case "@callee_owned": "x"
                case "@convention(thin)": "t"
                default: nil
                }
                if let convCh {
                    append(convCh)
                } else {
                    throw .invalidImplCalleeConvention(child)
                }
            case .implFunctionConvention:
                try mangleImplFunctionConvention(child, depth: depth + 1)
            case .implCoroutineKind:
                let text: String? = switch child.text {
                case "yield_once": "A"
                case "yield_once_2": "I"
                case "yield_many": "G"
                default: nil
                }
                if let text {
                    append(text)
                } else {
                    throw .invalidImplCoroutineKind(child)
                }
            case .implFunctionAttribute:
                let text: String? = switch child.text {
                case "@Sendable": "h"
                case "@async": "H"
                default: nil
                }
                if let text {
                    append(text)
                } else {
                    throw .invalidImplFunctionAttribute(child)
                }
            case .implYield:
                append("Y")
                fallthrough
            case .implParameter:
                let text: String? = switch try child.firstChild.text {
                case "@in": "i"
                case "@inout": "l"
                case "@inout_aliasable": "b"
                case "@in_guaranteed": "n"
                case "@in_cxx": "X"
                case "@in_constant": "c"
                case "@owned": "x"
                case "@guaranteed": "g"
                case "@deallocating": "e"
                case "@unowned": "y"
                case "@pack_guaranteed": "p"
                case "@pack_owned": "v"
                case "@pack_inout": "m"
                default: nil
                }
                if let text {
                    append(text)
                } else {
                    throw .invalidImplParameterConvention(child)
                }
                for index in 1 ..< child.numberOfChildren - 1 {
                    let grandChild = try child[safeChild: index]
                    switch grandChild.kind {
                    case .implParameterResultDifferentiability:
                        try mangleImplParameterResultDifferentiability(grandChild, depth: depth + 1)
                    case .implParameterSending:
                        try mangleImplParameterSending(grandChild, depth: depth + 1)
                    case .implParameterIsolated:
                        try mangleImplParameterIsolated(grandChild, depth: depth + 1)
                    case .implParameterImplicitLeading:
                        try mangleImplParameterImplicitLeading(grandChild, depth: depth + 1)
                    default:
                        throw .invalidImplParameterAttr(grandChild)
                    }
                }
            case .implErrorResult:
                append("z")
                fallthrough
            case .implResult:
                let text: String? = switch try child.firstChild.text {
                case "@out": "r"
                case "@owned": "o"
                case "@unowned": "d"
                case "@unowned_inner_pointer": "u"
                case "@autoreleased": "a"
                case "@pack_out": "k"
                default: nil
                }
                if let text {
                    append(text)
                    if child.numberOfChildren == 3 {
                        try mangleImplParameterResultDifferentiability(child[safeChild: 1], depth: depth + 1)
                    } else if child.numberOfChildren == 4 {
                        try mangleImplParameterResultDifferentiability(child[safeChild: 1], depth: depth + 1)
                        try mangleImplParameterSending(child[child: 2], depth: depth + 1)
                    }
                } else {
                    throw try .invalidImplParameterConvention(child.firstChild)
                }
            default:
                break
            }
        }
        append("_")
    }

    private func mangleImplParameter(_ node: Node, depth: Int) throws(ManglingError) {
        // ImplParameter is handled inline in mangleImplFunctionType
        throw .invalidNodeStructure(node, message: "ImplParameter should be handled inline")
    }

    private func mangleImplResult(_ node: Node, depth: Int) throws(ManglingError) {
        // ImplResult is handled inline in mangleImplFunctionType
        throw .invalidNodeStructure(node, message: "ImplResult should be handled inline")
    }

    private func mangleImplYield(_ node: Node, depth: Int) throws(ManglingError) {
        throw .unsupportedNodeKind(node)
    }

    private func mangleImplErrorResult(_ node: Node, depth: Int) throws(ManglingError) {
        throw .unsupportedNodeKind(node)
    }

    private func mangleImplConvention(_ node: Node, depth: Int) throws(ManglingError) {
        let convCh: String? = switch node.text {
        case "@callee_unowned": "y"
        case "@callee_guaranteed": "g"
        case "@callee_owned": "x"
        default: nil
        }
        if let convCh {
            append(convCh)
        } else {
            throw .invalidImplCalleeConvention(node)
        }
    }

    private func mangleImplFunctionConvention(_ node: Node, depth: Int) throws(ManglingError) {
        // Get text from first child if it exists
        let text = if node.numberOfChildren > 0, let text = try node.firstChild.text {
            text
        } else {
            ""
        }

        // Map function convention names
        let funcAttr: Character
        switch text {
        case "block": funcAttr = "B"
        case "c": funcAttr = "C"
        case "method": funcAttr = "M"
        case "objc_method": funcAttr = "O"
        case "closure": funcAttr = "K"
        case "witness_method": funcAttr = "W"
        default:
            throw .invalidNodeStructure(node, message: "Unknown function convention: \(text)")
        }

        // Check if we need to handle ClangType (for 'B' and 'C' conventions)
        if funcAttr == "B" || funcAttr == "C", node.numberOfChildren > 1,
           try node[safeChild: 1].kind == .clangType {
            append("z")
            append(funcAttr)
            try mangleClangType(node[safeChild: 1], depth: depth + 1)
        }

        append(funcAttr)
    }

    private func mangleImplFunctionConventionName(_ node: Node, depth: Int) throws(ManglingError) {
        throw .unsupportedNodeKind(node)
    }

    private func mangleImplFunctionAttribute(_ node: Node, depth: Int) throws(ManglingError) {
        throw .unsupportedNodeKind(node)
    }

    private func mangleImplEscaping(_ node: Node, depth: Int) throws(ManglingError) {
        append("e")
    }

    private func mangleImplDifferentiabilityKind(_ node: Node, depth: Int) throws(ManglingError) {
        if let index = node.index, let scalar = UnicodeScalar(UInt32(index)) {
            append(Character(scalar))
        }
    }

    private func mangleImplCoroutineKind(_ node: Node, depth: Int) throws(ManglingError) {
        throw .unsupportedNodeKind(node)
    }

    private func mangleImplParameterIsolated(_ node: Node, depth: Int) throws(ManglingError) {
        assert(node.text != nil)
        let diffChar: String? = switch node.text {
        case "isolated": "I"
        default: nil
        }
        if let diffChar {
            append(diffChar)
        } else {
            throw .invalidImplParameterAttr(node)
        }
    }

    private func mangleImplParameterSending(_ node: Node, depth: Int) throws(ManglingError) {
        assert(node.text != nil)
        let diffChar: String? = switch node.text {
        case "sending": "T"
        default: nil
        }
        if let diffChar {
            append(diffChar)
        } else {
            throw .invalidImplParameterAttr(node)
        }
    }

    private func mangleImplParameterImplicitLeading(_ node: Node, depth: Int) throws(ManglingError) {
        assert(node.text != nil)
        let diffChar: String? = switch node.text {
        case "sil_implicit_leading_param": "L"
        default: nil
        }
        if let diffChar {
            append(diffChar)
        } else {
            throw .invalidImplParameterAttr(node)
        }
    }

    private func mangleImplSendingResult(_ node: Node, depth: Int) throws(ManglingError) {
        append("T")
        try mangleChildNodes(node, depth: depth + 1)
    }

    private func mangleImplPatternSubstitutions(_ node: Node, depth: Int) throws(ManglingError) {
        throw .unsupportedNodeKind(node)
    }

    private func mangleImplInvocationSubstitutions(_ node: Node, depth: Int) throws(ManglingError) {
        throw .unsupportedNodeKind(node)
    }

    // MARK: - Descriptor/Record Types (20+ methods)

    private func mangleAccessibleFunctionRecord(_ node: Node, depth: Int) throws(ManglingError) {
        append("HF")
    }

    private func mangleAnonymousDescriptor(_ node: Node, depth: Int) throws(ManglingError) {
        try mangle(node[safeChild: 0], depth: depth + 1)

        // Check if there's an identifier child
        if node.numberOfChildren == 1 {
            append("MXX")
        } else {
            try mangleIdentifier(node[safeChild: 1], depth: depth + 1)
            append("MXY")
        }
    }

    private func mangleExtensionDescriptor(_ node: Node, depth: Int) throws(ManglingError) {
        try mangle(node[safeChild: 0], depth: depth + 1)
        append("MXE")
    }

    private func mangleMethodDescriptor(_ node: Node, depth: Int) throws(ManglingError) {
        try mangleSingleChildNode(node, depth: depth + 1)
        append("Tq")
    }

    private func mangleModuleDescriptor(_ node: Node, depth: Int) throws(ManglingError) {
        try mangle(node[safeChild: 0], depth: depth + 1)
        append("MXM")
    }

    private func manglePropertyDescriptor(_ node: Node, depth: Int) throws(ManglingError) {
        try mangleSingleChildNode(node, depth: depth + 1)
        append("MV")
    }

    private func mangleProtocolConformanceDescriptorRecord(_ node: Node, depth: Int) throws(ManglingError) {
        try mangleProtocolConformance(node[safeChild: 0], depth: depth + 1)

        append("Hc")
    }

    private func mangleProtocolRequirementsBaseDescriptor(_ node: Node, depth: Int) throws(ManglingError) {
        try manglePureProtocol(node.firstChild, depth: depth + 1)
        append("TL")
    }

    private func mangleProtocolSelfConformanceDescriptor(_ node: Node, depth: Int) throws(ManglingError) {
        try manglePureProtocol(node[safeChild: 0], depth: depth + 1)
        append("MS")
    }

    private func mangleProtocolSelfConformanceWitnessTable(_ node: Node, depth: Int) throws(ManglingError) {
        try manglePureProtocol(node[safeChild: 0], depth: depth + 1)
        append("WS")
    }

    private func mangleProtocolSymbolicReference(_ node: Node, depth: Int) throws(ManglingError) {
        // Symbolic reference - requires resolver
        throw .unsupportedNodeKind(node)
    }

    private func mangleTypeSymbolicReference(_ node: Node, depth: Int) throws(ManglingError) {
        // Symbolic reference - requires resolver
        throw .unsupportedNodeKind(node)
    }

    private func mangleObjectiveCProtocolSymbolicReference(_ node: Node, depth: Int) throws(ManglingError) {
        // Symbolic reference - requires resolver
        throw .unsupportedNodeKind(node)
    }

    // MARK: - Opaque Types (10 methods)

    private func mangleOpaqueType(_ node: Node, depth: Int) throws(ManglingError) {
        // Try substitution first
        let substResult = trySubstitution(node)
        if substResult.found {
            return
        }

        guard node.children.count >= 3 else {
            throw .invalidNodeStructure(node, message: "OpaqueType needs at least 3 children")
        }

        // Mangle first child (descriptor)
        try mangle(node[safeChild: 0], depth: depth + 1)

        // Mangle bound generics (child 2) with separators
        let boundGenerics = try node[safeChild: 2]
        for (i, child) in boundGenerics.children.enumerated() {
            append(i == 0 ? "y" : "_")
            try mangleChildNodes(child, depth: depth + 1)
        }

        // Mangle retroactive conformances if present (child 3)
        if node.children.count >= 4 {
            let retroactiveConformances = try node[safeChild: 3]
            for child in retroactiveConformances.children {
                try mangle(child, depth: depth + 1)
            }
        }

        append("Qo")

        // Mangle index from second child
        if let index = try node[safeChild: 1].index {
            mangleIndex(index)
        }

        // Add to substitutions (use entry from trySubstitution)
        addSubstitution(substResult.entry)
    }

    private func mangleOpaqueReturnType(_ node: Node, depth: Int) throws(ManglingError) {
        // Check if first child is OpaqueReturnTypeIndex
        if node.numberOfChildren > 0, try node.firstChild.kind == .opaqueReturnTypeIndex {
            // Has index - output "QR" followed by index
            append("QR")
            if let index = try node.firstChild.index {
                mangleIndex(index)
            }
        } else {
            // No index or no children - output "Qr"
            append("Qr")
        }
    }

    private func mangleOpaqueReturnTypeOf(_ node: Node, depth: Int) throws(ManglingError) {
        try mangle(node[safeChild: 0], depth: depth + 1)
        append("QO")
    }

    private func mangleOpaqueReturnTypeIndex(_ node: Node, depth: Int) throws(ManglingError) {
        throw .badNodeKind(node)
    }

    private func mangleOpaqueReturnTypeParent(_ node: Node, depth: Int) throws(ManglingError) {
        throw .badNodeKind(node)
    }

    private func mangleOpaqueTypeDescriptor(_ node: Node, depth: Int) throws(ManglingError) {
        try mangleSingleChildNode(node, depth: depth + 1)
        append("MQ")
    }

    private func mangleOpaqueTypeDescriptorAccessor(_ node: Node, depth: Int) throws(ManglingError) {
        try mangleSingleChildNode(node, depth: depth + 1)
        append("Mg")
    }

    private func mangleOpaqueTypeDescriptorAccessorImpl(_ node: Node, depth: Int) throws(ManglingError) {
        try mangleSingleChildNode(node, depth: depth + 1)
        append("Mh")
    }

    private func mangleOpaqueTypeDescriptorAccessorKey(_ node: Node, depth: Int) throws(ManglingError) {
        try mangleSingleChildNode(node, depth: depth + 1)
        append("Mj")
    }

    private func mangleOpaqueTypeDescriptorAccessorVar(_ node: Node, depth: Int) throws(ManglingError) {
        try mangleSingleChildNode(node, depth: depth + 1)
        append("Mk")
    }

    private func mangleOpaqueTypeDescriptorRecord(_ node: Node, depth: Int) throws(ManglingError) {
        try mangleSingleChildNode(node, depth: depth + 1)
        append("Ho")
    }

    private func mangleOpaqueTypeDescriptorSymbolicReference(_ node: Node, depth: Int) throws(ManglingError) {
        // Symbolic reference
        throw .unsupportedNodeKind(node)
    }

    // MARK: - Thunk Types (10+ methods)

    private func mangleCurryThunk(_ node: Node, depth: Int) throws(ManglingError) {
        try mangleSingleChildNode(node, depth: depth + 1)
        append("Tc")
    }

    private func mangleDispatchThunk(_ node: Node, depth: Int) throws(ManglingError) {
        try mangleSingleChildNode(node, depth: depth + 1)
        append("Tj")
    }

    private func mangleReabstractionThunk(_ node: Node, depth: Int) throws(ManglingError) {
        // IMPORTANT: Process children in REVERSE order
        try mangleChildNodesReversed(node, depth: depth + 1)
        append("Tr")
    }

    private func mangleReabstractionThunkHelper(_ node: Node, depth: Int) throws(ManglingError) {
        // IMPORTANT: Process children in REVERSE order
        try mangleChildNodesReversed(node, depth: depth + 1)
        append("TR")
    }

    private func mangleReabstractionThunkHelperWithSelf(_ node: Node, depth: Int) throws(ManglingError) {
        // IMPORTANT: Process children in REVERSE order
        try mangleChildNodesReversed(node, depth: depth + 1)
        append("Ty")
    }

    private func mangleReabstractionThunkHelperWithGlobalActor(_ node: Node, depth: Int) throws(ManglingError) {
        // This one uses NORMAL order (not reversed)
        try mangleChildNodes(node, depth: depth + 1)
        append("TU")
    }

    private func manglePartialApplyForwarder(_ node: Node, depth: Int) throws(ManglingError) {
        try mangleChildNodesReversed(node, depth: depth + 1)
        append("TA")
    }

    private func manglePartialApplyObjCForwarder(_ node: Node, depth: Int) throws(ManglingError) {
        try mangleChildNodesReversed(node, depth: depth + 1)
        append("Ta")
    }

    // MARK: - Macro Support (11 methods)

    private func mangleMacro(_ node: Node, depth: Int) throws(ManglingError) {
        try mangleChildNodes(node, depth: depth + 1)
        append("fm")
    }

    private func mangleMacroExpansionLoc(_ node: Node, depth: Int) throws(ManglingError) {
        // Mangle first two children (context)
        try mangle(node[safeChild: 0], depth: depth + 1)

        try mangle(node[safeChild: 1], depth: depth + 1)

        append("fMX")

        // Mangle line and column as indices
        if let line = try node[safeChild: 2].index {
            mangleIndex(line)
        }

        if let col = try node[safeChild: 3].index {
            mangleIndex(col)
        }
    }

    private func mangleMacroExpansionUniqueName(_ node: Node, depth: Int) throws(ManglingError) {
        try mangleChildNode(node, at: 0, depth: depth + 1)

        // Handle optional private discriminator (child 3)
        if let privateDiscriminator = try? node[safeChild: 3] {
            try mangle(privateDiscriminator, depth: depth + 1)
        }

        try mangleChildNode(node, at: 1, depth: depth + 1)

        append("fMu")

        try mangleChildNode(node, at: 2, depth: depth + 1)
    }

    private func mangleFreestandingMacroExpansion(_ node: Node, depth: Int) throws(ManglingError) {
        // Mangle first child (macro reference)
        try mangle(node[safeChild: 0], depth: depth + 1)

        // Handle optional private discriminator
        if let privateDiscriminator = try? node[safeChild: 3] {
            try mangle(privateDiscriminator, depth: depth + 1)
        }

        // Mangle macro name
        try mangleChildNode(node, at: 1, depth: depth + 1)

        append("fMf")

        // Mangle parent context
        try mangleChildNode(node, at: 2, depth: depth + 1)
    }

    private func mangleAccessorAttachedMacroExpansion(_ node: Node, depth: Int) throws(ManglingError) {
        try mangleChildNodes(node, depth: depth + 1)
        append("fMa")
    }

    private func mangleMemberAttributeAttachedMacroExpansion(_ node: Node, depth: Int) throws(ManglingError) {
        try mangleChildNodes(node, depth: depth + 1)
        append("fMA")
    }

    private func mangleMemberAttachedMacroExpansion(_ node: Node, depth: Int) throws(ManglingError) {
        try mangleChildNodes(node, depth: depth + 1)
        append("fMm")
    }

    private func manglePeerAttachedMacroExpansion(_ node: Node, depth: Int) throws(ManglingError) {
        try mangleChildNodes(node, depth: depth + 1)
        append("fMp")
    }

    private func mangleConformanceAttachedMacroExpansion(_ node: Node, depth: Int) throws(ManglingError) {
        try mangleChildNodes(node, depth: depth + 1)
        append("fMc")
    }

    private func mangleExtensionAttachedMacroExpansion(_ node: Node, depth: Int) throws(ManglingError) {
        try mangleChildNodes(node, depth: depth + 1)
        append("fMe")
    }

    private func mangleBodyAttachedMacroExpansion(_ node: Node, depth: Int) throws(ManglingError) {
        try mangleChildNodes(node, depth: depth + 1)
        append("fMb")
    }

    // MARK: - Additional Missing Node Handlers (109 methods)

    // MARK: - Simple Markers (20 methods)

    private func mangleAsyncFunctionPointer(_ node: Node, depth: Int) throws(ManglingError) {
        append("Tu")
    }

    private func mangleAsyncRemoved(_ node: Node, depth: Int) throws(ManglingError) {
        append("a")
    }

    private func mangleBackDeploymentFallback(_ node: Node, depth: Int) throws(ManglingError) {
        append("TwB")
    }

    private func mangleBackDeploymentThunk(_ node: Node, depth: Int) throws(ManglingError) {
        append("Twb")
    }

    private func mangleBuiltinTupleType(_ node: Node, depth: Int) throws(ManglingError) {
        append("BT")
    }

    private func mangleConcurrentFunctionType(_ node: Node, depth: Int) throws(ManglingError) {
        append("Yb")
    }

    private func mangleConstrainedExistentialSelf(_ node: Node, depth: Int) throws(ManglingError) {
        append("s")
    }

    private func mangleCoroFunctionPointer(_ node: Node, depth: Int) throws(ManglingError) {
        append("Twc")
    }

    private func mangleDefaultOverride(_ node: Node, depth: Int) throws(ManglingError) {
        append("Twd")
    }

    private func mangleDirectMethodReferenceAttribute(_ node: Node, depth: Int) throws(ManglingError) {
        append("Td")
    }

    private func mangleDynamicAttribute(_ node: Node, depth: Int) throws(ManglingError) {
        append("TD")
    }

    private func mangleHasSymbolQuery(_ node: Node, depth: Int) throws(ManglingError) {
        append("TwS")
    }

    private func mangleImplErasedIsolation(_ node: Node, depth: Int) throws(ManglingError) {
        append("A")
    }

    private func mangleIsSerialized(_ node: Node, depth: Int) throws(ManglingError) {
        append("q")
    }

    private func mangleIsolatedAnyFunctionType(_ node: Node, depth: Int) throws(ManglingError) {
        append("YA")
    }

    private func mangleMergedFunction(_ node: Node, depth: Int) throws(ManglingError) {
        append("Tm")
    }

    private func mangleNonIsolatedCallerFunctionType(_ node: Node, depth: Int) throws(ManglingError) {
        append("YC")
    }

    private func mangleNonObjCAttribute(_ node: Node, depth: Int) throws(ManglingError) {
        append("TO")
    }

    private func mangleObjCAttribute(_ node: Node, depth: Int) throws(ManglingError) {
        append("To")
    }

    private func mangleSendingResultFunctionType(_ node: Node, depth: Int) throws(ManglingError) {
        append("YT")
    }

    // MARK: - Child + Code (15 methods)

    private func mangleCompileTimeConst(_ node: Node, depth: Int) throws(ManglingError) {
        try mangleSingleChildNode(node, depth: depth + 1)
        append("Yt")
    }

    private func mangleConstValue(_ node: Node, depth: Int) throws(ManglingError) {
        try mangleSingleChildNode(node, depth: depth + 1)
        append("Yg")
    }

    private func mangleFullObjCResilientClassStub(_ node: Node, depth: Int) throws(ManglingError) {
        try mangleSingleChildNode(node, depth: depth + 1)
        append("Mt")
    }

    private func mangleIVarDestroyer(_ node: Node, depth: Int) throws(ManglingError) {
        try mangleSingleChildNode(node, depth: depth + 1)
        append("fE")
    }

    private func mangleIVarInitializer(_ node: Node, depth: Int) throws(ManglingError) {
        try mangleSingleChildNode(node, depth: depth + 1)
        append("fe")
    }

    private func mangleIsolated(_ node: Node, depth: Int) throws(ManglingError) {
        try mangleSingleChildNode(node, depth: depth + 1)
        append("Yi")
    }

    private func mangleMetadataInstantiationCache(_ node: Node, depth: Int) throws(ManglingError) {
        try mangleSingleChildNode(node, depth: depth + 1)
        append("MK")
    }

    private func mangleMethodLookupFunction(_ node: Node, depth: Int) throws(ManglingError) {
        try mangleSingleChildNode(node, depth: depth + 1)
        append("Mu")
    }

    private func mangleNoDerivative(_ node: Node, depth: Int) throws(ManglingError) {
        try mangleSingleChildNode(node, depth: depth + 1)
        append("Yk")
    }

    private func mangleNoncanonicalSpecializedGenericTypeMetadataCache(_ node: Node, depth: Int) throws(ManglingError) {
        try mangleSingleChildNode(node, depth: depth + 1)
        append("MJ")
    }

    private func mangleObjCMetadataUpdateFunction(_ node: Node, depth: Int) throws(ManglingError) {
        try mangleSingleChildNode(node, depth: depth + 1)
        append("MU")
    }

    private func mangleObjCResilientClassStub(_ node: Node, depth: Int) throws(ManglingError) {
        try mangleSingleChildNode(node, depth: depth + 1)
        append("Ms")
    }

    private func mangleSILBoxType(_ node: Node, depth: Int) throws(ManglingError) {
        try mangleSingleChildNode(node, depth: depth + 1)
        append("Xb")
    }

    private func mangleSILThunkIdentity(_ node: Node, depth: Int) throws(ManglingError) {
        try mangleSingleChildNode(node, depth: depth + 1)
        append("TTI")
    }

    private func mangleSending(_ node: Node, depth: Int) throws(ManglingError) {
        try mangleSingleChildNode(node, depth: depth + 1)
        append("Yu")
    }

    // MARK: - All Children + Code (9 methods)

    private func mangleBuiltinFixedArray(_ node: Node, depth: Int) throws(ManglingError) {
        try mangleChildNodes(node, depth: depth + 1)
        append("BV")
    }

    private func mangleCoroutineContinuationPrototype(_ node: Node, depth: Int) throws(ManglingError) {
        try mangleChildNodes(node, depth: depth + 1)
        append("TC")
    }

    private func mangleDeallocator(_ node: Node, depth: Int) throws(ManglingError) {
        try mangleChildNodes(node, depth: depth + 1)
        append("fD")
    }

    private func mangleGlobalActorFunctionType(_ node: Node, depth: Int) throws(ManglingError) {
        try mangleChildNodes(node, depth: depth + 1)
        append("Yc")
    }

    private func mangleGlobalVariableOnceFunction(_ node: Node, depth: Int) throws(ManglingError) {
        try mangleChildNodes(node, depth: depth + 1)
        append("WZ")
    }

    private func mangleGlobalVariableOnceToken(_ node: Node, depth: Int) throws(ManglingError) {
        try mangleChildNodes(node, depth: depth + 1)
        append("Wz")
    }

    private func mangleIsolatedDeallocator(_ node: Node, depth: Int) throws(ManglingError) {
        try mangleChildNodes(node, depth: depth + 1)
        append("fZ")
    }

    private func mangleTypedThrowsAnnotation(_ node: Node, depth: Int) throws(ManglingError) {
        try mangleChildNodes(node, depth: depth + 1)
        append("YK")
    }

    private func mangleVTableThunk(_ node: Node, depth: Int) throws(ManglingError) {
        try mangleChildNodes(node, depth: depth + 1)
        append("TV")
    }

    // MARK: - AbstractStorage Delegates (13 methods)

    private func mangleGlobalGetter(_ node: Node, depth: Int) throws(ManglingError) {
        try mangleAbstractStorage(node.firstChild, accessorCode: "G", depth: depth + 1)
    }

    private func mangleInitAccessor(_ node: Node, depth: Int) throws(ManglingError) {
        try mangleAbstractStorage(node.firstChild, accessorCode: "i", depth: depth + 1)
    }

    private func mangleMaterializeForSet(_ node: Node, depth: Int) throws(ManglingError) {
        guard node.children.count >= 1 else {
            throw .invalidNodeStructure(node, message: "MaterializeForSet needs at least 1 child")
        }
        try mangleAbstractStorage(node.firstChild, accessorCode: "m", depth: depth + 1)
    }

    private func mangleModify2Accessor(_ node: Node, depth: Int) throws(ManglingError) {
        guard node.children.count >= 1 else {
            throw .invalidNodeStructure(node, message: "Modify2Accessor needs at least 1 child")
        }
        try mangleAbstractStorage(node.firstChild, accessorCode: "x", depth: depth + 1)
    }

    private func mangleNativeOwningAddressor(_ node: Node, depth: Int) throws(ManglingError) {
        guard node.children.count >= 1 else {
            throw .invalidNodeStructure(node, message: "NativeOwningAddressor needs at least 1 child")
        }
        try mangleAbstractStorage(node.firstChild, accessorCode: "lo", depth: depth + 1)
    }

    private func mangleNativeOwningMutableAddressor(_ node: Node, depth: Int) throws(ManglingError) {
        guard node.children.count >= 1 else {
            throw .invalidNodeStructure(node, message: "NativeOwningMutableAddressor needs at least 1 child")
        }
        try mangleAbstractStorage(node.firstChild, accessorCode: "ao", depth: depth + 1)
    }

    private func mangleNativePinningAddressor(_ node: Node, depth: Int) throws(ManglingError) {
        guard node.children.count >= 1 else {
            throw .invalidNodeStructure(node, message: "NativePinningAddressor needs at least 1 child")
        }
        try mangleAbstractStorage(node.firstChild, accessorCode: "lp", depth: depth + 1)
    }

    private func mangleNativePinningMutableAddressor(_ node: Node, depth: Int) throws(ManglingError) {
        guard node.children.count >= 1 else {
            throw .invalidNodeStructure(node, message: "NativePinningMutableAddressor needs at least 1 child")
        }
        try mangleAbstractStorage(node.firstChild, accessorCode: "aP", depth: depth + 1)
    }

    private func mangleOwningAddressor(_ node: Node, depth: Int) throws(ManglingError) {
        guard node.children.count >= 1 else {
            throw .invalidNodeStructure(node, message: "OwningAddressor needs at least 1 child")
        }
        try mangleAbstractStorage(node.firstChild, accessorCode: "lO", depth: depth + 1)
    }

    private func mangleOwningMutableAddressor(_ node: Node, depth: Int) throws(ManglingError) {
        guard node.children.count >= 1 else {
            throw .invalidNodeStructure(node, message: "OwningMutableAddressor needs at least 1 child")
        }
        try mangleAbstractStorage(node.firstChild, accessorCode: "aO", depth: depth + 1)
    }

    private func mangleRead2Accessor(_ node: Node, depth: Int) throws(ManglingError) {
        guard node.children.count >= 1 else {
            throw .invalidNodeStructure(node, message: "Read2Accessor needs at least 1 child")
        }
        try mangleAbstractStorage(node.firstChild, accessorCode: "y", depth: depth + 1)
    }

    private func mangleUnsafeAddressor(_ node: Node, depth: Int) throws(ManglingError) {
        guard node.children.count >= 1 else {
            throw .invalidNodeStructure(node, message: "UnsafeAddressor needs at least 1 child")
        }
        try mangleAbstractStorage(node.firstChild, accessorCode: "lu", depth: depth + 1)
    }

    private func mangleUnsafeMutableAddressor(_ node: Node, depth: Int) throws(ManglingError) {
        guard node.children.count >= 1 else {
            throw .invalidNodeStructure(node, message: "UnsafeMutableAddressor needs at least 1 child")
        }
        try mangleAbstractStorage(node.firstChild, accessorCode: "au", depth: depth + 1)
    }

    // MARK: - Node Index Methods (8 methods)

    private func mangleAutoDiffFunctionKind(_ node: Node, depth: Int) throws(ManglingError) {
        guard let index = node.index, let scalar = UnicodeScalar(UInt32(index)) else {
            throw .invalidNodeStructure(node, message: "AutoDiffFunctionKind has no index")
        }
        append(Character(scalar))
    }

    private func mangleDependentConformanceIndex(_ node: Node, depth: Int) throws(ManglingError) {
        let indexValue = node.index != nil ? node.index! + 2 : 1
        mangleIndex(indexValue)
    }

    private func mangleDifferentiableFunctionType(_ node: Node, depth: Int) throws(ManglingError) {
        guard let index = node.index else {
            throw .invalidNodeStructure(node, message: "DifferentiableFunctionType has no index")
        }
        append("Yj")
        if let scalar = UnicodeScalar(UInt32(index)) {
            append(Character(scalar))
        }
    }

    private func mangleDirectness(_ node: Node, depth: Int) throws(ManglingError) {
        guard let index = node.index, let directness = Directness(rawValue: index) else {
            throw .invalidNodeStructure(node, message: "Directness has no index")
        }
        switch directness {
        case .direct:
            append("d")
        case .indirect:
            append("i")
        }
    }

    private func mangleDroppedArgument(_ node: Node, depth: Int) throws(ManglingError) {
        guard let index = node.index else {
            throw .invalidNodeStructure(node, message: "DroppedArgument has no index")
        }
        append("t")
        if index > 0 {
            append(index - 1)
        }
    }

    private func mangleInteger(_ node: Node, depth: Int) throws(ManglingError) {
        guard let index = node.index else {
            throw .invalidNodeStructure(node, message: "Integer has no index")
        }
        append("$")
        mangleIndex(index)
    }

    private func mangleNegativeInteger(_ node: Node, depth: Int) throws(ManglingError) {
        guard let index = node.index else {
            throw .invalidNodeStructure(node, message: "NegativeInteger has no index")
        }
        append("$n")
        mangleIndex(0 &- index)
    }

    private func mangleSpecializationPassID(_ node: Node, depth: Int) throws(ManglingError) {
        guard let index = node.index else {
            throw .invalidNodeStructure(node, message: "SpecializationPassID has no index")
        }
        append(index)
    }

    // MARK: - Node Text Methods (3 methods)

    private func mangleClangType(_ node: Node, depth: Int) throws(ManglingError) {
        guard let text = node.text else {
            throw .invalidNodeStructure(node, message: "ClangType has no text")
        }
        append(text.count.description)
        append(text)
    }

    private func mangleIndexSubset(_ node: Node, depth: Int) throws(ManglingError) {
        guard let text = node.text else {
            throw .invalidNodeStructure(node, message: "IndexSubset has no text")
        }
        append(text)
    }

    private func mangleMetatypeRepresentation(_ node: Node, depth: Int) throws(ManglingError) {
        guard let text = node.text else {
            throw .invalidNodeStructure(node, message: "MetatypeRepresentation has no text")
        }
        switch text {
        case "@thin":
            append("t")
        case "@thick":
            append("T")
        case "@objc_metatype":
            append("o")
        default:
            throw .invalidNodeStructure(node, message: "Invalid metatype representation: \(text)")
        }
    }

    // MARK: - Complex Conditional Methods (11 methods)

    private func mangleCFunctionPointer(_ node: Node, depth: Int) throws(ManglingError) {
        if node.numberOfChildren > 0, try node.firstChild.kind == .clangType {
            // Has ClangType child - use XzC
            for i in stride(from: node.numberOfChildren - 1, through: 1, by: -1) {
                try mangleChildNode(node, at: i, depth: depth + 1)
            }
            append("XzC")
            try mangleClangType(node.firstChild, depth: depth + 1)
        } else {
            // No ClangType - use XC
            try mangleChildNodesReversed(node, depth: depth + 1)
            append("XC")
        }
    }

    private func mangleDependentAssociatedTypeRef(_ node: Node, depth: Int) throws(ManglingError) {
        try mangleIdentifier(node.firstChild, depth: depth)

        if node.numberOfChildren > 1 {
            try mangleChildNode(node, at: 1, depth: depth + 1)
        }
    }

    private func mangleDependentProtocolConformanceOpaque(_ node: Node, depth: Int) throws(ManglingError) {
        try mangleAnyProtocolConformance(node[safeChild: 0], depth: depth + 1)

        try mangleType(node[safeChild: 1], depth: depth + 1)

        append("HO")
    }

    private func mangleEscapingObjCBlock(_ node: Node, depth: Int) throws(ManglingError) {
        try mangleChildNodesReversed(node, depth: depth + 1)
        append("XL")
    }

    private func mangleExtendedExistentialTypeShape(_ node: Node, depth: Int) throws(ManglingError) {
        var genSig: Node?
        var type: Node?

        if node.numberOfChildren == 1 {
            type = try node[safeChild: 0]
        } else {
            genSig = try node[safeChild: 0]
            type = try node[safeChild: 1]
        }
        if let genSig {
            try mangle(genSig, depth: depth + 1)
        }
        try mangle(type!, depth: depth + 1)

        if genSig != nil {
            append("XG")
        } else {
            append("Xg")
        }
    }

    private func mangleObjCAsyncCompletionHandlerImpl(_ node: Node, depth: Int) throws(ManglingError) {
        try mangleChildNode(node, at: 0, depth: depth + 1)

        try mangleChildNode(node, at: 1, depth: depth + 1)

        if node.numberOfChildren == 4 {
            try mangleChildNode(node, at: 3, depth: depth + 1)
        }

        append("Tz")
        try mangleChildNode(node, at: 2, depth: depth + 1)
    }

    private func mangleObjCBlock(_ node: Node, depth: Int) throws(ManglingError) {
        if node.numberOfChildren > 0, try node.firstChild.kind == .clangType {
            // Has ClangType child - use XzB
            for i in stride(from: node.numberOfChildren - 1, through: 1, by: -1) {
                try mangleChildNode(node, at: i, depth: depth + 1)
            }
            append("XzB")
            try mangleClangType(node.children[0], depth: depth + 1)
        } else {
            // No ClangType - use XB
            try mangleChildNodesReversed(node, depth: depth + 1)
            append("XB")
        }
    }

    private func mangleRelatedEntityDeclName(_ node: Node, depth: Int) throws(ManglingError) {
        try mangleChildNode(node, at: 1, depth: depth + 1)

        guard let kindText = try node.firstChild.text, kindText.count == 1 else {
            throw .invalidNodeStructure(node, message: "RelatedEntityDeclName kind must be single character")
        }

        append("L")
        append(kindText)
    }

    private func mangleSugaredDictionary(_ node: Node, depth: Int) throws(ManglingError) {
        try mangleType(node[safeChild: 0], depth: depth + 1)

        try mangleType(node[safeChild: 1], depth: depth + 1)

        append("XSD")
    }

    private func mangleConstrainedExistential(_ node: Node, depth: Int) throws(ManglingError) {
        try mangleChildNode(node, at: 0, depth: depth + 1)

        try mangleChildNode(node, at: 1, depth: depth + 1)

        append("XP")
    }

    private func mangleDependentGenericInverseConformanceRequirement(_ node: Node, depth: Int) throws(ManglingError) {
        guard node.numberOfChildren == 2 else {
            throw .invalidNodeStructure(node, message: "DependentGenericInverseConformanceRequirement needs 2 children")
        }

        let mangling = try mangleConstrainedType(node[safeChild: 0], depth: depth + 1)
        switch mangling.numMembers {
        case -1:
            append("RI")
            try mangleIndex(node[safeChild: 1].index!)
        case 0:
            append("Ri")
        case 1:
            append("Rj")
        default:
            append("RJ")
        }
        if let index = try node[safeChild: 1].index {
            mangleIndex(index)
        }
        if let paramIdx = mangling.paramIdx {
            try mangleDependentGenericParamIndex(paramIdx)
        }
    }

    // MARK: - Sugar Types (3 methods)

    private func mangleSugaredArray(_ node: Node, depth: Int) throws(ManglingError) {
        try mangleType(node[safeChild: 0], depth: depth + 1)
        append("XSa")
    }

    private func mangleSugaredOptional(_ node: Node, depth: Int) throws(ManglingError) {
        try mangleType(node[safeChild: 0], depth: depth + 1)
        append("XSq")
    }

    private func mangleSugaredParen(_ node: Node, depth: Int) throws(ManglingError) {
        try mangleType(node[safeChild: 0], depth: depth + 1)
        append("XSp")
    }

    // MARK: - Iterator/Helper Delegates (5+ methods)

    private func mangleAutoDiffFunction(_ node: Node, depth: Int) throws(ManglingError) {
        try mangleAutoDiffFunctionOrSimpleThunk(node, op: "TJ", depth: depth + 1)
    }

    private func mangleAutoDiffDerivativeVTableThunk(_ node: Node, depth: Int) throws(ManglingError) {
        try mangleAutoDiffFunctionOrSimpleThunk(node, op: "TJV", depth: depth + 1)
    }

    private func mangleAutoDiffFunctionOrSimpleThunk(_ node: Node, op: String, depth: Int) throws(ManglingError) {
        var childIt = 0

        while let next = try? node[safeChild: childIt], next.kind != .autoDiffFunctionKind {
            try mangle(next, depth: depth + 1)
            childIt += 1
        }

        append(op)

        try mangle(node[safeChild: childIt], depth: depth + 1)
        childIt += 1
        
        try mangle(node[safeChild: childIt], depth: depth + 1)
        childIt += 1
        
        append("p")
        
        try mangle(node[safeChild: childIt], depth: depth + 1)
        childIt += 1
        
        append("r")
    }

    private func mangleAutoDiffSubsetParametersThunk(_ node: Node, depth: Int) throws(ManglingError) {
        
        var childIt = 0

        while let next = try? node[safeChild: childIt], next.kind != .autoDiffFunctionKind {
            try mangle(next, depth: depth + 1)
            childIt += 1
        }

        append("TJS")

        try mangle(node[safeChild: childIt], depth: depth + 1)
        childIt += 1
        
        try mangle(node[safeChild: childIt], depth: depth + 1)
        childIt += 1
        
        append("p")
        
        try mangle(node[safeChild: childIt], depth: depth + 1)
        childIt += 1
        
        append("r")
        
        try mangle(node[safeChild: childIt], depth: depth + 1)
        childIt += 1
        
        append("P")
    }

    private func require<T>(_ param: T?) throws(ManglingError) -> T {
        if let param {
            return param
        } else {
            throw .genericError("")
        }
    }
    
    private func mangleDifferentiabilityWitness(_ node: Node, depth: Int) throws(ManglingError) {
        var childIt = 0

        while let next = try? node[safeChild: childIt], next.kind != .index {
            try mangle(next, depth: depth + 1)
            childIt += 1
        }

        if let last = node.children.last, last.kind == .dependentGenericSignature {
            try mangle(last, depth: depth + 1)
        }
        
        append("WJ")
        
        try append(node[safeChild: childIt].character)
        childIt += 1
        
        try mangle(node[safeChild: childIt], depth: depth + 1)
        childIt += 1
        
        append("p")
        
        try mangle(node[safeChild: childIt], depth: depth + 1)
        childIt += 1
        
        append("r")
    }

    private func mangleGlobalVariableOnceDeclList(_ node: Node, depth: Int) throws(ManglingError) {
        for child in node.children {
            try mangle(child, depth: depth + 1)
            append("_")
        }
    }

    private func mangleKeyPathThunkHelper(_ node: Node, op: String, depth: Int) throws(ManglingError) {
        // Mangle all non-IsSerialized children first
        for child in node.children {
            if child.kind != .isSerialized {
                try mangle(child, depth: depth + 1)
            }
        }

        append(op)

        // Then mangle all IsSerialized children
        for child in node.children {
            if child.kind == .isSerialized {
                try mangle(child, depth: depth + 1)
            }
        }
    }

    private func mangleKeyPathGetterThunkHelper(_ node: Node, depth: Int) throws(ManglingError) {
        try mangleKeyPathThunkHelper(node, op: "TK", depth: depth + 1)
    }

    private func mangleKeyPathSetterThunkHelper(_ node: Node, depth: Int) throws(ManglingError) {
        try mangleKeyPathThunkHelper(node, op: "Tk", depth: depth + 1)
    }

    private func mangleKeyPathEqualsThunkHelper(_ node: Node, depth: Int) throws(ManglingError) {
        try mangleKeyPathThunkHelper(node, op: "TH", depth: depth + 1)
    }

    private func mangleKeyPathHashThunkHelper(_ node: Node, depth: Int) throws(ManglingError) {
        try mangleKeyPathThunkHelper(node, op: "Th", depth: depth + 1)
    }

    private func mangleKeyPathAppliedMethodThunkHelper(_ node: Node, depth: Int) throws(ManglingError) {
        try mangleKeyPathThunkHelper(node, op: "TkMA", depth: depth + 1)
    }

    // MARK: - Pseudo/Delegate Methods (3 methods)

    private func mangleDependentPseudogenericSignature(_ node: Node, depth: Int) throws(ManglingError) {
        try mangleDependentGenericSignature(node, depth: depth + 1)
    }

    private func mangleInlinedGenericFunction(_ node: Node, depth: Int) throws(ManglingError) {
        try mangleGenericSpecializationNode(node, specKind: "i", depth: depth + 1)
    }

    private func mangleUniquable(_ node: Node, depth: Int) throws(ManglingError) {
        try mangle(node[safeChild: 0], depth: depth + 1)
        append("Mq")
    }

    // MARK: - Special Cases

    private func mangleDefaultArgumentInitializer(_ node: Node, depth: Int) throws(ManglingError) {
        try mangleChildNode(node, at: 0, depth: depth + 1)

        append("fA")

        try mangleChildNode(node, at: 1, depth: depth + 1)
    }

    private func mangleSymbolicExtendedExistentialType(_ node: Node, depth: Int) throws(ManglingError) {
        try mangle(node[safeChild: 0], depth: depth + 1)

        for arg in try node[safeChild: 1].children {
            try mangle(arg, depth: depth + 1)
        }

        // Mangle all children of child[2]
        if node.numberOfChildren > 2 {
            for conf in try node[safeChild: 2].children {
                try mangle(conf, depth: depth + 1)
            }
        }
    }

    private func mangleSILBoxTypeWithLayout(_ node: Node, depth: Int) throws(ManglingError) {
        let layout = try node[safeChild: 0]

        let layoutTypeList = Node(kind: .typeList)

        for layoutChild in layout.children {
            let field = layoutChild
            var fieldType = try field[safeChild: 0]
            if field.kind == .silBoxMutableField {
                let inoutNode = Node(kind: .inOut)
                try inoutNode.addChild(fieldType[safeChild: 0])
                fieldType = Node(kind: .type)
                fieldType.addChild(inoutNode)
            }

            layoutTypeList.addChild(fieldType)
        }

        try mangleTypeList(layoutTypeList, depth: depth + 1)

        if node.numberOfChildren == 3 {
            let signature = try node[safeChild: 1]
            let genericArgs = try node[safeChild: 2]
            try mangleTypeList(genericArgs, depth: depth + 1)
            try mangleDependentGenericSignature(signature, depth: depth + 1)
            append("XX")
        } else {
            append("Xx")
        }
    }

    private func mangleAsyncAwaitResumePartialFunction(_ node: Node, depth: Int) throws(ManglingError) {
        append("TQ")
        try mangleChildNode(node, at: 0, depth: depth + 1)
    }

    // MARK: - Error/Unsupported Methods (7 methods)

    private func mangleAccessorFunctionReference(_ node: Node, depth: Int) throws(ManglingError) {
        throw .unsupportedNodeKind(node)
    }

    private func mangleIndex(_ node: Node, depth: Int) throws(ManglingError) {
        // Handled inline elsewhere
        throw .unsupportedNodeKind(node)
    }

    private func mangleUnknownIndex(_ node: Node, depth: Int) throws(ManglingError) {
        // Handled inline elsewhere
        throw .unsupportedNodeKind(node)
    }

    private func mangleSILBoxImmutableField(_ node: Node, depth: Int) throws(ManglingError) {
        throw .unsupportedNodeKind(node)
    }

    private func mangleSILBoxLayout(_ node: Node, depth: Int) throws(ManglingError) {
        throw .unsupportedNodeKind(node)
    }

    private func mangleSILBoxMutableField(_ node: Node, depth: Int) throws(ManglingError) {
        throw .unsupportedNodeKind(node)
    }

    private func mangleVTableAttribute(_ node: Node, depth: Int) throws(ManglingError) {
        throw .unsupportedNodeKind(node)
    }

    // MARK: - Additional Missing Methods (17 methods)

    private func mangleAsyncSuspendResumePartialFunction(_ node: Node, depth: Int) throws(ManglingError) {
        append("TY")
        try mangleChildNode(node, at: 0, depth: depth + 1)
    }

    private func mangleDependentProtocolConformanceRoot(_ node: Node, depth: Int) throws(ManglingError) {
        try mangleType(node[safeChild: 0], depth: depth + 1)

        try manglePureProtocol(node[safeChild: 1], depth: depth + 1)

        append("HD")
        try mangleDependentConformanceIndex(node[safeChild: 2], depth: depth + 1)
    }

    private func mangleDependentProtocolConformanceInherited(_ node: Node, depth: Int) throws(ManglingError) {
        try mangleAnyProtocolConformance(node[safeChild: 0], depth: depth + 1)

        try manglePureProtocol(node[safeChild: 1], depth: depth + 1)

        append("HI")
        try mangleDependentConformanceIndex(node[safeChild: 2], depth: depth + 1)
    }

    private func mangleDependentProtocolConformanceAssociated(_ node: Node, depth: Int) throws(ManglingError) {
        try mangleAnyProtocolConformance(node[safeChild: 0], depth: depth + 1)

        try mangleDependentAssociatedConformance(node[safeChild: 1], depth: depth + 1)

        append("HA")
        try mangleDependentConformanceIndex(node[safeChild: 2], depth: depth + 1)
    }

    private func mangleDistributedAccessor(_ node: Node, depth: Int) throws(ManglingError) {
        append("TF")
    }

    private func mangleDistributedThunk(_ node: Node, depth: Int) throws(ManglingError) {
        append("TE")
    }

    private func mangleDynamicallyReplaceableFunctionImpl(_ node: Node, depth: Int) throws(ManglingError) {
        append("TI")
    }

    private func mangleDynamicallyReplaceableFunctionKey(_ node: Node, depth: Int) throws(ManglingError) {
        append("Tx")
    }

    private func mangleDynamicallyReplaceableFunctionVar(_ node: Node, depth: Int) throws(ManglingError) {
        append("TX")
    }

    private func mangleGenericPartialSpecializationNotReAbstracted(_ node: Node, depth: Int) throws(ManglingError) {
        try mangleGenericPartialSpecialization(node, depth: depth + 1)
    }

    private func mangleGenericSpecializationInResilienceDomain(_ node: Node, depth: Int) throws(ManglingError) {
        try mangleGenericSpecializationNode(node, specKind: "B", depth: depth + 1)
    }

    private func mangleGenericSpecializationNotReAbstracted(_ node: Node, depth: Int) throws(ManglingError) {
        try mangleGenericSpecializationNode(node, specKind: "G", depth: depth + 1)
    }

    private func mangleGenericSpecializationPrespecialized(_ node: Node, depth: Int) throws(ManglingError) {
        try mangleGenericSpecializationNode(node, specKind: "s", depth: depth + 1)
    }

    private func mangleImplParameterResultDifferentiability(_ node: Node, depth: Int) throws(ManglingError) {
        guard let text = node.text else {
            throw .invalidNodeStructure(node, message: "ImplParameterResultDifferentiability has no text")
        }
        // Empty string represents default differentiability
        if text.isEmpty {
            return
        }
        let diffChar: String? = switch text {
        case "@noDerivative": "w"
        default: nil
        }

        if let diffChar {
            append(diffChar)
        } else {
            throw .badNodeKind(node)
        }
    }

    private func manglePropertyWrapperBackingInitializer(_ node: Node, depth: Int) throws(ManglingError) {
        try mangleChildNodes(node, depth: depth + 1)
        append("fP")
    }

    private func manglePropertyWrapperInitFromProjectedValue(_ node: Node, depth: Int) throws(ManglingError) {
        try mangleChildNodes(node, depth: depth + 1)
        append("fW")
    }

    // MARK: - Additional 36 Missing Methods (Final Batch)

    /// Simple methods - just mangling child nodes + code
    private func mangleDefaultAssociatedConformanceAccessor(_ node: Node, depth: Int) throws(ManglingError) {
        try mangle(node[safeChild: 0], depth: depth + 1)
        try mangle(node[safeChild: 1], depth: depth + 1)
        try manglePureProtocol(node[safeChild: 2], depth: depth + 1)
        append("TN")
    }

    private func mangleDefaultAssociatedTypeMetadataAccessor(_ node: Node, depth: Int) throws(ManglingError) {
        try mangleChildNodes(node, depth: depth + 1)
        append("TM")
    }

    private func mangleAssociatedTypeWitnessTableAccessor(_ node: Node, depth: Int) throws(ManglingError) {
        try mangleChildNodes(node, depth: depth + 1)
        append("WT")
    }

    private func manglePredefinedObjCAsyncCompletionHandlerImpl(_ node: Node, depth: Int) throws(ManglingError) {
        try mangleChildNodes(node, depth: depth + 1)
        append("TZ")
    }

    private func mangleLazyProtocolWitnessTableAccessor(_ node: Node, depth: Int) throws(ManglingError) {
        try mangleChildNodes(node, depth: depth + 1)
        append("Wl")
    }

    private func mangleLazyProtocolWitnessTableCacheVariable(_ node: Node, depth: Int) throws(ManglingError) {
        try mangleChildNodes(node, depth: depth + 1)
        append("WL")
    }

    private func mangleProtocolConformanceRefInTypeModule(_ node: Node, depth: Int) throws(ManglingError) {
        try manglePureProtocol(node[safeChild: 0], depth: depth + 1)
        append("HP")
    }

    private func mangleProtocolConformanceRefInProtocolModule(_ node: Node, depth: Int) throws(ManglingError) {
        try manglePureProtocol(node[safeChild: 0], depth: depth + 1)
        append("Hp")
    }

    private func mangleProtocolConformanceRefInOtherModule(_ node: Node, depth: Int) throws(ManglingError) {
        try manglePureProtocol(node[safeChild: 0], depth: depth + 1)
        try mangleChildNode(node, at: 1, depth: depth + 1)
    }

    private func mangleTypeMetadataInstantiationFunction(_ node: Node, depth: Int) throws(ManglingError) {
        try mangleSingleChildNode(node, depth: depth + 1)
        append("Mi")
    }

    private func mangleTypeMetadataSingletonInitializationCache(_ node: Node, depth: Int) throws(ManglingError) {
        try mangleSingleChildNode(node, depth: depth + 1)
        append("Ml")
    }

    private func mangleReflectionMetadataBuiltinDescriptor(_ node: Node, depth: Int) throws(ManglingError) {
        try mangleSingleChildNode(node, depth: depth + 1)
        append("MB")
    }

    private func mangleReflectionMetadataFieldDescriptor(_ node: Node, depth: Int) throws(ManglingError) {
        try mangleSingleChildNode(node, depth: depth + 1)
        append("MF")
    }

    private func mangleReflectionMetadataAssocTypeDescriptor(_ node: Node, depth: Int) throws(ManglingError) {
        try mangleSingleChildNode(node, depth: depth + 1)
        append("MA")
    }

    private func mangleReflectionMetadataSuperclassDescriptor(_ node: Node, depth: Int) throws(ManglingError) {
        try mangleSingleChildNode(node, depth: depth + 1)
        append("MC")
    }

    private func mangleOutlinedInitializeWithTakeNoValueWitness(_ node: Node, depth: Int) throws(ManglingError) {
        try mangleChildNodes(node, depth: depth + 1)
        append("WOB")
    }

    private func mangleSugaredInlineArray(_ node: Node, depth: Int) throws(ManglingError) {
        try mangleType(node[safeChild: 0], depth: depth + 1)
        try mangleType(node[safeChild: 1], depth: depth + 1)
        append("XSA")
    }

    private func mangleCanonicalSpecializedGenericMetaclass(_ node: Node, depth: Int) throws(ManglingError) {
        try mangleChildNodes(node, depth: depth + 1)
        append("MM")
    }

    private func mangleCanonicalSpecializedGenericTypeMetadataAccessFunction(_ node: Node, depth: Int) throws(ManglingError) {
        try mangleSingleChildNode(node, depth: depth + 1)
        append("Mb")
    }

    private func mangleNoncanonicalSpecializedGenericTypeMetadata(_ node: Node, depth: Int) throws(ManglingError) {
        try mangleSingleChildNode(node, depth: depth + 1)
        append("MN")
    }

    private func mangleCanonicalPrespecializedGenericTypeCachingOnceToken(_ node: Node, depth: Int) throws(ManglingError) {
        try mangleSingleChildNode(node, depth: depth + 1)
        append("Mz")
    }

    private func mangleAutoDiffSelfReorderingReabstractionThunk(_ node: Node, depth: Int) throws(ManglingError) {
        var index = 0
        guard node.children.count >= 3 else {
            throw .invalidNodeStructure(node, message: "AutoDiffSelfReorderingReabstractionThunk needs at least 3 children")
        }

        // from type
        try mangle(node[safeChild: index], depth: depth + 1)
        index += 1

        // to type
        try mangle(node[safeChild: index], depth: depth + 1)
        index += 1

        // optional dependent generic signature
        if try node[safeChild: index].kind == .dependentGenericSignature {
            try mangleDependentGenericSignature(node[safeChild: index], depth: depth + 1)
            index += 1
        }

        append("TJO")

        // kind

        try mangle(node[safeChild: index], depth: depth + 1)
    }

    private func mangleKeyPathUnappliedMethodThunkHelper(_ node: Node, depth: Int) throws(ManglingError) {
        try mangleKeyPathThunkHelper(node, op: "Tkmu", depth: depth + 1)
    }

    /// Complex methods with special logic
    private func mangleDependentGenericConformanceRequirement(_ node: Node, depth: Int) throws(ManglingError) {
        guard node.children.count == 2 else {
            throw .invalidNodeStructure(node, message: "DependentGenericConformanceRequirement needs 2 children")
        }

        let protoOrClass = try node[safeChild: 1]
        guard protoOrClass.children.count > 0 else {
            throw .invalidNodeStructure(protoOrClass, message: "Protocol or class node has no children")
        }

        if try protoOrClass[safeChild: 0].kind == .protocol {
            try manglePureProtocol(protoOrClass, depth: depth + 1)

            let (numMembers, paramIdx) = try mangleConstrainedType(node[safeChild: 0], depth: depth + 1)

            guard numMembers < 0 || paramIdx != nil else {
                throw .invalidNodeStructure(node, message: "Invalid constrained type result")
            }

            switch numMembers {
            case -1:
                append("RQ")
                return
            case 0:
                append("R")
            case 1:
                append("Rp")
            default:
                append("RP")
            }

            if let idx = paramIdx {
                try mangleDependentGenericParamIndex(idx)
            }
            return
        }

        try mangle(protoOrClass, depth: depth + 1)

        let (numMembers, paramIdx) = try mangleConstrainedType(node[safeChild: 0], depth: depth + 1)
        // Note: C++ has DEMANGLER_ASSERT(numMembers < 0 || paramIdx != nil, node)
        // but we continue execution even if this doesn't hold (like C++ release mode)

        switch numMembers {
        case -1:
            append("RB")
            return
        case 0:
            append("Rb")
        case 1:
            append("Rc")
        default:
            append("RC")
        }

        if let idx = paramIdx {
            try mangleDependentGenericParamIndex(idx)
        }
    }

    private func mangleDependentGenericSameTypeRequirement(_ node: Node, depth: Int) throws(ManglingError) {
        guard node.children.count >= 2 else {
            throw .invalidNodeStructure(node, message: "DependentGenericSameTypeRequirement needs at least 2 children")
        }

        try mangleChildNode(node, at: 1, depth: depth + 1)

        let (numMembers, paramIdx) = try mangleConstrainedType(node[safeChild: 0], depth: depth + 1)
        // Note: C++ has DEMANGLER_ASSERT(numMembers < 0 || paramIdx != nil, node)
        // but we continue execution even if this doesn't hold (like C++ release mode)

        switch numMembers {
        case -1:
            append("RS")
            return
        case 0:
            append("Rs")
        case 1:
            append("Rt")
        default:
            append("RT")
        }

        if let idx = paramIdx {
            try mangleDependentGenericParamIndex(idx)
        }
    }

    private func mangleDependentGenericSameShapeRequirement(_ node: Node, depth: Int) throws(ManglingError) {
        guard node.children.count >= 2 else {
            throw .invalidNodeStructure(node, message: "DependentGenericSameShapeRequirement needs at least 2 children")
        }

        try mangleChildNode(node, at: 1, depth: depth + 1)

        let (numMembers, paramIdx) = try mangleConstrainedType(node[safeChild: 0], depth: depth + 1)

        guard numMembers < 0 || paramIdx != nil else {
            throw .invalidNodeStructure(node, message: "Invalid constrained type result")
        }

        guard numMembers == 0 else {
            throw .invalidNodeStructure(node, message: "Invalid same-shape requirement")
        }

        append("Rh")
        if let idx = paramIdx {
            try mangleDependentGenericParamIndex(idx)
        }
    }

    private func mangleDependentGenericLayoutRequirement(_ node: Node, depth: Int) throws(ManglingError) {
        guard node.children.count >= 2 else {
            throw .invalidNodeStructure(node, message: "DependentGenericLayoutRequirement needs at least 2 children")
        }

        let (numMembers, paramIdx) = try mangleConstrainedType(node[safeChild: 0], depth: depth + 1)
        // Note: C++ has DEMANGLER_ASSERT(numMembers < 0 || paramIdx != nil, node)
        // but we continue execution even if this doesn't hold (like C++ release mode)

        switch numMembers {
        case -1:
            append("RL")
        case 0:
            append("Rl")
        case 1:
            append("Rm")
        default:
            append("RM")
        }

        // If not a substitution, mangle the dependent generic param index
        if numMembers != -1, let idx = paramIdx {
            try mangleDependentGenericParamIndex(idx)
        }

        // Mangle layout constraint identifier
        guard try node[safeChild: 1].kind == .identifier else {
            throw .invalidNodeStructure(node, message: "Expected identifier as second child")
        }
        guard let text = try node[safeChild: 1].text, text.count == 1 else {
            throw .invalidNodeStructure(node, message: "Layout identifier must be single character")
        }
        append(text)

        // Optional size
        if node.numberOfChildren >= 3 {
            try mangleChildNode(node, at: 2, depth: depth + 1)
        }

        // Optional alignment
        if node.numberOfChildren >= 4 {
            try mangleChildNode(node, at: 3, depth: depth + 1)
        }
    }

    private func mangleConstrainedExistentialRequirementList(_ node: Node, depth: Int) throws(ManglingError) {
        guard node.children.count > 0 else {
            throw .invalidNodeStructure(node, message: "ConstrainedExistentialRequirementList must have children")
        }

        var firstElem = true
        for i in 0 ..< node.numberOfChildren {
            try mangleChildNode(node, at: i, depth: depth + 1)
            mangleListSeparator(&firstElem)
        }
    }

    private func mangleFunctionSignatureSpecializationReturn(_ node: Node, depth: Int) throws(ManglingError) {
        try mangleFunctionSignatureSpecializationParam(node, depth: depth + 1)
    }

    private func mangleFunctionSignatureSpecializationParam(_ node: Node, depth: Int) throws(ManglingError) {
        if node.children.count == 0 {
            append("n")
            return
        }

        // First child is kind
        guard let kindNode = node.children.first, let kindValue = kindNode.index else {
            throw .invalidNodeStructure(node, message: "FunctionSignatureSpecializationParam missing kind")
        }

        // Use enum values for cleaner code
        let kind = UInt64(kindValue)

        switch FunctionSigSpecializationParamKind(rawValue: kind) {
        case .constantPropFunction:
            append("pf")
        case .constantPropGlobal:
            append("pg")
        case .constantPropInteger:
            guard let text = try node[safeChild: 1].text else {
                throw .invalidNodeStructure(node, message: "ConstantPropInteger missing text")
            }
            append("pi")
            append(text)
        case .constantPropFloat:
            guard let text = try node[safeChild: 1].text else {
                throw .invalidNodeStructure(node, message: "ConstantPropFloat missing text")
            }
            append("pd")
            append(text)
        case .constantPropString:
            append("ps")
            guard let encodingStr = try node[safeChild: 1].text else {
                throw .invalidNodeStructure(node, message: "ConstantPropString missing encoding")
            }
            if encodingStr == "u8" {
                append("b")
            } else if encodingStr == "u16" {
                append("w")
            } else if encodingStr == "objc" {
                append("c")
            } else {
                throw .invalidNodeStructure(node, message: "Unknown string encoding: \(encodingStr)")
            }
        case .constantPropKeyPath:
            append("pk")
        case .closureProp:
            append("c")
        case .boxToValue:
            append("i")
        case .boxToStack:
            append("s")
        case .inOutToOut:
            append("r")
        case .sroa:
            append("x")
        default:
            if kindValue & FunctionSigSpecializationParamKind.existentialToGeneric.rawValue != 0 {
                append("e")
                if kindValue & FunctionSigSpecializationParamKind.dead.rawValue != 0 {
                    append("D")
                }
                if kindValue & FunctionSigSpecializationParamKind.ownedToGuaranteed.rawValue != 0 {
                    append("G")
                }
                if kindValue & FunctionSigSpecializationParamKind.guaranteedToOwned.rawValue != 0 {
                    append("O")
                }
            } else if kindValue & FunctionSigSpecializationParamKind.dead.rawValue != 0 {
                append("d")
                if kindValue & FunctionSigSpecializationParamKind.ownedToGuaranteed.rawValue != 0 {
                    append("G")
                }
                if kindValue & FunctionSigSpecializationParamKind.guaranteedToOwned.rawValue != 0 {
                    append("O")
                }
            } else if kindValue & FunctionSigSpecializationParamKind.ownedToGuaranteed.rawValue != 0 {
                append("g")
            } else if kindValue & FunctionSigSpecializationParamKind.guaranteedToOwned.rawValue != 0 {
                append("o")
            }
            if kindValue & FunctionSigSpecializationParamKind.sroa.rawValue != 0 {
                append("X")
            }
        }
    }

    private func mangleAnyProtocolConformanceList(_ node: Node, depth: Int) throws(ManglingError) {
        var firstElem = true
        for child in node.children {
            try mangleAnyProtocolConformance(child, depth: depth + 1)
            mangleListSeparator(&firstElem)
        }
        mangleEndOfList(firstElem)
    }

    /// Error/Unsupported methods
    private func mangleFunctionSignatureSpecializationParamKind(_ node: Node, depth: Int) throws(ManglingError) {
        // handled inline in mangleFunctionSignatureSpecializationParam
        throw .unsupportedNodeKind(node)
    }

    private func mangleFunctionSignatureSpecializationParamPayload(_ node: Node, depth: Int) throws(ManglingError) {
        // handled inline in mangleFunctionSignatureSpecializationParam
        throw .unsupportedNodeKind(node)
    }

    private func mangleUniqueExtendedExistentialTypeShapeSymbolicReference(_ node: Node, depth: Int) throws(ManglingError) {
        // We don't support absolute references in the mangling of these
        throw .unsupportedNodeKind(node)
    }

    private func mangleNonUniqueExtendedExistentialTypeShapeSymbolicReference(_ node: Node, depth: Int) throws(ManglingError) {
        // We don't support absolute references in the mangling of these
        throw .unsupportedNodeKind(node)
    }

    private func mangleSILThunkHopToMainActorIfNeeded(_ node: Node, depth: Int) throws(ManglingError) {
        // This method doesn't exist in C++ - likely a newer addition or different name
        throw .unsupportedNodeKind(node)
    }

    // MARK: - Helper Methods for Dependent Types

    /// Mangle a constrained type, returning the number of chain members and the base param node
    private func mangleConstrainedType(_ node: Node, depth: Int) throws(ManglingError) -> (numMembers: Int, paramIdx: Node?) {
        var node = node
        var resultNode: Node? = node
        if node.kind == .type {
            node = getChildOfType(node)
            resultNode = node
        }

        // Try substitution first
        let substResult = trySubstitution(node)
        if substResult.found {
            return (-1, nil)
        }

        // Build chain of dependent member types
        var chain: [Node] = []
        while node.kind == .dependentMemberType {
            try chain.append(node[safeChild: 1])
            node = try getChildOfType(node.firstChild)
            resultNode = node
        }

        // Check if we have a dependent generic param type or constrained existential self
        if node.kind != .dependentGenericParamType,
           node.kind != .constrainedExistentialSelf {
            try mangle(node, depth: depth + 1)

            if chain.isEmpty {
                return (-1, nil)
            }
            resultNode = nil
        }

        // Mangle the chain in reverse order
        var listSeparator = chain.count > 1 ? "_" : ""
        let n = chain.count
        if n >= 1 {
            for i in 1 ... n {
                let depAssocTyRef = chain[n - i]
                try mangle(depAssocTyRef, depth: depth + 1)
                append(listSeparator)
                listSeparator = "" // After first element, no more separators
            }
        }

        if !chain.isEmpty {
            addSubstitution(substResult.entry)
        }

        return (chain.count, resultNode)
    }

    /// Mangle a dependent generic parameter index
    private func mangleDependentGenericParamIndex(_ node: Node, nonZeroPrefix: String = "", zeroOp: String = "z") throws(ManglingError) {
        if node.kind == .constrainedExistentialSelf {
            append("s")
            return
        }

        guard node.children.count >= 2,
              let paramDepth = try node[safeChild: 0].index,
              let index = try node[safeChild: 1].index else {
            return
        }

        if paramDepth != 0 {
            append(nonZeroPrefix)
            append("d")
            mangleIndex(paramDepth - 1)
            mangleIndex(index)
            return
        }

        if index != 0 {
            append(nonZeroPrefix)
            mangleIndex(index - 1)
            return
        }

        // depth == index == 0
        append(zeroOp)
    }
}

extension Node {
    fileprivate subscript(safeChild childIndex: Int) -> Node {
        get throws(ManglingError) {
            if let child = children[safe: childIndex] {
                return child
            } else {
                throw .indexOutOfBounds
            }
        }
    }

    fileprivate var firstChild: Node {
        get throws(ManglingError) {
            try self[safeChild: 0]
        }
    }
}

// MARK: - Character Classification

extension Remangler {
    /// Returns true if the character is a lowercase letter (a-z)
    @inline(__always)
    private static func isLowerLetter(_ ch: Character) -> Bool {
        return ch >= "a" && ch <= "z"
    }

    /// Returns true if the character is an uppercase letter (A-Z)
    @inline(__always)
    private static func isUpperLetter(_ ch: Character) -> Bool {
        return ch >= "A" && ch <= "Z"
    }

    /// Returns true if the character is a digit (0-9)
    @inline(__always)
    private static func isDigit(_ ch: Character) -> Bool {
        return ch >= "0" && ch <= "9"
    }

    /// Returns true if the character is a hex digit (0-9, a-f, A-F)
    @inline(__always)
    private static func isHexDigit(_ ch: Character) -> Bool {
        return isDigit(ch) || (ch >= "a" && ch <= "f") || (ch >= "A" && ch <= "F")
    }

    /// Returns true if the character is a letter (a-z or A-Z)
    @inline(__always)
    private static func isLetter(_ ch: Character) -> Bool {
        return isLowerLetter(ch) || isUpperLetter(ch)
    }

    /// Returns true if the character is a letter or an underscore
    @inline(__always)
    private static func isAlpha(_ ch: Character) -> Bool {
        return isLetter(ch) || ch == "_"
    }

    /// Returns true if the character can be part of an identifier
    @inline(__always)
    private static func isIdentifierChar(_ ch: Character) -> Bool {
        return isAlpha(ch) || isDigit(ch)
    }

    /// Returns true if the character can be the first character of an identifier
    @inline(__always)
    private static func isStartOfIdentifier(_ ch: Character) -> Bool {
        return isAlpha(ch)
    }

    /// Returns true if the character defines the begin of a substitution word
    @inline(__always)
    private static func isWordStart(_ ch: Character) -> Bool {
        return !isDigit(ch) && ch != "_" && ch != "\0"
    }

    /// Returns true if the character (following prevCh) defines the end of a substitution word
    @inline(__always)
    private static func isWordEnd(_ ch: Character, _ prevCh: Character) -> Bool {
        if ch == "_" || ch == "\0" {
            return true
        }

        if !isUpperLetter(prevCh) && isUpperLetter(ch) {
            return true
        }

        return false
    }

    /// Returns true if the character is a valid character which may appear at the start of a symbol mangling
    @inline(__always)
    private static func isValidSymbolStart(_ ch: Character) -> Bool {
        return isLetter(ch) || ch == "_" || ch == "$"
    }

    /// Returns true if the character is a valid character which may appear in a symbol mangling
    /// anywhere other than the first character
    @inline(__always)
    private static func isValidSymbolChar(_ ch: Character) -> Bool {
        return isValidSymbolStart(ch) || isDigit(ch)
    }

    // MARK: - Punycode Support

    /// Returns true if the string contains any non-ASCII character
    private static func isNonAscii(_ str: String) -> Bool {
        for scalar in str.unicodeScalars {
            if scalar.value >= 0x80 {
                return true
            }
        }
        return false
    }

    /// Returns true if the string contains any character which may not appear in a
    /// mangled symbol string and therefore must be punycode encoded
    private static func needsPunycodeEncoding(_ str: String) -> Bool {
        if str.isEmpty {
            return false
        }

        let first = str.first!
        if !isValidSymbolStart(first) {
            return true
        }

        for ch in str.dropFirst() {
            if !isValidSymbolChar(ch) {
                return true
            }
        }

        return false
    }

    // MARK: - Operator Translation

    /// Translate the given operator character into its mangled form.
    ///
    /// Current operator characters: @/=-+*%<>!&|^~ and the special operator '..'
    private static func translateOperatorChar(_ op: Character) -> Character {
        switch op {
        case "&": return "a" // 'and'
        case "@": return "c" // 'commercial at sign'
        case "/": return "d" // 'divide'
        case "=": return "e" // 'equal'
        case ">": return "g" // 'greater'
        case "<": return "l" // 'less'
        case "*": return "m" // 'multiply'
        case "!": return "n" // 'negate'
        case "|": return "o" // 'or'
        case "+": return "p" // 'plus'
        case "?": return "q" // 'question'
        case "%": return "r" // 'remainder'
        case "-": return "s" // 'subtract'
        case "~": return "t" // 'tilde'
        case "^": return "x" // 'xor'
        case ".": return "z" // 'zperiod' (the z is silent)
        default: return op
        }
    }

    /// Returns a string where all characters of the operator are translated to their mangled form
    private static func translateOperator(_ op: String) -> String {
        return String(op.map { translateOperatorChar($0) })
    }

    // MARK: - Word Substitution

    /// Describes a word in a mangled identifier
    private struct SubstitutionWord {
        /// The position of the first word character in the mangled string
        var start: Int

        /// The length of the word
        var length: Int

        init(start: Int, length: Int) {
            self.start = start
            self.length = length
        }
    }

    /// Helper struct which represents a word replacement
    private struct WordReplacement {
        /// The position in the identifier where the word is substituted
        var stringPos: Int

        /// The index into the mangler's Words array (-1 if invalid)
        var wordIdx: Int

        init(stringPos: Int, wordIdx: Int) {
            self.stringPos = stringPos
            self.wordIdx = wordIdx
        }
    }

    // MARK: - Standard Type Substitutions

    /// Returns the standard type kind for an 'S' substitution
    ///
    /// For example, 'i' for "Int", 'S' for "String", etc.
    ///
    /// Based on StandardTypesMangling.def from Swift compiler
    ///
    /// - Parameters:
    ///   - typeName: The Swift type name
    ///   - allowConcurrencyManglings: When true, allows the standard substitutions
    ///     for types in the _Concurrency module that were introduced in Swift 5.5
    /// - Returns: The substitution string if this is a standard type, nil otherwise
    private static func getStandardTypeSubst(_ typeName: String, allowConcurrencyManglings: Bool = true) -> String? {
        // Standard types (Structure, Enum, Protocol)
        switch typeName {
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
                switch typeName {
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

    // MARK: - Substitution Merging

    /// Utility class for mangling merged substitutions
    ///
    /// Used in the Mangler and Remangler to optimize repeated substitutions.
    /// For example: 'AB' can be merged to 'A2B', 'AB' to 'AbC', etc.
    private class SubstitutionMerging {
        /// The position of the last substitution mangling
        /// e.g. 3 for 'AabC' and 'Aab4C'
        private var lastSubstPosition: Int = 0

        /// The size of the last substitution mangling
        /// e.g. 1 for 'AabC' or 2 for 'Aab4C'
        private var lastSubstSize: Int = 0

        /// The repeat count of the last substitution
        /// e.g. 1 for 'AabC' or 4 for 'Aab4C'
        private var lastNumSubsts: Int = 0

        /// True if the last substitution is an 'S' substitution,
        /// false if the last substitution is an 'A' substitution
        private var lastSubstIsStandardSubst: Bool = false

        /// Maximum number of repeated substitutions
        /// This limit prevents the demangler from blowing up on bogus substitutions
        static let maxRepeatCount = 2048

        init() {}

        /// Clear the state
        func clear() {
            lastNumSubsts = 0
        }

        /// Tries to merge the substitution with a previously mangled substitution
        ///
        /// Returns true on success. In case of false, the caller must mangle the
        /// substitution separately in the form 'S<Subst>' or 'A<Subst>'.
        ///
        /// - Parameters:
        ///   - buffer: Current buffer content
        ///   - subst: The substitution to merge
        ///   - isStandardSubst: True if this is an 'S' substitution, false for 'A'
        ///   - resetBuffer: Callback to reset buffer to a position
        ///   - appendToBuffer: Callback to append string to buffer
        ///   - getBuffer: Callback to get current buffer content
        /// - Returns: True if merge was successful
        func tryMergeSubst(
            _ mangler: Remangler,
            subst: String,
            isStandardSubst: Bool
        ) -> Bool {
            assert(Remangler.isUpperLetter(subst.last!) || (isStandardSubst && Remangler.isLowerLetter(subst.last!)))

            let bufferStr = mangler.buffer

            if lastNumSubsts > 0 && lastNumSubsts < Self.maxRepeatCount
                && bufferStr.count == lastSubstPosition + lastSubstSize
                && lastSubstIsStandardSubst == isStandardSubst {
                // The last mangled thing is a substitution
                assert(lastSubstPosition > 0 && lastSubstPosition < bufferStr.count)
                assert(lastSubstSize > 0)

                let lastSubstStart = bufferStr.index(bufferStr.endIndex, offsetBy: -lastSubstSize)
                var lastSubst = String(bufferStr[lastSubstStart...])

                // Drop leading digits
                while let first = lastSubst.first, Remangler.isDigit(first) {
                    lastSubst = String(lastSubst.dropFirst())
                }

                assert(Remangler.isUpperLetter(lastSubst.last!) || (isStandardSubst && Remangler.isLowerLetter(lastSubst.last!)))

                if lastSubst != subst && !isStandardSubst {
                    // We can merge with a different 'A' substitution
                    // e.g. 'AB' -> 'AbC'
                    lastSubstPosition = bufferStr.count
                    lastNumSubsts = 1
                    let resetPos = bufferStr.count - 1
                    mangler.resetBuffer(to: resetPos)
                    assert(Remangler.isUpperLetter(lastSubst.last!))

                    let lastChar = lastSubst.last!
                    let lowercaseChar = Character(UnicodeScalar(lastChar.asciiValue! - Character("A").asciiValue! + Character("a").asciiValue!))
                    mangler.append(String(lowercaseChar) + subst)
                    lastSubstSize = 1
                    return true
                }

                if lastSubst == subst {
                    // We can merge with the same 'A' or 'S' substitution
                    // e.g. 'AB' -> 'A2B', or 'S3i' -> 'S4i'
                    lastNumSubsts += 1
                    mangler.resetBuffer(to: lastSubstPosition)
                    mangler.append("\(lastNumSubsts)\(subst)")

                    // Get updated buffer to calculate the new size
                    let currentBuffer = mangler.buffer
                    lastSubstSize = currentBuffer.count - lastSubstPosition
                    return true
                }
            }

            // We can't merge with the previous substitution, but let's remember this
            // substitution which will be mangled by the caller
            lastSubstPosition = bufferStr.count + 1
            lastSubstSize = subst.count
            lastNumSubsts = 1
            lastSubstIsStandardSubst = isStandardSubst
            return false
        }
    }

    /// Mangles an identifier using word substitution
    ///
    /// This is a complex algorithm that:
    /// 1. Searches for common words in the identifier
    /// 2. Replaces repeated words with single-letter substitutions (a-z)
    /// 3. Handles Punycode encoding for non-ASCII identifiers
    ///
    /// - Parameters:
    ///   - mangler: The mangler instance implementing IdentifierMangler protocol
    ///   - ident: The identifier to mangle
    private static func mangleIdentifier(_ mangler: Remangler, _ ident: String) {
        let wordsInBuffer = mangler.words.count
        assert(mangler.substWordsInIdent.isEmpty)

        // Handle Punycode encoding for non-ASCII identifiers
        if mangler.usePunycode, needsPunycodeEncoding(ident) {
            if let encoded = Punycode.encodePunycode(ident, mapNonSymbolChars: true) {
                let pcIdent = encoded
                mangler.append("00\(pcIdent.count)")
                if let first = pcIdent.first, isDigit(first) || first == "_" {
                    mangler.append("_")
                }
                mangler.append(pcIdent)
                return
            }
        }

        // Search for word substitutions and new words
        let notInsideWord = -1
        var wordStartPos = notInsideWord

        for pos in 0 ... ident.count {
            let ch: Character = pos < ident.count ? ident[ident.index(ident.startIndex, offsetBy: pos)] : "\0"

            if wordStartPos != notInsideWord, isWordEnd(ch, pos > 0 ? ident[ident.index(ident.startIndex, offsetBy: pos - 1)] : "\0") {
                // End of a word
                assert(pos > wordStartPos)
                let wordLen = pos - wordStartPos
                let wordStart = ident.index(ident.startIndex, offsetBy: wordStartPos)
                let wordEnd = ident.index(wordStart, offsetBy: wordLen)
                let word = String(ident[wordStart ..< wordEnd])

                // Look up word in buffer and existing words
                func lookupWord(in str: String, from: Int, to: Int) -> Int? {
                    for idx in from ..< to {
                        let w = mangler.words[idx]
                        let existingWordStart = str.index(str.startIndex, offsetBy: w.start)
                        let existingWordEnd = str.index(existingWordStart, offsetBy: w.length)
                        let existingWord = String(str[existingWordStart ..< existingWordEnd])
                        if word == existingWord {
                            return idx
                        }
                    }
                    return nil
                }

                // Check if word exists in buffer
                var wordIdx = lookupWord(in: mangler.buffer, from: 0, to: wordsInBuffer)

                // Check if word exists in this identifier
                if wordIdx == nil {
                    wordIdx = lookupWord(in: ident, from: wordsInBuffer, to: mangler.words.count)
                }

                if let idx = wordIdx {
                    // Found word substitution
                    assert(idx < 26)
                    mangler.addSubstWordInIdent(WordReplacement(stringPos: wordStartPos, wordIdx: idx))
                } else if wordLen >= 2, mangler.words.count < Remangler.maxNumWords {
                    // New word
                    mangler.addWord(SubstitutionWord(start: wordStartPos, length: wordLen))
                }

                wordStartPos = notInsideWord
            }

            if wordStartPos == notInsideWord, isWordStart(ch) {
                // Begin of a word
                wordStartPos = pos
            }
        }

        // Mangle with word substitutions
        if !mangler.substWordsInIdent.isEmpty {
            mangler.append("0")
        }

        var pos = 0
        var wordsInBufferMutable = wordsInBuffer

        // Add dummy word at end
        mangler.addSubstWordInIdent(WordReplacement(stringPos: ident.count, wordIdx: -1))

        for idx in 0 ..< mangler.substWordsInIdent.count {
            let repl = mangler.substWordsInIdent[idx]

            if pos < repl.stringPos {
                // Mangle substring up to next word substitution
                var first = true
                mangler.append("\(repl.stringPos - pos)")

                repeat {
                    // Update start position of new words
                    if wordsInBufferMutable < mangler.words.count,
                       mangler.words[wordsInBufferMutable].start == pos {
                        var word = mangler.words[wordsInBufferMutable]
                        word.start = mangler.buffer.count
                        mangler.words[wordsInBufferMutable] = word
                        wordsInBufferMutable += 1
                    }

                    let ch = ident[ident.index(ident.startIndex, offsetBy: pos)]

                    // Error recovery for invalid identifiers
                    if first, isDigit(ch) {
                        mangler.append("X")
                    } else {
                        mangler.append(String(ch))
                    }

                    pos += 1
                    first = false
                } while pos < repl.stringPos
            }

            // Handle word substitution
            if repl.wordIdx >= 0 {
                assert(repl.wordIdx < mangler.words.count, "Word index \(repl.wordIdx) out of range (words.count = \(mangler.words.count))")
                pos += mangler.words[repl.wordIdx].length

                if idx < mangler.substWordsInIdent.count - 2 {
                    // Lowercase letter
                    let ch = Character(UnicodeScalar(UInt8(ascii: "a") + UInt8(repl.wordIdx)))
                    mangler.append(String(ch))
                } else {
                    // Last word substitution is uppercase
                    let ch = Character(UnicodeScalar(UInt8(ascii: "A") + UInt8(repl.wordIdx)))
                    mangler.append(String(ch))
                    if pos == ident.count {
                        mangler.append("0")
                    }
                }
            }
        }

        mangler.substWordsInIdent.removeAll()
    }

    /// An entry in the remangler's substitution map.
    ///
    /// This struct represents a substitutable node in the demangling tree, along with
    /// metadata for efficient lookup and comparison.
    private struct SubstitutionEntry: Hashable {
        /// The node being substituted
        let node: Node?

        /// Precomputed hash value for efficient lookup
        let storedHash: Int

        /// Whether to treat this node as an identifier (affects equality comparison)
        let treatAsIdentifier: Bool

        init(node: Node?, storedHash: Int, treatAsIdentifier: Bool) {
            self.node = node
            self.storedHash = storedHash
            self.treatAsIdentifier = treatAsIdentifier
        }

        /// Create an empty entry
        static var empty: SubstitutionEntry {
            return SubstitutionEntry(node: nil, storedHash: 0, treatAsIdentifier: false)
        }

        /// Check if this entry is empty
        var isEmpty: Bool {
            return node == nil
        }

        /// Check if this entry matches a given node and identifier treatment
        func matches(node: Node?, treatAsIdentifier: Bool) -> Bool {
            // Use pointer equality for fast path
            return self.node === node && self.treatAsIdentifier == treatAsIdentifier
        }

        // MARK: - Hashable

        func hash(into hasher: inout Hasher) {
            hasher.combine(storedHash)
        }

        static func == (lhs: SubstitutionEntry, rhs: SubstitutionEntry) -> Bool {
            // Fast path: check hash first
            if lhs.storedHash != rhs.storedHash {
                return false
            }

            // Check treatment mode
            if lhs.treatAsIdentifier != rhs.treatAsIdentifier {
                return false
            }

            // Handle nil nodes
            guard let lhsNode = lhs.node, let rhsNode = rhs.node else {
                return lhs.node == nil && rhs.node == nil
            }

            // Use appropriate equality check
            if lhs.treatAsIdentifier {
                return identifierEquals(lhsNode, rhsNode)
            } else {
                return deepEquals(lhsNode, rhsNode)
            }
        }

        // MARK: - Helper Methods

        /// Check if two nodes are equal as identifiers.
        ///
        /// This handles special cases like operator character translation.
        private static func identifierEquals(_ lhs: Node, _ rhs: Node) -> Bool {
            // Fast path: same kind and text
            if lhs.kind == rhs.kind && lhs.text == rhs.text {
                return true
            }

            // Both must have text
            guard let lhsText = lhs.text, let rhsText = rhs.text else {
                return false
            }

            // Length must match
            guard lhsText.count == rhsText.count else {
                return false
            }

            // Check if we need to translate operator characters
            let needsTranslation = lhs.kind.isOperatorKind || rhs.kind.isOperatorKind

            if needsTranslation {
                // Slow path: compare character by character with translation
                return lhsText.elementsEqual(rhsText) { lhsChar, rhsChar in
                    let lhsTranslated = lhs.kind.isOperatorKind ? Remangler.translateOperatorChar(lhsChar) : lhsChar
                    let rhsTranslated = rhs.kind.isOperatorKind ? Remangler.translateOperatorChar(rhsChar) : rhsChar
                    return lhsTranslated == rhsTranslated
                }
            } else {
                // Fast path for non-operators
                return lhsText == rhsText
            }
        }

        /// Perform deep equality comparison of two nodes.
        private static func deepEquals(_ lhs: Node, _ rhs: Node) -> Bool {
            // Nodes must be similar (same kind, same text/index)
            guard lhs.isSimilar(to: rhs) else {
                return false
            }

            // Check all children recursively
            guard lhs.children.count == rhs.children.count else {
                return false
            }

            for (lhsChild, rhsChild) in zip(lhs.children, rhs.children) {
                if !deepEquals(lhsChild, rhsChild) {
                    return false
                }
            }

            return true
        }
    }
}

extension Node.Kind {
    /// Check if this node kind represents an operator
    var isOperatorKind: Bool {
        switch self {
        case .infixOperator,
             .prefixOperator,
             .postfixOperator:
            return true
        default:
            return false
        }
    }
}

extension Node {
    /// Check if this node is similar to another node.
    ///
    /// Similarity means same kind and same text/index, but not necessarily same children.
    func isSimilar(to other: Node) -> Bool {
        // Kind must match
        guard kind == other.kind else {
            return false
        }

        // Check text
        if let selfText = text {
            if selfText != other.text {
                return false
            }
        } else if other.text != nil {
            return false
        }

        // Check index
        if let selfIndex = index {
            if selfIndex != other.index {
                return false
            }
        } else if other.index != nil {
            return false
        }

        return true
    }
    
    var character: Character {
        get throws(ManglingError) {
            if let index, let scalar = UnicodeScalar(UInt32(index)) {
                return Character(scalar)
            } else {
                throw .genericError("")
            }
        }
    }
}


