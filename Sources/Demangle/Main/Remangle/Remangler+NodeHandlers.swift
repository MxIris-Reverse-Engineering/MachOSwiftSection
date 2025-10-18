/// Extension containing specific node kind handlers
extension Remangler {
    // MARK: - Top-Level Nodes

    func mangleGlobal(_ node: Node, depth: Int) throws(ManglingError) {
        // Global node wraps the actual entity
        // Output the mangling prefix based on flavor
        append("_$s") // Default flavor

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

    func mangleSuffix(_ node: Node, depth: Int) throws(ManglingError) {
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

    func mangleType(_ node: Node, depth: Int) throws(ManglingError) {
        try mangleSingleChildNode(node, depth: depth + 1)
    }

    func mangleTypeMangling(_ node: Node, depth: Int) throws(ManglingError) {
        // TypeMangling only outputs children and 'D' suffix
        // The '_$s' prefix is output by the Global node
        try mangleChildNodes(node, depth: depth + 1)
        append("D")
    }

    func mangleTypeList(_ node: Node, depth: Int) throws(ManglingError) {
        // Type list with proper list separators
        var isFirst = true
        for child in node.children {
            try mangle(child, depth: depth + 1)
            mangleListSeparator(&isFirst)
        }
        mangleEndOfList(isFirst)
    }

    // MARK: - Nominal Types

    func mangleStructure(_ node: Node, depth: Int) throws(ManglingError) {
        try mangleAnyNominalType(node, depth: depth + 1)
    }

    func mangleClass(_ node: Node, depth: Int) throws(ManglingError) {
        try mangleAnyNominalType(node, depth: depth + 1)
    }

    func mangleEnum(_ node: Node, depth: Int) throws(ManglingError) {
        try mangleAnyNominalType(node, depth: depth + 1)
    }

    func mangleProtocol(_ node: Node, depth: Int) throws(ManglingError) {
        try mangleAnyGenericType(node, typeOp: "P", depth: depth + 1)
    }

    func mangleTypeAlias(_ node: Node, depth: Int) throws(ManglingError) {
        try mangleAnyNominalType(node, depth: depth + 1)
    }

    // MARK: - Bound Generic Types

    func mangleBoundGenericStructure(_ node: Node, depth: Int) throws(ManglingError) {
        try mangleAnyNominalType(node, depth: depth + 1)
    }

    func mangleBoundGenericClass(_ node: Node, depth: Int) throws(ManglingError) {
        try mangleAnyNominalType(node, depth: depth + 1)
    }

    func mangleBoundGenericEnum(_ node: Node, depth: Int) throws(ManglingError) {
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

    func mangleFunctionType(_ node: Node, depth: Int) throws(ManglingError) {
        // Function type: reverse children (result comes first in mangling)
        try mangleFunctionSignature(node, depth: depth + 1)
        append("c")
    }

    func mangleFunctionSignature(_ node: Node, depth: Int) throws(ManglingError) {
        try mangleChildNodesReversed(node, depth: depth)
    }

    func mangleArgumentTuple(_ node: Node, depth: Int) throws(ManglingError) {
        let child = try skipType(node[safeChild: 0])

        if child.kind == .tuple, child.children.count == 0 {
            append("y")
            return
        }

        try mangle(child, depth: depth + 1)
    }

    func mangleReturnType(_ node: Node, depth: Int) throws(ManglingError) {
        // Return type uses same logic as ArgumentTuple
        try mangleArgumentTuple(node, depth: depth + 1)
    }

    // MARK: - Functions and Methods

    func mangleFunction(_ node: Node, depth: Int) throws(ManglingError) {
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

    func mangleAllocator(_ node: Node, depth: Int) throws(ManglingError) {
        try mangleAnyConstructor(node, kindOp: "C", depth: depth + 1)
    }

    func mangleConstructor(_ node: Node, depth: Int) throws(ManglingError) {
        try mangleAnyConstructor(node, kindOp: "c", depth: depth)
    }

    func mangleDestructor(_ node: Node, depth: Int) throws(ManglingError) {
        try mangleChildNodes(node, depth: depth + 1)
        append("fd")
    }

    func mangleGetter(_ node: Node, depth: Int) throws(ManglingError) {
        try mangleAbstractStorage(node.firstChild, accessorCode: "g", depth: depth + 1)
    }

    func mangleSetter(_ node: Node, depth: Int) throws(ManglingError) {
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

    func mangleIdentifier(_ node: Node, depth: Int) throws(ManglingError) {
        mangleIdentifierImpl(node, isOperator: false)
    }

    func manglePrivateDeclName(_ node: Node, depth: Int) throws(ManglingError) {
        try mangleChildNodesReversed(node, depth: depth + 1)
        append(node.numberOfChildren == 1 ? "Ll" : "LL")
    }

    func mangleLocalDeclName(_ node: Node, depth: Int) throws(ManglingError) {
        try mangleChildNode(node, at: 1, depth: depth + 1)

        append("L")

        try mangleChildNode(node, at: 0, depth: depth + 1)
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
            processedText = Mangle.translateOperator(text)
        } else {
            processedText = text
        }

        // Use the shared Mangle.mangleIdentifier implementation
        var mangler = self
        Mangle.mangleIdentifier(&mangler, processedText)

        // Add this node to the substitution table
        addSubstitution(substResult.entry)
    }

    private func encodePunycode(_ text: String) -> String? {
        // Use the Punycode encoding implementation
        // mapNonSymbolChars: true to handle non-symbol characters
        return Punycode.encodePunycode(text, mapNonSymbolChars: true)
    }

    // MARK: - Module and Context

    func mangleModule(_ node: Node, depth: Int) throws(ManglingError) {
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

    func mangleExtension(_ node: Node, depth: Int) throws(ManglingError) {
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

    func mangleBuiltinTypeName(_ node: Node, depth: Int) throws(ManglingError) {
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

    func mangleTuple(_ node: Node, depth: Int) throws(ManglingError) {
        // Use mangleTypeList which handles proper list separators
        try mangleTypeList(node, depth: depth + 1)
        append("t")
    }

    func mangleTupleElement(_ node: Node, depth: Int) throws(ManglingError) {
        // Tuple element: optional label + type
        // C++ uses mangleChildNodesReversed, so mangle in reverse order: type, then label
        try mangleChildNodesReversed(node, depth: depth + 1)
    }

    // MARK: - Dependent Types

    func mangleDependentGenericParamType(_ node: Node, depth: Int) throws(ManglingError) {
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

    func mangleDependentMemberType(_ node: Node, depth: Int) throws(ManglingError) {
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

    func mangleProtocolList(_ node: Node, depth: Int) throws(ManglingError) {
        try mangleProtocolList(node, superclass: nil, hasExplicitAnyObject: false, depth: depth + 1)
    }

    func mangleProtocolListWithClass(_ node: Node, depth: Int) throws(ManglingError) {
        try mangleProtocolList(node[safeChild: 0], superclass: node[safeChild: 1], hasExplicitAnyObject: false, depth: depth + 1)
    }

    func mangleProtocolListWithAnyObject(_ node: Node, depth: Int) throws(ManglingError) {
        try mangleProtocolList(node[safeChild: 0], superclass: nil, hasExplicitAnyObject: true, depth: depth + 1)
    }

    // MARK: - Metatypes

    func mangleMetatype(_ node: Node, depth: Int) throws(ManglingError) {
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

    func mangleExistentialMetatype(_ node: Node, depth: Int) throws(ManglingError) {
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

    func mangleInOut(_ node: Node, depth: Int) throws(ManglingError) {
        try mangleSingleChildNode(node, depth: depth)
        append("z")
    }

    func mangleShared(_ node: Node, depth: Int) throws(ManglingError) {
        try mangleSingleChildNode(node, depth: depth)
        append("h")
    }

    func mangleOwned(_ node: Node, depth: Int) throws(ManglingError) {
        try mangleSingleChildNode(node, depth: depth)
        append("n")
    }

    // MARK: - Numbers and Indices

    func mangleNumber(_ node: Node, depth: Int) throws(ManglingError) {
        guard let index = node.index else {
            throw .invalidNodeStructure(node, message: "Number has no index")
        }
        mangleIndex(index)
    }

    // MARK: - Bound Generic Types (Additional)

    func mangleBoundGenericProtocol(_ node: Node, depth: Int) throws(ManglingError) {
        try mangleAnyNominalType(node, depth: depth + 1)
    }

    func mangleBoundGenericTypeAlias(_ node: Node, depth: Int) throws(ManglingError) {
        try mangleAnyNominalType(node, depth: depth + 1)
    }

    // MARK: - Variables and Storage

    func mangleVariable(_ node: Node, depth: Int) throws(ManglingError) {
        try mangleAbstractStorage(node, accessorCode: "p", depth: depth + 1)
    }

    func mangleSubscript(_ node: Node, depth: Int) throws(ManglingError) {
        try mangleAbstractStorage(node, accessorCode: "p", depth: depth + 1)
    }

    func mangleDidSet(_ node: Node, depth: Int) throws(ManglingError) {
        try mangleAbstractStorage(node[safeChild: 0], accessorCode: "W", depth: depth + 1)
    }

    func mangleWillSet(_ node: Node, depth: Int) throws(ManglingError) {
        try mangleAbstractStorage(node[safeChild: 0], accessorCode: "w", depth: depth + 1)
    }

    func mangleReadAccessor(_ node: Node, depth: Int) throws(ManglingError) {
        try mangleAbstractStorage(node[safeChild: 0], accessorCode: "r", depth: depth + 1)
    }

    func mangleModifyAccessor(_ node: Node, depth: Int) throws(ManglingError) {
        try mangleAbstractStorage(node[safeChild: 0], accessorCode: "M", depth: depth + 1)
    }

    // MARK: - Reference Storage

    func mangleWeak(_ node: Node, depth: Int) throws(ManglingError) {
        try mangleSingleChildNode(node, depth: depth + 1)
        append("Xw")
    }

    func mangleUnowned(_ node: Node, depth: Int) throws(ManglingError) {
        try mangleSingleChildNode(node, depth: depth + 1)
        append("Xo")
    }

    func mangleUnmanaged(_ node: Node, depth: Int) throws(ManglingError) {
        try mangleSingleChildNode(node, depth: depth + 1)
        append("Xu")
    }

    // MARK: - Special Function Types

    func mangleThinFunctionType(_ node: Node, depth: Int) throws(ManglingError) {
        try mangleFunctionSignature(node, depth: depth + 1)
        append("Xf")
    }

    func mangleNoEscapeFunctionType(_ node: Node, depth: Int) throws(ManglingError) {
        try mangleChildNodesReversed(node, depth: depth + 1)
        append("XE")
    }

    func mangleAutoClosureType(_ node: Node, depth: Int) throws(ManglingError) {
        try mangleChildNodesReversed(node, depth: depth + 1)
        append("XK")
    }

    func mangleEscapingAutoClosureType(_ node: Node, depth: Int) throws(ManglingError) {
        try mangleChildNodesReversed(node, depth: depth + 1)
        append("XA")
    }

    func mangleUncurriedFunctionType(_ node: Node, depth: Int) throws(ManglingError) {
        try mangleFunctionSignature(node, depth: depth + 1)
        append("c")
    }

    // MARK: - Protocol and Type References

    func mangleProtocolWitness(_ node: Node, depth: Int) throws(ManglingError) {
        try mangleChildNodes(node, depth: depth + 1)
        append("TW")
    }

    func mangleProtocolWitnessTable(_ node: Node, depth: Int) throws(ManglingError) {
        try mangleSingleChildNode(node, depth: depth + 1)
        append("WP")
    }

    func mangleProtocolWitnessTableAccessor(_ node: Node, depth: Int) throws(ManglingError) {
        try mangleSingleChildNode(node, depth: depth + 1)
        append("Wa")
    }

    func mangleValueWitness(_ node: Node, depth: Int) throws(ManglingError) {
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

    func mangleValueWitnessTable(_ node: Node, depth: Int) throws(ManglingError) {
        try mangleSingleChildNode(node, depth: depth + 1)
        append("WV")
    }

    // MARK: - Metadata

    func mangleTypeMetadata(_ node: Node, depth: Int) throws(ManglingError) {
        try mangleSingleChildNode(node, depth: depth + 1)
        append("N")
    }

    func mangleTypeMetadataAccessFunction(_ node: Node, depth: Int) throws(ManglingError) {
        try mangleSingleChildNode(node, depth: depth + 1)
        append("Ma")
    }

    func mangleFullTypeMetadata(_ node: Node, depth: Int) throws(ManglingError) {
        try mangleSingleChildNode(node, depth: depth + 1)
        append("Mf")
    }

    func mangleMetaclass(_ node: Node, depth: Int) throws(ManglingError) {
        try mangleChildNodes(node, depth: depth + 1)
        append("Mm")
    }

    // MARK: - Static and Class Members

    func mangleStatic(_ node: Node, depth: Int) throws(ManglingError) {
        try mangleSingleChildNode(node, depth: depth + 1)
        append("Z")
    }

    // MARK: - Initializers

    func mangleInitializer(_ node: Node, depth: Int) throws(ManglingError) {
        try mangleChildNodes(node, depth: depth + 1)
        append("fi")
    }

    // MARK: - Operators

    func manglePrefixOperator(_ node: Node, depth: Int) throws(ManglingError) {
        mangleIdentifierImpl(node, isOperator: true)
        append("op")
    }

    func manglePostfixOperator(_ node: Node, depth: Int) throws(ManglingError) {
        mangleIdentifierImpl(node, isOperator: true)
        append("oP")
    }

    func mangleInfixOperator(_ node: Node, depth: Int) throws(ManglingError) {
        mangleIdentifierImpl(node, isOperator: true)
        append("oi")
    }

    // MARK: - Generic Signature

    func mangleDependentGenericSignature(_ node: Node, depth: Int) throws(ManglingError) {
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

    func mangleDependentGenericType(_ node: Node, depth: Int) throws(ManglingError) {
        // Mangle children in reverse order (type, then generic signature)
        try mangleChildNodesReversed(node, depth: depth + 1)
        append("u")
    }

    // MARK: - Throwing and Async

    func mangleThrowsAnnotation(_ node: Node, depth: Int) throws(ManglingError) {
        append("K")
    }

    func mangleAsyncAnnotation(_ node: Node, depth: Int) throws(ManglingError) {
        append("Ya")
    }

    // MARK: - Context

    func mangleDeclContext(_ node: Node, depth: Int) throws(ManglingError) {
        try mangleSingleChildNode(node, depth: depth + 1)
    }

    func mangleAnonymousContext(_ node: Node, depth: Int) throws(ManglingError) {
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

    func mangleOtherNominalType(_ node: Node, depth: Int) throws(ManglingError) {
        try mangleAnyNominalType(node, depth: depth + 1)
    }

    // MARK: - Closures

    func mangleExplicitClosure(_ node: Node, depth: Int) throws(ManglingError) {
        try mangleChildNode(node, at: 0, depth: depth + 1) // context
        try mangleChildNode(node, at: 2, depth: depth + 1) // type
        append("fU")
        try mangleChildNode(node, at: 1, depth: depth + 1)
    }

    func mangleImplicitClosure(_ node: Node, depth: Int) throws(ManglingError) {
        try mangleChildNode(node, at: 0, depth: depth + 1) // context
        try mangleChildNode(node, at: 2, depth: depth + 1) // type
        append("fu")
        try mangleChildNode(node, at: 1, depth: depth + 1) // index
    }

    // MARK: - Label List and Tuple Element Name

    func mangleLabelList(_ node: Node, depth: Int) throws(ManglingError) {
        // LabelList contains identifiers or empty placeholders
        // Labels are mangled sequentially WITHOUT separators (unlike TypeList)
        if node.children.isEmpty {
            append("y")
        } else {
            try mangleChildNodes(node, depth: depth + 1)
        }
    }

    func mangleTupleElementName(_ node: Node, depth: Int) throws(ManglingError) {
        try mangleIdentifier(node, depth: depth + 1)
    }

    // MARK: - Special Types

    func mangleDynamicSelf(_ node: Node, depth: Int) throws(ManglingError) {
        try mangleSingleChildNode(node, depth: depth)
        append("XD")
    }

    func mangleErrorType(_ node: Node, depth: Int) throws(ManglingError) {
        append("Xe")
    }

    // MARK: - List Markers

    func mangleEmptyList(_ node: Node, depth: Int) throws(ManglingError) {
        append("y")
    }

    func mangleFirstElementMarker(_ node: Node, depth: Int) throws(ManglingError) {
        append("_")
    }

    func mangleVariadicMarker(_ node: Node, depth: Int) throws(ManglingError) {
        append("d")
    }

    // MARK: - Field and Enum

    func mangleFieldOffset(_ node: Node, depth: Int) throws(ManglingError) {
        try mangleChildNode(node, at: 1, depth: depth + 1) // variable
        append("Wv")
        try mangleChildNode(node, at: 0, depth: depth + 1) // directness
    }

    func mangleEnumCase(_ node: Node, depth: Int) throws(ManglingError) {
        try mangleSingleChildNode(node, depth: depth + 1) // enum case
        append("WC")
    }

    // MARK: - Generic Support (High Priority)

    /// Mangle any nominal type (generic or not)
    func mangleAnyNominalType(_ node: Node, depth: Int) throws(ManglingError) {
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
    func mangleAnyGenericType(_ node: Node, typeOp: String, depth: Int) throws(ManglingError) {
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
    func mangleAnyConstructor(_ node: Node, kindOp: Character, depth: Int) throws(ManglingError) {
        try mangleChildNodes(node, depth: depth + 1)
        append("f")
        append(kindOp)
    }

    // MARK: - Bound Generic Function

    func mangleBoundGenericFunction(_ node: Node, depth: Int) throws(ManglingError) {
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

    func mangleBoundGenericOtherNominalType(_ node: Node, depth: Int) throws(ManglingError) {
        try mangleAnyNominalType(node, depth: depth + 1)
    }

    // MARK: - Associated Types

    func mangleAssociatedType(_ node: Node, depth: Int) throws(ManglingError) {
        // Associated types are not directly mangleable
        throw .unsupportedNodeKind(node)
    }

    func mangleAssociatedTypeRef(_ node: Node, depth: Int) throws(ManglingError) {
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

    func mangleAssociatedTypeDescriptor(_ node: Node, depth: Int) throws(ManglingError) {
        try mangleChildNodes(node, depth: depth + 1)
        append("Tl")
    }

    func mangleAssociatedConformanceDescriptor(_ node: Node, depth: Int) throws(ManglingError) {
        try mangle(node[safeChild: 0], depth: depth + 1)
        try mangle(node[safeChild: 1], depth: depth + 1)
        try manglePureProtocol(node[safeChild: 2], depth: depth + 1)
        append("Tn")
    }

    func mangleAssociatedTypeMetadataAccessor(_ node: Node, depth: Int) throws(ManglingError) {
        try mangleChildNodes(node, depth: depth + 1)
        append("Wt")
    }

    func mangleAssocTypePath(_ node: Node, depth: Int) throws(ManglingError) {
        // Mangle path to associated type
        var firstElem = true
        for child in node.children {
            try mangle(child, depth: depth + 1)
            mangleListSeparator(&firstElem)
        }
    }

    func mangleAssociatedTypeGenericParamRef(_ node: Node, depth: Int) throws(ManglingError) {
        try mangleType(node[safeChild: 0], depth: depth + 1)

        try mangleAssocTypePath(node[safeChild: 1], depth: depth + 1)

        append("MXA")
    }

    // MARK: - Protocol Conformance

    func mangleProtocolConformance(_ node: Node, depth: Int) throws(ManglingError) {
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

    func mangleConcreteProtocolConformance(_ node: Node, depth: Int) throws(ManglingError) {
        try mangleType(node[safeChild: 0], depth: depth + 1)
        try mangle(node[safeChild: 1], depth: depth + 1)
        if node.numberOfChildren > 2 {
            try mangleAnyProtocolConformanceList(node[safeChild: 2], depth: depth + 1)
        } else {
            append("y")
        }
        append("HC")
    }

    func mangleProtocolConformanceDescriptor(_ node: Node, depth: Int) throws(ManglingError) {
        try mangleProtocolConformance(node[safeChild: 0], depth: depth + 1)
        append("Mc")
    }

    func mangleAnyProtocolConformance(_ node: Node, depth: Int) throws(ManglingError) {
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

    func mangleNominalTypeDescriptor(_ node: Node, depth: Int) throws(ManglingError) {
        try mangleSingleChildNode(node, depth: depth + 1)
        append("Mn")
    }

    func mangleNominalTypeDescriptorRecord(_ node: Node, depth: Int) throws(ManglingError) {
        try mangleSingleChildNode(node, depth: depth + 1)
        append("Hn")
    }

    func mangleProtocolDescriptor(_ node: Node, depth: Int) throws(ManglingError) {
        try manglePureProtocol(node[safeChild: 0], depth: depth + 1)
        append("Mp")
    }

    func mangleProtocolDescriptorRecord(_ node: Node, depth: Int) throws(ManglingError) {
        try manglePureProtocol(node[safeChild: 0], depth: depth + 1)
        append("Hr")
    }

    func mangleTypeMetadataCompletionFunction(_ node: Node, depth: Int) throws(ManglingError) {
        try mangleSingleChildNode(node, depth: depth + 1)
        append("Mr")
    }

    func mangleTypeMetadataDemanglingCache(_ node: Node, depth: Int) throws(ManglingError) {
        try mangleSingleChildNode(node, depth: depth + 1)
        append("MD")
    }

    func mangleTypeMetadataInstantiationCache(_ node: Node, depth: Int) throws(ManglingError) {
        try mangleSingleChildNode(node, depth: depth + 1)
        append("MI")
    }

    func mangleTypeMetadataLazyCache(_ node: Node, depth: Int) throws(ManglingError) {
        try mangleChildNodes(node, depth: depth + 1)
        append("ML")
    }

    func mangleClassMetadataBaseOffset(_ node: Node, depth: Int) throws(ManglingError) {
        try mangleSingleChildNode(node, depth: depth + 1)
        append("Mo")
    }

    func mangleGenericTypeMetadataPattern(_ node: Node, depth: Int) throws(ManglingError) {
        try mangleSingleChildNode(node, depth: depth + 1)
        append("MP")
    }

    func mangleProtocolWitnessTablePattern(_ node: Node, depth: Int) throws(ManglingError) {
        try mangleSingleChildNode(node, depth: depth + 1)
        append("Wp")
    }

    func mangleGenericProtocolWitnessTable(_ node: Node, depth: Int) throws(ManglingError) {
        try mangleSingleChildNode(node, depth: depth + 1)
        append("WG")
    }

    func mangleGenericProtocolWitnessTableInstantiationFunction(_ node: Node, depth: Int) throws(ManglingError) {
        try mangleSingleChildNode(node, depth: depth + 1)
        append("WI")
    }

    func mangleResilientProtocolWitnessTable(_ node: Node, depth: Int) throws(ManglingError) {
        try mangleSingleChildNode(node, depth: depth + 1)
        append("Wr")
    }

    func mangleProtocolSelfConformanceWitness(_ node: Node, depth: Int) throws(ManglingError) {
        try mangleSingleChildNode(node, depth: depth + 1)
        append("TS")
    }

    func mangleBaseWitnessTableAccessor(_ node: Node, depth: Int) throws(ManglingError) {
        try mangleChildNodes(node, depth: depth + 1)
        append("Wb")
    }

    func mangleBaseConformanceDescriptor(_ node: Node, depth: Int) throws(ManglingError) {
        try mangle(node[safeChild: 0], depth: depth + 1)
        try manglePureProtocol(node[safeChild: 1], depth: depth + 1)
        append("Tb")
    }

    func mangleDependentAssociatedConformance(_ node: Node, depth: Int) throws(ManglingError) {
        try mangleType(node[safeChild: 0], depth: depth + 1)
        try manglePureProtocol(node[safeChild: 1], depth: depth + 1)
    }

    func mangleRetroactiveConformance(_ node: Node, depth: Int) throws(ManglingError) {
        try mangleAnyProtocolConformance(node[safeChild: 1], depth: depth + 1)
        append("g")
        if let index = try node[safeChild: 0].index {
            mangleIndex(index)
        }
    }

    // MARK: - Outlined Operations (High Priority)

    func mangleOutlinedCopy(_ node: Node, depth: Int) throws(ManglingError) {
        try mangleChildNodes(node, depth: depth + 1)
        append("WOy")
    }

    func mangleOutlinedConsume(_ node: Node, depth: Int) throws(ManglingError) {
        try mangleChildNodes(node, depth: depth + 1)
        append("WOe")
    }

    func mangleOutlinedRetain(_ node: Node, depth: Int) throws(ManglingError) {
        try mangleChildNodes(node, depth: depth + 1)
        append("WOr")
    }

    func mangleOutlinedRelease(_ node: Node, depth: Int) throws(ManglingError) {
        try mangleChildNodes(node, depth: depth + 1)
        append("WOs")
    }

    func mangleOutlinedDestroy(_ node: Node, depth: Int) throws(ManglingError) {
        try mangleChildNodes(node, depth: depth + 1)
        append("WOh")
    }

    func mangleOutlinedInitializeWithTake(_ node: Node, depth: Int) throws(ManglingError) {
        try mangleChildNodes(node, depth: depth + 1)
        append("WOb")
    }

    func mangleOutlinedInitializeWithCopy(_ node: Node, depth: Int) throws(ManglingError) {
        try mangleChildNodes(node, depth: depth + 1)
        append("WOc")
    }

    func mangleOutlinedAssignWithTake(_ node: Node, depth: Int) throws(ManglingError) {
        try mangleChildNodes(node, depth: depth + 1)
        append("WOd")
    }

    func mangleOutlinedAssignWithCopy(_ node: Node, depth: Int) throws(ManglingError) {
        try mangleChildNodes(node, depth: depth + 1)
        append("WOf")
    }

    func mangleOutlinedVariable(_ node: Node, depth: Int) throws(ManglingError) {
        append("Tv")
        if let index = node.index {
            mangleIndex(index)
        }
    }

    func mangleOutlinedEnumGetTag(_ node: Node, depth: Int) throws(ManglingError) {
        try mangleChildNodes(node, depth: depth + 1)
        append("WOg")
    }

    func mangleOutlinedEnumProjectDataForLoad(_ node: Node, depth: Int) throws(ManglingError) {
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

    func mangleOutlinedEnumTagStore(_ node: Node, depth: Int) throws(ManglingError) {
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
    func mangleOutlinedDestroyNoValueWitness(_ node: Node, depth: Int) throws(ManglingError) {
        try mangleChildNodes(node, depth: depth + 1)
        append("WOH")
    }

    func mangleOutlinedInitializeWithCopyNoValueWitness(_ node: Node, depth: Int) throws(ManglingError) {
        try mangleChildNodes(node, depth: depth + 1)
        append("WOC")
    }

    func mangleOutlinedAssignWithTakeNoValueWitness(_ node: Node, depth: Int) throws(ManglingError) {
        try mangleChildNodes(node, depth: depth + 1)
        append("WOD")
    }

    func mangleOutlinedAssignWithCopyNoValueWitness(_ node: Node, depth: Int) throws(ManglingError) {
        try mangleChildNodes(node, depth: depth + 1)
        append("WOF")
    }

    func mangleOutlinedBridgedMethod(_ node: Node, depth: Int) throws(ManglingError) {
        append("Te")
        append(node.text ?? "")
        append("_")
    }

    func mangleOutlinedReadOnlyObject(_ node: Node, depth: Int) throws(ManglingError) {
        append("Tv")
        if let index = node.index {
            mangleIndex(index)
        }
        append("r")
    }

    // MARK: - Pack Support (High Priority)

    func manglePack(_ node: Node, depth: Int) throws(ManglingError) {
        try mangleTypeList(node, depth: depth + 1)
        append("QP")
    }

    func manglePackElement(_ node: Node, depth: Int) throws(ManglingError) {
        try mangleChildNode(node, at: 0, depth: depth + 1)
        append("Qe")
        try mangleChildNode(node, at: 1, depth: depth + 1)
    }

    func manglePackElementLevel(_ node: Node, depth: Int) throws(ManglingError) {
        // PackElementLevel: just mangle the index
        if let index = node.index {
            mangleIndex(index)
        }
    }

    func manglePackExpansion(_ node: Node, depth: Int) throws(ManglingError) {
        try mangleChildNodes(node, depth: depth + 1)
        append("Qp")
    }

    func manglePackProtocolConformance(_ node: Node, depth: Int) throws(ManglingError) {
        try mangleAnyProtocolConformanceList(node[safeChild: 0], depth: depth + 1)
        append("HX")
    }

    func mangleSILPackDirect(_ node: Node, depth: Int) throws(ManglingError) {
        try mangleTypeList(node, depth: depth + 1)
        append("Qsd")
    }

    func mangleSILPackIndirect(_ node: Node, depth: Int) throws(ManglingError) {
        try mangleTypeList(node, depth: depth + 1)
        append("QSi")
    }

    // MARK: - Generic Specialization

    func mangleGenericSpecialization(_ node: Node, depth: Int) throws(ManglingError) {
        try mangleGenericSpecializationNode(node, specKind: "g", depth: depth)
    }

    func mangleGenericPartialSpecialization(_ node: Node, depth: Int) throws(ManglingError) {
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

    func mangleGenericSpecializationParam(_ node: Node, depth: Int) throws(ManglingError) {
        throw .unsupportedNodeKind(node)
    }

    func mangleFunctionSignatureSpecialization(_ node: Node, depth: Int) throws(ManglingError) {
        for param in node.children {
            if param.kind == .functionSignatureSpecializationParam, param.numberOfChildren > 0, let rawValue = try param[safeChild: 0].index, let kind = FunctionSigSpecializationParamKind(rawValue: rawValue) {
                switch kind {
                case .constantPropFunction,
                     .constantPropGlobal:
                    try mangleIdentifier(param[safeChild: 1], depth: depth + 1)
                case .constantPropString:
                    var textNd = try param[safeChild: 2]
                    let text = textNd.text
                    if let text, !text.isEmpty, Mangle.isDigit(text.first!) || text.first == "_" {
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

    func mangleGenericTypeParamDecl(_ node: Node, depth: Int) throws(ManglingError) {
        try mangleChildNodes(node, depth: depth + 1)
        append("fp")
    }

    func mangleDependentGenericParamCount(_ node: Node, depth: Int) throws(ManglingError) {
        throw .unsupportedNodeKind(node)
    }

    func mangleDependentGenericParamPackMarker(_ node: Node, depth: Int) throws(ManglingError) {
        // DependentGenericParamPackMarker: output "Rv" then mangle the param index
        guard node.numberOfChildren == 1,
              try node[safeChild: 0].kind == .type else {
            throw .invalidNodeStructure(node, message: "DependentGenericParamPackMarker needs Type child")
        }
        append("Rv")
        try mangleDependentGenericParamIndex(node[safeChild: 0][safeChild: 0])
    }

    func mangleDependentGenericParamValueMarker(_ node: Node, depth: Int) throws(ManglingError) {
        assert(node.numberOfChildren == 2)
        assert(node.children[0].children[0].kind == .dependentGenericParamType)
        assert(node.children[1].kind == .type)
        try mangleType(node[safeChild: 1], depth: depth + 1)
        append("RV")
        try mangleDependentGenericParamIndex(node[safeChild: 0][safeChild: 0])
    }

    // MARK: - Impl Function Type (High Priority)

    func mangleImplFunctionType(_ node: Node, depth: Int) throws(ManglingError) {
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
                append(child.index!)
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

    func mangleImplParameter(_ node: Node, depth: Int) throws(ManglingError) {
        // ImplParameter is handled inline in mangleImplFunctionType
        throw .invalidNodeStructure(node, message: "ImplParameter should be handled inline")
    }

    func mangleImplResult(_ node: Node, depth: Int) throws(ManglingError) {
        // ImplResult is handled inline in mangleImplFunctionType
        throw .invalidNodeStructure(node, message: "ImplResult should be handled inline")
    }

    func mangleImplYield(_ node: Node, depth: Int) throws(ManglingError) {
        throw .unsupportedNodeKind(node)
    }

    func mangleImplErrorResult(_ node: Node, depth: Int) throws(ManglingError) {
        throw .unsupportedNodeKind(node)
    }

    func mangleImplConvention(_ node: Node, depth: Int) throws(ManglingError) {
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

    func mangleImplFunctionConvention(_ node: Node, depth: Int) throws(ManglingError) {
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

    func mangleImplFunctionConventionName(_ node: Node, depth: Int) throws(ManglingError) {
        throw .unsupportedNodeKind(node)
    }

    func mangleImplFunctionAttribute(_ node: Node, depth: Int) throws(ManglingError) {
        throw .unsupportedNodeKind(node)
    }

    func mangleImplEscaping(_ node: Node, depth: Int) throws(ManglingError) {
        append("e")
    }

    func mangleImplDifferentiabilityKind(_ node: Node, depth: Int) throws(ManglingError) {
        if let index = node.index {
            append(index)
        }
    }

    func mangleImplCoroutineKind(_ node: Node, depth: Int) throws(ManglingError) {
        throw .unsupportedNodeKind(node)
    }

    func mangleImplParameterIsolated(_ node: Node, depth: Int) throws(ManglingError) {
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

    func mangleImplParameterSending(_ node: Node, depth: Int) throws(ManglingError) {
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

    func mangleImplParameterImplicitLeading(_ node: Node, depth: Int) throws(ManglingError) {
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

    func mangleImplSendingResult(_ node: Node, depth: Int) throws(ManglingError) {
        append("T")
        try mangleChildNodes(node, depth: depth + 1)
    }

    func mangleImplPatternSubstitutions(_ node: Node, depth: Int) throws(ManglingError) {
        throw .unsupportedNodeKind(node)
    }

    func mangleImplInvocationSubstitutions(_ node: Node, depth: Int) throws(ManglingError) {
        throw .unsupportedNodeKind(node)
    }

    // MARK: - Descriptor/Record Types (20+ methods)

    func mangleAccessibleFunctionRecord(_ node: Node, depth: Int) throws(ManglingError) {
        append("HF")
    }

    func mangleAnonymousDescriptor(_ node: Node, depth: Int) throws(ManglingError) {
        try mangle(node[safeChild: 0], depth: depth + 1)

        // Check if there's an identifier child
        if node.numberOfChildren == 1 {
            append("MXX")
        } else {
            try mangleIdentifier(node[safeChild: 1], depth: depth + 1)
            append("MXY")
        }
    }

    func mangleExtensionDescriptor(_ node: Node, depth: Int) throws(ManglingError) {
        try mangle(node[safeChild: 0], depth: depth + 1)
        append("MXE")
    }

    func mangleMethodDescriptor(_ node: Node, depth: Int) throws(ManglingError) {
        try mangleSingleChildNode(node, depth: depth + 1)
        append("Tq")
    }

    func mangleModuleDescriptor(_ node: Node, depth: Int) throws(ManglingError) {
        try mangle(node[safeChild: 0], depth: depth + 1)
        append("MXM")
    }

    func manglePropertyDescriptor(_ node: Node, depth: Int) throws(ManglingError) {
        try mangleSingleChildNode(node, depth: depth + 1)
        append("MV")
    }

    func mangleProtocolConformanceDescriptorRecord(_ node: Node, depth: Int) throws(ManglingError) {
        try mangleProtocolConformance(node[safeChild: 0], depth: depth + 1)

        append("Hc")
    }

    func mangleProtocolRequirementsBaseDescriptor(_ node: Node, depth: Int) throws(ManglingError) {
        try manglePureProtocol(node.firstChild, depth: depth + 1)
        append("TL")
    }

    func mangleProtocolSelfConformanceDescriptor(_ node: Node, depth: Int) throws(ManglingError) {
        try manglePureProtocol(node[safeChild: 0], depth: depth + 1)
        append("MS")
    }

    func mangleProtocolSelfConformanceWitnessTable(_ node: Node, depth: Int) throws(ManglingError) {
        try manglePureProtocol(node[safeChild: 0], depth: depth + 1)
        append("WS")
    }

    func mangleProtocolSymbolicReference(_ node: Node, depth: Int) throws(ManglingError) {
        // Symbolic reference - requires resolver
        throw .unsupportedNodeKind(node)
    }

    func mangleTypeSymbolicReference(_ node: Node, depth: Int) throws(ManglingError) {
        // Symbolic reference - requires resolver
        throw .unsupportedNodeKind(node)
    }

    func mangleObjectiveCProtocolSymbolicReference(_ node: Node, depth: Int) throws(ManglingError) {
        // Symbolic reference - requires resolver
        throw .unsupportedNodeKind(node)
    }

    // MARK: - Opaque Types (10 methods)

    func mangleOpaqueType(_ node: Node, depth: Int) throws(ManglingError) {
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

    func mangleOpaqueReturnType(_ node: Node, depth: Int) throws(ManglingError) {
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

    func mangleOpaqueReturnTypeOf(_ node: Node, depth: Int) throws(ManglingError) {
        try mangle(node[safeChild: 0], depth: depth + 1)
        append("QO")
    }

    func mangleOpaqueReturnTypeIndex(_ node: Node, depth: Int) throws(ManglingError) {
        throw .badNodeKind(node)
    }

    func mangleOpaqueReturnTypeParent(_ node: Node, depth: Int) throws(ManglingError) {
        throw .badNodeKind(node)
    }

    func mangleOpaqueTypeDescriptor(_ node: Node, depth: Int) throws(ManglingError) {
        try mangleSingleChildNode(node, depth: depth + 1)
        append("MQ")
    }

    func mangleOpaqueTypeDescriptorAccessor(_ node: Node, depth: Int) throws(ManglingError) {
        try mangleSingleChildNode(node, depth: depth + 1)
        append("Mg")
    }

    func mangleOpaqueTypeDescriptorAccessorImpl(_ node: Node, depth: Int) throws(ManglingError) {
        try mangleSingleChildNode(node, depth: depth + 1)
        append("Mh")
    }

    func mangleOpaqueTypeDescriptorAccessorKey(_ node: Node, depth: Int) throws(ManglingError) {
        try mangleSingleChildNode(node, depth: depth + 1)
        append("Mj")
    }

    func mangleOpaqueTypeDescriptorAccessorVar(_ node: Node, depth: Int) throws(ManglingError) {
        try mangleSingleChildNode(node, depth: depth + 1)
        append("Mk")
    }

    func mangleOpaqueTypeDescriptorRecord(_ node: Node, depth: Int) throws(ManglingError) {
        try mangleSingleChildNode(node, depth: depth + 1)
        append("Ho")
    }

    func mangleOpaqueTypeDescriptorSymbolicReference(_ node: Node, depth: Int) throws(ManglingError) {
        // Symbolic reference
        throw .unsupportedNodeKind(node)
    }

    // MARK: - Thunk Types (10+ methods)

    func mangleCurryThunk(_ node: Node, depth: Int) throws(ManglingError) {
        try mangleSingleChildNode(node, depth: depth + 1)
        append("Tc")
    }

    func mangleDispatchThunk(_ node: Node, depth: Int) throws(ManglingError) {
        try mangleSingleChildNode(node, depth: depth + 1)
        append("Tj")
    }

    func mangleReabstractionThunk(_ node: Node, depth: Int) throws(ManglingError) {
        // IMPORTANT: Process children in REVERSE order
        try mangleChildNodesReversed(node, depth: depth + 1)
        append("Tr")
    }

    func mangleReabstractionThunkHelper(_ node: Node, depth: Int) throws(ManglingError) {
        // IMPORTANT: Process children in REVERSE order
        try mangleChildNodesReversed(node, depth: depth + 1)
        append("TR")
    }

    func mangleReabstractionThunkHelperWithSelf(_ node: Node, depth: Int) throws(ManglingError) {
        // IMPORTANT: Process children in REVERSE order
        try mangleChildNodesReversed(node, depth: depth + 1)
        append("Ty")
    }

    func mangleReabstractionThunkHelperWithGlobalActor(_ node: Node, depth: Int) throws(ManglingError) {
        // This one uses NORMAL order (not reversed)
        try mangleChildNodes(node, depth: depth + 1)
        append("TU")
    }

    func manglePartialApplyForwarder(_ node: Node, depth: Int) throws(ManglingError) {
        try mangleChildNodesReversed(node, depth: depth + 1)
        append("TA")
    }

    func manglePartialApplyObjCForwarder(_ node: Node, depth: Int) throws(ManglingError) {
        try mangleChildNodesReversed(node, depth: depth + 1)
        append("Ta")
    }

    // MARK: - Macro Support (11 methods)

    func mangleMacro(_ node: Node, depth: Int) throws(ManglingError) {
        try mangleChildNodes(node, depth: depth + 1)
        append("fm")
    }

    func mangleMacroExpansionLoc(_ node: Node, depth: Int) throws(ManglingError) {
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

    func mangleMacroExpansionUniqueName(_ node: Node, depth: Int) throws(ManglingError) {
        try mangleChildNode(node, at: 0, depth: depth + 1)

        // Handle optional private discriminator (child 3)
        if let privateDiscriminator = try? node[safeChild: 3] {
            try mangle(privateDiscriminator, depth: depth + 1)
        }

        try mangleChildNode(node, at: 1, depth: depth + 1)

        append("fMu")

        try mangleChildNode(node, at: 2, depth: depth + 1)
    }

    func mangleFreestandingMacroExpansion(_ node: Node, depth: Int) throws(ManglingError) {
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

    func mangleAccessorAttachedMacroExpansion(_ node: Node, depth: Int) throws(ManglingError) {
        try mangleChildNodes(node, depth: depth + 1)
        append("fMa")
    }

    func mangleMemberAttributeAttachedMacroExpansion(_ node: Node, depth: Int) throws(ManglingError) {
        try mangleChildNodes(node, depth: depth + 1)
        append("fMA")
    }

    func mangleMemberAttachedMacroExpansion(_ node: Node, depth: Int) throws(ManglingError) {
        try mangleChildNodes(node, depth: depth + 1)
        append("fMm")
    }

    func manglePeerAttachedMacroExpansion(_ node: Node, depth: Int) throws(ManglingError) {
        try mangleChildNodes(node, depth: depth + 1)
        append("fMp")
    }

    func mangleConformanceAttachedMacroExpansion(_ node: Node, depth: Int) throws(ManglingError) {
        try mangleChildNodes(node, depth: depth + 1)
        append("fMc")
    }

    func mangleExtensionAttachedMacroExpansion(_ node: Node, depth: Int) throws(ManglingError) {
        try mangleChildNodes(node, depth: depth + 1)
        append("fMe")
    }

    func mangleBodyAttachedMacroExpansion(_ node: Node, depth: Int) throws(ManglingError) {
        try mangleChildNodes(node, depth: depth + 1)
        append("fMb")
    }

    // MARK: - Additional Missing Node Handlers (109 methods)

    // MARK: - Simple Markers (20 methods)

    func mangleAsyncFunctionPointer(_ node: Node, depth: Int) throws(ManglingError) {
        append("Tu")
    }

    func mangleAsyncRemoved(_ node: Node, depth: Int) throws(ManglingError) {
        append("a")
    }

    func mangleBackDeploymentFallback(_ node: Node, depth: Int) throws(ManglingError) {
        append("TwB")
    }

    func mangleBackDeploymentThunk(_ node: Node, depth: Int) throws(ManglingError) {
        append("Twb")
    }

    func mangleBuiltinTupleType(_ node: Node, depth: Int) throws(ManglingError) {
        append("BT")
    }

    func mangleConcurrentFunctionType(_ node: Node, depth: Int) throws(ManglingError) {
        append("Yb")
    }

    func mangleConstrainedExistentialSelf(_ node: Node, depth: Int) throws(ManglingError) {
        append("s")
    }

    func mangleCoroFunctionPointer(_ node: Node, depth: Int) throws(ManglingError) {
        append("Twc")
    }

    func mangleDefaultOverride(_ node: Node, depth: Int) throws(ManglingError) {
        append("Twd")
    }

    func mangleDirectMethodReferenceAttribute(_ node: Node, depth: Int) throws(ManglingError) {
        append("Td")
    }

    func mangleDynamicAttribute(_ node: Node, depth: Int) throws(ManglingError) {
        append("TD")
    }

    func mangleHasSymbolQuery(_ node: Node, depth: Int) throws(ManglingError) {
        append("TwS")
    }

    func mangleImplErasedIsolation(_ node: Node, depth: Int) throws(ManglingError) {
        append("A")
    }

    func mangleIsSerialized(_ node: Node, depth: Int) throws(ManglingError) {
        append("q")
    }

    func mangleIsolatedAnyFunctionType(_ node: Node, depth: Int) throws(ManglingError) {
        append("YA")
    }

    func mangleMergedFunction(_ node: Node, depth: Int) throws(ManglingError) {
        append("Tm")
    }

    func mangleNonIsolatedCallerFunctionType(_ node: Node, depth: Int) throws(ManglingError) {
        append("YC")
    }

    func mangleNonObjCAttribute(_ node: Node, depth: Int) throws(ManglingError) {
        append("TO")
    }

    func mangleObjCAttribute(_ node: Node, depth: Int) throws(ManglingError) {
        append("To")
    }

    func mangleSendingResultFunctionType(_ node: Node, depth: Int) throws(ManglingError) {
        append("YT")
    }

    // MARK: - Child + Code (15 methods)

    func mangleCompileTimeConst(_ node: Node, depth: Int) throws(ManglingError) {
        try mangleSingleChildNode(node, depth: depth + 1)
        append("Yt")
    }

    func mangleConstValue(_ node: Node, depth: Int) throws(ManglingError) {
        try mangleSingleChildNode(node, depth: depth + 1)
        append("Yg")
    }

    func mangleFullObjCResilientClassStub(_ node: Node, depth: Int) throws(ManglingError) {
        try mangleSingleChildNode(node, depth: depth + 1)
        append("Mt")
    }

    func mangleIVarDestroyer(_ node: Node, depth: Int) throws(ManglingError) {
        try mangleSingleChildNode(node, depth: depth + 1)
        append("fE")
    }

    func mangleIVarInitializer(_ node: Node, depth: Int) throws(ManglingError) {
        try mangleSingleChildNode(node, depth: depth + 1)
        append("fe")
    }

    func mangleIsolated(_ node: Node, depth: Int) throws(ManglingError) {
        try mangleSingleChildNode(node, depth: depth + 1)
        append("Yi")
    }

    func mangleMetadataInstantiationCache(_ node: Node, depth: Int) throws(ManglingError) {
        try mangleSingleChildNode(node, depth: depth + 1)
        append("MK")
    }

    func mangleMethodLookupFunction(_ node: Node, depth: Int) throws(ManglingError) {
        try mangleSingleChildNode(node, depth: depth + 1)
        append("Mu")
    }

    func mangleNoDerivative(_ node: Node, depth: Int) throws(ManglingError) {
        try mangleSingleChildNode(node, depth: depth + 1)
        append("Yk")
    }

    func mangleNoncanonicalSpecializedGenericTypeMetadataCache(_ node: Node, depth: Int) throws(ManglingError) {
        try mangleSingleChildNode(node, depth: depth + 1)
        append("MJ")
    }

    func mangleObjCMetadataUpdateFunction(_ node: Node, depth: Int) throws(ManglingError) {
        try mangleSingleChildNode(node, depth: depth + 1)
        append("MU")
    }

    func mangleObjCResilientClassStub(_ node: Node, depth: Int) throws(ManglingError) {
        try mangleSingleChildNode(node, depth: depth + 1)
        append("Ms")
    }

    func mangleSILBoxType(_ node: Node, depth: Int) throws(ManglingError) {
        try mangleSingleChildNode(node, depth: depth + 1)
        append("Xb")
    }

    func mangleSILThunkIdentity(_ node: Node, depth: Int) throws(ManglingError) {
        try mangleSingleChildNode(node, depth: depth + 1)
        append("TTI")
    }

    func mangleSending(_ node: Node, depth: Int) throws(ManglingError) {
        try mangleSingleChildNode(node, depth: depth + 1)
        append("Yu")
    }

    // MARK: - All Children + Code (9 methods)

    func mangleBuiltinFixedArray(_ node: Node, depth: Int) throws(ManglingError) {
        try mangleChildNodes(node, depth: depth + 1)
        append("BV")
    }

    func mangleCoroutineContinuationPrototype(_ node: Node, depth: Int) throws(ManglingError) {
        try mangleChildNodes(node, depth: depth + 1)
        append("TC")
    }

    func mangleDeallocator(_ node: Node, depth: Int) throws(ManglingError) {
        try mangleChildNodes(node, depth: depth + 1)
        append("fD")
    }

    func mangleGlobalActorFunctionType(_ node: Node, depth: Int) throws(ManglingError) {
        try mangleChildNodes(node, depth: depth + 1)
        append("Yc")
    }

    func mangleGlobalVariableOnceFunction(_ node: Node, depth: Int) throws(ManglingError) {
        try mangleChildNodes(node, depth: depth + 1)
        append("WZ")
    }

    func mangleGlobalVariableOnceToken(_ node: Node, depth: Int) throws(ManglingError) {
        try mangleChildNodes(node, depth: depth + 1)
        append("Wz")
    }

    func mangleIsolatedDeallocator(_ node: Node, depth: Int) throws(ManglingError) {
        try mangleChildNodes(node, depth: depth + 1)
        append("fZ")
    }

    func mangleTypedThrowsAnnotation(_ node: Node, depth: Int) throws(ManglingError) {
        try mangleChildNodes(node, depth: depth + 1)
        append("YK")
    }

    func mangleVTableThunk(_ node: Node, depth: Int) throws(ManglingError) {
        try mangleChildNodes(node, depth: depth + 1)
        append("TV")
    }

    // MARK: - AbstractStorage Delegates (13 methods)

    func mangleGlobalGetter(_ node: Node, depth: Int) throws(ManglingError) {
        try mangleAbstractStorage(node.firstChild, accessorCode: "G", depth: depth + 1)
    }

    func mangleInitAccessor(_ node: Node, depth: Int) throws(ManglingError) {
        try mangleAbstractStorage(node.firstChild, accessorCode: "i", depth: depth + 1)
    }

    func mangleMaterializeForSet(_ node: Node, depth: Int) throws(ManglingError) {
        guard node.children.count >= 1 else {
            throw .invalidNodeStructure(node, message: "MaterializeForSet needs at least 1 child")
        }
        try mangleAbstractStorage(node.firstChild, accessorCode: "m", depth: depth + 1)
    }

    func mangleModify2Accessor(_ node: Node, depth: Int) throws(ManglingError) {
        guard node.children.count >= 1 else {
            throw .invalidNodeStructure(node, message: "Modify2Accessor needs at least 1 child")
        }
        try mangleAbstractStorage(node.firstChild, accessorCode: "x", depth: depth + 1)
    }

    func mangleNativeOwningAddressor(_ node: Node, depth: Int) throws(ManglingError) {
        guard node.children.count >= 1 else {
            throw .invalidNodeStructure(node, message: "NativeOwningAddressor needs at least 1 child")
        }
        try mangleAbstractStorage(node.firstChild, accessorCode: "lo", depth: depth + 1)
    }

    func mangleNativeOwningMutableAddressor(_ node: Node, depth: Int) throws(ManglingError) {
        guard node.children.count >= 1 else {
            throw .invalidNodeStructure(node, message: "NativeOwningMutableAddressor needs at least 1 child")
        }
        try mangleAbstractStorage(node.firstChild, accessorCode: "ao", depth: depth + 1)
    }

    func mangleNativePinningAddressor(_ node: Node, depth: Int) throws(ManglingError) {
        guard node.children.count >= 1 else {
            throw .invalidNodeStructure(node, message: "NativePinningAddressor needs at least 1 child")
        }
        try mangleAbstractStorage(node.firstChild, accessorCode: "lp", depth: depth + 1)
    }

    func mangleNativePinningMutableAddressor(_ node: Node, depth: Int) throws(ManglingError) {
        guard node.children.count >= 1 else {
            throw .invalidNodeStructure(node, message: "NativePinningMutableAddressor needs at least 1 child")
        }
        try mangleAbstractStorage(node.firstChild, accessorCode: "aP", depth: depth + 1)
    }

    func mangleOwningAddressor(_ node: Node, depth: Int) throws(ManglingError) {
        guard node.children.count >= 1 else {
            throw .invalidNodeStructure(node, message: "OwningAddressor needs at least 1 child")
        }
        try mangleAbstractStorage(node.firstChild, accessorCode: "lO", depth: depth + 1)
    }

    func mangleOwningMutableAddressor(_ node: Node, depth: Int) throws(ManglingError) {
        guard node.children.count >= 1 else {
            throw .invalidNodeStructure(node, message: "OwningMutableAddressor needs at least 1 child")
        }
        try mangleAbstractStorage(node.firstChild, accessorCode: "aO", depth: depth + 1)
    }

    func mangleRead2Accessor(_ node: Node, depth: Int) throws(ManglingError) {
        guard node.children.count >= 1 else {
            throw .invalidNodeStructure(node, message: "Read2Accessor needs at least 1 child")
        }
        try mangleAbstractStorage(node.firstChild, accessorCode: "y", depth: depth + 1)
    }

    func mangleUnsafeAddressor(_ node: Node, depth: Int) throws(ManglingError) {
        guard node.children.count >= 1 else {
            throw .invalidNodeStructure(node, message: "UnsafeAddressor needs at least 1 child")
        }
        try mangleAbstractStorage(node.firstChild, accessorCode: "lu", depth: depth + 1)
    }

    func mangleUnsafeMutableAddressor(_ node: Node, depth: Int) throws(ManglingError) {
        guard node.children.count >= 1 else {
            throw .invalidNodeStructure(node, message: "UnsafeMutableAddressor needs at least 1 child")
        }
        try mangleAbstractStorage(node.firstChild, accessorCode: "au", depth: depth + 1)
    }

    // MARK: - Node Index Methods (8 methods)

    func mangleAutoDiffFunctionKind(_ node: Node, depth: Int) throws(ManglingError) {
        guard let index = node.index else {
            throw .invalidNodeStructure(node, message: "AutoDiffFunctionKind has no index")
        }
        append(index)
    }

    func mangleDependentConformanceIndex(_ node: Node, depth: Int) throws(ManglingError) {
        let indexValue = node.index != nil ? node.index! + 2 : 1
        mangleIndex(indexValue)
    }

    func mangleDifferentiableFunctionType(_ node: Node, depth: Int) throws(ManglingError) {
        guard let index = node.index else {
            throw .invalidNodeStructure(node, message: "DifferentiableFunctionType has no index")
        }
        append("Yj")
        append(index)
    }

    func mangleDirectness(_ node: Node, depth: Int) throws(ManglingError) {
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

    func mangleDroppedArgument(_ node: Node, depth: Int) throws(ManglingError) {
        guard let index = node.index else {
            throw .invalidNodeStructure(node, message: "DroppedArgument has no index")
        }
        append("t")
        if index > 0 {
            append(index - 1)
        }
    }

    func mangleInteger(_ node: Node, depth: Int) throws(ManglingError) {
        guard let index = node.index else {
            throw .invalidNodeStructure(node, message: "Integer has no index")
        }
        append("$")
        mangleIndex(index)
    }

    func mangleNegativeInteger(_ node: Node, depth: Int) throws(ManglingError) {
        guard let index = node.index else {
            throw .invalidNodeStructure(node, message: "NegativeInteger has no index")
        }
        append("$n")
        mangleIndex(0 &- index)
    }

    func mangleSpecializationPassID(_ node: Node, depth: Int) throws(ManglingError) {
        guard let index = node.index else {
            throw .invalidNodeStructure(node, message: "SpecializationPassID has no index")
        }
        append(index)
    }

    // MARK: - Node Text Methods (3 methods)

    func mangleClangType(_ node: Node, depth: Int) throws(ManglingError) {
        guard let text = node.text else {
            throw .invalidNodeStructure(node, message: "ClangType has no text")
        }
        append(text.count.description)
        append(text)
    }

    func mangleIndexSubset(_ node: Node, depth: Int) throws(ManglingError) {
        guard let text = node.text else {
            throw .invalidNodeStructure(node, message: "IndexSubset has no text")
        }
        append(text)
    }

    func mangleMetatypeRepresentation(_ node: Node, depth: Int) throws(ManglingError) {
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

    func mangleCFunctionPointer(_ node: Node, depth: Int) throws(ManglingError) {
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

    func mangleDependentAssociatedTypeRef(_ node: Node, depth: Int) throws(ManglingError) {
        try mangleIdentifier(node.firstChild, depth: depth)

        if node.numberOfChildren > 1 {
            try mangleChildNode(node, at: 1, depth: depth + 1)
        }
    }

    func mangleDependentProtocolConformanceOpaque(_ node: Node, depth: Int) throws(ManglingError) {
        try mangleAnyProtocolConformance(node[safeChild: 0], depth: depth + 1)

        try mangleType(node[safeChild: 1], depth: depth + 1)

        append("HO")
    }

    func mangleEscapingObjCBlock(_ node: Node, depth: Int) throws(ManglingError) {
        try mangleChildNodesReversed(node, depth: depth + 1)
        append("XL")
    }

    func mangleExtendedExistentialTypeShape(_ node: Node, depth: Int) throws(ManglingError) {
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

    func mangleObjCAsyncCompletionHandlerImpl(_ node: Node, depth: Int) throws(ManglingError) {
        try mangleChildNode(node, at: 0, depth: depth + 1)

        try mangleChildNode(node, at: 1, depth: depth + 1)

        if node.numberOfChildren == 4 {
            try mangleChildNode(node, at: 3, depth: depth + 1)
        }

        append("Tz")
        try mangleChildNode(node, at: 2, depth: depth + 1)
    }

    func mangleObjCBlock(_ node: Node, depth: Int) throws(ManglingError) {
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

    func mangleRelatedEntityDeclName(_ node: Node, depth: Int) throws(ManglingError) {
        try mangleChildNode(node, at: 1, depth: depth + 1)

        guard let kindText = try node.firstChild.text, kindText.count == 1 else {
            throw .invalidNodeStructure(node, message: "RelatedEntityDeclName kind must be single character")
        }

        append("L")
        append(kindText)
    }

    func mangleSugaredDictionary(_ node: Node, depth: Int) throws(ManglingError) {
        try mangleType(node[safeChild: 0], depth: depth + 1)

        try mangleType(node[safeChild: 1], depth: depth + 1)

        append("XSD")
    }

    func mangleConstrainedExistential(_ node: Node, depth: Int) throws(ManglingError) {
        try mangleChildNode(node, at: 0, depth: depth + 1)

        try mangleChildNode(node, at: 1, depth: depth + 1)

        append("XP")
    }

    func mangleDependentGenericInverseConformanceRequirement(_ node: Node, depth: Int) throws(ManglingError) {
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

    func mangleSugaredArray(_ node: Node, depth: Int) throws(ManglingError) {
        try mangleType(node[safeChild: 0], depth: depth + 1)
        append("XSa")
    }

    func mangleSugaredOptional(_ node: Node, depth: Int) throws(ManglingError) {
        try mangleType(node[safeChild: 0], depth: depth + 1)
        append("XSq")
    }

    func mangleSugaredParen(_ node: Node, depth: Int) throws(ManglingError) {
        try mangleType(node[safeChild: 0], depth: depth + 1)
        append("XSp")
    }

    // MARK: - Iterator/Helper Delegates (5+ methods)

    func mangleAutoDiffFunction(_ node: Node, depth: Int) throws(ManglingError) {
        try mangleAutoDiffFunctionOrSimpleThunk(node, op: "TJ", depth: depth + 1)
    }

    func mangleAutoDiffDerivativeVTableThunk(_ node: Node, depth: Int) throws(ManglingError) {
        try mangleAutoDiffFunctionOrSimpleThunk(node, op: "TJV", depth: depth + 1)
    }

    private func mangleAutoDiffFunctionOrSimpleThunk(_ node: Node, op: String, depth: Int) throws(ManglingError) {
        var childIt = node.children.makeIterator()

        while let next = childIt.next(), next.kind != .autoDiffFunctionKind {
            try mangle(next, depth: depth + 1)
        }

        append(op)

        if let next = childIt.next() {
            try mangle(next, depth: depth + 1)
        }
        if let next = childIt.next() {
            try mangle(next, depth: depth + 1)
        }
        append("p")
        if let next = childIt.next() {
            try mangle(next, depth: depth + 1)
        }
        append("r")
    }

    func mangleAutoDiffSubsetParametersThunk(_ node: Node, depth: Int) throws(ManglingError) {
        var childIt = node.children.makeIterator()

        while let next = childIt.next(), next.kind != .autoDiffFunctionKind {
            try mangle(next, depth: depth + 1)
        }

        append("TJS")

        if let next = childIt.next() {
            try mangle(next, depth: depth + 1)
        }
        if let next = childIt.next() {
            try mangle(next, depth: depth + 1)
        }
        append("p")
        if let next = childIt.next() {
            try mangle(next, depth: depth + 1)
        }
        append("r")
        if let next = childIt.next() {
            try mangle(next, depth: depth + 1)
        }
        append("P")
    }

    func mangleDifferentiabilityWitness(_ node: Node, depth: Int) throws(ManglingError) {
        var childIt = node.children.makeIterator()

        while let next = childIt.next(), next.kind != .index {
            try mangle(next, depth: depth + 1)
        }

        append("WJ")

        if let last = node.children.last, last.kind == .dependentGenericSignature {
            try mangle(last, depth: depth + 1)
        }

        if let next = childIt.next() {
            try mangle(next, depth: depth + 1)
        }
        append("p")
        if let next = childIt.next() {
            try mangle(next, depth: depth + 1)
        }
        append("r")
    }

    func mangleGlobalVariableOnceDeclList(_ node: Node, depth: Int) throws(ManglingError) {
        for child in node.children {
            try mangle(child, depth: depth + 1)
            append("_")
        }
    }

    func mangleKeyPathThunkHelper(_ node: Node, op: String, depth: Int) throws(ManglingError) {
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

    func mangleKeyPathGetterThunkHelper(_ node: Node, depth: Int) throws(ManglingError) {
        try mangleKeyPathThunkHelper(node, op: "TK", depth: depth + 1)
    }

    func mangleKeyPathSetterThunkHelper(_ node: Node, depth: Int) throws(ManglingError) {
        try mangleKeyPathThunkHelper(node, op: "Tk", depth: depth + 1)
    }

    func mangleKeyPathEqualsThunkHelper(_ node: Node, depth: Int) throws(ManglingError) {
        try mangleKeyPathThunkHelper(node, op: "TH", depth: depth + 1)
    }

    func mangleKeyPathHashThunkHelper(_ node: Node, depth: Int) throws(ManglingError) {
        try mangleKeyPathThunkHelper(node, op: "Th", depth: depth + 1)
    }

    func mangleKeyPathAppliedMethodThunkHelper(_ node: Node, depth: Int) throws(ManglingError) {
        try mangleKeyPathThunkHelper(node, op: "TkMA", depth: depth + 1)
    }

    // MARK: - Pseudo/Delegate Methods (3 methods)

    func mangleDependentPseudogenericSignature(_ node: Node, depth: Int) throws(ManglingError) {
        try mangleDependentGenericSignature(node, depth: depth + 1)
    }

    func mangleInlinedGenericFunction(_ node: Node, depth: Int) throws(ManglingError) {
        try mangleGenericSpecializationNode(node, specKind: "i", depth: depth + 1)
    }

    func mangleUniquable(_ node: Node, depth: Int) throws(ManglingError) {
        try mangle(node[safeChild: 0], depth: depth + 1)
        append("Mq")
    }

    // MARK: - Special Cases

    func mangleDefaultArgumentInitializer(_ node: Node, depth: Int) throws(ManglingError) {
        try mangleChildNode(node, at: 0, depth: depth + 1)

        append("fA")

        try mangleChildNode(node, at: 1, depth: depth + 1)
    }

    func mangleSymbolicExtendedExistentialType(_ node: Node, depth: Int) throws(ManglingError) {
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

    func mangleSILBoxTypeWithLayout(_ node: Node, depth: Int) throws(ManglingError) {
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

    func mangleAsyncAwaitResumePartialFunction(_ node: Node, depth: Int) throws(ManglingError) {
        append("TQ")
        try mangleChildNode(node, at: 0, depth: depth + 1)
    }

    // MARK: - Error/Unsupported Methods (7 methods)

    func mangleAccessorFunctionReference(_ node: Node, depth: Int) throws(ManglingError) {
        throw .unsupportedNodeKind(node)
    }

    func mangleIndex(_ node: Node, depth: Int) throws(ManglingError) {
        // Handled inline elsewhere
        throw .unsupportedNodeKind(node)
    }

    func mangleUnknownIndex(_ node: Node, depth: Int) throws(ManglingError) {
        // Handled inline elsewhere
        throw .unsupportedNodeKind(node)
    }

    func mangleSILBoxImmutableField(_ node: Node, depth: Int) throws(ManglingError) {
        throw .unsupportedNodeKind(node)
    }

    func mangleSILBoxLayout(_ node: Node, depth: Int) throws(ManglingError) {
        throw .unsupportedNodeKind(node)
    }

    func mangleSILBoxMutableField(_ node: Node, depth: Int) throws(ManglingError) {
        throw .unsupportedNodeKind(node)
    }

    func mangleVTableAttribute(_ node: Node, depth: Int) throws(ManglingError) {
        throw .unsupportedNodeKind(node)
    }

    // MARK: - Additional Missing Methods (17 methods)

    func mangleAsyncSuspendResumePartialFunction(_ node: Node, depth: Int) throws(ManglingError) {
        append("TY")
        try mangleChildNode(node, at: 0, depth: depth + 1)
    }

    func mangleDependentProtocolConformanceRoot(_ node: Node, depth: Int) throws(ManglingError) {
        try mangleType(node[safeChild: 0], depth: depth + 1)

        try manglePureProtocol(node[safeChild: 1], depth: depth + 1)

        append("HD")
        try mangleDependentConformanceIndex(node[safeChild: 2], depth: depth + 1)
    }

    func mangleDependentProtocolConformanceInherited(_ node: Node, depth: Int) throws(ManglingError) {
        try mangleAnyProtocolConformance(node[safeChild: 0], depth: depth + 1)

        try manglePureProtocol(node[safeChild: 1], depth: depth + 1)

        append("HI")
        try mangleDependentConformanceIndex(node[safeChild: 2], depth: depth + 1)
    }

    func mangleDependentProtocolConformanceAssociated(_ node: Node, depth: Int) throws(ManglingError) {
        try mangleAnyProtocolConformance(node[safeChild: 0], depth: depth + 1)

        try mangleDependentAssociatedConformance(node[safeChild: 1], depth: depth + 1)

        append("HA")
        try mangleDependentConformanceIndex(node[safeChild: 2], depth: depth + 1)
    }

    func mangleDistributedAccessor(_ node: Node, depth: Int) throws(ManglingError) {
        append("TF")
    }

    func mangleDistributedThunk(_ node: Node, depth: Int) throws(ManglingError) {
        append("TE")
    }

    func mangleDynamicallyReplaceableFunctionImpl(_ node: Node, depth: Int) throws(ManglingError) {
        append("TI")
    }

    func mangleDynamicallyReplaceableFunctionKey(_ node: Node, depth: Int) throws(ManglingError) {
        append("Tx")
    }

    func mangleDynamicallyReplaceableFunctionVar(_ node: Node, depth: Int) throws(ManglingError) {
        append("TX")
    }

    func mangleGenericPartialSpecializationNotReAbstracted(_ node: Node, depth: Int) throws(ManglingError) {
        try mangleGenericPartialSpecialization(node, depth: depth + 1)
    }

    func mangleGenericSpecializationInResilienceDomain(_ node: Node, depth: Int) throws(ManglingError) {
        try mangleGenericSpecializationNode(node, specKind: "B", depth: depth + 1)
    }

    func mangleGenericSpecializationNotReAbstracted(_ node: Node, depth: Int) throws(ManglingError) {
        try mangleGenericSpecializationNode(node, specKind: "G", depth: depth + 1)
    }

    func mangleGenericSpecializationPrespecialized(_ node: Node, depth: Int) throws(ManglingError) {
        try mangleGenericSpecializationNode(node, specKind: "s", depth: depth + 1)
    }

    func mangleImplParameterResultDifferentiability(_ node: Node, depth: Int) throws(ManglingError) {
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

    func manglePropertyWrapperBackingInitializer(_ node: Node, depth: Int) throws(ManglingError) {
        try mangleChildNodes(node, depth: depth + 1)
        append("fP")
    }

    func manglePropertyWrapperInitFromProjectedValue(_ node: Node, depth: Int) throws(ManglingError) {
        try mangleChildNodes(node, depth: depth + 1)
        append("fW")
    }

    // MARK: - Additional 36 Missing Methods (Final Batch)

    /// Simple methods - just mangling child nodes + code
    func mangleDefaultAssociatedConformanceAccessor(_ node: Node, depth: Int) throws(ManglingError) {
        try mangle(node[safeChild: 0], depth: depth + 1)
        try mangle(node[safeChild: 1], depth: depth + 1)
        try manglePureProtocol(node[safeChild: 2], depth: depth + 1)
        append("TN")
    }

    func mangleDefaultAssociatedTypeMetadataAccessor(_ node: Node, depth: Int) throws(ManglingError) {
        try mangleChildNodes(node, depth: depth + 1)
        append("TM")
    }

    func mangleAssociatedTypeWitnessTableAccessor(_ node: Node, depth: Int) throws(ManglingError) {
        try mangleChildNodes(node, depth: depth + 1)
        append("WT")
    }

    func manglePredefinedObjCAsyncCompletionHandlerImpl(_ node: Node, depth: Int) throws(ManglingError) {
        try mangleChildNodes(node, depth: depth + 1)
        append("TZ")
    }

    func mangleLazyProtocolWitnessTableAccessor(_ node: Node, depth: Int) throws(ManglingError) {
        try mangleChildNodes(node, depth: depth + 1)
        append("Wl")
    }

    func mangleLazyProtocolWitnessTableCacheVariable(_ node: Node, depth: Int) throws(ManglingError) {
        try mangleChildNodes(node, depth: depth + 1)
        append("WL")
    }

    func mangleProtocolConformanceRefInTypeModule(_ node: Node, depth: Int) throws(ManglingError) {
        try manglePureProtocol(node[safeChild: 0], depth: depth + 1)
        append("HP")
    }

    func mangleProtocolConformanceRefInProtocolModule(_ node: Node, depth: Int) throws(ManglingError) {
        try manglePureProtocol(node[safeChild: 0], depth: depth + 1)
        append("Hp")
    }

    func mangleProtocolConformanceRefInOtherModule(_ node: Node, depth: Int) throws(ManglingError) {
        try manglePureProtocol(node[safeChild: 0], depth: depth + 1)
        try mangleChildNode(node, at: 1, depth: depth + 1)
    }

    func mangleTypeMetadataInstantiationFunction(_ node: Node, depth: Int) throws(ManglingError) {
        try mangleSingleChildNode(node, depth: depth + 1)
        append("Mi")
    }

    func mangleTypeMetadataSingletonInitializationCache(_ node: Node, depth: Int) throws(ManglingError) {
        try mangleSingleChildNode(node, depth: depth + 1)
        append("Ml")
    }

    func mangleReflectionMetadataBuiltinDescriptor(_ node: Node, depth: Int) throws(ManglingError) {
        try mangleSingleChildNode(node, depth: depth + 1)
        append("MB")
    }

    func mangleReflectionMetadataFieldDescriptor(_ node: Node, depth: Int) throws(ManglingError) {
        try mangleSingleChildNode(node, depth: depth + 1)
        append("MF")
    }

    func mangleReflectionMetadataAssocTypeDescriptor(_ node: Node, depth: Int) throws(ManglingError) {
        try mangleSingleChildNode(node, depth: depth + 1)
        append("MA")
    }

    func mangleReflectionMetadataSuperclassDescriptor(_ node: Node, depth: Int) throws(ManglingError) {
        try mangleSingleChildNode(node, depth: depth + 1)
        append("MC")
    }

    func mangleOutlinedInitializeWithTakeNoValueWitness(_ node: Node, depth: Int) throws(ManglingError) {
        try mangleChildNodes(node, depth: depth + 1)
        append("WOB")
    }

    func mangleSugaredInlineArray(_ node: Node, depth: Int) throws(ManglingError) {
        try mangleType(node[safeChild: 0], depth: depth + 1)
        try mangleType(node[safeChild: 1], depth: depth + 1)
        append("XSA")
    }

    func mangleCanonicalSpecializedGenericMetaclass(_ node: Node, depth: Int) throws(ManglingError) {
        try mangleChildNodes(node, depth: depth + 1)
        append("MM")
    }

    func mangleCanonicalSpecializedGenericTypeMetadataAccessFunction(_ node: Node, depth: Int) throws(ManglingError) {
        try mangleSingleChildNode(node, depth: depth + 1)
        append("Mb")
    }

    func mangleNoncanonicalSpecializedGenericTypeMetadata(_ node: Node, depth: Int) throws(ManglingError) {
        try mangleSingleChildNode(node, depth: depth + 1)
        append("MN")
    }

    func mangleCanonicalPrespecializedGenericTypeCachingOnceToken(_ node: Node, depth: Int) throws(ManglingError) {
        try mangleSingleChildNode(node, depth: depth + 1)
        append("Mz")
    }

    func mangleAutoDiffSelfReorderingReabstractionThunk(_ node: Node, depth: Int) throws(ManglingError) {
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

    func mangleKeyPathUnappliedMethodThunkHelper(_ node: Node, depth: Int) throws(ManglingError) {
        try mangleKeyPathThunkHelper(node, op: "Tkmu", depth: depth + 1)
    }

    /// Complex methods with special logic
    func mangleDependentGenericConformanceRequirement(_ node: Node, depth: Int) throws(ManglingError) {
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

    func mangleDependentGenericSameTypeRequirement(_ node: Node, depth: Int) throws(ManglingError) {
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

    func mangleDependentGenericSameShapeRequirement(_ node: Node, depth: Int) throws(ManglingError) {
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

    func mangleDependentGenericLayoutRequirement(_ node: Node, depth: Int) throws(ManglingError) {
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

    func mangleConstrainedExistentialRequirementList(_ node: Node, depth: Int) throws(ManglingError) {
        guard node.children.count > 0 else {
            throw .invalidNodeStructure(node, message: "ConstrainedExistentialRequirementList must have children")
        }

        var firstElem = true
        for i in 0 ..< node.numberOfChildren {
            try mangleChildNode(node, at: i, depth: depth + 1)
            mangleListSeparator(&firstElem)
        }
    }

    func mangleFunctionSignatureSpecializationReturn(_ node: Node, depth: Int) throws(ManglingError) {
        try mangleFunctionSignatureSpecializationParam(node, depth: depth + 1)
    }

    func mangleFunctionSignatureSpecializationParam(_ node: Node, depth: Int) throws(ManglingError) {
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

    func mangleAnyProtocolConformanceList(_ node: Node, depth: Int) throws(ManglingError) {
        var firstElem = true
        for child in node.children {
            try mangleAnyProtocolConformance(child, depth: depth + 1)
            mangleListSeparator(&firstElem)
        }
        mangleEndOfList(firstElem)
    }

    /// Error/Unsupported methods
    func mangleFunctionSignatureSpecializationParamKind(_ node: Node, depth: Int) throws(ManglingError) {
        // handled inline in mangleFunctionSignatureSpecializationParam
        throw .unsupportedNodeKind(node)
    }

    func mangleFunctionSignatureSpecializationParamPayload(_ node: Node, depth: Int) throws(ManglingError) {
        // handled inline in mangleFunctionSignatureSpecializationParam
        throw .unsupportedNodeKind(node)
    }

    func mangleUniqueExtendedExistentialTypeShapeSymbolicReference(_ node: Node, depth: Int) throws(ManglingError) {
        // We don't support absolute references in the mangling of these
        throw .unsupportedNodeKind(node)
    }

    func mangleNonUniqueExtendedExistentialTypeShapeSymbolicReference(_ node: Node, depth: Int) throws(ManglingError) {
        // We don't support absolute references in the mangling of these
        throw .unsupportedNodeKind(node)
    }

    func mangleSILThunkHopToMainActorIfNeeded(_ node: Node, depth: Int) throws(ManglingError) {
        // This method doesn't exist in C++ - likely a newer addition or different name
        throw .unsupportedNodeKind(node)
    }

    // MARK: - Helper Methods for Dependent Types

    /// Mangle a constrained type, returning the number of chain members and the base param node
    func mangleConstrainedType(_ node: Node, depth: Int) throws(ManglingError) -> (numMembers: Int, paramIdx: Node?) {
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
    func mangleDependentGenericParamIndex(_ node: Node, nonZeroPrefix: String = "", zeroOp: String = "z") throws(ManglingError) {
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

protocol NodeErrorable {
    static var indexOutOfBounds: Self { get }
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
