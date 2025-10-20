import Foundation

// MARK: - Type Declaration Decoding
extension TypeDecoder {
    func decodeMangledTypeDecl(
        _ node: Node,
        depth: Int,
        typeDecl: inout BuiltTypeDecl?,
        parent: inout BuiltType?,
        typeAlias: inout Bool
    ) throws {
        guard depth <= Self.maxDepth else {
            throw TypeLookupError("Mangled type is too complex")
        }

        let node = node
        if node.kind == .type {
            try decodeMangledTypeDecl(
                node.children[0],
                depth: depth + 1,
                typeDecl: &typeDecl,
                parent: &parent,
                typeAlias: &typeAlias
            )
            return
        }

        var declNode: Node
        if node.kind == .typeSymbolicReference {
            // A symbolic reference can be directly resolved to a nominal type
            declNode = node
        } else {
            guard node.children.count >= 2 else {
                throw makeNodeError(node, "Number of node children (\(node.children.count)) less than required (2)")
            }

            var parentContext = node.children[0]

            // Nested types are handled by storing the full mangled name
            // plus a reference to the parent type
            declNode = node

            switch parentContext.kind {
            case .module:
                break

            case .extension:
                // Decode the type being extended
                guard parentContext.children.count >= 2 else {
                    throw makeNodeError(
                        parentContext,
                        "Number of parentContext children (\(parentContext.children.count)) less than required (2)"
                    )
                }
                parentContext = parentContext.children[1]
                fallthrough

            default:
                parent = try decodeMangledType(parentContext, depth: depth + 1)

                // Remove any generic arguments from the context node
                if let unspecNode = getUnspecialized(node) {
                    declNode = unspecNode
                } else {
                    throw TypeLookupError("Failed to unspecialize type")
                }
            }
        }

        typeDecl = builder.createTypeDecl(declNode, &typeAlias)
        if typeDecl == nil {
            throw TypeLookupError("Failed to create type decl")
        }
    }

    func decodeMangledProtocolType(_ node: Node, depth: Int) -> BuiltProtocolDecl? {
        guard depth <= Self.maxDepth else {
            return nil
        }

        let node = node
        if node.kind == .type {
            guard !node.children.isEmpty else { return nil }
            return decodeMangledProtocolType(node.children[0], depth: depth + 1)
        }

        // Check for valid protocol node kinds
        let isValidProtocolNode = (node.children.count >= 2 && node.kind == .protocol) ||
                                  node.kind == .protocolSymbolicReference ||
                                  node.kind == .objectiveCProtocolSymbolicReference

        guard isValidProtocolNode else {
            return nil
        }

        #if canImport(ObjectiveC)
        if let objcProtocolName = getObjCClassOrProtocolName(node) {
            return builder.createObjCProtocolDecl(objcProtocolName)
        }
        #endif

        return builder.createProtocolDecl(node)
    }
}

// MARK: - Requirements Decoding
extension TypeDecoder {
    func decodeRequirements(
        _ node: Node,
        requirements: inout [BuiltRequirement],
        inverseRequirements: inout [BuiltInverseRequirement]
    ) throws {
        for child in node.children {
            // Skip parameter count and marker nodes
            switch child.kind {
            case .dependentGenericParamCount,
                 .dependentGenericParamPackMarker,
                 .dependentGenericParamValueMarker:
                continue
            default:
                break
            }

            guard child.children.count == 2 else {
                continue
            }

            // Decode subject type
            let subjectType = try decodeMangledType(child.children[0], depth: 0)

            try decodeRequirementChild(
                child,
                subjectType: subjectType,
                requirements: &requirements,
                inverseRequirements: &inverseRequirements
            )
        }
    }

    private func decodeRequirementChild(
        _ child: Node,
        subjectType: BuiltType,
        requirements: inout [BuiltRequirement],
        inverseRequirements: inout [BuiltInverseRequirement]
    ) throws {
        switch child.kind {
        case .dependentGenericConformanceRequirement:
            let constraintType = try decodeMangledType(child.children[1], depth: 0)
            let kind: RequirementKind = builder.isExistential(constraintType) ? .conformance : .superclass
            if let requirement = createRequirement(kind: kind, subjectType: subjectType, constraintType: constraintType) {
                requirements.append(requirement)
            }

        case .dependentGenericSameTypeRequirement:
            let constraintType = try decodeMangledType(child.children[1], depth: 0, forRequirement: false)
            if let requirement = createRequirement(kind: .sameType, subjectType: subjectType, constraintType: constraintType) {
                requirements.append(requirement)
            }

        case .dependentGenericInverseConformanceRequirement:
            try decodeInverseRequirement(
                child,
                subjectType: subjectType,
                inverseRequirements: &inverseRequirements
            )

        case .dependentGenericLayoutRequirement:
            try decodeLayoutRequirement(
                child,
                subjectType: subjectType,
                requirements: &requirements
            )

        default:
            break
        }
    }

    private func decodeInverseRequirement(
        _ child: Node,
        subjectType: BuiltType,
        inverseRequirements: inout [BuiltInverseRequirement]
    ) throws {
        let constraintNode = child.children[0]
        guard constraintNode.kind == .type,
              constraintNode.children.count == 1 else {
            return
        }

        guard let index = child.children[1].index else {
            return
        }

        let protocolKind = InvertibleProtocolKind(rawValue: UInt32(index)) ?? .copyable
        let inverseReq = builder.createInverseRequirement(subjectType, protocolKind)
        inverseRequirements.append(inverseReq)
    }

    private func decodeLayoutRequirement(
        _ child: Node,
        subjectType: BuiltType,
        requirements: inout [BuiltRequirement]
    ) throws {
        let kindChild = child.children[1]
        guard kindChild.kind == .identifier,
              let text = kindChild.text else {
            return
        }

        guard let layoutKind = LayoutConstraintKind(from: text) else {
            return
        }

        let layout: BuiltLayoutConstraint
        if layoutKind.needsSizeAlignment {
            guard child.children.count >= 3,
                  let size = child.children[2].index else {
                return
            }

            var alignment = 0
            if child.children.count >= 4,
               let align = child.children[3].index {
                alignment = Int(align)
            }

            layout = builder.getLayoutConstraintWithSizeAlign(layoutKind, Int(size), alignment)
        } else {
            layout = builder.getLayoutConstraint(layoutKind)
        }

        if let requirement = createLayoutRequirement(subjectType: subjectType, layout: layout) {
            requirements.append(requirement)
        }
    }

    private func createRequirement(
        kind: RequirementKind,
        subjectType: BuiltType,
        constraintType: BuiltType
    ) -> BuiltRequirement? {
        // This would need to be implemented based on how the builder creates requirements
        // For now, returning nil to indicate it needs builder-specific implementation
        return nil
    }

    private func createLayoutRequirement(
        subjectType: BuiltType,
        layout: BuiltLayoutConstraint
    ) -> BuiltRequirement? {
        // This would need to be implemented based on how the builder creates requirements
        // For now, returning nil to indicate it needs builder-specific implementation
        return nil
    }
}

// MARK: - SIL Box Type Decoding
extension TypeDecoder {
    func decodeSILBoxTypeWithLayout(_ node: Node, depth: Int) throws -> BuiltType {
        var fields: [Field] = []
        var substitutions: [BuiltSubstitution] = []
        var requirements: [BuiltRequirement] = []
        var inverseRequirements: [BuiltInverseRequirement] = []
        var genericParams: [BuiltType] = []

        guard !node.children.isEmpty else {
            throw makeNodeError(node, "no children")
        }

        var pushedGenericParams = false
        defer {
            if pushedGenericParams {
                builder.popGenericParams()
            }
        }

        if node.children.count > 1 {
            try decodeSILBoxGenericSignature(
                node,
                depth: depth,
                genericParams: &genericParams,
                requirements: &requirements,
                inverseRequirements: &inverseRequirements,
                substitutions: &substitutions,
                pushedGenericParams: &pushedGenericParams
            )
        }

        // Decode field types
        let fieldsNode = node.children[0]
        guard fieldsNode.kind == .silBoxLayout else {
            throw makeNodeError(fieldsNode, "expected layout")
        }

        for fieldNode in fieldsNode.children {
            let field = try decodeSILBoxField(fieldNode, depth: depth)
            fields.append(field)
        }

        return builder.createSILBoxTypeWithLayout(
            fields,
            substitutions,
            requirements,
            inverseRequirements
        )
    }

    private func decodeSILBoxGenericSignature(
        _ node: Node,
        depth: Int,
        genericParams: inout [BuiltType],
        requirements: inout [BuiltRequirement],
        inverseRequirements: inout [BuiltInverseRequirement],
        substitutions: inout [BuiltSubstitution],
        pushedGenericParams: inout Bool
    ) throws {
        guard node.children.count > 2 else { return }

        let substNode = node.children[2]
        guard substNode.kind == .typeList else {
            throw makeNodeError(substNode, "expected type list")
        }

        let dependentGenericSignatureNode = node.children[1]
        guard dependentGenericSignatureNode.kind == .dependentGenericSignature else {
            throw makeNodeError(dependentGenericSignatureNode, "expected dependent generic signature")
        }

        // Count generic parameters at each depth
        var genericParamsAtDepth: [Int] = []
        for reqNode in dependentGenericSignatureNode.children {
            if reqNode.kind == .dependentGenericParamCount,
               let index = reqNode.index {
                genericParamsAtDepth.append(Int(index))
            }
        }

        // Extract parameter packs
        var parameterPacks: [(Int, Int)] = []
        for child in dependentGenericSignatureNode.children {
            if child.kind == .dependentGenericParamPackMarker {
                if child.children.count > 0,
                   let marker = child.children[0].children.first,
                   marker.children.count >= 2,
                   let depth = marker.children[0].index,
                   let index = marker.children[1].index {
                    parameterPacks.append((Int(depth), Int(index)))
                }
            }
        }

        builder.pushGenericParams(parameterPacks)
        pushedGenericParams = true

        // Decode generic parameter types
        for d in 0..<genericParamsAtDepth.count {
            for i in 0..<genericParamsAtDepth[d] {
                let paramTy = builder.createGenericTypeParameterType(d, i)
                genericParams.append(paramTy)
            }
        }

        // Decode requirements
        try decodeRequirements(
            dependentGenericSignatureNode,
            requirements: &requirements,
            inverseRequirements: &inverseRequirements
        )

        // Decode substitutions
        for (i, substChild) in substNode.children.enumerated() {
            guard i < genericParams.count else { break }
            let substTy = try decodeMangledType(substChild, depth: depth + 1, forRequirement: false)
            // Create substitution - this would need builder-specific implementation
            // For now, leaving it empty as it depends on the builder's Substitution type
        }
    }

    private func decodeSILBoxField(_ fieldNode: Node, depth: Int) throws -> Field {
        let isMutable: Bool
        switch fieldNode.kind {
        case .silBoxMutableField:
            isMutable = true
        case .silBoxImmutableField:
            isMutable = false
        default:
            throw makeNodeError(fieldNode, "unhandled field type")
        }

        guard !fieldNode.children.isEmpty else {
            throw makeNodeError(fieldNode, "no children")
        }

        let type = try decodeMangledType(fieldNode.children[0], depth: depth + 1)

        // This would need to be implemented based on how the builder creates fields
        // For now, using a placeholder - the actual implementation depends on the builder
        return type as! Field  // This cast would need proper implementation
    }
}

// MARK: - Helper Methods
extension TypeDecoder {
    func getUnspecialized(_ node: Node) -> Node? {
        // Create a copy of the node without generic arguments
        var unspecNode = node

        // Remove bound generic prefix if present
        switch unspecNode.kind {
        case .boundGenericClass:
            unspecNode = Node(kind: .class, children: node.children)
        case .boundGenericEnum:
            unspecNode = Node(kind: .enum, children: node.children)
        case .boundGenericStructure:
            unspecNode = Node(kind: .structure, children: node.children)
        case .boundGenericTypeAlias:
            unspecNode = Node(kind: .typeAlias, children: node.children)
        case .boundGenericOtherNominalType:
            // Return the first child which should be the unspecialized type
            if !unspecNode.children.isEmpty {
                return unspecNode.children[0]
            }
        default:
            break
        }

        // Remove generic arguments (typically the second child)
        if unspecNode.children.count > 1 &&
           unspecNode.children[1].kind == .typeList {
            var newChildren = unspecNode.children
            newChildren.remove(at: 1)
            return Node(kind: unspecNode.kind, children: newChildren)
        }

        return unspecNode
    }

    #if canImport(ObjectiveC)
    func getObjCClassOrProtocolName(_ node: Node) -> String? {
        guard node.kind == .class || node.kind == .protocol else {
            return nil
        }

        guard node.children.count == 2 else {
            return nil
        }

        // Check whether we have the __ObjC module
        let moduleNode = node.children[0]
        guard moduleNode.kind == .module,
              moduleNode.text == "__ObjC" else {
            return nil
        }

        // Check whether we have an identifier
        let nameNode = node.children[1]
        guard nameNode.kind == .identifier else {
            return nil
        }

        return nameNode.text
    }
    #endif
}

// MARK: - Layout Constraint Kind Extensions
extension LayoutConstraintKind {
    init?(from text: String) {
        switch text {
        case "U": self = .unknownLayout
        case "R": self = .refCountedObject
        case "N": self = .nativeRefCountedObject
        case "C": self = .class
        case "D": self = .nativeClass
        case "T": self = .trivial
        case "B": self = .bridgeObject
        case "E", "e": self = .trivialOfExactSize
        case "M", "m": self = .trivialOfAtMostSize
        case "S": self = .trivialStride
        default: return nil
        }
    }

    var needsSizeAlignment: Bool {
        switch self {
        case .trivialOfExactSize, .trivialOfAtMostSize, .trivialStride:
            return true
        default:
            return false
        }
    }
}
