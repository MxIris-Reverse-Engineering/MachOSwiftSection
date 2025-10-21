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

        case .enum,
             .structure,
             .typeAlias,
             .typeSymbolicReference:
            return try decodeNominalType(node, depth: depth)

        case .boundGenericEnum,
             .boundGenericStructure,
             .boundGenericClass,
             .boundGenericTypeAlias,
             .boundGenericOtherNominalType:
            return try decodeBoundGenericType(node, depth: depth)

        case .boundGenericProtocol:
            return try decodeBoundGenericProtocol(node, depth: depth)

        case .builtinTypeName:
            return try decodeBuiltinType(node)

        case .metatype,
             .existentialMetatype:
            return try decodeMetatype(node, depth: depth)

        case .symbolicExtendedExistentialType:
            return try decodeSymbolicExtendedExistentialType(node, depth: depth)

        case .protocolList,
             .protocolListWithAnyObject,
             .protocolListWithClass:
            return try decodeProtocolComposition(node, depth: depth, forRequirement: forRequirement)

        case .constrainedExistential:
            return try decodeConstrainedExistential(node, depth: depth)

        case .constrainedExistentialSelf:
            return builder.createGenericTypeParameterType(0, 0)

        case .objectiveCProtocolSymbolicReference,
             .protocol,
             .protocolSymbolicReference:
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

        case .escapingObjCBlock,
             .objCBlock,
             .cFunctionPointer,
             .thinFunctionType,
             .noEscapeFunctionType,
             .autoClosureType,
             .escapingAutoClosureType,
             .functionType:
            return try decodeFunctionType(node, depth: depth, forRequirement: forRequirement)

        case .implFunctionType:
            return try decodeImplFunctionType(node, depth: depth)

        case .argumentTuple,
             .returnType:
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

        case .pack,
             .silPackDirect,
             .silPackIndirect:
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

        case .unowned,
             .unmanaged,
             .weak:
            return try decodeStorageType(node, depth: depth)

        case .silBoxType:
            guard !node.children.isEmpty else {
                throw makeNodeError(node, "no children")
            }
            let base = try decodeMangledType(node.children[0], depth: depth + 1)
            return builder.createSILBoxType(base)

        case .silBoxTypeWithLayout:
            return try decodeSILBoxTypeWithLayout(node, depth: depth)

        case .sugaredOptional,
             .sugaredArray,
             .sugaredInlineArray,
             .sugaredDictionary,
             .sugaredParen:
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

        for i in 0 ..< numElements {
            builder.advancePackExpansion(i)
            let expandedElementType = try decodeMangledType(patternType, depth: depth)
            try resultCallback(builder.createExpandedPackElement(expandedElementType))
        }
    }
}

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

        guard ordinalNode.kind == .integer || ordinalNode.kind == .index,
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
        for i in 0 ..< (genericArgsLevels.count - 1) {
            let start = genericArgsLevels[i]
            let end = genericArgsLevels[i + 1]
            genericArgs.append(genericArgsBuf[start ..< end])
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

import Foundation

// MARK: - Function Type Decoding

extension TypeDecoder {
    func decodeFunctionType(
        _ node: Node,
        depth: Int,
        forRequirement: Bool
    ) throws -> BuiltType {
        guard node.children.count >= 2 else {
            throw makeNodeError(node, "fewer children (\(node.children.count)) than required (2)")
        }

        var flags = FunctionTypeFlags()
        var extFlags = ExtendedFunctionTypeFlags()

        // Set convention based on node kind
        flags = flags.withConvention(functionConvention(for: node.kind))

        var childIndex = 0

        // Skip ClangType if present
        if childIndex < node.children.count && node.children[childIndex].kind == .clangType {
            childIndex += 1
        }

        // Handle sending result
        if childIndex < node.children.count && node.children[childIndex].kind == .sendingResultFunctionType {
            extFlags = extFlags.withSendingResult()
            childIndex += 1
        }

        // Handle global actor and isolation
        let (globalActorType, newExtFlags, newIndex) = try decodeGlobalActorAndIsolation(
            node: node,
            startIndex: childIndex,
            depth: depth,
            extFlags: extFlags
        )
        extFlags = newExtFlags
        childIndex = newIndex

        // Handle differentiability
        let (diffKind, nextIndex) = try decodeDifferentiability(node: node, startIndex: childIndex)
        childIndex = nextIndex

        // Handle throws
        let (thrownErrorType, isThrow, throwsIndex) = try decodeThrows(
            node: node,
            startIndex: childIndex,
            depth: depth,
            extFlags: &extFlags
        )
        childIndex = throwsIndex

        // Handle sendable/concurrent
        var isSendable = false
        if childIndex < node.children.count && node.children[childIndex].kind == .concurrentFunctionType {
            isSendable = true
            childIndex += 1
        }

        // Handle async
        var isAsync = false
        if childIndex < node.children.count && node.children[childIndex].kind == .asyncAnnotation {
            isAsync = true
            childIndex += 1
        }

        // Update flags
        flags = flags
            .withSendable(isSendable)
            .withAsync(isAsync)
            .withThrows(isThrow)
            .withDifferentiable(diffKind.isDifferentiable)

        guard node.children.count >= childIndex + 2 else {
            throw makeNodeError(node, "fewer children (\(node.children.count)) than required (\(childIndex + 2))")
        }

        // Decode parameters
        let (parameters, hasParamFlags) = try decodeFunctionParameters(
            node.children[childIndex],
            depth: depth + 1
        )

        flags = flags
            .withNumParameters(parameters.count)
            .withParameterFlags(hasParamFlags)
            .withEscaping(isEscapingFunction(node.kind))

        // Decode result type
        let resultType = try decodeMangledType(
            node.children[childIndex + 1],
            depth: depth + 1,
            forRequirement: false
        )

        if extFlags != ExtendedFunctionTypeFlags() {
            flags = flags.withExtendedFlags(true)
        }

        return builder.createFunctionType(
            parameters,
            resultType,
            flags,
            extFlags,
            diffKind,
            globalActorType,
            thrownErrorType
        )
    }

    func decodeImplFunctionType(_ node: Node, depth: Int) throws -> BuiltType {
        var calleeConvention = ImplParameterConvention.directUnowned
        var parameters: [ImplFunctionParam<BuiltType>] = []
        var yields: [ImplFunctionYield<BuiltType>] = []
        var results: [ImplFunctionResult<BuiltType>] = []
        var errorResults: [ImplFunctionResult<BuiltType>] = []
        var flags = ImplFunctionTypeFlags()
        var coroutineKind = ImplCoroutineKind.none

        for child in node.children {
            switch child.kind {
            case .implConvention:
                (calleeConvention, flags) = try decodeImplConvention(child, flags: flags)

            case .implFunctionConvention:
                flags = try decodeImplFunctionConvention(child, flags: flags)

            case .implFunctionAttribute:
                flags = try decodeImplFunctionAttribute(child, flags: flags)

            case .implSendingResult:
                flags = flags.withSendingResult()

            case .implCoroutineKind:
                coroutineKind = try decodeImplCoroutineKind(child)

            case .implDifferentiabilityKind:
                flags = try decodeImplDifferentiabilityKind(child, flags: flags)

            case .implEscaping:
                flags = flags.withEscaping()

            case .implErasedIsolation:
                flags = flags.withErasedIsolation()

            case .implParameter:
                try decodeImplFunctionParam(child, depth: depth + 1, results: &parameters)

            case .implYield:
                try decodeImplFunctionParam(child, depth: depth + 1, results: &yields)

            case .implResult:
                try decodeImplFunctionResult(child, depth: depth + 1, results: &results)

            case .implErrorResult:
                try decodeImplFunctionResult(child, depth: depth + 1, results: &errorResults)

            default:
                throw makeNodeError(child, "unexpected kind")
            }
        }

        let errorResult: ImplFunctionResult<BuiltType>?
        switch errorResults.count {
        case 0:
            errorResult = nil
        case 1:
            errorResult = errorResults[0]
        default:
            throw makeNodeError(node, "got \(errorResults.count) errors")
        }

        return builder.createImplFunctionType(
            calleeConvention,
            coroutineKind,
            parameters,
            yields,
            results,
            errorResult,
            flags
        )
    }
}

// MARK: - Function Type Helper Methods

extension TypeDecoder {
    fileprivate func functionConvention(for kind: Node.Kind) -> FunctionMetadataConvention {
        switch kind {
        case .objCBlock,
             .escapingObjCBlock:
            return .block
        case .cFunctionPointer:
            return .cFunctionPointer
        case .thinFunctionType:
            return .thin
        default:
            return .swift
        }
    }

    fileprivate func isEscapingFunction(_ kind: Node.Kind) -> Bool {
        switch kind {
        case .functionType,
             .escapingAutoClosureType,
             .escapingObjCBlock:
            return true
        default:
            return false
        }
    }

    fileprivate func decodeGlobalActorAndIsolation(
        node: Node,
        startIndex: Int,
        depth: Int,
        extFlags: ExtendedFunctionTypeFlags
    ) throws -> (BuiltType?, ExtendedFunctionTypeFlags, Int) {
        var index = startIndex
        var globalActorType: BuiltType?
        var flags = extFlags

        guard index < node.children.count else {
            return (nil, flags, index)
        }

        switch node.children[index].kind {
        case .globalActorFunctionType:
            let child = node.children[index]
            guard !child.children.isEmpty else {
                throw makeNodeError(child, "Global actor node is missing child")
            }
            globalActorType = try decodeMangledType(child.children[0], depth: depth + 1)
            index += 1

        case .isolatedAnyFunctionType:
            flags = flags.withIsolatedAny()
            index += 1

        case .nonIsolatedCallerFunctionType:
            flags = flags.withNonIsolatedCaller()
            index += 1

        default:
            break
        }

        return (globalActorType, flags, index)
    }

    fileprivate func decodeDifferentiability(
        node: Node,
        startIndex: Int
    ) throws -> (FunctionMetadataDifferentiabilityKind, Int) {
        var index = startIndex
        var diffKind = FunctionMetadataDifferentiabilityKind.nonDifferentiable

        if index < node.children.count, node.children[index].kind == .differentiableFunctionType {
            guard let rawValue = node.children[index].index else {
                throw makeNodeError(node.children[index], "missing differentiability index")
            }

            diffKind = FunctionMetadataDifferentiabilityKind(from: UInt8(rawValue))
            index += 1
        }

        return (diffKind, index)
    }

    fileprivate func decodeThrows(
        node: Node,
        startIndex: Int,
        depth: Int,
        extFlags: inout ExtendedFunctionTypeFlags
    ) throws -> (BuiltType?, Bool, Int) {
        var index = startIndex
        var thrownErrorType: BuiltType?
        var isThrow = false

        guard index < node.children.count else {
            return (nil, false, index)
        }

        switch node.children[index].kind {
        case .throwsAnnotation:
            isThrow = true
            index += 1

        case .typedThrowsAnnotation:
            isThrow = true
            let child = node.children[index]
            guard !child.children.isEmpty else {
                throw makeNodeError(child, "Thrown error node is missing child")
            }
            thrownErrorType = try decodeMangledType(child.children[0], depth: depth + 1)
            extFlags = extFlags.withTypedThrows(true)
            index += 1

        default:
            break
        }

        return (thrownErrorType, isThrow, index)
    }

    fileprivate func decodeFunctionParameters(
        _ node: Node,
        depth: Int
    ) throws -> ([FunctionParam<BuiltType>], Bool) {
        var params: [FunctionParam<BuiltType>] = []
        var hasParamFlags = false

        try decodeMangledFunctionInputType(
            node,
            depth: depth,
            params: &params,
            hasParamFlags: &hasParamFlags
        )

        return (params, hasParamFlags)
    }

    fileprivate func decodeMangledFunctionInputType(
        _ node: Node,
        depth: Int,
        params: inout [FunctionParam<BuiltType>],
        hasParamFlags: inout Bool
    ) throws {
        guard depth <= Self.maxDepth else {
            return
        }

        var node = node

        // Look through sugar nodes
        if node.kind == .type || node.kind == .argumentTuple {
            if !node.children.isEmpty {
                try decodeMangledFunctionInputType(
                    node.children[0],
                    depth: depth + 1,
                    params: &params,
                    hasParamFlags: &hasParamFlags
                )
            }
            return
        }

        // Handle tuple expansion
        if node.kind == .tuple {
            for element in node.children {
                try decodeParameterElement(
                    element,
                    depth: depth + 1,
                    params: &params,
                    hasParamFlags: &hasParamFlags
                )
            }
            return
        }

        // Handle single parameter
        try decodeSingleParameter(
            node,
            depth: depth,
            params: &params,
            hasParamFlags: &hasParamFlags
        )
    }

    fileprivate func decodeParameterElement(
        _ node: Node,
        depth: Int,
        params: inout [FunctionParam<BuiltType>],
        hasParamFlags: inout Bool
    ) throws {
        guard node.kind == .tupleElement else {
            return
        }

        var param: FunctionParam<BuiltType>?
        var label: String?

        for child in node.children {
            switch child.kind {
            case .tupleElementName:
                label = child.text

            case .variadicMarker:
                hasParamFlags = true
                if param == nil {
                    // We'll set the type later
                    continue
                }
                param?.setVariadic()

            case .type:
                if !child.children.isEmpty {
                    let typeParam = try decodeParameterType(
                        child.children[0],
                        depth: depth + 1,
                        hasParamFlags: &hasParamFlags
                    )
                    param = typeParam
                    param?.setLabel(label)
                }

            default:
                let typeParam = try decodeParameterType(
                    child,
                    depth: depth + 1,
                    hasParamFlags: &hasParamFlags
                )
                param = typeParam
                param?.setLabel(label)
            }
        }

        if let param = param {
            params.append(param)
        }
    }

    fileprivate func decodeSingleParameter(
        _ node: Node,
        depth: Int,
        params: inout [FunctionParam<BuiltType>],
        hasParamFlags: inout Bool
    ) throws {
        let param = try decodeParameterType(node, depth: depth, hasParamFlags: &hasParamFlags)
        params.append(param)
    }

    fileprivate func decodeParameterType(
        _ node: Node,
        depth: Int,
        hasParamFlags: inout Bool
    ) throws -> FunctionParam<BuiltType> {
        var currentNode = node
        var param: FunctionParam<BuiltType>?

        // Process parameter modifiers
        while true {
            switch currentNode.kind {
            case .inOut:
                hasParamFlags = true
                if param == nil {
                    // Decode the inner type first
                    if !currentNode.children.isEmpty {
                        let innerType = try decodeMangledType(currentNode.children[0], depth: depth + 1, forRequirement: false)
                        param = FunctionParam(type: innerType)
                    }
                }
                param?.setOwnership(.inout)
                if let param = param {
                    return param
                }
                return try FunctionParam(type: decodeMangledType(currentNode, depth: depth, forRequirement: false))

            case .shared:
                hasParamFlags = true
                if !currentNode.children.isEmpty {
                    currentNode = currentNode.children[0]
                    if param == nil {
                        let innerType = try decodeMangledType(currentNode, depth: depth + 1, forRequirement: false)
                        param = FunctionParam(type: innerType)
                    }
                    param?.setOwnership(.shared)
                }
                if let param = param {
                    return param
                }
                return try FunctionParam(type: decodeMangledType(currentNode, depth: depth, forRequirement: false))

            case .owned:
                hasParamFlags = true
                if !currentNode.children.isEmpty {
                    currentNode = currentNode.children[0]
                    if param == nil {
                        let innerType = try decodeMangledType(currentNode, depth: depth + 1, forRequirement: false)
                        param = FunctionParam(type: innerType)
                    }
                    param?.setOwnership(.owned)
                }
                if let param = param {
                    return param
                }
                return try FunctionParam(type: decodeMangledType(currentNode, depth: depth, forRequirement: false))

            case .noDerivative:
                hasParamFlags = true
                if !currentNode.children.isEmpty {
                    currentNode = currentNode.children[0]
                    if param == nil {
                        let innerType = try decodeMangledType(currentNode, depth: depth + 1, forRequirement: false)
                        param = FunctionParam(type: innerType)
                    }
                    param?.setNoDerivative()
                } else {
                    break
                }

            case .isolated:
                hasParamFlags = true
                if !currentNode.children.isEmpty {
                    currentNode = currentNode.children[0]
                    if param == nil {
                        let innerType = try decodeMangledType(currentNode, depth: depth + 1, forRequirement: false)
                        param = FunctionParam(type: innerType)
                    }
                    param?.setIsolated()
                } else {
                    break
                }

            case .sending:
                hasParamFlags = true
                if !currentNode.children.isEmpty {
                    currentNode = currentNode.children[0]
                    if param == nil {
                        let innerType = try decodeMangledType(currentNode, depth: depth + 1, forRequirement: false)
                        param = FunctionParam(type: innerType)
                    }
                    param?.setSending()
                } else {
                    break
                }

            case .autoClosureType,
                 .escapingAutoClosureType:
                hasParamFlags = true
                let innerType = try decodeMangledType(currentNode, depth: depth + 1, forRequirement: false)
                if param == nil {
                    param = FunctionParam(type: innerType)
                }
                param?.setAutoClosure()
                return param!

            default:
                // No more modifiers, decode the actual type
                let type = try decodeMangledType(currentNode, depth: depth + 1, forRequirement: false)
                return param ?? FunctionParam(type: type)
            }
        }
    }
}

// MARK: - Implementation Function Helpers

extension TypeDecoder {
    fileprivate func decodeImplConvention(
        _ node: Node,
        flags: ImplFunctionTypeFlags
    ) throws -> (ImplParameterConvention, ImplFunctionTypeFlags) {
        guard let text = node.text else {
            throw makeNodeError(node, "expected text")
        }

        if text == "@convention(thin)" {
            return (.directUnowned, flags.withRepresentation(.thin))
        } else if text == "@callee_guaranteed" {
            return (.directGuaranteed, flags)
        }

        return (.directUnowned, flags)
    }

    fileprivate func decodeImplFunctionConvention(
        _ node: Node,
        flags: ImplFunctionTypeFlags
    ) throws -> ImplFunctionTypeFlags {
        guard !node.children.isEmpty,
              node.children[0].kind == .implFunctionConventionName,
              let text = node.children[0].text else {
            throw makeNodeError(node, "expected convention name")
        }

        switch text {
        case "c":
            return flags.withRepresentation(.cFunctionPointer)
        case "block":
            return flags.withRepresentation(.block)
        default:
            return flags
        }
    }

    fileprivate func decodeImplFunctionAttribute(
        _ node: Node,
        flags: ImplFunctionTypeFlags
    ) throws -> ImplFunctionTypeFlags {
        guard let text = node.text else {
            throw makeNodeError(node, "expected text")
        }

        switch text {
        case "@Sendable":
            return flags.withSendable()
        case "@async":
            return flags.withAsync()
        case "sending-result":
            return flags.withSendingResult()
        default:
            return flags
        }
    }

    fileprivate func decodeImplCoroutineKind(_ node: Node) throws -> ImplCoroutineKind {
        guard let text = node.text else {
            throw makeNodeError(node, "expected text")
        }

        switch text {
        case "yield_once":
            return .yieldOnce
        case "yield_once_2":
            return .yieldOnce2
        case "yield_many":
            return .yieldMany
        default:
            throw makeNodeError(node, "failed to decode coroutine kind")
        }
    }

    fileprivate func decodeImplDifferentiabilityKind(
        _ node: Node,
        flags: ImplFunctionTypeFlags
    ) throws -> ImplFunctionTypeFlags {
        guard let index = node.index else {
            throw makeNodeError(node, "missing differentiability index")
        }

        let diffKind = ImplFunctionDifferentiabilityKind(from: UInt8(index))
        return flags.withDifferentiabilityKind(diffKind)
    }

    fileprivate func decodeImplFunctionParam<T: ImplFunctionParamProtocol>(
        _ node: Node,
        depth: Int,
        results: inout [T]
    ) throws where T.BuiltTypeParam == BuiltType {
        guard depth <= Self.maxDepth else {
            throw TypeLookupError("Depth exceeded")
        }

        guard node.children.count >= 2 else {
            throw makeNodeError(node, "expected at least 2 children")
        }

        let conventionNode = node.children[0]
        let typeNode = node.children[node.children.count - 1]

        guard conventionNode.kind == .implConvention,
              typeNode.kind == .type,
              let conventionString = conventionNode.text else {
            throw makeNodeError(node, "invalid parameter structure")
        }

        guard let convention = T.getConventionFromString(conventionString) else {
            throw makeNodeError(conventionNode, "invalid convention")
        }

        let type = try decodeMangledType(typeNode, depth: depth + 1)

        var options = T.OptionsType()
        for i in 1 ..< (node.children.count - 1) {
            let child = node.children[i]
            switch child.kind {
            case .implParameterResultDifferentiability:
                if let text = child.text,
                   let diffOptions = T.getDifferentiabilityFromString(text) {
                    options = options.union(diffOptions)
                }

            case .implParameterSending:
                options = options.union(T.getSending())

            case .implParameterIsolated:
                if T.self == ImplFunctionParam<BuiltType>.self {
                    options = options.union(ImplFunctionParam<BuiltType>.getIsolated() as! T.OptionsType)
                }

            case .implParameterImplicitLeading:
                if T.self == ImplFunctionParam<BuiltType>.self {
                    options = options.union(ImplFunctionParam<BuiltType>.getImplicitLeading() as! T.OptionsType)
                }

            default:
                break
            }
        }

        results.append(T(type: type, convention: convention, options: options))
    }

    fileprivate func decodeImplFunctionResult<T: ImplFunctionResultProtocol>(
        _ node: Node,
        depth: Int,
        results: inout [T]
    ) throws where T.BuiltTypeParam == BuiltType {
        guard depth <= Self.maxDepth else {
            throw TypeLookupError("Depth exceeded")
        }

        guard node.children.count >= 2 else {
            throw makeNodeError(node, "expected at least 2 children")
        }

        let conventionNode = node.children[0]
        let typeNode = node.children[node.children.count - 1]

        guard conventionNode.kind == .implConvention,
              typeNode.kind == .type,
              let conventionString = conventionNode.text else {
            throw makeNodeError(node, "invalid result structure")
        }

        guard let convention = T.getConventionFromString(conventionString) else {
            throw makeNodeError(conventionNode, "invalid convention")
        }

        let type = try decodeMangledType(typeNode, depth: depth + 1)

        var options = T.OptionsType()
        for i in 1 ..< (node.children.count - 1) {
            let child = node.children[i]
            switch child.kind {
            case .implParameterResultDifferentiability:
                if let text = child.text,
                   let diffOptions = T.getDifferentiabilityFromString(text) {
                    options = options.union(diffOptions)
                }

            case .implParameterSending:
                options = options.union(T.getSending())

            default:
                break
            }
        }

        let result = T(type: type, convention: convention, options: options)
        results.append(result)
    }
}

// MARK: - Differentiability Helper

extension FunctionMetadataDifferentiabilityKind {
    init(from rawValue: UInt8) {
        switch rawValue {
        case 1:
            self = .forward
        case 2:
            self = .reverse
        case 3:
            self = .normal
        case 4:
            self = .linear
        default:
            self = .nonDifferentiable
        }
    }
}

extension ImplFunctionDifferentiabilityKind {
    init(from rawValue: UInt8) {
        switch rawValue {
        case 0:
            self = .nonDifferentiable
        case 1:
            self = .forward
        case 2:
            self = .reverse
        case 3:
            self = .normal
        case 4:
            self = .linear
        default:
            self = .nonDifferentiable
        }
    }
}

// MARK: - Protocol Helpers

protocol ImplFunctionParamProtocol {
    associatedtype BuiltTypeParam
    associatedtype ConventionType
    associatedtype OptionsType: OptionSet

    init(type: BuiltTypeParam, convention: ConventionType, options: OptionsType)

    static func getConventionFromString(_ string: String) -> ConventionType?
    static func getDifferentiabilityFromString(_ string: String) -> OptionsType?
    static func getSending() -> OptionsType
}

protocol ImplFunctionResultProtocol {
    associatedtype BuiltTypeParam
    associatedtype ConventionType
    associatedtype OptionsType: OptionSet

    init(type: BuiltTypeParam, convention: ConventionType, options: OptionsType)

    static func getConventionFromString(_ string: String) -> ConventionType?
    static func getDifferentiabilityFromString(_ string: String) -> OptionsType?
    static func getSending() -> OptionsType
}

extension ImplFunctionParam: ImplFunctionParamProtocol {
    typealias BuiltTypeParam = BuiltType
}

extension ImplFunctionResult: ImplFunctionResultProtocol {
    typealias BuiltTypeParam = BuiltType
}

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
            for d in 0 ..< genericParamsAtDepth.count {
                for i in 0 ..< genericParamsAtDepth[d] {
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
                substitutions.append(.init(firstType: genericParams[i], secondType: substTy))
            }
        }

        // Decode field types
        let fieldsNode = node.children[0]
        guard fieldsNode.kind == .silBoxLayout else {
            throw makeNodeError(fieldsNode, "expected layout")
        }

        for fieldNode in fieldsNode.children {
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
            fields.append(.init(type: type, isMutable: isMutable))
        }

        return builder.createSILBoxTypeWithLayout(
            fields,
            substitutions,
            requirements,
            inverseRequirements
        )
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
        if unspecNode.children.count > 1,
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
        case "E",
             "e": self = .trivialOfExactSize
        case "M",
             "m": self = .trivialOfAtMostSize
        case "S": self = .trivialStride
        default: return nil
        }
    }

    var needsSizeAlignment: Bool {
        switch self {
        case .trivialOfExactSize,
             .trivialOfAtMostSize,
             .trivialStride:
            return true
        default:
            return false
        }
    }
}
