import Foundation

/// Decode a mangled type to construct an abstract type using a custom builder.
/// This is a Swifty implementation that uses throws for error handling.
public final class TypeDecoder<Builder: TypeBuilder> {
    public typealias BuiltType = Builder.BuiltType
    public typealias BuiltTypeDecl = Builder.BuiltTypeDecl
    public typealias BuiltProtocolDecl = Builder.BuiltProtocolDecl
    public typealias Field = Builder.BuiltSILBoxField
    public typealias BuiltSubstitution = Builder.BuiltSubstitution
    public typealias BuiltRequirement = Builder.BuiltRequirement
    public typealias BuiltInverseRequirement = Builder.BuiltInverseRequirement
    public typealias BuiltLayoutConstraint = Builder.BuiltLayoutConstraint
    public typealias BuiltGenericSignature = Builder.BuiltGenericSignature
    public typealias BuiltSubstitutionMap = Builder.BuiltSubstitutionMap

    internal let builder: Builder
    internal static var maxDepth: Int { 1024 }

    public init(builder: Builder) {
        self.builder = builder
    }

    /// Given a demangle tree, attempt to turn it into a type.
    public func decodeMangledType(_ node: Node?, forRequirement: Bool = true) throws -> BuiltType {
        try decodeMangledType(node, depth: 0, forRequirement: forRequirement)
    }
}

// MARK: - Main Type Decoding
extension TypeDecoder {
    internal func decodeMangledType(
        _ node: Node?,
        depth: Int,
        forRequirement: Bool = true
    ) throws -> BuiltType {
        guard depth <= Self.maxDepth else {
            throw TypeLookupError("Mangled type is too complex")
        }

        guard let node = node else {
            throw TypeLookupError("Node is NULL")
        }

        switch node.kind {
        case .global:
            guard !node.children.isEmpty else {
                throw makeNodeError(node, "no children")
            }
            return try decodeMangledType(node.children[0], depth: depth + 1)

        case .typeMangling:
            guard !node.children.isEmpty else {
                throw makeNodeError(node, "no children")
            }
            return try decodeMangledType(node.children[0], depth: depth + 1)

        case .type:
            guard !node.children.isEmpty else {
                throw makeNodeError(node, "no children")
            }
            return try decodeMangledType(
                node.children[0],
                depth: depth + 1,
                forRequirement: forRequirement
            )

        case .class:
            #if canImport(ObjectiveC)
            if let mangledName = getObjCClassOrProtocolName(node) {
                return builder.createObjCClassType(mangledName)
            }
            #endif
            fallthrough

        case .enum, .structure, .typeAlias, .typeSymbolicReference:
            return try decodeNominalType(node, depth: depth)

        case .boundGenericEnum, .boundGenericStructure, .boundGenericClass,
             .boundGenericTypeAlias, .boundGenericOtherNominalType:
            return try decodeBoundGenericType(node, depth: depth)

        case .boundGenericProtocol:
            return try decodeBoundGenericProtocol(node, depth: depth)

        case .builtinTypeName:
            return try decodeBuiltinType(node)

        case .metatype, .existentialMetatype:
            return try decodeMetatype(node, depth: depth)

        case .symbolicExtendedExistentialType:
            return try decodeSymbolicExtendedExistentialType(node, depth: depth)

        case .protocolList, .protocolListWithAnyObject, .protocolListWithClass:
            return try decodeProtocolComposition(node, depth: depth, forRequirement: forRequirement)

        case .constrainedExistential:
            return try decodeConstrainedExistential(node, depth: depth)

        case .constrainedExistentialSelf:
            return builder.createGenericTypeParameterType(0, 0)

        case .objectiveCProtocolSymbolicReference, .protocol, .protocolSymbolicReference:
            guard let proto = decodeMangledProtocolType(node, depth: depth + 1) else {
                throw makeNodeError(node, "failed to decode protocol type")
            }
            return builder.createProtocolCompositionType(proto, nil, false, forRequirement)

        case .dynamicSelf:
            guard node.children.count == 1 else {
                throw makeNodeError(node, "expected 1 child, saw \(node.children.count)")
            }
            let selfType = try decodeMangledType(node.children[0], depth: depth + 1)
            return builder.createDynamicSelfType(selfType)

        case .dependentGenericParamType:
            guard node.children.count >= 2,
                  let depthValue = node.children[0].index,
                  let indexValue = node.children[1].index else {
                throw makeNodeError(node, "invalid generic param type")
            }
            return builder.createGenericTypeParameterType(Int(depthValue), Int(indexValue))

        case .escapingObjCBlock, .objCBlock, .cFunctionPointer, .thinFunctionType,
             .noEscapeFunctionType, .autoClosureType, .escapingAutoClosureType, .functionType:
            return try decodeFunctionType(node, depth: depth, forRequirement: forRequirement)

        case .implFunctionType:
            return try decodeImplFunctionType(node, depth: depth)

        case .argumentTuple, .returnType:
            guard !node.children.isEmpty else {
                throw makeNodeError(node, "no children")
            }
            let isReturnType = node.kind == .returnType
            return try decodeMangledType(
                node.children[0],
                depth: depth + 1,
                forRequirement: !isReturnType && forRequirement
            )

        case .tuple:
            return try decodeTuple(node, depth: depth)

        case .tupleElement:
            return try decodeTupleElement(node, depth: depth)

        case .pack, .silPackDirect, .silPackIndirect:
            return try decodePack(node, depth: depth)

        case .packExpansion:
            throw makeNodeError(node, "pack expansion type in unsupported position")

        case .dependentGenericType:
            guard node.children.count >= 2 else {
                throw makeNodeError(node, "fewer children (\(node.children.count)) than required (2)")
            }
            return try decodeMangledType(node.children[1], depth: depth + 1)

        case .dependentMemberType:
            return try decodeDependentMemberType(node, depth: depth)

        case .dependentAssociatedTypeRef:
            guard node.children.count >= 2 else {
                throw makeNodeError(node, "fewer children (\(node.children.count)) than required (2)")
            }
            return try decodeMangledType(node.children[1], depth: depth + 1)

        case .unowned, .unmanaged, .weak:
            return try decodeStorageType(node, depth: depth)

        case .silBoxType:
            guard !node.children.isEmpty else {
                throw makeNodeError(node, "no children")
            }
            let base = try decodeMangledType(node.children[0], depth: depth + 1)
            return builder.createSILBoxType(base)

        case .silBoxTypeWithLayout:
            return try decodeSILBoxTypeWithLayout(node, depth: depth)

        case .sugaredOptional, .sugaredArray, .sugaredInlineArray,
             .sugaredDictionary, .sugaredParen:
            return try decodeSugaredType(node, depth: depth)

        case .opaqueType:
            return try decodeOpaqueType(node, depth: depth)

        case .integer:
            guard let index = node.index else {
                throw makeNodeError(node, "missing index")
            }
            return builder.createIntegerType(Int(index))

        case .negativeInteger:
            guard let index = node.index else {
                throw makeNodeError(node, "missing index")
            }
            return builder.createNegativeIntegerType(Int(index))

        case .builtinFixedArray:
            guard node.children.count >= 2 else {
                throw makeNodeError(node, "fewer children (\(node.children.count)) than required (2)")
            }
            let size = try decodeMangledType(node.children[0], depth: depth + 1)
            let element = try decodeMangledType(node.children[1], depth: depth + 1)
            return builder.createBuiltinFixedArrayType(size, element)

        default:
            throw makeNodeError(node, "unexpected kind")
        }
    }
}

// MARK: - Helper Methods
extension TypeDecoder {
    internal func makeNodeError(_ node: Node, _ message: String) -> TypeLookupError {
        TypeLookupError(node: node, message)
    }

    private func decodeNominalType(_ node: Node, depth: Int) throws -> BuiltType {
        var typeDecl: BuiltTypeDecl?
        var parent: BuiltType?
        var typeAlias = false

        try decodeMangledTypeDecl(
            node,
            depth: depth,
            typeDecl: &typeDecl,
            parent: &parent,
            typeAlias: &typeAlias
        )

        guard let typeDecl = typeDecl else {
            throw makeNodeError(node, "Failed to create type decl")
        }

        if typeAlias {
            return builder.createTypeAliasType(typeDecl, parent)
        }

        return builder.createNominalType(typeDecl, parent)
    }

    private func decodeBoundGenericType(_ node: Node, depth: Int) throws -> BuiltType {
        guard node.children.count >= 2 else {
            throw makeNodeError(node, "fewer children (\(node.children.count)) than required (2)")
        }

        let args = try decodeGenericArgs(node.children[1], depth: depth + 1)

        var childNode = node.children[0]
        if childNode.kind == .type && !childNode.children.isEmpty {
            childNode = childNode.children[0]
        }

        #if canImport(ObjectiveC)
        if let mangledName = getObjCClassOrProtocolName(childNode) {
            return builder.createBoundGenericObjCClassType(mangledName, args)
        }
        #endif

        var typeDecl: BuiltTypeDecl?
        var parent: BuiltType?
        var typeAlias = false

        try decodeMangledTypeDecl(
            childNode,
            depth: depth,
            typeDecl: &typeDecl,
            parent: &parent,
            typeAlias: &typeAlias
        )

        guard let typeDecl = typeDecl else {
            throw makeNodeError(node, "Failed to create type decl")
        }

        return builder.createBoundGenericType(typeDecl, args, parent)
    }

    private func decodeBoundGenericProtocol(_ node: Node, depth: Int) throws -> BuiltType {
        guard node.children.count >= 2 else {
            throw makeNodeError(node, "fewer children (\(node.children.count)) than required (2)")
        }

        let genericArgs = node.children[1]
        guard genericArgs.children.count == 1 else {
            throw makeNodeError(genericArgs, "expected 1 generic argument, saw \(genericArgs.children.count)")
        }

        return try decodeMangledType(genericArgs.children[0], depth: depth + 1)
    }

    private func decodeBuiltinType(_ node: Node) throws -> BuiltType {
        let remangler = Remangler(usePunycode: false)
        let mangling: String
        do {
            mangling = try remangler.mangle(node)
        } catch {
            throw makeNodeError(node, "failed to mangle node")
        }
        return builder.createBuiltinType(node.text ?? "", mangling)
    }
}

// MARK: - Type Sequence Element Decoding
extension TypeDecoder {
    internal func decodeTypeSequenceElement(
        _ node: Node,
        depth: Int,
        resultCallback: (BuiltType) throws -> Void
    ) throws {
        var node = node
        if node.kind == .type {
            node = node.children[0]
        }

        if node.kind == .packExpansion {
            try decodePackExpansion(node, depth: depth, resultCallback: resultCallback)
        } else {
            let elementType = try decodeMangledType(node, depth: depth, forRequirement: false)
            try resultCallback(elementType)
        }
    }

    private func decodePackExpansion(
        _ node: Node,
        depth: Int,
        resultCallback: (BuiltType) throws -> Void
    ) throws {
        guard node.children.count >= 2 else {
            throw makeNodeError(node, "fewer children (\(node.children.count)) than required (2)")
        }

        let patternType = node.children[0]
        let countType = try decodeMangledType(node.children[1], depth: depth)

        let numElements = builder.beginPackExpansion(countType)
        defer { builder.endPackExpansion() }

        for i in 0..<numElements {
            builder.advancePackExpansion(i)
            let expandedElementType = try decodeMangledType(patternType, depth: depth)
            try resultCallback(builder.createExpandedPackElement(expandedElementType))
        }
    }
}