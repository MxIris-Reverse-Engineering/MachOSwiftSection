package struct Demangler<C> where C: Collection, C.Iterator.Element == UnicodeScalar {
    private var scanner: ScalarScanner<C>
    private var nameStack: [SwiftSymbol] = []
    private var substitutions: [SwiftSymbol] = []
    private var words: [String] = []
    private var symbolicReferences: [Int32] = []
    private var isOldFunctionTypeMangling: Bool = false
    private var flavor: ManglingFlavor = .default
    private var symbolicReferenceIndex: Int = 0
    
    package var symbolicReferenceResolver: SymbolicReferenceResolver? = nil
    
    package init(scalars: C) {
        self.scanner = ScalarScanner(scalars: scalars)
    }
}

extension Demangler {
    func require<T>(_ optional: T?) throws -> T {
        if let v = optional {
            return v
        } else {
            throw failure
        }
    }

    func require(_ value: Bool) throws {
        if !value {
            throw failure
        }
    }

    var failure: Error {
        return scanner.unexpectedError()
    }

    mutating func readManglingPrefix() throws {
        let prefixes = [
            "_T0", "$S", "_$S", "$s", "_$s", "$e", "_$e", "@__swiftmacro_",
        ]
        for prefix in prefixes {
            if scanner.conditional(string: prefix) {
                return
            }
        }
        throw scanner.unexpectedError()
    }

    mutating func reset() {
        nameStack = []
        substitutions = []
        words = []
        scanner.reset()
    }

    mutating func popTopLevelInto(_ parent: inout SwiftSymbol) throws {
        while var funcAttr = pop(where: { $0.isFunctionAttr }) {
            switch funcAttr.kind {
            case .partialApplyForwarder,
                 .partialApplyObjCForwarder:
                try popTopLevelInto(&funcAttr)
                parent.children.append(funcAttr)
                return
            default:
                parent.children.append(funcAttr)
            }
        }
        for name in nameStack {
            switch name.kind {
            case .type: try parent.children.append(require(name.children.first))
            default: parent.children.append(name)
            }
        }
    }

    package mutating func demangleSymbol() throws -> SwiftSymbol {
        reset()

        if scanner.conditional(string: "_Tt") {
            return try demangleObjCTypeName()
        } else if scanner.conditional(string: "_T") {
            isOldFunctionTypeMangling = true
            try scanner.backtrack(count: 2)
        }

        try readManglingPrefix()
        try parseAndPushNames()

        let suffix = pop(kind: .suffix)
        var topLevel = SwiftSymbol(kind: .global)
        try popTopLevelInto(&topLevel)
        if let suffix {
            topLevel.children.append(suffix)
        }
        try require(topLevel.children.count != 0)
        return topLevel
    }

    package mutating func demangleType() throws -> SwiftSymbol {
        reset()

        try parseAndPushNames()
        if let result = pop() {
            return result
        }

        return SwiftSymbol(kind: .suffix, children: [], contents: .name(String(String.UnicodeScalarView(scanner.scalars))))
    }

    mutating func parseAndPushNames() throws {
        while !scanner.isAtEnd {
            try nameStack.append(demangleOperator())
        }
    }

    mutating func demangleSymbolicReference(rawValue: UInt8) throws -> SwiftSymbol {
        guard let (kind, directness) = SymbolicReference.symbolicReference(for: rawValue) else {
            throw SwiftSymbolParseError.unimplementedFeature
        }
        guard let symbolicReferenceResolver, let symbol = symbolicReferenceResolver(kind, directness, symbolicReferenceIndex) else {
            throw SwiftSymbolParseError.unimplementedFeature
        }
        symbolicReferenceIndex += 1
        substitutions.append(symbol)
        return symbol
    }

    mutating func demangleTypeAnnotation() throws -> SwiftSymbol {
        switch try scanner.readScalar() {
        case "a": return SwiftSymbol(kind: .asyncAnnotation)
        case "A": return SwiftSymbol(kind: .isolatedAnyFunctionType)
        case "b": return SwiftSymbol(kind: .concurrentFunctionType)
        case "c": return try SwiftSymbol(kind: .globalActorFunctionType, child: require(popTypeAndGetChild()))
        case "i": return try SwiftSymbol(typeWithChildKind: .isolated, childChild: require(popTypeAndGetChild()))
        case "j": return try demangleDifferentiableFunctionType()
        case "k": return try SwiftSymbol(typeWithChildKind: .noDerivative, childChild: require(popTypeAndGetChild()))
        case "K": return try SwiftSymbol(kind: .typedThrowsAnnotation, child: require(popTypeAndGetChild()))
        case "t": return try SwiftSymbol(typeWithChildKind: .compileTimeConst, childChild: require(popTypeAndGetChild()))
        case "T": return SwiftSymbol(kind: .sendingResultFunctionType)
        case "u": return try SwiftSymbol(typeWithChildKind: .sending, childChild: require(popTypeAndGetChild()))
        default: throw failure
        }
    }

    mutating func demangleOperator() throws -> SwiftSymbol {
        let scalar = try scanner.readScalar()
        switch scalar {
        case "\u{1}",
             "\u{2}",
             "\u{3}",
             "\u{4}",
             "\u{5}",
             "\u{6}",
             "\u{7}",
             "\u{8}",
             "\u{9}",
             "\u{A}",
             "\u{B}",
             "\u{C}":
//            try scanner.backtrack()
            return try demangleSymbolicReference(rawValue: .init(scalar.value))
        case "A": return try demangleMultiSubstitutions()
        case "B": return try demangleBuiltinType()
        case "C": return try demangleAnyGenericType(kind: .class)
        case "D": return try SwiftSymbol(kind: .typeMangling, child: require(pop(kind: .type)))
        case "E": return try demangleExtensionContext()
        case "F": return try demanglePlainFunction()
        case "G": return try demangleBoundGenericType()
        case "H":
            switch try scanner.readScalar() {
            case "A": return try demangleDependentProtocolConformanceAssociated()
            case "C": return try demangleConcreteProtocolConformance()
            case "D": return try demangleDependentProtocolConformanceRoot()
            case "I": return try demangleDependentProtocolConformanceInherited()
            case "P": return try SwiftSymbol(kind: .protocolConformanceRefInTypeModule, child: popProtocol())
            case "p": return try SwiftSymbol(kind: .protocolConformanceRefInProtocolModule, child: popProtocol())
            case "X": return try SwiftSymbol(kind: .packProtocolConformance, child: popAnyProtocolConformanceList())
            case "c": return try SwiftSymbol(kind: .protocolConformanceDescriptorRecord, child: popProtocolConformance())
            case "n": return try SwiftSymbol(kind: .nominalTypeDescriptorRecord, child: require(pop(kind: .type)))
            case "o": return try SwiftSymbol(kind: .opaqueTypeDescriptorRecord, child: require(pop()))
            case "r": return try SwiftSymbol(kind: .protocolDescriptorRecord, child: popProtocol())
            case "F": return SwiftSymbol(kind: .accessibleFunctionRecord)
            default:
                try scanner.backtrack(count: 2)
                return try demangleIdentifier()
            }
        case "I": return try demangleImplFunctionType()
        case "K": return SwiftSymbol(kind: .throwsAnnotation)
        case "L": return try demangleLocalIdentifier()
        case "M": return try demangleMetatype()
        case "N": return try SwiftSymbol(kind: .typeMetadata, child: require(pop(kind: .type)))
        case "O": return try demangleAnyGenericType(kind: .enum)
        case "P": return try demangleAnyGenericType(kind: .protocol)
        case "Q": return try demangleArchetype()
        case "R": return try demangleGenericRequirement()
        case "S": return try demangleStandardSubstitution()
        case "T": return try demangleThunkOrSpecialization()
        case "V": return try demangleAnyGenericType(kind: .structure)
        case "W": return try demangleWitness()
        case "X": return try demangleSpecialType()
        case "Y": return try demangleTypeAnnotation()
        case "Z": return try SwiftSymbol(kind: .static, child: require(pop(where: { $0.isEntity })))
        case "a": return try demangleAnyGenericType(kind: .typeAlias)
        case "c": return try require(popFunctionType(kind: .functionType))
        case "d": return SwiftSymbol(kind: .variadicMarker)
        case "f": return try demangleFunctionEntity()
        case "g": return try demangleRetroactiveConformance()
        case "h": return try SwiftSymbol(typeWithChildKind: .shared, childChild: require(popTypeAndGetChild()))
        case "i": return try demangleSubscript()
        case "l": return try demangleGenericSignature(hasParamCounts: false)
        case "m": return try SwiftSymbol(typeWithChildKind: .metatype, childChild: require(pop(kind: .type)))
        case "n": return try SwiftSymbol(typeWithChildKind: .owned, childChild: popTypeAndGetChild())
        case "o": return try demangleOperatorIdentifier()
        case "p": return try demangleProtocolListType()
        case "q": return try SwiftSymbol(kind: .type, child: demangleGenericParamIndex())
        case "r": return try demangleGenericSignature(hasParamCounts: true)
        case "s": return SwiftSymbol(kind: .module, contents: .name(stdlibName))
        case "t": return try popTuple()
        case "u": return try demangleGenericType()
        case "v": return try demangleVariable()
        case "w": return try demangleValueWitness()
        case "x": return try SwiftSymbol(kind: .type, child: getDependentGenericParamType(depth: 0, index: 0))
        case "y": return SwiftSymbol(kind: .emptyList)
        case "z": return try SwiftSymbol(typeWithChildKind: .inOut, childChild: require(popTypeAndGetChild()))
        case "_": return SwiftSymbol(kind: .firstElementMarker)
        case ".":
            try scanner.backtrack()
            return SwiftSymbol(kind: .suffix, contents: .name(scanner.remainder()))
        case "$": return try demangleIntegerType()
        default:
            try scanner.backtrack()
            return try demangleIdentifier()
        }
    }

    mutating func demangleNatural() throws -> UInt64? {
        return try scanner.conditionalInt()
    }

    mutating func demangleIndex() throws -> UInt64 {
        if scanner.conditional(scalar: "_") {
            return 0
        }
        let value = try require(demangleNatural())
        try scanner.match(scalar: "_")
        return value + 1
    }

    mutating func demangleIndexAsName() throws -> SwiftSymbol {
        return try SwiftSymbol(kind: .number, contents: .index(demangleIndex()))
    }

    mutating func demangleMultiSubstitutions() throws -> SwiftSymbol {
        var repeatCount: Int = -1
        while true {
            let c = try scanner.readScalar()
            if c == "\0" {
                throw scanner.unexpectedError()
            } else if c.isLower {
                let nd = try pushMultiSubstitutions(repeatCount: repeatCount, index: Int(c.value - UnicodeScalar("a").value))
                nameStack.append(nd)
                repeatCount = -1
                continue
            } else if c.isUpper {
                return try pushMultiSubstitutions(repeatCount: repeatCount, index: Int(c.value - UnicodeScalar("A").value))
            } else if c == "_" {
                let idx = Int(repeatCount + 27)
                return try require(substitutions.at(idx))
            } else {
                try scanner.backtrack()
                repeatCount = try Int(demangleNatural() ?? 0)
            }
        }
    }

    mutating func pushMultiSubstitutions(repeatCount: Int, index: Int) throws -> SwiftSymbol {
        try require(repeatCount <= maxRepeatCount)
        let nd = try require(substitutions.at(index))
        (0 ..< max(0, repeatCount - 1)).forEach { _ in nameStack.append(nd) }
        return nd
    }

    mutating func pop() -> SwiftSymbol? {
        return nameStack.popLast()
    }

    mutating func pop(kind: SwiftSymbol.Kind) -> SwiftSymbol? {
        return nameStack.last?.kind == kind ? pop() : nil
    }

    mutating func pop(where cond: (SwiftSymbol.Kind) -> Bool) -> SwiftSymbol? {
        return nameStack.last.map { cond($0.kind) } == true ? pop() : nil
    }

    mutating func popFunctionType(kind: SwiftSymbol.Kind, hasClangType: Bool = false) throws -> SwiftSymbol {
        var name = SwiftSymbol(kind: kind)
        if hasClangType {
            try name.children.append(demangleClangType())
        }
        if let sendingResult = pop(kind: .sendingResultFunctionType) {
            name.children.append(sendingResult)
        }
        if let isFunctionIsolation = pop(where: { $0 == .globalActorFunctionType || $0 == .isolatedAnyFunctionType }) {
            name.children.append(isFunctionIsolation)
        }
        if let differentiable = pop(kind: .differentiableFunctionType) {
            name.children.append(differentiable)
        }
        if let throwsAnnotation = pop(where: { $0 == .throwsAnnotation || $0 == .typedThrowsAnnotation }) {
            name.children.append(throwsAnnotation)
        }
        if let concurrent = pop(kind: .concurrentFunctionType) {
            name.children.append(concurrent)
        }
        if let asyncAnnotation = pop(kind: .asyncAnnotation) {
            name.children.append(asyncAnnotation)
        }
        try name.children.append(popFunctionParams(kind: .argumentTuple))
        try name.children.append(popFunctionParams(kind: .returnType))
        return SwiftSymbol(kind: .type, child: name)
    }

    mutating func popFunctionParams(kind: SwiftSymbol.Kind) throws -> SwiftSymbol {
        let paramsType: SwiftSymbol
        if pop(kind: .emptyList) != nil {
            return SwiftSymbol(kind: kind, child: SwiftSymbol(kind: .type, child: SwiftSymbol(kind: .tuple)))
        } else {
            paramsType = try require(pop(kind: .type))
        }

        if kind == .argumentTuple {
            let params = try require(paramsType.children.first)
            let numParams = params.kind == .tuple ? params.children.count : 1
            return SwiftSymbol(kind: kind, children: [paramsType], contents: .index(UInt64(numParams)))
        } else {
            return SwiftSymbol(kind: kind, children: [paramsType])
        }
    }

    mutating func getLabel(params: inout SwiftSymbol, idx: Int) throws -> SwiftSymbol {
        if isOldFunctionTypeMangling {
            let param = try require(params.children.at(idx))
            if let label = param.children.enumerated().first(where: { $0.element.kind == .tupleElementName }) {
                params.children[idx].children.remove(at: label.offset)
                return SwiftSymbol(kind: .identifier, contents: .name(label.element.text ?? ""))
            }
            return SwiftSymbol(kind: .firstElementMarker)
        }
        return try require(pop())
    }

    mutating func popFunctionParamLabels(type: SwiftSymbol) throws -> SwiftSymbol? {
        if !isOldFunctionTypeMangling && pop(kind: .emptyList) != nil {
            return SwiftSymbol(kind: .labelList)
        }

        guard type.kind == .type else { return nil }

        let topFuncType = try require(type.children.first)
        let funcType: SwiftSymbol
        if topFuncType.kind == .dependentGenericType {
            funcType = try require(topFuncType.children.at(1)?.children.first)
        } else {
            funcType = topFuncType
        }

        guard funcType.kind == .functionType || funcType.kind == .noEscapeFunctionType else { return nil }

        var firstChildIndex = 0
        if funcType.children.at(firstChildIndex)?.kind == .sendingResultFunctionType {
            firstChildIndex += 1
        }
        if funcType.children.at(firstChildIndex)?.kind == .globalActorFunctionType {
            firstChildIndex += 1
        }
        if funcType.children.at(firstChildIndex)?.kind == .isolatedAnyFunctionType {
            firstChildIndex += 1
        }
        if funcType.children.at(firstChildIndex)?.kind == .differentiableFunctionType {
            firstChildIndex += 1
        }
        if funcType.children.at(firstChildIndex)?.kind == .throwsAnnotation || funcType.children.at(0)?.kind == .typedThrowsAnnotation {
            firstChildIndex += 1
        }
        if funcType.children.at(firstChildIndex)?.kind == .asyncAnnotation {
            firstChildIndex += 1
        }

        let parameterType = try require(funcType.children.at(firstChildIndex))
        try require(parameterType.kind == .argumentTuple)

        let paramsType = try require(parameterType.children.first)
        try require(paramsType.kind == .type)

        let params = paramsType.children.first
        let numParams = params?.kind == .tuple ? (params?.children.count ?? 0) : 1

        guard numParams > 0 else { return nil }

        let possibleTuple = parameterType.children.first?.children.first
        guard !isOldFunctionTypeMangling, var tuple = possibleTuple, tuple.kind == .tuple else {
            return SwiftSymbol(kind: .labelList)
        }

        var hasLabels = false
        var children = [SwiftSymbol]()
        for i in 0 ..< numParams {
            let label = try getLabel(params: &tuple, idx: Int(i))
            try require(label.kind == .identifier || label.kind == .firstElementMarker)
            children.append(label)
            hasLabels = hasLabels || (label.kind != .firstElementMarker)
        }

        if !hasLabels {
            return SwiftSymbol(kind: .labelList)
        }

        return SwiftSymbol(kind: .labelList, children: isOldFunctionTypeMangling ? children : children.reversed())
    }

    mutating func popTuple() throws -> SwiftSymbol {
        var children: [SwiftSymbol] = []
        if pop(kind: .emptyList) == nil {
            var firstElem = false
            repeat {
                firstElem = pop(kind: .firstElementMarker) != nil
                var elemChildren: [SwiftSymbol] = pop(kind: .variadicMarker).map { [$0] } ?? []
                if let ident = pop(kind: .identifier), case let .name(text) = ident.contents {
                    elemChildren.append(SwiftSymbol(kind: .tupleElementName, contents: .name(text)))
                }
                try elemChildren.append(require(pop(kind: .type)))
                children.insert(SwiftSymbol(kind: .tupleElement, children: elemChildren), at: 0)
            } while !firstElem
        }
        return SwiftSymbol(typeWithChildKind: .tuple, childChildren: children)
    }

    mutating func popPack(kind: SwiftSymbol.Kind = .pack) throws -> SwiftSymbol {
        if pop(kind: .emptyList) != nil {
            return SwiftSymbol(kind: .type, child: SwiftSymbol(kind: .pack))
        }
        var firstElem = false
        var children = [SwiftSymbol]()
        repeat {
            firstElem = pop(kind: .firstElementMarker) != nil
            try children.append(require(pop(kind: .type)))
        } while !firstElem
        children.reverse()
        return SwiftSymbol(kind: .type, child: SwiftSymbol(kind: .pack, children: children))
    }

    mutating func popSilPack() throws -> SwiftSymbol {
        switch try scanner.readScalar() {
        case "d": return try popPack(kind: .silPackDirect)
        case "i": return try popPack(kind: .silPackIndirect)
        default: throw failure
        }
    }

    mutating func popTypeList() throws -> SwiftSymbol {
        var children: [SwiftSymbol] = []
        if pop(kind: .emptyList) == nil {
            var firstElem = false
            repeat {
                firstElem = pop(kind: .firstElementMarker) != nil
                try children.insert(require(pop(kind: .type)), at: 0)
            } while !firstElem
        }
        return SwiftSymbol(kind: .typeList, children: children)
    }

    mutating func popProtocol() throws -> SwiftSymbol {
        if let type = pop(kind: .type) {
            try require(type.children.at(0)?.isProtocol == true)
            return type
        }

        if let symbolicRef = pop(kind: .protocolSymbolicReference) {
            return symbolicRef
        } else if let symbolicRef = pop(kind: .objectiveCProtocolSymbolicReference) {
            return symbolicRef
        }

        let name = try require(pop { $0.isDeclName })
        let context = try popContext()
        return SwiftSymbol(typeWithChildKind: .protocol, childChildren: [context, name])
    }

    mutating func popAnyProtocolConformanceList() throws -> SwiftSymbol {
        var conformanceList = SwiftSymbol(kind: .anyProtocolConformanceList)
        if pop(kind: .emptyList) == nil {
            var firstElem = false
            repeat {
                firstElem = pop(kind: .firstElementMarker) != nil
                try conformanceList.children.append(require(popAnyProtocolConformance()))
            } while !firstElem
            conformanceList.children = conformanceList.children.reversed()
        }
        return conformanceList
    }

    mutating func popAnyProtocolConformance() -> SwiftSymbol? {
        return pop { kind in
            switch kind {
            case .concreteProtocolConformance,
                 .packProtocolConformance,
                 .dependentProtocolConformanceRoot,
                 .dependentProtocolConformanceInherited,
                 .dependentProtocolConformanceAssociated: return true
            default: return false
            }
        }
    }

    mutating func demangleRetroactiveProtocolConformanceRef() throws -> SwiftSymbol {
        let module = try require(popModule())
        let proto = try require(popProtocol())
        return SwiftSymbol(kind: .protocolConformanceRefInOtherModule, children: [proto, module])
    }

    mutating func demangleConcreteProtocolConformance() throws -> SwiftSymbol {
        let conditionalConformanceList = try require(popAnyProtocolConformanceList())
        let conformanceRef = try pop(kind: .protocolConformanceRefInTypeModule) ?? pop(kind: .protocolConformanceRefInProtocolModule) ?? demangleRetroactiveProtocolConformanceRef()
        return try SwiftSymbol(kind: .concreteProtocolConformance, children: [require(pop(kind: .type)), conformanceRef, conditionalConformanceList])
    }

    mutating func popDependentProtocolConformance() -> SwiftSymbol? {
        return pop { kind in
            switch kind {
            case .dependentProtocolConformanceRoot,
                 .dependentProtocolConformanceInherited,
                 .dependentProtocolConformanceAssociated: return true
            default: return false
            }
        }
    }

    mutating func demangleDependentProtocolConformanceRoot() throws -> SwiftSymbol {
        let index = try demangleDependentConformanceIndex()
        let prot = try popProtocol()
        return try SwiftSymbol(kind: .dependentProtocolConformanceRoot, children: [require(pop(kind: .type)), prot, index])
    }

    mutating func demangleDependentProtocolConformanceInherited() throws -> SwiftSymbol {
        let index = try demangleDependentConformanceIndex()
        let prot = try popProtocol()
        let nested = try require(popDependentProtocolConformance())
        return SwiftSymbol(kind: .dependentProtocolConformanceInherited, children: [nested, prot, index])
    }

    mutating func popDependentAssociatedConformance() throws -> SwiftSymbol {
        let prot = try popProtocol()
        let dependentType = try require(pop(kind: .type))
        return SwiftSymbol(kind: .dependentAssociatedConformance, children: [dependentType, prot])
    }

    mutating func demangleDependentProtocolConformanceAssociated() throws -> SwiftSymbol {
        let index = try demangleDependentConformanceIndex()
        let assoc = try popDependentAssociatedConformance()
        let nested = try require(popDependentProtocolConformance())
        return SwiftSymbol(kind: .dependentProtocolConformanceAssociated, children: [nested, assoc, index])
    }

    mutating func demangleDependentConformanceIndex() throws -> SwiftSymbol {
        let index = try demangleIndex()
        if index == 1 {
            return SwiftSymbol(kind: .unknownIndex)
        }
        return SwiftSymbol(kind: .index, contents: .index(index - 2))
    }

    mutating func popModule() -> SwiftSymbol? {
        if let ident = pop(kind: .identifier) {
            return ident.changeKind(.module)
        } else {
            return pop(kind: .module)
        }
    }

    mutating func popContext() throws -> SwiftSymbol {
        if let mod = popModule() {
            return mod
        } else if let type = pop(kind: .type) {
            let child = try require(type.children.first)
            try require(child.kind.isContext)
            return child
        }
        return try require(pop { $0.isContext })
    }

    mutating func popTypeAndGetChild() throws -> SwiftSymbol {
        return try require(pop(kind: .type)?.children.first)
    }

    mutating func popTypeAndGetAnyGeneric() throws -> SwiftSymbol {
        let child = try popTypeAndGetChild()
        try require(child.kind.isAnyGeneric)
        return child
    }

    mutating func popAssociatedTypeName() throws -> SwiftSymbol {
        let maybeProto = pop(kind: .type)
        let proto: SwiftSymbol?
        if let p = maybeProto {
            try require(p.isProtocol)
            proto = p
        } else {
            proto = pop(kind: .protocolSymbolicReference) ?? pop(kind: .objectiveCProtocolSymbolicReference)
        }

        let id = try require(pop(kind: .identifier))
        if let p = proto {
            return SwiftSymbol(kind: .dependentAssociatedTypeRef, children: [id, p])
        } else {
            return SwiftSymbol(kind: .dependentAssociatedTypeRef, child: id)
        }
    }

    mutating func popAssociatedTypePath() throws -> SwiftSymbol {
        var firstElem = false
        var assocTypePath = [SwiftSymbol]()
        repeat {
            firstElem = pop(kind: .firstElementMarker) != nil
            try assocTypePath.append(require(popAssociatedTypeName()))
        } while !firstElem
        return SwiftSymbol(kind: .assocTypePath, children: assocTypePath.reversed())
    }

    mutating func popProtocolConformance() throws -> SwiftSymbol {
        let genSig = pop(kind: .dependentGenericSignature)
        let module = try require(popModule())
        let proto = try popProtocol()
        var type = pop(kind: .type)
        var ident: SwiftSymbol? = nil
        if type == nil {
            ident = pop(kind: .identifier)
            type = pop(kind: .type)
        }
        if let gs = genSig {
            type = try SwiftSymbol(typeWithChildKind: .dependentGenericType, childChildren: [gs, require(type)])
        }
        var children = try [require(type), proto, module]
        if let i = ident {
            children.append(i)
        }
        return SwiftSymbol(kind: .protocolConformance, children: children)
    }

    mutating func getDependentGenericParamType(depth: Int, index: Int) throws -> SwiftSymbol {
        try require(depth >= 0 && index >= 0)
        var charIndex = index
        var name = ""
        repeat {
            try name.unicodeScalars.append(require(UnicodeScalar(UnicodeScalar("A").value + UInt32(charIndex % 26))))
            charIndex /= 26
        } while charIndex != 0
        if depth != 0 {
            name = "\(name)\(depth)"
        }

        return SwiftSymbol(kind: .dependentGenericParamType, children: [
            SwiftSymbol(kind: .index, contents: .index(UInt64(depth))),
            SwiftSymbol(kind: .index, contents: .index(UInt64(index))),
        ], contents: .name(name))
    }

    mutating func demangleStandardSubstitution() throws -> SwiftSymbol {
        switch try scanner.readScalar() {
        case "o": return SwiftSymbol(kind: .module, contents: .name(objcModule))
        case "C": return SwiftSymbol(kind: .module, contents: .name(cModule))
        case "g":
            let op = try SwiftSymbol(typeWithChildKind: .boundGenericEnum, childChildren: [
                SwiftSymbol(swiftStdlibTypeKind: .enum, name: "Optional"),
                SwiftSymbol(kind: .typeList, child: require(pop(kind: .type))),
            ])
            substitutions.append(op)
            return op
        default:
            try scanner.backtrack()
            let repeatCount = try demangleNatural() ?? 0
            try require(repeatCount <= maxRepeatCount)
            let secondLevel = scanner.conditional(scalar: "c")
            let nd: SwiftSymbol
            if secondLevel {
                switch try scanner.readScalar() {
                case "A": nd = SwiftSymbol(swiftStdlibTypeKind: .structure, name: "Actor")
                case "C": nd = SwiftSymbol(swiftStdlibTypeKind: .structure, name: "CheckedContinuation")
                case "c": nd = SwiftSymbol(swiftStdlibTypeKind: .structure, name: "UnsafeContinuation")
                case "E": nd = SwiftSymbol(swiftStdlibTypeKind: .structure, name: "CancellationError")
                case "e": nd = SwiftSymbol(swiftStdlibTypeKind: .structure, name: "UnownedSerialExecutor")
                case "F": nd = SwiftSymbol(swiftStdlibTypeKind: .protocol, name: "Executor")
                case "f": nd = SwiftSymbol(swiftStdlibTypeKind: .protocol, name: "SerialExecutor")
                case "G": nd = SwiftSymbol(swiftStdlibTypeKind: .structure, name: "TaskGroup")
                case "g": nd = SwiftSymbol(swiftStdlibTypeKind: .structure, name: "ThrowingTaskGroup")
                case "h": nd = SwiftSymbol(swiftStdlibTypeKind: .protocol, name: "TaskExecutor")
                case "I": nd = SwiftSymbol(swiftStdlibTypeKind: .protocol, name: "AsyncIteratorProtocol")
                case "i": nd = SwiftSymbol(swiftStdlibTypeKind: .protocol, name: "AsyncSequence")
                case "J": nd = SwiftSymbol(swiftStdlibTypeKind: .structure, name: "UnownedJob")
                case "M": nd = SwiftSymbol(swiftStdlibTypeKind: .class, name: "MainActor")
                case "P": nd = SwiftSymbol(swiftStdlibTypeKind: .structure, name: "TaskPriority")
                case "S": nd = SwiftSymbol(swiftStdlibTypeKind: .structure, name: "AsyncStream")
                case "s": nd = SwiftSymbol(swiftStdlibTypeKind: .structure, name: "AsyncThrowingStream")
                case "T": nd = SwiftSymbol(swiftStdlibTypeKind: .structure, name: "Task")
                case "t": nd = SwiftSymbol(swiftStdlibTypeKind: .structure, name: "UnsafeCurrentTask")
                default: throw failure
                }
            } else {
                switch try scanner.readScalar() {
                case "a": nd = SwiftSymbol(swiftStdlibTypeKind: .structure, name: "Array")
                case "A": nd = SwiftSymbol(swiftStdlibTypeKind: .structure, name: "AutoreleasingUnsafeMutablePointer")
                case "b": nd = SwiftSymbol(swiftStdlibTypeKind: .structure, name: "Bool")
                case "c": nd = SwiftSymbol(swiftStdlibTypeKind: .structure, name: "UnicodeScalar")
                case "D": nd = SwiftSymbol(swiftStdlibTypeKind: .structure, name: "Dictionary")
                case "d": nd = SwiftSymbol(swiftStdlibTypeKind: .structure, name: "Double")
                case "f": nd = SwiftSymbol(swiftStdlibTypeKind: .structure, name: "Float")
                case "h": nd = SwiftSymbol(swiftStdlibTypeKind: .structure, name: "Set")
                case "I": nd = SwiftSymbol(swiftStdlibTypeKind: .structure, name: "DefaultIndices")
                case "i": nd = SwiftSymbol(swiftStdlibTypeKind: .structure, name: "Int")
                case "J": nd = SwiftSymbol(swiftStdlibTypeKind: .structure, name: "Character")
                case "N": nd = SwiftSymbol(swiftStdlibTypeKind: .structure, name: "ClosedRange")
                case "n": nd = SwiftSymbol(swiftStdlibTypeKind: .structure, name: "Range")
                case "O": nd = SwiftSymbol(swiftStdlibTypeKind: .structure, name: "ObjectIdentifier")
                case "p": nd = SwiftSymbol(swiftStdlibTypeKind: .structure, name: "UnsafeMutablePointer")
                case "P": nd = SwiftSymbol(swiftStdlibTypeKind: .structure, name: "UnsafePointer")
                case "R": nd = SwiftSymbol(swiftStdlibTypeKind: .structure, name: "UnsafeBufferPointer")
                case "r": nd = SwiftSymbol(swiftStdlibTypeKind: .structure, name: "UnsafeMutableBufferPointer")
                case "S": nd = SwiftSymbol(swiftStdlibTypeKind: .structure, name: "String")
                case "s": nd = SwiftSymbol(swiftStdlibTypeKind: .structure, name: "Substring")
                case "u": nd = SwiftSymbol(swiftStdlibTypeKind: .structure, name: "UInt")
                case "v": nd = SwiftSymbol(swiftStdlibTypeKind: .structure, name: "UnsafeMutableRawPointer")
                case "V": nd = SwiftSymbol(swiftStdlibTypeKind: .structure, name: "UnsafeRawPointer")
                case "W": nd = SwiftSymbol(swiftStdlibTypeKind: .structure, name: "UnsafeRawBufferPointer")
                case "w": nd = SwiftSymbol(swiftStdlibTypeKind: .structure, name: "UnsafeMutableRawBufferPointer")
                case "q": nd = SwiftSymbol(swiftStdlibTypeKind: .enum, name: "Optional")
                case "B": nd = SwiftSymbol(swiftStdlibTypeKind: .protocol, name: "BinaryFloatingPoint")
                case "E": nd = SwiftSymbol(swiftStdlibTypeKind: .protocol, name: "Encodable")
                case "e": nd = SwiftSymbol(swiftStdlibTypeKind: .protocol, name: "Decodable")
                case "F": nd = SwiftSymbol(swiftStdlibTypeKind: .protocol, name: "FloatingPoint")
                case "G": nd = SwiftSymbol(swiftStdlibTypeKind: .protocol, name: "RandomNumberGenerator")
                case "H": nd = SwiftSymbol(swiftStdlibTypeKind: .protocol, name: "Hashable")
                case "j": nd = SwiftSymbol(swiftStdlibTypeKind: .protocol, name: "Numeric")
                case "K": nd = SwiftSymbol(swiftStdlibTypeKind: .protocol, name: "BidirectionalCollection")
                case "k": nd = SwiftSymbol(swiftStdlibTypeKind: .protocol, name: "RandomAccessCollection")
                case "L": nd = SwiftSymbol(swiftStdlibTypeKind: .protocol, name: "Comparable")
                case "l": nd = SwiftSymbol(swiftStdlibTypeKind: .protocol, name: "Collection")
                case "M": nd = SwiftSymbol(swiftStdlibTypeKind: .protocol, name: "MutableCollection")
                case "m": nd = SwiftSymbol(swiftStdlibTypeKind: .protocol, name: "RangeReplaceableCollection")
                case "Q": nd = SwiftSymbol(swiftStdlibTypeKind: .protocol, name: "Equatable")
                case "T": nd = SwiftSymbol(swiftStdlibTypeKind: .protocol, name: "Sequence")
                case "t": nd = SwiftSymbol(swiftStdlibTypeKind: .protocol, name: "IteratorProtocol")
                case "U": nd = SwiftSymbol(swiftStdlibTypeKind: .protocol, name: "UnsignedInteger")
                case "X": nd = SwiftSymbol(swiftStdlibTypeKind: .protocol, name: "RangeExpression")
                case "x": nd = SwiftSymbol(swiftStdlibTypeKind: .protocol, name: "Strideable")
                case "Y": nd = SwiftSymbol(swiftStdlibTypeKind: .protocol, name: "RawRepresentable")
                case "y": nd = SwiftSymbol(swiftStdlibTypeKind: .protocol, name: "StringProtocol")
                case "Z": nd = SwiftSymbol(swiftStdlibTypeKind: .protocol, name: "SignedInteger")
                case "z": nd = SwiftSymbol(swiftStdlibTypeKind: .protocol, name: "BinaryInteger")
                default: throw failure
                }
            }
            if repeatCount > 1 {
                for _ in 0 ..< (repeatCount - 1) {
                    nameStack.append(nd)
                }
            }
            return nd
        }
    }

    mutating func demangleIdentifier() throws -> SwiftSymbol {
        var hasWordSubs = false
        var isPunycoded = false
        let c = try scanner.read(where: { $0.isDigit })
        if c == "0" {
            if try scanner.readScalar() == "0" {
                isPunycoded = true
            } else {
                try scanner.backtrack()
                hasWordSubs = true
            }
        } else {
            try scanner.backtrack()
        }

        var identifier = ""
        repeat {
            while hasWordSubs && scanner.peek()?.isLetter == true {
                let c = try scanner.readScalar()
                var wordIndex = 0
                if c.isLower {
                    wordIndex = Int(c.value - UnicodeScalar("a").value)
                } else {
                    wordIndex = Int(c.value - UnicodeScalar("A").value)
                    hasWordSubs = false
                }
                try require(wordIndex < maxNumWords)
                try identifier.append(require(words.at(wordIndex)))
            }
            if scanner.conditional(scalar: "0") {
                break
            }
            let numChars = try require(demangleNatural())
            try require(numChars > 0)
            if isPunycoded {
                _ = scanner.conditional(scalar: "_")
            }
            let text = try scanner.readScalars(count: Int(numChars))
            if isPunycoded {
                try identifier.append(decodeSwiftPunycode(text))
            } else {
                identifier.append(text)
                var word: String?
                for c in text.unicodeScalars {
                    if word == nil, !c.isDigit && c != "_" && words.count < maxNumWords {
                        word = "\(c)"
                    } else if let w = word {
                        if (c == "_") || (w.unicodeScalars.last?.isUpper == false && c.isUpper) {
                            if w.unicodeScalars.count >= 2 {
                                words.append(w)
                            }
                            if !c.isDigit && c != "_" && words.count < maxNumWords {
                                word = "\(c)"
                            } else {
                                word = nil
                            }
                        } else {
                            word?.unicodeScalars.append(c)
                        }
                    }
                }
                if let w = word, w.unicodeScalars.count >= 2 {
                    words.append(w)
                }
            }
        } while hasWordSubs
        try require(!identifier.isEmpty)
        let result = SwiftSymbol(kind: .identifier, contents: .name(identifier))
        substitutions.append(result)
        return result
    }

    mutating func demangleOperatorIdentifier() throws -> SwiftSymbol {
        let ident = try require(pop(kind: .identifier))
        let opCharTable = Array("& @/= >    <*!|+?%-~   ^ .".unicodeScalars)

        var str = ""
        for c in try (require(ident.text)).unicodeScalars {
            if !c.isASCII {
                str.unicodeScalars.append(c)
            } else {
                try require(c.isLower)
                let o = try require(opCharTable.at(Int(c.value - UnicodeScalar("a").value)))
                try require(o != " ")
                str.unicodeScalars.append(o)
            }
        }
        switch try scanner.readScalar() {
        case "i": return SwiftSymbol(kind: .infixOperator, contents: .name(str))
        case "p": return SwiftSymbol(kind: .prefixOperator, contents: .name(str))
        case "P": return SwiftSymbol(kind: .postfixOperator, contents: .name(str))
        default: throw failure
        }
    }

    mutating func demangleLocalIdentifier() throws -> SwiftSymbol {
        let c = try scanner.readScalar()
        switch c {
        case "L":
            let discriminator = try require(pop(kind: .identifier))
            let name = try require(pop(where: { $0.isDeclName }))
            return SwiftSymbol(kind: .privateDeclName, children: [discriminator, name])
        case "l":
            let discriminator = try require(pop(kind: .identifier))
            return SwiftSymbol(kind: .privateDeclName, children: [discriminator])
        case "a" ... "j",
             "A" ... "J":
            return try SwiftSymbol(kind: .relatedEntityDeclName, children: [require(pop())], contents: .name(String(c)))
        default:
            try scanner.backtrack()
            let discriminator = try demangleIndexAsName()
            let name = try require(pop(where: { $0.isDeclName }))
            return SwiftSymbol(kind: .localDeclName, children: [discriminator, name])
        }
    }

    mutating func demangleBuiltinType() throws -> SwiftSymbol {
        let maxTypeSize: UInt64 = 4096
        switch try scanner.readScalar() {
        case "b": return SwiftSymbol(swiftBuiltinType: .builtinTypeName, name: "Builtin.BridgeObject")
        case "B": return SwiftSymbol(swiftBuiltinType: .builtinTypeName, name: "Builtin.UnsafeValueBuffer")
        case "e": return SwiftSymbol(swiftBuiltinType: .builtinTypeName, name: "Builtin.Executor")
        case "f":
            let size = try demangleIndex() - 1
            try require(size > 0 && size <= maxTypeSize)
            return SwiftSymbol(swiftBuiltinType: .builtinTypeName, name: "Builtin.FPIEEE\(size)")
        case "i":
            let size = try demangleIndex() - 1
            try require(size > 0 && size <= maxTypeSize)
            return SwiftSymbol(swiftBuiltinType: .builtinTypeName, name: "Builtin.Int\(size)")
        case "I": return SwiftSymbol(swiftBuiltinType: .builtinTypeName, name: "Builtin.IntLiteral")
        case "v":
            let elts = try demangleIndex() - 1
            try require(elts > 0 && elts <= maxTypeSize)
            let eltType = try popTypeAndGetChild()
            let text = try require(eltType.text)
            try require(eltType.kind == .builtinTypeName && text.starts(with: "Builtin.") == true)
            let name = text["Builtin.".endIndex...]
            return SwiftSymbol(swiftBuiltinType: .builtinTypeName, name: "Builtin.Vec\(elts)x\(name)")
        case "V":
            let element = try require(pop(kind: .type))
            let size = try require(pop(kind: .type))
            return SwiftSymbol(kind: .builtinFixedArray, children: [size, element])
        case "O": return SwiftSymbol(swiftBuiltinType: .builtinTypeName, name: "Builtin.UnknownObject")
        case "o": return SwiftSymbol(swiftBuiltinType: .builtinTypeName, name: "Builtin.NativeObject")
        case "p": return SwiftSymbol(swiftBuiltinType: .builtinTypeName, name: "Builtin.RawPointer")
        case "t": return SwiftSymbol(swiftBuiltinType: .builtinTypeName, name: "Builtin.SILToken")
        case "w": return SwiftSymbol(swiftBuiltinType: .builtinTypeName, name: "Builtin.Word")
        case "c": return SwiftSymbol(swiftBuiltinType: .builtinTypeName, name: "Builtin.DefaultActorStorage")
        case "D": return SwiftSymbol(swiftBuiltinType: .builtinTypeName, name: "Builtin.DefaultActorStorage")
        case "d": return SwiftSymbol(swiftBuiltinType: .builtinTypeName, name: "Builtin.NonDefaultDistributedActorStorage")
        case "j": return SwiftSymbol(swiftBuiltinType: .builtinTypeName, name: "Builtin.Job")
        case "P": return SwiftSymbol(swiftBuiltinType: .builtinTypeName, name: "Builtin.PackIndex")
        default: throw failure
        }
    }

    mutating func demangleAnyGenericType(kind: SwiftSymbol.Kind) throws -> SwiftSymbol {
        let name = try require(pop(where: { $0.isDeclName }))
        let ctx = try popContext()
        let type = SwiftSymbol(typeWithChildKind: kind, childChildren: [ctx, name])
        substitutions.append(type)
        return type
    }

    mutating func demangleExtensionContext() throws -> SwiftSymbol {
        let genSig = pop(kind: .dependentGenericSignature)
        let module = try require(popModule())
        let type = try popTypeAndGetAnyGeneric()
        if let g = genSig {
            return SwiftSymbol(kind: .extension, children: [module, type, g])
        } else {
            return SwiftSymbol(kind: .extension, children: [module, type])
        }
    }

    enum ManglingFlavor {
        case `default`
        case embedded
    }

    func getParentId(parent: SwiftSymbol, flavor: ManglingFlavor) -> String {
        return "{ParentId}"
    }

    mutating func setParentForOpaqueReturnTypeNodes(visited: inout SwiftSymbol, parentId: String) {
        if visited.kind == .opaqueReturnType {
            if visited.children.last?.kind == .opaqueReturnTypeParent {
                return
            }
            visited.children.append(SwiftSymbol(kind: .opaqueReturnTypeParent, contents: .name(parentId)))
            return
        }

        switch visited.kind {
        case .function,
             .variable,
             .subscript: return
        default: break
        }

        for index in visited.children.indices {
            setParentForOpaqueReturnTypeNodes(visited: &visited.children[index], parentId: parentId)
        }
    }

    mutating func demanglePlainFunction() throws -> SwiftSymbol {
        let genSig = pop(kind: .dependentGenericSignature)
        var type = try popFunctionType(kind: .functionType)
        let labelList = try popFunctionParamLabels(type: type)

        if let g = genSig {
            type = SwiftSymbol(typeWithChildKind: .dependentGenericType, childChildren: [g, type])
        }
        let name = try require(pop(where: { $0.isDeclName }))
        let ctx = try popContext()
        if let ll = labelList {
            return SwiftSymbol(kind: .function, children: [ctx, name, ll, type])
        }
        return SwiftSymbol(kind: .function, children: [ctx, name, type])
    }

    mutating func demangleRetroactiveConformance() throws -> SwiftSymbol {
        let index = try demangleIndexAsName()
        let conformance = try require(popAnyProtocolConformance())
        return SwiftSymbol(kind: .retroactiveConformance, children: [index, conformance])
    }

    mutating func demangleBoundGenericType() throws -> SwiftSymbol {
        let (array, retroactiveConformances) = try demangleBoundGenerics()
        let nominal = try popTypeAndGetAnyGeneric()
        var children = try [demangleBoundGenericArgs(nominal: nominal, array: array, index: 0)]
        if !retroactiveConformances.isEmpty {
            children.append(SwiftSymbol(kind: .typeList, children: retroactiveConformances.reversed()))
        }
        let type = SwiftSymbol(kind: .type, children: children)
        substitutions.append(type)
        return type
    }

    mutating func popRetroactiveConformances() throws -> SwiftSymbol? {
        var retroactiveConformances: [SwiftSymbol] = []
        while let conformance = pop(kind: .retroactiveConformance) {
            retroactiveConformances.append(conformance)
        }
        retroactiveConformances = retroactiveConformances.reversed()
        return retroactiveConformances.isEmpty ? nil : SwiftSymbol(kind: .typeList, children: retroactiveConformances)
    }

    mutating func demangleBoundGenerics() throws -> (typeLists: [SwiftSymbol], conformances: [SwiftSymbol]) {
        let retroactiveConformances = try popRetroactiveConformances()

        var array = [SwiftSymbol]()
        while true {
            var children = [SwiftSymbol]()
            while let t = pop(kind: .type) {
                children.append(t)
            }
            array.append(SwiftSymbol(kind: .typeList, children: children.reversed()))

            if pop(kind: .emptyList) != nil {
                break
            } else {
                _ = try require(pop(kind: .firstElementMarker))
            }
        }

        return (array, retroactiveConformances?.children ?? [])
    }

    mutating func demangleBoundGenericArgs(nominal: SwiftSymbol, array: [SwiftSymbol], index: Int) throws -> SwiftSymbol {
        if nominal.kind == .typeSymbolicReference || nominal.kind == .protocolSymbolicReference {
            let remaining = array.reversed().flatMap { $0.children }
            return SwiftSymbol(kind: .boundGenericOtherNominalType, children: [SwiftSymbol(kind: .type, child: nominal), SwiftSymbol(kind: .typeList, children: remaining)])
        }

        let context = try require(nominal.children.first)

        let consumesGenericArgs: Bool
        switch nominal.kind {
        case .variable,
             .subscript,
             .implicitClosure,
             .explicitClosure,
             .defaultArgumentInitializer,
             .initializer,
             .propertyWrapperBackingInitializer,
             .propertyWrapperInitFromProjectedValue,
             .static:
            consumesGenericArgs = false
        default:
            consumesGenericArgs = true
        }

        let args = try require(array.at(index))

        let n: SwiftSymbol
        let offsetIndex = index + (consumesGenericArgs ? 1 : 0)
        if offsetIndex < array.count {
            var boundParent: SwiftSymbol
            if context.kind == .extension {
                let p = try demangleBoundGenericArgs(nominal: require(context.children.at(1)), array: array, index: offsetIndex)
                boundParent = try SwiftSymbol(kind: .extension, children: [require(context.children.first), p])
                if let thirdChild = context.children.at(2) {
                    boundParent.children.append(thirdChild)
                }
            } else {
                boundParent = try demangleBoundGenericArgs(nominal: context, array: array, index: offsetIndex)
            }
            n = SwiftSymbol(kind: nominal.kind, children: [boundParent] + nominal.children.dropFirst())
        } else {
            n = nominal
        }

        if !consumesGenericArgs || args.children.count == 0 {
            return n
        }

        let kind: SwiftSymbol.Kind
        switch n.kind {
        case .class: kind = .boundGenericClass
        case .structure: kind = .boundGenericStructure
        case .enum: kind = .boundGenericEnum
        case .protocol: kind = .boundGenericProtocol
        case .otherNominalType: kind = .boundGenericOtherNominalType
        case .typeAlias: kind = .boundGenericTypeAlias
        case .function,
             .constructor: return SwiftSymbol(kind: .boundGenericFunction, children: [n, args])
        default: throw failure
        }

        return SwiftSymbol(kind: kind, children: [SwiftSymbol(kind: .type, child: n), args])
    }

    mutating func demangleImplParamConvention(kind: SwiftSymbol.Kind) throws -> SwiftSymbol? {
        let attr: String
        switch try scanner.readScalar() {
        case "i": attr = "@in"
        case "c": attr = "@in_constant"
        case "l": attr = "@inout"
        case "b": attr = "@inout_aliasable"
        case "n": attr = "@in_guaranteed"
        case "X": attr = "@in_cxx"
        case "x": attr = "@owned"
        case "g": attr = "@guaranteed"
        case "e": attr = "@deallocating"
        case "y": attr = "@unowned"
        case "v": attr = "@pack_owned"
        case "p": attr = "@pack_guaranteed"
        case "m": attr = "@pack_inout"
        default:
            try scanner.backtrack()
            return nil
        }
        return SwiftSymbol(kind: kind, child: SwiftSymbol(kind: .implConvention, contents: .name(attr)))
    }

    mutating func demangleImplResultConvention(kind: SwiftSymbol.Kind) throws -> SwiftSymbol? {
        let attr: String
        switch try scanner.readScalar() {
        case "r": attr = "@out"
        case "o": attr = "@owned"
        case "d": attr = "@unowned"
        case "u": attr = "@unowned_inner_pointer"
        case "a": attr = "@autoreleased"
        case "k": attr = "@pack_out"
        default:
            try scanner.backtrack()
            return nil
        }
        return SwiftSymbol(kind: kind, child: SwiftSymbol(kind: .implConvention, contents: .name(attr)))
    }

    mutating func demangleImplParameterSending() -> SwiftSymbol? {
        guard scanner.conditional(scalar: "T") else {
            return nil
        }
        return SwiftSymbol(kind: .implParameterSending, contents: .name("sending"))
    }

    mutating func demangleImplResultDifferentiability() -> SwiftSymbol {
        return SwiftSymbol(kind: .implParameterResultDifferentiability, contents: .name(scanner.conditional(scalar: "w") ? "@noDerivative" : ""))
    }

    mutating func demangleClangType() throws -> SwiftSymbol {
        let numChars = try require(demangleNatural())
        let text = try scanner.readScalars(count: Int(numChars))
        return SwiftSymbol(kind: .clangType, contents: .name(text))
    }

    mutating func demangleImplFunctionType() throws -> SwiftSymbol {
        var typeChildren = [SwiftSymbol]()
        if scanner.conditional(scalar: "s") {
            let (substitutions, conformances) = try demangleBoundGenerics()
            let sig = try require(pop(kind: .dependentGenericSignature))
            let subsNode = try SwiftSymbol(kind: .implPatternSubstitutions, children: [sig, require(substitutions.first)] + conformances)
            typeChildren.append(subsNode)
        }

        if scanner.conditional(scalar: "I") {
            let (substitutions, conformances) = try demangleBoundGenerics()
            let subsNode = try SwiftSymbol(kind: .implInvocationSubstitutions, children: [require(substitutions.first)] + conformances)
            typeChildren.append(subsNode)
        }

        var genSig = pop(kind: .dependentGenericSignature)
        if let g = genSig, scanner.conditional(scalar: "P") {
            genSig = g.changeKind(.dependentPseudogenericSignature)
        }

        if scanner.conditional(scalar: "e") {
            typeChildren.append(SwiftSymbol(kind: .implEscaping))
        }

        if scanner.conditional(scalar: "A") {
            typeChildren.append(SwiftSymbol(kind: .implErasedIsolation))
        }

        if let peek = scanner.peek(), let differentiability = Differentiability(rawValue: peek) {
            try scanner.skip()
            typeChildren.append(SwiftSymbol(kind: .implDifferentiabilityKind, contents: .index(UInt64(differentiability.rawValue))))
        }

        let cAttr: String
        switch try scanner.readScalar() {
        case "y": cAttr = "@callee_unowned"
        case "g": cAttr = "@callee_guaranteed"
        case "x": cAttr = "@callee_owned"
        case "t": cAttr = "@convention(thin)"
        default: throw failure
        }
        typeChildren.append(SwiftSymbol(kind: .implConvention, contents: .name(cAttr)))

        let fConv: String?
        var hasClangType = false
        switch try scanner.readScalar() {
        case "B": fConv = "block"
        case "C": fConv = "c"
        case "z":
            if scanner.conditional(scalar: "B") {
                hasClangType = true
                fConv = "block"
            } else if scanner.conditional(scalar: "C") {
                hasClangType = true
                fConv = "c"
            } else {
                fConv = nil
            }
        case "M": fConv = "method"
        case "O": fConv = "objc_method"
        case "K": fConv = "closure"
        case "W": fConv = "witness_method"
        default:
            try scanner.backtrack()
            fConv = nil
        }
        if let fConv {
            var node = SwiftSymbol(kind: .implFunctionConvention, child: SwiftSymbol(kind: .implFunctionConventionName, contents: .name(fConv)))
            if hasClangType {
                try node.children.append(demangleClangType())
            }
            typeChildren.append(node)
        }

        if scanner.conditional(scalar: "A") {
            typeChildren.append(SwiftSymbol(kind: .implCoroutineKind, contents: .name("yield_once")))
        } else if scanner.conditional(scalar: "I") {
            typeChildren.append(SwiftSymbol(kind: .implCoroutineKind, contents: .name("yield_once_2")))
        } else if scanner.conditional(scalar: "G") {
            typeChildren.append(SwiftSymbol(kind: .implCoroutineKind, contents: .name("yield_many")))
        }

        if scanner.conditional(scalar: "h") {
            typeChildren.append(SwiftSymbol(kind: .implFunctionAttribute, contents: .name("@Sendable")))
        }

        if scanner.conditional(scalar: "H") {
            typeChildren.append(SwiftSymbol(kind: .implFunctionAttribute, contents: .name("@async")))
        }

        if scanner.conditional(scalar: "T") {
            typeChildren.append(SwiftSymbol(kind: .implSendingResult))
        }

        if let g = genSig {
            typeChildren.append(g)
        }

        var numTypesToAdd = 0
        while var param = try demangleImplParamConvention(kind: .implParameter) {
            param.children.append(demangleImplResultDifferentiability())
            if let diff = demangleImplParameterSending() {
                param.children.append(diff)
            }
            typeChildren.append(param)
            numTypesToAdd += 1
        }
        while var result = try demangleImplResultConvention(kind: .implResult) {
            result.children.append(demangleImplResultDifferentiability())
            typeChildren.append(result)
            numTypesToAdd += 1
        }
        while scanner.conditional(scalar: "Y") {
            try typeChildren.append(require(demangleImplParamConvention(kind: .implYield)))
            numTypesToAdd += 1
        }
        if scanner.conditional(scalar: "z") {
            try typeChildren.append(require(demangleImplResultConvention(kind: .implErrorResult)))
            numTypesToAdd += 1
        }
        try scanner.match(scalar: "_")
        for i in 0 ..< numTypesToAdd {
            try require(typeChildren.indices.contains(typeChildren.count - i - 1))
            try typeChildren[typeChildren.count - i - 1].children.append(require(pop(kind: .type)))
        }

        return SwiftSymbol(typeWithChildKind: .implFunctionType, childChildren: typeChildren)
    }

    mutating func demangleMetatype() throws -> SwiftSymbol {
        switch try scanner.readScalar() {
        case "a": return try SwiftSymbol(kind: .typeMetadataAccessFunction, child: require(pop(kind: .type)))
        case "A": return try SwiftSymbol(kind: .reflectionMetadataAssocTypeDescriptor, child: popProtocolConformance())
        case "b": return try SwiftSymbol(kind: .canonicalSpecializedGenericTypeMetadataAccessFunction, child: require(pop(kind: .type)))
        case "B": return try SwiftSymbol(kind: .reflectionMetadataBuiltinDescriptor, child: require(pop(kind: .type)))
        case "c": return try SwiftSymbol(kind: .protocolConformanceDescriptor, child: require(popProtocolConformance()))
        case "C":
            let t = try require(pop(kind: .type))
            try require(t.children.first?.kind.isAnyGeneric == true)
            return try SwiftSymbol(kind: .reflectionMetadataSuperclassDescriptor, child: require(t.children.first))
        case "D": return try SwiftSymbol(kind: .typeMetadataDemanglingCache, child: require(pop(kind: .type)))
        case "f": return try SwiftSymbol(kind: .fullTypeMetadata, child: require(pop(kind: .type)))
        case "F": return try SwiftSymbol(kind: .reflectionMetadataFieldDescriptor, child: require(pop(kind: .type)))
        case "g": return try SwiftSymbol(kind: .opaqueTypeDescriptorAccessor, child: require(pop()))
        case "h": return try SwiftSymbol(kind: .opaqueTypeDescriptorAccessorImpl, child: require(pop()))
        case "i": return try SwiftSymbol(kind: .typeMetadataInstantiationFunction, child: require(pop(kind: .type)))
        case "I": return try SwiftSymbol(kind: .typeMetadataInstantiationCache, child: require(pop(kind: .type)))
        case "j": return try SwiftSymbol(kind: .opaqueTypeDescriptorAccessorKey, child: require(pop()))
        case "J": return try SwiftSymbol(kind: .noncanonicalSpecializedGenericTypeMetadataCache, child: require(pop()))
        case "k": return try SwiftSymbol(kind: .opaqueTypeDescriptorAccessorVar, child: require(pop()))
        case "K": return try SwiftSymbol(kind: .metadataInstantiationCache, child: require(pop()))
        case "l": return try SwiftSymbol(kind: .typeMetadataSingletonInitializationCache, child: require(pop(kind: .type)))
        case "L": return try SwiftSymbol(kind: .typeMetadataLazyCache, child: require(pop(kind: .type)))
        case "m": return try SwiftSymbol(kind: .metaclass, child: require(pop(kind: .type)))
        case "M": return try SwiftSymbol(kind: .canonicalSpecializedGenericMetaclass, child: require(pop(kind: .type)))
        case "n": return try SwiftSymbol(kind: .nominalTypeDescriptor, child: require(pop(kind: .type)))
        case "N": return try SwiftSymbol(kind: .noncanonicalSpecializedGenericTypeMetadata, child: require(pop(kind: .type)))
        case "o": return try SwiftSymbol(kind: .classMetadataBaseOffset, child: require(pop(kind: .type)))
        case "p": return try SwiftSymbol(kind: .protocolDescriptor, child: popProtocol())
        case "P": return try SwiftSymbol(kind: .genericTypeMetadataPattern, child: require(pop(kind: .type)))
        case "q": return try SwiftSymbol(kind: .uniquable, child: require(pop()))
        case "Q": return try SwiftSymbol(kind: .opaqueTypeDescriptor, child: require(pop()))
        case "r": return try SwiftSymbol(kind: .typeMetadataCompletionFunction, child: require(pop(kind: .type)))
        case "s": return try SwiftSymbol(kind: .objCResilientClassStub, child: require(popProtocol()))
        case "S": return try SwiftSymbol(kind: .protocolSelfConformanceDescriptor, child: require(pop(kind: .type)))
        case "t": return try SwiftSymbol(kind: .fullObjCResilientClassStub, child: require(pop(kind: .type)))
        case "u": return try SwiftSymbol(kind: .methodLookupFunction, child: require(pop(kind: .type)))
        case "U": return try SwiftSymbol(kind: .objCMetadataUpdateFunction, child: require(pop(kind: .type)))
        case "V": return try SwiftSymbol(kind: .propertyDescriptor, child: require(pop { $0.isEntity }))
        case "X": return try demanglePrivateContextDescriptor()
        case "z": return try SwiftSymbol(kind: .canonicalPrespecializedGenericTypeCachingOnceToken, child: require(pop(kind: .type)))
        default: throw failure
        }
    }

    mutating func demanglePrivateContextDescriptor() throws -> SwiftSymbol {
        switch try scanner.readScalar() {
        case "E": return try SwiftSymbol(kind: .extensionDescriptor, child: popContext())
        case "M": return try SwiftSymbol(kind: .moduleDescriptor, child: require(popModule()))
        case "Y":
            let discriminator = try require(pop())
            let context = try popContext()
            return SwiftSymbol(kind: .anonymousDescriptor, children: [context, discriminator])
        case "X": return try SwiftSymbol(kind: .anonymousDescriptor, child: popContext())
        case "A":
            let path = try require(popAssociatedTypePath())
            let base = try require(pop(kind: .type))
            return SwiftSymbol(kind: .associatedTypeGenericParamRef, children: [base, path])
        default: throw failure
        }
    }

    mutating func demangleArchetype() throws -> SwiftSymbol {
        switch try scanner.readScalar() {
        case "a":
            let ident = try require(pop(kind: .identifier))
            let arch = try popTypeAndGetChild()
            let assoc = SwiftSymbol(typeWithChildKind: .associatedTypeRef, childChildren: [arch, ident])
            substitutions.append(assoc)
            return assoc
        case "O":
            return try SwiftSymbol(kind: .opaqueReturnTypeOf, child: popContext())
        case "o":
            let index = try demangleIndex()
            let (boundGenericArgs, retroactiveConformances) = try demangleBoundGenerics()
            let name = try require(pop())
            let opaque = SwiftSymbol(
                kind: .opaqueType,
                children: [
                    name,
                    SwiftSymbol(kind: .index, contents: .index(index)),
                    SwiftSymbol(kind: .typeList, children: boundGenericArgs + retroactiveConformances),
                ]
            )
            let opaqueType = SwiftSymbol(kind: .type, child: opaque)
            substitutions.append(opaqueType)
            return opaqueType
        case "r":
            return SwiftSymbol(typeWithChildKind: .opaqueReturnType, childChildren: [])
        case "x":
            let t = try demangleAssociatedTypeSimple(index: nil)
            substitutions.append(t)
            return t
        case "X":
            let t = try demangleAssociatedTypeCompound(index: nil)
            substitutions.append(t)
            return t
        case "y":
            let t = try demangleAssociatedTypeSimple(index: demangleGenericParamIndex())
            substitutions.append(t)
            return t
        case "Y":
            let t = try demangleAssociatedTypeCompound(index: demangleGenericParamIndex())
            substitutions.append(t)
            return t
        case "z":
            let t = try demangleAssociatedTypeSimple(index: getDependentGenericParamType(depth: 0, index: 0))
            substitutions.append(t)
            return t
        case "Z":
            let t = try demangleAssociatedTypeCompound(index: getDependentGenericParamType(depth: 0, index: 0))
            substitutions.append(t)
            return t
        case "p":
            let count = try popTypeAndGetChild()
            let pattern = try popTypeAndGetChild()
            return SwiftSymbol(kind: .type, child: SwiftSymbol(kind: .packExpansion, children: [pattern, count]))
        case "e":
            let pack = try popTypeAndGetChild()
            let level = try demangleIndex()
            return SwiftSymbol(kind: .type, child: SwiftSymbol(kind: .packElement, children: [pack, SwiftSymbol(kind: .packElementLevel, contents: .index(level))]))
        case "P":
            return try popPack()
        case "S":
            return try popSilPack()
        default: throw failure
        }
    }

    mutating func demangleAssociatedTypeSimple(index: SwiftSymbol?) throws -> SwiftSymbol {
        let atName = try popAssociatedTypeName()
        let gpi = try index.map { SwiftSymbol(kind: .type, child: $0) } ?? require(pop(kind: .type))
        return SwiftSymbol(typeWithChildKind: .dependentMemberType, childChildren: [gpi, atName])
    }

    mutating func demangleAssociatedTypeCompound(index: SwiftSymbol?) throws -> SwiftSymbol {
        var assocTypeNames = [SwiftSymbol]()
        var firstElem = false
        repeat {
            firstElem = pop(kind: .firstElementMarker) != nil
            try assocTypeNames.append(popAssociatedTypeName())
        } while !firstElem

        var base = try index.map { SwiftSymbol(kind: .type, child: $0) } ?? require(pop(kind: .type))
        while let assocType = assocTypeNames.popLast() {
            base = SwiftSymbol(kind: .type, child: SwiftSymbol(kind: .dependentMemberType, children: [SwiftSymbol(kind: .type, child: base), assocType]))
        }
        return base
    }

    mutating func demangleGenericParamIndex() throws -> SwiftSymbol {
        switch try scanner.readScalar() {
        case "d":
            let depth = try demangleIndex() + 1
            let index = try demangleIndex()
            return try getDependentGenericParamType(depth: Int(depth), index: Int(index))
        case "z":
            return try getDependentGenericParamType(depth: 0, index: 0)
        case "s":
            return SwiftSymbol(kind: .constrainedExistentialSelf)
        default:
            try scanner.backtrack()
            return try getDependentGenericParamType(depth: 0, index: Int(demangleIndex() + 1))
        }
    }

    mutating func demangleThunkOrSpecialization() throws -> SwiftSymbol {
        let c = try scanner.readScalar()
        switch c {
        case "T":
            switch try scanner.readScalar() {
            case "I": return try SwiftSymbol(kind: .silThunkIdentity, child: require(pop(where: { $0.isEntity })))
            case "H": return try SwiftSymbol(kind: .silThunkHopToMainActorIfNeeded, child: require(pop(where: { $0.isEntity })))
            default: throw failure
            }
        case "c": return try SwiftSymbol(kind: .curryThunk, child: require(pop(where: { $0.isEntity })))
        case "j": return try SwiftSymbol(kind: .dispatchThunk, child: require(pop(where: { $0.isEntity })))
        case "q": return try SwiftSymbol(kind: .methodDescriptor, child: require(pop(where: { $0.isEntity })))
        case "o": return SwiftSymbol(kind: .objCAttribute)
        case "O": return SwiftSymbol(kind: .nonObjCAttribute)
        case "D": return SwiftSymbol(kind: .dynamicAttribute)
        case "d": return SwiftSymbol(kind: .directMethodReferenceAttribute)
        case "E": return SwiftSymbol(kind: .distributedThunk)
        case "F": return SwiftSymbol(kind: .distributedAccessor)
        case "a": return SwiftSymbol(kind: .partialApplyObjCForwarder)
        case "A": return SwiftSymbol(kind: .partialApplyForwarder)
        case "m": return SwiftSymbol(kind: .mergedFunction)
        case "X": return SwiftSymbol(kind: .dynamicallyReplaceableFunctionVar)
        case "x": return SwiftSymbol(kind: .dynamicallyReplaceableFunctionKey)
        case "I": return SwiftSymbol(kind: .dynamicallyReplaceableFunctionImpl)
        case "Y": return try SwiftSymbol(kind: .asyncSuspendResumePartialFunction, child: demangleIndexAsName())
        case "Q": return try SwiftSymbol(kind: .asyncAwaitResumePartialFunction, child: demangleIndexAsName())
        case "C": return try SwiftSymbol(kind: .coroutineContinuationPrototype, child: require(pop(kind: .type)))
        case "z": fallthrough
        case "Z":
            let flagMode = try demangleIndexAsName()
            let sig = pop(kind: .dependentGenericSignature)
            let resultType = try require(pop(kind: .type))
            let implType = try require(pop(kind: .type))
            var node = SwiftSymbol(kind: c == "z" ? .objCAsyncCompletionHandlerImpl : .predefinedObjCAsyncCompletionHandlerImpl, children: [implType, resultType, flagMode])
            if let sig {
                node.children.append(sig)
            }
            return node
        case "V":
            let base = try require(pop(where: { $0.isEntity }))
            let derived = try require(pop(where: { $0.isEntity }))
            return SwiftSymbol(kind: .vTableThunk, children: [derived, base])
        case "W":
            let entity = try require(pop(where: { $0.isEntity }))
            let conf = try popProtocolConformance()
            return SwiftSymbol(kind: .protocolWitness, children: [conf, entity])
        case "S":
            return try SwiftSymbol(kind: .protocolSelfConformanceWitness, child: require(pop(where: { $0.isEntity })))
        case "R",
             "r",
             "y":
            let kind = switch c {
            case "R": SwiftSymbol.Kind.reabstractionThunkHelper
            case "y": SwiftSymbol.Kind.reabstractionThunkHelperWithSelf
            default: SwiftSymbol.Kind.reabstractionThunk
            }
            var name = SwiftSymbol(kind: kind)
            if let genSig = pop(kind: .dependentGenericSignature) {
                name.children.append(genSig)
            }
            if kind == .reabstractionThunkHelperWithSelf {
                try name.children.append(require(pop(kind: .type)))
            }
            try name.children.append(require(pop(kind: .type)))
            try name.children.append(require(pop(kind: .type)))
            return name
        case "g": return try demangleGenericSpecialization(kind: .genericSpecialization)
        case "G": return try demangleGenericSpecialization(kind: .genericSpecializationNotReAbstracted)
        case "B": return try demangleGenericSpecialization(kind: .genericSpecializationInResilienceDomain)
        case "t": return try demangleGenericSpecializationWithDroppedArguments()
        case "s": return try demangleGenericSpecialization(kind: .genericSpecializationPrespecialized)
        case "i": return try demangleGenericSpecialization(kind: .inlinedGenericFunction)
        case "P",
             "p":
            var spec = try demangleSpecAttributes(kind: c == "P" ? .genericPartialSpecializationNotReAbstracted : .genericPartialSpecialization)
            let param = try SwiftSymbol(kind: .genericSpecializationParam, child: require(pop(kind: .type)))
            spec.children.append(param)
            return spec
        case "f": return try demangleFunctionSpecialization()
        case "K",
             "k":
            let nodeKind: SwiftSymbol.Kind = c == "K" ? .keyPathGetterThunkHelper : .keyPathSetterThunkHelper
            let isSerialized = scanner.conditional(string: "q")
            var types = [SwiftSymbol]()
            var node = pop(kind: .type)
            while let n = node {
                types.append(n)
                node = pop(kind: .type)
            }
            var result: SwiftSymbol
            if let n = pop() {
                if n.kind == .dependentGenericSignature {
                    let decl = try require(pop())
                    result = SwiftSymbol(kind: nodeKind, children: [decl, n])
                } else {
                    result = SwiftSymbol(kind: nodeKind, child: n)
                }
            } else {
                throw failure
            }
            for t in types {
                result.children.append(t)
            }
            if isSerialized {
                result.children.append(SwiftSymbol(kind: .isSerialized))
            }
            return result
        case "l": return try SwiftSymbol(kind: .associatedTypeDescriptor, child: require(popAssociatedTypeName()))
        case "L": return try SwiftSymbol(kind: .protocolRequirementsBaseDescriptor, child: require(popProtocol()))
        case "M": return try SwiftSymbol(kind: .defaultAssociatedTypeMetadataAccessor, child: require(popAssociatedTypeName()))
        case "n":
            let requirement = try popProtocol()
            let associatedTypePath = try popAssociatedTypePath()
            let protocolType = try require(pop(kind: .type))
            return SwiftSymbol(kind: .associatedConformanceDescriptor, children: [protocolType, associatedTypePath, requirement])
        case "N":
            let requirement = try popProtocol()
            let associatedTypePath = try popAssociatedTypePath()
            let protocolType = try require(pop(kind: .type))
            return SwiftSymbol(kind: .defaultAssociatedConformanceAccessor, children: [protocolType, associatedTypePath, requirement])
        case "b":
            let requirement = try popProtocol()
            let protocolType = try require(pop(kind: .type))
            return SwiftSymbol(kind: .baseConformanceDescriptor, children: [protocolType, requirement])
        case "H",
             "h":
            let nodeKind: SwiftSymbol.Kind = c == "H" ? .keyPathEqualsThunkHelper : .keyPathHashThunkHelper
            let isSerialized = scanner.peek() == "q"
            var types = [SwiftSymbol]()
            let node = try require(pop())
            var genericSig: SwiftSymbol? = nil
            if node.kind == .dependentGenericSignature {
                genericSig = node
            } else if node.kind == .type {
                types.append(node)
            } else {
                throw failure
            }
            while let n = pop() {
                try require(n.kind == .type)
                types.append(n)
            }
            var result = SwiftSymbol(kind: nodeKind)
            for t in types {
                result.children.append(t)
            }
            if let gs = genericSig {
                result.children.append(gs)
            }
            if isSerialized {
                result.children.append(SwiftSymbol(kind: .isSerialized))
            }
            return result
        case "v":
            let index = try demangleIndex()
            if scanner.conditional(scalar: "r") {
                return SwiftSymbol(kind: .outlinedReadOnlyObject, contents: .index(index))
            } else {
                return SwiftSymbol(kind: .outlinedVariable, contents: .index(index))
            }
        case "e": return try SwiftSymbol(kind: .outlinedBridgedMethod, contents: .name(demangleBridgedMethodParams()))
        case "u": return SwiftSymbol(kind: .asyncFunctionPointer)
        case "U":
            let globalActor = try require(pop(kind: .type))
            let reabstraction = try require(pop())
            return SwiftSymbol(kind: .reabstractionThunkHelperWithGlobalActor, children: [reabstraction, globalActor])
        case "J":
            switch try scanner.readScalar() {
            case "S": return try demangleAutoDiffSubsetParametersThunk()
            case "O": return try demangleAutoDiffSelfReorderingReabstractionThunk()
            case "V": return try demangleAutoDiffFunctionOrSimpleThunk(kind: .autoDiffDerivativeVTableThunk)
            default:
                try scanner.backtrack()
                return try demangleAutoDiffFunctionOrSimpleThunk(kind: .autoDiffFunction)
            }
        case "w":
            switch try scanner.readScalar() {
            case "b": return SwiftSymbol(kind: .backDeploymentThunk)
            case "B": return SwiftSymbol(kind: .backDeploymentFallback)
            case "S": return SwiftSymbol(kind: .hasSymbolQuery)
            default: throw failure
            }
        default: throw failure
        }
    }

    mutating func demangleAutoDiffFunctionOrSimpleThunk(kind: SwiftSymbol.Kind) throws -> SwiftSymbol {
        var result = SwiftSymbol(kind: kind)
        while let node = pop() {
            result.children.append(node)
        }
        result.children.reverse()
        let kind = try demangleAutoDiffFunctionKind()
        result.children.append(kind)
        try result.children.append(require(demangleIndexSubset()))
        try scanner.match(scalar: "p")
        try result.children.append(require(demangleIndexSubset()))
        try scanner.match(scalar: "r")
        return result
    }

    mutating func demangleAutoDiffFunctionKind() throws -> SwiftSymbol {
        let kind = try scanner.readScalar()
        guard let autoDiffFunctionKind = AutoDiffFunctionKind(UInt64(kind.value)) else {
            throw failure
        }
        return SwiftSymbol(kind: .autoDiffFunctionKind, contents: .index(UInt64(autoDiffFunctionKind.rawValue.value)))
    }

    mutating func demangleAutoDiffSubsetParametersThunk() throws -> SwiftSymbol {
        var result = SwiftSymbol(kind: .autoDiffSubsetParametersThunk)
        while let node = pop() {
            result.children.append(node)
        }
        result.children.reverse()
        let kind = try demangleAutoDiffFunctionKind()
        result.children.append(kind)
        try result.children.append(require(demangleIndexSubset()))
        try scanner.match(scalar: "p")
        try result.children.append(require(demangleIndexSubset()))
        try scanner.match(scalar: "r")
        try result.children.append(require(demangleIndexSubset()))
        try scanner.match(scalar: "P")
        return result
    }

    mutating func demangleAutoDiffSelfReorderingReabstractionThunk() throws -> SwiftSymbol {
        var result = SwiftSymbol(kind: .autoDiffSelfReorderingReabstractionThunk)
        if let dependentGenericSignature = pop(kind: .dependentGenericSignature) {
            result.children.append(dependentGenericSignature)
        }
        try result.children.append(require(pop(kind: .type)))
        try result.children.append(require(pop(kind: .type)))
        result.children.reverse()
        try result.children.append(demangleAutoDiffFunctionKind())
        return result
    }

    mutating func demangleDifferentiabilityWitness() throws -> SwiftSymbol {
        var result = SwiftSymbol(kind: .differentiabilityWitness)
        let optionalGenSig = pop(kind: .dependentGenericSignature)
        while let node = pop() {
            result.children.append(node)
        }
        result.children.reverse()
        let kind: Differentiability = switch try scanner.readScalar() {
        case "f": .forward
        case "r": .reverse
        case "d": .normal
        case "l": .linear
        default: throw failure
        }
        result.children.append(SwiftSymbol(kind: .index, contents: .index(UInt64(kind.rawValue.value))))
        try result.children.append(require(demangleIndexSubset()))
        try scanner.match(scalar: "p")
        try result.children.append(require(demangleIndexSubset()))
        try scanner.match(scalar: "r")
        if let optionalGenSig {
            result.children.append(optionalGenSig)
        }
        return result
    }

    mutating func demangleIndexSubset() throws -> SwiftSymbol {
        var str = ""
        while let c = scanner.conditional(where: { $0 == "S" || $0 == "U" }) {
            str.unicodeScalars.append(c)
        }
        try require(!str.isEmpty)
        return SwiftSymbol(kind: .indexSubset, contents: .name(str))
    }

    mutating func demangleDifferentiableFunctionType() throws -> SwiftSymbol {
        let kind: Differentiability = switch try scanner.readScalar() {
        case "f": .forward
        case "r": .reverse
        case "d": .normal
        case "l": .linear
        default: throw failure
        }
        return SwiftSymbol(kind: .differentiableFunctionType, contents: .index(UInt64(kind.rawValue.value)))
    }

    mutating func demangleBridgedMethodParams() throws -> String {
        if scanner.conditional(scalar: "_") {
            return ""
        }
        var str = ""
        let kind = try scanner.readScalar()
        switch kind {
        case "p",
             "a",
             "m": str.unicodeScalars.append(kind)
        default: return ""
        }
        while !scanner.conditional(scalar: "_") {
            let c = try scanner.readScalar()
            try require(c == "n" || c == "b" || c == "g")
            str.unicodeScalars.append(c)
        }
        return str
    }

    mutating func demangleGenericSpecialization(kind: SwiftSymbol.Kind, droppedArguments: SwiftSymbol? = nil) throws -> SwiftSymbol {
        var spec = try demangleSpecAttributes(kind: kind)
        if let droppedArguments {
            spec.children.append(contentsOf: droppedArguments.children)
        }
        let list = try popTypeList()
        for t in list.children {
            spec.children.append(SwiftSymbol(kind: .genericSpecializationParam, child: t))
        }
        return spec
    }

    mutating func demangleGenericSpecializationWithDroppedArguments() throws -> SwiftSymbol {
        try scanner.backtrack()
        var tmp = SwiftSymbol(kind: .genericSpecialization)
        while scanner.conditional(scalar: "t") {
            let n = try demangleNatural().map { SwiftSymbol.Contents.index($0 + 1) } ?? SwiftSymbol.Contents.index(0)
            tmp.children.append(SwiftSymbol(kind: .droppedArgument, contents: n))
        }
        let kind: SwiftSymbol.Kind = switch try scanner.readScalar() {
        case "g": .genericSpecialization
        case "G": .genericSpecializationNotReAbstracted
        case "B": .genericSpecializationInResilienceDomain
        default: throw failure
        }
        return try demangleGenericSpecialization(kind: kind, droppedArguments: tmp)
    }

    mutating func demangleFunctionSpecialization() throws -> SwiftSymbol {
        var spec = try demangleSpecAttributes(kind: .functionSignatureSpecialization, demangleUniqueId: true)
        var paramIdx: UInt64 = 0
        while !scanner.conditional(scalar: "_") {
            try spec.children.append(demangleFuncSpecParam(kind: .functionSignatureSpecializationParam))
            paramIdx += 1
        }
        if !scanner.conditional(scalar: "n") {
            try spec.children.append(demangleFuncSpecParam(kind: .functionSignatureSpecializationReturn))
        }

        for paramIndexPair in spec.children.enumerated().reversed() {
            var param = paramIndexPair.element
            guard param.kind == .functionSignatureSpecializationParam else { continue }
            guard let kindName = param.children.first else { continue }
            guard kindName.kind == .functionSignatureSpecializationParamKind, case let .index(i) = kindName.contents, let paramKind = FunctionSigSpecializationParamKind(rawValue: UInt64(i)) else { throw failure }
            switch paramKind {
            case .constantPropFunction,
                 .constantPropGlobal,
                 .constantPropString,
                 .constantPropKeyPath,
                 .closureProp:
                let fixedChildrenEndIndex = param.children.endIndex
                while let t = pop(kind: .type) {
                    try require(paramKind == .closureProp || paramKind == .constantPropKeyPath)
                    param.children.insert(t, at: fixedChildrenEndIndex)
                }
                let name = try require(pop(kind: .identifier))
                var text = try require(name.text)
                if paramKind == .constantPropString, !text.isEmpty, text.first == "_" {
                    text = String(text.dropFirst())
                }
                param.children.insert(SwiftSymbol(kind: .functionSignatureSpecializationParamPayload, contents: .name(text)), at: fixedChildrenEndIndex)
                spec.children[paramIndexPair.offset] = param
            default: break
            }
        }
        return spec
    }

    mutating func demangleFuncSpecParam(kind: SwiftSymbol.Kind) throws -> SwiftSymbol {
        var param = SwiftSymbol(kind: kind)
        switch try scanner.readScalar() {
        case "n": break
        case "c": param.children.append(SwiftSymbol(kind: .functionSignatureSpecializationParamKind, contents: .index(FunctionSigSpecializationParamKind.closureProp.rawValue)))
        case "p":
            switch try scanner.readScalar() {
            case "f": param.children.append(SwiftSymbol(kind: .functionSignatureSpecializationParamKind, contents: .index(FunctionSigSpecializationParamKind.constantPropFunction.rawValue)))
            case "g": param.children.append(SwiftSymbol(kind: .functionSignatureSpecializationParamKind, contents: .index(FunctionSigSpecializationParamKind.constantPropGlobal.rawValue)))
            case "i": param.children.append(SwiftSymbol(kind: .functionSignatureSpecializationParamKind, contents: .index(FunctionSigSpecializationParamKind.constantPropInteger.rawValue)))
            case "d": param.children.append(SwiftSymbol(kind: .functionSignatureSpecializationParamKind, contents: .index(FunctionSigSpecializationParamKind.constantPropFloat.rawValue)))
            case "s":
                let encoding: String
                switch try scanner.readScalar() {
                case "b": encoding = "u8"
                case "w": encoding = "u16"
                case "c": encoding = "objc"
                default: throw failure
                }
                param.children.append(SwiftSymbol(kind: .functionSignatureSpecializationParamKind, contents: .index(FunctionSigSpecializationParamKind.constantPropString.rawValue)))
                param.children.append(SwiftSymbol(kind: .functionSignatureSpecializationParamPayload, contents: .name(encoding)))
            case "k":
                param.children.append(SwiftSymbol(kind: .functionSignatureSpecializationParamKind, contents: .index(FunctionSigSpecializationParamKind.constantPropKeyPath.rawValue)))
            default: throw failure
            }
        case "e":
            var value = FunctionSigSpecializationParamKind.existentialToGeneric.rawValue
            if scanner.conditional(scalar: "D") {
                value |= FunctionSigSpecializationParamKind.dead.rawValue
            }
            if scanner.conditional(scalar: "G") {
                value |= FunctionSigSpecializationParamKind.ownedToGuaranteed.rawValue
            }
            if scanner.conditional(scalar: "O") {
                value |= FunctionSigSpecializationParamKind.guaranteedToOwned.rawValue
            }
            if scanner.conditional(scalar: "X") {
                value |= FunctionSigSpecializationParamKind.sroa.rawValue
            }
            param.children.append(SwiftSymbol(kind: .functionSignatureSpecializationParamKind, contents: .index(value)))
        case "d":
            var value = FunctionSigSpecializationParamKind.dead.rawValue
            if scanner.conditional(scalar: "G") {
                value |= FunctionSigSpecializationParamKind.ownedToGuaranteed.rawValue
            }
            if scanner.conditional(scalar: "O") {
                value |= FunctionSigSpecializationParamKind.guaranteedToOwned.rawValue
            }
            if scanner.conditional(scalar: "X") {
                value |= FunctionSigSpecializationParamKind.sroa.rawValue
            }
            param.children.append(SwiftSymbol(kind: .functionSignatureSpecializationParamKind, contents: .index(value)))
        case "g":
            var value = FunctionSigSpecializationParamKind.ownedToGuaranteed.rawValue
            if scanner.conditional(scalar: "O") {
                value |= FunctionSigSpecializationParamKind.guaranteedToOwned.rawValue
            }
            if scanner.conditional(scalar: "X") {
                value |= FunctionSigSpecializationParamKind.sroa.rawValue
            }
            param.children.append(SwiftSymbol(kind: .functionSignatureSpecializationParamKind, contents: .index(value)))
        case "o":
            var value = FunctionSigSpecializationParamKind.guaranteedToOwned.rawValue
            if scanner.conditional(scalar: "X") {
                value |= FunctionSigSpecializationParamKind.sroa.rawValue
            }
            param.children.append(SwiftSymbol(kind: .functionSignatureSpecializationParamKind, contents: .index(value)))
        case "x":
            param.children.append(SwiftSymbol(kind: .functionSignatureSpecializationParamKind, contents: .index(FunctionSigSpecializationParamKind.sroa.rawValue)))
        case "i":
            param.children.append(SwiftSymbol(kind: .functionSignatureSpecializationParamKind, contents: .index(FunctionSigSpecializationParamKind.boxToValue.rawValue)))
        case "s":
            param.children.append(SwiftSymbol(kind: .functionSignatureSpecializationParamKind, contents: .index(FunctionSigSpecializationParamKind.boxToStack.rawValue)))
        case "r":
            param.children.append(SwiftSymbol(kind: .functionSignatureSpecializationParamKind, contents: .index(FunctionSigSpecializationParamKind.inOutToOut.rawValue)))
        default: throw failure
        }
        return param
    }

    mutating func addFuncSpecParamNumber(param: inout SwiftSymbol, kind: FunctionSigSpecializationParamKind) throws {
        param.children.append(SwiftSymbol(kind: .functionSignatureSpecializationParamKind, contents: .index(kind.rawValue)))
        let str = scanner.readWhile { $0.isDigit }
        try require(!str.isEmpty)
        param.children.append(SwiftSymbol(kind: .functionSignatureSpecializationParamPayload, contents: .name(str)))
    }

    mutating func demangleSpecAttributes(kind: SwiftSymbol.Kind, demangleUniqueId: Bool = false) throws -> SwiftSymbol {
        let isSerialized = scanner.conditional(scalar: "q")
        let asyncRemoved = scanner.conditional(scalar: "a")
        let passId = try scanner.readScalar().value - UnicodeScalar("0").value
        try require((0 ... 9).contains(passId))
        let contents = try demangleUniqueId ? (demangleNatural().map { SwiftSymbol.Contents.index($0) } ?? SwiftSymbol.Contents.none) : SwiftSymbol.Contents.none
        var specName = SwiftSymbol(kind: kind, contents: contents)
        if isSerialized {
            specName.children.append(SwiftSymbol(kind: .isSerialized))
        }
        if asyncRemoved {
            specName.children.append(SwiftSymbol(kind: .asyncRemoved))
        }
        specName.children.append(SwiftSymbol(kind: .specializationPassID, contents: .index(UInt64(passId))))
        return specName
    }

    mutating func demangleWitness() throws -> SwiftSymbol {
        let c = try scanner.readScalar()
        switch c {
        case "C": return try SwiftSymbol(kind: .enumCase, child: require(pop(where: { $0.isEntity })))
        case "V": return try SwiftSymbol(kind: .valueWitnessTable, child: require(pop(kind: .type)))
        case "v":
            let directness: UInt64
            switch try scanner.readScalar() {
            case "d": directness = Directness.direct.rawValue
            case "i": directness = Directness.indirect.rawValue
            default: throw failure
            }
            return try SwiftSymbol(kind: .fieldOffset, children: [SwiftSymbol(kind: .directness, contents: .index(directness)), require(pop(where: { $0.isEntity }))])
        case "S": return try SwiftSymbol(kind: .protocolSelfConformanceWitnessTable, child: popProtocolConformance())
        case "P": return try SwiftSymbol(kind: .protocolWitnessTable, child: popProtocolConformance())
        case "p": return try SwiftSymbol(kind: .protocolWitnessTablePattern, child: popProtocolConformance())
        case "G": return try SwiftSymbol(kind: .genericProtocolWitnessTable, child: popProtocolConformance())
        case "I": return try SwiftSymbol(kind: .genericProtocolWitnessTableInstantiationFunction, child: popProtocolConformance())
        case "r": return try SwiftSymbol(kind: .resilientProtocolWitnessTable, child: popProtocolConformance())
        case "l":
            let conf = try popProtocolConformance()
            let type = try require(pop(kind: .type))
            return SwiftSymbol(kind: .lazyProtocolWitnessTableAccessor, children: [type, conf])
        case "L":
            let conf = try popProtocolConformance()
            let type = try require(pop(kind: .type))
            return SwiftSymbol(kind: .lazyProtocolWitnessTableCacheVariable, children: [type, conf])
        case "a": return try SwiftSymbol(kind: .protocolWitnessTableAccessor, child: popProtocolConformance())
        case "t":
            let name = try require(pop(where: { $0.isDeclName }))
            let conf = try popProtocolConformance()
            return SwiftSymbol(kind: .associatedTypeMetadataAccessor, children: [conf, name])
        case "T":
            let protoType = try require(pop(kind: .type))
            var assocTypePath = SwiftSymbol(kind: .assocTypePath)
            var firstElem = false
            repeat {
                firstElem = pop(kind: .firstElementMarker) != nil
                let assocType = try require(pop(where: { $0.isDeclName }))
                assocTypePath.children.insert(assocType, at: 0)
            } while !firstElem
            return try SwiftSymbol(kind: .associatedTypeWitnessTableAccessor, children: [popProtocolConformance(), assocTypePath, protoType])
        case "b":
            let protoTy = try require(pop(kind: .type))
            let conf = try popProtocolConformance()
            return SwiftSymbol(kind: .baseWitnessTableAccessor, children: [conf, protoTy])
        case "O":
            let sig = pop(kind: .dependentGenericSignature)
            let type = try require(pop(kind: .type))
            let children: [SwiftSymbol] = sig.map { [type, $0] } ?? [type]
            switch try scanner.readScalar() {
            case "C": return SwiftSymbol(kind: .outlinedInitializeWithCopyNoValueWitness, children: children)
            case "D": return SwiftSymbol(kind: .outlinedAssignWithTakeNoValueWitness, children: children)
            case "F": return SwiftSymbol(kind: .outlinedAssignWithCopyNoValueWitness, children: children)
            case "H": return SwiftSymbol(kind: .outlinedDestroyNoValueWitness, children: children)
            case "y": return SwiftSymbol(kind: .outlinedCopy, children: children)
            case "e": return SwiftSymbol(kind: .outlinedConsume, children: children)
            case "r": return SwiftSymbol(kind: .outlinedRetain, children: children)
            case "s": return SwiftSymbol(kind: .outlinedRelease, children: children)
            case "b": return SwiftSymbol(kind: .outlinedInitializeWithTake, children: children)
            case "c": return SwiftSymbol(kind: .outlinedInitializeWithCopy, children: children)
            case "d": return SwiftSymbol(kind: .outlinedAssignWithTake, children: children)
            case "f": return SwiftSymbol(kind: .outlinedAssignWithCopy, children: children)
            case "h": return SwiftSymbol(kind: .outlinedDestroy, children: children)
            case "g": return SwiftSymbol(kind: .outlinedEnumGetTag, children: children)
            case "i": return SwiftSymbol(kind: .outlinedEnumTagStore, children: children)
            case "j": return SwiftSymbol(kind: .outlinedEnumProjectDataForLoad, children: children)
            default: throw failure
            }
        case "Z",
             "z":
            var declList = SwiftSymbol(kind: .globalVariableOnceDeclList)
            while pop(kind: .firstElementMarker) != nil {
                guard let identifier = pop(where: { $0.isDeclName }) else { throw failure }
                declList.children.append(identifier)
            }
            declList.children.reverse()
            return try SwiftSymbol(kind: c == "Z" ? .globalVariableOnceFunction : .globalVariableOnceToken, children: [popContext(), declList])
        case "J":
            return try demangleDifferentiabilityWitness()
        default: throw failure
        }
    }

    mutating func demangleSpecialType() throws -> SwiftSymbol {
        let specialChar = try scanner.readScalar()
        switch specialChar {
        case "E": return try popFunctionType(kind: .noEscapeFunctionType)
        case "A": return try popFunctionType(kind: .escapingAutoClosureType)
        case "f": return try popFunctionType(kind: .thinFunctionType)
        case "K": return try popFunctionType(kind: .autoClosureType)
        case "U": return try popFunctionType(kind: .uncurriedFunctionType)
        case "L": return try popFunctionType(kind: .escapingObjCBlock)
        case "B": return try popFunctionType(kind: .objCBlock)
        case "C": return try popFunctionType(kind: .cFunctionPointer)
        case "g": fallthrough
        case "G": return try demangleExtendedExistentialShape(nodeKind: specialChar)
        case "j": return try demangleSymbolicExtendedExistentialType()
        case "z":
            switch try scanner.readScalar() {
            case "B": return try popFunctionType(kind: .objCBlock, hasClangType: true)
            case "C": return try popFunctionType(kind: .cFunctionPointer, hasClangType: true)
            default: throw failure
            }
        case "o": return try SwiftSymbol(typeWithChildKind: .unowned, childChild: require(pop(kind: .type)))
        case "u": return try SwiftSymbol(typeWithChildKind: .unmanaged, childChild: require(pop(kind: .type)))
        case "w": return try SwiftSymbol(typeWithChildKind: .weak, childChild: require(pop(kind: .type)))
        case "b": return try SwiftSymbol(typeWithChildKind: .silBoxType, childChild: require(pop(kind: .type)))
        case "D": return try SwiftSymbol(typeWithChildKind: .dynamicSelf, childChild: require(pop(kind: .type)))
        case "M":
            let mtr = try demangleMetatypeRepresentation()
            let type = try require(pop(kind: .type))
            return SwiftSymbol(typeWithChildKind: .metatype, childChildren: [mtr, type])
        case "m":
            let mtr = try demangleMetatypeRepresentation()
            let type = try require(pop(kind: .type))
            return SwiftSymbol(typeWithChildKind: .existentialMetatype, childChildren: [mtr, type])
        case "P":
            let reqs = try demangleConstrainedExistentialRequirementList()
            let base = try require(pop(kind: .type))
            return SwiftSymbol(typeWithChildKind: .constrainedExistential, childChildren: [base, reqs])
        case "p": return try SwiftSymbol(typeWithChildKind: .existentialMetatype, childChild: require(pop(kind: .type)))
        case "c":
            let superclass = try require(pop(kind: .type))
            let protocols = try demangleProtocolList()
            return SwiftSymbol(typeWithChildKind: .protocolListWithClass, childChildren: [protocols, superclass])
        case "l": return try SwiftSymbol(typeWithChildKind: .protocolListWithAnyObject, childChild: demangleProtocolList())
        case "X",
             "x":
            var signatureGenericArgs: (SwiftSymbol, SwiftSymbol)? = nil
            if specialChar == "X" {
                signatureGenericArgs = try (require(pop(kind: .dependentGenericSignature)), popTypeList())
            }

            let fieldTypes = try popTypeList()
            var layout = SwiftSymbol(kind: .silBoxLayout)
            for fieldType in fieldTypes.children {
                try require(fieldType.kind == .type)
                if fieldType.children.first?.kind == .inOut {
                    try layout.children.append(SwiftSymbol(kind: .silBoxMutableField, child: SwiftSymbol(kind: .type, child: require(fieldType.children.first?.children.first))))
                } else {
                    layout.children.append(SwiftSymbol(kind: .silBoxImmutableField, child: fieldType))
                }
            }
            var boxType = SwiftSymbol(kind: .silBoxTypeWithLayout, child: layout)
            if let (signature, genericArgs) = signatureGenericArgs {
                boxType.children.append(signature)
                boxType.children.append(genericArgs)
            }
            return SwiftSymbol(kind: .type, child: boxType)
        case "Y": return try demangleAnyGenericType(kind: .otherNominalType)
        case "Z":
            let types = try popTypeList()
            let name = try require(pop(kind: .identifier))
            let parent = try popContext()
            return SwiftSymbol(kind: .anonymousContext, children: [name, parent, types])
        case "e": return SwiftSymbol(kind: .type, child: SwiftSymbol(kind: .errorType))
        case "S":
            switch try scanner.readScalar() {
            case "q": return SwiftSymbol(kind: .type, child: SwiftSymbol(kind: .sugaredOptional))
            case "a": return SwiftSymbol(kind: .type, child: SwiftSymbol(kind: .sugaredArray))
            case "D": return SwiftSymbol(kind: .type, child: SwiftSymbol(kind: .sugaredDictionary))
            case "p": return SwiftSymbol(kind: .type, child: SwiftSymbol(kind: .sugaredParen))
            default: throw failure
            }
        default: throw failure
        }
    }

    mutating func demangleSymbolicExtendedExistentialType() throws -> SwiftSymbol {
        let retroactiveConformances = try popRetroactiveConformances()
        var args = SwiftSymbol(kind: .typeList)
        while let type = pop(kind: .type) {
            args.children.append(type)
        }
        args.children.reverse()
        let shape = try require(pop(where: { $0 == .uniqueExtendedExistentialTypeShapeSymbolicReference || $0 == .nonUniqueExtendedExistentialTypeShapeSymbolicReference }))
        if let retroactiveConformances {
            return SwiftSymbol(typeWithChildKind: .symbolicExtendedExistentialType, childChildren: [shape, args, retroactiveConformances])
        } else {
            return SwiftSymbol(typeWithChildKind: .symbolicExtendedExistentialType, childChildren: [shape, args])
        }
    }

    mutating func demangleExtendedExistentialShape(nodeKind: UnicodeScalar) throws -> SwiftSymbol {
        let type = try require(pop(kind: .type))
        var genSig: SwiftSymbol?
        if nodeKind == "G" {
            genSig = pop(kind: .dependentGenericSignature)
        }
        if let genSig {
            return SwiftSymbol(kind: .extendedExistentialTypeShape, children: [genSig, type])
        } else {
            return SwiftSymbol(kind: .extendedExistentialTypeShape, child: type)
        }
    }

    mutating func demangleMetatypeRepresentation() throws -> SwiftSymbol {
        let value: String
        switch try scanner.readScalar() {
        case "t": value = "@thin"
        case "T": value = "@thick"
        case "o": value = "@objc_metatype"
        default: throw failure
        }
        return SwiftSymbol(kind: .metatypeRepresentation, contents: .name(value))
    }

    mutating func demangleAccessor(child: SwiftSymbol) throws -> SwiftSymbol {
        let kind: SwiftSymbol.Kind
        switch try scanner.readScalar() {
        case "m": kind = .materializeForSet
        case "s": kind = .setter
        case "g": kind = .getter
        case "G": kind = .globalGetter
        case "w": kind = .willSet
        case "W": kind = .didSet
        case "r": kind = .readAccessor
        case "y": kind = .read2Accessor
        case "M": kind = .modifyAccessor
        case "x": kind = .modify2Accessor
        case "i": kind = .initAccessor
        case "a":
            switch try scanner.readScalar() {
            case "O": kind = .owningMutableAddressor
            case "o": kind = .nativeOwningMutableAddressor
            case "p": kind = .nativePinningMutableAddressor
            case "u": kind = .unsafeMutableAddressor
            default: throw failure
            }
        case "l":
            switch try scanner.readScalar() {
            case "O": kind = .owningAddressor
            case "o": kind = .nativeOwningAddressor
            case "p": kind = .nativePinningAddressor
            case "u": kind = .unsafeAddressor
            default: throw failure
            }
        case "p": return child
        default: throw failure
        }
        return SwiftSymbol(kind: kind, child: child)
    }

    mutating func demangleFunctionEntity() throws -> SwiftSymbol {
        let argsAndKind: (args: DemangleFunctionEntityArgs, kind: SwiftSymbol.Kind)
        switch try scanner.readScalar() {
        case "D": argsAndKind = (.none, .deallocator)
        case "d": argsAndKind = (.none, .destructor)
        case "Z": argsAndKind = (.none, .isolatedDeallocator)
        case "E": argsAndKind = (.none, .iVarDestroyer)
        case "e": argsAndKind = (.none, .iVarInitializer)
        case "i": argsAndKind = (.none, .initializer)
        case "C": argsAndKind = (.typeAndMaybePrivateName, .allocator)
        case "c": argsAndKind = (.typeAndMaybePrivateName, .constructor)
        case "U": argsAndKind = (.typeAndIndex, .explicitClosure)
        case "u": argsAndKind = (.typeAndIndex, .implicitClosure)
        case "A": argsAndKind = (.index, .defaultArgumentInitializer)
        case "m": return try demangleEntity(kind: .macro)
        case "M": return try demangleMacroExpansion()
        case "p": return try demangleEntity(kind: .genericTypeParamDecl)
        case "P": argsAndKind = (.none, .propertyWrapperBackingInitializer)
        case "W": argsAndKind = (.none, .propertyWrapperInitFromProjectedValue)
        default: throw failure
        }

        var children = [SwiftSymbol]()
        switch argsAndKind.args {
        case .none: break
        case .index: try children.append(demangleIndexAsName())
        case .typeAndIndex:
            let index = try demangleIndexAsName()
            let type = try require(pop(kind: .type))
            children += [index, type]
        case .typeAndMaybePrivateName:
            let privateName = pop(kind: .privateDeclName)
            let paramType = try require(pop(kind: .type))
            let labelList = try popFunctionParamLabels(type: paramType)
            if let ll = labelList {
                children.append(ll)
                children.append(paramType)
            } else {
                children.append(paramType)
            }
            if let pn = privateName {
                children.append(pn)
            }
        }
        return try SwiftSymbol(kind: argsAndKind.kind, children: [popContext()] + children)
    }

    mutating func demangleEntity(kind: SwiftSymbol.Kind) throws -> SwiftSymbol {
        var type = try require(pop(kind: .type))
        let labelList = try popFunctionParamLabels(type: type)
        let name = try require(pop(where: { $0.isDeclName }))
        let context = try popContext()
        let result = if let labelList = labelList {
            SwiftSymbol(kind: kind, children: [context, name, labelList, type])
        } else {
            SwiftSymbol(kind: kind, children: [context, name, type])
        }
        setParentForOpaqueReturnTypeNodes(visited: &type, parentId: getParentId(parent: result, flavor: flavor))
        return result
    }

    mutating func demangleVariable() throws -> SwiftSymbol {
        return try demangleAccessor(child: demangleEntity(kind: .variable))
    }

    mutating func demangleSubscript() throws -> SwiftSymbol {
        let privateName = pop(kind: .privateDeclName)
        var type = try require(pop(kind: .type))
        let labelList = try popFunctionParamLabels(type: type)
        let context = try popContext()

        var ss = SwiftSymbol(kind: .subscript, child: context)
        if let labelList = labelList {
            ss.children.append(labelList)
        }
        setParentForOpaqueReturnTypeNodes(visited: &type, parentId: getParentId(parent: ss, flavor: flavor))
        ss.children.append(type)
        if let pn = privateName {
            ss.children.append(pn)
        }
        return try demangleAccessor(child: ss)
    }

    mutating func demangleProtocolList() throws -> SwiftSymbol {
        var typeList = SwiftSymbol(kind: .typeList)
        if pop(kind: .emptyList) == nil {
            var firstElem = false
            repeat {
                firstElem = pop(kind: .firstElementMarker) != nil
                try typeList.children.insert(popProtocol(), at: 0)
            } while !firstElem
        }
        return SwiftSymbol(kind: .protocolList, child: typeList)
    }

    mutating func demangleProtocolListType() throws -> SwiftSymbol {
        return try SwiftSymbol(kind: .type, child: demangleProtocolList())
    }

    mutating func demangleConstrainedExistentialRequirementList() throws -> SwiftSymbol {
        var reqList = SwiftSymbol(kind: .constrainedExistentialRequirementList)
        var firstElement = false
        repeat {
            firstElement = (pop(kind: .firstElementMarker) != nil)
            let req = try require(pop(where: { $0.isRequirement }))
            reqList.children.append(req)
        } while !firstElement
        reqList.children.reverse()
        return reqList
    }

    mutating func demangleGenericSignature(hasParamCounts: Bool) throws -> SwiftSymbol {
        var sig = SwiftSymbol(kind: .dependentGenericSignature)
        if hasParamCounts {
            while !scanner.conditional(scalar: "l") {
                var count: UInt64 = 0
                if !scanner.conditional(scalar: "z") {
                    count = try demangleIndex() + 1
                }
                sig.children.append(SwiftSymbol(kind: .dependentGenericParamCount, contents: .index(count)))
            }
        } else {
            sig.children.append(SwiftSymbol(kind: .dependentGenericParamCount, contents: .index(1)))
        }
        let requirementsIndex = sig.children.endIndex
        while let req = pop(where: { $0.isRequirement }) {
            sig.children.insert(req, at: requirementsIndex)
        }
        return sig
    }

    mutating func demangleGenericRequirement() throws -> SwiftSymbol {
        let constraintAndTypeKinds: (constraint: DemangleGenericRequirementConstraintKind, type: DemangleGenericRequirementTypeKind)
        var inverseKind: SwiftSymbol?
        switch try scanner.readScalar() {
        case "V": constraintAndTypeKinds = (.valueMarker, .generic)
        case "v": constraintAndTypeKinds = (.packMarker, .generic)
        case "c": constraintAndTypeKinds = (.baseClass, .assoc)
        case "C": constraintAndTypeKinds = (.baseClass, .compoundAssoc)
        case "b": constraintAndTypeKinds = (.baseClass, .generic)
        case "B": constraintAndTypeKinds = (.baseClass, .substitution)
        case "t": constraintAndTypeKinds = (.sameType, .assoc)
        case "T": constraintAndTypeKinds = (.sameType, .compoundAssoc)
        case "s": constraintAndTypeKinds = (.sameType, .generic)
        case "S": constraintAndTypeKinds = (.sameType, .substitution)
        case "m": constraintAndTypeKinds = (.layout, .assoc)
        case "M": constraintAndTypeKinds = (.layout, .compoundAssoc)
        case "l": constraintAndTypeKinds = (.layout, .generic)
        case "L": constraintAndTypeKinds = (.layout, .substitution)
        case "p": constraintAndTypeKinds = (.protocol, .assoc)
        case "P": constraintAndTypeKinds = (.protocol, .compoundAssoc)
        case "Q": constraintAndTypeKinds = (.protocol, .substitution)
        case "h": constraintAndTypeKinds = (.sameShape, .generic)
        case "i":
            constraintAndTypeKinds = (.inverse, .generic)
            inverseKind = try demangleIndexAsName()
        case "I":
            constraintAndTypeKinds = (.inverse, .substitution)
            inverseKind = try demangleIndexAsName()
        default:
            constraintAndTypeKinds = (.protocol, .generic)
            try scanner.backtrack()
        }

        let constrType: SwiftSymbol
        switch constraintAndTypeKinds.type {
        case .generic: constrType = try SwiftSymbol(kind: .type, child: demangleGenericParamIndex())
        case .assoc:
            constrType = try demangleAssociatedTypeSimple(index: demangleGenericParamIndex())
            substitutions.append(constrType)
        case .compoundAssoc:
            constrType = try demangleAssociatedTypeCompound(index: demangleGenericParamIndex())
            substitutions.append(constrType)
        case .substitution: constrType = try require(pop(kind: .type))
        }

        switch constraintAndTypeKinds.constraint {
        case .valueMarker: return try SwiftSymbol(kind: .dependentGenericParamPackMarker, children: [constrType, require(pop(kind: .type))])
        case .packMarker: return SwiftSymbol(kind: .dependentGenericParamPackMarker, children: [constrType])
        case .protocol: return try SwiftSymbol(kind: .dependentGenericConformanceRequirement, children: [constrType, popProtocol()])
        case .inverse: return try SwiftSymbol(kind: .dependentGenericInverseConformanceRequirement, children: [constrType, require(inverseKind)])
        case .baseClass: return try SwiftSymbol(kind: .dependentGenericConformanceRequirement, children: [constrType, require(pop(kind: .type))])
        case .sameType: return try SwiftSymbol(kind: .dependentGenericSameTypeRequirement, children: [constrType, require(pop(kind: .type))])
        case .sameShape: return try SwiftSymbol(kind: .dependentGenericSameShapeRequirement, children: [constrType, require(pop(kind: .type))])
        case .layout:
            let c = try scanner.readScalar()
            var size: SwiftSymbol? = nil
            var alignment: SwiftSymbol? = nil
            switch c {
            case "U",
                 "R",
                 "N",
                 "C",
                 "D",
                 "T": break
            case "E",
                 "M":
                size = try demangleIndexAsName()
                alignment = try demangleIndexAsName()
            case "e",
                 "m":
                size = try demangleIndexAsName()
            default: throw failure
            }
            let name = SwiftSymbol(kind: .identifier, contents: .name(String(String.UnicodeScalarView([c]))))
            var layoutRequirement = SwiftSymbol(kind: .dependentGenericLayoutRequirement, children: [constrType, name])
            if let s = size {
                layoutRequirement.children.append(s)
            }
            if let a = alignment {
                layoutRequirement.children.append(a)
            }
            return layoutRequirement
        }
    }

    mutating func demangleGenericType() throws -> SwiftSymbol {
        let genSig = try require(pop(kind: .dependentGenericSignature))
        let type = try require(pop(kind: .type))
        return SwiftSymbol(typeWithChildKind: .dependentGenericType, childChildren: [genSig, type])
    }

    mutating func demangleValueWitness() throws -> SwiftSymbol {
        let code = try scanner.readScalars(count: 2)
        let kind = try require(ValueWitnessKind(code: code))
        return try SwiftSymbol(kind: .valueWitness, children: [require(pop(kind: .type))], contents: .index(kind.rawValue))
    }
}

extension Demangler {
    mutating func demangleMacroExpansion() throws -> SwiftSymbol {
        let kind: SwiftSymbol.Kind
        let isAttached: Bool
        let isFreestanding: Bool
        switch try scanner.readScalar() {
        case "a": (kind, isAttached, isFreestanding) = (.accessorAttachedMacroExpansion, true, false)
        case "r": (kind, isAttached, isFreestanding) = (.memberAttributeAttachedMacroExpansion, true, false)
        case "m": (kind, isAttached, isFreestanding) = (.memberAttachedMacroExpansion, true, false)
        case "p": (kind, isAttached, isFreestanding) = (.peerAttachedMacroExpansion, true, false)
        case "c": (kind, isAttached, isFreestanding) = (.conformanceAttachedMacroExpansion, true, false)
        case "b": (kind, isAttached, isFreestanding) = (.bodyAttachedMacroExpansion, true, false)
        case "f": (kind, isAttached, isFreestanding) = (.freestandingMacroExpansion, false, true)
        case "u": (kind, isAttached, isFreestanding) = (.macroExpansionUniqueName, false, false)
        case "X":
            let line = try demangleIndex()
            let col = try demangleIndex()
            let lineNode = SwiftSymbol(kind: .index, contents: .index(line))
            let colNode = SwiftSymbol(kind: .index, contents: .index(col))
            let buffer = try require(pop(kind: .identifier))
            let module = try require(pop(kind: .identifier))
            return SwiftSymbol(kind: .macroExpansionLoc, children: [module, buffer, lineNode, colNode])
        default:
            throw failure
        }

        let macroName = try require(pop(kind: .identifier))
        let privateDiscriminator = isFreestanding ? pop(kind: .privateDeclName) : nil
        let attachedName = isAttached ? pop(where: { $0.isDeclName }) : nil
        let context = try pop(where: { $0.isMacroExpansion }) ?? popContext()
        let discriminator = try demangleIndexAsName()
        var result: SwiftSymbol
        if isAttached {
            result = try SwiftSymbol(kind: kind, children: [context, require(attachedName), macroName, discriminator])
        } else {
            result = SwiftSymbol(kind: kind, children: [context, macroName, discriminator])
        }
        if let privateDiscriminator {
            result.children.append(privateDiscriminator)
        }
        return result
    }

    mutating func demangleIntegerType() throws -> SwiftSymbol {
        if scanner.conditional(scalar: "n") {
            return try SwiftSymbol(kind: .type, children: [SwiftSymbol(kind: .negativeInteger, contents: .index(demangleIndex()))])
        } else {
            return try SwiftSymbol(kind: .type, children: [SwiftSymbol(kind: .integer, contents: .index(demangleIndex()))])
        }
    }

    mutating func demangleObjCTypeName() throws -> SwiftSymbol {
        var type = SwiftSymbol(kind: .type)
        if scanner.conditional(scalar: "C") {
            let module: SwiftSymbol
            if scanner.conditional(scalar: "s") {
                module = SwiftSymbol(kind: .module, contents: .name(stdlibName))
            } else {
                module = try demangleIdentifier().changeKind(.module)
            }
            try type.children.append(SwiftSymbol(kind: .class, children: [module, demangleIdentifier()]))
        } else if scanner.conditional(scalar: "P") {
            let module: SwiftSymbol
            if scanner.conditional(scalar: "s") {
                module = SwiftSymbol(kind: .module, contents: .name(stdlibName))
            } else {
                module = try demangleIdentifier().changeKind(.module)
            }
            try type.children.append(SwiftSymbol(kind: .protocolList, child: SwiftSymbol(kind: .typeList, child: SwiftSymbol(kind: .type, child: SwiftSymbol(kind: .protocol, children: [module, demangleIdentifier()])))))
            try scanner.match(scalar: "_")
        } else {
            throw failure
        }
        try require(scanner.isAtEnd)
        return SwiftSymbol(kind: .global, child: SwiftSymbol(kind: .typeMangling, child: type))
    }
}

// MARK Demangle.cpp (Swift 3)

extension Demangler {
    mutating func demangleSwift3TopLevelSymbol() throws -> SwiftSymbol {
        reset()

        try scanner.match(string: "_T")
        var children = [SwiftSymbol]()

        switch try (scanner.readScalar(), scanner.readScalar()) {
        case ("T", "S"):
            repeat {
                try children.append(demangleSwift3SpecializedAttribute())
                nameStack.removeAll()
            } while scanner.conditional(string: "_TTS")
            try scanner.match(string: "_T")
        case ("T", "o"): children.append(SwiftSymbol(kind: .objCAttribute))
        case ("T", "O"): children.append(SwiftSymbol(kind: .nonObjCAttribute))
        case ("T", "D"): children.append(SwiftSymbol(kind: .dynamicAttribute))
        case ("T", "d"): children.append(SwiftSymbol(kind: .directMethodReferenceAttribute))
        case ("T", "v"): children.append(SwiftSymbol(kind: .vTableAttribute))
        default: try scanner.backtrack(count: 2)
        }

        try children.append(demangleSwift3Global())

        let remainder = scanner.remainder()
        if !remainder.isEmpty {
            children.append(SwiftSymbol(kind: .suffix, contents: .name(remainder)))
        }

        return SwiftSymbol(kind: .global, children: children)
    }

    mutating func demangleSwift3Global() throws -> SwiftSymbol {
        let c1 = try scanner.readScalar()
        let c2 = try scanner.readScalar()
        switch (c1, c2) {
        case ("M", "P"): return try SwiftSymbol(kind: .genericTypeMetadataPattern, children: [demangleSwift3Type()])
        case ("M", "a"): return try SwiftSymbol(kind: .typeMetadataAccessFunction, children: [demangleSwift3Type()])
        case ("M", "L"): return try SwiftSymbol(kind: .typeMetadataLazyCache, children: [demangleSwift3Type()])
        case ("M", "m"): return try SwiftSymbol(kind: .metaclass, children: [demangleSwift3Type()])
        case ("M", "n"): return try SwiftSymbol(kind: .nominalTypeDescriptor, children: [demangleSwift3Type()])
        case ("M", "f"): return try SwiftSymbol(kind: .fullTypeMetadata, children: [demangleSwift3Type()])
        case ("M", "p"): return try SwiftSymbol(kind: .protocolDescriptor, children: [demangleSwift3ProtocolName()])
        case ("M", _):
            try scanner.backtrack()
            return try SwiftSymbol(kind: .typeMetadata, children: [demangleSwift3Type()])
        case ("P", "A"):
            return try SwiftSymbol(kind: scanner.conditional(scalar: "o") ? .partialApplyObjCForwarder : .partialApplyForwarder, children: scanner.conditional(string: "__T") ? [demangleSwift3Global()] : [])
        case ("P", _): throw scanner.unexpectedError()
        case ("t", _):
            try scanner.backtrack()
            return try SwiftSymbol(kind: .typeMangling, children: [demangleSwift3Type()])
        case ("w", _):
            let c3 = try scanner.readScalar()
            let value: UInt64
            switch (c2, c3) {
            case ("a", "l"): value = ValueWitnessKind.allocateBuffer.rawValue
            case ("c", "a"): value = ValueWitnessKind.assignWithCopy.rawValue
            case ("t", "a"): value = ValueWitnessKind.assignWithTake.rawValue
            case ("d", "e"): value = ValueWitnessKind.deallocateBuffer.rawValue
            case ("x", "x"): value = ValueWitnessKind.destroy.rawValue
            case ("X", "X"): value = ValueWitnessKind.destroyBuffer.rawValue
            case ("C", "P"): value = ValueWitnessKind.initializeBufferWithCopyOfBuffer.rawValue
            case ("C", "p"): value = ValueWitnessKind.initializeBufferWithCopy.rawValue
            case ("c", "p"): value = ValueWitnessKind.initializeWithCopy.rawValue
            case ("C", "c"): value = ValueWitnessKind.initializeArrayWithCopy.rawValue
            case ("T", "K"): value = ValueWitnessKind.initializeBufferWithTakeOfBuffer.rawValue
            case ("T", "k"): value = ValueWitnessKind.initializeBufferWithTake.rawValue
            case ("t", "k"): value = ValueWitnessKind.initializeWithTake.rawValue
            case ("T", "t"): value = ValueWitnessKind.initializeArrayWithTakeFrontToBack.rawValue
            case ("t", "T"): value = ValueWitnessKind.initializeArrayWithTakeBackToFront.rawValue
            case ("p", "r"): value = ValueWitnessKind.projectBuffer.rawValue
            case ("X", "x"): value = ValueWitnessKind.destroyArray.rawValue
            case ("x", "s"): value = ValueWitnessKind.storeExtraInhabitant.rawValue
            case ("x", "g"): value = ValueWitnessKind.getExtraInhabitantIndex.rawValue
            case ("u", "g"): value = ValueWitnessKind.getEnumTag.rawValue
            case ("u", "p"): value = ValueWitnessKind.destructiveProjectEnumData.rawValue
            default: throw scanner.unexpectedError()
            }
            return try SwiftSymbol(kind: .valueWitness, children: [demangleSwift3Type()], contents: .index(value))
        case ("W", "V"): return try SwiftSymbol(kind: .valueWitnessTable, children: [demangleSwift3Type()])
        case ("W", "v"): return try SwiftSymbol(kind: .fieldOffset, children: [SwiftSymbol(kind: .directness, contents: .index(scanner.readScalar() == "d" ? 0 : 1)), demangleSwift3Entity()])
        case ("W", "P"): return try SwiftSymbol(kind: .protocolWitnessTable, children: [demangleSwift3ProtocolConformance()])
        case ("W", "G"): return try SwiftSymbol(kind: .genericProtocolWitnessTable, children: [demangleSwift3ProtocolConformance()])
        case ("W", "I"): return try SwiftSymbol(kind: .genericProtocolWitnessTableInstantiationFunction, children: [demangleSwift3ProtocolConformance()])
        case ("W", "l"): return try SwiftSymbol(kind: .lazyProtocolWitnessTableAccessor, children: [demangleSwift3Type(), demangleSwift3ProtocolConformance()])
        case ("W", "L"): return try SwiftSymbol(kind: .lazyProtocolWitnessTableCacheVariable, children: [demangleSwift3Type(), demangleSwift3ProtocolConformance()])
        case ("W", "a"): return try SwiftSymbol(kind: .protocolWitnessTableAccessor, children: [demangleSwift3ProtocolConformance()])
        case ("W", "t"): return try SwiftSymbol(kind: .associatedTypeMetadataAccessor, children: [demangleSwift3ProtocolConformance(), demangleSwift3DeclName()])
        case ("W", "T"): return try SwiftSymbol(kind: .associatedTypeWitnessTableAccessor, children: [demangleSwift3ProtocolConformance(), demangleSwift3DeclName(), demangleSwift3ProtocolName()])
        case ("W", _): throw scanner.unexpectedError()
        case ("T", "W"): return try SwiftSymbol(kind: .protocolWitness, children: [demangleSwift3ProtocolConformance(), demangleSwift3Entity()])
        case ("T", "R"): fallthrough
        case ("T", "r"): return try SwiftSymbol(kind: c2 == "R" ? SwiftSymbol.Kind.reabstractionThunkHelper : SwiftSymbol.Kind.reabstractionThunk, children: scanner.conditional(scalar: "G") ? [demangleSwift3GenericSignature(), demangleSwift3Type(), demangleSwift3Type()] : [demangleSwift3Type(), demangleSwift3Type()])
        default:
            try scanner.backtrack(count: 2)
            return try demangleSwift3Entity()
        }
    }

    mutating func demangleSwift3SpecializedAttribute() throws -> SwiftSymbol {
        let c = try scanner.readScalar()
        var children = [SwiftSymbol]()
        if scanner.conditional(scalar: "q") {
            children.append(SwiftSymbol(kind: .isSerialized))
        }
        try children.append(SwiftSymbol(kind: .specializationPassID, contents: .index(UInt64(scanner.readScalar().value - 48))))
        switch c {
        case "r": fallthrough
        case "g":
            while !scanner.conditional(scalar: "_") {
                var parameterChildren = [SwiftSymbol]()
                try parameterChildren.append(demangleSwift3Type())
                while !scanner.conditional(scalar: "_") {
                    try parameterChildren.append(demangleSwift3ProtocolConformance())
                }
                children.append(SwiftSymbol(kind: .genericSpecializationParam, children: parameterChildren))
            }
            return SwiftSymbol(kind: c == "r" ? .genericSpecializationNotReAbstracted : .genericSpecialization, children: children)
        case "f":
            var count: UInt64 = 0
            while !scanner.conditional(scalar: "_") {
                var paramChildren = [SwiftSymbol]()
                let c = try scanner.readScalar()
                switch try (c, scanner.readScalar()) {
                case ("n", "_"): break
                case ("c", "p"): try paramChildren.append(contentsOf: demangleSwift3FuncSigSpecializationConstantProp())
                case ("c", "l"):
                    paramChildren.append(SwiftSymbol(kind: .functionSignatureSpecializationParamKind, contents: .index(FunctionSigSpecializationParamKind.closureProp.rawValue)))
                    try paramChildren.append(SwiftSymbol(kind: .functionSignatureSpecializationParamPayload, contents: demangleSwift3Identifier().contents))
                    while !scanner.conditional(scalar: "_") {
                        try paramChildren.append(demangleSwift3Type())
                    }
                case ("i", "_"): fallthrough
                case ("k", "_"): paramChildren.append(SwiftSymbol(kind: .functionSignatureSpecializationParamKind, contents: .index(c == "i" ? FunctionSigSpecializationParamKind.boxToValue.rawValue : FunctionSigSpecializationParamKind.boxToStack.rawValue)))
                default:
                    try scanner.backtrack(count: 2)
                    var value: UInt64 = 0
                    value |= scanner.conditional(scalar: "d") ? FunctionSigSpecializationParamKind.dead.rawValue : 0
                    value |= scanner.conditional(scalar: "g") ? FunctionSigSpecializationParamKind.ownedToGuaranteed.rawValue : 0
                    value |= scanner.conditional(scalar: "o") ? FunctionSigSpecializationParamKind.guaranteedToOwned.rawValue : 0
                    value |= scanner.conditional(scalar: "s") ? FunctionSigSpecializationParamKind.sroa.rawValue : 0
                    try scanner.match(scalar: "_")
                    paramChildren.append(SwiftSymbol(kind: .functionSignatureSpecializationParamKind, contents: .index(value)))
                }
                children.append(SwiftSymbol(kind: .functionSignatureSpecializationParam, children: paramChildren, contents: .index(count)))
                count += 1
            }
            return SwiftSymbol(kind: .functionSignatureSpecialization, children: children)
        default: throw scanner.unexpectedError()
        }
    }

    mutating func demangleSwift3FuncSigSpecializationConstantProp() throws -> [SwiftSymbol] {
        switch try (scanner.readScalar(), scanner.readScalar()) {
        case ("f", "r"):
            let name = try SwiftSymbol(kind: .functionSignatureSpecializationParamPayload, contents: demangleSwift3Identifier().contents)
            try scanner.match(scalar: "_")
            let kind = SwiftSymbol(kind: .functionSignatureSpecializationParamKind, contents: .index(FunctionSigSpecializationParamKind.constantPropFunction.rawValue))
            return [kind, name]
        case ("g", _):
            try scanner.backtrack()
            let name = try SwiftSymbol(kind: .functionSignatureSpecializationParamPayload, contents: demangleSwift3Identifier().contents)
            try scanner.match(scalar: "_")
            let kind = SwiftSymbol(kind: .functionSignatureSpecializationParamKind, contents: .index(FunctionSigSpecializationParamKind.constantPropGlobal.rawValue))
            return [kind, name]
        case ("i", _):
            try scanner.backtrack()
            let string = try scanner.readUntil(scalar: "_")
            try scanner.match(scalar: "_")
            let name = SwiftSymbol(kind: .functionSignatureSpecializationParamPayload, contents: .name(string))
            let kind = SwiftSymbol(kind: .functionSignatureSpecializationParamKind, contents: .index(FunctionSigSpecializationParamKind.constantPropInteger.rawValue))
            return [kind, name]
        case ("f", "l"):
            let string = try scanner.readUntil(scalar: "_")
            try scanner.match(scalar: "_")
            let name = SwiftSymbol(kind: .functionSignatureSpecializationParamPayload, contents: .name(string))
            let kind = SwiftSymbol(kind: .functionSignatureSpecializationParamKind, contents: .index(FunctionSigSpecializationParamKind.constantPropFloat.rawValue))
            return [kind, name]
        case ("s", "e"):
            var string: String
            switch try scanner.readScalar() {
            case "0": string = "u8"
            case "1": string = "u16"
            default: throw scanner.unexpectedError()
            }
            try scanner.match(scalar: "v")
            let name = try SwiftSymbol(kind: .functionSignatureSpecializationParamPayload, contents: demangleSwift3Identifier().contents)
            let encoding = SwiftSymbol(kind: .functionSignatureSpecializationParamPayload, contents: .name(string))
            let kind = SwiftSymbol(kind: .functionSignatureSpecializationParamKind, contents: .index(FunctionSigSpecializationParamKind.constantPropString.rawValue))
            try scanner.match(scalar: "_")
            return [kind, encoding, name]
        default: throw scanner.unexpectedError()
        }
    }

    mutating func demangleSwift3ProtocolConformance() throws -> SwiftSymbol {
        let type = try demangleSwift3Type()
        let prot = try demangleSwift3ProtocolName()
        let context = try demangleSwift3Context()
        return SwiftSymbol(kind: .protocolConformance, children: [type, prot, context])
    }

    mutating func demangleSwift3ProtocolName() throws -> SwiftSymbol {
        let name: SwiftSymbol
        if scanner.conditional(scalar: "S") {
            let index = try demangleSwift3SubstitutionIndex()
            switch index.kind {
            case .protocol: name = index
            case .module: name = try demangleSwift3ProtocolNameGivenContext(context: index)
            default: throw scanner.unexpectedError()
            }
        } else if scanner.conditional(scalar: "s") {
            let stdlib = SwiftSymbol(kind: .module, contents: .name(stdlibName))
            name = try demangleSwift3ProtocolNameGivenContext(context: stdlib)
        } else {
            name = try demangleSwift3DeclarationName(kind: .protocol)
        }

        return SwiftSymbol(kind: .type, children: [name])
    }

    mutating func demangleSwift3ProtocolNameGivenContext(context: SwiftSymbol) throws -> SwiftSymbol {
        let name = try demangleSwift3DeclName()
        let result = SwiftSymbol(kind: .protocol, children: [context, name])
        nameStack.append(result)
        return result
    }

    mutating func demangleSwift3NominalType() throws -> SwiftSymbol {
        switch try scanner.readScalar() {
        case "S": return try demangleSwift3SubstitutionIndex()
        case "V": return try demangleSwift3DeclarationName(kind: .structure)
        case "O": return try demangleSwift3DeclarationName(kind: .enum)
        case "C": return try demangleSwift3DeclarationName(kind: .class)
        case "P": return try demangleSwift3DeclarationName(kind: .protocol)
        default: throw scanner.unexpectedError()
        }
    }

    mutating func demangleSwift3BoundGenericArgs(nominalType initialNominal: SwiftSymbol) throws -> SwiftSymbol {
        guard var parentOrModule = initialNominal.children.first else { throw scanner.unexpectedError() }

        let nominalType: SwiftSymbol
        switch parentOrModule.kind {
        case .module: fallthrough
        case .function: fallthrough
        case .extension: nominalType = initialNominal
        default:
            parentOrModule = try demangleSwift3BoundGenericArgs(nominalType: parentOrModule)

            guard initialNominal.children.count > 1 else { throw scanner.unexpectedError() }
            nominalType = SwiftSymbol(kind: initialNominal.kind, children: [parentOrModule, initialNominal.children[1]])
        }

        var children = [SwiftSymbol]()
        while !scanner.conditional(scalar: "_") {
            try children.append(demangleSwift3Type())
        }
        if children.isEmpty {
            return nominalType
        }
        let args = SwiftSymbol(kind: .typeList, children: children)
        let unboundType = SwiftSymbol(kind: .type, children: [nominalType])
        switch nominalType.kind {
        case .class: return SwiftSymbol(kind: .boundGenericClass, children: [unboundType, args])
        case .structure: return SwiftSymbol(kind: .boundGenericStructure, children: [unboundType, args])
        case .enum: return SwiftSymbol(kind: .boundGenericEnum, children: [unboundType, args])
        default: throw scanner.unexpectedError()
        }
    }

    mutating func demangleSwift3Entity() throws -> SwiftSymbol {
        let isStatic = scanner.conditional(scalar: "Z")

        let basicKind: SwiftSymbol.Kind
        switch try scanner.readScalar() {
        case "F": basicKind = .function
        case "v": basicKind = .variable
        case "I": basicKind = .initializer
        case "i": basicKind = .subscript
        default:
            try scanner.backtrack()
            return try demangleSwift3NominalType()
        }

        let context = try demangleSwift3Context()
        let kind: SwiftSymbol.Kind
        let hasType: Bool
        var name: SwiftSymbol? = nil
        var wrapEntity = false

        let c = try scanner.readScalar()
        switch c {
        case "Z": (kind, hasType) = (.isolatedDeallocator, false)
        case "D": (kind, hasType) = (.deallocator, false)
        case "d": (kind, hasType) = (.destructor, false)
        case "e": (kind, hasType) = (.iVarInitializer, false)
        case "E": (kind, hasType) = (.iVarDestroyer, false)
        case "C": (kind, hasType) = (.allocator, true)
        case "c": (kind, hasType) = (.constructor, true)
        case "a": fallthrough
        case "l":
            wrapEntity = true
            switch try scanner.readScalar() {
            case "O": (kind, hasType, name) = try (c == "a" ? .owningMutableAddressor : .owningAddressor, true, demangleSwift3DeclName())
            case "o": (kind, hasType, name) = try (c == "a" ? .nativeOwningMutableAddressor : .nativeOwningAddressor, true, demangleSwift3DeclName())
            case "p": (kind, hasType, name) = try (c == "a" ? .nativePinningMutableAddressor : .nativePinningAddressor, true, demangleSwift3DeclName())
            case "u": (kind, hasType, name) = try (c == "a" ? .unsafeMutableAddressor : .unsafeAddressor, true, demangleSwift3DeclName())
            default: throw scanner.unexpectedError()
            }
        case "g": (kind, hasType, name, wrapEntity) = try (.getter, true, demangleSwift3DeclName(), true)
        case "G": (kind, hasType, name, wrapEntity) = try (.globalGetter, true, demangleSwift3DeclName(), true)
        case "s": (kind, hasType, name, wrapEntity) = try (.setter, true, demangleSwift3DeclName(), true)
        case "m": (kind, hasType, name, wrapEntity) = try (.materializeForSet, true, demangleSwift3DeclName(), true)
        case "w": (kind, hasType, name, wrapEntity) = try (.willSet, true, demangleSwift3DeclName(), true)
        case "W": (kind, hasType, name, wrapEntity) = try (.didSet, true, demangleSwift3DeclName(), true)
        case "U": (kind, hasType, name) = try (.explicitClosure, true, SwiftSymbol(kind: .number, contents: .index(demangleSwift3Index())))
        case "u": (kind, hasType, name) = try (.implicitClosure, true, SwiftSymbol(kind: .number, contents: .index(demangleSwift3Index())))
        case "A" where basicKind == .initializer: (kind, hasType, name) = try (.defaultArgumentInitializer, false, SwiftSymbol(kind: .number, contents: .index(demangleSwift3Index())))
        case "i" where basicKind == .initializer: (kind, hasType) = (.initializer, false)
        case _ where basicKind == .initializer: throw scanner.unexpectedError()
        default:
            try scanner.backtrack()
            (kind, hasType, name) = try (basicKind, true, demangleSwift3DeclName())
        }

        var entity = SwiftSymbol(kind: kind)
        if wrapEntity {
            var isSubscript = false
            switch name?.kind {
            case .some(.identifier):
                if name?.text == "subscript" {
                    isSubscript = true
                    name = nil
                }
            case .some(.privateDeclName):
                if let n = name, let first = n.children.at(0), let second = n.children.at(1), second.text == "subscript" {
                    isSubscript = true
                    name = SwiftSymbol(kind: .privateDeclName, children: [first])
                }
            default: break
            }
            var wrappedEntity: SwiftSymbol
            if isSubscript {
                wrappedEntity = SwiftSymbol(kind: .subscript, child: context)
            } else {
                wrappedEntity = SwiftSymbol(kind: .variable, child: context)
            }
            if !isSubscript, let n = name {
                wrappedEntity.children.append(n)
            }
            if hasType {
                try wrappedEntity.children.append(demangleSwift3Type())
            }
            if isSubscript, let n = name {
                wrappedEntity.children.append(n)
            }
            entity.children.append(wrappedEntity)
        } else {
            entity.children.append(context)
            if let n = name {
                entity.children.append(n)
            }
            if hasType {
                try entity.children.append(demangleSwift3Type())
            }
        }

        return isStatic ? SwiftSymbol(kind: .static, children: [entity]) : entity
    }

    mutating func demangleSwift3DeclarationName(kind: SwiftSymbol.Kind) throws -> SwiftSymbol {
        let result = try SwiftSymbol(kind: kind, children: [demangleSwift3Context(), demangleSwift3DeclName()])
        nameStack.append(result)
        return result
    }

    mutating func demangleSwift3Context() throws -> SwiftSymbol {
        switch try scanner.readScalar() {
        case "E": return try SwiftSymbol(kind: .extension, children: [demangleSwift3Module(), demangleSwift3Context()])
        case "e":
            let module = try demangleSwift3Module()
            let signature = try demangleSwift3GenericSignature()
            let type = try demangleSwift3Context()
            return SwiftSymbol(kind: .extension, children: [module, type, signature])
        case "S": return try demangleSwift3SubstitutionIndex()
        case "s": return SwiftSymbol(kind: .module, children: [], contents: .name(stdlibName))
        case "G": return try demangleSwift3BoundGenericArgs(nominalType: demangleSwift3NominalType())
        case "F": fallthrough
        case "I": fallthrough
        case "v": fallthrough
        case "P": fallthrough
        case "Z": fallthrough
        case "C": fallthrough
        case "V": fallthrough
        case "O":
            try scanner.backtrack()
            return try demangleSwift3Entity()
        default:
            try scanner.backtrack()
            return try demangleSwift3Module()
        }
    }

    mutating func demangleSwift3Module() throws -> SwiftSymbol {
        switch try scanner.readScalar() {
        case "S": return try demangleSwift3SubstitutionIndex()
        case "s": return SwiftSymbol(kind: .module, children: [], contents: .name("Swift"))
        default:
            try scanner.backtrack()
            let module = try demangleSwift3Identifier(kind: .module)
            nameStack.append(module)
            return module
        }
    }

    func swiftStdLibType(_ kind: SwiftSymbol.Kind, named: String) -> SwiftSymbol {
        return SwiftSymbol(kind: kind, children: [SwiftSymbol(kind: .module, contents: .name(stdlibName)), SwiftSymbol(kind: .identifier, contents: .name(named))])
    }

    mutating func demangleSwift3SubstitutionIndex() throws -> SwiftSymbol {
        switch try scanner.readScalar() {
        case "o": return SwiftSymbol(kind: .module, contents: .name(objcModule))
        case "C": return SwiftSymbol(kind: .module, contents: .name(cModule))
        case "a": return swiftStdLibType(.structure, named: "Array")
        case "b": return swiftStdLibType(.structure, named: "Bool")
        case "c": return swiftStdLibType(.structure, named: "UnicodeScalar")
        case "d": return swiftStdLibType(.structure, named: "Double")
        case "f": return swiftStdLibType(.structure, named: "Float")
        case "i": return swiftStdLibType(.structure, named: "Int")
        case "V": return swiftStdLibType(.structure, named: "UnsafeRawPointer")
        case "v": return swiftStdLibType(.structure, named: "UnsafeMutableRawPointer")
        case "P": return swiftStdLibType(.structure, named: "UnsafePointer")
        case "p": return swiftStdLibType(.structure, named: "UnsafeMutablePointer")
        case "q": return swiftStdLibType(.enum, named: "Optional")
        case "Q": return swiftStdLibType(.enum, named: "ImplicitlyUnwrappedOptional")
        case "R": return swiftStdLibType(.structure, named: "UnsafeBufferPointer")
        case "r": return swiftStdLibType(.structure, named: "UnsafeMutableBufferPointer")
        case "S": return swiftStdLibType(.structure, named: "String")
        case "u": return swiftStdLibType(.structure, named: "UInt")
        default:
            try scanner.backtrack()
            let index = try demangleSwift3Index()
            if Int(index) >= nameStack.count {
                throw scanner.unexpectedError()
            }
            return nameStack[Int(index)]
        }
    }

    mutating func demangleSwift3GenericSignature(isPseudo: Bool = false) throws -> SwiftSymbol {
        var children = [SwiftSymbol]()
        var c = try scanner.requirePeek()
        while c != "R" && c != "r" {
            try children.append(SwiftSymbol(kind: .dependentGenericParamCount, contents: .index(scanner.conditional(scalar: "z") ? 0 : (demangleSwift3Index() + 1))))
            c = try scanner.requirePeek()
        }
        if children.isEmpty {
            children.append(SwiftSymbol(kind: .dependentGenericParamCount, contents: .index(1)))
        }
        if !scanner.conditional(scalar: "r") {
            try scanner.match(scalar: "R")
            while !scanner.conditional(scalar: "r") {
                try children.append(demangleSwift3GenericRequirement())
            }
        }
        return SwiftSymbol(kind: .dependentGenericSignature, children: children)
    }

    mutating func demangleSwift3GenericRequirement() throws -> SwiftSymbol {
        let constrainedType = try demangleSwift3ConstrainedType()
        if scanner.conditional(scalar: "z") {
            return try SwiftSymbol(kind: .dependentGenericSameTypeRequirement, children: [constrainedType, demangleSwift3Type()])
        }

        if scanner.conditional(scalar: "l") {
            let name: String
            let kind: SwiftSymbol.Kind
            var size = UInt64.max
            var alignment = UInt64.max
            switch try scanner.readScalar() {
            case "U": (kind, name) = (.identifier, "U")
            case "R": (kind, name) = (.identifier, "R")
            case "N": (kind, name) = (.identifier, "N")
            case "T": (kind, name) = (.identifier, "T")
            case "E":
                (kind, name) = (.identifier, "E")
                size = try require(demangleNatural())
                try scanner.match(scalar: "_")
                alignment = try require(demangleNatural())
            case "e":
                (kind, name) = (.identifier, "e")
                size = try require(demangleNatural())
            case "M":
                (kind, name) = (.identifier, "M")
                size = try require(demangleNatural())
                try scanner.match(scalar: "_")
                alignment = try require(demangleNatural())
            case "m":
                (kind, name) = (.identifier, "m")
                size = try require(demangleNatural())
            default: throw failure
            }
            let second = SwiftSymbol(kind: kind, contents: .name(name))
            var reqt = SwiftSymbol(kind: .dependentGenericLayoutRequirement, children: [constrainedType, second])
            if size != UInt64.max {
                reqt.children.append(SwiftSymbol(kind: .number, contents: .index(size)))
                if alignment != UInt64.max {
                    reqt.children.append(SwiftSymbol(kind: .number, contents: .index(alignment)))
                }
            }
            return reqt
        }

        let c = try scanner.requirePeek()
        let constraint: SwiftSymbol
        if c == "C" {
            constraint = try demangleSwift3Type()
        } else if c == "S" {
            try scanner.match(scalar: "S")
            let index = try demangleSwift3SubstitutionIndex()
            let typename: SwiftSymbol
            switch index.kind {
            case .protocol: fallthrough
            case .class: typename = index
            case .module: typename = try demangleSwift3ProtocolNameGivenContext(context: index)
            default: throw scanner.unexpectedError()
            }
            constraint = SwiftSymbol(kind: .type, children: [typename])
        } else {
            constraint = try demangleSwift3ProtocolName()
        }
        return SwiftSymbol(kind: .dependentGenericConformanceRequirement, children: [constrainedType, constraint])
    }

    mutating func demangleSwift3ConstrainedType() throws -> SwiftSymbol {
        if scanner.conditional(scalar: "w") {
            return try demangleSwift3AssociatedTypeSimple()
        } else if scanner.conditional(scalar: "W") {
            return try demangleSwift3AssociatedTypeCompound()
        }
        return try demangleSwift3GenericParamIndex()
    }

    mutating func demangleSwift3AssociatedTypeSimple() throws -> SwiftSymbol {
        let base = try demangleSwift3GenericParamIndex()
        return try demangleSwift3DependentMemberTypeName(base: SwiftSymbol(kind: .type, children: [base]))
    }

    mutating func demangleSwift3AssociatedTypeCompound() throws -> SwiftSymbol {
        var base = try demangleSwift3GenericParamIndex()
        while !scanner.conditional(scalar: "_") {
            let type = SwiftSymbol(kind: .type, children: [base])
            base = try demangleSwift3DependentMemberTypeName(base: type)
        }
        return base
    }

    mutating func demangleSwift3GenericParamIndex() throws -> SwiftSymbol {
        let depth: UInt64
        let index: UInt64
        switch try scanner.readScalar() {
        case "d": (depth, index) = try (demangleSwift3Index() + 1, demangleSwift3Index())
        case "x": (depth, index) = (0, 0)
        default:
            try scanner.backtrack()
            (depth, index) = try (0, demangleSwift3Index() + 1)
        }
        return SwiftSymbol(kind: .dependentGenericParamType, children: [SwiftSymbol(kind: .index, contents: .index(depth)), SwiftSymbol(kind: .index, contents: .index(index))], contents: .name(archetypeName(index, depth)))
    }

    mutating func demangleSwift3DependentMemberTypeName(base: SwiftSymbol) throws -> SwiftSymbol {
        let associatedType: SwiftSymbol
        if scanner.conditional(scalar: "S") {
            associatedType = try demangleSwift3SubstitutionIndex()
        } else {
            var prot: SwiftSymbol? = nil
            if scanner.conditional(scalar: "P") {
                prot = try demangleSwift3ProtocolName()
            }
            let identifier = try demangleSwift3Identifier()
            if let p = prot {
                associatedType = SwiftSymbol(kind: .dependentAssociatedTypeRef, children: [identifier, p])
            } else {
                associatedType = SwiftSymbol(kind: .dependentAssociatedTypeRef, children: [identifier])
            }
            nameStack.append(associatedType)
        }

        return SwiftSymbol(kind: .dependentMemberType, children: [base, associatedType])
    }

    mutating func demangleSwift3DeclName() throws -> SwiftSymbol {
        switch try scanner.readScalar() {
        case "L": return try SwiftSymbol(kind: .localDeclName, children: [SwiftSymbol(kind: .number, contents: .index(demangleSwift3Index())), demangleSwift3Identifier()])
        case "P": return try SwiftSymbol(kind: .privateDeclName, children: [demangleSwift3Identifier(), demangleSwift3Identifier()])
        default:
            try scanner.backtrack()
            return try demangleSwift3Identifier()
        }
    }

    mutating func demangleSwift3Index() throws -> UInt64 {
        if scanner.conditional(scalar: "_") {
            return 0
        }
        let value = try UInt64(scanner.readInt()) + 1
        try scanner.match(scalar: "_")
        return value
    }

    mutating func demangleSwift3Type() throws -> SwiftSymbol {
        let type: SwiftSymbol
        switch try scanner.readScalar() {
        case "B":
            switch try scanner.readScalar() {
            case "b": type = SwiftSymbol(kind: .builtinTypeName, contents: .name("Builtin.BridgeObject"))
            case "B": type = SwiftSymbol(kind: .builtinTypeName, contents: .name("Builtin.UnsafeValueBuffer"))
            case "f":
                let size = try scanner.readInt()
                try scanner.match(scalar: "_")
                type = SwiftSymbol(kind: .builtinTypeName, contents: .name("Builtin.FPIEEE\(size)"))
            case "i":
                let size = try scanner.readInt()
                try scanner.match(scalar: "_")
                type = SwiftSymbol(kind: .builtinTypeName, contents: .name("Builtin.Int\(size)"))
            case "v":
                let elements = try scanner.readInt()
                try scanner.match(scalar: "B")
                let name: String
                let size: String
                let c = try scanner.readScalar()
                switch c {
                case "p": (name, size) = ("xRawPointer", "")
                case "i": fallthrough
                case "f":
                    (name, size) = try (c == "i" ? "xInt" : "xFPIEEE", "\(scanner.readInt())")
                    try scanner.match(scalar: "_")
                default: throw scanner.unexpectedError()
                }
                type = SwiftSymbol(kind: .builtinTypeName, contents: .name("Builtin.Vec\(elements)\(name)\(size)"))
            case "O": type = SwiftSymbol(kind: .builtinTypeName, contents: .name("Builtin.UnknownObject"))
            case "o": type = SwiftSymbol(kind: .builtinTypeName, contents: .name("Builtin.NativeObject"))
            case "t": type = SwiftSymbol(kind: .builtinTypeName, contents: .name("Builtin.SILToken"))
            case "p": type = SwiftSymbol(kind: .builtinTypeName, contents: .name("Builtin.RawPointer"))
            case "w": type = SwiftSymbol(kind: .builtinTypeName, contents: .name("Builtin.Word"))
            default: throw scanner.unexpectedError()
            }
        case "a": type = try demangleSwift3DeclarationName(kind: .typeAlias)
        case "b": type = try demangleSwift3FunctionType(kind: .objCBlock)
        case "c": type = try demangleSwift3FunctionType(kind: .cFunctionPointer)
        case "D": type = try SwiftSymbol(kind: .dynamicSelf, children: [demangleSwift3Type()])
        case "E":
            guard try scanner.readScalars(count: 2) == "RR" else { throw scanner.unexpectedError() }
            type = SwiftSymbol(kind: .errorType, children: [], contents: .name(""))
        case "F": type = try demangleSwift3FunctionType(kind: .functionType)
        case "f": type = try demangleSwift3FunctionType(kind: .uncurriedFunctionType)
        case "G": type = try demangleSwift3BoundGenericArgs(nominalType: demangleSwift3NominalType())
        case "X":
            let c = try scanner.readScalar()
            switch c {
            case "b": type = try SwiftSymbol(kind: .silBoxType, children: [demangleSwift3Type()])
            case "B":
                var signature: SwiftSymbol? = nil
                if scanner.conditional(scalar: "G") {
                    signature = try demangleSwift3GenericSignature(isPseudo: false)
                }
                var layout = SwiftSymbol(kind: .silBoxLayout)
                while !scanner.conditional(scalar: "_") {
                    let kind: SwiftSymbol.Kind
                    switch try scanner.readScalar() {
                    case "m": kind = .silBoxMutableField
                    case "i": kind = .silBoxImmutableField
                    default: throw failure
                    }
                    let type = try demangleType()
                    let field = SwiftSymbol(kind: kind, child: type)
                    layout.children.append(field)
                }
                var genericArgs: SwiftSymbol? = nil
                if signature != nil {
                    var ga = SwiftSymbol(kind: .typeList)
                    while !scanner.conditional(scalar: "_") {
                        let type = try demangleType()
                        ga.children.append(type)
                    }
                    genericArgs = ga
                }
                var boxType = SwiftSymbol(kind: .silBoxTypeWithLayout, child: layout)
                if let s = signature, let ga = genericArgs {
                    boxType.children.append(s)
                    boxType.children.append(ga)
                }
                return boxType
            case "P" where scanner.conditional(scalar: "M"): fallthrough
            case "M":
                let value: String
                switch try scanner.readScalar() {
                case "t": value = "@thick"
                case "T": value = "@thin"
                case "o": value = "@objc_metatype"
                default: throw scanner.unexpectedError()
                }
                type = try SwiftSymbol(kind: c == "P" ? .existentialMetatype : .metatype, children: [SwiftSymbol(kind: .metatypeRepresentation, contents: .name(value)), demangleSwift3Type()])
            case "P":
                var children = [SwiftSymbol]()
                while !scanner.conditional(scalar: "_") {
                    try children.append(demangleSwift3ProtocolName())
                }
                type = SwiftSymbol(kind: .protocolList, children: [SwiftSymbol(kind: .typeList)])
            case "f": type = try demangleSwift3FunctionType(kind: .thinFunctionType)
            case "o": type = try SwiftSymbol(kind: .unowned, children: [demangleSwift3Type()])
            case "u": type = try SwiftSymbol(kind: .unmanaged, children: [demangleSwift3Type()])
            case "w": type = try SwiftSymbol(kind: .weak, children: [demangleSwift3Type()])
            case "F":
                var children = [SwiftSymbol]()
                try children.append(SwiftSymbol(kind: .implConvention, contents: .name(demangleSwift3ImplConvention(kind: .implConvention))))
                if scanner.conditional(scalar: "C") {
                    let name: String
                    switch try scanner.readScalar() {
                    case "b": name = "@convention(block)"
                    case "c": name = "@convention(c)"
                    case "m": name = "@convention(method)"
                    case "O": name = "@convention(objc_method)"
                    case "w": name = "@convention(witness_method)"
                    default: throw scanner.unexpectedError()
                    }
                    children.append(SwiftSymbol(kind: .implFunctionAttribute, contents: .name(name)))
                }
                if scanner.conditional(scalar: "G") {
                    try children.append(demangleSwift3GenericSignature(isPseudo: false))
                } else if scanner.conditional(scalar: "g") {
                    try children.append(demangleSwift3GenericSignature(isPseudo: true))
                }
                try scanner.match(scalar: "_")
                while !scanner.conditional(scalar: "_") {
                    try children.append(demangleSwift3ImplParameterOrResult(kind: .implParameter))
                }
                while !scanner.conditional(scalar: "_") {
                    try children.append(demangleSwift3ImplParameterOrResult(kind: .implResult))
                }
                type = SwiftSymbol(kind: .implFunctionType, children: children)
            default: throw scanner.unexpectedError()
            }
        case "K": type = try demangleSwift3FunctionType(kind: .autoClosureType)
        case "M": type = try SwiftSymbol(kind: .metatype, children: [demangleSwift3Type()])
        case "P" where scanner.conditional(scalar: "M"): type = try SwiftSymbol(kind: .existentialMetatype, children: [demangleSwift3Type()])
        case "P":
            var children = [SwiftSymbol]()
            while !scanner.conditional(scalar: "_") {
                try children.append(demangleSwift3ProtocolName())
            }
            type = SwiftSymbol(kind: .protocolList, children: [SwiftSymbol(kind: .typeList, children: children)])
        case "Q":
            if scanner.conditional(scalar: "u") {
                type = SwiftSymbol(kind: .opaqueReturnType)
            } else if scanner.conditional(scalar: "U") {
                let index = try demangleIndex()
                type = SwiftSymbol(kind: .opaqueReturnType, child: SwiftSymbol(kind: .opaqueReturnTypeIndex, contents: .index(index)))
            } else {
                type = try demangleSwift3ArchetypeType()
            }
        case "q":
            let c = try scanner.requirePeek()
            if c != "d" && c != "_" && c < "0" && c > "9" {
                type = try demangleSwift3DependentMemberTypeName(base: demangleSwift3Type())
            } else {
                type = try demangleSwift3GenericParamIndex()
            }
        case "x": type = SwiftSymbol(kind: .dependentGenericParamType, children: [SwiftSymbol(kind: .index, contents: .index(0)), SwiftSymbol(kind: .index, contents: .index(0))], contents: .name(archetypeName(0, 0)))
        case "w": type = try demangleSwift3AssociatedTypeSimple()
        case "W": type = try demangleSwift3AssociatedTypeCompound()
        case "R": type = try SwiftSymbol(kind: .inOut, children: demangleSwift3Type().children)
        case "S": type = try demangleSwift3SubstitutionIndex()
        case "T": type = try demangleSwift3Tuple(variadic: false)
        case "t": type = try demangleSwift3Tuple(variadic: true)
        case "u": type = try SwiftSymbol(kind: .dependentGenericType, children: [demangleSwift3GenericSignature(), demangleSwift3Type()])
        case "C": type = try demangleSwift3DeclarationName(kind: .class)
        case "V": type = try demangleSwift3DeclarationName(kind: .structure)
        case "O": type = try demangleSwift3DeclarationName(kind: .enum)
        default: throw scanner.unexpectedError()
        }
        return SwiftSymbol(kind: .type, children: [type])
    }

    mutating func demangleSwift3ArchetypeType() throws -> SwiftSymbol {
        switch try scanner.readScalar() {
        case "Q":
            let result = try SwiftSymbol(kind: .associatedTypeRef, children: [demangleSwift3ArchetypeType(), demangleSwift3Identifier()])
            nameStack.append(result)
            return result
        case "S":
            let index = try demangleSwift3SubstitutionIndex()
            let result = try SwiftSymbol(kind: .associatedTypeRef, children: [index, demangleSwift3Identifier()])
            nameStack.append(result)
            return result
        case "s":
            let root = SwiftSymbol(kind: .module, contents: .name(stdlibName))
            let result = try SwiftSymbol(kind: .associatedTypeRef, children: [root, demangleSwift3Identifier()])
            nameStack.append(result)
            return result
        default: throw scanner.unexpectedError()
        }
    }

    mutating func demangleSwift3ImplConvention(kind: SwiftSymbol.Kind) throws -> String {
        let scalar = try scanner.readScalar()
        switch (scalar, kind == .implErrorResult ? .implResult : kind) {
        case ("a", .implResult): return "@autoreleased"
        case ("d", .implConvention): return "@callee_unowned"
        case ("d", _): return "@unowned"
        case ("D", .implResult): return "@unowned_inner_pointer"
        case ("g", .implParameter): return "@guaranteed"
        case ("e", .implParameter): return "@deallocating"
        case ("g", .implConvention): return "@callee_guaranteed"
        case ("i", .implParameter): return "@in"
        case ("i", .implResult): return "@out"
        case ("l", .implParameter): return "@inout"
        case ("o", .implConvention): return "@callee_owned"
        case ("o", _): return "@owned"
        case ("t", .implConvention): return "@convention(thin)"
        default: throw scanner.unexpectedError()
        }
    }

    mutating func demangleSwift3ImplParameterOrResult(kind: SwiftSymbol.Kind) throws -> SwiftSymbol {
        var k: SwiftSymbol.Kind
        if scanner.conditional(scalar: "z") {
            if case .implResult = kind {
                k = .implErrorResult
            } else {
                throw scanner.unexpectedError()
            }
        } else {
            k = kind
        }

        let convention = try demangleSwift3ImplConvention(kind: k)
        let type = try demangleSwift3Type()
        let conventionNode = SwiftSymbol(kind: .implConvention, contents: .name(convention))
        return SwiftSymbol(kind: k, children: [conventionNode, type])
    }

    mutating func demangleSwift3Tuple(variadic: Bool) throws -> SwiftSymbol {
        var children = [SwiftSymbol]()
        while !scanner.conditional(scalar: "_") {
            var elementChildren = [SwiftSymbol]()
            let peek = try scanner.requirePeek()
            if (peek >= "0" && peek <= "9") || peek == "o" {
                try elementChildren.append(demangleSwift3Identifier(kind: .tupleElementName))
            }
            try elementChildren.append(demangleSwift3Type())
            children.append(SwiftSymbol(kind: .tupleElement, children: elementChildren))
        }
        if variadic, var last = children.popLast() {
            last.children.insert(SwiftSymbol(kind: .variadicMarker), at: 0)
            children.append(last)
        }
        return SwiftSymbol(kind: .tuple, children: children)
    }

    mutating func demangleSwift3FunctionType(kind: SwiftSymbol.Kind) throws -> SwiftSymbol {
        var children = [SwiftSymbol]()
        if scanner.conditional(scalar: "z") {
            children.append(SwiftSymbol(kind: .throwsAnnotation))
        }
        try children.append(SwiftSymbol(kind: .argumentTuple, children: [demangleSwift3Type()]))
        try children.append(SwiftSymbol(kind: .returnType, children: [demangleSwift3Type()]))
        return SwiftSymbol(kind: kind, children: children)
    }

    mutating func demangleSwift3Identifier(kind: SwiftSymbol.Kind? = nil) throws -> SwiftSymbol {
        let isPunycode = scanner.conditional(scalar: "X")
        let k: SwiftSymbol.Kind
        let isOperator: Bool
        if scanner.conditional(scalar: "o") {
            guard kind == nil else { throw scanner.unexpectedError() }
            switch try scanner.readScalar() {
            case "p": (isOperator, k) = (true, .prefixOperator)
            case "P": (isOperator, k) = (true, .postfixOperator)
            case "i": (isOperator, k) = (true, .infixOperator)
            default: throw scanner.unexpectedError()
            }
        } else {
            (isOperator, k) = (false, kind ?? SwiftSymbol.Kind.identifier)
        }

        var identifier = try scanner.readScalars(count: Int(scanner.readInt()))
        if isPunycode {
            identifier = try decodeSwiftPunycode(identifier)
        }
        if isOperator {
            let source = identifier
            identifier = ""
            for scalar in source.unicodeScalars {
                switch scalar {
                case "a": identifier.unicodeScalars.append("&" as UnicodeScalar)
                case "c": identifier.unicodeScalars.append("@" as UnicodeScalar)
                case "d": identifier.unicodeScalars.append("/" as UnicodeScalar)
                case "e": identifier.unicodeScalars.append("=" as UnicodeScalar)
                case "g": identifier.unicodeScalars.append(">" as UnicodeScalar)
                case "l": identifier.unicodeScalars.append("<" as UnicodeScalar)
                case "m": identifier.unicodeScalars.append("*" as UnicodeScalar)
                case "n": identifier.unicodeScalars.append("!" as UnicodeScalar)
                case "o": identifier.unicodeScalars.append("|" as UnicodeScalar)
                case "p": identifier.unicodeScalars.append("+" as UnicodeScalar)
                case "q": identifier.unicodeScalars.append("?" as UnicodeScalar)
                case "r": identifier.unicodeScalars.append("%" as UnicodeScalar)
                case "s": identifier.unicodeScalars.append("-" as UnicodeScalar)
                case "t": identifier.unicodeScalars.append("~" as UnicodeScalar)
                case "x": identifier.unicodeScalars.append("^" as UnicodeScalar)
                case "z": identifier.unicodeScalars.append("." as UnicodeScalar)
                default:
                    if scalar.value >= 128 {
                        identifier.unicodeScalars.append(scalar)
                    } else {
                        throw scanner.unexpectedError()
                    }
                }
            }
        }

        return SwiftSymbol(kind: k, children: [], contents: .name(identifier))
    }
}
