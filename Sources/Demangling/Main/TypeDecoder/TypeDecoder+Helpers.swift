import Foundation

// MARK: - Protocol and Existential Type Decoding
extension TypeDecoder {
    func decodeProtocolComposition(
        _ node: Node,
        depth: Int,
        forRequirement: Bool
    ) throws -> BuiltType {
        guard !node.children.isEmpty else {
            throw makeNodeError(node, "no children")
        }

        // Find the protocol list
        var protocols: [BuiltProtocolDecl] = []
        var typeList = node.children[0]

        if typeList.kind == .protocolList && !typeList.children.isEmpty {
            typeList = typeList.children[0]
        }

        // Decode the protocol list
        for componentType in typeList.children {
            guard let proto = decodeMangledProtocolType(componentType, depth: depth + 1) else {
                throw makeNodeError(componentType, "failed to decode protocol type")
            }
            protocols.append(proto)
        }

        // Handle superclass or AnyObject
        var isClassBound = false
        var superclass: BuiltType?

        switch node.kind {
        case .protocolListWithClass:
            guard node.children.count >= 2 else {
                throw makeNodeError(node, "fewer children (\(node.children.count)) than required (2)")
            }
            superclass = try decodeMangledType(node.children[1], depth: depth + 1)
            isClassBound = true

        case .protocolListWithAnyObject:
            isClassBound = true

        default:
            break
        }

        return builder.createProtocolCompositionType(protocols, superclass, isClassBound, forRequirement)
    }

    func decodeConstrainedExistential(_ node: Node, depth: Int) throws -> BuiltType {
        guard node.children.count >= 2 else {
            throw makeNodeError(node, "fewer children (\(node.children.count)) than required (2)")
        }

        let protocolType = try decodeMangledType(node.children[0], depth: depth + 1)

        var requirements: [BuiltRequirement] = []
        var inverseRequirements: [BuiltInverseRequirement] = []

        let reqts = node.children[1]
        guard reqts.kind == .constrainedExistentialRequirementList else {
            throw makeNodeError(reqts, "is not requirement list")
        }

        try decodeRequirements(
            reqts,
            requirements: &requirements,
            inverseRequirements: &inverseRequirements
        )

        return builder.createConstrainedExistentialType(protocolType, requirements, inverseRequirements)
    }

    func decodeSymbolicExtendedExistentialType(_ node: Node, depth: Int) throws -> BuiltType {
        guard node.children.count >= 2 else {
            throw makeNodeError(node, "not enough children")
        }

        let shapeNode = node.children[0]
        let args = try decodeGenericArgs(node.children[1], depth: depth + 1)

        return builder.createSymbolicExtendedExistentialType(shapeNode, args)
    }
}

// MARK: - Metatype Decoding
extension TypeDecoder {
    func decodeMetatype(_ node: Node, depth: Int) throws -> BuiltType {
        var childIndex = 0
        var repr: ImplMetatypeRepresentation?

        // Handle lowered metatypes
        if node.children.count >= 2 {
            let reprNode = node.children[childIndex]
            childIndex += 1

            guard reprNode.kind == .metatypeRepresentation,
                  let text = reprNode.text else {
                throw makeNodeError(reprNode, "wrong node kind or no text")
            }

            repr = ImplMetatypeRepresentation(from: text)
        } else if node.children.isEmpty {
            throw makeNodeError(node, "no children")
        }

        let instance = try decodeMangledType(node.children[childIndex], depth: depth + 1)

        switch node.kind {
        case .metatype:
            return builder.createMetatypeType(instance, repr)
        case .existentialMetatype:
            return builder.createExistentialMetatypeType(instance, repr)
        default:
            throw makeNodeError(node, "unexpected metatype kind")
        }
    }
}

// MARK: - Tuple and Pack Decoding
extension TypeDecoder {
    func decodeTuple(_ node: Node, depth: Int) throws -> BuiltType {
        var elements: [BuiltType] = []
        var labels: [String?] = []

        for element in node.children {
            guard element.kind == .tupleElement else {
                throw makeNodeError(element, "unexpected kind")
            }

            var typeChildIndex = 0

            // Check for variadic marker
            if typeChildIndex < element.children.count &&
               element.children[typeChildIndex].kind == .variadicMarker {
                throw makeNodeError(element.children[typeChildIndex], "variadic not supported")
            }

            // Check for label
            var label: String?
            if typeChildIndex < element.children.count &&
               element.children[typeChildIndex].kind == .tupleElementName {
                label = element.children[typeChildIndex].text
                typeChildIndex += 1
            }

            // Decode the element type
            try decodeTypeSequenceElement(
                element.children[typeChildIndex],
                depth: depth + 1
            ) { type in
                elements.append(type)
                labels.append(label)
            }
        }

        return builder.createTupleType(elements, labels)
    }

    func decodeTupleElement(_ node: Node, depth: Int) throws -> BuiltType {
        guard !node.children.isEmpty else {
            throw makeNodeError(node, "no children")
        }

        if node.children[0].kind == .tupleElementName {
            guard node.children.count >= 2 else {
                throw makeNodeError(node, "fewer children (\(node.children.count)) than required (2)")
            }
            return try decodeMangledType(node.children[1], depth: depth + 1, forRequirement: false)
        }

        return try decodeMangledType(node.children[0], depth: depth + 1, forRequirement: false)
    }

    func decodePack(_ node: Node, depth: Int) throws -> BuiltType {
        var elements: [BuiltType] = []

        for element in node.children {
            try decodeTypeSequenceElement(element, depth: depth + 1) { elementType in
                elements.append(elementType)
            }
        }

        switch node.kind {
        case .pack:
            return builder.createPackType(elements)
        case .silPackDirect:
            return builder.createSILPackType(elements, false)
        case .silPackIndirect:
            return builder.createSILPackType(elements, true)
        default:
            throw makeNodeError(node, "unexpected pack kind")
        }
    }
}

// MARK: - Dependent Type Decoding
extension TypeDecoder {
    func decodeDependentMemberType(_ node: Node, depth: Int) throws -> BuiltType {
        guard node.children.count >= 2 else {
            throw makeNodeError(node, "fewer children (\(node.children.count)) than required (2)")
        }

        let base = try decodeMangledType(node.children[0], depth: depth + 1)

        let assocTypeChild = node.children[1]
        guard let member = assocTypeChild.children.first?.text else {
            throw makeNodeError(assocTypeChild, "missing member name")
        }

        if assocTypeChild.children.count < 2 {
            return builder.createDependentMemberType(member, base)
        }

        guard let proto = decodeMangledProtocolType(assocTypeChild.children[1], depth: depth + 1) else {
            throw makeNodeError(assocTypeChild, "failed to decode protocol")
        }

        return builder.createDependentMemberType(member, base, proto)
    }
}

// MARK: - Storage Type Decoding
extension TypeDecoder {
    func decodeStorageType(_ node: Node, depth: Int) throws -> BuiltType {
        guard !node.children.isEmpty else {
            throw makeNodeError(node, "no children")
        }

        let base = try decodeMangledType(node.children[0], depth: depth + 1)

        switch node.kind {
        case .unowned:
            return builder.createUnownedStorageType(base)
        case .unmanaged:
            return builder.createUnmanagedStorageType(base)
        case .weak:
            return builder.createWeakStorageType(base)
        default:
            throw makeNodeError(node, "unexpected storage type kind")
        }
    }
}

// MARK: - Sugared Type Decoding
extension TypeDecoder {
    func decodeSugaredType(_ node: Node, depth: Int) throws -> BuiltType {
        switch node.kind {
        case .sugaredOptional:
            guard !node.children.isEmpty else {
                throw makeNodeError(node, "no children")
            }
            let base = try decodeMangledType(node.children[0], depth: depth + 1)
            return builder.createOptionalType(base)

        case .sugaredArray:
            guard !node.children.isEmpty else {
                throw makeNodeError(node, "no children")
            }
            let element = try decodeMangledType(node.children[0], depth: depth + 1)
            return builder.createArrayType(element)

        case .sugaredInlineArray:
            guard node.children.count >= 2 else {
                throw makeNodeError(node, "fewer children (\(node.children.count)) than required (2)")
            }
            let count = try decodeMangledType(node.children[0], depth: depth + 1)
            let element = try decodeMangledType(node.children[1], depth: depth + 1)
            return builder.createInlineArrayType(count, element)

        case .sugaredDictionary:
            guard node.children.count >= 2 else {
                throw makeNodeError(node, "fewer children (\(node.children.count)) than required (2)")
            }
            let key = try decodeMangledType(node.children[0], depth: depth + 1)
            let value = try decodeMangledType(node.children[1], depth: depth + 1)
            return builder.createDictionaryType(key, value)

        case .sugaredParen:
            guard !node.children.isEmpty else {
                throw makeNodeError(node, "no children")
            }
            // ParenType has been removed, return the base type
            return try decodeMangledType(node.children[0], depth: depth + 1)

        default:
            throw makeNodeError(node, "unexpected sugared type kind")
        }
    }
}

// MARK: - Opaque Type Decoding
extension TypeDecoder {
    func decodeOpaqueType(_ node: Node, depth: Int) throws -> BuiltType {
        guard node.children.count >= 3 else {
            throw makeNodeError(node, "fewer children (\(node.children.count)) than required (3)")
        }

        let descriptor = node.children[0]
        let ordinalNode = node.children[1]

        guard (ordinalNode.kind == .integer || ordinalNode.kind == .index),
              let ordinal = ordinalNode.index else {
            throw makeNodeError(ordinalNode, "unexpected kind or no index")
        }

        var genericArgsBuf: [BuiltType] = []
        var genericArgsLevels: [Int] = []
        let boundGenerics = node.children[2]

        for genericsNode in boundGenerics.children {
            genericArgsLevels.append(genericArgsBuf.count)

            guard genericsNode.kind == .typeList else {
                break
            }

            for argNode in genericsNode.children {
                let arg = try decodeMangledType(argNode, depth: depth + 1, forRequirement: false)
                genericArgsBuf.append(arg)
            }
        }
        genericArgsLevels.append(genericArgsBuf.count)

        var genericArgs: [ArraySlice<BuiltType>] = []
        for i in 0..<(genericArgsLevels.count - 1) {
            let start = genericArgsLevels[i]
            let end = genericArgsLevels[i + 1]
            genericArgs.append(genericArgsBuf[start..<end])
        }

        return builder.resolveOpaqueType(descriptor, genericArgs, ordinal)
    }
}

// MARK: - Generic Argument Decoding
extension TypeDecoder {
    func decodeGenericArgs(_ node: Node, depth: Int) throws -> [BuiltType] {
        guard node.kind == .typeList else {
            throw makeNodeError(node, "is not TypeList")
        }

        var args: [BuiltType] = []
        for genericArg in node.children {
            let paramType = try decodeMangledType(genericArg, depth: depth, forRequirement: false)
            args.append(paramType)
        }
        return args
    }
}

// MARK: - Helpers
extension ImplMetatypeRepresentation {
    init?(from text: String) {
        switch text {
        case "@thin":
            self = .thin
        case "@thick":
            self = .thick
        case "@objc_metatype":
            self = .objC
        default:
            return nil
        }
    }
}