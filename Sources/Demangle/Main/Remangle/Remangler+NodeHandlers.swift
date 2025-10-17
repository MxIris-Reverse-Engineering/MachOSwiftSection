/// Extension containing specific node kind handlers
extension Remangler {
    // MARK: - Top-Level Nodes

    func mangleGlobal(_ node: Node, depth: Int) -> RemanglerError {
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
                let result = mangleNode(child, depth: depth + 1)
                if !result.isSuccess { return result }

                // If we need reverse order, mangle all previous children in reverse
                if mangleInReverseOrder {
                    for reverseIndex in stride(from: index - 1, through: 0, by: -1) {
                        let reverseResult = mangleNode(node.children[reverseIndex], depth: depth + 1)
                        if !reverseResult.isSuccess { return reverseResult }
                    }
                    mangleInReverseOrder = false
                }
            }
        }

        return .success
    }

    func mangleSuffix(_ node: Node, depth: Int) -> RemanglerError {
        // Suffix is appended as-is
        if let text = node.text {
            append(text)
        }
        return .success
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
    private func mangleGenericArgs(_ node: Node, separator: inout Character, depth: Int, fullSubstitutionMap: Bool = false) -> RemanglerError {
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

            let result = mangleGenericArgs(node.children[0], separator: &separator, depth: depth + 1, fullSubstitutionMap: fullSubst)
            if !result.isSuccess { return result }
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

            let result = mangleGenericArgs(node.children[0], separator: &separator, depth: depth + 1, fullSubstitutionMap: fullSubst)
            if !result.isSuccess { return result }

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

            guard node.children.count >= 2 else {
                return .invalidNodeStructure(node, message: "BoundGeneric needs at least 2 children")
            }
            let unboundType = node.children[0]
            guard unboundType.kind == .type && unboundType.children.count > 0 else {
                return .invalidNodeStructure(node, message: "BoundGeneric child 0 must be Type with children")
            }
            let nominalType = unboundType.children[0]
            guard nominalType.children.count > 0 else {
                return .invalidNodeStructure(node, message: "Nominal type must have parent/module")
            }
            let parentOrModule = nominalType.children[0]
            var result = mangleGenericArgs(parentOrModule, separator: &separator, depth: depth + 1, fullSubstitutionMap: fullSubst)
            if !result.isSuccess { return result }
            append(String(separator))
            separator = "_"
            // Mangle type arguments from TypeList (child 1)
            result = mangleChildNodes(node.children[1], depth: depth + 1)
            if !result.isSuccess { return result }

        case .constrainedExistential:
            append(String(separator))
            separator = "_"
            let result = mangleChildNodes(node.children[1], depth: depth + 1)
            if !result.isSuccess { return result }

        case .boundGenericFunction:
            fullSubst = true

            let unboundFunction = node.children[0]
            guard unboundFunction.kind == .function || unboundFunction.kind == .constructor else {
                return .invalidNodeStructure(node, message: "BoundGenericFunction child 0 must be Function or Constructor")
            }
            let parentOrModule = unboundFunction.children[0]
            var result = mangleGenericArgs(parentOrModule, separator: &separator, depth: depth + 1, fullSubstitutionMap: fullSubst)
            if !result.isSuccess { return result }
            append(String(separator))
            separator = "_"
            result = mangleChildNodes(node.children[1], depth: depth + 1)
            if !result.isSuccess { return result }

        case .extension:
            guard node.children.count > 1 else {
                return .invalidNodeStructure(node, message: "Extension needs at least 2 children")
            }
            return mangleGenericArgs(node.children[1], separator: &separator, depth: depth + 1, fullSubstitutionMap: fullSubst)

        default:
            break
        }

        return .success
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

    func mangleType(_ node: Node, depth: Int) -> RemanglerError {
        mangleSingleChildNode(node, depth: depth + 1)
    }

    func mangleTypeMangling(_ node: Node, depth: Int) -> RemanglerError {
        // TypeMangling only outputs children and 'D' suffix
        // The '_$s' prefix is output by the Global node
        let result = mangleChildNodes(node, depth: depth + 1)
        if !result.isSuccess { return result }
        append("D")
        return .success
    }

    func mangleTypeList(_ node: Node, depth: Int) -> RemanglerError {
        // Type list with proper list separators
        var isFirst = true
        for child in node.children {
            let result = mangleNode(child, depth: depth + 1)
            if !result.isSuccess { return result }
            mangleListSeparator(&isFirst)
        }
        mangleEndOfList(isFirst)
        return .success
    }

    // MARK: - Nominal Types

    func mangleStructure(_ node: Node, depth: Int) -> RemanglerError {
        return mangleAnyNominalType(node, depth: depth + 1)
    }

    func mangleClass(_ node: Node, depth: Int) -> RemanglerError {
        return mangleAnyNominalType(node, depth: depth + 1)
    }

    func mangleEnum(_ node: Node, depth: Int) -> RemanglerError {
        return mangleAnyNominalType(node, depth: depth + 1)
    }

    func mangleProtocol(_ node: Node, depth: Int) -> RemanglerError {
        return mangleAnyGenericType(node, typeOp: "P", depth: depth + 1)
    }

    func mangleTypeAlias(_ node: Node, depth: Int) -> RemanglerError {
        return mangleAnyNominalType(node, depth: depth + 1)
    }

    // MARK: - Bound Generic Types

    func mangleBoundGenericStructure(_ node: Node, depth: Int) -> RemanglerError {
        return mangleAnyNominalType(node, depth: depth + 1)
    }

    func mangleBoundGenericClass(_ node: Node, depth: Int) -> RemanglerError {
        return mangleAnyNominalType(node, depth: depth + 1)
    }

    func mangleBoundGenericEnum(_ node: Node, depth: Int) -> RemanglerError {
        // Special case for Optional: use sugar form "Sg"
        guard node.children.count >= 2 else {
            return .invalidNodeStructure(node, message: "BoundGenericEnum needs at least 2 children")
        }

        // Check if this is Optional
        let typeChild = node.children[0]
        if typeChild.kind == .type && typeChild.children.count > 0 {
            let enumNode = typeChild.children[0]
            if enumNode.kind == .enum && enumNode.children.count >= 2 {
                let moduleNode = enumNode.children[0]
                let identNode = enumNode.children[1]

                if moduleNode.kind == .module && moduleNode.text == "Swift" &&
                    identNode.kind == .identifier && identNode.text == "Optional" {
                    // This is Swift.Optional - use sugar form
                    let substResult = trySubstitution(node)
                    if substResult.found {
                        return .success
                    }

                    // Mangle the wrapped type (single child of TypeList)
                    let typeList = node.children[1]
                    guard typeList.kind == .typeList && typeList.children.count == 1 else {
                        return .invalidNodeStructure(node, message: "Optional TypeList must have 1 child")
                    }

                    let result = mangleNode(typeList.children[0], depth: depth + 1)
                    if !result.isSuccess { return result }

                    append("Sg")

                    // Add to substitution table (use entry from trySubstitution)
                    addSubstitution(substResult.entry)

                    return .success
                }
            }
        }

        // Not Optional - use standard bound generic mangling
        return mangleAnyNominalType(node, depth: depth + 1)
    }

    // MARK: - Function Types

    func mangleFunctionType(_ node: Node, depth: Int) -> RemanglerError {
        // Function type: reverse children (result comes first in mangling)
        let result = mangleFunctionSignature(node, depth: depth + 1)
        if !result.isSuccess { return result }
        append("c")
        return .success
    }

    func mangleFunctionSignature(_ node: Node, depth: Int) -> RemanglerError {
        mangleChildNodesReversed(node, depth: depth)
    }

    func mangleArgumentTuple(_ node: Node, depth: Int) -> RemanglerError {
        // Skip Type wrappers to get the actual content
        guard node.children.count > 0 else {
            return .invalidNodeStructure(node, message: "ArgumentTuple has no children")
        }

        let child = skipType(node.children[0])

        // Check if it's an empty tuple - output 'y'
        if child.kind == .tuple && child.children.count == 0 {
            append("y")
            return .success
        }

        // Otherwise mangle the unwrapped child directly
        return mangleNode(child, depth: depth + 1)
    }

    func mangleReturnType(_ node: Node, depth: Int) -> RemanglerError {
        // Return type uses same logic as ArgumentTuple
        return mangleArgumentTuple(node, depth: depth + 1)
    }

    // MARK: - Functions and Methods

    func mangleFunction(_ node: Node, depth: Int) -> RemanglerError {
        // Function: context + name + optional labels + function signature
        guard node.children.count >= 3 else {
            return .invalidNodeStructure(node, message: "Function needs at least 3 children")
        }

        // Mangle context (child 0)
        var result = mangleNode(node.children[0], depth: depth + 1)
        if !result.isSuccess { return result }

        // Mangle name (child 1)
        result = mangleNode(node.children[1], depth: depth + 1)
        if !result.isSuccess { return result }

        // Check if child 2 is a LabelList
        let hasLabels = node.children[2].kind == .labelList
        let funcTypeIndex = hasLabels ? 3 : 2

        guard funcTypeIndex < node.children.count else {
            return .invalidNodeStructure(node, message: "Function missing type node")
        }

        // Get the function type (usually wrapped in Type node)
        var funcTypeNode = node.children[funcTypeIndex]
        if funcTypeNode.kind == .type && funcTypeNode.children.count > 0 {
            funcTypeNode = funcTypeNode.children[0]
        }

        // Mangle label list if present (must come before function signature)
        if hasLabels {
            result = mangleChildNode(node, at: 2, depth: depth + 1)
            if !result.isSuccess { return result }
        }

        // Handle the function type
        if funcTypeNode.kind == .dependentGenericType {
            // DependentGenericType: mangle signature first, then generic signature
            guard funcTypeNode.children.count >= 2 else {
                return .invalidNodeStructure(funcTypeNode, message: "DependentGenericType needs 2 children")
            }

            // Get the actual function type from child 1
            var actualFuncType = funcTypeNode.children[1]
            if actualFuncType.kind == .type && actualFuncType.children.count > 0 {
                actualFuncType = actualFuncType.children[0]
            }

            // Mangle function signature (reversed children)
            result = mangleFunctionSignature(actualFuncType, depth: depth + 1)
            if !result.isSuccess { return result }

            // Mangle generic signature (child 0)
            result = mangleChildNode(funcTypeNode, at: 0, depth: depth + 1)
            if !result.isSuccess { return result }
        } else {
            // Normal function type: just mangle signature (reversed children)
            result = mangleFunctionSignature(funcTypeNode, depth: depth + 1)
            if !result.isSuccess { return result }
        }

        append("F")
        return .success
    }

    func mangleAllocator(_ node: Node, depth: Int) -> RemanglerError {
        return mangleAnyConstructor(node, kindOp: "C", depth: depth + 1)
    }

    func mangleConstructor(_ node: Node, depth: Int) -> RemanglerError {
        return mangleAnyConstructor(node, kindOp: "c", depth: depth)
    }

    func mangleDestructor(_ node: Node, depth: Int) -> RemanglerError {
        let result = mangleChildNodes(node, depth: depth + 1)
        if !result.isSuccess { return result }
        append("fd")
        return .success
    }

    func mangleGetter(_ node: Node, depth: Int) -> RemanglerError {
        guard node.children.count >= 1 else {
            return .invalidNodeStructure(node, message: "Getter needs at least 1 child")
        }
        return mangleAbstractStorage(node.children[0], accessorCode: "g", depth: depth + 1)
    }

    func mangleSetter(_ node: Node, depth: Int) -> RemanglerError {
        guard node.children.count >= 1 else {
            return .invalidNodeStructure(node, message: "Setter needs at least 1 child")
        }
        return mangleAbstractStorage(node.children[0], accessorCode: "s", depth: depth + 1)
    }

    private func mangleAbstractStorage(_ node: Node, accessorCode: String, depth: Int) -> RemanglerError {
        let result = mangleChildNodes(node, depth: depth + 1)
        if !result.isSuccess { return result }

        // Output storage kind marker
        switch node.kind {
        case .subscript:
            append("i")
        case .variable:
            append("v")
        default:
            return .invalidNodeStructure(node, message: "Not a storage node")
        }

        // Output accessor code
        append(accessorCode)
        return .success
    }

    // MARK: - Identifiers and Names

    func mangleIdentifier(_ node: Node, depth: Int) -> RemanglerError {
        mangleIdentifierImpl(node, isOperator: false)
        return .success
    }

    func manglePrivateDeclName(_ node: Node, depth: Int) -> RemanglerError {
        guard node.children.count >= 1 else {
            return .invalidNodeStructure(node, message: "PrivateDeclName needs at least 1 child")
        }

        let result = mangleChildNodesReversed(node, depth: depth + 1)

        guard result.isSuccess else { return result }
        // Append "Ll" if 1 child, "LL" if 2 children
        append(node.children.count == 1 ? "Ll" : "LL")
        return .success
    }

    func mangleLocalDeclName(_ node: Node, depth: Int) -> RemanglerError {
        // LocalDeclName has: number, identifier
        guard node.children.count >= 2 else {
            return .invalidNodeStructure(node, message: "LocalDeclName needs at least 2 children")
        }

        let result = mangleChildNode(node, at: 1, depth: depth + 1)

        guard result.isSuccess else { return result }

        append("L")

        return mangleChildNode(node, at: 0, depth: depth + 1)
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

    func mangleModule(_ node: Node, depth: Int) -> RemanglerError {
        guard let name = node.text else {
            return .invalidNodeStructure(node, message: "Module has no text")
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
            return mangleIdentifier(node, depth: depth)
        }

        return .success
    }

    func mangleExtension(_ node: Node, depth: Int) -> RemanglerError {
        // Extension: extended type (child 1), extending module (child 0), optional generic signature (child 2)
        guard node.children.count >= 2 else {
            return .invalidNodeStructure(node, message: "Extension needs at least 2 children")
        }

        // Mangle child 1 (the extended type) first
        let result1 = mangleChildNode(node, at: 1, depth: depth + 1)
        if !result1.isSuccess { return result1 }

        // Then mangle child 0 (the extending module)
        let result0 = mangleChildNode(node, at: 0, depth: depth + 1)
        if !result0.isSuccess { return result0 }

        // If there's a third child (generic signature), mangle it
        if node.children.count == 3 {
            let result2 = mangleChildNode(node, at: 2, depth: depth + 1)
            if !result2.isSuccess { return result2 }
        }

        append("E")
        return .success
    }

    // MARK: - Built-in Types

    func mangleBuiltinTypeName(_ node: Node, depth: Int) -> RemanglerError {
        guard let name = node.text else {
            return .invalidNodeStructure(node, message: "BuiltinTypeName has no text")
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
        } else if name.hasPrefix("Builtin.FPPPC") {
            // PowerPC Float types: Builtin.FPPPC<width>
            let width = name.dropFirst("Builtin.FPPPC".count)
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
                    return .unexpectedBuiltinVectorType(node)
                }
                append("Bv\(count)_")
            } else {
                return .unexpectedBuiltinVectorType(node)
            }
        } else {
            return .unexpectedBuiltinType(node)
        }

        return .success
    }

    // MARK: - Tuple Types

    func mangleTuple(_ node: Node, depth: Int) -> RemanglerError {
        // Use mangleTypeList which handles proper list separators
        let result = mangleTypeList(node, depth: depth + 1)
        if !result.isSuccess { return result }
        append("t")
        return .success
    }

    func mangleTupleElement(_ node: Node, depth: Int) -> RemanglerError {
        // Tuple element: optional label + type
        // C++ uses mangleChildNodesReversed, so mangle in reverse order: type, then label
        return mangleChildNodesReversed(node, depth: depth + 1)
    }

    // MARK: - Dependent Types

    func mangleDependentGenericParamType(_ node: Node, depth: Int) -> RemanglerError {
        if node.children.count == 2,
           let paramDepth = node.children[0].index,
           let paramIndex = node.children[1].index,
           paramDepth == 0 && paramIndex == 0 {
            
            append("x")
            return .success
        }

        append("q")
        mangleDependentGenericParamIndex(node)
        return .success
    }

    func mangleDependentMemberType(_ node: Node, depth: Int) -> RemanglerError {
        // Call mangleConstrainedType to handle the whole chain with substitutions
        let manglingResult = mangleConstrainedType(node, depth: depth + 1)
        guard case .success(let result) = manglingResult else {
            if case .failure(let error) = manglingResult {
                return error
            }
            return .invalidNodeStructure(node, message: "mangleConstrainedType failed")
        }

        let (numMembers, paramIdx) = result

        // Based on chain size, output the appropriate suffix
        switch numMembers {
        case -1:
            // Substitution was used - nothing more to output
            break

        case 0:
            // Error case - shouldn't happen with valid dependent member types
            return .invalidNodeStructure(node, message: "WrongDependentMemberType")

        case 1:
            // Single member access
            append("Q")
            if let dependentBase = paramIdx {
                mangleDependentGenericParamIndex(dependentBase, nonZeroPrefix: "y", zeroOp: "z")
            } else {
                append("x")
            }

        default:
            // Multiple member accesses
            append("Q")
            if let dependentBase = paramIdx {
                mangleDependentGenericParamIndex(dependentBase, nonZeroPrefix: "Y", zeroOp: "Z")
            } else {
                append("X")
            }
        }

        return .success
    }

    // MARK: - Protocol Composition

    /// Helper function for mangling protocol lists with optional superclass or AnyObject
    private func mangleProtocolListHelper(_ protocols: Node, superclass: Node?, hasExplicitAnyObject: Bool, depth: Int) -> RemanglerError {
        // Get the TypeList from the protocols node
        guard protocols.children.count == 1, protocols.children[0].kind == .typeList else {
            return .invalidNodeStructure(protocols, message: "ProtocolList should contain a single TypeList child")
        }

        let typeList = protocols.children[0]

        // Mangle each protocol
        var isFirst = true
        for child in typeList.children {
            let result = manglePureProtocol(child, depth: depth + 1)
            if !result.isSuccess { return result }
            mangleListSeparator(&isFirst)
        }

        mangleEndOfList(isFirst)

        // Append suffix based on type
        if let superclass = superclass {
            let result = mangleType(superclass, depth: depth + 1)
            if !result.isSuccess { return result }
            append("Xc")
        } else if hasExplicitAnyObject {
            append("Xl")
        } else {
            append("p")
        }

        return .success
    }

    func mangleProtocolList(_ node: Node, depth: Int) -> RemanglerError {
        return mangleProtocolListHelper(node, superclass: nil, hasExplicitAnyObject: false, depth: depth + 1)
    }

    func mangleProtocolListWithClass(_ node: Node, depth: Int) -> RemanglerError {
        guard node.children.count >= 2 else {
            return .invalidNodeStructure(node, message: "ProtocolListWithClass needs at least 2 children")
        }
        return mangleProtocolListHelper(node.children[0], superclass: node.children[1], hasExplicitAnyObject: false, depth: depth + 1)
    }

    func mangleProtocolListWithAnyObject(_ node: Node, depth: Int) -> RemanglerError {
        guard node.children.count >= 1 else {
            return .invalidNodeStructure(node, message: "ProtocolListWithAnyObject needs at least 1 child")
        }
        return mangleProtocolListHelper(node.children[0], superclass: nil, hasExplicitAnyObject: true, depth: depth + 1)
    }

    // MARK: - Metatypes

    func mangleMetatype(_ node: Node, depth: Int) -> RemanglerError {
        // Check if first child is MetatypeRepresentation
        if node.children.count > 0 && node.children[0].kind == .metatypeRepresentation {
            var result = mangleChildNode(node, at: 1, depth: depth + 1)
            if !result.isSuccess { return result }
            append("XM")
            result = mangleChildNode(node, at: 0, depth: depth + 1)
            guard result.isSuccess else { return result }
            return .success
        } else {
            // Normal case: output single child + "m"
            let result = mangleSingleChildNode(node, depth: depth + 1)
            if !result.isSuccess { return result }
            append("m")
            return .success
        }
    }

    func mangleExistentialMetatype(_ node: Node, depth: Int) -> RemanglerError {
        if node.children.count > 0 && node.children[0].kind == .metatypeRepresentation {
            let result = mangleChildNode(node, at: 1, depth: depth + 1)
            if !result.isSuccess { return result }
            append("Xm")
            return mangleChildNode(node, at: 0, depth: depth + 1)
        } else {
            let result = mangleSingleChildNode(node, depth: depth)
            if !result.isSuccess { return result }
            append("Xp")
            return .success
        }
    }

    // MARK: - Attributes and Modifiers

    func mangleInOut(_ node: Node, depth: Int) -> RemanglerError {
        let result = mangleSingleChildNode(node, depth: depth)
        if !result.isSuccess { return result }
        append("z")
        return .success
    }

    func mangleShared(_ node: Node, depth: Int) -> RemanglerError {
        let result = mangleSingleChildNode(node, depth: depth)
        if !result.isSuccess { return result }
        append("h")
        return .success
    }

    func mangleOwned(_ node: Node, depth: Int) -> RemanglerError {
        let result = mangleSingleChildNode(node, depth: depth)
        if !result.isSuccess { return result }
        append("n")
        return .success
    }

    // MARK: - Numbers and Indices

    func mangleNumber(_ node: Node, depth: Int) -> RemanglerError {
        guard let index = node.index else {
            return .invalidNodeStructure(node, message: "Number has no index")
        }
        mangleIndex(index)
        return .success
    }

    // MARK: - Bound Generic Types (Additional)

    func mangleBoundGenericProtocol(_ node: Node, depth: Int) -> RemanglerError {
        return mangleAnyNominalType(node, depth: depth + 1)
    }

    func mangleBoundGenericTypeAlias(_ node: Node, depth: Int) -> RemanglerError {
        return mangleAnyNominalType(node, depth: depth + 1)
    }

    // MARK: - Variables and Storage

    func mangleVariable(_ node: Node, depth: Int) -> RemanglerError {
        return mangleAbstractStorage(node, accessorCode: "p", depth: depth + 1)
    }

    func mangleSubscript(_ node: Node, depth: Int) -> RemanglerError {
        return mangleAbstractStorage(node, accessorCode: "p", depth: depth + 1)
    }

    func mangleDidSet(_ node: Node, depth: Int) -> RemanglerError {
        guard node.children.count >= 1 else {
            return .invalidNodeStructure(node, message: "DidSet needs at least 1 child")
        }
        return mangleAbstractStorage(node.children[0], accessorCode: "W", depth: depth + 1)
    }

    func mangleWillSet(_ node: Node, depth: Int) -> RemanglerError {
        guard node.children.count >= 1 else {
            return .invalidNodeStructure(node, message: "WillSet needs at least 1 child")
        }
        return mangleAbstractStorage(node.children[0], accessorCode: "w", depth: depth + 1)
    }

    func mangleReadAccessor(_ node: Node, depth: Int) -> RemanglerError {
        guard node.children.count >= 1 else {
            return .invalidNodeStructure(node, message: "ReadAccessor needs at least 1 child")
        }
        return mangleAbstractStorage(node.children[0], accessorCode: "r", depth: depth + 1)
    }

    func mangleModifyAccessor(_ node: Node, depth: Int) -> RemanglerError {
        guard node.children.count >= 1 else {
            return .invalidNodeStructure(node, message: "ModifyAccessor needs at least 1 child")
        }
        return mangleAbstractStorage(node.children[0], accessorCode: "M", depth: depth + 1)
    }

    // MARK: - Reference Storage

    func mangleWeak(_ node: Node, depth: Int) -> RemanglerError {
        let result = mangleSingleChildNode(node, depth: depth + 1)
        if !result.isSuccess { return result }
        append("Xw")
        return .success
    }

    func mangleUnowned(_ node: Node, depth: Int) -> RemanglerError {
        let result = mangleSingleChildNode(node, depth: depth + 1)
        if !result.isSuccess { return result }
        append("Xo")
        return .success
    }

    func mangleUnmanaged(_ node: Node, depth: Int) -> RemanglerError {
        let result = mangleSingleChildNode(node, depth: depth + 1)
        if !result.isSuccess { return result }
        append("Xu")
        return .success
    }

    // MARK: - Special Function Types

    func mangleThinFunctionType(_ node: Node, depth: Int) -> RemanglerError {
        let result = mangleChildNodesReversed(node, depth: depth + 1)
        if !result.isSuccess { return result }
        append("Xf")
        return .success
    }

    func mangleNoEscapeFunctionType(_ node: Node, depth: Int) -> RemanglerError {
        let result = mangleChildNodesReversed(node, depth: depth + 1)
        if !result.isSuccess { return result }
        append("XE")
        return .success
    }

    func mangleAutoClosureType(_ node: Node, depth: Int) -> RemanglerError {
        let result = mangleChildNodesReversed(node, depth: depth + 1)
        if !result.isSuccess { return result }
        append("XK")
        return .success
    }

    func mangleEscapingAutoClosureType(_ node: Node, depth: Int) -> RemanglerError {
        let result = mangleChildNodesReversed(node, depth: depth + 1)
        if !result.isSuccess { return result }
        append("XA")
        return .success
    }

    func mangleUncurriedFunctionType(_ node: Node, depth: Int) -> RemanglerError {
        let result = mangleFunctionSignature(node, depth: depth + 1)
        if !result.isSuccess { return result }
        append("c")
        return .success
    }

    // MARK: - Protocol and Type References

    func mangleProtocolWitness(_ node: Node, depth: Int) -> RemanglerError {
        let result = mangleChildNodes(node, depth: depth + 1)
        if !result.isSuccess { return result }
        append("TW")
        return .success
    }

    func mangleProtocolWitnessTable(_ node: Node, depth: Int) -> RemanglerError {
        let result = mangleSingleChildNode(node, depth: depth + 1)
        if !result.isSuccess { return result }
        append("WP")
        return .success
    }

    func mangleProtocolWitnessTableAccessor(_ node: Node, depth: Int) -> RemanglerError {
        let result = mangleSingleChildNode(node, depth: depth + 1)
        if !result.isSuccess { return result }
        append("Wa")
        return .success
    }

    func mangleValueWitness(_ node: Node, depth: Int) -> RemanglerError {
        guard node.children.count >= 2 else {
            return .invalidNodeStructure(node, message: "ValueWitness needs at least 2 children")
        }

        // Get the index from the first child (Index node)
        guard let indexValue = node.children[0].index else {
            return .invalidNodeStructure(node, message: "ValueWitness Index child has no index value")
        }

        // Convert index to ValueWitnessKind
        guard let kind = ValueWitnessKind(rawValue: indexValue) else {
            return .invalidNodeStructure(node, message: "Invalid ValueWitnessKind index: \(indexValue)")
        }

        // Mangle the type (second child)
        let result = mangleChildNode(node, at: 1, depth: depth + 1)
        if !result.isSuccess { return result }

        // Append "w" + code
        append("w")
        append(kind.code)
        return .success
    }

    func mangleValueWitnessTable(_ node: Node, depth: Int) -> RemanglerError {
        let result = mangleSingleChildNode(node, depth: depth + 1)
        if !result.isSuccess { return result }
        append("WV")
        return .success
    }

    // MARK: - Metadata

    func mangleTypeMetadata(_ node: Node, depth: Int) -> RemanglerError {
        let result = mangleSingleChildNode(node, depth: depth + 1)
        if !result.isSuccess { return result }
        append("N")
        return .success
    }

    func mangleTypeMetadataAccessFunction(_ node: Node, depth: Int) -> RemanglerError {
        let result = mangleSingleChildNode(node, depth: depth + 1)
        if !result.isSuccess { return result }
        append("Ma")
        return .success
    }

    func mangleFullTypeMetadata(_ node: Node, depth: Int) -> RemanglerError {
        let result = mangleSingleChildNode(node, depth: depth + 1)
        if !result.isSuccess { return result }
        append("Mf")
        return .success
    }

    func mangleMetaclass(_ node: Node, depth: Int) -> RemanglerError {
        let result = mangleChildNodes(node, depth: depth + 1)
        if !result.isSuccess { return result }
        append("Mm")
        return .success
    }

    // MARK: - Static and Class Members

    func mangleStatic(_ node: Node, depth: Int) -> RemanglerError {
        let result = mangleSingleChildNode(node, depth: depth + 1)
        if !result.isSuccess { return result }
        append("Z")
        return .success
    }

    // MARK: - Initializers

    func mangleInitializer(_ node: Node, depth: Int) -> RemanglerError {
        let result = mangleChildNodes(node, depth: depth + 1)
        if !result.isSuccess { return result }
        append("fi")
        return .success
    }

    // MARK: - Operators

    func manglePrefixOperator(_ node: Node, depth: Int) -> RemanglerError {
        mangleIdentifierImpl(node, isOperator: true)
        append("op")
        return .success
    }

    func manglePostfixOperator(_ node: Node, depth: Int) -> RemanglerError {
        mangleIdentifierImpl(node, isOperator: true)
        append("oP")
        return .success
    }

    func mangleInfixOperator(_ node: Node, depth: Int) -> RemanglerError {
        mangleIdentifierImpl(node, isOperator: true)
        append("oi")
        return .success
    }

    // MARK: - Generic Signature

    func mangleDependentGenericSignature(_ node: Node, depth: Int) -> RemanglerError {
        // First, separate param counts from requirements
        var paramCountEnd = 0
        var paramCounts: [Node] = []

        for (idx, child) in node.children.enumerated() {
            if child.kind == .dependentGenericParamCount {
                paramCountEnd = idx + 1
                paramCounts.append(child)
            } else {
                // It's a requirement - mangle it
                let result = mangleChildNode(node, at: idx, depth: depth + 1)
                if !result.isSuccess { return result }
            }
        }

        // If there's only one generic param, mangle nothing except 'l'
        if paramCountEnd == 1 && paramCounts[0].index == 1 {
            append("l")
            return .success
        }

        // Remangle generic params: 'r' + param counts + 'l'
        append("r")
        for paramCount in paramCounts {
            if let index = paramCount.index, index > 0 {
                mangleIndex(index - 1)
            } else {
                append("z")
            }
        }
        append("l")
        return .success
    }

    func mangleDependentGenericType(_ node: Node, depth: Int) -> RemanglerError {
        // Mangle children in reverse order (type, then generic signature)
        let result = mangleChildNodesReversed(node, depth: depth + 1)
        if !result.isSuccess { return result }
        append("u")
        return .success
    }

    // MARK: - Throwing and Async

    func mangleThrowsAnnotation(_ node: Node, depth: Int) -> RemanglerError {
        append("K")
        return .success
    }

    func mangleAsyncAnnotation(_ node: Node, depth: Int) -> RemanglerError {
        append("Ya")
        return .success
    }

    // MARK: - Context

    func mangleDeclContext(_ node: Node, depth: Int) -> RemanglerError {
        // DeclContext just mangles its single child
        return mangleSingleChildNode(node, depth: depth + 1)
    }

    func mangleAnonymousContext(_ node: Node, depth: Int) -> RemanglerError {
        // AnonymousContext: name, parent context, optional type list
        guard node.children.count >= 2 else {
            return .invalidNodeStructure(node, message: "AnonymousContext needs at least 2 children")
        }

        // Mangle parent context
        var result = mangleChildNode(node, at: 1, depth: depth + 1)
        if !result.isSuccess { return result }

        // Mangle name
        result = mangleChildNode(node, at: 0, depth: depth + 1)
        if !result.isSuccess { return result }

        // Mangle type list if present
        if node.children.count >= 3 {
            result = mangleTypeList(node.children[2], depth: depth + 1)
        } else {
            append("y")
        }
        if !result.isSuccess { return result }

        append("XZ")
        return .success
    }

    // MARK: - Other Nominal Type

    func mangleOtherNominalType(_ node: Node, depth: Int) -> RemanglerError {
        return mangleAnyNominalType(node, depth: depth + 1)
    }

    // MARK: - Closures

    func mangleExplicitClosure(_ node: Node, depth: Int) -> RemanglerError {
        // ExplicitClosure: context (child 0), type (child 2), index (child 1)
        // Match C++ order: child 0, child 2, "fU", child 1
        var result = mangleChildNode(node, at: 0, depth: depth + 1) // context
        if !result.isSuccess { return result }

        if node.children.count > 2 {
            result = mangleChildNode(node, at: 2, depth: depth + 1) // type
            if !result.isSuccess { return result }
        }

        append("fU")

        // Mangle index (child 1)
        return mangleChildNode(node, at: 1, depth: depth + 1)
    }

    func mangleImplicitClosure(_ node: Node, depth: Int) -> RemanglerError {
        // ImplicitClosure: context (child 0), type (child 2), index (child 1)
        // Match C++ order: child 0, child 2, "fu", child 1
        var result = mangleChildNode(node, at: 0, depth: depth + 1) // context
        if !result.isSuccess { return result }

        if node.children.count > 2 {
            result = mangleChildNode(node, at: 2, depth: depth + 1) // type
            if !result.isSuccess { return result }
        }

        append("fu")

        // Mangle index (child 1)
        return mangleChildNode(node, at: 1, depth: depth + 1)
    }

    // MARK: - Label List and Tuple Element Name

    func mangleLabelList(_ node: Node, depth: Int) -> RemanglerError {
        // LabelList contains identifiers or empty placeholders
        // Labels are mangled sequentially WITHOUT separators (unlike TypeList)
        if node.children.isEmpty {
            append("y")
            return .success
        } else {
            return mangleChildNodes(node, depth: depth + 1)
        }
    }

    func mangleTupleElementName(_ node: Node, depth: Int) -> RemanglerError {
        mangleIdentifier(node, depth: depth + 1)
    }

    // MARK: - Special Types

    func mangleDynamicSelf(_ node: Node, depth: Int) -> RemanglerError {
        let result = mangleSingleChildNode(node, depth: depth)
        if !result.isSuccess { return result }
        append("XD")
        return .success
    }

    func mangleErrorType(_ node: Node, depth: Int) -> RemanglerError {
        append("Xe")
        return .success
    }

    // MARK: - List Markers

    func mangleEmptyList(_ node: Node, depth: Int) -> RemanglerError {
        append("y")
        return .success
    }

    func mangleFirstElementMarker(_ node: Node, depth: Int) -> RemanglerError {
        append("_")
        return .success
    }

    func mangleVariadicMarker(_ node: Node, depth: Int) -> RemanglerError {
        append("d")
        return .success
    }

    // MARK: - Field and Enum

    func mangleFieldOffset(_ node: Node, depth: Int) -> RemanglerError {
        // FieldOffset: child 1 (variable), then "Wv", then child 0 (directness)
        var result = mangleChildNode(node, at: 1, depth: depth + 1)
        if !result.isSuccess { return result }
        append("Wv")
        return mangleChildNode(node, at: 0, depth: depth + 1)
    }

    func mangleEnumCase(_ node: Node, depth: Int) -> RemanglerError {
        let result = mangleSingleChildNode(node, depth: depth + 1)
        if !result.isSuccess { return result }
        append("WC")
        return .success
    }

    // MARK: - Generic Support (High Priority)

    /// Mangle any nominal type (generic or not)
    func mangleAnyNominalType(_ node: Node, depth: Int) -> RemanglerError {
        if depth > Self.maxDepth {
            return .tooComplex(node)
        }

        // Check if this is a specialized type
        if isSpecialized(node) {
            // Try substitution first
            let substResult = trySubstitution(node)
            if substResult.found {
                return .success
            }

            // Get unspecialized version
            guard let unboundType = getUnspecialized(node) else {
                return .invalidNodeStructure(node, message: "Cannot get unspecialized type")
            }

            // Mangle unbound type
            var result = mangleAnyNominalType(unboundType, depth: depth + 1)
            if !result.isSuccess { return result }

            // Mangle generic arguments
            var separator: Character = "y"
            result = mangleGenericArgs(node, separator: &separator, depth: depth + 1)
            if !result.isSuccess { return result }

            // Handle retroactive conformances if present
            if node.children.count == 3 {
                let listNode = node.children[2]
                for child in listNode.children {
                    result = mangleNode(child, depth: depth + 1)
                    if !result.isSuccess { return result }
                }
            }

            append("G")

            // Add to substitutions (use entry from trySubstitution)
            addSubstitution(substResult.entry)

            return .success
        }

        // Handle non-specialized nominal types
        switch node.kind {
        case .structure: return mangleAnyGenericType(node, typeOp: "V", depth: depth)
        case .class: return mangleAnyGenericType(node, typeOp: "C", depth: depth)
        case .enum: return mangleAnyGenericType(node, typeOp: "O", depth: depth)
        case .typeAlias: return mangleAnyGenericType(node, typeOp: "a", depth: depth)
        case .otherNominalType: return mangleAnyGenericType(node, typeOp: "XY", depth: depth)
        case .typeSymbolicReference: return mangleTypeSymbolicReference(node, depth: depth)
        default:
            return .invalidNodeStructure(node, message: "Not a nominal type")
        }
    }

    /// Mangle any generic type with a given type operator
    func mangleAnyGenericType(_ node: Node, typeOp: String, depth: Int) -> RemanglerError {
        // Try substitution first
        let substResult = trySubstitution(node)
        if substResult.found {
            return .success
        }

        // Mangle child nodes
        let result = mangleChildNodes(node, depth: depth + 1)
        if !result.isSuccess { return result }

        // Append type operator
        append(typeOp)

        // Add to substitutions (use entry from trySubstitution)
        addSubstitution(substResult.entry)

        return .success
    }

    // MARK: - Constructor Support

    /// Mangle any constructor (constructor, allocator, etc.)
    func mangleAnyConstructor(_ node: Node, kindOp: Character, depth: Int) -> RemanglerError {
        let result = mangleChildNodes(node, depth: depth + 1)
        if !result.isSuccess { return result }
        append("f\(kindOp)")
        return .success
    }

    // MARK: - Bound Generic Function

    func mangleBoundGenericFunction(_ node: Node, depth: Int) -> RemanglerError {
        // Try substitution first
        let substResult = trySubstitution(node)
        if substResult.found {
            return .success
        }

        // Get unspecialized function
        guard let unboundFunction = getUnspecialized(node) else {
            return .invalidNodeStructure(node, message: "Cannot get unspecialized function")
        }

        // Mangle the unbound function
        var result = mangleFunction(unboundFunction, depth: depth + 1)
        if !result.isSuccess { return result }

        // Mangle generic arguments
        var separator: Character = "y"
        result = mangleGenericArgs(node, separator: &separator, depth: depth + 1)
        if !result.isSuccess { return result }

        append("G")

        // Add to substitutions (use entry from trySubstitution)
        addSubstitution(substResult.entry)

        return .success
    }

    func mangleBoundGenericOtherNominalType(_ node: Node, depth: Int) -> RemanglerError {
        return mangleAnyNominalType(node, depth: depth + 1)
    }

    // MARK: - Associated Types

    func mangleAssociatedType(_ node: Node, depth: Int) -> RemanglerError {
        // Associated types are not directly mangleable
        return .unsupportedNodeKind(node)
    }

    func mangleAssociatedTypeRef(_ node: Node, depth: Int) -> RemanglerError {
        // Try substitution first
        let substResult = trySubstitution(node)
        if substResult.found {
            return .success
        }

        let result = mangleChildNodes(node, depth: depth + 1)
        if !result.isSuccess { return result }

        append("Qa")

        // Add to substitutions (use entry from trySubstitution)
        addSubstitution(substResult.entry)

        return .success
    }

    func mangleAssociatedTypeDescriptor(_ node: Node, depth: Int) -> RemanglerError {
        let result = mangleChildNodes(node, depth: depth + 1)
        if !result.isSuccess { return result }
        append("Tl")
        return .success
    }

    func mangleAssociatedConformanceDescriptor(_ node: Node, depth: Int) -> RemanglerError {
        guard node.children.count >= 3 else {
            return .invalidNodeStructure(node, message: "AssociatedConformanceDescriptor needs 3 children")
        }

        var result = mangleNode(node.children[0], depth: depth + 1)
        if !result.isSuccess { return result }

        result = mangleNode(node.children[1], depth: depth + 1)
        if !result.isSuccess { return result }

        result = manglePureProtocol(node.children[2], depth: depth + 1)
        if !result.isSuccess { return result }

        append("Tn")
        return .success
    }

    func mangleAssociatedTypeMetadataAccessor(_ node: Node, depth: Int) -> RemanglerError {
        let result = mangleChildNodes(node, depth: depth + 1)
        if !result.isSuccess { return result }
        append("Wt")
        return .success
    }

    func mangleAssocTypePath(_ node: Node, depth: Int) -> RemanglerError {
        // Mangle path to associated type
        var firstElem = true
        for child in node.children {
            let result = mangleNode(child, depth: depth + 1)
            guard result.isSuccess else { return result }
            mangleListSeparator(&firstElem)
        }
        return .success
    }

    func mangleAssociatedTypeGenericParamRef(_ node: Node, depth: Int) -> RemanglerError {
        guard node.children.count >= 2 else {
            return .invalidNodeStructure(node, message: "AssociatedTypeGenericParamRef needs 2 children")
        }

        var result = mangleType(node.children[0], depth: depth + 1)
        if !result.isSuccess { return result }

        result = mangleAssocTypePath(node.children[1], depth: depth + 1)
        if !result.isSuccess { return result }

        append("MXA")
        return .success
    }

    // MARK: - Protocol Conformance

    func mangleProtocolConformance(_ node: Node, depth: Int) -> RemanglerError {
        guard node.children.count >= 3 else {
            return .invalidNodeStructure(node, message: "ProtocolConformance needs at least 3 children")
        }

        // Get type from first child
        var ty = node.children[0]
        if ty.kind == .type {
            ty = getChildOfType(ty)
        }

        var genSig: Node? = nil

        // Check for dependent generic type
        if ty.kind == .dependentGenericType {
            genSig = ty.children[0]
            ty = ty.children[1]
        }

        // Mangle type
        var result = mangleNode(ty, depth: depth + 1)
        if !result.isSuccess { return result }

        // Mangle module if present (4th child)
        if node.children.count == 4 {
            result = mangleChildNode(node, at: 3, depth: depth + 1)
            if !result.isSuccess { return result }
        }

        // Mangle protocol
        result = manglePureProtocol(node.children[1], depth: depth + 1)
        if !result.isSuccess { return result }

        // Mangle conformance reference
        result = mangleChildNode(node, at: 2, depth: depth + 1)
        if !result.isSuccess { return result }

        // Mangle generic signature if present
        if let genSig = genSig {
            result = mangleNode(genSig, depth: depth + 1)
            if !result.isSuccess { return result }
        }

        return .success
    }

    func mangleConcreteProtocolConformance(_ node: Node, depth: Int) -> RemanglerError {
        var result = mangleType(node.children[0], depth: depth + 1)
        guard result.isSuccess else { return result }
        result = mangleNode(node.children[1], depth: depth + 1)
        guard result.isSuccess else { return result }
        if node.children.count > 2 {
            result = mangleAnyProtocolConformanceList(node.children[2], depth: depth + 1)
            guard result.isSuccess else { return result }
        } else {
            append("y")
        }
        append("HC")
        return .success
    }

    func mangleProtocolConformanceDescriptor(_ node: Node, depth: Int) -> RemanglerError {
        guard node.children.count >= 1 else {
            return .invalidNodeStructure(node, message: "ProtocolConformanceDescriptor needs 1 child")
        }

        let result = mangleProtocolConformance(node.children[0], depth: depth + 1)
        if !result.isSuccess { return result }

        append("Mc")
        return .success
    }

    func mangleAnyProtocolConformance(_ node: Node, depth: Int) -> RemanglerError {
        // Dispatch to specific conformance handler
        switch node.kind {
        case .concreteProtocolConformance:
            return mangleConcreteProtocolConformance(node, depth: depth + 1)
        case .packProtocolConformance:
            return manglePackProtocolConformance(node, depth: depth + 1)
        case .dependentProtocolConformanceRoot:
            return mangleDependentProtocolConformanceRoot(node, depth: depth + 1)
        case .dependentProtocolConformanceInherited:
            return mangleDependentProtocolConformanceInherited(node, depth: depth + 1)
        case .dependentProtocolConformanceAssociated:
            return mangleDependentProtocolConformanceAssociated(node, depth: depth + 1)
        case .dependentProtocolConformanceOpaque:
            return mangleDependentProtocolConformanceOpaque(node, depth: depth + 1)
        default:
            return .success
        }
    }

    /// Mangle a pure protocol (without wrapper)
    private func manglePureProtocol(_ node: Node, depth: Int) -> RemanglerError {
        let proto = skipType(node)

        // Try standard substitution
        if mangleStandardSubstitution(proto) {
            return .success
        }

        return mangleChildNodes(proto, depth: depth + 1)
    }

    private func getChildOfType(_ node: Node) -> Node {
        assert(node.kind == .type)
        assert(node.children.count == 1)
        return node.children[0]
    }

    // MARK: - Metadata Descriptors

    func mangleNominalTypeDescriptor(_ node: Node, depth: Int) -> RemanglerError {
        let result = mangleChildNodes(node, depth: depth + 1)
        if !result.isSuccess { return result }
        append("Mn")
        return .success
    }

    func mangleNominalTypeDescriptorRecord(_ node: Node, depth: Int) -> RemanglerError {
        let result = mangleChildNodes(node, depth: depth + 1)
        if !result.isSuccess { return result }
        append("Hn")
        return .success
    }

    func mangleProtocolDescriptor(_ node: Node, depth: Int) -> RemanglerError {
        let result = manglePureProtocol(node.children[0], depth: depth + 1)
        if !result.isSuccess { return result }
        append("Mp")
        return .success
    }

    func mangleProtocolDescriptorRecord(_ node: Node, depth: Int) -> RemanglerError {
        let result = manglePureProtocol(node.children[0], depth: depth + 1)
        if !result.isSuccess { return result }
        append("Hr")
        return .success
    }

    func mangleTypeMetadataCompletionFunction(_ node: Node, depth: Int) -> RemanglerError {
        let result = mangleSingleChildNode(node, depth: depth + 1)
        if !result.isSuccess { return result }
        append("Mr")
        return .success
    }

    func mangleTypeMetadataDemanglingCache(_ node: Node, depth: Int) -> RemanglerError {
        let result = mangleSingleChildNode(node, depth: depth + 1)
        if !result.isSuccess { return result }
        append("MD")
        return .success
    }

    func mangleTypeMetadataInstantiationCache(_ node: Node, depth: Int) -> RemanglerError {
        let result = mangleSingleChildNode(node, depth: depth + 1)
        if !result.isSuccess { return result }
        append("MI")
        return .success
    }

    func mangleTypeMetadataLazyCache(_ node: Node, depth: Int) -> RemanglerError {
        let result = mangleSingleChildNode(node, depth: depth + 1)
        if !result.isSuccess { return result }
        append("ML")
        return .success
    }

    func mangleClassMetadataBaseOffset(_ node: Node, depth: Int) -> RemanglerError {
        let result = mangleSingleChildNode(node, depth: depth + 1)
        if !result.isSuccess { return result }
        append("Mo")
        return .success
    }

    func mangleGenericTypeMetadataPattern(_ node: Node, depth: Int) -> RemanglerError {
        let result = mangleSingleChildNode(node, depth: depth + 1)
        if !result.isSuccess { return result }
        append("MP")
        return .success
    }

    func mangleProtocolWitnessTablePattern(_ node: Node, depth: Int) -> RemanglerError {
        let result = mangleSingleChildNode(node, depth: depth + 1)
        if !result.isSuccess { return result }
        append("Wp")
        return .success
    }

    func mangleGenericProtocolWitnessTable(_ node: Node, depth: Int) -> RemanglerError {
        let result = mangleSingleChildNode(node, depth: depth + 1)
        if !result.isSuccess { return result }
        append("WG")
        return .success
    }

    func mangleGenericProtocolWitnessTableInstantiationFunction(_ node: Node, depth: Int) -> RemanglerError {
        let result = mangleSingleChildNode(node, depth: depth + 1)
        if !result.isSuccess { return result }
        append("WI")
        return .success
    }

    func mangleResilientProtocolWitnessTable(_ node: Node, depth: Int) -> RemanglerError {
        let result = mangleSingleChildNode(node, depth: depth + 1)
        if !result.isSuccess { return result }
        append("Wr")
        return .success
    }

    func mangleProtocolSelfConformanceWitness(_ node: Node, depth: Int) -> RemanglerError {
        let result = mangleSingleChildNode(node, depth: depth + 1)
        if !result.isSuccess { return result }
        append("TS")
        return .success
    }

    func mangleBaseWitnessTableAccessor(_ node: Node, depth: Int) -> RemanglerError {
        let result = mangleChildNodes(node, depth: depth + 1)
        if !result.isSuccess { return result }
        append("Wb")
        return .success
    }

    func mangleBaseConformanceDescriptor(_ node: Node, depth: Int) -> RemanglerError {
        guard node.children.count >= 2 else {
            return .invalidNodeStructure(node, message: "BaseConformanceDescriptor needs 2 children")
        }

        var result = mangleNode(node.children[0], depth: depth + 1)
        if !result.isSuccess { return result }

        result = manglePureProtocol(node.children[1], depth: depth + 1)
        if !result.isSuccess { return result }

        append("Tb")
        return .success
    }

    func mangleDependentAssociatedConformance(_ node: Node, depth: Int) -> RemanglerError {
        let result = mangleType(node.children[0], depth: depth + 1)
        guard result.isSuccess else { return result }
        return manglePureProtocol(node.children[1], depth: depth + 1)
    }

    func mangleRetroactiveConformance(_ node: Node, depth: Int) -> RemanglerError {
        // RetroactiveConformance: process child 1 (protocol conformance), output 'g', then index from child 0
        guard node.children.count >= 2 else {
            return .invalidNodeStructure(node, message: "RetroactiveConformance needs at least 2 children")
        }
        var result = mangleAnyProtocolConformance(node.children[1], depth: depth + 1)
        if !result.isSuccess { return result }
        append("g")
        if let index = node.children[0].index {
            mangleIndex(index)
        }
        return .success
    }

    // MARK: - Outlined Operations (High Priority)

    func mangleOutlinedCopy(_ node: Node, depth: Int) -> RemanglerError {
        let result = mangleChildNodes(node, depth: depth + 1)
        if !result.isSuccess { return result }
        append("WOy")
        return .success
    }

    func mangleOutlinedConsume(_ node: Node, depth: Int) -> RemanglerError {
        let result = mangleChildNodes(node, depth: depth + 1)
        if !result.isSuccess { return result }
        append("WOe")
        return .success
    }

    func mangleOutlinedRetain(_ node: Node, depth: Int) -> RemanglerError {
        let result = mangleChildNodes(node, depth: depth + 1)
        if !result.isSuccess { return result }
        append("WOr")
        return .success
    }

    func mangleOutlinedRelease(_ node: Node, depth: Int) -> RemanglerError {
        let result = mangleChildNodes(node, depth: depth + 1)
        if !result.isSuccess { return result }
        append("WOs")
        return .success
    }

    func mangleOutlinedDestroy(_ node: Node, depth: Int) -> RemanglerError {
        let result = mangleChildNodes(node, depth: depth + 1)
        if !result.isSuccess { return result }
        append("WOh")
        return .success
    }

    func mangleOutlinedInitializeWithTake(_ node: Node, depth: Int) -> RemanglerError {
        let result = mangleChildNodes(node, depth: depth + 1)
        if !result.isSuccess { return result }
        append("WOb")
        return .success
    }

    func mangleOutlinedInitializeWithCopy(_ node: Node, depth: Int) -> RemanglerError {
        let result = mangleChildNodes(node, depth: depth + 1)
        if !result.isSuccess { return result }
        append("WOc")
        return .success
    }

    func mangleOutlinedAssignWithTake(_ node: Node, depth: Int) -> RemanglerError {
        let result = mangleChildNodes(node, depth: depth + 1)
        if !result.isSuccess { return result }
        append("WOd")
        return .success
    }

    func mangleOutlinedAssignWithCopy(_ node: Node, depth: Int) -> RemanglerError {
        let result = mangleChildNodes(node, depth: depth + 1)
        if !result.isSuccess { return result }
        append("WOf")
        return .success
    }

    func mangleOutlinedVariable(_ node: Node, depth: Int) -> RemanglerError {
        append("Tv")
        if let index = node.index {
            mangleIndex(index)
        }
        return .success
    }

    func mangleOutlinedEnumGetTag(_ node: Node, depth: Int) -> RemanglerError {
        let result = mangleChildNodes(node, depth: depth + 1)
        if !result.isSuccess { return result }
        append("WOg")
        return .success
    }

    func mangleOutlinedEnumProjectDataForLoad(_ node: Node, depth: Int) -> RemanglerError {
        if node.children.count == 2 {
            let result = mangleNode(node.children[0], depth: depth + 1)
            guard result.isSuccess else { return result }
            append("WOj")
            if let index = node.children[1].index {
                mangleIndex(index)
            }
            return .success
        } else {
            var result = mangleNode(node.children[0], depth: depth + 1)
            guard result.isSuccess else { return result }
            result = mangleNode(node.children[1], depth: depth + 1)
            guard result.isSuccess else { return result }
            append("WOj")
            if let index = node.children[2].index {
                mangleIndex(index)
            }
            return .success
        }
    }

    func mangleOutlinedEnumTagStore(_ node: Node, depth: Int) -> RemanglerError {
        if node.children.count == 2 {
            let result = mangleNode(node.children[0], depth: depth + 1)
            guard result.isSuccess else { return result }
            append("WOi")
            if let index = node.children[1].index {
                mangleIndex(index)
            }
            return .success
        } else {
            var result = mangleNode(node.children[0], depth: depth + 1)
            guard result.isSuccess else { return result }
            result = mangleNode(node.children[1], depth: depth + 1)
            guard result.isSuccess else { return result }
            append("WOi")
            if let index = node.children[2].index {
                mangleIndex(index)
            }
            return .success
        }
    }

    /// No ValueWitness variants
    func mangleOutlinedDestroyNoValueWitness(_ node: Node, depth: Int) -> RemanglerError {
        let result = mangleChildNodes(node, depth: depth + 1)
        if !result.isSuccess { return result }
        append("WOH")
        return .success
    }

    func mangleOutlinedInitializeWithCopyNoValueWitness(_ node: Node, depth: Int) -> RemanglerError {
        let result = mangleChildNodes(node, depth: depth + 1)
        if !result.isSuccess { return result }
        append("WOC")
        return .success
    }

    func mangleOutlinedAssignWithTakeNoValueWitness(_ node: Node, depth: Int) -> RemanglerError {
        let result = mangleChildNodes(node, depth: depth + 1)
        if !result.isSuccess { return result }
        append("WOD")
        return .success
    }

    func mangleOutlinedAssignWithCopyNoValueWitness(_ node: Node, depth: Int) -> RemanglerError {
        let result = mangleChildNodes(node, depth: depth + 1)
        if !result.isSuccess { return result }
        append("WOF")
        return .success
    }

    func mangleOutlinedBridgedMethod(_ node: Node, depth: Int) -> RemanglerError {
        append("Te")
        append(node.text ?? "")
        append("_")
        return .success
    }

    func mangleOutlinedReadOnlyObject(_ node: Node, depth: Int) -> RemanglerError {
        append("Tv")
        if let index = node.index {
            mangleIndex(index)
        }
        append("r")
        return .success
    }

    // MARK: - Pack Support (High Priority)

    func manglePack(_ node: Node, depth: Int) -> RemanglerError {
        let result = mangleChildNodes(node, depth: depth + 1)
        if !result.isSuccess { return result }
        append("QP")
        return .success
    }

    func manglePackElement(_ node: Node, depth: Int) -> RemanglerError {
        // PackElement: child 0, "Qe", child 1
        guard node.children.count >= 2 else {
            return .invalidNodeStructure(node, message: "PackElement needs at least 2 children")
        }
        var result = mangleChildNode(node, at: 0, depth: depth + 1)
        if !result.isSuccess { return result }
        append("Qe")
        result = mangleChildNode(node, at: 1, depth: depth + 1)
        return result
    }

    func manglePackElementLevel(_ node: Node, depth: Int) -> RemanglerError {
        // PackElementLevel: just mangle the index
        if let index = node.index {
            mangleIndex(index)
        }
        return .success
    }

    func manglePackExpansion(_ node: Node, depth: Int) -> RemanglerError {
        let result = mangleChildNodes(node, depth: depth + 1)
        if !result.isSuccess { return result }
        append("Qp")
        return .success
    }

    func manglePackProtocolConformance(_ node: Node, depth: Int) -> RemanglerError {
        let result = mangleAnyProtocolConformanceList(node.children[0], depth: depth + 1)
        if !result.isSuccess { return result }
        append("HX")
        return .success
    }

    func mangleSILPackDirect(_ node: Node, depth: Int) -> RemanglerError {
        let result = mangleTypeList(node, depth: depth + 1)
        if !result.isSuccess { return result }
        append("Qsd")
        return .success
    }

    func mangleSILPackIndirect(_ node: Node, depth: Int) -> RemanglerError {
        let result = mangleTypeList(node, depth: depth + 1)
        if !result.isSuccess { return result }
        append("QSi")
        return .success
    }

    // MARK: - Generic Specialization

    func mangleGenericSpecialization(_ node: Node, depth: Int) -> RemanglerError {
        return mangleGenericSpecializationNode(node, specKind: "g", depth: depth)
    }

    func mangleGenericPartialSpecialization(_ node: Node, depth: Int) -> RemanglerError {
        for child in node.children {
            if child.kind == .genericSpecializationParam {
                let result = mangleChildNode(child, at: 0, depth: depth + 1)
                if !result.isSuccess { return result }
                break
            }
        }
        append(node.kind == .genericPartialSpecializationNotReAbstracted ? "TP": "Tp")
        for child in node.children {
            if child.kind == .genericSpecializationParam {
                let result = mangleNode(child, depth: depth + 1)
                if !result.isSuccess { return result }
            }
        }
        return .success
    }

    private func mangleGenericSpecializationNode(_ node: Node, specKind: String, depth: Int) -> RemanglerError {
        // Mangle the specialized entity
        guard node.children.count >= 2 else {
            return .invalidNodeStructure(node, message: "GenericSpecialization needs at least 2 children")
        }

        var result = mangleNode(node.children[0], depth: depth + 1)
        if !result.isSuccess { return result }

        // Mangle specialization parameters
        for i in 1 ..< node.children.count {
            result = mangleNode(node.children[i], depth: depth + 1)
            if !result.isSuccess { return result }
        }

        append("T\(specKind)")
        return .success
    }

    func mangleGenericSpecializationParam(_ node: Node, depth: Int) -> RemanglerError {
        return mangleChildNodes(node, depth: depth + 1)
    }

    func mangleFunctionSignatureSpecialization(_ node: Node, depth: Int) -> RemanglerError {
        let result = mangleChildNodes(node, depth: depth + 1)
        if !result.isSuccess { return result }
        append("Tf")
        return .success
    }

    func mangleGenericTypeParamDecl(_ node: Node, depth: Int) -> RemanglerError {
        let result = mangleChildNodes(node, depth: depth + 1)
        if case .success = result {
            append("fp")
        }
        return result
    }

    func mangleDependentGenericParamCount(_ node: Node, depth: Int) -> RemanglerError {
        guard let count = node.index else {
            return .invalidNodeStructure(node, message: "DependentGenericParamCount has no index")
        }
        append("\(count)")
        return .success
    }

    func mangleDependentGenericParamPackMarker(_ node: Node, depth: Int) -> RemanglerError {
        // DependentGenericParamPackMarker: output "Rv" then mangle the param index
        guard node.children.count == 1,
              node.children[0].kind == .type else {
            return .invalidNodeStructure(node, message: "DependentGenericParamPackMarker needs Type child")
        }
        append("Rv")
        mangleDependentGenericParamIndex(node.children[0].children[0])
        return .success
    }

    func mangleDependentGenericParamValueMarker(_ node: Node, depth: Int) -> RemanglerError {
        append("Xv")
        return .success
    }

    // MARK: - Impl Function Type (High Priority)

    func mangleImplFunctionType(_ node: Node, depth: Int) -> RemanglerError {
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
                guard child.children.count >= 2 else {
                    return .invalidNodeStructure(child, message: "Impl parameter/result needs at least 2 children")
                }
                let result = mangleNode(child.children.last!, depth: depth + 1)
                if !result.isSuccess { return result }

            case .dependentPseudogenericSignature:
                pseudoGeneric = "P"
                genSig = child

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

        // Output coroutine kind if present
        for child in node.children where child.kind == .implCoroutineKind {
            let result = mangleNode(child, depth: depth + 1)
            if !result.isSuccess { return result }
        }

        // Output async if present
        // Note: implAsync node kind may not exist in current Node definitions
        // for child in node.children where child.kind == .implAsync {
        //     append("H")
        // }

        // Output differentiability kind if present
        for child in node.children where child.kind == .implDifferentiabilityKind {
            let result = mangleNode(child, depth: depth + 1)
            if !result.isSuccess { return result }
        }

        // Output parameters with conventions
        var isFirst = true
        for child in node.children where child.kind == .implParameter {
            guard child.children.count >= 2 else { continue }

            // Inline mangle parameter convention (first child should be ImplConvention)
            if child.children[0].kind == .implConvention {
                guard let convText = child.children[0].text else {
                    return .invalidNodeStructure(child.children[0], message: "ImplConvention has no text")
                }
                // Parameter convention mapping
                switch convText {
                case "@in": append("i")
                case "@inout": append("l")
                case "@inout_aliasable": append("b")
                case "@in_guaranteed": append("n")
                case "@in_cxx": append("X")
                case "@in_constant": append("c")
                case "@owned": append("x")
                case "@guaranteed": append("g")
                case "@deallocating": append("e")
                case "@unowned": append("y")
                case "@pack_guaranteed": append("p")
                case "@pack_owned": append("v")
                case "@pack_inout": append("m")
                default:
                    return .invalidNodeStructure(child.children[0], message: "Unknown parameter convention: \(convText)")
                }

                // Handle parameter attributes (middle children)
                for i in 1 ..< (child.children.count - 1) {
                    let grandchild = child.children[i]
                    let result = mangleNode(grandchild, depth: depth + 1)
                    if !result.isSuccess { return result }
                }

                // Mangle the last child (the parameter type)
                let paramType = child.children[child.children.count - 1]
                let result = mangleNode(paramType, depth: depth + 1)
                if !result.isSuccess { return result }
            }

            mangleListSeparator(&isFirst)
        }
        mangleEndOfList(isFirst)

        // Output results with conventions
        isFirst = true
        for child in node.children where child.kind == .implResult || child.kind == .implYield {
            guard child.children.count >= 2 else { continue }

            // Output 'Y' for yield
            if child.kind == .implYield {
                append("Y")
            }

            // Inline mangle result convention (first child should be ImplConvention)
            if child.children[0].kind == .implConvention {
                guard let convText = child.children[0].text else {
                    return .invalidNodeStructure(child.children[0], message: "ImplConvention has no text")
                }
                // Result convention mapping (different from parameter!)
                switch convText {
                case "@out": append("r")
                case "@owned": append("o")
                case "@unowned": append("d")
                case "@unowned_inner_pointer": append("u")
                case "@autoreleased": append("a")
                case "@pack_out": append("k")
                default:
                    return .invalidNodeStructure(child.children[0], message: "Unknown result convention: \(convText)")
                }

                // Handle result attributes (middle children)
                for i in 1 ..< (child.children.count - 1) {
                    let grandchild = child.children[i]
                    let result = mangleNode(grandchild, depth: depth + 1)
                    if !result.isSuccess { return result }
                }

                // Mangle the last child (the result type)
                let resultType = child.children[child.children.count - 1]
                let result = mangleNode(resultType, depth: depth + 1)
                if !result.isSuccess { return result }
            }

            mangleListSeparator(&isFirst)
        }
        mangleEndOfList(isFirst)

        // Mangle error result if present
        for child in node.children where child.kind == .implErrorResult {
            guard child.children.count >= 2 else { continue }
            let result = mangleNode(child.children[0], depth: depth + 1)
            if !result.isSuccess { return result }
            append("z")
        }

        // Output generic signature if present
        if let genSig = genSig {
            let result = mangleNode(genSig, depth: depth + 1)
            if !result.isSuccess { return result }
        }

        // Mangle pattern substitutions if present
        if let patternSubs = patternSubs {
            let result = mangleNode(patternSubs, depth: depth + 1)
            if !result.isSuccess { return result }
        }

        // Mangle invocation substitutions if present
        if let invocationSubs = invocationSubs {
            let result = mangleNode(invocationSubs, depth: depth + 1)
            if !result.isSuccess { return result }
        }

        // Output calling convention
        for child in node.children where child.kind == .implFunctionConvention {
            let result = mangleNode(child, depth: depth + 1)
            if !result.isSuccess { return result }
        }

        append("I\(pseudoGeneric)")
        return .success
    }

    func mangleImplParameter(_ node: Node, depth: Int) -> RemanglerError {
        // ImplParameter is handled inline in mangleImplFunctionType
        return .invalidNodeStructure(node, message: "ImplParameter should be handled inline")
    }

    func mangleImplResult(_ node: Node, depth: Int) -> RemanglerError {
        // ImplResult is handled inline in mangleImplFunctionType
        return .invalidNodeStructure(node, message: "ImplResult should be handled inline")
    }

    func mangleImplYield(_ node: Node, depth: Int) -> RemanglerError {
        return mangleChildNodes(node, depth: depth + 1)
    }

    func mangleImplErrorResult(_ node: Node, depth: Int) -> RemanglerError {
        return mangleChildNodes(node, depth: depth + 1)
    }

    func mangleImplConvention(_ node: Node, depth: Int) -> RemanglerError {
        guard let text = node.text else {
            return .invalidNodeStructure(node, message: "ImplConvention has no text")
        }

        // Map convention names to characters
        // Handle both parameter/result conventions and callee conventions
        switch text {
        // Parameter/Result conventions
        case "@in": append("i")
        case "@inout": append("l")
        case "@inout_aliasable": append("b")
        case "@in_guaranteed": append("n")
        case "@in_cxx": append("X")
        case "@owned": append("x")
        case "@guaranteed": append("g")
        case "@deallocating": append("e")
        case "@unowned": append("y")
        case "@pack_owned": append("v")
        case "@pack_guaranteed": append("p")
        case "@pack_inout": append("m")
        case "@out": append("r")
        case "@unowned_inner_pointer": append("u")
        case "@autoreleased": append("a")
        case "@pack_out": append("k")
        // Callee conventions
        case "@callee_unowned": append("y")
        case "@callee_guaranteed": append("g")
        case "@callee_owned": append("x")
        // Legacy direct/indirect forms (if needed)
        case "direct_unowned": append("d")
        case "direct_owned": append("o")
        case "direct_guaranteed": append("g")
        case "indirect_in": append("i")
        case "indirect_in_guaranteed": append("l")
        case "indirect_inout": append("n")
        case "indirect_inout_aliasable": append("a")
        case "indirect_out": append("r")
        case "pack_owned": append("p")
        case "pack_guaranteed": append("k")
        case "pack_inout": append("t")
        default:
            return .invalidNodeStructure(node, message: "Unknown impl convention: \(text)")
        }

        return .success
    }

    func mangleImplFunctionConvention(_ node: Node, depth: Int) -> RemanglerError {
        // Get text from first child if it exists
        let text = (node.children.count > 0 && node.children[0].text != nil)
            ? node.children[0].text!
            : ""

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
            return .invalidNodeStructure(node, message: "Unknown function convention: \(text)")
        }

        // Check if we need to handle ClangType (for 'B' and 'C' conventions)
        if (funcAttr == "B" || funcAttr == "C") && node.children.count > 1
            && node.children[1].kind == .clangType {
            append("z")
            append(funcAttr)
            return mangleNode(node.children[1], depth: depth + 1)
        }

        append(funcAttr)
        return .success
    }

    func mangleImplFunctionConventionName(_ node: Node, depth: Int) -> RemanglerError {
        return mangleImplFunctionConvention(node, depth: depth)
    }

    func mangleImplFunctionAttribute(_ node: Node, depth: Int) -> RemanglerError {
        guard let text = node.text else {
            return .invalidNodeStructure(node, message: "ImplFunctionAttribute has no text")
        }

        // Map attribute names
        switch text {
        case "pseudogeneric": append("Cp")
        case "noescape": append("Ce")
        case "noasync": append("Ca")
        case "Sendable": append("Cs")
        case "async": append("Ch")
        default:
            return .invalidNodeStructure(node, message: "Unknown function attribute: \(text)")
        }

        return .success
    }

    func mangleImplEscaping(_ node: Node, depth: Int) -> RemanglerError {
        append("e")
        return .success
    }

    func mangleImplDifferentiabilityKind(_ node: Node, depth: Int) -> RemanglerError {
        guard let text = node.text else {
            return .invalidNodeStructure(node, message: "ImplDifferentiabilityKind has no text")
        }

        switch text {
        case "forward": append("Jf")
        case "reverse": append("Jr")
        case "normal": append("Jn")
        case "linear": append("Jl")
        default:
            return .invalidNodeStructure(node, message: "Unknown differentiability kind: \(text)")
        }

        return .success
    }

    func mangleImplCoroutineKind(_ node: Node, depth: Int) -> RemanglerError {
        guard let text = node.text else {
            return .invalidNodeStructure(node, message: "ImplCoroutineKind has no text")
        }

        switch text {
        case "yield_once": append("A")
        case "yield_many": append("G")
        default:
            return .invalidNodeStructure(node, message: "Unknown coroutine kind: \(text)")
        }

        return .success
    }

    func mangleImplParameterIsolated(_ node: Node, depth: Int) -> RemanglerError {
        append("i")
        return mangleChildNodes(node, depth: depth + 1)
    }

    func mangleImplParameterSending(_ node: Node, depth: Int) -> RemanglerError {
        append("s")
        return mangleChildNodes(node, depth: depth + 1)
    }

    func mangleImplParameterImplicitLeading(_ node: Node, depth: Int) -> RemanglerError {
        append("I")
        return mangleChildNodes(node, depth: depth + 1)
    }

    func mangleImplSendingResult(_ node: Node, depth: Int) -> RemanglerError {
        append("S")
        return mangleChildNodes(node, depth: depth + 1)
    }

    func mangleImplPatternSubstitutions(_ node: Node, depth: Int) -> RemanglerError {
        let result = mangleChildNodes(node, depth: depth + 1)
        if !result.isSuccess { return result }
        append("Ts")
        return .success
    }

    func mangleImplInvocationSubstitutions(_ node: Node, depth: Int) -> RemanglerError {
        let result = mangleChildNodes(node, depth: depth + 1)
        if !result.isSuccess { return result }
        append("Ti")
        return .success
    }

    // MARK: - Descriptor/Record Types (20+ methods)

    func mangleAccessibleFunctionRecord(_ node: Node, depth: Int) -> RemanglerError {
        append("HF")
        return .success
    }

    func mangleAnonymousDescriptor(_ node: Node, depth: Int) -> RemanglerError {
        guard node.children.count >= 1 else {
            return .invalidNodeStructure(node, message: "AnonymousDescriptor needs at least 1 child")
        }

        var result = mangleNode(node.children[0], depth: depth + 1)
        if !result.isSuccess { return result }

        // Check if there's an identifier child
        if node.children.count == 1 {
            append("MXX")
        } else {
            result = mangleNode(node.children[1], depth: depth + 1)
            if !result.isSuccess { return result }
            append("MXY")
        }

        return .success
    }

    func mangleExtensionDescriptor(_ node: Node, depth: Int) -> RemanglerError {
        let result = mangleNode(node.children[0], depth: depth + 1)
        if !result.isSuccess { return result }
        append("MXE")
        return .success
    }

    func mangleMethodDescriptor(_ node: Node, depth: Int) -> RemanglerError {
        let result = mangleSingleChildNode(node, depth: depth + 1)
        if !result.isSuccess { return result }
        append("Tq")
        return .success
    }

    func mangleModuleDescriptor(_ node: Node, depth: Int) -> RemanglerError {
        let result = mangleNode(node.children[0], depth: depth + 1)
        if !result.isSuccess { return result }
        append("MXM")
        return .success
    }

    func manglePropertyDescriptor(_ node: Node, depth: Int) -> RemanglerError {
        let result = mangleSingleChildNode(node, depth: depth + 1)
        if !result.isSuccess { return result }
        append("MV")
        return .success
    }

    func mangleProtocolConformanceDescriptorRecord(_ node: Node, depth: Int) -> RemanglerError {
        guard node.children.count >= 1 else {
            return .invalidNodeStructure(node, message: "ProtocolConformanceDescriptorRecord needs 1 child")
        }

        let result = mangleProtocolConformance(node.children[0], depth: depth + 1)
        if !result.isSuccess { return result }

        append("Hc")
        return .success
    }

    func mangleProtocolRequirementsBaseDescriptor(_ node: Node, depth: Int) -> RemanglerError {
        guard node.children.count >= 1 else {
            return .invalidNodeStructure(node, message: "ProtocolRequirementsBaseDescriptor needs 1 child")
        }

        let result = manglePureProtocol(skipType(node.children[0]), depth: depth + 1)
        if !result.isSuccess { return result }

        append("TL")
        return .success
    }

    func mangleProtocolSelfConformanceDescriptor(_ node: Node, depth: Int) -> RemanglerError {
        guard node.children.count >= 1 else {
            return .invalidNodeStructure(node, message: "ProtocolSelfConformanceDescriptor needs 1 child")
        }

        let result = manglePureProtocol(node.children[0], depth: depth + 1)
        if !result.isSuccess { return result }

        append("MS")
        return .success
    }

    func mangleProtocolSelfConformanceWitnessTable(_ node: Node, depth: Int) -> RemanglerError {
        let result = manglePureProtocol(node.children[0], depth: depth + 1)
        if !result.isSuccess { return result }
        append("WS")
        return .success
    }

    func mangleProtocolSymbolicReference(_ node: Node, depth: Int) -> RemanglerError {
        // Symbolic reference - requires resolver
        return .unsupportedNodeKind(node)
    }

    func mangleTypeSymbolicReference(_ node: Node, depth: Int) -> RemanglerError {
        // Symbolic reference - requires resolver
        return .unsupportedNodeKind(node)
    }

    func mangleObjectiveCProtocolSymbolicReference(_ node: Node, depth: Int) -> RemanglerError {
        // Symbolic reference - requires resolver
        return .unsupportedNodeKind(node)
    }

    // MARK: - Opaque Types (10 methods)

    func mangleOpaqueType(_ node: Node, depth: Int) -> RemanglerError {
        // Try substitution first
        let substResult = trySubstitution(node)
        if substResult.found {
            return .success
        }

        guard node.children.count >= 3 else {
            return .invalidNodeStructure(node, message: "OpaqueType needs at least 3 children")
        }

        // Mangle first child (descriptor)
        var result = mangleNode(node.children[0], depth: depth + 1)
        if !result.isSuccess { return result }

        // Mangle bound generics (child 2) with separators
        let boundGenerics = node.children[2]
        for (i, child) in boundGenerics.children.enumerated() {
            append(i == 0 ? "y" : "_")
            result = mangleChildNodes(child, depth: depth + 1)
            if !result.isSuccess { return result }
        }

        // Mangle retroactive conformances if present (child 3)
        if node.children.count >= 4 {
            let retroactiveConformances = node.children[3]
            for child in retroactiveConformances.children {
                result = mangleNode(child, depth: depth + 1)
                if !result.isSuccess { return result }
            }
        }

        append("Qo")

        // Mangle index from second child
        if let index = node.children[1].index {
            mangleIndex(index)
        }

        // Add to substitutions (use entry from trySubstitution)
        addSubstitution(substResult.entry)

        return .success
    }

    func mangleOpaqueReturnType(_ node: Node, depth: Int) -> RemanglerError {
        // Check if first child is OpaqueReturnTypeIndex
        if node.children.count > 0 && node.children[0].kind == .opaqueReturnTypeIndex {
            // Has index - output "QR" followed by index
            append("QR")
            if let index = node.children[0].index {
                mangleIndex(index)
            }
        } else {
            // No index or no children - output "Qr"
            append("Qr")
        }

        return .success
    }

    func mangleOpaqueReturnTypeOf(_ node: Node, depth: Int) -> RemanglerError {
        let result = mangleSingleChildNode(node, depth: depth + 1)
        if !result.isSuccess { return result }
        append("QO")
        return .success
    }

    func mangleOpaqueReturnTypeIndex(_ node: Node, depth: Int) -> RemanglerError {
        // This is just a marker node with an index
        return .success
    }

    func mangleOpaqueReturnTypeParent(_ node: Node, depth: Int) -> RemanglerError {
        return mangleChildNodes(node, depth: depth + 1)
    }

    func mangleOpaqueTypeDescriptor(_ node: Node, depth: Int) -> RemanglerError {
        let result = mangleSingleChildNode(node, depth: depth + 1)
        if !result.isSuccess { return result }
        append("MQ")
        return .success
    }

    func mangleOpaqueTypeDescriptorAccessor(_ node: Node, depth: Int) -> RemanglerError {
        let result = mangleSingleChildNode(node, depth: depth + 1)
        if !result.isSuccess { return result }
        append("Mg")
        return .success
    }

    func mangleOpaqueTypeDescriptorAccessorImpl(_ node: Node, depth: Int) -> RemanglerError {
        let result = mangleChildNodes(node, depth: depth + 1)
        if !result.isSuccess { return result }
        append("Mi")
        return .success
    }

    func mangleOpaqueTypeDescriptorAccessorKey(_ node: Node, depth: Int) -> RemanglerError {
        let result = mangleSingleChildNode(node, depth: depth + 1)
        if !result.isSuccess { return result }
        append("Mj")
        return .success
    }

    func mangleOpaqueTypeDescriptorAccessorVar(_ node: Node, depth: Int) -> RemanglerError {
        let result = mangleSingleChildNode(node, depth: depth + 1)
        if !result.isSuccess { return result }
        append("Mk")
        return .success
    }

    func mangleOpaqueTypeDescriptorRecord(_ node: Node, depth: Int) -> RemanglerError {
        let result = mangleSingleChildNode(node, depth: depth + 1)
        if !result.isSuccess { return result }
        append("Ho")
        return .success
    }

    func mangleOpaqueTypeDescriptorSymbolicReference(_ node: Node, depth: Int) -> RemanglerError {
        // Symbolic reference
        return .unsupportedNodeKind(node)
    }

    // MARK: - Thunk Types (10+ methods)

    func mangleCurryThunk(_ node: Node, depth: Int) -> RemanglerError {
        let result = mangleSingleChildNode(node, depth: depth + 1)
        if !result.isSuccess { return result }
        append("Tc")
        return .success
    }

    func mangleDispatchThunk(_ node: Node, depth: Int) -> RemanglerError {
        let result = mangleSingleChildNode(node, depth: depth + 1)
        if !result.isSuccess { return result }
        append("Tj")
        return .success
    }

    func mangleReabstractionThunk(_ node: Node, depth: Int) -> RemanglerError {
        // IMPORTANT: Process children in REVERSE order
        let result = mangleChildNodesReversed(node, depth: depth + 1)
        if !result.isSuccess { return result }
        append("Tr")
        return .success
    }

    func mangleReabstractionThunkHelper(_ node: Node, depth: Int) -> RemanglerError {
        // IMPORTANT: Process children in REVERSE order
        let result = mangleChildNodesReversed(node, depth: depth + 1)
        if !result.isSuccess { return result }
        append("TR")
        return .success
    }

    func mangleReabstractionThunkHelperWithSelf(_ node: Node, depth: Int) -> RemanglerError {
        // IMPORTANT: Process children in REVERSE order
        let result = mangleChildNodesReversed(node, depth: depth + 1)
        if !result.isSuccess { return result }
        append("Ty")
        return .success
    }

    func mangleReabstractionThunkHelperWithGlobalActor(_ node: Node, depth: Int) -> RemanglerError {
        // This one uses NORMAL order (not reversed)
        let result = mangleChildNodes(node, depth: depth + 1)
        if !result.isSuccess { return result }
        append("TU")
        return .success
    }

    func manglePartialApplyForwarder(_ node: Node, depth: Int) -> RemanglerError {
        let result = mangleChildNodesReversed(node, depth: depth + 1)
        if !result.isSuccess { return result }
        append("TA")
        return .success
    }

    func manglePartialApplyObjCForwarder(_ node: Node, depth: Int) -> RemanglerError {
        let result = mangleChildNodesReversed(node, depth: depth + 1)
        if !result.isSuccess { return result }
        append("Ta")
        return .success
    }

    // MARK: - Macro Support (11 methods)

    func mangleMacro(_ node: Node, depth: Int) -> RemanglerError {
        let result = mangleChildNodes(node, depth: depth + 1)
        if !result.isSuccess { return result }
        append("fm")
        return .success
    }

    func mangleMacroExpansionLoc(_ node: Node, depth: Int) -> RemanglerError {
        guard node.children.count >= 3 else {
            return .invalidNodeStructure(node, message: "MacroExpansionLoc needs at least 3 children")
        }

        // Mangle first two children (context)
        var result = mangleNode(node.children[0], depth: depth + 1)
        if !result.isSuccess { return result }

        result = mangleNode(node.children[1], depth: depth + 1)
        if !result.isSuccess { return result }

        append("fMX")

        // Mangle line and column as indices
        if let line = node.children[2].index {
            mangleIndex(line)
        }

        if node.children.count >= 4, let col = node.children[3].index {
            mangleIndex(col)
        }

        return .success
    }

    func mangleMacroExpansionUniqueName(_ node: Node, depth: Int) -> RemanglerError {
        // MacroExpansionUniqueName: child 0, optional child 3, child 1, "fMu", child 2
        guard node.children.count >= 3 else {
            return .invalidNodeStructure(node, message: "MacroExpansionUniqueName needs at least 3 children")
        }
        var result = mangleChildNode(node, at: 0, depth: depth + 1)
        if !result.isSuccess { return result }

        // Handle optional private discriminator (child 3)
        if node.children.count >= 4 {
            result = mangleNode(node.children[3], depth: depth + 1)
            if !result.isSuccess { return result }
        }

        result = mangleChildNode(node, at: 1, depth: depth + 1)
        if !result.isSuccess { return result }

        append("fMu")

        return mangleChildNode(node, at: 2, depth: depth + 1)
    }

    func mangleFreestandingMacroExpansion(_ node: Node, depth: Int) -> RemanglerError {
        guard node.children.count >= 3 else {
            return .invalidNodeStructure(node, message: "FreestandingMacroExpansion needs at least 3 children")
        }

        // Mangle first child (macro reference)
        var result = mangleNode(node.children[0], depth: depth + 1)
        if !result.isSuccess { return result }

        // Handle optional private discriminator
        var macroNameIndex = 1
        if node.children.count >= 4 && node.children[1].kind == .privateDeclName {
            result = mangleNode(node.children[1], depth: depth + 1)
            if !result.isSuccess { return result }
            macroNameIndex = 2
        }

        // Mangle macro name
        result = mangleNode(node.children[macroNameIndex], depth: depth + 1)
        if !result.isSuccess { return result }

        append("fMf")

        // Mangle parent context
        result = mangleNode(node.children[macroNameIndex + 1], depth: depth + 1)
        if !result.isSuccess { return result }

        return .success
    }

    func mangleAccessorAttachedMacroExpansion(_ node: Node, depth: Int) -> RemanglerError {
        let result = mangleChildNodes(node, depth: depth + 1)
        if !result.isSuccess { return result }
        append("fMa")
        return .success
    }

    func mangleMemberAttributeAttachedMacroExpansion(_ node: Node, depth: Int) -> RemanglerError {
        let result = mangleChildNodes(node, depth: depth + 1)
        if !result.isSuccess { return result }
        append("fMA")
        return .success
    }

    func mangleMemberAttachedMacroExpansion(_ node: Node, depth: Int) -> RemanglerError {
        let result = mangleChildNodes(node, depth: depth + 1)
        if !result.isSuccess { return result }
        append("fMm")
        return .success
    }

    func manglePeerAttachedMacroExpansion(_ node: Node, depth: Int) -> RemanglerError {
        let result = mangleChildNodes(node, depth: depth + 1)
        if !result.isSuccess { return result }
        append("fMp")
        return .success
    }

    func mangleConformanceAttachedMacroExpansion(_ node: Node, depth: Int) -> RemanglerError {
        let result = mangleChildNodes(node, depth: depth + 1)
        if !result.isSuccess { return result }
        append("fMc")
        return .success
    }

    func mangleExtensionAttachedMacroExpansion(_ node: Node, depth: Int) -> RemanglerError {
        let result = mangleChildNodes(node, depth: depth + 1)
        if !result.isSuccess { return result }
        append("fMe")
        return .success
    }

    func mangleBodyAttachedMacroExpansion(_ node: Node, depth: Int) -> RemanglerError {
        let result = mangleChildNodes(node, depth: depth + 1)
        if !result.isSuccess { return result }
        append("fMb")
        return .success
    }

    // MARK: - Additional Missing Node Handlers (109 methods)

    // MARK: - Simple Markers (20 methods)

    func mangleAsyncFunctionPointer(_ node: Node, depth: Int) -> RemanglerError {
        append("Tu")
        return .success
    }

    func mangleAsyncRemoved(_ node: Node, depth: Int) -> RemanglerError {
        append("a")
        return .success
    }

    func mangleBackDeploymentFallback(_ node: Node, depth: Int) -> RemanglerError {
        append("TwB")
        return .success
    }

    func mangleBackDeploymentThunk(_ node: Node, depth: Int) -> RemanglerError {
        append("Twb")
        return .success
    }

    func mangleBuiltinTupleType(_ node: Node, depth: Int) -> RemanglerError {
        append("BT")
        return .success
    }

    func mangleConcurrentFunctionType(_ node: Node, depth: Int) -> RemanglerError {
        append("Yb")
        return .success
    }

    func mangleConstrainedExistentialSelf(_ node: Node, depth: Int) -> RemanglerError {
        append("s")
        return .success
    }

    func mangleCoroFunctionPointer(_ node: Node, depth: Int) -> RemanglerError {
        append("Twc")
        return .success
    }

    func mangleDefaultOverride(_ node: Node, depth: Int) -> RemanglerError {
        append("Twd")
        return .success
    }

    func mangleDirectMethodReferenceAttribute(_ node: Node, depth: Int) -> RemanglerError {
        append("Td")
        return .success
    }

    func mangleDynamicAttribute(_ node: Node, depth: Int) -> RemanglerError {
        append("TD")
        return .success
    }

    func mangleHasSymbolQuery(_ node: Node, depth: Int) -> RemanglerError {
        append("TwS")
        return .success
    }

    func mangleImplErasedIsolation(_ node: Node, depth: Int) -> RemanglerError {
        append("A")
        return .success
    }

    func mangleIsSerialized(_ node: Node, depth: Int) -> RemanglerError {
        append("q")
        return .success
    }

    func mangleIsolatedAnyFunctionType(_ node: Node, depth: Int) -> RemanglerError {
        append("YA")
        return .success
    }

    func mangleMergedFunction(_ node: Node, depth: Int) -> RemanglerError {
        append("Tm")
        return .success
    }

    func mangleNonIsolatedCallerFunctionType(_ node: Node, depth: Int) -> RemanglerError {
        append("YC")
        return .success
    }

    func mangleNonObjCAttribute(_ node: Node, depth: Int) -> RemanglerError {
        append("TO")
        return .success
    }

    func mangleObjCAttribute(_ node: Node, depth: Int) -> RemanglerError {
        append("To")
        return .success
    }

    func mangleSendingResultFunctionType(_ node: Node, depth: Int) -> RemanglerError {
        append("YT")
        return .success
    }

    // MARK: - Child + Code (15 methods)

    func mangleCompileTimeConst(_ node: Node, depth: Int) -> RemanglerError {
        let result = mangleSingleChildNode(node, depth: depth + 1)
        if !result.isSuccess { return result }
        append("Yt")
        return .success
    }

    func mangleConstValue(_ node: Node, depth: Int) -> RemanglerError {
        let result = mangleSingleChildNode(node, depth: depth + 1)
        if !result.isSuccess { return result }
        append("Yg")
        return .success
    }

    func mangleFullObjCResilientClassStub(_ node: Node, depth: Int) -> RemanglerError {
        let result = mangleSingleChildNode(node, depth: depth + 1)
        if !result.isSuccess { return result }
        append("Mt")
        return .success
    }

    func mangleIVarDestroyer(_ node: Node, depth: Int) -> RemanglerError {
        let result = mangleSingleChildNode(node, depth: depth + 1)
        if !result.isSuccess { return result }
        append("fE")
        return .success
    }

    func mangleIVarInitializer(_ node: Node, depth: Int) -> RemanglerError {
        let result = mangleSingleChildNode(node, depth: depth + 1)
        if !result.isSuccess { return result }
        append("fe")
        return .success
    }

    func mangleIsolated(_ node: Node, depth: Int) -> RemanglerError {
        let result = mangleSingleChildNode(node, depth: depth + 1)
        if !result.isSuccess { return result }
        append("Yi")
        return .success
    }

    func mangleMetadataInstantiationCache(_ node: Node, depth: Int) -> RemanglerError {
        let result = mangleSingleChildNode(node, depth: depth + 1)
        if !result.isSuccess { return result }
        append("MK")
        return .success
    }

    func mangleMethodLookupFunction(_ node: Node, depth: Int) -> RemanglerError {
        let result = mangleSingleChildNode(node, depth: depth + 1)
        if !result.isSuccess { return result }
        append("Mu")
        return .success
    }

    func mangleNoDerivative(_ node: Node, depth: Int) -> RemanglerError {
        let result = mangleSingleChildNode(node, depth: depth + 1)
        if !result.isSuccess { return result }
        append("Yk")
        return .success
    }

    func mangleNoncanonicalSpecializedGenericTypeMetadataCache(_ node: Node, depth: Int) -> RemanglerError {
        let result = mangleSingleChildNode(node, depth: depth + 1)
        if !result.isSuccess { return result }
        append("MJ")
        return .success
    }

    func mangleObjCMetadataUpdateFunction(_ node: Node, depth: Int) -> RemanglerError {
        let result = mangleSingleChildNode(node, depth: depth + 1)
        if !result.isSuccess { return result }
        append("MU")
        return .success
    }

    func mangleObjCResilientClassStub(_ node: Node, depth: Int) -> RemanglerError {
        let result = mangleSingleChildNode(node, depth: depth + 1)
        if !result.isSuccess { return result }
        append("Ms")
        return .success
    }

    func mangleSILBoxType(_ node: Node, depth: Int) -> RemanglerError {
        let result = mangleSingleChildNode(node, depth: depth + 1)
        if !result.isSuccess { return result }
        append("Xb")
        return .success
    }

    func mangleSILThunkIdentity(_ node: Node, depth: Int) -> RemanglerError {
        let result = mangleSingleChildNode(node, depth: depth + 1)
        if !result.isSuccess { return result }
        append("TTI")
        return .success
    }

    func mangleSending(_ node: Node, depth: Int) -> RemanglerError {
        let result = mangleSingleChildNode(node, depth: depth + 1)
        if !result.isSuccess { return result }
        append("Yu")
        return .success
    }

    // MARK: - All Children + Code (9 methods)

    func mangleBuiltinFixedArray(_ node: Node, depth: Int) -> RemanglerError {
        let result = mangleChildNodes(node, depth: depth + 1)
        if !result.isSuccess { return result }
        append("BV")
        return .success
    }

    func mangleCoroutineContinuationPrototype(_ node: Node, depth: Int) -> RemanglerError {
        let result = mangleChildNodes(node, depth: depth + 1)
        if !result.isSuccess { return result }
        append("TC")
        return .success
    }

    func mangleDeallocator(_ node: Node, depth: Int) -> RemanglerError {
        let result = mangleChildNodes(node, depth: depth + 1)
        if !result.isSuccess { return result }
        append("fD")
        return .success
    }

    func mangleGlobalActorFunctionType(_ node: Node, depth: Int) -> RemanglerError {
        let result = mangleChildNodes(node, depth: depth + 1)
        if !result.isSuccess { return result }
        append("Yc")
        return .success
    }

    func mangleGlobalVariableOnceFunction(_ node: Node, depth: Int) -> RemanglerError {
        let result = mangleChildNodes(node, depth: depth + 1)
        if !result.isSuccess { return result }
        append("WZ")
        return .success
    }

    func mangleGlobalVariableOnceToken(_ node: Node, depth: Int) -> RemanglerError {
        let result = mangleChildNodes(node, depth: depth + 1)
        if !result.isSuccess { return result }
        append("Wz")
        return .success
    }

    func mangleIsolatedDeallocator(_ node: Node, depth: Int) -> RemanglerError {
        let result = mangleChildNodes(node, depth: depth + 1)
        if !result.isSuccess { return result }
        append("fZ")
        return .success
    }

    func mangleTypedThrowsAnnotation(_ node: Node, depth: Int) -> RemanglerError {
        let result = mangleChildNodes(node, depth: depth + 1)
        if !result.isSuccess { return result }
        append("YK")
        return .success
    }

    func mangleVTableThunk(_ node: Node, depth: Int) -> RemanglerError {
        let result = mangleChildNodes(node, depth: depth + 1)
        if !result.isSuccess { return result }
        append("TV")
        return .success
    }

    // MARK: - AbstractStorage Delegates (13 methods)

    func mangleGlobalGetter(_ node: Node, depth: Int) -> RemanglerError {
        guard node.children.count >= 1 else {
            return .invalidNodeStructure(node, message: "GlobalGetter needs at least 1 child")
        }
        return mangleAbstractStorage(node.children[0], accessorCode: "G", depth: depth)
    }

    func mangleInitAccessor(_ node: Node, depth: Int) -> RemanglerError {
        guard node.children.count >= 1 else {
            return .invalidNodeStructure(node, message: "InitAccessor needs at least 1 child")
        }
        return mangleAbstractStorage(node.children[0], accessorCode: "i", depth: depth)
    }

    func mangleMaterializeForSet(_ node: Node, depth: Int) -> RemanglerError {
        guard node.children.count >= 1 else {
            return .invalidNodeStructure(node, message: "MaterializeForSet needs at least 1 child")
        }
        return mangleAbstractStorage(node.children[0], accessorCode: "m", depth: depth)
    }

    func mangleModify2Accessor(_ node: Node, depth: Int) -> RemanglerError {
        guard node.children.count >= 1 else {
            return .invalidNodeStructure(node, message: "Modify2Accessor needs at least 1 child")
        }
        return mangleAbstractStorage(node.children[0], accessorCode: "x", depth: depth)
    }

    func mangleNativeOwningAddressor(_ node: Node, depth: Int) -> RemanglerError {
        guard node.children.count >= 1 else {
            return .invalidNodeStructure(node, message: "NativeOwningAddressor needs at least 1 child")
        }
        return mangleAbstractStorage(node.children[0], accessorCode: "lo", depth: depth)
    }

    func mangleNativeOwningMutableAddressor(_ node: Node, depth: Int) -> RemanglerError {
        guard node.children.count >= 1 else {
            return .invalidNodeStructure(node, message: "NativeOwningMutableAddressor needs at least 1 child")
        }
        return mangleAbstractStorage(node.children[0], accessorCode: "ao", depth: depth)
    }

    func mangleNativePinningAddressor(_ node: Node, depth: Int) -> RemanglerError {
        guard node.children.count >= 1 else {
            return .invalidNodeStructure(node, message: "NativePinningAddressor needs at least 1 child")
        }
        return mangleAbstractStorage(node.children[0], accessorCode: "lp", depth: depth)
    }

    func mangleNativePinningMutableAddressor(_ node: Node, depth: Int) -> RemanglerError {
        guard node.children.count >= 1 else {
            return .invalidNodeStructure(node, message: "NativePinningMutableAddressor needs at least 1 child")
        }
        return mangleAbstractStorage(node.children[0], accessorCode: "aP", depth: depth)
    }

    func mangleOwningAddressor(_ node: Node, depth: Int) -> RemanglerError {
        guard node.children.count >= 1 else {
            return .invalidNodeStructure(node, message: "OwningAddressor needs at least 1 child")
        }
        return mangleAbstractStorage(node.children[0], accessorCode: "lO", depth: depth)
    }

    func mangleOwningMutableAddressor(_ node: Node, depth: Int) -> RemanglerError {
        guard node.children.count >= 1 else {
            return .invalidNodeStructure(node, message: "OwningMutableAddressor needs at least 1 child")
        }
        return mangleAbstractStorage(node.children[0], accessorCode: "aO", depth: depth)
    }

    func mangleRead2Accessor(_ node: Node, depth: Int) -> RemanglerError {
        guard node.children.count >= 1 else {
            return .invalidNodeStructure(node, message: "Read2Accessor needs at least 1 child")
        }
        return mangleAbstractStorage(node.children[0], accessorCode: "y", depth: depth)
    }

    func mangleUnsafeAddressor(_ node: Node, depth: Int) -> RemanglerError {
        guard node.children.count >= 1 else {
            return .invalidNodeStructure(node, message: "UnsafeAddressor needs at least 1 child")
        }
        return mangleAbstractStorage(node.children[0], accessorCode: "lu", depth: depth)
    }

    func mangleUnsafeMutableAddressor(_ node: Node, depth: Int) -> RemanglerError {
        guard node.children.count >= 1 else {
            return .invalidNodeStructure(node, message: "UnsafeMutableAddressor needs at least 1 child")
        }
        return mangleAbstractStorage(node.children[0], accessorCode: "au", depth: depth)
    }

    // MARK: - Node Index Methods (8 methods)

    func mangleAutoDiffFunctionKind(_ node: Node, depth: Int) -> RemanglerError {
        guard let index = node.index else {
            return .invalidNodeStructure(node, message: "AutoDiffFunctionKind has no index")
        }
        // Cast index to character
        let scalar = UnicodeScalar(UInt8(index))
        append(String(Character(scalar)))
        return .success
    }

    func mangleDependentConformanceIndex(_ node: Node, depth: Int) -> RemanglerError {
        let indexValue = node.index != nil ? node.index! + 2 : 1
        mangleIndex(indexValue)
        return .success
    }

    func mangleDifferentiableFunctionType(_ node: Node, depth: Int) -> RemanglerError {
        guard let index = node.index else {
            return .invalidNodeStructure(node, message: "DifferentiableFunctionType has no index")
        }
        append("Yj")
        let scalar = UnicodeScalar(UInt8(index))
        append(String(Character(scalar)))
        return .success
    }

    func mangleDirectness(_ node: Node, depth: Int) -> RemanglerError {
        guard let index = node.index else {
            return .invalidNodeStructure(node, message: "Directness has no index")
        }
        // 0 = Direct, 1 = Indirect
        if index == 0 {
            append("d")
        } else if index == 1 {
            append("i")
        } else {
            return .invalidNodeStructure(node, message: "Invalid directness index")
        }
        return .success
    }

    func mangleDroppedArgument(_ node: Node, depth: Int) -> RemanglerError {
        guard let index = node.index else {
            return .invalidNodeStructure(node, message: "DroppedArgument has no index")
        }
        append("t")
        if index > 0 {
            append("\(index - 1)")
        }
        return .success
    }

    func mangleInteger(_ node: Node, depth: Int) -> RemanglerError {
        guard let index = node.index else {
            return .invalidNodeStructure(node, message: "Integer has no index")
        }
        append("$")
        mangleIndex(index)
        return .success
    }

    func mangleNegativeInteger(_ node: Node, depth: Int) -> RemanglerError {
        guard let index = node.index else {
            return .invalidNodeStructure(node, message: "NegativeInteger has no index")
        }
        append("$n")
        mangleIndex(0 &- index)
        return .success
    }

    func mangleSpecializationPassID(_ node: Node, depth: Int) -> RemanglerError {
        guard let index = node.index else {
            return .invalidNodeStructure(node, message: "SpecializationPassID has no index")
        }
        append("\(index)")
        return .success
    }

    // MARK: - Node Text Methods (3 methods)

    func mangleClangType(_ node: Node, depth: Int) -> RemanglerError {
        guard let text = node.text else {
            return .invalidNodeStructure(node, message: "ClangType has no text")
        }
        append("\(text.count)")
        append(text)
        return .success
    }

    func mangleIndexSubset(_ node: Node, depth: Int) -> RemanglerError {
        guard let text = node.text else {
            return .invalidNodeStructure(node, message: "IndexSubset has no text")
        }
        append(text)
        return .success
    }

    func mangleMetatypeRepresentation(_ node: Node, depth: Int) -> RemanglerError {
        guard let text = node.text else {
            return .invalidNodeStructure(node, message: "MetatypeRepresentation has no text")
        }
        switch text {
        case "@thin":
            append("t")
        case "@thick":
            append("T")
        case "@objc_metatype":
            append("o")
        default:
            return .invalidNodeStructure(node, message: "Invalid metatype representation: \(text)")
        }
        return .success
    }

    // MARK: - Complex Conditional Methods (11 methods)

    func mangleCFunctionPointer(_ node: Node, depth: Int) -> RemanglerError {
        if node.children.count > 0 && node.children[0].kind == .clangType {
            // Has ClangType child - use XzC
            for i in stride(from: node.children.count - 1, through: 1, by: -1) {
                let result = mangleChildNode(node, at: i, depth: depth + 1)
                if !result.isSuccess { return result }
            }
            append("XzC")
            return mangleClangType(node.children[0], depth: depth + 1)
        } else {
            // No ClangType - use XC
            let result = mangleChildNodesReversed(node, depth: depth + 1)
            if !result.isSuccess { return result }
            append("XC")
            return .success
        }
    }

    func mangleDependentAssociatedTypeRef(_ node: Node, depth: Int) -> RemanglerError {
        guard node.children.count >= 1 else {
            return .invalidNodeStructure(node, message: "DependentAssociatedTypeRef needs at least 1 child")
        }
        var result = mangleIdentifier(node.children[0], depth: depth)
        if !result.isSuccess { return result }

        if node.children.count > 1 {
            result = mangleChildNode(node, at: 1, depth: depth + 1)
        }
        return result
    }

    func mangleDependentProtocolConformanceOpaque(_ node: Node, depth: Int) -> RemanglerError {
        guard node.children.count >= 2 else {
            return .invalidNodeStructure(node, message: "DependentProtocolConformanceOpaque needs 2 children")
        }
        var result = mangleAnyProtocolConformance(node.children[0], depth: depth + 1)
        if !result.isSuccess { return result }

        result = mangleType(node.children[1], depth: depth + 1)
        if !result.isSuccess { return result }

        append("HO")
        return .success
    }

    func mangleEscapingObjCBlock(_ node: Node, depth: Int) -> RemanglerError {
        let result = mangleChildNodesReversed(node, depth: depth + 1)
        if !result.isSuccess { return result }
        append("XL")
        return .success
    }

    func mangleExtendedExistentialTypeShape(_ node: Node, depth: Int) -> RemanglerError {
        if node.children.count == 1 {
            // Only type
            let result = mangleNode(node.children[0], depth: depth + 1)
            if !result.isSuccess { return result }
            append("Xg")
        } else if node.children.count == 2 {
            // genSig + type
            var result = mangleNode(node.children[0], depth: depth + 1)
            if !result.isSuccess { return result }
            result = mangleNode(node.children[1], depth: depth + 1)
            if !result.isSuccess { return result }
            append("XG")
        } else {
            return .invalidNodeStructure(node, message: "ExtendedExistentialTypeShape needs 1 or 2 children")
        }
        return .success
    }

    func mangleObjCAsyncCompletionHandlerImpl(_ node: Node, depth: Int) -> RemanglerError {
        guard node.children.count >= 3 else {
            return .invalidNodeStructure(node, message: "ObjCAsyncCompletionHandlerImpl needs at least 3 children")
        }
        var result = mangleChildNode(node, at: 0, depth: depth + 1)
        if !result.isSuccess { return result }

        result = mangleChildNode(node, at: 1, depth: depth + 1)
        if !result.isSuccess { return result }

        if node.children.count == 4 {
            result = mangleChildNode(node, at: 3, depth: depth + 1)
            if !result.isSuccess { return result }
        }

        append("Tz")
        return mangleChildNode(node, at: 2, depth: depth + 1)
    }

    func mangleObjCBlock(_ node: Node, depth: Int) -> RemanglerError {
        if node.children.count > 0 && node.children[0].kind == .clangType {
            // Has ClangType child - use XzB
            for i in stride(from: node.children.count - 1, through: 1, by: -1) {
                let result = mangleChildNode(node, at: i, depth: depth + 1)
                if !result.isSuccess { return result }
            }
            append("XzB")
            return mangleClangType(node.children[0], depth: depth + 1)
        } else {
            // No ClangType - use XB
            let result = mangleChildNodesReversed(node, depth: depth + 1)
            if !result.isSuccess { return result }
            append("XB")
            return .success
        }
    }

    func mangleRelatedEntityDeclName(_ node: Node, depth: Int) -> RemanglerError {
        guard node.children.count >= 2 else {
            return .invalidNodeStructure(node, message: "RelatedEntityDeclName needs 2 children")
        }
        let result = mangleChildNode(node, at: 1, depth: depth + 1)
        if !result.isSuccess { return result }

        guard let kindText = node.children[0].text, kindText.count == 1 else {
            return .invalidNodeStructure(node, message: "RelatedEntityDeclName kind must be single character")
        }

        append("L")
        append(kindText)
        return .success
    }

    func mangleSugaredDictionary(_ node: Node, depth: Int) -> RemanglerError {
        guard node.children.count >= 2 else {
            return .invalidNodeStructure(node, message: "SugaredDictionary needs 2 children")
        }
        var result = mangleType(node.children[0], depth: depth + 1)
        if !result.isSuccess { return result }

        result = mangleType(node.children[1], depth: depth + 1)
        if !result.isSuccess { return result }

        append("XSD")
        return .success
    }

    func mangleConstrainedExistential(_ node: Node, depth: Int) -> RemanglerError {
        guard node.children.count >= 2 else {
            return .invalidNodeStructure(node, message: "ConstrainedExistential needs 2 children")
        }
        var result = mangleChildNode(node, at: 0, depth: depth + 1)
        if !result.isSuccess { return result }

        result = mangleChildNode(node, at: 1, depth: depth + 1)
        if !result.isSuccess { return result }

        append("XP")
        return .success
    }

    func mangleDependentGenericInverseConformanceRequirement(_ node: Node, depth: Int) -> RemanglerError {
        guard node.children.count >= 2 else {
            return .invalidNodeStructure(node, message: "DependentGenericInverseConformanceRequirement needs 2 children")
        }

        // This is a complex one - simplified implementation
        let result = mangleChildNodes(node, depth: depth + 1)
        if !result.isSuccess { return result }

        append("RI")
        return .success
    }

    // MARK: - Sugar Types (3 methods)

    func mangleSugaredArray(_ node: Node, depth: Int) -> RemanglerError {
        guard node.children.count >= 1 else {
            return .invalidNodeStructure(node, message: "SugaredArray needs 1 child")
        }
        let result = mangleType(node.children[0], depth: depth + 1)
        if !result.isSuccess { return result }
        append("XSa")
        return .success
    }

    func mangleSugaredOptional(_ node: Node, depth: Int) -> RemanglerError {
        guard node.children.count >= 1 else {
            return .invalidNodeStructure(node, message: "SugaredOptional needs 1 child")
        }
        let result = mangleType(node.children[0], depth: depth + 1)
        if !result.isSuccess { return result }
        append("XSq")
        return .success
    }

    func mangleSugaredParen(_ node: Node, depth: Int) -> RemanglerError {
        guard node.children.count >= 1 else {
            return .invalidNodeStructure(node, message: "SugaredParen needs 1 child")
        }
        let result = mangleType(node.children[0], depth: depth + 1)
        if !result.isSuccess { return result }
        append("XSp")
        return .success
    }

    // MARK: - Iterator/Helper Delegates (5+ methods)

    func mangleAutoDiffFunction(_ node: Node, depth: Int) -> RemanglerError {
        return mangleAutoDiffFunctionOrSimpleThunk(node, op: "TJ", depth: depth)
    }

    func mangleAutoDiffDerivativeVTableThunk(_ node: Node, depth: Int) -> RemanglerError {
        return mangleAutoDiffFunctionOrSimpleThunk(node, op: "TJV", depth: depth)
    }

    private func mangleAutoDiffFunctionOrSimpleThunk(_ node: Node, op: String, depth: Int) -> RemanglerError {
        // Mangle children before AutoDiffFunctionKind
        for child in node.children {
            if child.kind != .autoDiffFunctionKind {
                let result = mangleNode(child, depth: depth + 1)
                if !result.isSuccess { return result }
            } else {
                break
            }
        }

        append(op)

        // Find and mangle kind, parameter indices, result indices
        var paramIndices: Node? = nil
        var resultIndices: Node? = nil

        for (index, child) in node.children.enumerated() {
            if child.kind == .autoDiffFunctionKind {
                let result = mangleNode(child, depth: depth + 1)
                if !result.isSuccess { return result }

                if index + 1 < node.children.count {
                    paramIndices = node.children[index + 1]
                }
                if index + 2 < node.children.count {
                    resultIndices = node.children[index + 2]
                }
                break
            }
        }

        if let paramIndices = paramIndices {
            let result = mangleNode(paramIndices, depth: depth + 1)
            if !result.isSuccess { return result }
        }
        append("p")

        if let resultIndices = resultIndices {
            let result = mangleNode(resultIndices, depth: depth + 1)
            if !result.isSuccess { return result }
        }
        append("r")

        return .success
    }

    func mangleAutoDiffSubsetParametersThunk(_ node: Node, depth: Int) -> RemanglerError {
        // Similar to AutoDiffFunctionOrSimpleThunk but with TJS and additional P
        for child in node.children {
            if child.kind != .autoDiffFunctionKind {
                let result = mangleNode(child, depth: depth + 1)
                if !result.isSuccess { return result }
            } else {
                break
            }
        }

        append("TJS")

        // Process remaining children
        for (index, child) in node.children.enumerated() {
            if child.kind == .autoDiffFunctionKind {
                var result = mangleNode(child, depth: depth + 1)
                if !result.isSuccess { return result }

                // Mangle next 3 children
                if index + 1 < node.children.count {
                    result = mangleNode(node.children[index + 1], depth: depth + 1)
                    if !result.isSuccess { return result }
                }
                append("p")

                if index + 2 < node.children.count {
                    result = mangleNode(node.children[index + 2], depth: depth + 1)
                    if !result.isSuccess { return result }
                }
                append("r")

                if index + 3 < node.children.count {
                    result = mangleNode(node.children[index + 3], depth: depth + 1)
                    if !result.isSuccess { return result }
                }
                append("P")

                break
            }
        }

        return .success
    }

    func mangleDifferentiabilityWitness(_ node: Node, depth: Int) -> RemanglerError {
        // Mangle children before Index
        for child in node.children {
            if child.kind != .index {
                let result = mangleNode(child, depth: depth + 1)
                if !result.isSuccess { return result }
            } else {
                break
            }
        }

        // Check for DependentGenericSignature at end
        if node.children.count > 0 && node.children.last!.kind == .dependentGenericSignature {
            let result = mangleNode(node.children.last!, depth: depth + 1)
            if !result.isSuccess { return result }
        }

        append("WJ")

        // Find index child and mangle it
        for (index, child) in node.children.enumerated() {
            if child.kind == .index {
                if let idx = child.index {
                    let scalar = UnicodeScalar(UInt8(idx))
                    append(String(Character(scalar)))
                }

                // Mangle next two children (parameter and result indices)
                if index + 1 < node.children.count {
                    let result = mangleNode(node.children[index + 1], depth: depth + 1)
                    if !result.isSuccess { return result }
                }
                append("p")

                if index + 2 < node.children.count {
                    let result = mangleNode(node.children[index + 2], depth: depth + 1)
                    if !result.isSuccess { return result }
                }
                append("r")

                break
            }
        }

        return .success
    }

    func mangleGlobalVariableOnceDeclList(_ node: Node, depth: Int) -> RemanglerError {
        for child in node.children {
            let result = mangleNode(child, depth: depth + 1)
            if !result.isSuccess { return result }
            append("_")
        }
        return .success
    }

    func mangleKeyPathThunkHelper(_ node: Node, op: String, depth: Int) -> RemanglerError {
        // Mangle all non-IsSerialized children first
        for child in node.children {
            if child.kind != .isSerialized {
                let result = mangleNode(child, depth: depth + 1)
                if !result.isSuccess { return result }
            }
        }

        append(op)

        // Then mangle all IsSerialized children
        for child in node.children {
            if child.kind == .isSerialized {
                let result = mangleNode(child, depth: depth + 1)
                if !result.isSuccess { return result }
            }
        }

        return .success
    }

    func mangleKeyPathGetterThunkHelper(_ node: Node, depth: Int) -> RemanglerError {
        return mangleKeyPathThunkHelper(node, op: "TK", depth: depth)
    }

    func mangleKeyPathSetterThunkHelper(_ node: Node, depth: Int) -> RemanglerError {
        return mangleKeyPathThunkHelper(node, op: "Tk", depth: depth)
    }

    func mangleKeyPathEqualsThunkHelper(_ node: Node, depth: Int) -> RemanglerError {
        return mangleKeyPathThunkHelper(node, op: "TH", depth: depth)
    }

    func mangleKeyPathHashThunkHelper(_ node: Node, depth: Int) -> RemanglerError {
        return mangleKeyPathThunkHelper(node, op: "Th", depth: depth)
    }

    func mangleKeyPathAppliedMethodThunkHelper(_ node: Node, depth: Int) -> RemanglerError {
        return mangleKeyPathThunkHelper(node, op: "TkMA", depth: depth)
    }

    // MARK: - Pseudo/Delegate Methods (3 methods)

    func mangleDependentPseudogenericSignature(_ node: Node, depth: Int) -> RemanglerError {
        return mangleDependentGenericSignature(node, depth: depth)
    }

    func mangleInlinedGenericFunction(_ node: Node, depth: Int) -> RemanglerError {
        return mangleGenericSpecializationNode(node, specKind: "i", depth: depth)
    }

    func mangleUniquable(_ node: Node, depth: Int) -> RemanglerError {
        guard node.children.count >= 1 else {
            return .invalidNodeStructure(node, message: "Uniquable needs 1 child")
        }
        let result = mangleNode(node.children[0], depth: depth + 1)
        if !result.isSuccess { return result }
        append("Mq")
        return .success
    }

    // MARK: - Special Cases

    func mangleDefaultArgumentInitializer(_ node: Node, depth: Int) -> RemanglerError {
        guard node.children.count >= 2 else {
            return .invalidNodeStructure(node, message: "DefaultArgumentInitializer needs 2 children")
        }
        let result = mangleChildNode(node, at: 0, depth: depth + 1)
        if !result.isSuccess { return result }

        append("fA")

        return mangleChildNode(node, at: 1, depth: depth + 1)
    }

    func mangleSymbolicExtendedExistentialType(_ node: Node, depth: Int) -> RemanglerError {
        guard node.children.count >= 1 else {
            return .invalidNodeStructure(node, message: "SymbolicExtendedExistentialType needs children")
        }

        var result = mangleNode(node.children[0], depth: depth + 1)
        if !result.isSuccess { return result }

        // Mangle all children of child[1]
        if node.children.count >= 2 {
            for arg in node.children[1].children {
                result = mangleNode(arg, depth: depth + 1)
                if !result.isSuccess { return result }
            }
        }

        // Mangle all children of child[2]
        if node.children.count >= 3 {
            for conf in node.children[2].children {
                result = mangleNode(conf, depth: depth + 1)
                if !result.isSuccess { return result }
            }
        }

        return .success
    }

    func mangleSILBoxTypeWithLayout(_ node: Node, depth: Int) -> RemanglerError {
        // This is complex - simplified implementation
        guard node.children.count >= 1 && node.children[0].kind == .silBoxLayout else {
            return .invalidNodeStructure(node, message: "SILBoxTypeWithLayout needs SILBoxLayout child")
        }

        // Simplified: just mangle children
        let result = mangleChildNodes(node, depth: depth + 1)
        if !result.isSuccess { return result }

        if node.children.count == 3 {
            append("XX")
        } else {
            append("Xx")
        }

        return .success
    }

    func mangleAsyncAwaitResumePartialFunction(_ node: Node, depth: Int) -> RemanglerError {
        append("TQ")
        return mangleChildNode(node, at: 0, depth: depth + 1)
    }

    // MARK: - Error/Unsupported Methods (7 methods)

    func mangleAccessorFunctionReference(_ node: Node, depth: Int) -> RemanglerError {
        return .unsupportedNodeKind(node)
    }

    func mangleIndex(_ node: Node, depth: Int) -> RemanglerError {
        // Handled inline elsewhere
        return .unsupportedNodeKind(node)
    }

    func mangleUnknownIndex(_ node: Node, depth: Int) -> RemanglerError {
        // Handled inline elsewhere
        return .unsupportedNodeKind(node)
    }

    func mangleSILBoxImmutableField(_ node: Node, depth: Int) -> RemanglerError {
        return .unsupportedNodeKind(node)
    }

    func mangleSILBoxLayout(_ node: Node, depth: Int) -> RemanglerError {
        return .unsupportedNodeKind(node)
    }

    func mangleSILBoxMutableField(_ node: Node, depth: Int) -> RemanglerError {
        return .unsupportedNodeKind(node)
    }

    func mangleVTableAttribute(_ node: Node, depth: Int) -> RemanglerError {
        return .unsupportedNodeKind(node)
    }

    // MARK: - Additional Missing Methods (17 methods)

    func mangleAsyncSuspendResumePartialFunction(_ node: Node, depth: Int) -> RemanglerError {
        // This is handled in the function attribute mangling logic (mangleInReverseOrder)
        // The actual work happens in mangleFunctionAttribut context
        return mangleChildNodes(node, depth: depth + 1)
    }

    func mangleDependentProtocolConformanceRoot(_ node: Node, depth: Int) -> RemanglerError {
        guard node.children.count >= 3 else {
            return .invalidNodeStructure(node, message: "DependentProtocolConformanceRoot needs at least 3 children")
        }
        var result = mangleType(node.children[0], depth: depth + 1)
        if !result.isSuccess { return result }

        result = manglePureProtocol(node.children[1], depth: depth + 1)
        if !result.isSuccess { return result }

        append("HD")
        return mangleDependentConformanceIndex(node.children[2], depth: depth + 1)
    }

    func mangleDependentProtocolConformanceInherited(_ node: Node, depth: Int) -> RemanglerError {
        guard node.children.count >= 3 else {
            return .invalidNodeStructure(node, message: "DependentProtocolConformanceInherited needs at least 3 children")
        }
        var result = mangleAnyProtocolConformance(node.children[0], depth: depth + 1)
        if !result.isSuccess { return result }

        result = manglePureProtocol(node.children[1], depth: depth + 1)
        if !result.isSuccess { return result }

        append("HI")
        return mangleDependentConformanceIndex(node.children[2], depth: depth + 1)
    }

    func mangleDependentProtocolConformanceAssociated(_ node: Node, depth: Int) -> RemanglerError {
        guard node.children.count >= 3 else {
            return .invalidNodeStructure(node, message: "DependentProtocolConformanceAssociated needs at least 3 children")
        }
        var result = mangleAnyProtocolConformance(node.children[0], depth: depth + 1)
        if !result.isSuccess { return result }

        result = mangleDependentAssociatedConformance(node.children[1], depth: depth + 1)
        if !result.isSuccess { return result }

        append("HA")
        return mangleDependentConformanceIndex(node.children[2], depth: depth + 1)
    }

    func mangleDistributedAccessor(_ node: Node, depth: Int) -> RemanglerError {
        append("TF")
        return .success
    }

    func mangleDistributedThunk(_ node: Node, depth: Int) -> RemanglerError {
        append("TE")
        return .success
    }

    func mangleDynamicallyReplaceableFunctionImpl(_ node: Node, depth: Int) -> RemanglerError {
        append("TI")
        return .success
    }

    func mangleDynamicallyReplaceableFunctionKey(_ node: Node, depth: Int) -> RemanglerError {
        append("Tx")
        return .success
    }

    func mangleDynamicallyReplaceableFunctionVar(_ node: Node, depth: Int) -> RemanglerError {
        append("TX")
        return .success
    }

    func mangleGenericPartialSpecializationNotReAbstracted(_ node: Node, depth: Int) -> RemanglerError {
        return mangleGenericPartialSpecialization(node, depth: depth + 1)
    }

    func mangleGenericSpecializationInResilienceDomain(_ node: Node, depth: Int) -> RemanglerError {
        return mangleGenericSpecializationNode(node, specKind: "B", depth: depth + 1)
    }

    func mangleGenericSpecializationNotReAbstracted(_ node: Node, depth: Int) -> RemanglerError {
        return mangleGenericSpecializationNode(node, specKind: "G", depth: depth + 1)
    }

    func mangleGenericSpecializationPrespecialized(_ node: Node, depth: Int) -> RemanglerError {
        return mangleGenericSpecializationNode(node, specKind: "s", depth: depth + 1)
    }

    func mangleImplParameterResultDifferentiability(_ node: Node, depth: Int) -> RemanglerError {
        guard let text = node.text else {
            return .invalidNodeStructure(node, message: "ImplParameterResultDifferentiability has no text")
        }
        // Empty string represents default differentiability
        if text.isEmpty {
            return .success
        }
        append(text)
        return .success
    }

    func manglePropertyWrapperBackingInitializer(_ node: Node, depth: Int) -> RemanglerError {
        let result = mangleChildNodes(node, depth: depth + 1)
        if !result.isSuccess { return result }
        append("fP")
        return .success
    }

    func manglePropertyWrapperInitFromProjectedValue(_ node: Node, depth: Int) -> RemanglerError {
        let result = mangleChildNodes(node, depth: depth + 1)
        if !result.isSuccess { return result }
        append("fW")
        return .success
    }

    // MARK: - Additional 36 Missing Methods (Final Batch)

    /// Simple methods - just mangling child nodes + code
    func mangleDefaultAssociatedConformanceAccessor(_ node: Node, depth: Int) -> RemanglerError {
        guard node.children.count >= 3 else {
            return .invalidNodeStructure(node, message: "DefaultAssociatedConformanceAccessor needs at least 3 children")
        }
        var result = mangleNode(node.children[0], depth: depth + 1)
        if !result.isSuccess { return result }
        result = mangleNode(node.children[1], depth: depth + 1)
        if !result.isSuccess { return result }
        result = manglePureProtocol(node.children[2], depth: depth + 1)
        if !result.isSuccess { return result }
        append("TN")
        return .success
    }

    func mangleDefaultAssociatedTypeMetadataAccessor(_ node: Node, depth: Int) -> RemanglerError {
        let result = mangleChildNodes(node, depth: depth + 1)
        if !result.isSuccess { return result }
        append("TM")
        return .success
    }

    func mangleAssociatedTypeWitnessTableAccessor(_ node: Node, depth: Int) -> RemanglerError {
        let result = mangleChildNodes(node, depth: depth + 1)
        if !result.isSuccess { return result }
        append("WT")
        return .success
    }

    func manglePredefinedObjCAsyncCompletionHandlerImpl(_ node: Node, depth: Int) -> RemanglerError {
        let result = mangleChildNodes(node, depth: depth + 1)
        if !result.isSuccess { return result }
        append("TZ")
        return .success
    }

    func mangleLazyProtocolWitnessTableAccessor(_ node: Node, depth: Int) -> RemanglerError {
        let result = mangleChildNodes(node, depth: depth + 1)
        if !result.isSuccess { return result }
        append("Wl")
        return .success
    }

    func mangleLazyProtocolWitnessTableCacheVariable(_ node: Node, depth: Int) -> RemanglerError {
        let result = mangleChildNodes(node, depth: depth + 1)
        if !result.isSuccess { return result }
        append("WL")
        return .success
    }

    func mangleProtocolConformanceRefInTypeModule(_ node: Node, depth: Int) -> RemanglerError {
        guard node.children.count >= 1 else {
            return .invalidNodeStructure(node, message: "ProtocolConformanceRefInTypeModule needs at least 1 child")
        }
        let result = manglePureProtocol(node.children[0], depth: depth + 1)
        if !result.isSuccess { return result }
        append("HP")
        return .success
    }

    func mangleProtocolConformanceRefInProtocolModule(_ node: Node, depth: Int) -> RemanglerError {
        guard node.children.count >= 1 else {
            return .invalidNodeStructure(node, message: "ProtocolConformanceRefInProtocolModule needs at least 1 child")
        }
        let result = manglePureProtocol(node.children[0], depth: depth + 1)
        if !result.isSuccess { return result }
        append("Hp")
        return .success
    }

    func mangleProtocolConformanceRefInOtherModule(_ node: Node, depth: Int) -> RemanglerError {
        guard node.children.count >= 2 else {
            return .invalidNodeStructure(node, message: "ProtocolConformanceRefInOtherModule needs at least 2 children")
        }
        let result = manglePureProtocol(node.children[0], depth: depth + 1)
        if !result.isSuccess { return result }
        return mangleChildNode(node, at: 1, depth: depth + 1)
    }

    func mangleTypeMetadataInstantiationFunction(_ node: Node, depth: Int) -> RemanglerError {
        let result = mangleSingleChildNode(node, depth: depth + 1)
        if !result.isSuccess { return result }
        append("Mi")
        return .success
    }

    func mangleTypeMetadataSingletonInitializationCache(_ node: Node, depth: Int) -> RemanglerError {
        let result = mangleSingleChildNode(node, depth: depth + 1)
        if !result.isSuccess { return result }
        append("Ml")
        return .success
    }

    func mangleReflectionMetadataBuiltinDescriptor(_ node: Node, depth: Int) -> RemanglerError {
        let result = mangleSingleChildNode(node, depth: depth + 1)
        if !result.isSuccess { return result }
        append("MB")
        return .success
    }

    func mangleReflectionMetadataFieldDescriptor(_ node: Node, depth: Int) -> RemanglerError {
        let result = mangleSingleChildNode(node, depth: depth + 1)
        if !result.isSuccess { return result }
        append("MF")
        return .success
    }

    func mangleReflectionMetadataAssocTypeDescriptor(_ node: Node, depth: Int) -> RemanglerError {
        let result = mangleSingleChildNode(node, depth: depth + 1)
        if !result.isSuccess { return result }
        append("MA")
        return .success
    }

    func mangleReflectionMetadataSuperclassDescriptor(_ node: Node, depth: Int) -> RemanglerError {
        let result = mangleSingleChildNode(node, depth: depth + 1)
        if !result.isSuccess { return result }
        append("MC")
        return .success
    }

    func mangleOutlinedInitializeWithTakeNoValueWitness(_ node: Node, depth: Int) -> RemanglerError {
        let result = mangleChildNodes(node, depth: depth + 1)
        if !result.isSuccess { return result }
        append("WOB")
        return .success
    }

    func mangleSugaredInlineArray(_ node: Node, depth: Int) -> RemanglerError {
        guard node.children.count >= 2 else {
            return .invalidNodeStructure(node, message: "SugaredInlineArray needs at least 2 children")
        }
        var result = mangleType(node.children[0], depth: depth + 1)
        if !result.isSuccess { return result }
        result = mangleType(node.children[1], depth: depth + 1)
        if !result.isSuccess { return result }
        append("XSA")
        return .success
    }

    func mangleCanonicalSpecializedGenericMetaclass(_ node: Node, depth: Int) -> RemanglerError {
        let result = mangleChildNodes(node, depth: depth + 1)
        if !result.isSuccess { return result }
        append("MM")
        return .success
    }

    func mangleCanonicalSpecializedGenericTypeMetadataAccessFunction(_ node: Node, depth: Int) -> RemanglerError {
        let result = mangleSingleChildNode(node, depth: depth + 1)
        if !result.isSuccess { return result }
        append("Mb")
        return .success
    }

    func mangleNoncanonicalSpecializedGenericTypeMetadata(_ node: Node, depth: Int) -> RemanglerError {
        let result = mangleSingleChildNode(node, depth: depth + 1)
        if !result.isSuccess { return result }
        append("MN")
        return .success
    }

    func mangleCanonicalPrespecializedGenericTypeCachingOnceToken(_ node: Node, depth: Int) -> RemanglerError {
        let result = mangleSingleChildNode(node, depth: depth + 1)
        if !result.isSuccess { return result }
        append("Mz")
        return .success
    }

    func mangleAutoDiffSelfReorderingReabstractionThunk(_ node: Node, depth: Int) -> RemanglerError {
        var index = 0
        guard node.children.count >= 3 else {
            return .invalidNodeStructure(node, message: "AutoDiffSelfReorderingReabstractionThunk needs at least 3 children")
        }

        // from type
        var result = mangleNode(node.children[index], depth: depth + 1)
        if !result.isSuccess { return result }
        index += 1

        // to type
        result = mangleNode(node.children[index], depth: depth + 1)
        if !result.isSuccess { return result }
        index += 1

        // optional dependent generic signature
        if index < node.children.count && node.children[index].kind == .dependentGenericSignature {
            result = mangleDependentGenericSignature(node.children[index], depth: depth + 1)
            if !result.isSuccess { return result }
            index += 1
        }

        append("TJO")

        // kind
        if index < node.children.count {
            result = mangleNode(node.children[index], depth: depth + 1)
            if !result.isSuccess { return result }
        }

        return .success
    }

    func mangleKeyPathUnappliedMethodThunkHelper(_ node: Node, depth: Int) -> RemanglerError {
        return mangleKeyPathThunkHelper(node, op: "Tkmu", depth: depth + 1)
    }

    /// Complex methods with special logic
    func mangleDependentGenericConformanceRequirement(_ node: Node, depth: Int) -> RemanglerError {
        guard node.children.count == 2 else {
            return .invalidNodeStructure(node, message: "DependentGenericConformanceRequirement needs 2 children")
        }

        let protoOrClass = node.children[1]
        guard protoOrClass.children.count > 0 else {
            return .invalidNodeStructure(protoOrClass, message: "Protocol or class node has no children")
        }

        if protoOrClass.children[0].kind == .protocol {
            let result = manglePureProtocol(protoOrClass, depth: depth + 1)
            if !result.isSuccess { return result }

            let mangling = mangleConstrainedType(node.children[0], depth: depth + 1)
            if !mangling.isSuccess { return mangling.error! }

            let (numMembers, paramIdx) = mangling.value!
            guard numMembers < 0 || paramIdx != nil else {
                return .invalidNodeStructure(node, message: "Invalid constrained type result")
            }

            switch numMembers {
            case -1:
                append("RQ")
                return .success
            case 0:
                append("R")
            case 1:
                append("Rp")
            default:
                append("RP")
            }

            if let idx = paramIdx {
                mangleDependentGenericParamIndex(idx)
            }
            return .success
        }

        let result = mangleNode(protoOrClass, depth: depth + 1)
        if !result.isSuccess { return result }

        let mangling = mangleConstrainedType(node.children[0], depth: depth + 1)
        if !mangling.isSuccess { return mangling.error! }

        let (numMembers, paramIdx) = mangling.value!
        // Note: C++ has DEMANGLER_ASSERT(numMembers < 0 || paramIdx != nil, node)
        // but we continue execution even if this doesn't hold (like C++ release mode)

        switch numMembers {
        case -1:
            append("RB")
            return .success
        case 0:
            append("Rb")
        case 1:
            append("Rc")
        default:
            append("RC")
        }

        if let idx = paramIdx {
            mangleDependentGenericParamIndex(idx)
        }
        return .success
    }

    func mangleDependentGenericSameTypeRequirement(_ node: Node, depth: Int) -> RemanglerError {
        guard node.children.count >= 2 else {
            return .invalidNodeStructure(node, message: "DependentGenericSameTypeRequirement needs at least 2 children")
        }

        let result = mangleChildNode(node, at: 1, depth: depth + 1)
        if !result.isSuccess { return result }

        let mangling = mangleConstrainedType(node.children[0], depth: depth + 1)
        if !mangling.isSuccess { return mangling.error! }

        let (numMembers, paramIdx) = mangling.value!
        // Note: C++ has DEMANGLER_ASSERT(numMembers < 0 || paramIdx != nil, node)
        // but we continue execution even if this doesn't hold (like C++ release mode)

        switch numMembers {
        case -1:
            append("RS")
            return .success
        case 0:
            append("Rs")
        case 1:
            append("Rt")
        default:
            append("RT")
        }

        if let idx = paramIdx {
            mangleDependentGenericParamIndex(idx)
        }
        return .success
    }

    func mangleDependentGenericSameShapeRequirement(_ node: Node, depth: Int) -> RemanglerError {
        guard node.children.count >= 2 else {
            return .invalidNodeStructure(node, message: "DependentGenericSameShapeRequirement needs at least 2 children")
        }

        let result = mangleChildNode(node, at: 1, depth: depth + 1)
        if !result.isSuccess { return result }

        let mangling = mangleConstrainedType(node.children[0], depth: depth + 1)
        if !mangling.isSuccess { return mangling.error! }

        let (numMembers, paramIdx) = mangling.value!
        guard numMembers < 0 || paramIdx != nil else {
            return .invalidNodeStructure(node, message: "Invalid constrained type result")
        }

        guard numMembers == 0 else {
            return .invalidNodeStructure(node, message: "Invalid same-shape requirement")
        }

        append("Rh")
        if let idx = paramIdx {
            mangleDependentGenericParamIndex(idx)
        }
        return .success
    }

    func mangleDependentGenericLayoutRequirement(_ node: Node, depth: Int) -> RemanglerError {
        guard node.children.count >= 2 else {
            return .invalidNodeStructure(node, message: "DependentGenericLayoutRequirement needs at least 2 children")
        }

        let mangling = mangleConstrainedType(node.children[0], depth: depth + 1)
        if !mangling.isSuccess { return mangling.error! }

        let (numMembers, paramIdx) = mangling.value!
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
            mangleDependentGenericParamIndex(idx)
        }

        // Mangle layout constraint identifier
        guard node.children[1].kind == .identifier else {
            return .invalidNodeStructure(node, message: "Expected identifier as second child")
        }
        guard let text = node.children[1].text, text.count == 1 else {
            return .invalidNodeStructure(node, message: "Layout identifier must be single character")
        }
        append(text)

        // Optional size
        if node.children.count >= 3 {
            let result = mangleChildNode(node, at: 2, depth: depth + 1)
            if !result.isSuccess { return result }
        }

        // Optional alignment
        if node.children.count >= 4 {
            let result = mangleChildNode(node, at: 3, depth: depth + 1)
            if !result.isSuccess { return result }
        }

        return .success
    }

    func mangleConstrainedExistentialRequirementList(_ node: Node, depth: Int) -> RemanglerError {
        guard node.children.count > 0 else {
            return .invalidNodeStructure(node, message: "ConstrainedExistentialRequirementList must have children")
        }

        var firstElem = true
        for i in 0 ..< node.children.count {
            let result = mangleChildNode(node, at: i, depth: depth + 1)
            if !result.isSuccess { return result }
            mangleListSeparator(&firstElem)
        }

        return .success
    }

    func mangleFunctionSignatureSpecializationReturn(_ node: Node, depth: Int) -> RemanglerError {
        return mangleFunctionSignatureSpecializationParam(node, depth: depth + 1)
    }

    func mangleFunctionSignatureSpecializationParam(_ node: Node, depth: Int) -> RemanglerError {
        if node.children.count == 0 {
            append("n")
            return .success
        }

        // First child is kind
        guard let kindNode = node.children.first, let kindValue = kindNode.index else {
            return .invalidNodeStructure(node, message: "FunctionSignatureSpecializationParam missing kind")
        }

        // Use enum values for cleaner code
        let kind = UInt64(kindValue)

        // Check if this is a simple (non-bitfield) case first
        if let simpleKind = FunctionSigSpecializationParamKind(rawValue: kind) {
            switch simpleKind {
            case .constantPropFunction:
                append("pf")
            case .constantPropGlobal:
                append("pg")
            case .constantPropInteger:
                guard node.children.count >= 2, let text = node.children[1].text else {
                    return .invalidNodeStructure(node, message: "ConstantPropInteger missing text")
                }
                append("pi")
                append(text)
            case .constantPropFloat:
                guard node.children.count >= 2, let text = node.children[1].text else {
                    return .invalidNodeStructure(node, message: "ConstantPropFloat missing text")
                }
                append("pd")
                append(text)
            case .constantPropString:
                guard node.children.count >= 2, let encodingStr = node.children[1].text else {
                    return .invalidNodeStructure(node, message: "ConstantPropString missing encoding")
                }
                append("ps")
                if encodingStr == "u8" {
                    append("b")
                } else if encodingStr == "u16" {
                    append("w")
                } else if encodingStr == "objc" {
                    append("c")
                } else {
                    return .invalidNodeStructure(node, message: "Unknown string encoding: \(encodingStr)")
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
            case .dead,
                 .ownedToGuaranteed,
                 .sroa,
                 .guaranteedToOwned,
                 .existentialToGeneric:
                // These are handled as bitfields below
                break
            }

            // If it's a simple case, we're done
            if kind < FunctionSigSpecializationParamKind.dead.rawValue {
                return .success
            }
        }

        // Handle bitfield combinations
        let hasDead = (kind & FunctionSigSpecializationParamKind.dead.rawValue) != 0
        let hasOwnedToGuaranteed = (kind & FunctionSigSpecializationParamKind.ownedToGuaranteed.rawValue) != 0
        let hasSROA = (kind & FunctionSigSpecializationParamKind.sroa.rawValue) != 0
        let hasGuaranteedToOwned = (kind & FunctionSigSpecializationParamKind.guaranteedToOwned.rawValue) != 0
        let hasExistentialToGeneric = (kind & FunctionSigSpecializationParamKind.existentialToGeneric.rawValue) != 0

        if hasExistentialToGeneric {
            append("e")
            if hasDead {
                append("D")
            }
            if hasOwnedToGuaranteed {
                append("G")
            }
            if hasGuaranteedToOwned {
                append("O")
            }
        } else if hasDead {
            append("d")
            if hasOwnedToGuaranteed {
                append("G")
            }
            if hasGuaranteedToOwned {
                append("O")
            }
        } else if hasOwnedToGuaranteed {
            append("g")
        } else if hasGuaranteedToOwned {
            append("o")
        }

        if hasSROA {
            append("X")
        }

        return .success
    }

    func mangleAnyProtocolConformanceList(_ node: Node, depth: Int) -> RemanglerError {
        var firstElem = true
        for child in node.children {
            let result = mangleAnyProtocolConformance(child, depth: depth + 1)
            if !result.isSuccess { return result }
            mangleListSeparator(&firstElem)
        }
        mangleEndOfList(firstElem)
        return .success
    }

    /// Error/Unsupported methods
    func mangleFunctionSignatureSpecializationParamKind(_ node: Node, depth: Int) -> RemanglerError {
        // handled inline in mangleFunctionSignatureSpecializationParam
        return .unsupportedNodeKind(node)
    }

    func mangleFunctionSignatureSpecializationParamPayload(_ node: Node, depth: Int) -> RemanglerError {
        // handled inline in mangleFunctionSignatureSpecializationParam
        return .unsupportedNodeKind(node)
    }

    func mangleUniqueExtendedExistentialTypeShapeSymbolicReference(_ node: Node, depth: Int) -> RemanglerError {
        // We don't support absolute references in the mangling of these
        return .unsupportedNodeKind(node)
    }

    func mangleNonUniqueExtendedExistentialTypeShapeSymbolicReference(_ node: Node, depth: Int) -> RemanglerError {
        // We don't support absolute references in the mangling of these
        return .unsupportedNodeKind(node)
    }

    func mangleSILThunkHopToMainActorIfNeeded(_ node: Node, depth: Int) -> RemanglerError {
        // This method doesn't exist in C++ - likely a newer addition or different name
        return .unsupportedNodeKind(node)
    }

    // MARK: - Helper Methods for Dependent Types

    /// Mangle a constrained type, returning the number of chain members and the base param node
    func mangleConstrainedType(_ node: Node, depth: Int) -> RemanglerResult<(numMembers: Int, paramIdx: Node?)> {
        var currentNode = skipType(node)

        // Try substitution first
        let substResult = trySubstitution(currentNode)
        if substResult.found {
            return .success((-1, nil))
        }

        // Build chain of dependent member types
        var chain: [Node] = []
        while currentNode.kind == .dependentMemberType {
            if currentNode.children.count >= 2 {
                chain.append(currentNode.children[1])
                currentNode = skipType(currentNode.children[0])
            } else {
                break
            }
        }

        // Check if we have a dependent generic param type or constrained existential self
        if currentNode.kind != .dependentGenericParamType &&
            currentNode.kind != .constrainedExistentialSelf {
            let result = mangleNode(currentNode, depth: depth + 1)
            if !result.isSuccess {
                return .failure(result)
            }
            if chain.isEmpty {
                return .success((-1, nil))
            }
            currentNode = Node(kind: .type) // placeholder
        }

        // Mangle the chain in reverse order
        var listSeparator = chain.count > 1 ? "_" : ""
        for i in stride(from: chain.count - 1, through: 0, by: -1) {
            let depAssocTyRef = chain[i]
            let result = mangleNode(depAssocTyRef, depth: depth + 1)
            if !result.isSuccess {
                return .failure(result)
            }
            append(listSeparator)
            listSeparator = "" // After first element, no more separators
        }

        if !chain.isEmpty {
            addSubstitution(substResult.entry)
        }

        let paramNode = (currentNode.kind == .dependentGenericParamType ||
            currentNode.kind == .constrainedExistentialSelf) ? currentNode : nil

        return .success((chain.count, paramNode))
    }

    /// Mangle a dependent generic parameter index
    func mangleDependentGenericParamIndex(_ node: Node, nonZeroPrefix: String = "", zeroOp: String = "z") {
        if node.kind == .constrainedExistentialSelf {
            append("s")
            return
        }

        guard node.children.count >= 2,
              let paramDepth = node.children[0].index,
              let index = node.children[1].index else {
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
