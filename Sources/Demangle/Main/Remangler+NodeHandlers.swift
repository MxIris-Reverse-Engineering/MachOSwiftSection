// Extension containing specific node kind handlers
extension Remangler {
    // MARK: - Top-Level Nodes

    func mangleGlobal(_ node: Node, depth: Int) -> RemanglerError {
        // Global node wraps the actual entity
        // Format: _$s <entity>
        append("_$s")
        return mangleChildNodes(node, depth: depth + 1)
    }

    func mangleSuffix(_ node: Node, depth: Int) -> RemanglerError {
        // Suffix is appended as-is
        if let text = node.text {
            append(text)
        }
        return .success
    }

    // MARK: - Type Nodes

    func mangleType(_ node: Node, depth: Int) -> RemanglerError {
        // Type is a wrapper - mangle the actual type
        return mangleSingleChildNode(node, depth: depth)
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
        return mangleNominalType(node, op: "V", depth: depth)
    }

    func mangleClass(_ node: Node, depth: Int) -> RemanglerError {
        return mangleNominalType(node, op: "C", depth: depth)
    }

    func mangleEnum(_ node: Node, depth: Int) -> RemanglerError {
        return mangleNominalType(node, op: "O", depth: depth)
    }

    func mangleProtocol(_ node: Node, depth: Int) -> RemanglerError {
        return mangleNominalType(node, op: "P", depth: depth)
    }

    func mangleTypeAlias(_ node: Node, depth: Int) -> RemanglerError {
        return mangleNominalType(node, op: "a", depth: depth)
    }

    private func mangleNominalType(_ node: Node, op: String, depth: Int) -> RemanglerError {
        // Try substitution first
        if trySubstitution(node) {
            return .success
        }

        // Mangle context and name
        let result = mangleChildNodes(node, depth: depth + 1)
        if !result.isSuccess { return result }

        // Add type operator
        append(op)

        // Add to substitution table
        let entry = entryForNode(node)
        addSubstitution(entry)

        return .success
    }

    // MARK: - Bound Generic Types

    func mangleBoundGenericStructure(_ node: Node, depth: Int) -> RemanglerError {
        return mangleBoundGenericType(node, depth: depth)
    }

    func mangleBoundGenericClass(_ node: Node, depth: Int) -> RemanglerError {
        return mangleBoundGenericType(node, depth: depth)
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
                    if trySubstitution(node) {
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

                    // Add to substitution table
                    let entry = entryForNode(node)
                    addSubstitution(entry)

                    return .success
                }
            }
        }

        // Not Optional - use standard bound generic mangling
        return mangleBoundGenericType(node, depth: depth)
    }

    private func mangleBoundGenericType(_ node: Node, depth: Int) -> RemanglerError {
        // Try substitution first
        if trySubstitution(node) {
            return .success
        }

        // Expected structure: BoundGeneric(Type, TypeList)
        guard node.children.count >= 2 else {
            return .invalidNodeStructure(node, message: "BoundGeneric needs at least 2 children")
        }

        // Mangle the unbound type
        var result = mangleNode(node.children[0], depth: depth + 1)
        if !result.isSuccess { return result }

        // Output separator 'y' before type arguments
        append("y")

        // Mangle generic arguments (children of TypeList, not the TypeList itself)
        let typeList = node.children[1]
        guard typeList.kind == .typeList else {
            return .invalidNodeStructure(node, message: "BoundGeneric child 1 must be TypeList")
        }

        result = mangleChildNodes(typeList, depth: depth + 1)
        if !result.isSuccess { return result }

        // Add generic signature
        append("G")

        // Add to substitution table
        let entry = entryForNode(node)
        addSubstitution(entry)

        return .success
    }

    // MARK: - Function Types

    func mangleFunctionType(_ node: Node, depth: Int) -> RemanglerError {
        // Function type: reverse children (result comes first in mangling)
        let result = mangleChildNodesReversed(node, depth: depth + 1)
        if !result.isSuccess { return result }
        append("c")
        return .success
    }

    func mangleArgumentTuple(_ node: Node, depth: Int) -> RemanglerError {
        // Argument tuple - mangle as tuple
        return mangleChildNodes(node, depth: depth + 1)
    }

    func mangleReturnType(_ node: Node, depth: Int) -> RemanglerError {
        // Return type - just mangle the child
        return mangleSingleChildNode(node, depth: depth)
    }

    // MARK: - Functions and Methods

    func mangleFunction(_ node: Node, depth: Int) -> RemanglerError {
        // Function: context + name + type
        let result = mangleChildNodes(node, depth: depth + 1)
        if !result.isSuccess { return result }
        append("F")
        return .success
    }

    func mangleAllocator(_ node: Node, depth: Int) -> RemanglerError {
        return mangleConstructorLike(node, op: "fC", depth: depth)
    }

    func mangleConstructor(_ node: Node, depth: Int) -> RemanglerError {
        return mangleConstructorLike(node, op: "fc", depth: depth)
    }

    func mangleDestructor(_ node: Node, depth: Int) -> RemanglerError {
        let result = mangleChildNodes(node, depth: depth + 1)
        if !result.isSuccess { return result }
        append("fd")
        return .success
    }

    private func mangleConstructorLike(_ node: Node, op: String, depth: Int) -> RemanglerError {
        let result = mangleChildNodes(node, depth: depth + 1)
        if !result.isSuccess { return result }
        append(op)
        return .success
    }

    func mangleGetter(_ node: Node, depth: Int) -> RemanglerError {
        return mangleAccessor(node, code: "g", depth: depth)
    }

    func mangleSetter(_ node: Node, depth: Int) -> RemanglerError {
        return mangleAccessor(node, code: "s", depth: depth)
    }

    private func mangleAccessor(_ node: Node, code: String, depth: Int) -> RemanglerError {
        let result = mangleChildNodes(node, depth: depth + 1)
        if !result.isSuccess { return result }
        append("f\(code)")
        return .success
    }

    // MARK: - Identifiers and Names

    func mangleIdentifier(_ node: Node, depth: Int) -> RemanglerError {
        guard let text = node.text else {
            return .invalidNodeStructure(node, message: "Identifier has no text")
        }

        // Try substitution as identifier
        if trySubstitution(node, treatAsIdentifier: true) {
            return .success
        }

        // Mangle the identifier
        mangleIdentifierImpl(text, isOperator: false)

        // Add to substitutions
        let entry = entryForNode(node, treatAsIdentifier: true)
        addSubstitution(entry)

        return .success
    }

    func manglePrivateDeclName(_ node: Node, depth: Int) -> RemanglerError {
        guard node.children.count >= 2 else {
            return .invalidNodeStructure(node, message: "PrivateDeclName needs 2 children")
        }

        // Mangle identifier
        var result = mangleNode(node.children[0], depth: depth + 1)
        if !result.isSuccess { return result }

        // Mangle discriminator
        result = mangleNode(node.children[1], depth: depth + 1)
        if !result.isSuccess { return result }

        append("LL")
        return .success
    }

    func mangleLocalDeclName(_ node: Node, depth: Int) -> RemanglerError {
        // LocalDeclName has: number, identifier
        guard node.children.count >= 2 else {
            return .invalidNodeStructure(node, message: "LocalDeclName needs at least 2 children")
        }

        // Mangle number (discriminator)
        var result = mangleNode(node.children[0], depth: depth + 1)
        if !result.isSuccess { return result }

        // Mangle identifier
        result = mangleNode(node.children[1], depth: depth + 1)
        if !result.isSuccess { return result }

        append("L")
        return .success
    }

    private func mangleIdentifierImpl(_ text: String, isOperator: Bool) {
        // Check if we need Punycode encoding
        if usePunycode && text.unicodeScalars.contains(where: { !$0.isASCII }) {
            if let encoded = encodePunycode(text) {
                append("00\(encoded.count)")
                append(encoded)
                return
            }
        }

        // Normal identifier
        append("\(text.count)")
        append(text)
    }

    private func encodePunycode(_ text: String) -> String? {
        // Simplified Punycode encoding
        // In a full implementation, this would use proper Punycode algorithm
        return nil
    }

    // MARK: - Module and Context

    func mangleModule(_ node: Node, depth: Int) -> RemanglerError {
        guard let name = node.text else {
            return .invalidNodeStructure(node, message: "Module has no text")
        }

        // Module name
        append("\(name.count)")
        append(name)

        return .success
    }

    func mangleExtension(_ node: Node, depth: Int) -> RemanglerError {
        // Extension: module + extended type
        let result = mangleChildNodes(node, depth: depth + 1)
        if !result.isSuccess { return result }
        append("E")
        return .success
    }

    // MARK: - Built-in Types

    func mangleBuiltinTypeName(_ node: Node, depth: Int) -> RemanglerError {
        guard let name = node.text else {
            return .invalidNodeStructure(node, message: "BuiltinTypeName has no text")
        }

        append("B")

        // Handle special builtin types
        if name == "Builtin.BridgeObject" {
            append("b")
        } else if name == "Builtin.RawPointer" {
            append("p")
        } else if name == "Builtin.NativeObject" {
            append("o")
        } else if name == "Builtin.UnknownObject" {
            append("O")
        } else if name.hasPrefix("Builtin.Int") {
            let width = name.dropFirst("Builtin.Int".count)
            append("i\(width)_")
        } else if name.hasPrefix("Builtin.Float") {
            let width = name.dropFirst("Builtin.Float".count)
            append("f\(width)_")
        } else if name.hasPrefix("Builtin.Vec") {
            // Vector type
            append("v")
        } else {
            append("w")
        }

        return .success
    }

    // MARK: - Tuple Types

    func mangleTuple(_ node: Node, depth: Int) -> RemanglerError {
        if node.children.isEmpty {
            // Empty tuple
            append("yt")
            return .success
        }

        let result = mangleChildNodes(node, depth: depth + 1)
        if !result.isSuccess { return result }
        append("t")
        return .success
    }

    func mangleTupleElement(_ node: Node, depth: Int) -> RemanglerError {
        // Tuple element: optional label + type
        if node.children.count == 2 {
            // Has label
            var result = mangleNode(node.children[0], depth: depth + 1)
            if !result.isSuccess { return result }
            result = mangleNode(node.children[1], depth: depth + 1)
            return result
        } else {
            // No label
            return mangleSingleChildNode(node, depth: depth)
        }
    }

    // MARK: - Dependent Types

    func mangleDependentGenericParamType(_ node: Node, depth: Int) -> RemanglerError {
        guard node.children.count == 2,
              let paramDepth = node.children[0].index,
              let paramIndex = node.children[1].index else {
            return .invalidNodeStructure(node, message: "DependentGenericParamType invalid structure")
        }

        if paramDepth == 0 && paramIndex == 0 {
            // τ_0_0
            append("x")
        } else if paramDepth == 0 {
            // τ_0_n
            mangleIndex(Int(paramIndex) - 1)
        } else {
            // τ_d_n
            append("q")
            mangleIndex(Int(paramDepth) - 1)
            mangleIndex(Int(paramIndex))
        }

        return .success
    }

    func mangleDependentMemberType(_ node: Node, depth: Int) -> RemanglerError {
        guard node.children.count >= 2 else {
            return .invalidNodeStructure(node, message: "DependentMemberType needs at least 2 children")
        }

        // Base type
        var result = mangleNode(node.children[0], depth: depth + 1)
        if !result.isSuccess { return result }

        // Member name
        result = mangleNode(node.children[1], depth: depth + 1)
        if !result.isSuccess { return result }

        append("Qa")
        return .success
    }

    // MARK: - Protocol Composition

    func mangleProtocolList(_ node: Node, depth: Int) -> RemanglerError {
        if node.children.isEmpty {
            append("y")
        }

        var isFirst = true
        for child in node.children {
            let result = mangleNode(child, depth: depth + 1)
            if !result.isSuccess { return result }
            mangleListSeparator(&isFirst)
        }

        mangleEndOfList(isFirst)
        append("p")

        return .success
    }

    func mangleProtocolListWithClass(_ node: Node, depth: Int) -> RemanglerError {
        let result = mangleChildNodes(node, depth: depth + 1)
        if !result.isSuccess { return result }
        append("Xc")
        return .success
    }

    func mangleProtocolListWithAnyObject(_ node: Node, depth: Int) -> RemanglerError {
        let result = mangleChildNodes(node, depth: depth + 1)
        if !result.isSuccess { return result }
        append("Xl")
        return .success
    }

    // MARK: - Metatypes

    func mangleMetatype(_ node: Node, depth: Int) -> RemanglerError {
        let result = mangleSingleChildNode(node, depth: depth)
        if !result.isSuccess { return result }
        append("m")
        return .success
    }

    func mangleExistentialMetatype(_ node: Node, depth: Int) -> RemanglerError {
        let result = mangleSingleChildNode(node, depth: depth)
        if !result.isSuccess { return result }
        append("Xp")
        return .success
    }

    // MARK: - Special Types

    func mangleOptional(_ node: Node, depth: Int) -> RemanglerError {
        let result = mangleSingleChildNode(node, depth: depth)
        if !result.isSuccess { return result }
        append("Sg")
        return .success
    }

    func mangleImplicitlyUnwrappedOptional(_ node: Node, depth: Int) -> RemanglerError {
        let result = mangleSingleChildNode(node, depth: depth)
        if !result.isSuccess { return result }
        append("SG")
        return .success
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
        append("\(Int(index))")
        return .success
    }

    func mangleIndexNode(_ node: Node, depth: Int) -> RemanglerError {
        guard let index = node.index else {
            return .invalidNodeStructure(node, message: "Index has no index value")
        }
        mangleIndex(Int(index))
        return .success
    }

    // MARK: - Bound Generic Types (Additional)

    func mangleBoundGenericProtocol(_ node: Node, depth: Int) -> RemanglerError {
        return mangleBoundGenericType(node, depth: depth)
    }

    func mangleBoundGenericTypeAlias(_ node: Node, depth: Int) -> RemanglerError {
        return mangleBoundGenericType(node, depth: depth)
    }

    // MARK: - Variables and Storage

    func mangleVariable(_ node: Node, depth: Int) -> RemanglerError {
        return mangleAbstractStorage(node, op: "p", depth: depth)
    }

    func mangleSubscript(_ node: Node, depth: Int) -> RemanglerError {
        return mangleAbstractStorage(node, op: "p", depth: depth)
    }

    private func mangleAbstractStorage(_ node: Node, op: String, depth: Int) -> RemanglerError {
        let result = mangleChildNodes(node, depth: depth + 1)
        if !result.isSuccess { return result }
        append("f")
        append(op)
        return .success
    }

    func mangleDidSet(_ node: Node, depth: Int) -> RemanglerError {
        guard node.children.count >= 1 else {
            return .invalidNodeStructure(node, message: "DidSet needs at least 1 child")
        }
        return mangleAbstractStorage(node.children[0], op: "W", depth: depth)
    }

    func mangleWillSet(_ node: Node, depth: Int) -> RemanglerError {
        guard node.children.count >= 1 else {
            return .invalidNodeStructure(node, message: "WillSet needs at least 1 child")
        }
        return mangleAbstractStorage(node.children[0], op: "w", depth: depth)
    }

    func mangleReadAccessor(_ node: Node, depth: Int) -> RemanglerError {
        return mangleAccessor(node, code: "r", depth: depth)
    }

    func mangleModifyAccessor(_ node: Node, depth: Int) -> RemanglerError {
        return mangleAccessor(node, code: "M", depth: depth)
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
        // Uncurried function types are mangled the same as regular function types
        return mangleFunctionType(node, depth: depth)
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
        var result = mangleNode(node.children[1], depth: depth + 1)
        if !result.isSuccess { return result }
        result = mangleNode(node.children[0], depth: depth + 1)
        if !result.isSuccess { return result }
        append("w")
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
        let result = mangleSingleChildNode(node, depth: depth + 1)
        if !result.isSuccess { return result }
        append("Mm")
        return .success
    }

    // MARK: - Static and Class Members

    func mangleStatic(_ node: Node, depth: Int) -> RemanglerError {
        let result = mangleChildNodes(node, depth: depth + 1)
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
        guard let text = node.text else {
            return .invalidNodeStructure(node, message: "PrefixOperator has no text")
        }
        mangleIdentifierImpl(text, isOperator: true)
        append("op")
        return .success
    }

    func manglePostfixOperator(_ node: Node, depth: Int) -> RemanglerError {
        guard let text = node.text else {
            return .invalidNodeStructure(node, message: "PostfixOperator has no text")
        }
        mangleIdentifierImpl(text, isOperator: true)
        append("oP")
        return .success
    }

    func mangleInfixOperator(_ node: Node, depth: Int) -> RemanglerError {
        guard let text = node.text else {
            return .invalidNodeStructure(node, message: "InfixOperator has no text")
        }
        mangleIdentifierImpl(text, isOperator: true)
        append("oi")
        return .success
    }

    // MARK: - Generic Signature

    func mangleDependentGenericSignature(_ node: Node, depth: Int) -> RemanglerError {
        let result = mangleChildNodes(node, depth: depth + 1)
        if !result.isSuccess { return result }
        append("l")
        return .success
    }

    func mangleDependentGenericType(_ node: Node, depth: Int) -> RemanglerError {
        return mangleChildNodes(node, depth: depth + 1)
    }

    // MARK: - Throwing and Async

    func mangleThrowsAnnotation(_ node: Node, depth: Int) -> RemanglerError {
        append("K")
        return .success
    }

    func mangleAsyncAnnotation(_ node: Node, depth: Int) -> RemanglerError {
        append("Y")
        return .success
    }

    // MARK: - Context

    func mangleDeclContext(_ node: Node, depth: Int) -> RemanglerError {
        // DeclContext just mangles its single child
        return mangleSingleChildNode(node, depth: depth)
    }

    func mangleAnonymousContext(_ node: Node, depth: Int) -> RemanglerError {
        // AnonymousContext: name, parent context, optional type list
        guard node.children.count >= 2 else {
            return .invalidNodeStructure(node, message: "AnonymousContext needs at least 2 children")
        }

        // Mangle parent context
        var result = mangleNode(node.children[1], depth: depth + 1)
        if !result.isSuccess { return result }

        // Mangle name
        result = mangleNode(node.children[0], depth: depth + 1)
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
        return mangleNominalType(node, op: "XY", depth: depth)
    }

    // MARK: - Closures

    func mangleExplicitClosure(_ node: Node, depth: Int) -> RemanglerError {
        // ExplicitClosure: context, optional type, index
        let result = mangleChildNodes(node, depth: depth + 1)
        if !result.isSuccess { return result }
        append("fU")
        return .success
    }

    func mangleImplicitClosure(_ node: Node, depth: Int) -> RemanglerError {
        // ImplicitClosure: context, optional type, index
        let result = mangleChildNodes(node, depth: depth + 1)
        if !result.isSuccess { return result }
        append("fu")
        return .success
    }

    // MARK: - Label List and Tuple Element Name

    func mangleLabelList(_ node: Node, depth: Int) -> RemanglerError {
        // LabelList contains identifiers or empty placeholders
        if node.children.isEmpty {
            append("y")
            return .success
        }

        var isFirst = true
        for child in node.children {
            if child.kind == .identifier || child.kind == .firstElementMarker {
                let result = mangleNode(child, depth: depth + 1)
                if !result.isSuccess { return result }
            } else {
                // Empty label
                append("_")
            }
            mangleListSeparator(&isFirst)
        }
        mangleEndOfList(isFirst)
        return .success
    }

    func mangleTupleElementName(_ node: Node, depth: Int) -> RemanglerError {
        // Tuple element names are just text
        guard let text = node.text else {
            return .invalidNodeStructure(node, message: "TupleElementName has no text")
        }
        append("\(text.count)")
        append(text)
        return .success
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
        // FieldOffset: directness, entity
        let result = mangleChildNodes(node, depth: depth + 1)
        if !result.isSuccess { return result }
        append("Wv")
        return .success
    }

    func mangleEnumCase(_ node: Node, depth: Int) -> RemanglerError {
        let result = mangleChildNodes(node, depth: depth + 1)
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
            if trySubstitution(node) {
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

            // Add to substitutions
            let entry = entryForNode(node)
            addSubstitution(entry)

            return .success
        }

        // Handle non-specialized nominal types
        switch node.kind {
        case .structure: return mangleStructure(node, depth: depth)
        case .class: return mangleClass(node, depth: depth)
        case .enum: return mangleEnum(node, depth: depth)
        case .protocol: return mangleProtocol(node, depth: depth)
        case .typeAlias: return mangleTypeAlias(node, depth: depth)
        case .otherNominalType: return mangleOtherNominalType(node, depth: depth)
        default:
            return .invalidNodeStructure(node, message: "Not a nominal type")
        }
    }

    /// Mangle any generic type with a given type operator
    func mangleAnyGenericType(_ node: Node, typeOp: String, depth: Int) -> RemanglerError {
        // Try substitution first
        if trySubstitution(node) {
            return .success
        }

        // Mangle child nodes
        let result = mangleChildNodes(node, depth: depth + 1)
        if !result.isSuccess { return result }

        // Append type operator
        append(typeOp)

        // Add to substitutions
        let entry = entryForNode(node)
        addSubstitution(entry)

        return .success
    }

    /// Mangle generic arguments
    func mangleGenericArgs(_ node: Node, separator: inout Character, depth: Int) -> RemanglerError {
        // Find TypeList node
        guard node.children.count >= 2 else {
            return .invalidNodeStructure(node, message: "Missing generic arguments")
        }

        let typeList = node.children[1]
        guard typeList.kind == .typeList else {
            return .invalidNodeStructure(node, message: "Expected TypeList")
        }

        // Mangle each type argument
        for typeArg in typeList.children {
            // Output separator before first argument
            if separator == "y" {
                append(separator)
                separator = "_"
            }

            let result = mangleNode(typeArg, depth: depth + 1)
            if !result.isSuccess { return result }
        }

        return .success
    }

    /// Check if a node is a specialized type
    private func isSpecialized(_ node: Node) -> Bool {
        // A type is specialized if it has generic arguments
        return node.children.count >= 2 && node.children[1].kind == .typeList
    }

    /// Get the unspecialized version of a type
    private func getUnspecialized(_ node: Node) -> Node? {
        guard node.children.count >= 1 else { return nil }
        return node.children[0]
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
        if trySubstitution(node) {
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

        // Add to substitutions
        let entry = entryForNode(node)
        addSubstitution(entry)

        return .success
    }

    func mangleBoundGenericOtherNominalType(_ node: Node, depth: Int) -> RemanglerError {
        return mangleBoundGenericType(node, depth: depth)
    }

    // MARK: - Associated Types

    func mangleAssociatedType(_ node: Node, depth: Int) -> RemanglerError {
        // Associated types are not directly mangleable
        return .unsupportedNodeKind(node)
    }

    func mangleAssociatedTypeRef(_ node: Node, depth: Int) -> RemanglerError {
        // Try substitution first
        if trySubstitution(node) {
            return .success
        }

        let result = mangleChildNodes(node, depth: depth + 1)
        if !result.isSuccess { return result }

        append("Qa")

        // Add to substitutions
        let entry = entryForNode(node)
        addSubstitution(entry)

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
        return mangleChildNodes(node, depth: depth + 1)
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
            result = mangleNode(node.children[3], depth: depth + 1)
            if !result.isSuccess { return result }
        }

        // Mangle protocol
        result = manglePureProtocol(node.children[1], depth: depth + 1)
        if !result.isSuccess { return result }

        // Mangle conformance reference
        result = mangleNode(node.children[2], depth: depth + 1)
        if !result.isSuccess { return result }

        // Mangle generic signature if present
        if let genSig = genSig {
            result = mangleNode(genSig, depth: depth + 1)
            if !result.isSuccess { return result }
        }

        return .success
    }

    func mangleConcreteProtocolConformance(_ node: Node, depth: Int) -> RemanglerError {
        return mangleProtocolConformance(node, depth: depth)
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
        return mangleNode(node, depth: depth)
    }

    func mangleAnyProtocolConformanceList(_ node: Node, depth: Int) -> RemanglerError {
        // Mangle list of protocol conformances
        return mangleChildNodes(node, depth: depth + 1)
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
        let result = mangleChildNodes(node, depth: depth + 1)
        if !result.isSuccess { return result }
        append("Mp")
        return .success
    }

    func mangleProtocolDescriptorRecord(_ node: Node, depth: Int) -> RemanglerError {
        let result = mangleChildNodes(node, depth: depth + 1)
        if !result.isSuccess { return result }
        append("Hp")
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
        let result = mangleChildNodes(node, depth: depth + 1)
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
        return mangleChildNodes(node, depth: depth + 1)
    }

    func mangleRetroactiveConformance(_ node: Node, depth: Int) -> RemanglerError {
        return mangleChildNodes(node, depth: depth + 1)
    }

    // MARK: - Outlined Operations (High Priority)

    func mangleOutlinedCopy(_ node: Node, depth: Int) -> RemanglerError {
        let result = mangleChildNodes(node, depth: depth + 1)
        if !result.isSuccess { return result }
        append("Wy")
        return .success
    }

    func mangleOutlinedConsume(_ node: Node, depth: Int) -> RemanglerError {
        let result = mangleChildNodes(node, depth: depth + 1)
        if !result.isSuccess { return result }
        append("We")
        return .success
    }

    func mangleOutlinedRetain(_ node: Node, depth: Int) -> RemanglerError {
        let result = mangleChildNodes(node, depth: depth + 1)
        if !result.isSuccess { return result }
        append("Wh")
        return .success
    }

    func mangleOutlinedRelease(_ node: Node, depth: Int) -> RemanglerError {
        let result = mangleChildNodes(node, depth: depth + 1)
        if !result.isSuccess { return result }
        append("Wr")
        return .success
    }

    func mangleOutlinedDestroy(_ node: Node, depth: Int) -> RemanglerError {
        let result = mangleChildNodes(node, depth: depth + 1)
        if !result.isSuccess { return result }
        append("Wz")
        return .success
    }

    func mangleOutlinedInitializeWithTake(_ node: Node, depth: Int) -> RemanglerError {
        let result = mangleChildNodes(node, depth: depth + 1)
        if !result.isSuccess { return result }
        append("WB")
        return .success
    }

    func mangleOutlinedInitializeWithCopy(_ node: Node, depth: Int) -> RemanglerError {
        let result = mangleChildNodes(node, depth: depth + 1)
        if !result.isSuccess { return result }
        append("Wc")
        return .success
    }

    func mangleOutlinedAssignWithTake(_ node: Node, depth: Int) -> RemanglerError {
        let result = mangleChildNodes(node, depth: depth + 1)
        if !result.isSuccess { return result }
        append("Wd")
        return .success
    }

    func mangleOutlinedAssignWithCopy(_ node: Node, depth: Int) -> RemanglerError {
        let result = mangleChildNodes(node, depth: depth + 1)
        if !result.isSuccess { return result }
        append("Wf")
        return .success
    }

    func mangleOutlinedVariable(_ node: Node, depth: Int) -> RemanglerError {
        let result = mangleChildNodes(node, depth: depth + 1)
        if !result.isSuccess { return result }
        append("Tv")
        return .success
    }

    func mangleOutlinedEnumGetTag(_ node: Node, depth: Int) -> RemanglerError {
        let result = mangleChildNodes(node, depth: depth + 1)
        if !result.isSuccess { return result }
        append("Wg")
        return .success
    }

    func mangleOutlinedEnumProjectDataForLoad(_ node: Node, depth: Int) -> RemanglerError {
        let result = mangleChildNodes(node, depth: depth + 1)
        if !result.isSuccess { return result }
        append("Wl")
        return .success
    }

    func mangleOutlinedEnumTagStore(_ node: Node, depth: Int) -> RemanglerError {
        let result = mangleChildNodes(node, depth: depth + 1)
        if !result.isSuccess { return result }
        append("Ws")
        return .success
    }

    // No ValueWitness variants
    func mangleOutlinedDestroyNoValueWitness(_ node: Node, depth: Int) -> RemanglerError {
        let result = mangleChildNodes(node, depth: depth + 1)
        if !result.isSuccess { return result }
        append("WZ")
        return .success
    }

    func mangleOutlinedInitializeWithCopyNoValueWitness(_ node: Node, depth: Int) -> RemanglerError {
        let result = mangleChildNodes(node, depth: depth + 1)
        if !result.isSuccess { return result }
        append("WC")
        return .success
    }

    func mangleOutlinedAssignWithTakeNoValueWitness(_ node: Node, depth: Int) -> RemanglerError {
        let result = mangleChildNodes(node, depth: depth + 1)
        if !result.isSuccess { return result }
        append("WD")
        return .success
    }

    func mangleOutlinedAssignWithCopyNoValueWitness(_ node: Node, depth: Int) -> RemanglerError {
        let result = mangleChildNodes(node, depth: depth + 1)
        if !result.isSuccess { return result }
        append("WF")
        return .success
    }

    func mangleOutlinedBridgedMethod(_ node: Node, depth: Int) -> RemanglerError {
        let result = mangleChildNodes(node, depth: depth + 1)
        if !result.isSuccess { return result }
        append("Te")
        return .success
    }

    func mangleOutlinedReadOnlyObject(_ node: Node, depth: Int) -> RemanglerError {
        let result = mangleChildNodes(node, depth: depth + 1)
        if !result.isSuccess { return result }
        append("Tf")
        return .success
    }

    // MARK: - Pack Support (High Priority)

    func manglePack(_ node: Node, depth: Int) -> RemanglerError {
        let result = mangleChildNodes(node, depth: depth + 1)
        if !result.isSuccess { return result }
        append("Pk")
        return .success
    }

    func manglePackElement(_ node: Node, depth: Int) -> RemanglerError {
        let result = mangleChildNodes(node, depth: depth + 1)
        if !result.isSuccess { return result }
        append("Xe")
        return .success
    }

    func manglePackElementLevel(_ node: Node, depth: Int) -> RemanglerError {
        let result = mangleChildNodes(node, depth: depth + 1)
        if !result.isSuccess { return result }
        append("XL")
        return .success
    }

    func manglePackExpansion(_ node: Node, depth: Int) -> RemanglerError {
        let result = mangleChildNodes(node, depth: depth + 1)
        if !result.isSuccess { return result }
        append("XP")
        return .success
    }

    func manglePackProtocolConformance(_ node: Node, depth: Int) -> RemanglerError {
        let result = mangleChildNodes(node, depth: depth + 1)
        if !result.isSuccess { return result }
        append("XK")
        return .success
    }

    func mangleSILPackDirect(_ node: Node, depth: Int) -> RemanglerError {
        let result = mangleChildNodes(node, depth: depth + 1)
        if !result.isSuccess { return result }
        append("Xd")
        return .success
    }

    func mangleSILPackIndirect(_ node: Node, depth: Int) -> RemanglerError {
        let result = mangleChildNodes(node, depth: depth + 1)
        if !result.isSuccess { return result }
        append("Xi")
        return .success
    }

    // MARK: - Generic Specialization

    func mangleGenericSpecialization(_ node: Node, depth: Int) -> RemanglerError {
        return mangleGenericSpecializationNode(node, specKind: "g", depth: depth)
    }

    func mangleGenericPartialSpecialization(_ node: Node, depth: Int) -> RemanglerError {
        return mangleGenericSpecializationNode(node, specKind: "p", depth: depth)
    }

    private func mangleGenericSpecializationNode(_ node: Node, specKind: String, depth: Int) -> RemanglerError {
        // Mangle the specialized entity
        guard node.children.count >= 2 else {
            return .invalidNodeStructure(node, message: "GenericSpecialization needs at least 2 children")
        }

        var result = mangleNode(node.children[0], depth: depth + 1)
        if !result.isSuccess { return result }

        // Mangle specialization parameters
        for i in 1..<node.children.count {
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
        return mangleChildNodes(node, depth: depth + 1)
    }

    func mangleDependentGenericParamCount(_ node: Node, depth: Int) -> RemanglerError {
        guard let count = node.index else {
            return .invalidNodeStructure(node, message: "DependentGenericParamCount has no index")
        }
        append("\(count)")
        return .success
    }

    func mangleDependentGenericParamPackMarker(_ node: Node, depth: Int) -> RemanglerError {
        append("Xp")
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
            case .implParameter, .implResult, .implYield, .implErrorResult:
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

            // Mangle parameter convention
            let result = mangleNode(child.children[0], depth: depth + 1)
            if !result.isSuccess { return result }

            mangleListSeparator(&isFirst)
        }
        mangleEndOfList(isFirst)

        // Output results with conventions
        isFirst = true
        for child in node.children where child.kind == .implResult || child.kind == .implYield {
            guard child.children.count >= 2 else { continue }

            // Mangle result convention
            let result = mangleNode(child.children[0], depth: depth + 1)
            if !result.isSuccess { return result }

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
        return mangleChildNodes(node, depth: depth + 1)
    }

    func mangleImplResult(_ node: Node, depth: Int) -> RemanglerError {
        return mangleChildNodes(node, depth: depth + 1)
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
        switch text {
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
        guard let text = node.text else {
            return .invalidNodeStructure(node, message: "ImplFunctionConvention has no text")
        }

        // Map function convention names
        switch text {
        case "thin": append("t")
        case "c": append("c")
        case "block": append("b")
        case "method": append("m")
        case "witness_method": append("w")
        case "closure": append("k")
        default:
            return .invalidNodeStructure(node, message: "Unknown function convention: \(text)")
        }

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
        if node.children.count > 1 {
            // Has identifier
            result = mangleNode(node.children[1], depth: depth + 1)
            if !result.isSuccess { return result }
            append("MXY")
        } else {
            // No identifier
            append("MXX")
        }

        return .success
    }

    func mangleExtensionDescriptor(_ node: Node, depth: Int) -> RemanglerError {
        let result = mangleSingleChildNode(node, depth: depth + 1)
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
        let result = mangleSingleChildNode(node, depth: depth + 1)
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

        let result = manglePureProtocol(node.children[0], depth: depth + 1)
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
        let result = mangleChildNodes(node, depth: depth + 1)
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
        if trySubstitution(node) {
            return .success
        }

        guard node.children.count >= 2 else {
            return .invalidNodeStructure(node, message: "OpaqueType needs at least 2 children")
        }

        // Mangle first child (bound types)
        var result = mangleNode(node.children[0], depth: depth + 1)
        if !result.isSuccess { return result }

        // Mangle additional type arguments if present
        for i in 2..<node.children.count {
            result = mangleNode(node.children[i], depth: depth + 1)
            if !result.isSuccess { return result }
        }

        append("Qo")

        // Mangle index from second child
        if let index = node.children[1].index {
            mangleIndex(Int(index))
        }

        // Add to substitutions
        let entry = entryForNode(node)
        addSubstitution(entry)

        return .success
    }

    func mangleOpaqueReturnType(_ node: Node, depth: Int) -> RemanglerError {
        guard node.children.count >= 1 else {
            return .invalidNodeStructure(node, message: "OpaqueReturnType needs at least 1 child")
        }

        // Check if first child is OpaqueReturnTypeIndex
        if node.children.count >= 2 && node.children[0].kind == .opaqueReturnTypeIndex {
            // Has index
            let result = mangleNode(node.children[1], depth: depth + 1)
            if !result.isSuccess { return result }

            append("QR")

            if let index = node.children[0].index {
                mangleIndex(Int(index))
            }
        } else {
            // No index
            let result = mangleNode(node.children[0], depth: depth + 1)
            if !result.isSuccess { return result }

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
        let result = mangleSingleChildNode(node, depth: depth + 1)
        if !result.isSuccess { return result }
        append("TA")
        return .success
    }

    func manglePartialApplyObjCForwarder(_ node: Node, depth: Int) -> RemanglerError {
        let result = mangleSingleChildNode(node, depth: depth + 1)
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
            mangleIndex(Int(line))
        }

        if node.children.count >= 4, let col = node.children[3].index {
            mangleIndex(Int(col))
        }

        return .success
    }

    func mangleMacroExpansionUniqueName(_ node: Node, depth: Int) -> RemanglerError {
        return mangleChildNodes(node, depth: depth + 1)
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
}
