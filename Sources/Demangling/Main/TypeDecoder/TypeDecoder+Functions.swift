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
private extension TypeDecoder {
    func functionConvention(for kind: Node.Kind) -> FunctionMetadataConvention {
        switch kind {
        case .objCBlock, .escapingObjCBlock:
            return .block
        case .cFunctionPointer:
            return .cFunctionPointer
        case .thinFunctionType:
            return .thin
        default:
            return .swift
        }
    }

    func isEscapingFunction(_ kind: Node.Kind) -> Bool {
        switch kind {
        case .functionType, .escapingAutoClosureType, .escapingObjCBlock:
            return true
        default:
            return false
        }
    }

    func decodeGlobalActorAndIsolation(
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

    func decodeDifferentiability(
        node: Node,
        startIndex: Int
    ) throws -> (FunctionMetadataDifferentiabilityKind, Int) {
        var index = startIndex
        var diffKind = FunctionMetadataDifferentiabilityKind.nonDifferentiable

        if index < node.children.count && node.children[index].kind == .differentiableFunctionType {
            guard let rawValue = node.children[index].index else {
                throw makeNodeError(node.children[index], "missing differentiability index")
            }

            diffKind = FunctionMetadataDifferentiabilityKind(from: UInt8(rawValue))
            index += 1
        }

        return (diffKind, index)
    }

    func decodeThrows(
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

    func decodeFunctionParameters(
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

    func decodeMangledFunctionInputType(
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

    func decodeParameterElement(
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

    func decodeSingleParameter(
        _ node: Node,
        depth: Int,
        params: inout [FunctionParam<BuiltType>],
        hasParamFlags: inout Bool
    ) throws {
        let param = try decodeParameterType(node, depth: depth, hasParamFlags: &hasParamFlags)
        params.append(param)
    }

    func decodeParameterType(
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

            case .autoClosureType, .escapingAutoClosureType:
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
private extension TypeDecoder {
    func decodeImplConvention(
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

    func decodeImplFunctionConvention(
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

    func decodeImplFunctionAttribute(
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

    func decodeImplCoroutineKind(_ node: Node) throws -> ImplCoroutineKind {
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

    func decodeImplDifferentiabilityKind(
        _ node: Node,
        flags: ImplFunctionTypeFlags
    ) throws -> ImplFunctionTypeFlags {
        guard let index = node.index else {
            throw makeNodeError(node, "missing differentiability index")
        }

        let diffKind = ImplFunctionDifferentiabilityKind(from: UInt8(index))
        return flags.withDifferentiabilityKind(diffKind)
    }

    func decodeImplFunctionParam<T: ImplFunctionParamProtocol>(
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
        for i in 1..<(node.children.count - 1) {
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

        let param = T(type: type, convention: convention as! T.ConventionType, options: options)
        results.append(param)
    }

    func decodeImplFunctionResult<T: ImplFunctionResultProtocol>(
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
        for i in 1..<(node.children.count - 1) {
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

        let result = T(type: type, convention: convention as! T.ConventionType, options: options)
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