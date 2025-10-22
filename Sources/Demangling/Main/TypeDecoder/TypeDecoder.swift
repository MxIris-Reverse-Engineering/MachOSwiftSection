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

    private let builder: Builder

    private static var maxDepth: Int { 1024 }

    public init(builder: Builder) {
        self.builder = builder
    }

    /// Given a demangle tree, attempt to turn it into a type.
    public func decodeMangledType(node: Node, forRequirement: Bool = true) throws -> BuiltType {
        try decodeMangledType(node: node, depth: 0, forRequirement: forRequirement)
    }
}

// MARK: - Main Type Decoding

extension TypeDecoder {
    private func decodeMangledType(
        node: Node,
        depth: Int,
        forRequirement: Bool = true
    ) throws -> BuiltType {
        guard depth <= Self.maxDepth else {
            throw TypeLookupError("Mangled type is too complex")
        }

        switch node.kind {
        case .global:
            guard !node.children.isEmpty else {
                throw makeError(node: node, message: "no children")
            }
            return try decodeMangledType(node: node.children[0], depth: depth + 1)

        case .typeMangling:
            guard !node.children.isEmpty else {
                throw makeError(node: node, message: "no children")
            }
            return try decodeMangledType(node: node.children[0], depth: depth + 1)

        case .type:
            guard !node.children.isEmpty else {
                throw makeError(node: node, message: "no children")
            }
            return try decodeMangledType(
                node: node.children[0],
                depth: depth + 1,
                forRequirement: forRequirement
            )

        case .class:
            #if canImport(ObjectiveC)
            if let mangledName = getObjCClassOrProtocolName(node) {
                return builder.createObjCClassType(name: mangledName)
            }
            #endif
            fallthrough

        case .enum,
             .structure,
             .typeAlias,
             .typeSymbolicReference:
            var typeDecl: BuiltTypeDecl?
            var parent: BuiltType?
            var typeAlias = false

            try decodeMangledTypeDecl(
                node: node,
                depth: depth,
                typeDecl: &typeDecl,
                parent: &parent,
                typeAlias: &typeAlias
            )

            guard let typeDecl else {
                throw makeError(node: node, message: "Failed to create type decl")
            }

            if typeAlias {
                return builder.createTypeAliasType(typeDecl: typeDecl, parent: parent)
            }

            return builder.createNominalType(typeDecl: typeDecl, parent: parent)

        case .boundGenericEnum,
             .boundGenericStructure,
             .boundGenericClass,
             .boundGenericTypeAlias,
             .boundGenericOtherNominalType:
            guard node.children.count >= 2 else {
                throw makeError(node: node, message: "fewer children (\(node.children.count)) than required (2)")
            }

            let args = try decodeGenericArgs(node: node.children[1], depth: depth + 1)

            var childNode = node.children[0]
            if childNode.kind == .type, childNode.hasChildren {
                childNode = childNode.children[0]
            }

            #if canImport(ObjectiveC)
            if let mangledName = getObjCClassOrProtocolName(childNode) {
                return builder.createBoundGenericObjCClassType(name: mangledName, args: args)
            }
            #endif

            var typeDecl: BuiltTypeDecl?
            var parent: BuiltType?
            var typeAlias = false

            try decodeMangledTypeDecl(
                node: childNode,
                depth: depth,
                typeDecl: &typeDecl,
                parent: &parent,
                typeAlias: &typeAlias
            )

            guard let typeDecl else {
                throw makeError(node: node, message: "Failed to create type decl")
            }

            return builder.createBoundGenericType(typeDecl: typeDecl, args: args, parent: parent)

        case .boundGenericProtocol:
            // This is a special case. When you write a protocol typealias with a
            // concrete type base, for example:
            //
            // protocol P { typealias A<T> = ... }
            // struct S : P {}
            // let x: S.A<Int> = ...
            //
            // The mangling tree looks like this:
            //
            // BoundGenericProtocol ---> BoundGenericTypeAlias
            // |                         |
            // |                         |
            // --> Protocol: P           --> TypeAlias: A
            // |                         |
            // --> TypeList:             --> TypeList:
            //     |                         |
            //     --> Structure: S          --> Structure: Int
            //
            // When resolving the mangling tree to a decl, we strip off the
            // BoundGenericProtocol's *argument*, leaving behind only the
            // protocol reference.
            //
            // But when resolving it to a type, we want to *keep* the argument
            // so that the parent type becomes 'S' and not 'P'.
            guard node.children.count >= 2 else {
                throw makeError(node: node, message: "fewer children (\(node.children.count)) than required (2)")
            }

            let genericArgs = node.children[1]
            guard genericArgs.children.count == 1 else {
                throw makeError(node: genericArgs, message: "expected 1 generic argument, saw \(genericArgs.children.count)")
            }

            return try decodeMangledType(node: genericArgs.children[0], depth: depth + 1)

        case .builtinTypeName:
            let mangling: String
            do {
                mangling = try mangleAsString(node)
            } catch {
                throw makeError(node: node, message: "failed to mangle node")
            }
            return builder.createBuiltinType(name: node.text ?? "", mangledName: mangling)

        case .metatype,
             .existentialMetatype:
            var childIndex = 0
            var repr: ImplMetatypeRepresentation?

            // Handle lowered metatypes
            if node.children.count >= 2 {
                let reprNode = node.children[childIndex]
                childIndex += 1

                guard reprNode.kind == .metatypeRepresentation,
                      let text = reprNode.text else {
                    throw makeError(node: reprNode, message: "wrong node kind or no text")
                }

                repr = ImplMetatypeRepresentation(from: text)
            } else if node.children.isEmpty {
                throw makeError(node: node, message: "no children")
            }

            let instance = try decodeMangledType(node: node.children[childIndex], depth: depth + 1)

            switch node.kind {
            case .metatype:
                return builder.createMetatypeType(instance: instance, repr: repr)
            case .existentialMetatype:
                return builder.createExistentialMetatypeType(instance: instance, repr: repr)
            default:
                throw makeError(node: node, message: "unexpected metatype kind")
            }

        case .symbolicExtendedExistentialType:
            guard node.children.count >= 2 else {
                throw makeError(node: node, message: "not enough children")
            }

            let shapeNode = node.children[0]
            let args = try decodeGenericArgs(node: node.children[1], depth: depth + 1)

            return builder.createSymbolicExtendedExistentialType(shapeNode: shapeNode, args: args)

        case .protocolList,
             .protocolListWithAnyObject,
             .protocolListWithClass:
            guard !node.children.isEmpty else {
                throw makeError(node: node, message: "no children")
            }

            // Find the protocol list
            var protocols: [BuiltProtocolDecl] = []
            var typeList = node.children[0]

            if typeList.kind == .protocolList, typeList.hasChildren {
                typeList = typeList.children[0]
            }

            // Demangle the protocol list.
            for componentType in typeList.children {
                guard let proto = decodeMangledProtocolType(node: componentType, depth: depth + 1) else {
                    throw makeError(node: componentType, message: "failed to decode protocol type")
                }
                protocols.append(proto)
            }

            // Superclass or AnyObject, if present.
            var isClassBound = false
            var superclass: BuiltType?

            switch node.kind {
            case .protocolListWithClass:
                guard node.children.count >= 2 else {
                    throw makeError(node: node, message: "fewer children (\(node.children.count)) than required (2)")
                }
                superclass = try decodeMangledType(node: node.children[1], depth: depth + 1)
                isClassBound = true

            case .protocolListWithAnyObject:
                isClassBound = true

            default:
                break
            }

            return builder.createProtocolCompositionType(protocols: protocols, superclass: superclass, isClassBound: isClassBound, forRequirement: forRequirement)

        case .constrainedExistential:
            guard node.children.count >= 2 else {
                throw makeError(node: node, message: "fewer children (\(node.children.count)) than required (2)")
            }

            let protocolType = try decodeMangledType(node: node.children[0], depth: depth + 1)

            var requirements: [BuiltRequirement] = []
            var inverseRequirements: [BuiltInverseRequirement] = []

            let reqts = node.children[1]
            guard reqts.kind == .constrainedExistentialRequirementList else {
                throw makeError(node: reqts, message: "is not requirement list")
            }

            try decodeRequirements(
                node: reqts,
                requirements: &requirements,
                inverseRequirements: &inverseRequirements,
                builder: builder
            )

            return builder.createConstrainedExistentialType(base: protocolType, requirements: requirements, inverseRequirements: inverseRequirements)

        case .constrainedExistentialSelf:
            return builder.createGenericTypeParameterType(depth: 0, index: 0)

        case .objectiveCProtocolSymbolicReference,
             .protocol,
             .protocolSymbolicReference:
            guard let proto = decodeMangledProtocolType(node: node, depth: depth + 1) else {
                throw makeError(node: node, message: "failed to decode protocol type")
            }
            return builder.createProtocolCompositionType(protocol: proto, superclass: nil, isClassBound: false, forRequirement: forRequirement)

        case .dynamicSelf:
            guard node.children.count == 1 else {
                throw makeError(node: node, message: "expected 1 child, saw \(node.children.count)")
            }
            let selfType = try decodeMangledType(node: node.children[0], depth: depth + 1)
            return builder.createDynamicSelfType(base: selfType)

        case .dependentGenericParamType:
            guard node.children.count >= 2,
                  let depthValue = node.children[0].index,
                  let indexValue = node.children[1].index else {
                throw makeError(node: node, message: "invalid generic param type")
            }
            return builder.createGenericTypeParameterType(depth: Int(depthValue), index: Int(indexValue))

        case .escapingObjCBlock,
             .objCBlock,
             .cFunctionPointer,
             .thinFunctionType,
             .noEscapeFunctionType,
             .autoClosureType,
             .escapingAutoClosureType,
             .functionType:
            guard node.children.count >= 2 else {
                throw makeError(node: node, message: "fewer children (\(node.children.count)) than required (2)")
            }

            var flags = FunctionTypeFlags()
            var extFlags = ExtendedFunctionTypeFlags()

            // Set convention based on node kind
            flags = flags.withConvention(functionConvention(for: node.kind))

            var firstChildIndex = 0

            // Skip ClangType if present
            if firstChildIndex < node.children.count && node.children[firstChildIndex].kind == .clangType {
                firstChildIndex += 1
            }

            // Handle sending result
            if firstChildIndex < node.children.count && node.children[firstChildIndex].kind == .sendingResultFunctionType {
                extFlags = extFlags.withSendingResult()
                firstChildIndex += 1
            }

            var globalActorType: BuiltType?

            switch node.children[firstChildIndex].kind {
            case .globalActorFunctionType:
                let child = node.children[firstChildIndex]
                guard !child.children.isEmpty else {
                    throw makeError(node: child, message: "Global actor node is missing child")
                }
                globalActorType = try decodeMangledType(node: child.children[0], depth: depth + 1)
                firstChildIndex += 1

            case .isolatedAnyFunctionType:
                extFlags = extFlags.withIsolatedAny()
                firstChildIndex += 1

            case .nonIsolatedCallerFunctionType:
                extFlags = extFlags.withNonIsolatedCaller()
                firstChildIndex += 1

            default:
                break
            }

            var diffKind = FunctionMetadataDifferentiabilityKind.nonDifferentiable

            if firstChildIndex < node.children.count, node.children[firstChildIndex].kind == .differentiableFunctionType {
                guard let rawValue = node.children[firstChildIndex].index else {
                    throw makeError(node: node.children[firstChildIndex], message: "missing differentiability index")
                }

                diffKind = FunctionMetadataDifferentiabilityKind(from: UInt8(rawValue))
                firstChildIndex += 1
            }

            var thrownErrorType: BuiltType?
            var isThrow = false

            switch node.children[firstChildIndex].kind {
            case .throwsAnnotation:
                isThrow = true
                firstChildIndex += 1

            case .typedThrowsAnnotation:
                isThrow = true
                let child = node.children[firstChildIndex]
                guard child.hasChildren else {
                    throw makeError(node: child, message: "Thrown error node is missing child")
                }
                thrownErrorType = try decodeMangledType(node: child.children[0], depth: depth + 1)
                extFlags = extFlags.withTypedThrows(true)
                firstChildIndex += 1

            default:
                break
            }

            // Handle sendable/concurrent
            var isSendable = false
            if firstChildIndex < node.children.count && node.children[firstChildIndex].kind == .concurrentFunctionType {
                isSendable = true
                firstChildIndex += 1
            }

            // Handle async
            var isAsync = false
            if firstChildIndex < node.children.count && node.children[firstChildIndex].kind == .asyncAnnotation {
                isAsync = true
                firstChildIndex += 1
            }

            // Update flags
            flags = flags
                .withSendable(isSendable)
                .withAsync(isAsync)
                .withThrows(isThrow)
                .withDifferentiable(diffKind.isDifferentiable)

            guard node.children.count >= firstChildIndex + 2 else {
                throw makeError(node: node, message: "fewer children (\(node.children.count)) than required (\(firstChildIndex + 2))")
            }

            var hasParamFlags = false
            var parameters: [FunctionParam<BuiltType>] = []

            try decodeMangledFunctionInputType(
                node: node.children[firstChildIndex],
                depth: depth,
                params: &parameters,
                hasParamFlags: &hasParamFlags
            )

            flags = flags
                .withNumParameters(parameters.count)
                .withParameterFlags(hasParamFlags)
                .withEscaping(isEscapingFunction(kind: node.kind))

            // Decode result type
            let resultType = try decodeMangledType(
                node: node.children[firstChildIndex + 1],
                depth: depth + 1,
                forRequirement: false
            )

            if extFlags != ExtendedFunctionTypeFlags() {
                flags = flags.withExtendedFlags(true)
            }

            return builder.createFunctionType(
                parameters: parameters,
                result: resultType,
                flags: flags,
                extFlags: extFlags,
                diffKind: diffKind,
                globalActorType: globalActorType,
                thrownErrorType: thrownErrorType
            )

        case .implFunctionType:
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
                    guard let text = child.text else {
                        throw makeError(node: node, message: "expected text")
                    }
                    if text == "@convention(thin)" {
                        flags = flags.withRepresentation(.thin)
                    } else if text == "@callee_guaranteed" {
                        calleeConvention = .directGuaranteed
                    }

                case .implFunctionConvention:
                    guard child.hasChildren,
                          child.children[0].kind == .implFunctionConventionName,
                          let text = child.children[0].text else {
                        throw makeError(node: node, message: "expected convention name")
                    }

                    switch text {
                    case "c":
                        flags = flags.withRepresentation(.cFunctionPointer)
                    case "block":
                        flags = flags.withRepresentation(.block)
                    default:
                        break
                    }

                case .implFunctionAttribute:
                    guard let text = child.text else {
                        throw makeError(node: node, message: "expected text")
                    }

                    switch text {
                    case "@Sendable":
                        flags = flags.withSendable()
                    case "@async":
                        flags = flags.withAsync()
                    case "sending-result":
                        flags = flags.withSendingResult()
                    default:
                        break
                    }

                case .implSendingResult:
                    // NOTE: This flag needs to be set both at the function level and on
                    // each of the parameters. The flag on the function just means that
                    // all parameters are sending (which is always true today).
                    flags = flags.withSendingResult()

                case .implCoroutineKind:
                    guard let text = child.text else {
                        throw makeError(node: node, message: "expected text")
                    }

                    switch text {
                    case "yield_once":
                        coroutineKind = .yieldOnce
                    case "yield_once_2":
                        coroutineKind = .yieldOnce2
                    case "yield_many":
                        coroutineKind = .yieldMany
                    default:
                        throw makeError(node: node, message: "failed to decode coroutine kind")
                    }

                case .implDifferentiabilityKind:
                    guard let index = child.index else {
                        throw makeError(node: node, message: "missing differentiability index")
                    }

                    let diffKind = ImplFunctionDifferentiabilityKind(from: UInt8(index))
                    flags = flags.withDifferentiabilityKind(diffKind)

                case .implEscaping:
                    flags = flags.withEscaping()

                case .implErasedIsolation:
                    flags = flags.withErasedIsolation()

                case .implParameter:
                    try decodeImplFunctionParam(node: child, depth: depth + 1, results: &parameters)

                case .implYield:
                    try decodeImplFunctionParam(node: child, depth: depth + 1, results: &yields)

                case .implResult:
                    try decodeImplFunctionResult(node: child, depth: depth + 1, results: &results)

                case .implErrorResult:
                    try decodeImplFunctionResult(node: child, depth: depth + 1, results: &errorResults)

                default:
                    throw makeError(node: child, message: "unexpected kind")
                }
            }

            let errorResult: ImplFunctionResult<BuiltType>?
            switch errorResults.count {
            case 0:
                errorResult = nil
            case 1:
                errorResult = errorResults[0]
            default:
                throw makeError(node: node, message: "got \(errorResults.count) errors")
            }

            return builder.createImplFunctionType(
                calleeConvention: calleeConvention,
                coroutineKind: coroutineKind,
                parameters: parameters,
                yields: yields,
                results: results,
                errorResult: errorResult,
                flags: flags
            )

        case .argumentTuple:
            guard node.hasChildren else {
                throw makeError(node: node, message: "no children")
            }
            return try decodeMangledType(
                node: node.children[0],
                depth: depth + 1
            )

        case .returnType:
            guard node.hasChildren else {
                throw makeError(node: node, message: "no children")
            }
            return try decodeMangledType(
                node: node.children[0],
                depth: depth + 1,
                forRequirement: false
            )

        case .tuple:
            var elements: [BuiltType] = []
            var labels: [String?] = []

            for element in node.children {
                guard element.kind == .tupleElement else {
                    throw makeError(node: element, message: "unexpected kind")
                }

                var typeChildIndex = 0

                // Check for variadic marker
                if typeChildIndex < element.children.count &&
                    element.children[typeChildIndex].kind == .variadicMarker {
                    throw makeError(node: element.children[typeChildIndex], message: "variadic not supported")
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
                    node: element.children[typeChildIndex],
                    depth: depth + 1
                ) { type in
                    elements.append(type)
                    labels.append(label)
                }
            }

            return builder.createTupleType(elements: elements, labels: labels)

        case .tupleElement:
            guard !node.children.isEmpty else {
                throw makeError(node: node, message: "no children")
            }

            if node.children[0].kind == .tupleElementName {
                guard node.children.count >= 2 else {
                    throw makeError(node: node, message: "fewer children (\(node.children.count)) than required (2)")
                }
                return try decodeMangledType(node: node.children[1], depth: depth + 1, forRequirement: false)
            }

            return try decodeMangledType(node: node.children[0], depth: depth + 1, forRequirement: false)

        case .pack,
             .silPackDirect,
             .silPackIndirect:
            var elements: [BuiltType] = []

            for element in node.children {
                try decodeTypeSequenceElement(node: element, depth: depth + 1) { elementType in
                    elements.append(elementType)
                }
            }

            switch node.kind {
            case .pack:
                return builder.createPackType(elements: elements)
            case .silPackDirect:
                return builder.createSILPackType(elements: elements, isElementAddress: false)
            case .silPackIndirect:
                return builder.createSILPackType(elements: elements, isElementAddress: true)
            default:
                throw makeError(node: node, message: "unexpected pack kind")
            }

        case .packExpansion:
            throw makeError(node: node, message: "pack expansion type in unsupported position")

        case .dependentGenericType:
            guard node.children.count >= 2 else {
                throw makeError(node: node, message: "fewer children (\(node.children.count)) than required (2)")
            }
            return try decodeMangledType(node: node.children[1], depth: depth + 1)

        case .dependentMemberType:
            guard node.children.count >= 2 else {
                throw makeError(node: node, message: "fewer children (\(node.children.count)) than required (2)")
            }

            let base = try decodeMangledType(node: node.children[0], depth: depth + 1)

            let assocTypeChild = node.children[1]
            guard let member = assocTypeChild.children.first?.text else {
                throw makeError(node: assocTypeChild, message: "missing member name")
            }

            if assocTypeChild.children.count < 2 {
                return builder.createDependentMemberType(member: member, base: base)
            }

            guard let proto = decodeMangledProtocolType(node: assocTypeChild.children[1], depth: depth + 1) else {
                throw makeError(node: assocTypeChild, message: "failed to decode protocol")
            }

            return builder.createDependentMemberType(member: member, base: base, protocol: proto)

        case .dependentAssociatedTypeRef:
            guard node.children.count >= 2 else {
                throw makeError(node: node, message: "fewer children (\(node.children.count)) than required (2)")
            }
            return try decodeMangledType(node: node.children[1], depth: depth + 1)

        case .unowned,
             .unmanaged,
             .weak:
            guard !node.children.isEmpty else {
                throw makeError(node: node, message: "no children")
            }

            let base = try decodeMangledType(node: node.children[0], depth: depth + 1)

            switch node.kind {
            case .unowned:
                return builder.createUnownedStorageType(base: base)
            case .unmanaged:
                return builder.createUnmanagedStorageType(base: base)
            case .weak:
                return builder.createWeakStorageType(base: base)
            default:
                throw makeError(node: node, message: "unexpected storage type kind")
            }

        case .silBoxType:
            guard !node.children.isEmpty else {
                throw makeError(node: node, message: "no children")
            }
            let base = try decodeMangledType(node: node.children[0], depth: depth + 1)
            return builder.createSILBoxType(base: base)

        case .silBoxTypeWithLayout:
            var fields: [Field] = []
            var substitutions: [BuiltSubstitution] = []
            var requirements: [BuiltRequirement] = []
            var inverseRequirements: [BuiltInverseRequirement] = []
            var genericParams: [BuiltType] = []

            guard !node.children.isEmpty else {
                throw makeError(node: node, message: "no children")
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
                    throw makeError(node: substNode, message: "expected type list")
                }

                let dependentGenericSignatureNode = node.children[1]
                guard dependentGenericSignatureNode.kind == .dependentGenericSignature else {
                    throw makeError(node: dependentGenericSignatureNode, message: "expected dependent generic signature")
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

                builder.pushGenericParams(parameterPacks: parameterPacks)
                pushedGenericParams = true

                // Decode generic parameter types
                for d in 0 ..< genericParamsAtDepth.count {
                    for i in 0 ..< genericParamsAtDepth[d] {
                        let paramTy = builder.createGenericTypeParameterType(depth: d, index: i)
                        genericParams.append(paramTy)
                    }
                }

                // Decode requirements
                try decodeRequirements(
                    node: dependentGenericSignatureNode,
                    requirements: &requirements,
                    inverseRequirements: &inverseRequirements,
                    builder: builder
                )

                // Decode substitutions
                for (i, substChild) in substNode.children.enumerated() {
                    guard i < genericParams.count else { break }
                    let substTy = try decodeMangledType(node: substChild, depth: depth + 1, forRequirement: false)
                    substitutions.append(builder.createSubstitution(firstType: genericParams[i], secondType: substTy))
                }
            }

            // Decode field types
            let fieldsNode = node.children[0]
            guard fieldsNode.kind == .silBoxLayout else {
                throw makeError(node: fieldsNode, message: "expected layout")
            }

            for fieldNode in fieldsNode.children {
                let isMutable: Bool
                switch fieldNode.kind {
                case .silBoxMutableField:
                    isMutable = true
                case .silBoxImmutableField:
                    isMutable = false
                default:
                    throw makeError(node: fieldNode, message: "unhandled field type")
                }

                guard !fieldNode.children.isEmpty else {
                    throw makeError(node: fieldNode, message: "no children")
                }

                let type = try decodeMangledType(node: fieldNode.children[0], depth: depth + 1)
                fields.append(builder.createSILBoxField(type: type, isMutable: isMutable))
            }

            return builder.createSILBoxTypeWithLayout(
                fields: fields,
                substitutions: substitutions,
                requirements: requirements,
                inverseRequirements: inverseRequirements
            )

        case .sugaredOptional,
             .sugaredArray,
             .sugaredInlineArray,
             .sugaredDictionary,
             .sugaredParen:
            switch node.kind {
            case .sugaredOptional:
                guard !node.children.isEmpty else {
                    throw makeError(node: node, message: "no children")
                }
                let base = try decodeMangledType(node: node.children[0], depth: depth + 1)
                return builder.createOptionalType(base: base)

            case .sugaredArray:
                guard !node.children.isEmpty else {
                    throw makeError(node: node, message: "no children")
                }
                let element = try decodeMangledType(node: node.children[0], depth: depth + 1)
                return builder.createArrayType(element: element)

            case .sugaredInlineArray:
                guard node.children.count >= 2 else {
                    throw makeError(node: node, message: "fewer children (\(node.children.count)) than required (2)")
                }
                let count = try decodeMangledType(node: node.children[0], depth: depth + 1)
                let element = try decodeMangledType(node: node.children[1], depth: depth + 1)
                return builder.createInlineArrayType(count: count, element: element)

            case .sugaredDictionary:
                guard node.children.count >= 2 else {
                    throw makeError(node: node, message: "fewer children (\(node.children.count)) than required (2)")
                }
                let key = try decodeMangledType(node: node.children[0], depth: depth + 1)
                let value = try decodeMangledType(node: node.children[1], depth: depth + 1)
                return builder.createDictionaryType(key: key, value: value)

            case .sugaredParen:
                guard !node.children.isEmpty else {
                    throw makeError(node: node, message: "no children")
                }
                // ParenType has been removed, return the base type
                return try decodeMangledType(node: node.children[0], depth: depth + 1)

            default:
                throw makeError(node: node, message: "unexpected sugared type kind")
            }

        case .opaqueType:
            guard node.children.count >= 3 else {
                throw makeError(node: node, message: "fewer children (\(node.children.count)) than required (3)")
            }

            let descriptor = node.children[0]
            let ordinalNode = node.children[1]

            guard ordinalNode.kind == .index,
                  let ordinal = ordinalNode.index else {
                throw makeError(node: ordinalNode, message: "unexpected kind or no index")
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
                    let arg = try decodeMangledType(node: argNode, depth: depth + 1, forRequirement: false)
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

            return builder.resolveOpaqueType(descriptor: descriptor, genericArgs: genericArgs, ordinal: ordinal)

        case .integer:
            guard let index = node.index else {
                throw makeError(node: node, message: "missing index")
            }
            return builder.createIntegerType(value: Int(index))

        case .negativeInteger:
            guard let index = node.index else {
                throw makeError(node: node, message: "missing index")
            }
            return builder.createNegativeIntegerType(value: Int(index))

        case .builtinFixedArray:
            guard node.children.count >= 2 else {
                throw makeError(node: node, message: "fewer children (\(node.children.count)) than required (2)")
            }
            let size = try decodeMangledType(node: node.children[0], depth: depth + 1)
            let element = try decodeMangledType(node: node.children[1], depth: depth + 1)
            return builder.createBuiltinFixedArrayType(size: size, element: element)

        default:
            throw makeError(node: node, message: "unexpected kind")
        }
    }
}

extension TypeDecoder {
    private func makeError(node: Node, message: String) -> TypeLookupError {
        TypeLookupError(node: node, message: message)
    }
}

extension TypeDecoder {
    private func decodeTypeSequenceElement(
        node: Node,
        depth: Int,
        resultCallback: (BuiltType) throws -> Void
    ) throws {
        var node = node
        if node.kind == .type {
            node = node.children[0]
        }

        if node.kind == .packExpansion {
            try decodePackExpansion(node: node, depth: depth, resultCallback: resultCallback)
        } else {
            let elementType = try decodeMangledType(node: node, depth: depth, forRequirement: false)
            try resultCallback(elementType)
        }
    }

    private func decodePackExpansion(
        node: Node,
        depth: Int,
        resultCallback: (BuiltType) throws -> Void
    ) throws {
        guard node.children.count >= 2 else {
            throw makeError(node: node, message: "fewer children (\(node.children.count)) than required (2)")
        }

        let patternType = node.children[0]
        let countType = try decodeMangledType(node: node.children[1], depth: depth)

        let numElements = builder.beginPackExpansion(countType: countType)
        defer { builder.endPackExpansion() }

        for i in 0 ..< numElements {
            builder.advancePackExpansion(index: i)
            let expandedElementType = try decodeMangledType(node: patternType, depth: depth)
            try resultCallback(builder.createExpandedPackElement(type: expandedElementType))
        }
    }
}

extension TypeDecoder {
    private func decodeGenericArgs(node: Node, depth: Int) throws -> [BuiltType] {
        guard node.kind == .typeList else {
            throw makeError(node: node, message: "is not TypeList")
        }

        var args: [BuiltType] = []
        for genericArg in node.children {
            let paramType = try decodeMangledType(node: genericArg, depth: depth, forRequirement: false)
            args.append(paramType)
        }
        return args
    }
}

extension TypeDecoder {
    private func functionConvention(for kind: Node.Kind) -> FunctionMetadataConvention {
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

    private func isEscapingFunction(kind: Node.Kind) -> Bool {
        switch kind {
        case .functionType,
             .escapingAutoClosureType,
             .escapingObjCBlock:
            return true
        default:
            return false
        }
    }

    private func decodeMangledFunctionInputType(
        node: Node,
        depth: Int,
        params: inout [FunctionParam<BuiltType>],
        hasParamFlags: inout Bool
    ) throws {
        guard depth <= Self.maxDepth else {
            return
        }

        // Look through sugar nodes
        if node.kind == .type || node.kind == .argumentTuple {
            if !node.children.isEmpty {
                try decodeMangledFunctionInputType(
                    node: node.children[0],
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
                    node: element,
                    depth: depth + 1,
                    params: &params,
                    hasParamFlags: &hasParamFlags
                )
            }
            return
        }

        // Handle single parameter
        try decodeSingleParameter(
            node: node,
            depth: depth,
            params: &params,
            hasParamFlags: &hasParamFlags
        )
    }

    private func decodeParameterElement(
        node: Node,
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
                        node: child.children[0],
                        depth: depth + 1,
                        hasParamFlags: &hasParamFlags
                    )
                    param = typeParam
                    param?.setLabel(label)
                }

            default:
                let typeParam = try decodeParameterType(
                    node: child,
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

    private func decodeSingleParameter(
        node: Node,
        depth: Int,
        params: inout [FunctionParam<BuiltType>],
        hasParamFlags: inout Bool
    ) throws {
        let param = try decodeParameterType(node: node, depth: depth, hasParamFlags: &hasParamFlags)
        params.append(param)
    }

    private func decodeParameterType(
        node: Node,
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
                        let innerType = try decodeMangledType(node: currentNode.children[0], depth: depth + 1, forRequirement: false)
                        param = FunctionParam(type: innerType)
                    }
                }
                param?.setOwnership(.inout)
                if let param = param {
                    return param
                }
                return try FunctionParam(type: decodeMangledType(node: currentNode, depth: depth, forRequirement: false))

            case .shared:
                hasParamFlags = true
                if !currentNode.children.isEmpty {
                    currentNode = currentNode.children[0]
                    if param == nil {
                        let innerType = try decodeMangledType(node: currentNode, depth: depth + 1, forRequirement: false)
                        param = FunctionParam(type: innerType)
                    }
                    param?.setOwnership(.shared)
                }
                if let param = param {
                    return param
                }
                return try FunctionParam(type: decodeMangledType(node: currentNode, depth: depth, forRequirement: false))

            case .owned:
                hasParamFlags = true
                if !currentNode.children.isEmpty {
                    currentNode = currentNode.children[0]
                    if param == nil {
                        let innerType = try decodeMangledType(node: currentNode, depth: depth + 1, forRequirement: false)
                        param = FunctionParam(type: innerType)
                    }
                    param?.setOwnership(.owned)
                }
                if let param = param {
                    return param
                }
                return try FunctionParam(type: decodeMangledType(node: currentNode, depth: depth, forRequirement: false))

            case .noDerivative:
                hasParamFlags = true
                if !currentNode.children.isEmpty {
                    currentNode = currentNode.children[0]
                    if param == nil {
                        let innerType = try decodeMangledType(node: currentNode, depth: depth + 1, forRequirement: false)
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
                        let innerType = try decodeMangledType(node: currentNode, depth: depth + 1, forRequirement: false)
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
                        let innerType = try decodeMangledType(node: currentNode, depth: depth + 1, forRequirement: false)
                        param = FunctionParam(type: innerType)
                    }
                    param?.setSending()
                } else {
                    break
                }

            case .autoClosureType,
                 .escapingAutoClosureType:
                hasParamFlags = true
                let innerType = try decodeMangledType(node: currentNode, depth: depth + 1, forRequirement: false)
                if param == nil {
                    param = FunctionParam(type: innerType)
                }
                param?.setAutoClosure()
                return param!

            default:
                // No more modifiers, decode the actual type
                let type = try decodeMangledType(node: currentNode, depth: depth + 1, forRequirement: false)
                return param ?? FunctionParam(type: type)
            }
        }
    }
}

extension TypeDecoder {
    private func decodeImplFunctionParam<T: ImplFunctionParamProtocol>(
        node: Node,
        depth: Int,
        results: inout [T]
    ) throws where T.BuiltTypeParam == BuiltType {
        guard depth <= Self.maxDepth else {
            throw TypeLookupError("Depth exceeded")
        }

        guard node.children.count >= 2 else {
            throw makeError(node: node, message: "expected at least 2 children")
        }

        let conventionNode = node.children[0]
        let typeNode = node.children[node.children.count - 1]

        guard conventionNode.kind == .implConvention,
              typeNode.kind == .type,
              let conventionString = conventionNode.text else {
            throw makeError(node: node, message: "invalid parameter structure")
        }

        guard let convention = T.getConventionFromString(conventionString) else {
            throw makeError(node: conventionNode, message: "invalid convention")
        }

        let type = try decodeMangledType(node: typeNode, depth: depth + 1)

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

    private func decodeImplFunctionResult<T: ImplFunctionResultProtocol>(
        node: Node,
        depth: Int,
        results: inout [T]
    ) throws where T.BuiltTypeParam == BuiltType {
        guard depth <= Self.maxDepth else {
            throw TypeLookupError("Depth exceeded")
        }

        guard node.children.count >= 2 else {
            throw makeError(node: node, message: "expected at least 2 children")
        }

        let conventionNode = node.children[0]
        let typeNode = node.children[node.children.count - 1]

        guard conventionNode.kind == .implConvention,
              typeNode.kind == .type,
              let conventionString = conventionNode.text else {
            throw makeError(node: node, message: "invalid result structure")
        }

        guard let convention = T.getConventionFromString(conventionString) else {
            throw makeError(node: conventionNode, message: "invalid convention")
        }

        let type = try decodeMangledType(node: typeNode, depth: depth + 1)

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

extension TypeDecoder {
    private func decodeMangledTypeDecl(
        node: Node,
        depth: Int,
        typeDecl: inout BuiltTypeDecl?,
        parent: inout BuiltType?,
        typeAlias: inout Bool
    ) throws {
        guard depth <= Self.maxDepth else {
            throw TypeLookupError("Mangled type is too complex")
        }

        if node.kind == .type {
            return try decodeMangledTypeDecl(
                node: node.children[0],
                depth: depth + 1,
                typeDecl: &typeDecl,
                parent: &parent,
                typeAlias: &typeAlias
            )
        }

        var declNode: Node
        if node.kind == .typeSymbolicReference {
            // A symbolic reference can be directly resolved to a nominal type
            declNode = node
        } else {
            guard node.children.count >= 2 else {
                throw makeError(node: node, message: "Number of node children (\(node.children.count)) less than required (2)")
            }

            var parentContext = node.children[0]

            // Nested types are handled a bit funny here because a
            // nominal typeref always stores its full mangled name,
            // in addition to a reference to the parent type. The
            // mangled name already includes the module and parent
            // types, if any.
            declNode = node

            switch parentContext.kind {
            case .module:
                break

            case .extension:
                // Decode the type being extended
                guard parentContext.children.count >= 2 else {
                    throw makeError(
                        node: parentContext,
                        message: "Number of parentContext children (\(parentContext.children.count)) less than required (2)"
                    )
                }
                parentContext = parentContext.children[1]
                fallthrough

            default:
                parent = try decodeMangledType(node: parentContext, depth: depth + 1)

                // Remove any generic arguments from the context node, producing a
                // node that references the nominal type declaration.
                if let unspecNode = getUnspecialized(node) {
                    declNode = unspecNode
                } else {
                    throw TypeLookupError("Failed to unspecialize type")
                }
            }
        }

        typeDecl = builder.createTypeDecl(node: declNode, typeAlias: &typeAlias)
        if typeDecl == nil {
            throw TypeLookupError("Failed to create type decl")
        }
    }

    private func decodeMangledProtocolType(node: Node, depth: Int) -> BuiltProtocolDecl? {
        guard depth <= Self.maxDepth else {
            return nil
        }

        let node = node
        if node.kind == .type {
            guard !node.children.isEmpty else { return nil }
            return decodeMangledProtocolType(node: node.children[0], depth: depth + 1)
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
            return builder.createObjCProtocolDecl(name: objcProtocolName)
        }
        #endif

        return builder.createProtocolDecl(node: node)
    }
}

private func decodeRequirements<BuilderType: TypeBuilder>(
    node: Node,
    requirements: inout [BuilderType.BuiltRequirement],
    inverseRequirements: inout [BuilderType.BuiltInverseRequirement],
    builder: BuilderType
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
        let subjectType = try builder.decodeMangledType(node: child.children[0], forRequirement: true)

        switch child.kind {
        case .dependentGenericConformanceRequirement:
            let constraintType = try builder.decodeMangledType(node: child.children[1], forRequirement: true)
            let kind: RequirementKind = builder.isExistential(type: constraintType) ? .conformance : .superclass
            requirements.append(builder.createRequirement(kind: kind, subjectType: subjectType, constraintType: constraintType))

        case .dependentGenericSameTypeRequirement:
            let constraintType = try builder.decodeMangledType(node: child.children[1], forRequirement: false)
            requirements.append(builder.createRequirement(kind: .sameType, subjectType: subjectType, constraintType: constraintType))

        case .dependentGenericInverseConformanceRequirement:
            let constraintNode = child.children[0]
            guard constraintNode.kind == .type,
                  constraintNode.children.count == 1 else {
                return
            }

            guard let index = child.children[1].index else {
                return
            }

            let protocolKind = InvertibleProtocolKind(rawValue: UInt32(index)) ?? .copyable
            let inverseReq = builder.createInverseRequirement(subjectType: subjectType, kind: protocolKind)
            inverseRequirements.append(inverseReq)

        case .dependentGenericLayoutRequirement:
            let kindChild = child.children[1]
            guard kindChild.kind == .identifier,
                  let text = kindChild.text else {
                return
            }

            guard let layoutKind = LayoutConstraintKind(from: text) else {
                return
            }

            let layout: BuilderType.BuiltLayoutConstraint
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

                layout = builder.getLayoutConstraintWithSizeAlign(kind: layoutKind, size: Int(size), alignment: alignment)
            } else {
                layout = builder.getLayoutConstraint(kind: layoutKind)
            }
            requirements.append(builder.createRequirement(kind: .layout, subjectType: subjectType, layout: layout))

        default:
            break
        }
    }
}

extension TypeDecoder {
    #if canImport(ObjectiveC)
    private func getObjCClassOrProtocolName(_ node: Node) -> String? {
        guard node.kind == .class || node.kind == .protocol else {
            return nil
        }

        guard node.children.count == 2 else {
            return nil
        }

        let moduleNode = node.children[0]
        guard moduleNode.kind == .module,
              moduleNode.text == objcModule else {
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
