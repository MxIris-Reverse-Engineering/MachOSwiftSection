struct Demangler<C>: Sendable where C: Collection, C.Iterator.Element == UnicodeScalar, C: Sendable, C.Index: Sendable {
    private var scanner: ScalarScanner
    private var nameStack: [Node] = []
    private var substitutions: [Node] = []
    private var words: [String] = []
    private var isOldFunctionTypeMangling: Bool = false
    private var flavor: ManglingFlavor = .default
    private var symbolicReferenceIndex: Int = 0

    var symbolicReferenceResolver: DemangleSymbolicReferenceResolver?

    init(scalars: C) {
        self.scanner = ScalarScanner(scalars: scalars)
    }

    static func getManglingPrefixLength(_ scalars: C) -> Int {
        var scanner = ScalarScanner(scalars: scalars)
        if scanner.conditional(string: "_T0") || scanner.conditional(string: "_$S") || scanner.conditional(string: "_$s") || scanner.conditional(string: "_$e") {
            return 3
        } else if scanner.conditional(string: "$S") || scanner.conditional(string: "$s") || scanner.conditional(string: "$e") {
            return 2
        } else if scanner.conditional(string: "@__swiftmacro_") {
            return 14
        }

        return 0
    }
}

extension Demangler {
    private func require<T>(_ optional: T?) throws(DemanglingError) -> T {
        if let v = optional {
            return v
        } else {
            throw failure
        }
    }

    private func require(_ value: Bool) throws(DemanglingError) {
        if !value {
            throw failure
        }
    }

    private var failure: DemanglingError {
        return scanner.unexpectedError()
    }

    private mutating func readManglingPrefix() throws(DemanglingError) {
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

    private mutating func reset() {
        nameStack = []
        substitutions = []
        words = []
        scanner.reset()
    }

    private mutating func popTopLevelInto(_ parent: Node) throws(DemanglingError) {
        while let funcAttr = pop(where: { $0.isFunctionAttr }) {
            switch funcAttr.kind {
            case .partialApplyForwarder,
                 .partialApplyObjCForwarder:
                try popTopLevelInto(funcAttr)
                parent.addChild(funcAttr)
                return
            default:
                parent.addChild(funcAttr)
            }
        }
        for name in nameStack {
            switch name.kind {
            case .type: try parent.addChild(require(name.children.first))
            default: parent.addChild(name)
            }
        }
    }

    package mutating func demangleSymbol() throws(DemanglingError) -> Node {
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
        let topLevel = Node(kind: .global)
        try popTopLevelInto(topLevel)
        if let suffix {
            topLevel.addChild(suffix)
        }
        try require(topLevel.children.count != 0)
        return topLevel
    }

    package mutating func demangleType() throws(DemanglingError) -> Node {
        reset()

        try parseAndPushNames()
        if let result = pop() {
            return result
        }

        return Node(kind: .suffix, contents: .text(String(String.UnicodeScalarView(scanner.scalars))), children: [])
    }

    private mutating func parseAndPushNames() throws(DemanglingError) {
        while !scanner.isAtEnd {
            try nameStack.append(demangleOperator())
        }
    }

    private mutating func demangleSymbolicReference(rawValue: UInt8) throws(DemanglingError) -> Node {
        guard let (kind, directness) = SymbolicReference.symbolicReference(for: rawValue) else {
            throw DemanglingError.requiredNonOptional
        }
        guard let symbolicReferenceResolver, let resolvedNode = symbolicReferenceResolver(kind, directness, symbolicReferenceIndex) else {
            throw DemanglingError.requiredNonOptional
        }
        symbolicReferenceIndex += 1
        if (kind == .context || kind == .objectiveCProtocol) && (resolvedNode.kind != .opaqueTypeDescriptorSymbolicReference && resolvedNode.kind != .opaqueReturnTypeOf) {
            substitutions.append(resolvedNode)
        }
        return resolvedNode
    }

    private mutating func demangleTypeAnnotation() throws(DemanglingError) -> Node {
        switch try scanner.readScalar() {
        case "a": return Node(kind: .asyncAnnotation)
        case "A": return Node(kind: .isolatedAnyFunctionType)
        case "b": return Node(kind: .concurrentFunctionType)
        case "c": return try Node(kind: .globalActorFunctionType, child: require(popTypeAndGetChild()))
        case "C": return Node(kind: .nonIsolatedCallerFunctionType)
        case "i": return try Node(typeWithChildKind: .isolated, childChild: require(popTypeAndGetChild()))
        case "j": return try demangleDifferentiableFunctionType()
        case "k": return try Node(typeWithChildKind: .noDerivative, childChild: require(popTypeAndGetChild()))
        case "K": return try Node(kind: .typedThrowsAnnotation, child: require(popTypeAndGetChild()))
        case "t": return try Node(typeWithChildKind: .compileTimeConst, childChild: require(popTypeAndGetChild()))
        case "T": return Node(kind: .sendingResultFunctionType)
        case "u": return try Node(typeWithChildKind: .sending, childChild: require(popTypeAndGetChild()))
        case "g": return try Node(typeWithChildKind: .constValue, childChild: require(popTypeAndGetChild()))
        default: throw failure
        }
    }

    private mutating func demangleOperator() throws(DemanglingError) -> Node {
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
        case "D": return try Node(kind: .typeMangling, child: require(pop(kind: .type)))
        case "E": return try demangleExtensionContext()
        case "F": return try demanglePlainFunction()
        case "G": return try demangleBoundGenericType()
        case "H":
            switch try scanner.readScalar() {
            case "A": return try demangleDependentProtocolConformanceAssociated()
            case "C": return try demangleConcreteProtocolConformance()
            case "D": return try demangleDependentProtocolConformanceRoot()
            case "I": return try demangleDependentProtocolConformanceInherited()
            case "O": return try demangleDependentProtocolConformanceOpaque()
            case "P": return try Node(kind: .protocolConformanceRefInTypeModule, child: popProtocol())
            case "p": return try Node(kind: .protocolConformanceRefInProtocolModule, child: popProtocol())
            case "X": return try Node(kind: .packProtocolConformance, child: popAnyProtocolConformanceList())
            case "c": return try Node(kind: .protocolConformanceDescriptorRecord, child: popProtocolConformance())
            case "n": return try Node(kind: .nominalTypeDescriptorRecord, child: require(pop(kind: .type)))
            case "o": return try Node(kind: .opaqueTypeDescriptorRecord, child: require(pop()))
            case "r": return try Node(kind: .protocolDescriptorRecord, child: popProtocol())
            case "F": return Node(kind: .accessibleFunctionRecord)
            default:
                try scanner.backtrack(count: 2)
                return try demangleIdentifier()
            }
        case "I": return try demangleImplFunctionType()
        case "K": return Node(kind: .throwsAnnotation)
        case "L": return try demangleLocalIdentifier()
        case "M": return try demangleMetatype()
        case "N": return try Node(kind: .typeMetadata, child: require(pop(kind: .type)))
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
        case "Z": return try Node(kind: .static, child: require(pop(where: { $0.isEntity })))
        case "a": return try demangleAnyGenericType(kind: .typeAlias)
        case "c": return try require(popFunctionType(kind: .functionType))
        case "d": return Node(kind: .variadicMarker)
        case "f": return try demangleFunctionEntity()
        case "g": return try demangleRetroactiveConformance()
        case "h": return try Node(typeWithChildKind: .shared, childChild: require(popTypeAndGetChild()))
        case "i": return try demangleSubscript()
        case "l": return try demangleGenericSignature(hasParamCounts: false)
        case "m": return try Node(typeWithChildKind: .metatype, childChild: require(pop(kind: .type)))
        case "n": return try Node(typeWithChildKind: .owned, childChild: popTypeAndGetChild())
        case "o": return try demangleOperatorIdentifier()
        case "p": return try demangleProtocolListType()
        case "q": return try Node(kind: .type, child: demangleGenericParamIndex())
        case "r": return try demangleGenericSignature(hasParamCounts: true)
        case "s": return Node(kind: .module, contents: .text(stdlibName))
        case "t": return try popTuple()
        case "u": return try demangleGenericType()
        case "v": return try demangleVariable()
        case "w": return try demangleValueWitness()
        case "x": return try Node(kind: .type, child: getDependentGenericParamType(depth: 0, index: 0))
        case "y": return Node(kind: .emptyList)
        case "z": return try Node(typeWithChildKind: .inOut, childChild: require(popTypeAndGetChild()))
        case "_": return Node(kind: .firstElementMarker)
        case ".":
            try scanner.backtrack()
            return Node(kind: .suffix, contents: .text(scanner.remainder()))
        case "$": return try demangleIntegerType()
        default:
            try scanner.backtrack()
            return try demangleIdentifier()
        }
    }

    private mutating func demangleNatural() throws(DemanglingError) -> UInt64? {
        return try scanner.conditionalInt()
    }

    private mutating func demangleIndex() throws(DemanglingError) -> UInt64 {
        if scanner.conditional(scalar: "_") {
            return 0
        }
        let value = try require(demangleNatural())
        try scanner.match(scalar: "_")
        return value + 1
    }

    private mutating func demangleIndexAsName() throws(DemanglingError) -> Node {
        return try Node(kind: .number, contents: .index(demangleIndex()))
    }

    private mutating func demangleMultiSubstitutions() throws(DemanglingError) -> Node {
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

    private mutating func pushMultiSubstitutions(repeatCount: Int, index: Int) throws(DemanglingError) -> Node {
        try require(repeatCount <= maxRepeatCount)
        let nd = try require(substitutions.at(index))
//        (0 ..< max(0, repeatCount - 1)).forEach { _ in  }
        var repeatCount = repeatCount
        while repeatCount > 1 {
            nameStack.append(nd)
            repeatCount -= 1
        }
        return nd
    }

    private mutating func pop() -> Node? {
        return nameStack.popLast()
    }

    private mutating func pop(kind: Node.Kind) -> Node? {
        return nameStack.last?.kind == kind ? pop() : nil
    }

    private mutating func pop(where cond: (Node.Kind) -> Bool) -> Node? {
        return nameStack.last.map { cond($0.kind) } == true ? pop() : nil
    }

    private mutating func popFunctionType(kind: Node.Kind, hasClangType: Bool = false) throws(DemanglingError) -> Node {
        let name = Node(kind: kind)
        if hasClangType {
            try name.addChild(demangleClangType())
        }
        if let sendingResult = pop(kind: .sendingResultFunctionType) {
            name.addChild(sendingResult)
        }
        if let isFunctionIsolation = pop(where: { $0 == .globalActorFunctionType || $0 == .isolatedAnyFunctionType || $0 == .nonIsolatedCallerFunctionType }) {
            name.addChild(isFunctionIsolation)
        }
        if let differentiable = pop(kind: .differentiableFunctionType) {
            name.addChild(differentiable)
        }
        if let throwsAnnotation = pop(where: { $0 == .throwsAnnotation || $0 == .typedThrowsAnnotation }) {
            name.addChild(throwsAnnotation)
        }
        if let concurrent = pop(kind: .concurrentFunctionType) {
            name.addChild(concurrent)
        }
        if let asyncAnnotation = pop(kind: .asyncAnnotation) {
            name.addChild(asyncAnnotation)
        }
        try name.addChild(popFunctionParams(kind: .argumentTuple))
        try name.addChild(popFunctionParams(kind: .returnType))
        return Node(kind: .type, child: name)
    }

    private mutating func popFunctionParams(kind: Node.Kind) throws(DemanglingError) -> Node {
        let paramsType: Node
        if pop(kind: .emptyList) != nil {
            return Node(kind: kind, child: Node(kind: .type, child: Node(kind: .tuple)))
        } else {
            paramsType = try require(pop(kind: .type))
        }
        return Node(kind: kind, children: [paramsType])
    }

    private mutating func getLabel(params: Node, idx: Int) throws(DemanglingError) -> Node {
        if isOldFunctionTypeMangling {
            let param = try require(params.children.at(idx))
            if let label = param.children.enumerated().first(where: { $0.element.kind == .tupleElementName }) {
                param.removeChild(at: label.offset)
                return Node(kind: .identifier, contents: .text(label.element.text ?? ""))
            }
            return Node(kind: .firstElementMarker)
        }
        return try require(pop())
    }

    private mutating func popFunctionParamLabels(type: Node) throws(DemanglingError) -> Node? {
        if !isOldFunctionTypeMangling && pop(kind: .emptyList) != nil {
            return Node(kind: .labelList)
        }

        guard type.kind == .type else { return nil }

        let topFuncType = try require(type.children.first)
        let funcType: Node
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
        if funcType.children.at(firstChildIndex)?.kind == .nonIsolatedCallerFunctionType {
            firstChildIndex += 1
        }
        if funcType.children.at(firstChildIndex)?.kind == .differentiableFunctionType {
            firstChildIndex += 1
        }
        if funcType.children.at(firstChildIndex)?.kind == .throwsAnnotation || funcType.children.at(firstChildIndex)?.kind == .typedThrowsAnnotation {
            firstChildIndex += 1
        }
        if funcType.children.at(firstChildIndex)?.kind == .concurrentFunctionType {
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
        guard !isOldFunctionTypeMangling, let tuple = possibleTuple, tuple.kind == .tuple else {
            return Node(kind: .labelList)
        }

        var hasLabels = false
        var children = [Node]()
        for i in 0 ..< numParams {
            let label = try getLabel(params: tuple, idx: Int(i))
            try require(label.kind == .identifier || label.kind == .firstElementMarker)
            children.append(label)
            hasLabels = hasLabels || (label.kind != .firstElementMarker)
        }

        if !hasLabels {
            return Node(kind: .labelList)
        }

        return Node(kind: .labelList, children: isOldFunctionTypeMangling ? children : children.reversed())
    }

    private mutating func popTuple() throws(DemanglingError) -> Node {
        let root = Node(kind: .tuple)
        if pop(kind: .emptyList) == nil {
            var firstElem = false
            repeat {
                firstElem = pop(kind: .firstElementMarker) != nil
                let tupleElement = Node(kind: .tupleElement)
                if let variadicMarker = pop(kind: .variadicMarker) {
                    tupleElement.addChild(variadicMarker)
                }
                if let ident = pop(kind: .identifier), case .text(let text) = ident.contents {
                    tupleElement.addChild(Node(kind: .tupleElementName, contents: .text(text)))
                }
                try tupleElement.addChild(require(pop(kind: .type)))
                root.addChild(tupleElement)
            } while !firstElem
            root.reverseChildren()
        }
        return Node(kind: .type, child: root)
    }

    private mutating func popPack(kind: Node.Kind = .pack) throws(DemanglingError) -> Node {
        if pop(kind: .emptyList) != nil {
            return Node(kind: .type, child: Node(kind: .pack))
        }
        var firstElem = false
        var children = [Node]()
        repeat {
            firstElem = pop(kind: .firstElementMarker) != nil
            try children.append(require(pop(kind: .type)))
        } while !firstElem
        children.reverse()
        return Node(kind: .type, child: Node(kind: .pack, children: children))
    }

    private mutating func popSilPack() throws(DemanglingError) -> Node {
        switch try scanner.readScalar() {
        case "d": return try popPack(kind: .silPackDirect)
        case "i": return try popPack(kind: .silPackIndirect)
        default: throw failure
        }
    }

    private mutating func popTypeList() throws(DemanglingError) -> Node {
        var children: [Node] = []
        if pop(kind: .emptyList) == nil {
            var firstElem = false
            repeat {
                firstElem = pop(kind: .firstElementMarker) != nil
                try children.insert(require(pop(kind: .type)), at: 0)
            } while !firstElem
        }
        return Node(kind: .typeList, children: children)
    }

    private mutating func popProtocol() throws(DemanglingError) -> Node {
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
        return Node(typeWithChildKind: .protocol, childChildren: [context, name])
    }

    private mutating func popAnyProtocolConformanceList() throws(DemanglingError) -> Node {
        let conformanceList = Node(kind: .anyProtocolConformanceList)
        if pop(kind: .emptyList) == nil {
            var firstElem = false
            repeat {
                firstElem = pop(kind: .firstElementMarker) != nil
                try conformanceList.addChild(require(popAnyProtocolConformance()))
            } while !firstElem
            conformanceList.reverseChildren()
        }
        return conformanceList
    }

    private mutating func popAnyProtocolConformance() -> Node? {
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

    private mutating func demangleRetroactiveProtocolConformanceRef() throws(DemanglingError) -> Node {
        let module = try require(popModule())
        let proto = try require(popProtocol())
        return Node(kind: .protocolConformanceRefInOtherModule, children: [proto, module])
    }

    private mutating func demangleConcreteProtocolConformance() throws(DemanglingError) -> Node {
        do {
            let conditionalConformanceList = try require(popAnyProtocolConformanceList())
            let conformanceRef = try pop(kind: .protocolConformanceRefInTypeModule) ?? pop(kind: .protocolConformanceRefInProtocolModule) ?? demangleRetroactiveProtocolConformanceRef()
            return try Node(kind: .concreteProtocolConformance, children: [require(pop(kind: .type)), conformanceRef, conditionalConformanceList])
        } catch {
            throw error as! DemanglingError
        }
    }

    private mutating func popDependentProtocolConformance() -> Node? {
        return pop { kind in
            switch kind {
            case .dependentProtocolConformanceRoot,
                 .dependentProtocolConformanceInherited,
                 .dependentProtocolConformanceAssociated: return true
            default: return false
            }
        }
    }

    private mutating func demangleDependentProtocolConformanceRoot() throws(DemanglingError) -> Node {
        let index = try demangleDependentConformanceIndex()
        let prot = try popProtocol()
        return try Node(kind: .dependentProtocolConformanceRoot, children: [require(pop(kind: .type)), prot, index])
    }

    private mutating func demangleDependentProtocolConformanceInherited() throws(DemanglingError) -> Node {
        let index = try demangleDependentConformanceIndex()
        let prot = try popProtocol()
        let nested = try require(popDependentProtocolConformance())
        return Node(kind: .dependentProtocolConformanceInherited, children: [nested, prot, index])
    }

    private mutating func popDependentAssociatedConformance() throws(DemanglingError) -> Node {
        let prot = try popProtocol()
        let dependentType = try require(pop(kind: .type))
        return Node(kind: .dependentAssociatedConformance, children: [dependentType, prot])
    }

    private mutating func demangleDependentProtocolConformanceAssociated() throws(DemanglingError) -> Node {
        let index = try demangleDependentConformanceIndex()
        let assoc = try popDependentAssociatedConformance()
        let nested = try require(popDependentProtocolConformance())
        return Node(kind: .dependentProtocolConformanceAssociated, children: [nested, assoc, index])
    }

    private mutating func demangleDependentConformanceIndex() throws(DemanglingError) -> Node {
        let index = try demangleIndex()
        if index == 1 {
            return Node(kind: .unknownIndex)
        }
        return Node(kind: .index, contents: .index(index - 2))
    }

    private mutating func demangleDependentProtocolConformanceOpaque() throws(DemanglingError) -> Node {
        let type = try require(pop(kind: .type))
        let conformance = try require(popDependentProtocolConformance())
        return Node(kind: .dependentProtocolConformanceOpaque, children: [conformance, type])
    }

    private mutating func popModule() -> Node? {
        if let ident = pop(kind: .identifier) {
            return ident.changeKind(.module)
        } else {
            return pop(kind: .module)
        }
    }

    private mutating func popContext() throws(DemanglingError) -> Node {
        if let mod = popModule() {
            return mod
        } else if let type = pop(kind: .type) {
            let child = try require(type.children.first)
            try require(child.kind.isContext)
            return child
        }
        return try require(pop { $0.isContext })
    }

    private mutating func popTypeAndGetChild() throws(DemanglingError) -> Node {
        return try require(pop(kind: .type)?.children.first)
    }

    private mutating func popTypeAndGetAnyGeneric() throws(DemanglingError) -> Node {
        let child = try popTypeAndGetChild()
        try require(child.kind.isAnyGeneric)
        return child
    }

    private mutating func popAssociatedTypeName() throws(DemanglingError) -> Node {
        let maybeProto = pop(kind: .type)
        let proto: Node?
        if let p = maybeProto {
            try require(p.isProtocol)
            proto = p
        } else {
            proto = pop(kind: .protocolSymbolicReference) ?? pop(kind: .objectiveCProtocolSymbolicReference)
        }

        let id = try require(pop(kind: .identifier))
        if let p = proto {
            return Node(kind: .dependentAssociatedTypeRef, children: [id, p])
        } else {
            return Node(kind: .dependentAssociatedTypeRef, child: id)
        }
    }

    private mutating func popAssociatedTypePath() throws(DemanglingError) -> Node {
        var firstElem = false
        var assocTypePath = [Node]()
        repeat {
            firstElem = pop(kind: .firstElementMarker) != nil
            try assocTypePath.append(require(popAssociatedTypeName()))
        } while !firstElem
        return Node(kind: .assocTypePath, children: assocTypePath.reversed())
    }

    private mutating func popProtocolConformance() throws(DemanglingError) -> Node {
        let genSig = pop(kind: .dependentGenericSignature)
        let module = try require(popModule())
        let proto = try popProtocol()
        var type = pop(kind: .type)
        var ident: Node? = nil
        if type == nil {
            ident = pop(kind: .identifier)
            type = pop(kind: .type)
        }
        if let gs = genSig {
            type = try Node(typeWithChildKind: .dependentGenericType, childChildren: [gs, require(type)])
        }
        var children = try [require(type), proto, module]
        if let i = ident {
            children.append(i)
        }
        return Node(kind: .protocolConformance, children: children)
    }

    private mutating func getDependentGenericParamType(depth: Int, index: Int) throws(DemanglingError) -> Node {
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

        return Node(kind: .dependentGenericParamType, contents: .text(name), children: [
            Node(kind: .index, contents: .index(UInt64(depth))),
            Node(kind: .index, contents: .index(UInt64(index))),
        ])
    }

    private mutating func demangleStandardSubstitution() throws(DemanglingError) -> Node {
        switch try scanner.readScalar() {
        case "o": return Node(kind: .module, contents: .text(objcModule))
        case "C": return Node(kind: .module, contents: .text(cModule))
        case "g":
            let op = try Node(typeWithChildKind: .boundGenericEnum, childChildren: [
                Node(swiftStdlibTypeKind: .enum, name: "Optional"),
                Node(kind: .typeList, child: require(pop(kind: .type))),
            ])
            substitutions.append(op)
            return op
        default:
            try scanner.backtrack()
            let repeatCount = try demangleNatural() ?? 0
            try require(repeatCount <= maxRepeatCount)
            let secondLevel = scanner.conditional(scalar: "c")
            let nd: Node
            if secondLevel {
                switch try scanner.readScalar() {
                case "A": nd = Node(swiftStdlibTypeKind: .protocol, name: "Actor")
                case "C": nd = Node(swiftStdlibTypeKind: .structure, name: "CheckedContinuation")
                case "c": nd = Node(swiftStdlibTypeKind: .structure, name: "UnsafeContinuation")
                case "E": nd = Node(swiftStdlibTypeKind: .structure, name: "CancellationError")
                case "e": nd = Node(swiftStdlibTypeKind: .structure, name: "UnownedSerialExecutor")
                case "F": nd = Node(swiftStdlibTypeKind: .protocol, name: "Executor")
                case "f": nd = Node(swiftStdlibTypeKind: .protocol, name: "SerialExecutor")
                case "G": nd = Node(swiftStdlibTypeKind: .structure, name: "TaskGroup")
                case "g": nd = Node(swiftStdlibTypeKind: .structure, name: "ThrowingTaskGroup")
                case "h": nd = Node(swiftStdlibTypeKind: .protocol, name: "TaskExecutor")
                case "I": nd = Node(swiftStdlibTypeKind: .protocol, name: "AsyncIteratorProtocol")
                case "i": nd = Node(swiftStdlibTypeKind: .protocol, name: "AsyncSequence")
                case "J": nd = Node(swiftStdlibTypeKind: .structure, name: "UnownedJob")
                case "M": nd = Node(swiftStdlibTypeKind: .class, name: "MainActor")
                case "P": nd = Node(swiftStdlibTypeKind: .structure, name: "TaskPriority")
                case "S": nd = Node(swiftStdlibTypeKind: .structure, name: "AsyncStream")
                case "s": nd = Node(swiftStdlibTypeKind: .structure, name: "AsyncThrowingStream")
                case "T": nd = Node(swiftStdlibTypeKind: .structure, name: "Task")
                case "t": nd = Node(swiftStdlibTypeKind: .structure, name: "UnsafeCurrentTask")
                default: throw failure
                }
            } else {
                switch try scanner.readScalar() {
                case "a": nd = Node(swiftStdlibTypeKind: .structure, name: "Array")
                case "A": nd = Node(swiftStdlibTypeKind: .structure, name: "AutoreleasingUnsafeMutablePointer")
                case "b": nd = Node(swiftStdlibTypeKind: .structure, name: "Bool")
                case "c": nd = Node(swiftStdlibTypeKind: .structure, name: "UnicodeScalar")
                case "D": nd = Node(swiftStdlibTypeKind: .structure, name: "Dictionary")
                case "d": nd = Node(swiftStdlibTypeKind: .structure, name: "Double")
                case "f": nd = Node(swiftStdlibTypeKind: .structure, name: "Float")
                case "h": nd = Node(swiftStdlibTypeKind: .structure, name: "Set")
                case "I": nd = Node(swiftStdlibTypeKind: .structure, name: "DefaultIndices")
                case "i": nd = Node(swiftStdlibTypeKind: .structure, name: "Int")
                case "J": nd = Node(swiftStdlibTypeKind: .structure, name: "Character")
                case "N": nd = Node(swiftStdlibTypeKind: .structure, name: "ClosedRange")
                case "n": nd = Node(swiftStdlibTypeKind: .structure, name: "Range")
                case "O": nd = Node(swiftStdlibTypeKind: .structure, name: "ObjectIdentifier")
                case "p": nd = Node(swiftStdlibTypeKind: .structure, name: "UnsafeMutablePointer")
                case "P": nd = Node(swiftStdlibTypeKind: .structure, name: "UnsafePointer")
                case "R": nd = Node(swiftStdlibTypeKind: .structure, name: "UnsafeBufferPointer")
                case "r": nd = Node(swiftStdlibTypeKind: .structure, name: "UnsafeMutableBufferPointer")
                case "S": nd = Node(swiftStdlibTypeKind: .structure, name: "String")
                case "s": nd = Node(swiftStdlibTypeKind: .structure, name: "Substring")
                case "u": nd = Node(swiftStdlibTypeKind: .structure, name: "UInt")
                case "v": nd = Node(swiftStdlibTypeKind: .structure, name: "UnsafeMutableRawPointer")
                case "V": nd = Node(swiftStdlibTypeKind: .structure, name: "UnsafeRawPointer")
                case "W": nd = Node(swiftStdlibTypeKind: .structure, name: "UnsafeRawBufferPointer")
                case "w": nd = Node(swiftStdlibTypeKind: .structure, name: "UnsafeMutableRawBufferPointer")
                case "q": nd = Node(swiftStdlibTypeKind: .enum, name: "Optional")
                case "B": nd = Node(swiftStdlibTypeKind: .protocol, name: "BinaryFloatingPoint")
                case "E": nd = Node(swiftStdlibTypeKind: .protocol, name: "Encodable")
                case "e": nd = Node(swiftStdlibTypeKind: .protocol, name: "Decodable")
                case "F": nd = Node(swiftStdlibTypeKind: .protocol, name: "FloatingPoint")
                case "G": nd = Node(swiftStdlibTypeKind: .protocol, name: "RandomNumberGenerator")
                case "H": nd = Node(swiftStdlibTypeKind: .protocol, name: "Hashable")
                case "j": nd = Node(swiftStdlibTypeKind: .protocol, name: "Numeric")
                case "K": nd = Node(swiftStdlibTypeKind: .protocol, name: "BidirectionalCollection")
                case "k": nd = Node(swiftStdlibTypeKind: .protocol, name: "RandomAccessCollection")
                case "L": nd = Node(swiftStdlibTypeKind: .protocol, name: "Comparable")
                case "l": nd = Node(swiftStdlibTypeKind: .protocol, name: "Collection")
                case "M": nd = Node(swiftStdlibTypeKind: .protocol, name: "MutableCollection")
                case "m": nd = Node(swiftStdlibTypeKind: .protocol, name: "RangeReplaceableCollection")
                case "Q": nd = Node(swiftStdlibTypeKind: .protocol, name: "Equatable")
                case "T": nd = Node(swiftStdlibTypeKind: .protocol, name: "Sequence")
                case "t": nd = Node(swiftStdlibTypeKind: .protocol, name: "IteratorProtocol")
                case "U": nd = Node(swiftStdlibTypeKind: .protocol, name: "UnsignedInteger")
                case "X": nd = Node(swiftStdlibTypeKind: .protocol, name: "RangeExpression")
                case "x": nd = Node(swiftStdlibTypeKind: .protocol, name: "Strideable")
                case "Y": nd = Node(swiftStdlibTypeKind: .protocol, name: "RawRepresentable")
                case "y": nd = Node(swiftStdlibTypeKind: .protocol, name: "StringProtocol")
                case "Z": nd = Node(swiftStdlibTypeKind: .protocol, name: "SignedInteger")
                case "z": nd = Node(swiftStdlibTypeKind: .protocol, name: "BinaryInteger")
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

    private mutating func demangleIdentifier() throws(DemanglingError) -> Node {
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
                try identifier.append(Punycode.decodePunycode(text))
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
        let result = Node(kind: .identifier, contents: .text(identifier))
        substitutions.append(result)
        return result
    }

    private mutating func demangleOperatorIdentifier() throws(DemanglingError) -> Node {
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
        case "i": return Node(kind: .infixOperator, contents: .text(str))
        case "p": return Node(kind: .prefixOperator, contents: .text(str))
        case "P": return Node(kind: .postfixOperator, contents: .text(str))
        default: throw failure
        }
    }

    private mutating func demangleLocalIdentifier() throws(DemanglingError) -> Node {
        let c = try scanner.readScalar()
        switch c {
        case "L":
            let discriminator = try require(pop(kind: .identifier))
            let name = try require(pop(where: { $0.isDeclName }))
            return Node(kind: .privateDeclName, children: [discriminator, name])
        case "l":
            let discriminator = try require(pop(kind: .identifier))
            return Node(kind: .privateDeclName, children: [discriminator])
        case "a" ... "j",
             "A" ... "J":
            return try Node(kind: .relatedEntityDeclName, children: [
                Node(kind: .identifier, contents: .text(String(c))),
                require(pop()),
            ])
        default:
            try scanner.backtrack()
            let discriminator = try demangleIndexAsName()
            let name = try require(pop(where: { $0.isDeclName }))
            return Node(kind: .localDeclName, children: [discriminator, name])
        }
    }

    private mutating func demangleBuiltinType() throws(DemanglingError) -> Node {
        let maxTypeSize: UInt64 = 4096
        switch try scanner.readScalar() {
        case "b": return Node(swiftBuiltinType: .builtinTypeName, name: "Builtin.BridgeObject")
        case "B": return Node(swiftBuiltinType: .builtinTypeName, name: "Builtin.UnsafeValueBuffer")
        case "e": return Node(swiftBuiltinType: .builtinTypeName, name: "Builtin.Executor")
        case "f":
            let size = try demangleIndex() - 1
            try require(size > 0 && size <= maxTypeSize)
            return Node(swiftBuiltinType: .builtinTypeName, name: "Builtin.FPIEEE\(size)")
        case "i":
            let size = try demangleIndex() - 1
            try require(size > 0 && size <= maxTypeSize)
            return Node(swiftBuiltinType: .builtinTypeName, name: "Builtin.Int\(size)")
        case "I": return Node(swiftBuiltinType: .builtinTypeName, name: "Builtin.IntLiteral")
        case "v":
            let elts = try demangleIndex() - 1
            try require(elts > 0 && elts <= maxTypeSize)
            let eltType = try popTypeAndGetChild()
            let text = try require(eltType.text)
            try require(eltType.kind == .builtinTypeName && text.starts(with: "Builtin.") == true)
            let name = text["Builtin.".endIndex...]
            return Node(swiftBuiltinType: .builtinTypeName, name: "Builtin.Vec\(elts)x\(name)")
        case "V":
            let element = try require(pop(kind: .type))
            let size = try require(pop(kind: .type))
            return Node(typeWithChildKind: .builtinFixedArray, childChildren: [size, element])
        case "O": return Node(swiftBuiltinType: .builtinTypeName, name: "Builtin.UnknownObject")
        case "o": return Node(swiftBuiltinType: .builtinTypeName, name: "Builtin.NativeObject")
        case "p": return Node(swiftBuiltinType: .builtinTypeName, name: "Builtin.RawPointer")
        case "t": return Node(swiftBuiltinType: .builtinTypeName, name: "Builtin.SILToken")
        case "w": return Node(swiftBuiltinType: .builtinTypeName, name: "Builtin.Word")
        case "c": return Node(swiftBuiltinType: .builtinTypeName, name: "Builtin.RawUnsafeContinuation")
        case "D": return Node(swiftBuiltinType: .builtinTypeName, name: "Builtin.DefaultActorStorage")
        case "d": return Node(swiftBuiltinType: .builtinTypeName, name: "Builtin.NonDefaultDistributedActorStorage")
        case "j": return Node(swiftBuiltinType: .builtinTypeName, name: "Builtin.Job")
        case "P": return Node(swiftBuiltinType: .builtinTypeName, name: "Builtin.PackIndex")
        default: throw failure
        }
    }

    private mutating func demangleAnyGenericType(kind: Node.Kind) throws(DemanglingError) -> Node {
        let name = try require(pop(where: { $0.isDeclName }))
        let ctx = try popContext()
        let type = Node(typeWithChildKind: kind, childChildren: [ctx, name])
        substitutions.append(type)
        return type
    }

    private mutating func demangleExtensionContext() throws(DemanglingError) -> Node {
        let genSig = pop(kind: .dependentGenericSignature)
        let module = try require(popModule())
        let type = try popTypeAndGetAnyGeneric()
        if let g = genSig {
            return Node(kind: .extension, children: [module, type, g])
        } else {
            return Node(kind: .extension, children: [module, type])
        }
    }

    private func getParentId(parent: Node, flavor: ManglingFlavor) -> String {
        return "{ParentId}"
    }

    private mutating func setParentForOpaqueReturnTypeNodes(visited: Node, parentId: String) {
        if visited.kind == .opaqueReturnType {
            if visited.children.last?.kind == .opaqueReturnTypeParent {
                return
            }
            visited.addChild(Node(kind: .opaqueReturnTypeParent, contents: .text(parentId)))
            return
        }

        switch visited.kind {
        case .function,
             .variable,
             .subscript: return
        default: break
        }

        for index in visited.children.indices {
            setParentForOpaqueReturnTypeNodes(visited: visited.children[index], parentId: parentId)
        }
    }

    private mutating func demanglePlainFunction() throws(DemanglingError) -> Node {
        let genSig = pop(kind: .dependentGenericSignature)
        var type = try popFunctionType(kind: .functionType)
        let labelList = try popFunctionParamLabels(type: type)

        if let g = genSig {
            type = Node(typeWithChildKind: .dependentGenericType, childChildren: [g, type])
        }
        let name = try require(pop(where: { $0.isDeclName }))
        let ctx = try popContext()
        if let ll = labelList {
            return Node(kind: .function, children: [ctx, name, ll, type])
        }
        return Node(kind: .function, children: [ctx, name, type])
    }

    private mutating func demangleRetroactiveConformance() throws(DemanglingError) -> Node {
        let index = try demangleIndexAsName()
        let conformance = try require(popAnyProtocolConformance())
        return Node(kind: .retroactiveConformance, children: [index, conformance])
    }

    private mutating func demangleBoundGenericType() throws(DemanglingError) -> Node {
        let (array, retroactiveConformances) = try demangleBoundGenerics()
        let nominal = try popTypeAndGetAnyGeneric()
        let boundNode = try demangleBoundGenericArgs(nominal: nominal, array: array, index: 0)
        if let retroactiveConformances {
            boundNode.addChild(retroactiveConformances)
        }
        let type = Node(kind: .type, child: boundNode)
        substitutions.append(type)
        return type
    }

    private mutating func popRetroactiveConformances() throws(DemanglingError) -> Node? {
        var retroactiveConformances: [Node] = []
        while let conformance = pop(kind: .retroactiveConformance) {
            retroactiveConformances.append(conformance)
        }
        retroactiveConformances = retroactiveConformances.reversed()
        return retroactiveConformances.isEmpty ? nil : Node(kind: .typeList, children: retroactiveConformances)
    }

    private mutating func demangleBoundGenerics() throws(DemanglingError) -> (typeLists: [Node], conformances: Node?) {
        let retroactiveConformances = try popRetroactiveConformances()

        var array = [Node]()
        while true {
            let typeList = Node(kind: .typeList)
            array.append(typeList)
            while let t = pop(kind: .type) {
                typeList.addChild(t)
            }
            typeList.reverseChildren()

            if pop(kind: .emptyList) != nil {
                break
            } else {
                _ = try require(pop(kind: .firstElementMarker))
            }
        }

        return (array, retroactiveConformances)
    }

    private mutating func demangleBoundGenericArgs(nominal: Node, array: [Node], index: Int) throws(DemanglingError) -> Node {
        if nominal.kind == .typeSymbolicReference || nominal.kind == .protocolSymbolicReference {
            let remaining = array.reversed().flatMap { $0.children }
            return Node(kind: .boundGenericOtherNominalType, children: [Node(kind: .type, child: nominal), Node(kind: .typeList, children: remaining)])
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

        let n: Node
        let offsetIndex = index + (consumesGenericArgs ? 1 : 0)
        if offsetIndex < array.count {
            var boundParent: Node
            if context.kind == .extension {
                let p = try demangleBoundGenericArgs(nominal: require(context.children.at(1)), array: array, index: offsetIndex)
                boundParent = try Node(kind: .extension, children: [require(context.children.first), p])
                if let thirdChild = context.children.at(2) {
                    boundParent.addChild(thirdChild)
                }
            } else {
                boundParent = try demangleBoundGenericArgs(nominal: context, array: array, index: offsetIndex)
            }
            n = Node(kind: nominal.kind, children: [boundParent] + nominal.children.dropFirst())
        } else {
            n = nominal
        }

        if !consumesGenericArgs || args.children.count == 0 {
            return n
        }

        let kind: Node.Kind
        switch n.kind {
        case .class: kind = .boundGenericClass
        case .structure: kind = .boundGenericStructure
        case .enum: kind = .boundGenericEnum
        case .protocol: kind = .boundGenericProtocol
        case .otherNominalType: kind = .boundGenericOtherNominalType
        case .typeAlias: kind = .boundGenericTypeAlias
        case .function,
             .constructor: return Node(kind: .boundGenericFunction, children: [n, args])
        default: throw failure
        }

        return Node(kind: kind, children: [Node(kind: .type, child: n), args])
    }

    private mutating func demangleImplParamConvention(kind: Node.Kind) throws(DemanglingError) -> Node? {
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
        return Node(kind: kind, child: Node(kind: .implConvention, contents: .text(attr)))
    }

    private mutating func demangleImplResultConvention(kind: Node.Kind) throws(DemanglingError) -> Node? {
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
        return Node(kind: kind, child: Node(kind: .implConvention, contents: .text(attr)))
    }

    private mutating func demangleImplParameterSending() -> Node? {
        guard scanner.conditional(scalar: "T") else {
            return nil
        }
        return Node(kind: .implParameterSending, contents: .text("sending"))
    }

    private mutating func demangleImplParameterIsolated() -> Node? {
        guard scanner.conditional(scalar: "I") else { return nil }
        return Node(kind: .implParameterIsolated, contents: .text("isolated"))
    }

    private mutating func demangleImplParameterImplicitLeading() -> Node? {
        guard scanner.conditional(scalar: "L") else { return nil }
        return Node(kind: .implParameterIsolated, contents: .text("sil_implicit_leading_param"))
    }

    private mutating func demangleImplResultDifferentiability() -> Node {
        return Node(kind: .implParameterResultDifferentiability, contents: .text(scanner.conditional(scalar: "w") ? "@noDerivative" : ""))
    }

    private mutating func demangleClangType() throws(DemanglingError) -> Node {
        let numChars = try require(demangleNatural())
        let text = try scanner.readScalars(count: Int(numChars))
        return Node(kind: .clangType, contents: .text(text))
    }

    private mutating func demangleImplFunctionType() throws(DemanglingError) -> Node {
        var typeChildren = [Node]()
        if scanner.conditional(scalar: "s") {
            let (substitutions, conformances) = try demangleBoundGenerics()
            let sig = try require(pop(kind: .dependentGenericSignature))
            let subsNode = try Node(kind: .implPatternSubstitutions, children: [sig, require(substitutions.first)])
            if let conformances {
                subsNode.addChild(conformances)
            }
            typeChildren.append(subsNode)
        }

        if scanner.conditional(scalar: "I") {
            let (substitutions, conformances) = try demangleBoundGenerics()
            let subsNode = try Node(kind: .implInvocationSubstitutions, children: [require(substitutions.first)])
            if let conformances {
                subsNode.addChild(conformances)
            }
            typeChildren.append(subsNode)
        }

        var genSig = pop(kind: .dependentGenericSignature)
        if let g = genSig, scanner.conditional(scalar: "P") {
            genSig = g.changeKind(.dependentPseudogenericSignature)
        }

        if scanner.conditional(scalar: "e") {
            typeChildren.append(Node(kind: .implEscaping))
        }

        if scanner.conditional(scalar: "A") {
            typeChildren.append(Node(kind: .implErasedIsolation))
        }

        if let peek = scanner.peek(), let differentiability = Differentiability(rawValue: peek) {
            try scanner.skip()
            typeChildren.append(Node(kind: .implDifferentiabilityKind, contents: .index(UInt64(differentiability.rawValue))))
        }

        let cAttr: String
        switch try scanner.readScalar() {
        case "y": cAttr = "@callee_unowned"
        case "g": cAttr = "@callee_guaranteed"
        case "x": cAttr = "@callee_owned"
        case "t": cAttr = "@convention(thin)"
        default: throw failure
        }
        typeChildren.append(Node(kind: .implConvention, contents: .text(cAttr)))

        let fConv: String?
        var hasClangType = false
        switch try scanner.readScalar() {
        case "B": fConv = "block"
        case "C": fConv = "c"
        case "z":
            switch try scanner.readScalar() {
            case "B":
                hasClangType = true
                fConv = "block"
            case "C":
                hasClangType = true
                fConv = "c"
            default:
                try scanner.backtrack()
                try scanner.backtrack()
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
            let node = Node(kind: .implFunctionConvention, child: Node(kind: .implFunctionConventionName, contents: .text(fConv)))
            if hasClangType {
                try node.addChild(demangleClangType())
            }
            typeChildren.append(node)
        }

        if scanner.conditional(scalar: "A") {
            typeChildren.append(Node(kind: .implCoroutineKind, contents: .text("yield_once")))
        } else if scanner.conditional(scalar: "I") {
            typeChildren.append(Node(kind: .implCoroutineKind, contents: .text("yield_once_2")))
        } else if scanner.conditional(scalar: "G") {
            typeChildren.append(Node(kind: .implCoroutineKind, contents: .text("yield_many")))
        }

        if scanner.conditional(scalar: "h") {
            typeChildren.append(Node(kind: .implFunctionAttribute, contents: .text("@Sendable")))
        }

        if scanner.conditional(scalar: "H") {
            typeChildren.append(Node(kind: .implFunctionAttribute, contents: .text("@async")))
        }

        if scanner.conditional(scalar: "T") {
            typeChildren.append(Node(kind: .implSendingResult))
        }

        if let g = genSig {
            typeChildren.append(g)
        }

        var numTypesToAdd = 0
        while let param = try demangleImplParamConvention(kind: .implParameter) {
            param.addChild(demangleImplResultDifferentiability())
            if let sending = demangleImplParameterSending() {
                param.addChild(sending)
            }

            if let sending = demangleImplParameterIsolated() {
                param.addChild(sending)
            }

            if let sending = demangleImplParameterImplicitLeading() {
                param.addChild(sending)
            }

            typeChildren.append(param)
            numTypesToAdd += 1
        }
        while let result = try demangleImplResultConvention(kind: .implResult) {
            result.addChild(demangleImplResultDifferentiability())
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
            try typeChildren[typeChildren.count - i - 1].addChild(require(pop(kind: .type)))
        }

        return Node(typeWithChildKind: .implFunctionType, childChildren: typeChildren)
    }

    private mutating func demangleMetatype() throws(DemanglingError) -> Node {
        switch try scanner.readScalar() {
        case "a": return try Node(kind: .typeMetadataAccessFunction, child: require(pop(kind: .type)))
        case "A": return try Node(kind: .reflectionMetadataAssocTypeDescriptor, child: popProtocolConformance())
        case "b": return try Node(kind: .canonicalSpecializedGenericTypeMetadataAccessFunction, child: require(pop(kind: .type)))
        case "B": return try Node(kind: .reflectionMetadataBuiltinDescriptor, child: require(pop(kind: .type)))
        case "c": return try Node(kind: .protocolConformanceDescriptor, child: require(popProtocolConformance()))
        case "C":
            let t = try require(pop(kind: .type))
            try require(t.children.first?.kind.isAnyGeneric == true)
            return try Node(kind: .reflectionMetadataSuperclassDescriptor, child: require(t.children.first))
        case "D": return try Node(kind: .typeMetadataDemanglingCache, child: require(pop(kind: .type)))
        case "f": return try Node(kind: .fullTypeMetadata, child: require(pop(kind: .type)))
        case "F": return try Node(kind: .reflectionMetadataFieldDescriptor, child: require(pop(kind: .type)))
        case "g": return try Node(kind: .opaqueTypeDescriptorAccessor, child: require(pop()))
        case "h": return try Node(kind: .opaqueTypeDescriptorAccessorImpl, child: require(pop()))
        case "i": return try Node(kind: .typeMetadataInstantiationFunction, child: require(pop(kind: .type)))
        case "I": return try Node(kind: .typeMetadataInstantiationCache, child: require(pop(kind: .type)))
        case "j": return try Node(kind: .opaqueTypeDescriptorAccessorKey, child: require(pop()))
        case "J": return try Node(kind: .noncanonicalSpecializedGenericTypeMetadataCache, child: require(pop()))
        case "k": return try Node(kind: .opaqueTypeDescriptorAccessorVar, child: require(pop()))
        case "K": return try Node(kind: .metadataInstantiationCache, child: require(pop()))
        case "l": return try Node(kind: .typeMetadataSingletonInitializationCache, child: require(pop(kind: .type)))
        case "L": return try Node(kind: .typeMetadataLazyCache, child: require(pop(kind: .type)))
        case "m": return try Node(kind: .metaclass, child: require(pop(kind: .type)))
        case "M": return try Node(kind: .canonicalSpecializedGenericMetaclass, child: require(pop(kind: .type)))
        case "n": return try Node(kind: .nominalTypeDescriptor, child: require(pop(kind: .type)))
        case "N": return try Node(kind: .noncanonicalSpecializedGenericTypeMetadata, child: require(pop(kind: .type)))
        case "o": return try Node(kind: .classMetadataBaseOffset, child: require(pop(kind: .type)))
        case "p": return try Node(kind: .protocolDescriptor, child: popProtocol())
        case "P": return try Node(kind: .genericTypeMetadataPattern, child: require(pop(kind: .type)))
        case "q": return try Node(kind: .uniquable, child: require(pop()))
        case "Q": return try Node(kind: .opaqueTypeDescriptor, child: require(pop()))
        case "r": return try Node(kind: .typeMetadataCompletionFunction, child: require(pop(kind: .type)))
        case "s": return try Node(kind: .objCResilientClassStub, child: require(pop(kind: .type)))
        case "S": return try Node(kind: .protocolSelfConformanceDescriptor, child: popProtocol())
        case "t": return try Node(kind: .fullObjCResilientClassStub, child: require(pop(kind: .type)))
        case "u": return try Node(kind: .methodLookupFunction, child: require(pop(kind: .type)))
        case "U": return try Node(kind: .objCMetadataUpdateFunction, child: require(pop(kind: .type)))
        case "V": return try Node(kind: .propertyDescriptor, child: require(pop { $0.isEntity }))
        case "X": return try demanglePrivateContextDescriptor()
        case "z": return try Node(kind: .canonicalPrespecializedGenericTypeCachingOnceToken, child: require(pop(kind: .type)))
        default: throw failure
        }
    }

    private mutating func demanglePrivateContextDescriptor() throws(DemanglingError) -> Node {
        switch try scanner.readScalar() {
        case "E": return try Node(kind: .extensionDescriptor, child: popContext())
        case "M": return try Node(kind: .moduleDescriptor, child: require(popModule()))
        case "Y":
            let discriminator = try require(pop())
            let context = try popContext()
            return Node(kind: .anonymousDescriptor, children: [context, discriminator])
        case "X": return try Node(kind: .anonymousDescriptor, child: popContext())
        case "A":
            let path = try require(popAssociatedTypePath())
            let base = try require(pop(kind: .type))
            return Node(kind: .associatedTypeGenericParamRef, children: [base, path])
        default: throw failure
        }
    }

    private mutating func demangleArchetype() throws(DemanglingError) -> Node {
        switch try scanner.readScalar() {
        case "a":
            let ident = try require(pop(kind: .identifier))
            let arch = try popTypeAndGetChild()
            let assoc = Node(typeWithChildKind: .associatedTypeRef, childChildren: [arch, ident])
            substitutions.append(assoc)
            return assoc
        case "O":
            return try Node(kind: .opaqueReturnTypeOf, child: popContext())
        case "o":
            let index = try demangleIndex()
            let (boundGenericArgs, retroactiveConformances) = try demangleBoundGenerics()
            let name = try require(pop())
            let opaque = Node(
                kind: .opaqueType,
                children: [
                    name,
                    Node(kind: .index, contents: .index(index)),
                    Node(kind: .typeList, children: boundGenericArgs.reversed()),
                ]
            )
            if let retroactiveConformances {
                opaque.addChild(retroactiveConformances)
            }
            let opaqueType = Node(kind: .type, child: opaque)
            substitutions.append(opaqueType)
            return opaqueType
        case "r":
            return Node(typeWithChildKind: .opaqueReturnType, childChildren: [])
        case "R":
            let index = try demangleIndex()
            return Node(typeWithChildKind: .opaqueReturnType, childChildren: [Node(kind: .opaqueReturnTypeIndex, index: index)])
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
            return Node(kind: .type, child: Node(kind: .packExpansion, children: [pattern, count]))
        case "e":
            let pack = try popTypeAndGetChild()
            let level = try demangleIndex()
            return Node(kind: .type, child: Node(kind: .packElement, children: [pack, Node(kind: .packElementLevel, contents: .index(level))]))
        case "P":
            return try popPack()
        case "S":
            return try popSilPack()
        default: throw failure
        }
    }

    private mutating func demangleAssociatedTypeSimple(index: Node?) throws(DemanglingError) -> Node {
        do {
            let atName = try popAssociatedTypeName()
            let gpi = try index.map { Node(kind: .type, child: $0) } ?? require(pop(kind: .type))
            return Node(typeWithChildKind: .dependentMemberType, childChildren: [gpi, atName])
        } catch {
            throw error as! DemanglingError
        }
    }

    private mutating func demangleAssociatedTypeCompound(index: Node?) throws(DemanglingError) -> Node {
        do {
            var assocTypeNames = [Node]()
            var firstElem = false
            repeat {
                firstElem = pop(kind: .firstElementMarker) != nil
                try assocTypeNames.append(popAssociatedTypeName())
            } while !firstElem

            var base = try index.map { Node(kind: .type, child: $0) } ?? require(pop(kind: .type))
            while let assocType = assocTypeNames.popLast() {
                let depTy = Node(kind: .dependentMemberType, children: [base, assocType])
                base = Node(kind: .type, child: depTy)
            }
            return base
        } catch {
            throw error as! DemanglingError
        }
    }

    private mutating func demangleGenericParamIndex() throws(DemanglingError) -> Node {
        switch try scanner.readScalar() {
        case "d":
            let depth = try demangleIndex() + 1
            let index = try demangleIndex()
            return try getDependentGenericParamType(depth: Int(depth), index: Int(index))
        case "z":
            return try getDependentGenericParamType(depth: 0, index: 0)
        case "s":
            return Node(kind: .constrainedExistentialSelf)
        default:
            try scanner.backtrack()
            return try getDependentGenericParamType(depth: 0, index: Int(demangleIndex() + 1))
        }
    }

    private mutating func demangleThunkOrSpecialization() throws(DemanglingError) -> Node {
        let c = try scanner.readScalar()
        switch c {
        case "T":
            switch try scanner.readScalar() {
            case "I": return try Node(kind: .silThunkIdentity, child: require(pop(where: { $0.isEntity })))
            case "H": return try Node(kind: .silThunkHopToMainActorIfNeeded, child: require(pop(where: { $0.isEntity })))
            default: throw failure
            }
        case "c": return try Node(kind: .curryThunk, child: require(pop(where: { $0.isEntity })))
        case "j": return try Node(kind: .dispatchThunk, child: require(pop(where: { $0.isEntity })))
        case "q": return try Node(kind: .methodDescriptor, child: require(pop(where: { $0.isEntity })))
        case "o": return Node(kind: .objCAttribute)
        case "O": return Node(kind: .nonObjCAttribute)
        case "D": return Node(kind: .dynamicAttribute)
        case "d": return Node(kind: .directMethodReferenceAttribute)
        case "E": return Node(kind: .distributedThunk)
        case "F": return Node(kind: .distributedAccessor)
        case "a": return Node(kind: .partialApplyObjCForwarder)
        case "A": return Node(kind: .partialApplyForwarder)
        case "m": return Node(kind: .mergedFunction)
        case "X": return Node(kind: .dynamicallyReplaceableFunctionVar)
        case "x": return Node(kind: .dynamicallyReplaceableFunctionKey)
        case "I": return Node(kind: .dynamicallyReplaceableFunctionImpl)
        case "Y": return try Node(kind: .asyncSuspendResumePartialFunction, child: demangleIndexAsName())
        case "Q": return try Node(kind: .asyncAwaitResumePartialFunction, child: demangleIndexAsName())
        case "C": return try Node(kind: .coroutineContinuationPrototype, child: require(pop(kind: .type)))
        case "z": fallthrough
        case "Z":
            let flagMode = try demangleIndexAsName()
            let sig = pop(kind: .dependentGenericSignature)
            let resultType = try require(pop(kind: .type))
            let implType = try require(pop(kind: .type))
            let node = Node(kind: c == "z" ? .objCAsyncCompletionHandlerImpl : .predefinedObjCAsyncCompletionHandlerImpl, children: [implType, resultType, flagMode])
            if let sig {
                node.addChild(sig)
            }
            return node
        case "V":
            let base = try require(pop(where: { $0.isEntity }))
            let derived = try require(pop(where: { $0.isEntity }))
            return Node(kind: .vTableThunk, children: [derived, base])
        case "W":
            let entity = try require(pop(where: { $0.isEntity }))
            let conf = try popProtocolConformance()
            return Node(kind: .protocolWitness, children: [conf, entity])
        case "S":
            return try Node(kind: .protocolSelfConformanceWitness, child: require(pop(where: { $0.isEntity })))
        case "R",
             "r",
             "y":
            let kind = switch c {
            case "R": Node.Kind.reabstractionThunkHelper
            case "y": Node.Kind.reabstractionThunkHelperWithSelf
            default: Node.Kind.reabstractionThunk
            }
            let name = Node(kind: kind)
            if let genSig = pop(kind: .dependentGenericSignature) {
                name.addChild(genSig)
            }
            if kind == .reabstractionThunkHelperWithSelf {
                try name.addChild(require(pop(kind: .type)))
            }
            try name.addChild(require(pop(kind: .type)))
            try name.addChild(require(pop(kind: .type)))
            return name
        case "g": return try demangleGenericSpecialization(kind: .genericSpecialization)
        case "G": return try demangleGenericSpecialization(kind: .genericSpecializationNotReAbstracted)
        case "B": return try demangleGenericSpecialization(kind: .genericSpecializationInResilienceDomain)
        case "t": return try demangleGenericSpecializationWithDroppedArguments()
        case "s": return try demangleGenericSpecialization(kind: .genericSpecializationPrespecialized)
        case "i": return try demangleGenericSpecialization(kind: .inlinedGenericFunction)
        case "P",
             "p":
            let spec = try demangleSpecAttributes(kind: c == "P" ? .genericPartialSpecializationNotReAbstracted : .genericPartialSpecialization)
            let param = try Node(kind: .genericSpecializationParam, child: require(pop(kind: .type)))
            spec.addChild(param)
            return spec
        case "f": return try demangleFunctionSpecialization()
        case "K",
             "k":
            let nodeKind: Node.Kind
            if scanner.conditional(string: "mu") {
                nodeKind = .keyPathUnappliedMethodThunkHelper
            } else if scanner.conditional(string: "MA") {
                nodeKind = .keyPathAppliedMethodThunkHelper
            } else {
                nodeKind = c == "K" ? .keyPathGetterThunkHelper : .keyPathSetterThunkHelper
            }

            let isSerialized = scanner.conditional(string: "q")
            var types = [Node]()
            var node = pop(kind: .type)
            repeat {
                if let node {
                    types.append(node)
                }
                node = pop(kind: .type)
            } while node != nil && node?.kind == .type

            var result: Node
            if let n = pop() {
                if n.kind == .dependentGenericSignature {
                    let decl = try require(pop())
                    result = Node(kind: nodeKind, children: [decl, n])
                } else {
                    result = Node(kind: nodeKind, child: n)
                }
            } else {
                throw failure
            }
            for t in types.reversed() {
                result.addChild(t)
            }
            if isSerialized {
                result.addChild(Node(kind: .isSerialized))
            }
            return result
        case "l": return try Node(kind: .associatedTypeDescriptor, child: require(popAssociatedTypeName()))
        case "L": return try Node(kind: .protocolRequirementsBaseDescriptor, child: require(popProtocol()))
        case "M": return try Node(kind: .defaultAssociatedTypeMetadataAccessor, child: require(popAssociatedTypeName()))
        case "n":
            let requirement = try popProtocol()
            let associatedTypePath = try popAssociatedTypePath()
            let protocolType = try require(pop(kind: .type))
            return Node(kind: .associatedConformanceDescriptor, children: [protocolType, associatedTypePath, requirement])
        case "N":
            let requirement = try popProtocol()
            let associatedTypePath = try popAssociatedTypePath()
            let protocolType = try require(pop(kind: .type))
            return Node(kind: .defaultAssociatedConformanceAccessor, children: [protocolType, associatedTypePath, requirement])
        case "b":
            let requirement = try popProtocol()
            let protocolType = try require(pop(kind: .type))
            return Node(kind: .baseConformanceDescriptor, children: [protocolType, requirement])
        case "H",
             "h":
            let nodeKind: Node.Kind = c == "H" ? .keyPathEqualsThunkHelper : .keyPathHashThunkHelper
            let isSerialized = scanner.peek() == "q"
            var types = [Node]()
            let node = try require(pop())
            var genericSig: Node? = nil
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
            let result = Node(kind: nodeKind)
            for t in types.reversed() {
                result.addChild(t)
            }
            if let gs = genericSig {
                result.addChild(gs)
            }
            if isSerialized {
                result.addChild(Node(kind: .isSerialized))
            }
            return result
        case "v":
            let index = try demangleIndex()
            if scanner.conditional(scalar: "r") {
                return Node(kind: .outlinedReadOnlyObject, contents: .index(index))
            } else {
                return Node(kind: .outlinedVariable, contents: .index(index))
            }
        case "e": return try Node(kind: .outlinedBridgedMethod, contents: .text(demangleBridgedMethodParams()))
        case "u": return Node(kind: .asyncFunctionPointer)
        case "U":
            let globalActor = try require(pop(kind: .type))
            let reabstraction = try require(pop())
            return Node(kind: .reabstractionThunkHelperWithGlobalActor, children: [reabstraction, globalActor])
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
            case "b": return Node(kind: .backDeploymentThunk)
            case "B": return Node(kind: .backDeploymentFallback)
            case "c": return Node(kind: .coroFunctionPointer)
            case "d": return Node(kind: .defaultOverride)
            case "S": return Node(kind: .hasSymbolQuery)
            default: throw failure
            }
        default: throw failure
        }
    }

    private mutating func demangleAutoDiffFunctionOrSimpleThunk(kind: Node.Kind) throws(DemanglingError) -> Node {
        let result = Node(kind: kind)
        while let node = pop() {
            result.addChild(node)
        }
        result.reverseChildren()
        let kind = try demangleAutoDiffFunctionKind()
        result.addChild(kind)
        try result.addChild(require(demangleIndexSubset()))
        try scanner.match(scalar: "p")
        try result.addChild(require(demangleIndexSubset()))
        try scanner.match(scalar: "r")
        return result
    }

    private mutating func demangleAutoDiffFunctionKind() throws(DemanglingError) -> Node {
        let kind = try scanner.readScalar()
        guard let autoDiffFunctionKind = AutoDiffFunctionKind(UInt64(kind.value)) else {
            throw failure
        }
        return Node(kind: .autoDiffFunctionKind, contents: .index(UInt64(autoDiffFunctionKind.rawValue.value)))
    }

    private mutating func demangleAutoDiffSubsetParametersThunk() throws(DemanglingError) -> Node {
        let result = Node(kind: .autoDiffSubsetParametersThunk)
        while let node = pop() {
            result.addChild(node)
        }
        result.reverseChildren()
        let kind = try demangleAutoDiffFunctionKind()
        result.addChild(kind)
        try result.addChild(require(demangleIndexSubset()))
        try scanner.match(scalar: "p")
        try result.addChild(require(demangleIndexSubset()))
        try scanner.match(scalar: "r")
        try result.addChild(require(demangleIndexSubset()))
        try scanner.match(scalar: "P")
        return result
    }

    private mutating func demangleAutoDiffSelfReorderingReabstractionThunk() throws(DemanglingError) -> Node {
        let result = Node(kind: .autoDiffSelfReorderingReabstractionThunk)
        if let dependentGenericSignature = pop(kind: .dependentGenericSignature) {
            result.addChild(dependentGenericSignature)
        }
        try result.addChild(require(pop(kind: .type)))
        try result.addChild(require(pop(kind: .type)))
        result.reverseChildren()
        try result.addChild(demangleAutoDiffFunctionKind())
        return result
    }

    private mutating func demangleDifferentiabilityWitness() throws(DemanglingError) -> Node {
        let result = Node(kind: .differentiabilityWitness)
        let optionalGenSig = pop(kind: .dependentGenericSignature)
        while let node = pop() {
            result.addChild(node)
        }
        result.reverseChildren()
        let kind: Differentiability = switch try scanner.readScalar() {
        case "f": .forward
        case "r": .reverse
        case "d": .normal
        case "l": .linear
        default: throw failure
        }
        result.addChild(Node(kind: .index, contents: .index(UInt64(kind.rawValue.value))))
        try result.addChild(require(demangleIndexSubset()))
        try scanner.match(scalar: "p")
        try result.addChild(require(demangleIndexSubset()))
        try scanner.match(scalar: "r")
        if let optionalGenSig {
            result.addChild(optionalGenSig)
        }
        return result
    }

    private mutating func demangleIndexSubset() throws(DemanglingError) -> Node {
        var str = ""
        while let c = scanner.conditional(where: { $0 == "S" || $0 == "U" }) {
            str.unicodeScalars.append(c)
        }
        try require(!str.isEmpty)
        return Node(kind: .indexSubset, contents: .text(str))
    }

    private mutating func demangleDifferentiableFunctionType() throws(DemanglingError) -> Node {
        let kind: Differentiability = switch try scanner.readScalar() {
        case "f": .forward
        case "r": .reverse
        case "d": .normal
        case "l": .linear
        default: throw failure
        }
        return Node(kind: .differentiableFunctionType, contents: .index(UInt64(kind.rawValue.value)))
    }

    private mutating func demangleBridgedMethodParams() throws(DemanglingError) -> String {
        if scanner.conditional(scalar: "_") {
            return ""
        }
        var str = ""
        let kind = try scanner.readScalar()
        switch kind {
        case "o",
             "p",
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

    private mutating func demangleGenericSpecialization(kind: Node.Kind, droppedArguments: Node? = nil) throws(DemanglingError) -> Node {
        let spec = try demangleSpecAttributes(kind: kind)
        if let droppedArguments {
            spec.addChildren(droppedArguments.children)
        }
        let list = try popTypeList()
        for t in list.children {
            spec.addChild(Node(kind: .genericSpecializationParam, child: t))
        }
        return spec
    }

    private mutating func demangleGenericSpecializationWithDroppedArguments() throws(DemanglingError) -> Node {
        try scanner.backtrack()
        let tmp = Node(kind: .genericSpecialization)
        while scanner.conditional(scalar: "t") {
            let n = try demangleNatural().map { Node.Contents.index($0 + 1) } ?? Node.Contents.index(0)
            tmp.addChild(Node(kind: .droppedArgument, contents: n))
        }
        let kind: Node.Kind = switch try scanner.readScalar() {
        case "g": .genericSpecialization
        case "G": .genericSpecializationNotReAbstracted
        case "B": .genericSpecializationInResilienceDomain
        default: throw failure
        }
        return try demangleGenericSpecialization(kind: kind, droppedArguments: tmp)
    }

    private mutating func demangleFunctionSpecialization() throws(DemanglingError) -> Node {
        let spec = try demangleSpecAttributes(kind: .functionSignatureSpecialization, demangleUniqueId: true)
        var paramIdx: UInt64 = 0
        while !scanner.conditional(scalar: "_") {
            try spec.addChild(demangleFuncSpecParam(kind: .functionSignatureSpecializationParam))
            paramIdx += 1
        }
        if !scanner.conditional(scalar: "n") {
            try spec.addChild(demangleFuncSpecParam(kind: .functionSignatureSpecializationReturn))
        }

        for paramIndexPair in spec.children.enumerated().reversed() {
            let param = paramIndexPair.element
            guard param.kind == .functionSignatureSpecializationParam else { continue }
            guard let kindName = param.children.first else { continue }
            guard kindName.kind == .functionSignatureSpecializationParamKind, case .index(let i) = kindName.contents else { throw failure }
            let paramKind = FunctionSigSpecializationParamKind(rawValue: UInt64(i))
            switch paramKind {
            case .constantPropFunction,
                 .constantPropGlobal,
                 .constantPropString,
                 .constantPropKeyPath,
                 .closureProp:
                let fixedChildrenEndIndex = param.children.endIndex
                while let t = pop(kind: .type) {
                    try require(paramKind == .closureProp || paramKind == .constantPropKeyPath)
                    param.insertChild(t, at: fixedChildrenEndIndex)
                }
                let name = try require(pop(kind: .identifier))
                var text = try require(name.text)
                if paramKind == .constantPropString, !text.isEmpty, text.first == "_" {
                    text = String(text.dropFirst())
                }
                param.insertChild(Node(kind: .functionSignatureSpecializationParamPayload, contents: .text(text)), at: fixedChildrenEndIndex)
                spec.setChild(param, at: paramIndexPair.offset)
            default: break
            }
        }
        return spec
    }

    private mutating func demangleFuncSpecParam(kind: Node.Kind) throws(DemanglingError) -> Node {
        let param = Node(kind: kind)
        switch try scanner.readScalar() {
        case "n": break
        case "c": param.addChild(Node(kind: .functionSignatureSpecializationParamKind, contents: .index(FunctionSigSpecializationParamKind.closureProp.rawValue)))
        case "p":
            switch try scanner.readScalar() {
            case "f": param.addChild(Node(kind: .functionSignatureSpecializationParamKind, contents: .index(FunctionSigSpecializationParamKind.constantPropFunction.rawValue)))
            case "g": param.addChild(Node(kind: .functionSignatureSpecializationParamKind, contents: .index(FunctionSigSpecializationParamKind.constantPropGlobal.rawValue)))
            case "i": param.addChild(Node(kind: .functionSignatureSpecializationParamKind, contents: .index(FunctionSigSpecializationParamKind.constantPropInteger.rawValue)))
            case "d": param.addChild(Node(kind: .functionSignatureSpecializationParamKind, contents: .index(FunctionSigSpecializationParamKind.constantPropFloat.rawValue)))
            case "s":
                let encoding: String
                switch try scanner.readScalar() {
                case "b": encoding = "u8"
                case "w": encoding = "u16"
                case "c": encoding = "objc"
                default: throw failure
                }
                param.addChild(Node(kind: .functionSignatureSpecializationParamKind, contents: .index(FunctionSigSpecializationParamKind.constantPropString.rawValue)))
                param.addChild(Node(kind: .functionSignatureSpecializationParamPayload, contents: .text(encoding)))
            case "k":
                param.addChild(Node(kind: .functionSignatureSpecializationParamKind, contents: .index(FunctionSigSpecializationParamKind.constantPropKeyPath.rawValue)))
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
            param.addChild(Node(kind: .functionSignatureSpecializationParamKind, contents: .index(value)))
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
            param.addChild(Node(kind: .functionSignatureSpecializationParamKind, contents: .index(value)))
        case "g":
            var value = FunctionSigSpecializationParamKind.ownedToGuaranteed.rawValue
            if scanner.conditional(scalar: "X") {
                value |= FunctionSigSpecializationParamKind.sroa.rawValue
            }
            param.addChild(Node(kind: .functionSignatureSpecializationParamKind, contents: .index(value)))
        case "o":
            var value = FunctionSigSpecializationParamKind.guaranteedToOwned.rawValue
            if scanner.conditional(scalar: "X") {
                value |= FunctionSigSpecializationParamKind.sroa.rawValue
            }
            param.addChild(Node(kind: .functionSignatureSpecializationParamKind, contents: .index(value)))
        case "x":
            param.addChild(Node(kind: .functionSignatureSpecializationParamKind, contents: .index(FunctionSigSpecializationParamKind.sroa.rawValue)))
        case "i":
            param.addChild(Node(kind: .functionSignatureSpecializationParamKind, contents: .index(FunctionSigSpecializationParamKind.boxToValue.rawValue)))
        case "s":
            param.addChild(Node(kind: .functionSignatureSpecializationParamKind, contents: .index(FunctionSigSpecializationParamKind.boxToStack.rawValue)))
        case "r":
            param.addChild(Node(kind: .functionSignatureSpecializationParamKind, contents: .index(FunctionSigSpecializationParamKind.inOutToOut.rawValue)))
        default: throw failure
        }
        return param
    }

    private mutating func addFuncSpecParamNumber(param: inout Node, kind: FunctionSigSpecializationParamKind) throws(DemanglingError) {
        param.addChild(Node(kind: .functionSignatureSpecializationParamKind, contents: .index(kind.rawValue)))
        let str = scanner.readWhile { $0.isDigit }
        try require(!str.isEmpty)
        param.addChild(Node(kind: .functionSignatureSpecializationParamPayload, contents: .text(str)))
    }

    private mutating func demangleSpecAttributes(kind: Node.Kind, demangleUniqueId: Bool = false) throws(DemanglingError) -> Node {
        let isSerialized = scanner.conditional(scalar: "q")
        let asyncRemoved = scanner.conditional(scalar: "a")
        let passId = try scanner.readScalar().value - UnicodeScalar("0").value
        try require((0 ... 9).contains(passId))
        let contents = try demangleUniqueId ? (demangleNatural().map { Node.Contents.index($0) } ?? Node.Contents.none) : Node.Contents.none
        let specName = Node(kind: kind, contents: contents)
        if isSerialized {
            specName.addChild(Node(kind: .isSerialized))
        }
        if asyncRemoved {
            specName.addChild(Node(kind: .asyncRemoved))
        }
        specName.addChild(Node(kind: .specializationPassID, contents: .index(UInt64(passId))))
        return specName
    }

    private mutating func demangleWitness() throws(DemanglingError) -> Node {
        let c = try scanner.readScalar()
        switch c {
        case "C": return try Node(kind: .enumCase, child: require(pop(where: { $0.isEntity })))
        case "V": return try Node(kind: .valueWitnessTable, child: require(pop(kind: .type)))
        case "v":
            let directness: UInt64
            switch try scanner.readScalar() {
            case "d": directness = Directness.direct.rawValue
            case "i": directness = Directness.indirect.rawValue
            default: throw failure
            }
            return try Node(kind: .fieldOffset, children: [Node(kind: .directness, contents: .index(directness)), require(pop(where: { $0.isEntity }))])
        case "S": return try Node(kind: .protocolSelfConformanceWitnessTable, child: popProtocol())
        case "P": return try Node(kind: .protocolWitnessTable, child: popProtocolConformance())
        case "p": return try Node(kind: .protocolWitnessTablePattern, child: popProtocolConformance())
        case "G": return try Node(kind: .genericProtocolWitnessTable, child: popProtocolConformance())
        case "I": return try Node(kind: .genericProtocolWitnessTableInstantiationFunction, child: popProtocolConformance())
        case "r": return try Node(kind: .resilientProtocolWitnessTable, child: popProtocolConformance())
        case "l":
            let conf = try popProtocolConformance()
            let type = try require(pop(kind: .type))
            return Node(kind: .lazyProtocolWitnessTableAccessor, children: [type, conf])
        case "L":
            let conf = try popProtocolConformance()
            let type = try require(pop(kind: .type))
            return Node(kind: .lazyProtocolWitnessTableCacheVariable, children: [type, conf])
        case "a": return try Node(kind: .protocolWitnessTableAccessor, child: popProtocolConformance())
        case "t":
            let name = try require(pop(where: { $0.isDeclName }))
            let conf = try popProtocolConformance()
            return Node(kind: .associatedTypeMetadataAccessor, children: [conf, name])
        case "T":
            let protoType = try require(pop(kind: .type))
            let assocTypePath = try popAssocTypePath()
            return try Node(kind: .associatedTypeWitnessTableAccessor, children: [popProtocolConformance(), assocTypePath, protoType])
        case "b":
            let protoTy = try require(pop(kind: .type))
            let conf = try popProtocolConformance()
            return Node(kind: .baseWitnessTableAccessor, children: [conf, protoTy])
        case "O":
            let sig = pop(kind: .dependentGenericSignature)
            let type = try require(pop(kind: .type))
            var children: [Node] = sig.map { [type, $0] } ?? [type]
            switch try scanner.readScalar() {
            case "B":
                let type = try require(pop(kind: .type))
                if let sig = pop(kind: .dependentGenericSignature) {
                    return Node(kind: .outlinedInitializeWithTakeNoValueWitness, children: [type, sig])
                } else {
                    return Node(kind: .outlinedInitializeWithTakeNoValueWitness, children: [type])
                }
            case "C": return Node(kind: .outlinedInitializeWithCopyNoValueWitness, children: children)
            case "D": return Node(kind: .outlinedAssignWithTakeNoValueWitness, children: children)
            case "F": return Node(kind: .outlinedAssignWithCopyNoValueWitness, children: children)
            case "H": return Node(kind: .outlinedDestroyNoValueWitness, children: children)
            case "y": return Node(kind: .outlinedCopy, children: children)
            case "e": return Node(kind: .outlinedConsume, children: children)
            case "r": return Node(kind: .outlinedRetain, children: children)
            case "s": return Node(kind: .outlinedRelease, children: children)
            case "b": return Node(kind: .outlinedInitializeWithTake, children: children)
            case "c": return Node(kind: .outlinedInitializeWithCopy, children: children)
            case "d": return Node(kind: .outlinedAssignWithTake, children: children)
            case "f": return Node(kind: .outlinedAssignWithCopy, children: children)
            case "h": return Node(kind: .outlinedDestroy, children: children)
            case "g": return Node(kind: .outlinedEnumGetTag, children: children)
            case "i":
                let enumCaseIndex = try demangleIndexAsName()
                children.append(enumCaseIndex)
                return Node(kind: .outlinedEnumTagStore, children: children)
            case "j":
                let enumCaseIndex = try demangleIndexAsName()
                children.append(enumCaseIndex)
                return Node(kind: .outlinedEnumProjectDataForLoad, children: children)
            default: throw failure
            }
        case "Z",
             "z":
            let declList = Node(kind: .globalVariableOnceDeclList)
            while pop(kind: .firstElementMarker) != nil {
                guard let identifier = pop(where: { $0.isDeclName }) else { throw failure }
                declList.addChild(identifier)
            }
//            declList.reverseChildren()
            return try Node(kind: c == "Z" ? .globalVariableOnceFunction : .globalVariableOnceToken, children: [popContext(), declList])
        case "J":
            return try demangleDifferentiabilityWitness()
        default: throw failure
        }
    }

    private mutating func popAssocTypePath() throws(DemanglingError) -> Node {
        let assocTypePath = Node(kind: .assocTypePath)
        var firstElem = false
        repeat {
            firstElem = pop(kind: .firstElementMarker) != nil
            let assocType = try require(popAssocTypeName())
            assocTypePath.addChild(assocType)
        } while !firstElem
        assocTypePath.reverseChildren()
        return assocTypePath
    }

    private mutating func popAssocTypeName() -> Node? {
        var proto = pop(kind: .type)
        if let proto, !proto.isProtocol {
            return nil
        }
        if proto == nil {
            proto = pop(kind: .protocolSymbolicReference)
        }
        if proto == nil {
            proto = pop(kind: .objectiveCProtocolSymbolicReference)
        }

        guard let identifier = pop(kind: .identifier) else { return nil }
        let assocType = Node(kind: .dependentAssociatedTypeRef, child: identifier)
        if let proto {
            assocType.addChild(proto)
        }
        return assocType
    }

    private mutating func demangleSpecialType() throws(DemanglingError) -> Node {
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
        case "o": return try Node(typeWithChildKind: .unowned, childChild: require(pop(kind: .type)))
        case "u": return try Node(typeWithChildKind: .unmanaged, childChild: require(pop(kind: .type)))
        case "w": return try Node(typeWithChildKind: .weak, childChild: require(pop(kind: .type)))
        case "b": return try Node(typeWithChildKind: .silBoxType, childChild: require(pop(kind: .type)))
        case "D": return try Node(typeWithChildKind: .dynamicSelf, childChild: require(pop(kind: .type)))
        case "M":
            let mtr = try demangleMetatypeRepresentation()
            let type = try require(pop(kind: .type))
            return Node(typeWithChildKind: .metatype, childChildren: [mtr, type])
        case "m":
            let mtr = try demangleMetatypeRepresentation()
            let type = try require(pop(kind: .type))
            return Node(typeWithChildKind: .existentialMetatype, childChildren: [mtr, type])
        case "P":
            let reqs = try demangleConstrainedExistentialRequirementList()
            let base = try require(pop(kind: .type))
            return Node(typeWithChildKind: .constrainedExistential, childChildren: [base, reqs])
        case "p": return try Node(typeWithChildKind: .existentialMetatype, childChild: require(pop(kind: .type)))
        case "c":
            let superclass = try require(pop(kind: .type))
            let protocols = try demangleProtocolList()
            return Node(typeWithChildKind: .protocolListWithClass, childChildren: [protocols, superclass])
        case "l": return try Node(typeWithChildKind: .protocolListWithAnyObject, childChild: demangleProtocolList())
        case "X",
             "x":
            var signatureGenericArgs: (Node, Node)? = nil
            if specialChar == "X" {
                signatureGenericArgs = try (require(pop(kind: .dependentGenericSignature)), popTypeList())
            }

            let fieldTypes = try popTypeList()
            let layout = Node(kind: .silBoxLayout)
            for fieldType in fieldTypes.children {
                try require(fieldType.kind == .type)
                if fieldType.children.first?.kind == .inOut {
                    try layout.addChild(Node(kind: .silBoxMutableField, child: Node(kind: .type, child: require(fieldType.children.first?.children.first))))
                } else {
                    layout.addChild(Node(kind: .silBoxImmutableField, child: fieldType))
                }
            }
            let boxType = Node(kind: .silBoxTypeWithLayout, child: layout)
            if let (signature, genericArgs) = signatureGenericArgs {
                boxType.addChild(signature)
                boxType.addChild(genericArgs)
            }
            return Node(kind: .type, child: boxType)
        case "Y": return try demangleAnyGenericType(kind: .otherNominalType)
        case "Z":
            let types = try popTypeList()
            let name = try require(pop(kind: .identifier))
            let parent = try popContext()
            return Node(kind: .anonymousContext, children: [name, parent, types])
        case "e": return Node(kind: .type, child: Node(kind: .errorType))
        case "S":
            switch try scanner.readScalar() {
            case "q": return Node(kind: .type, child: Node(kind: .sugaredOptional))
            case "a": return Node(kind: .type, child: Node(kind: .sugaredArray))
            case "D":
                let value = try require(pop(kind: .type))
                let key = try require(pop(kind: .type))
                return Node(kind: .type, child: Node(kind: .sugaredDictionary, children: [key, value]))
            case "p": return Node(kind: .type, child: Node(kind: .sugaredParen))
            case "A":
                let element = try require(pop(kind: .type))
                let count = try require(pop(kind: .type))
                return Node(kind: .type, child: Node(kind: .sugaredInlineArray, children: [count, element]))
            default: throw failure
            }
        default: throw failure
        }
    }

    private mutating func demangleSymbolicExtendedExistentialType() throws(DemanglingError) -> Node {
        let retroactiveConformances = try popRetroactiveConformances()
        let args = Node(kind: .typeList)
        while let type = pop(kind: .type) {
            args.addChild(type)
        }
        args.reverseChildren()
        let shape = try require(pop(where: { $0 == .uniqueExtendedExistentialTypeShapeSymbolicReference || $0 == .nonUniqueExtendedExistentialTypeShapeSymbolicReference }))
        if let retroactiveConformances {
            return Node(typeWithChildKind: .symbolicExtendedExistentialType, childChildren: [shape, args, retroactiveConformances])
        } else {
            return Node(typeWithChildKind: .symbolicExtendedExistentialType, childChildren: [shape, args])
        }
    }

    private mutating func demangleExtendedExistentialShape(nodeKind: UnicodeScalar) throws(DemanglingError) -> Node {
        let type = try require(pop(kind: .type))
        var genSig: Node?
        if nodeKind == "G" {
            genSig = pop(kind: .dependentGenericSignature)
        }
        if let genSig {
            return Node(kind: .extendedExistentialTypeShape, children: [genSig, type])
        } else {
            return Node(kind: .extendedExistentialTypeShape, child: type)
        }
    }

    private mutating func demangleMetatypeRepresentation() throws(DemanglingError) -> Node {
        let value: String
        switch try scanner.readScalar() {
        case "t": value = "@thin"
        case "T": value = "@thick"
        case "o": value = "@objc_metatype"
        default: throw failure
        }
        return Node(kind: .metatypeRepresentation, contents: .text(value))
    }

    private mutating func demangleAccessor(child: Node) throws(DemanglingError) -> Node {
        let kind: Node.Kind
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
        return Node(kind: kind, child: child)
    }

    private mutating func demangleFunctionEntity() throws(DemanglingError) -> Node {
        let argsAndKind: (args: DemangleFunctionEntityArgs, kind: Node.Kind)
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

        var children = [Node]()
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
        return try Node(kind: argsAndKind.kind, children: [popContext()] + children)
    }

    private mutating func demangleEntity(kind: Node.Kind) throws(DemanglingError) -> Node {
        let type = try require(pop(kind: .type))
        let labelList = try popFunctionParamLabels(type: type)
        let name = try require(pop(where: { $0.isDeclName }))
        let context = try popContext()
        let result = if let labelList = labelList {
            Node(kind: kind, children: [context, name, labelList, type])
        } else {
            Node(kind: kind, children: [context, name, type])
        }
        setParentForOpaqueReturnTypeNodes(visited: type, parentId: getParentId(parent: result, flavor: flavor))
        return result
    }

    private mutating func demangleVariable() throws(DemanglingError) -> Node {
        return try demangleAccessor(child: demangleEntity(kind: .variable))
    }

    private mutating func demangleSubscript() throws(DemanglingError) -> Node {
        let privateName = pop(kind: .privateDeclName)
        let type = try require(pop(kind: .type))
        let labelList = try popFunctionParamLabels(type: type)
        let context = try popContext()

        let ss = Node(kind: .subscript, child: context)
        if let labelList = labelList {
            ss.addChild(labelList)
        }
        ss.addChild(type)
        if let pn = privateName {
            ss.addChild(pn)
        }
        setParentForOpaqueReturnTypeNodes(visited: type, parentId: getParentId(parent: ss, flavor: flavor))
        return try demangleAccessor(child: ss)
    }

    private mutating func demangleProtocolList() throws(DemanglingError) -> Node {
        let typeList = Node(kind: .typeList)
        if pop(kind: .emptyList) == nil {
            var firstElem = false
            repeat {
                firstElem = pop(kind: .firstElementMarker) != nil
                try typeList.insertChild(popProtocol(), at: 0)
            } while !firstElem
        }
        return Node(kind: .protocolList, child: typeList)
    }

    private mutating func demangleProtocolListType() throws(DemanglingError) -> Node {
        return try Node(kind: .type, child: demangleProtocolList())
    }

    private mutating func demangleConstrainedExistentialRequirementList() throws(DemanglingError) -> Node {
        let reqList = Node(kind: .constrainedExistentialRequirementList)
        var firstElement = false
        repeat {
            firstElement = (pop(kind: .firstElementMarker) != nil)
            let req = try require(pop(where: { $0.isRequirement }))
            reqList.addChild(req)
        } while !firstElement
        reqList.reverseChildren()
        return reqList
    }

    private mutating func demangleGenericSignature(hasParamCounts: Bool) throws(DemanglingError) -> Node {
        let sig = Node(kind: .dependentGenericSignature)
        if hasParamCounts {
            while !scanner.conditional(scalar: "l") {
                var count: UInt64 = 0
                if !scanner.conditional(scalar: "z") {
                    count = try demangleIndex() + 1
                }
                sig.addChild(Node(kind: .dependentGenericParamCount, contents: .index(count)))
            }
        } else {
            sig.addChild(Node(kind: .dependentGenericParamCount, contents: .index(1)))
        }
        let requirementsIndex = sig.children.endIndex
        while let req = pop(where: { $0.isRequirement }) {
            sig.insertChild(req, at: requirementsIndex)
        }
        return sig
        // let count = sig.children.count
        // while let req = pop(where: { $0.isRequirement }) {
        //    sig.addChild(req)
        // }
        // sig.reverseFirst(count)
    }

    private mutating func demangleGenericRequirement() throws(DemanglingError) -> Node {
        let constraintAndTypeKinds: (constraint: DemangleGenericRequirementConstraintKind, type: DemangleGenericRequirementTypeKind)
        var inverseKind: Node?
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

        let constrType: Node
        switch constraintAndTypeKinds.type {
        case .generic: constrType = try Node(kind: .type, child: demangleGenericParamIndex())
        case .assoc:
            constrType = try demangleAssociatedTypeSimple(index: demangleGenericParamIndex())
            substitutions.append(constrType)
        case .compoundAssoc:
            constrType = try demangleAssociatedTypeCompound(index: demangleGenericParamIndex())
            substitutions.append(constrType)
        case .substitution: constrType = try require(pop(kind: .type))
        }

        switch constraintAndTypeKinds.constraint {
        case .valueMarker: return try Node(kind: .dependentGenericParamValueMarker, children: [constrType, require(pop(kind: .type))])
        case .packMarker: return Node(kind: .dependentGenericParamPackMarker, children: [constrType])
        case .protocol: return try Node(kind: .dependentGenericConformanceRequirement, children: [constrType, popProtocol()])
        case .inverse: return try Node(kind: .dependentGenericInverseConformanceRequirement, children: [constrType, require(inverseKind)])
        case .baseClass: return try Node(kind: .dependentGenericConformanceRequirement, children: [constrType, require(pop(kind: .type))])
        case .sameType: return try Node(kind: .dependentGenericSameTypeRequirement, children: [constrType, require(pop(kind: .type))])
        case .sameShape: return try Node(kind: .dependentGenericSameShapeRequirement, children: [constrType, require(pop(kind: .type))])
        case .layout:
            let c = try scanner.readScalar()
            var size: Node? = nil
            var alignment: Node? = nil
            switch c {
            case "U",
                 "R",
                 "N",
                 "C",
                 "D",
                 "T",
                 "B": break
            case "E",
                 "M":
                size = try demangleIndexAsName()
                alignment = try demangleIndexAsName()
            case "e",
                 "m",
                 "S":
                size = try demangleIndexAsName()
            default: throw failure
            }
            let name = Node(kind: .identifier, contents: .text(String(String.UnicodeScalarView([c]))))
            let layoutRequirement = Node(kind: .dependentGenericLayoutRequirement, children: [constrType, name])
            if let s = size {
                layoutRequirement.addChild(s)
            }
            if let a = alignment {
                layoutRequirement.addChild(a)
            }
            return layoutRequirement
        }
    }

    private mutating func demangleGenericType() throws(DemanglingError) -> Node {
        let genSig = try require(pop(kind: .dependentGenericSignature))
        let type = try require(pop(kind: .type))
        return Node(typeWithChildKind: .dependentGenericType, childChildren: [genSig, type])
    }

    private mutating func demangleValueWitness() throws(DemanglingError) -> Node {
        let code = try scanner.readScalars(count: 2)
        let kind = try require(ValueWitnessKind(code: code))
        // ValueWitness node should have 2 children: Index node and Type node
        let indexNode = Node(kind: .index, contents: .index(kind.rawValue))
        let typeNode = try require(pop(kind: .type))
        return Node(kind: .valueWitness, children: [indexNode, typeNode])
    }
}

extension Demangler {
    private mutating func demangleMacroExpansion() throws(DemanglingError) -> Node {
        do {
            let kind: Node.Kind
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
                let lineNode = Node(kind: .index, contents: .index(line))
                let colNode = Node(kind: .index, contents: .index(col))
                let buffer = try require(pop(kind: .identifier))
                let module = try require(pop(kind: .identifier))
                return Node(kind: .macroExpansionLoc, children: [module, buffer, lineNode, colNode])
            default:
                throw failure
            }

            let macroName = try require(pop(kind: .identifier))
            let privateDiscriminator = isFreestanding ? pop(kind: .privateDeclName) : nil
            let attachedName = isAttached ? pop(where: { $0.isDeclName }) : nil
            let context = try pop(where: { $0.isMacroExpansion }) ?? popContext()
            let discriminator = try demangleIndexAsName()
            var result: Node
            if isAttached, let attachedName {
                result = Node(kind: kind, children: [context, attachedName, macroName, discriminator])
            } else {
                result = Node(kind: kind, children: [context, macroName, discriminator])
            }
            if let privateDiscriminator {
                result.addChild(privateDiscriminator)
            }
            return result
        } catch {
            throw error as! DemanglingError
        }
    }

    private mutating func demangleIntegerType() throws(DemanglingError) -> Node {
        if scanner.conditional(scalar: "n") {
            return try Node(kind: .type, children: [Node(kind: .negativeInteger, contents: .index(demangleIndex()))])
        } else {
            return try Node(kind: .type, children: [Node(kind: .integer, contents: .index(demangleIndex()))])
        }
    }

    private mutating func demangleObjCTypeName() throws(DemanglingError) -> Node {
        let type = Node(kind: .type)
        if scanner.conditional(scalar: "C") {
            let module: Node
            if scanner.conditional(scalar: "s") {
                module = Node(kind: .module, contents: .text(stdlibName))
            } else {
                module = try demangleIdentifier().changeKind(.module)
            }
            try type.addChild(Node(kind: .class, children: [module, demangleIdentifier()]))
        } else if scanner.conditional(scalar: "P") {
            let module: Node
            if scanner.conditional(scalar: "s") {
                module = Node(kind: .module, contents: .text(stdlibName))
            } else {
                module = try demangleIdentifier().changeKind(.module)
            }
            try type.addChild(Node(kind: .protocolList, child: Node(kind: .typeList, child: Node(kind: .type, child: Node(kind: .protocol, children: [module, demangleIdentifier()])))))
            try scanner.match(scalar: "_")
        } else {
            throw failure
        }
        try require(scanner.isAtEnd)
        return Node(kind: .global, child: Node(kind: .typeMangling, child: type))
    }
}

private let maxRepeatCount = 2048

private let maxNumWords = 26

extension Demangler {
    /// NOTE: This struct is fileprivate to avoid clashing with CwlUtils (from which it is taken). If you want to use this struct outside this file, consider including CwlUtils.
    ///
    /// A structure for traversing a `String.UnicodeScalarView`.
    ///
    /// **UNICODE WARNING**: this struct ignores all Unicode combining rules and parses each scalar individually. The rules for parsing must allow combined characters to be parsed separately or better yet, forbid combining characters at critical parse locations. If your data structure does not include these types of rule then you should be iterating over the `Character` elements in a `String` rather than using this struct.
    private struct ScalarScanner: Sendable {
        /// The underlying storage
        let scalars: C

        /// Current scanning index
        var index: C.Index

        /// Number of scalars consumed up to `index` (since String.UnicodeScalarView.Index is not a RandomAccessIndex, this makes determining the position *much* easier)
        var consumed: Int

        /// Construct from a String.UnicodeScalarView and a context value
        init(scalars: C) {
            self.scalars = scalars
            self.index = self.scalars.startIndex
            self.consumed = 0
        }

        /// Sets the index back to the beginning and clears the consumed count
        mutating func reset() {
            index = scalars.startIndex
            consumed = 0
        }

        /// Throw if the scalars at the current `index` don't match the scalars in `value`. Advance the `index` to the end of the match.
        /// WARNING: `string` is used purely for its `unicodeScalars` property and matching is purely based on direct scalar comparison (no decomposition or normalization is performed).
        mutating func match(string: String) throws(DemanglingError) {
            let (newIndex, newConsumed) = try string.unicodeScalars.reduceThrowable((index: index, count: 0)) { (tuple: (index: C.Index, count: Int), scalar: UnicodeScalar) throws(DemanglingError) in
                if tuple.index == self.scalars.endIndex || scalar != self.scalars[tuple.index] {
                    throw .matchFailed(wanted: string, at: consumed)
                }
                return (index: self.scalars.index(after: tuple.index), count: tuple.count + 1)
            }
            index = newIndex
            consumed += newConsumed
        }

        /// Throw if the scalars at the current `index` don't match the scalars in `value`. Advance the `index` to the end of the match.
        mutating func match(scalar: UnicodeScalar) throws(DemanglingError) {
            if index == scalars.endIndex || scalars[index] != scalar {
                throw DemanglingError.matchFailed(wanted: String(scalar), at: consumed)
            }
            index = scalars.index(after: index)
            consumed += 1
        }

        /// Throw if the scalars at the current `index` don't match the scalars in `value`. Advance the `index` to the end of the match.
        mutating func match(where test: @escaping (UnicodeScalar) -> Bool) throws(DemanglingError) {
            if index == scalars.endIndex || !test(scalars[index]) {
                throw DemanglingError.matchFailed(wanted: "(match test function to succeed)", at: consumed)
            }
            index = scalars.index(after: index)
            consumed += 1
        }

        /// Throw if the scalars at the current `index` don't match the scalars in `value`. Advance the `index` to the end of the match.
        mutating func read(where test: @escaping (UnicodeScalar) -> Bool) throws(DemanglingError) -> UnicodeScalar {
            if index == scalars.endIndex || !test(scalars[index]) {
                throw DemanglingError.matchFailed(wanted: "(read test function to succeed)", at: consumed)
            }
            let s = scalars[index]
            index = scalars.index(after: index)
            consumed += 1
            return s
        }

        /// Consume scalars from the contained collection, up to but not including the first instance of `scalar` found. `index` is advanced to immediately before `scalar`. Returns all scalars consumed prior to `scalar` as a `String`. Throws if `scalar` is never found.
        mutating func readUntil(scalar: UnicodeScalar) throws(DemanglingError) -> String {
            var i = index
            let previousConsumed = consumed
            try skipUntil(scalar: scalar)

            var result = ""
            result.reserveCapacity(consumed - previousConsumed)
            while i != index {
                result.unicodeScalars.append(scalars[i])
                i = scalars.index(after: i)
            }

            return result
        }

        /// Consume scalars from the contained collection, up to but not including the first instance of `string` found. `index` is advanced to immediately before `string`. Returns all scalars consumed prior to `string` as a `String`. Throws if `string` is never found.
        /// WARNING: `string` is used purely for its `unicodeScalars` property and matching is purely based on direct scalar comparison (no decomposition or normalization is performed).
        mutating func readUntil(string: String) throws(DemanglingError) -> String {
            var i = index
            let previousConsumed = consumed
            try skipUntil(string: string)

            var result = ""
            result.reserveCapacity(consumed - previousConsumed)
            while i != index {
                result.unicodeScalars.append(scalars[i])
                i = scalars.index(after: i)
            }

            return result
        }

        /// Consume scalars from the contained collection, up to but not including the first instance of any character in `set` found. `index` is advanced to immediately before `string`. Returns all scalars consumed prior to `string` as a `String`. Throws if no matching characters are ever found.
        mutating func readUntil(set inSet: Set<UnicodeScalar>) throws(DemanglingError) -> String {
            var i = index
            let previousConsumed = consumed
            try skipUntil(set: inSet)

            var result = ""
            result.reserveCapacity(consumed - previousConsumed)
            while i != index {
                result.unicodeScalars.append(scalars[i])
                i = scalars.index(after: i)
            }

            return result
        }

        /// Peeks at the scalar at the current `index`, testing it with function `f`. If `f` returns `true`, the scalar is appended to a `String` and the `index` increased. The `String` is returned at the end.
        mutating func readWhile(true test: (UnicodeScalar) -> Bool) -> String {
            var string = ""
            while index != scalars.endIndex {
                if !test(scalars[index]) {
                    break
                }
                string.unicodeScalars.append(scalars[index])
                index = scalars.index(after: index)
                consumed += 1
            }
            return string
        }

        /// Repeatedly peeks at the scalar at the current `index`, testing it with function `f`. If `f` returns `true`, the `index` increased. If `false`, the function returns.
        mutating func skipWhile(true test: (UnicodeScalar) -> Bool) {
            while index != scalars.endIndex {
                if !test(scalars[index]) {
                    return
                }
                index = scalars.index(after: index)
                consumed += 1
            }
        }

        /// Consume scalars from the contained collection, up to but not including the first instance of `scalar` found. `index` is advanced to immediately before `scalar`. Throws if `scalar` is never found.
        mutating func skipUntil(scalar: UnicodeScalar) throws(DemanglingError) {
            var i = index
            var c = 0
            while i != scalars.endIndex, scalars[i] != scalar {
                i = scalars.index(after: i)
                c += 1
            }
            if i == scalars.endIndex {
                throw DemanglingError.searchFailed(wanted: String(scalar), after: consumed)
            }
            index = i
            consumed += c
        }

        /// Consume scalars from the contained collection, up to but not including the first instance of any scalar from `set` is found. `index` is advanced to immediately before `scalar`. Throws if `scalar` is never found.
        mutating func skipUntil(set inSet: Set<UnicodeScalar>) throws(DemanglingError) {
            var i = index
            var c = 0
            while i != scalars.endIndex, !inSet.contains(scalars[i]) {
                i = scalars.index(after: i)
                c += 1
            }
            if i == scalars.endIndex {
                throw DemanglingError.searchFailed(wanted: "One of: \(inSet.sorted())", after: consumed)
            }
            index = i
            consumed += c
        }

        /// Consume scalars from the contained collection, up to but not including the first instance of `string` found. `index` is advanced to immediately before `string`. Throws if `string` is never found.
        /// WARNING: `string` is used purely for its `unicodeScalars` property and matching is purely based on direct scalar comparison (no decomposition or normalization is performed).
        mutating func skipUntil(string: String) throws(DemanglingError) {
            let match = string.unicodeScalars
            guard let first = match.first else { return }
            if match.count == 1 {
                return try skipUntil(scalar: first)
            }
            var i = index
            var j = index
            var c = 0
            var d = 0
            let remainder = match[match.index(after: match.startIndex) ..< match.endIndex]
            outerLoop: repeat {
                while scalars[i] != first {
                    if i == scalars.endIndex {
                        throw DemanglingError.searchFailed(wanted: String(match), after: consumed)
                    }
                    i = scalars.index(after: i)
                    c += 1

                    // Track the last index and consume count before hitting the match
                    j = i
                    d = c
                }
                i = scalars.index(after: i)
                c += 1
                for s in remainder {
                    if i == scalars.endIndex {
                        throw DemanglingError.searchFailed(wanted: String(match), after: consumed)
                    }
                    if scalars[i] != s {
                        continue outerLoop
                    }
                    i = scalars.index(after: i)
                    c += 1
                }
                break
            } while true
            index = j
            consumed += d
        }

        /// Attempt to advance the `index` by count, returning `false` and `index` unchanged if `index` would advance past the end, otherwise returns `true` and `index` is advanced.
        mutating func skip(count: Int = 1) throws(DemanglingError) {
            if count == 1, index != scalars.endIndex {
                index = scalars.index(after: index)
                consumed += 1
            } else {
                var i = index
                var c = count
                while c > 0 {
                    if i == scalars.endIndex {
                        throw DemanglingError.endedPrematurely(count: count, at: consumed)
                    }
                    i = scalars.index(after: i)
                    c -= 1
                }
                index = i
                consumed += count
            }
        }

        /// Attempt to advance the `index` by count, returning `false` and `index` unchanged if `index` would advance past the end, otherwise returns `true` and `index` is advanced.
        mutating func backtrack(count: Int = 1) throws(DemanglingError) {
            if count <= consumed {
                if count == 1 {
                    index = scalars.index(index, offsetBy: -1)
                    consumed -= 1
                } else {
                    let limit = consumed - count
                    while consumed != limit {
                        index = scalars.index(index, offsetBy: -1)
                        consumed -= 1
                    }
                }
            } else {
                throw DemanglingError.endedPrematurely(count: -count, at: consumed)
            }
        }

        /// Returns all content after the current `index`. `index` is advanced to the end.
        mutating func remainder() -> String {
            var string = ""
            while index != scalars.endIndex {
                string.unicodeScalars.append(scalars[index])
                index = scalars.index(after: index)
                consumed += 1
            }
            return string
        }

        /// If the next scalars after the current `index` match `value`, advance over them and return `true`, otherwise, leave `index` unchanged and return `false`.
        /// WARNING: `string` is used purely for its `unicodeScalars` property and matching is purely based on direct scalar comparison (no decomposition or normalization is performed).
        mutating func conditional(string: String) -> Bool {
            var i = index
            var c = 0
            for s in string.unicodeScalars {
                if i == scalars.endIndex || s != scalars[i] {
                    return false
                }
                i = scalars.index(after: i)
                c += 1
            }
            index = i
            consumed += c
            return true
        }

        /// If the next scalar after the current `index` match `value`, advance over it and return `true`, otherwise, leave `index` unchanged and return `false`.
        mutating func conditional(scalar: UnicodeScalar) -> Bool {
            if index == scalars.endIndex || scalar != scalars[index] {
                return false
            }
            index = scalars.index(after: index)
            consumed += 1
            return true
        }

        /// If the next scalar after the current `index` match `value`, advance over it and return `true`, otherwise, leave `index` unchanged and return `false`.
        mutating func conditional(where test: (UnicodeScalar) -> Bool) -> UnicodeScalar? {
            if index == scalars.endIndex || !test(scalars[index]) {
                return nil
            }
            let s = scalars[index]
            index = scalars.index(after: index)
            consumed += 1
            return s
        }

        /// If the `index` is at the end, throw, otherwise, return the next scalar at the current `index` without advancing `index`.
        func requirePeek() throws(DemanglingError) -> UnicodeScalar {
            if index == scalars.endIndex {
                throw DemanglingError.endedPrematurely(count: 1, at: consumed)
            }
            return scalars[index]
        }

        /// If `index` + `ahead` is within bounds, return the scalar at that location, otherwise return `nil`. The `index` will not be changed in any case.
        func peek(skipCount: Int = 0) -> UnicodeScalar? {
            var i = index
            var c = skipCount
            while c > 0, i != scalars.endIndex {
                i = scalars.index(after: i)
                c -= 1
            }
            if i == scalars.endIndex {
                return nil
            }
            return scalars[i]
        }

        /// If the `index` is at the end, throw, otherwise, return the next scalar at the current `index`, advancing `index` by one.
        mutating func readScalar() throws(DemanglingError) -> UnicodeScalar {
            if index == scalars.endIndex {
                throw DemanglingError.endedPrematurely(count: 1, at: consumed)
            }
            let result = scalars[index]
            index = scalars.index(after: index)
            consumed += 1
            return result
        }

        /// Throws if scalar at the current `index` is not in the range `"0"` to `"9"`. Consume scalars `"0"` to `"9"` until a scalar outside that range is encountered. Return the integer representation of the value scanned, interpreted as a base 10 integer. `index` is advanced to the end of the number.
        mutating func readInt() throws(DemanglingError) -> UInt64 {
            let result = try conditionalInt()
            guard let r = result else {
                throw DemanglingError.expectedInt(at: consumed)
            }
            return r
        }

        /// Throws if scalar at the current `index` is not in the range `"0"` to `"9"`. Consume scalars `"0"` to `"9"` until a scalar outside that range is encountered. Return the integer representation of the value scanned, interpreted as a base 10 integer. `index` is advanced to the end of the number.
        mutating func conditionalInt() throws(DemanglingError) -> UInt64? {
            var result: UInt64 = 0
            var i = index
            var c = 0
            while i != scalars.endIndex, scalars[i].isDigit {
                let digit = UInt64(scalars[i].value - UnicodeScalar("0").value)

                // The Swift compiler allows overflow here for malformed inputs, so we're obliged to do the same
                result = result &* 10 &+ digit

                i = scalars.index(after: i)
                c += 1
            }
            if i == index {
                return nil
            }
            index = i
            consumed += c
            return result
        }

        /// Consume and return `count` scalars. `index` will be advanced by count. Throws if end of `scalars` occurs before consuming `count` scalars.
        mutating func readScalars(count: Int) throws(DemanglingError) -> String {
            var result = String()
            result.reserveCapacity(count)
            var i = index
            for _ in 0 ..< count {
                if i == scalars.endIndex {
                    throw DemanglingError.endedPrematurely(count: count, at: consumed)
                }
                result.unicodeScalars.append(scalars[i])
                i = scalars.index(after: i)
            }
            index = i
            consumed += count
            return result
        }

        /// Returns a throwable error capturing the current scanner progress point.
        func unexpectedError() -> DemanglingError {
            return DemanglingError.unexpected(at: consumed)
        }

        var isAtEnd: Bool {
            return index == scalars.endIndex
        }
    }
}


extension Demangler {
    
    mutating func demangleSwift3TopLevelSymbol() throws(DemanglingError) -> Node {
        reset()
        
        try scanner.match(string: "_T")
        var children = [Node]()
        
        switch (try scanner.readScalar(), try scanner.readScalar()) {
        case ("T", "S"):
            repeat {
                children.append(try demangleSwift3SpecializedAttribute())
                nameStack.removeAll()
            } while scanner.conditional(string: "_TTS")
            try scanner.match(string: "_T")
        case ("T", "o"): children.append(Node(kind: .objCAttribute))
        case ("T", "O"): children.append(Node(kind: .nonObjCAttribute))
        case ("T", "D"): children.append(Node(kind: .dynamicAttribute))
        case ("T", "d"): children.append(Node(kind: .directMethodReferenceAttribute))
        case ("T", "v"): children.append(Node(kind: .vTableAttribute))
        default: try scanner.backtrack(count: 2)
        }
        
        children.append(try demangleSwift3Global())
        
        let remainder = scanner.remainder()
        if !remainder.isEmpty {
            children.append(Node(kind: .suffix, contents: .text(remainder)))
        }
        
        return Node(kind: .global, children: children)
    }
    
    mutating func demangleSwift3Global() throws(DemanglingError) -> Node {
        let c1 = try scanner.readScalar()
        let c2 = try scanner.readScalar()
        switch (c1, c2) {
        case ("M", "P"): return Node(kind: .genericTypeMetadataPattern, children: [try demangleSwift3Type()])
        case ("M", "a"): return Node(kind: .typeMetadataAccessFunction, children: [try demangleSwift3Type()])
        case ("M", "L"): return Node(kind: .typeMetadataLazyCache, children: [try demangleSwift3Type()])
        case ("M", "m"): return Node(kind: .metaclass, children: [try demangleSwift3Type()])
        case ("M", "n"): return Node(kind: .nominalTypeDescriptor, children: [try demangleSwift3Type()])
        case ("M", "f"): return Node(kind: .fullTypeMetadata, children: [try demangleSwift3Type()])
        case ("M", "p"): return Node(kind: .protocolDescriptor, children: [try demangleSwift3ProtocolName()])
        case ("M", _):
            try scanner.backtrack()
            return Node(kind: .typeMetadata, children: [try demangleSwift3Type()])
        case ("P", "A"):
            return Node(kind: scanner.conditional(scalar: "o") ? .partialApplyObjCForwarder : .partialApplyForwarder, children: scanner.conditional(string: "__T") ? [try demangleSwift3Global()] : [])
        case ("P", _): throw scanner.unexpectedError()
        case ("t", _):
            try scanner.backtrack()
            return Node(kind: .typeMangling, children: [try demangleSwift3Type()])
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
            return Node(kind: .valueWitness, contents: .index(value), children: [try demangleSwift3Type()])
        case ("W", "V"): return Node(kind: .valueWitnessTable, children: [try demangleSwift3Type()])
        case ("W", "v"): return Node(kind: .fieldOffset, children: [Node(kind: .directness, contents: .index(try scanner.readScalar() == "d" ? 0 : 1)), try demangleSwift3Entity()])
        case ("W", "P"): return Node(kind: .protocolWitnessTable, children: [try demangleSwift3ProtocolConformance()])
        case ("W", "G"): return Node(kind: .genericProtocolWitnessTable, children: [try demangleSwift3ProtocolConformance()])
        case ("W", "I"): return Node(kind: .genericProtocolWitnessTableInstantiationFunction, children: [try demangleSwift3ProtocolConformance()])
        case ("W", "l"): return Node(kind: .lazyProtocolWitnessTableAccessor, children: [try demangleSwift3Type(), try demangleSwift3ProtocolConformance()])
        case ("W", "L"): return Node(kind: .lazyProtocolWitnessTableCacheVariable, children: [try demangleSwift3Type(), try demangleSwift3ProtocolConformance()])
        case ("W", "a"): return Node(kind: .protocolWitnessTableAccessor, children: [try demangleSwift3ProtocolConformance()])
        case ("W", "t"): return Node(kind: .associatedTypeMetadataAccessor, children: [try demangleSwift3ProtocolConformance(), try demangleSwift3DeclName()])
        case ("W", "T"): return Node(kind: .associatedTypeWitnessTableAccessor, children: [try demangleSwift3ProtocolConformance(), try demangleSwift3DeclName(), try demangleSwift3ProtocolName()])
        case ("W", _): throw scanner.unexpectedError()
        case ("T","W"): return Node(kind: .protocolWitness, children: [try demangleSwift3ProtocolConformance(), try demangleSwift3Entity()])
        case ("T", "R"): fallthrough
        case ("T", "r"): return Node(kind: c2 == "R" ? Node.Kind.reabstractionThunkHelper : Node.Kind.reabstractionThunk, children: scanner.conditional(scalar: "G") ? [try demangleSwift3GenericSignature(), try demangleSwift3Type(), try demangleSwift3Type()] : [try demangleSwift3Type(), try demangleSwift3Type()])
        default:
            try scanner.backtrack(count: 2)
            return try demangleSwift3Entity()
        }
    }
    
    mutating func demangleSwift3SpecializedAttribute() throws(DemanglingError) -> Node {
        let c = try scanner.readScalar()
        var children = [Node]()
        if scanner.conditional(scalar: "q") {
            children.append(Node(kind: .isSerialized))
        }
        children.append(Node(kind: .specializationPassID, contents: .index(UInt64(try scanner.readScalar().value - 48))))
        switch c {
        case "r": fallthrough
        case "g":
            while !scanner.conditional(scalar: "_") {
                var parameterChildren = [Node]()
                parameterChildren.append(try demangleSwift3Type())
                while !scanner.conditional(scalar: "_") {
                    parameterChildren.append(try demangleSwift3ProtocolConformance())
                }
                children.append(Node(kind: .genericSpecializationParam, children: parameterChildren))
            }
            return Node(kind: c == "r" ? .genericSpecializationNotReAbstracted : .genericSpecialization, children: children)
        case "f":
            var count: UInt64 = 0
            while !scanner.conditional(scalar: "_") {
                var paramChildren = [Node]()
                let c = try scanner.readScalar()
                switch (c, try scanner.readScalar()) {
                case ("n", "_"): break
                case ("c", "p"): paramChildren.append(contentsOf: try demangleSwift3FuncSigSpecializationConstantProp())
                case ("c", "l"):
                    paramChildren.append(Node(kind: .functionSignatureSpecializationParamKind, contents: .index(FunctionSigSpecializationParamKind.closureProp.rawValue)))
                    paramChildren.append(Node(kind: .functionSignatureSpecializationParamPayload, contents: try demangleSwift3Identifier().contents))
                    while !scanner.conditional(scalar: "_") {
                        paramChildren.append(try demangleSwift3Type())
                    }
                case ("i", "_"): fallthrough
                case ("k", "_"): paramChildren.append(Node(kind: .functionSignatureSpecializationParamKind, contents: .index(c == "i" ? FunctionSigSpecializationParamKind.boxToValue.rawValue : FunctionSigSpecializationParamKind.boxToStack.rawValue)))
                default:
                    try scanner.backtrack(count: 2)
                    var value: UInt64 = 0
                    value |= scanner.conditional(scalar: "d") ? FunctionSigSpecializationParamKind.dead.rawValue : 0
                    value |= scanner.conditional(scalar: "g") ? FunctionSigSpecializationParamKind.ownedToGuaranteed.rawValue : 0
                    value |= scanner.conditional(scalar: "o") ? FunctionSigSpecializationParamKind.guaranteedToOwned.rawValue : 0
                    value |= scanner.conditional(scalar: "s") ? FunctionSigSpecializationParamKind.sroa.rawValue : 0
                    try scanner.match(scalar: "_")
                    paramChildren.append(Node(kind: .functionSignatureSpecializationParamKind, contents: .index(value)))
                }
                children.append(Node(kind: .functionSignatureSpecializationParam, contents: .index(count), children: paramChildren))
                count += 1
            }
            return Node(kind: .functionSignatureSpecialization, children: children)
        default: throw scanner.unexpectedError()
        }
    }
    
    mutating func demangleSwift3FuncSigSpecializationConstantProp() throws(DemanglingError) -> [Node] {
        switch (try scanner.readScalar(), try scanner.readScalar()) {
        case ("f", "r"):
            let name = Node(kind: .functionSignatureSpecializationParamPayload, contents: try demangleSwift3Identifier().contents)
            try scanner.match(scalar: "_")
            let kind = Node(kind: .functionSignatureSpecializationParamKind, contents: .index(FunctionSigSpecializationParamKind.constantPropFunction.rawValue))
            return [kind, name]
        case ("g", _):
            try scanner.backtrack()
            let name = Node(kind: .functionSignatureSpecializationParamPayload, contents: try demangleSwift3Identifier().contents)
            try scanner.match(scalar: "_")
            let kind = Node(kind: .functionSignatureSpecializationParamKind, contents: .index(FunctionSigSpecializationParamKind.constantPropGlobal.rawValue))
            return [kind, name]
        case ("i", _):
            try scanner.backtrack()
            let string = try scanner.readUntil(scalar: "_")
            try scanner.match(scalar: "_")
            let name = Node(kind: .functionSignatureSpecializationParamPayload, contents: .text(string))
            let kind = Node(kind: .functionSignatureSpecializationParamKind, contents: .index(FunctionSigSpecializationParamKind.constantPropInteger.rawValue))
            return [kind, name]
        case ("f", "l"):
            let string = try scanner.readUntil(scalar: "_")
            try scanner.match(scalar: "_")
            let name = Node(kind: .functionSignatureSpecializationParamPayload, contents: .text(string))
            let kind = Node(kind: .functionSignatureSpecializationParamKind, contents: .index(FunctionSigSpecializationParamKind.constantPropFloat.rawValue))
            return [kind, name]
        case ("s", "e"):
            var string: String
            switch try scanner.readScalar() {
            case "0": string = "u8"
            case "1": string = "u16"
            default: throw scanner.unexpectedError()
            }
            try scanner.match(scalar: "v")
            let name = Node(kind: .functionSignatureSpecializationParamPayload, contents: try demangleSwift3Identifier().contents)
            let encoding = Node(kind: .functionSignatureSpecializationParamPayload, contents: .text(string))
            let kind = Node(kind: .functionSignatureSpecializationParamKind, contents: .index(FunctionSigSpecializationParamKind.constantPropString.rawValue))
            try scanner.match(scalar: "_")
            return [kind, encoding, name]
        default: throw scanner.unexpectedError()
        }
    }
    
    
    mutating func demangleSwift3ProtocolConformance() throws(DemanglingError) -> Node {
        let type = try demangleSwift3Type()
        let prot = try demangleSwift3ProtocolName()
        let context = try demangleSwift3Context()
        return Node(kind: .protocolConformance, children: [type, prot, context])
    }
    
    mutating func demangleSwift3ProtocolName() throws(DemanglingError) -> Node {
        let name: Node
        if scanner.conditional(scalar: "S") {
            let index = try demangleSwift3SubstitutionIndex()
            switch index.kind {
            case .protocol: name = index
            case .module: name = try demangleSwift3ProtocolNameGivenContext(context: index)
            default: throw scanner.unexpectedError()
            }
        } else if scanner.conditional(scalar: "s") {
            let stdlib = Node(kind: .module, contents: .text(stdlibName))
            name = try demangleSwift3ProtocolNameGivenContext(context: stdlib)
        } else {
            name = try demangleSwift3DeclarationName(kind: .protocol)
        }
        
        return Node(kind: .type, children: [name])
    }
    
    mutating func demangleSwift3ProtocolNameGivenContext(context: Node) throws(DemanglingError) -> Node {
        let name = try demangleSwift3DeclName()
        let result = Node(kind: .protocol, children: [context, name])
        nameStack.append(result)
        return result
    }
    
    mutating func demangleSwift3NominalType() throws(DemanglingError) -> Node {
        switch try scanner.readScalar() {
        case "S": return try demangleSwift3SubstitutionIndex()
        case "V": return try demangleSwift3DeclarationName(kind: .structure)
        case "O": return try demangleSwift3DeclarationName(kind: .enum)
        case "C": return try demangleSwift3DeclarationName(kind: .class)
        case "P": return try demangleSwift3DeclarationName(kind: .protocol)
        default: throw scanner.unexpectedError()
        }
    }
    
    mutating func demangleSwift3BoundGenericArgs(nominalType initialNominal: Node) throws(DemanglingError) -> Node {
        guard var parentOrModule = initialNominal.children.first else { throw scanner.unexpectedError() }
        
        let nominalType: Node
        switch parentOrModule.kind {
        case .module: fallthrough
        case .function: fallthrough
        case .extension: nominalType = initialNominal
        default:
            parentOrModule = try demangleSwift3BoundGenericArgs(nominalType: parentOrModule)
            
            guard initialNominal.children.count > 1 else { throw scanner.unexpectedError() }
            nominalType = Node(kind: initialNominal.kind, children: [parentOrModule, initialNominal.children[1]])
        }
        
        var children = [Node]()
        while !scanner.conditional(scalar: "_") {
            children.append(try demangleSwift3Type())
        }
        if children.isEmpty {
            return nominalType
        }
        let args = Node(kind: .typeList, children: children)
        let unboundType = Node(kind: .type, children: [nominalType])
        switch nominalType.kind {
        case .class: return Node(kind: .boundGenericClass, children: [unboundType, args])
        case .structure: return Node(kind: .boundGenericStructure, children: [unboundType, args])
        case .enum: return Node(kind: .boundGenericEnum, children: [unboundType, args])
        default: throw scanner.unexpectedError()
        }
    }
    
    mutating func demangleSwift3Entity() throws(DemanglingError) -> Node {
        let isStatic = scanner.conditional(scalar: "Z")
        
        let basicKind: Node.Kind
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
        let kind: Node.Kind
        let hasType: Bool
        var name: Node? = nil
        var wrapEntity: Bool = false
        
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
            case "O": (kind, hasType, name) = (c == "a" ? .owningMutableAddressor : .owningAddressor, true, try demangleSwift3DeclName())
            case "o": (kind, hasType, name) = (c == "a" ? .nativeOwningMutableAddressor : .nativeOwningAddressor, true, try demangleSwift3DeclName())
            case "p": (kind, hasType, name) = (c == "a" ? .nativePinningMutableAddressor : .nativePinningAddressor, true, try demangleSwift3DeclName())
            case "u": (kind, hasType, name) = (c == "a" ? .unsafeMutableAddressor : .unsafeAddressor, true, try demangleSwift3DeclName())
            default: throw scanner.unexpectedError()
            }
        case "g": (kind, hasType, name, wrapEntity) = (.getter, true, try demangleSwift3DeclName(), true)
        case "G": (kind, hasType, name, wrapEntity) = (.globalGetter, true, try demangleSwift3DeclName(), true)
        case "s": (kind, hasType, name, wrapEntity) = (.setter, true, try demangleSwift3DeclName(), true)
        case "m": (kind, hasType, name, wrapEntity) = (.materializeForSet, true, try demangleSwift3DeclName(), true)
        case "w": (kind, hasType, name, wrapEntity) = (.willSet, true, try demangleSwift3DeclName(), true)
        case "W": (kind, hasType, name, wrapEntity) = (.didSet, true, try demangleSwift3DeclName(), true)
        case "U": (kind, hasType, name) = (.explicitClosure, true, Node(kind: .number, contents: .index(try demangleSwift3Index())))
        case "u": (kind, hasType, name) = (.implicitClosure, true, Node(kind: .number, contents: .index(try demangleSwift3Index())))
        case "A" where basicKind == .initializer: (kind, hasType, name) = (.defaultArgumentInitializer, false, Node(kind: .number, contents: .index(try demangleSwift3Index())))
        case "i" where basicKind == .initializer: (kind, hasType) = (.initializer, false)
        case _ where basicKind == .initializer: throw scanner.unexpectedError()
        default:
            try scanner.backtrack()
            (kind, hasType, name) = (basicKind, true, try demangleSwift3DeclName())
        }
        
        let entity = Node(kind: kind)
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
                    name = Node(kind: .privateDeclName, children: [first])
                }
            default: break
            }
            var wrappedEntity: Node
            if isSubscript {
                wrappedEntity = Node(kind: .subscript, child: context)
            } else {
                wrappedEntity = Node(kind: .variable, child: context)
            }
            if !isSubscript, let n = name {
                wrappedEntity.addChild(n)
            }
            if hasType {
                wrappedEntity.addChild(try demangleSwift3Type())
            }
            if isSubscript, let n = name {
                wrappedEntity.addChild(n)
            }
            entity.addChild(wrappedEntity)
        } else {
            entity.addChild(context)
            if let n = name {
                entity.addChild(n)
            }
            if hasType {
                entity.addChild(try demangleSwift3Type())
            }
        }
        
        return isStatic ? Node(kind: .static, children: [entity]) : entity
    }
    
    mutating func demangleSwift3DeclarationName(kind: Node.Kind) throws(DemanglingError) -> Node {
        let result = Node(kind: kind, children: [try demangleSwift3Context(), try demangleSwift3DeclName()])
        nameStack.append(result)
        return result
    }
    
    mutating func demangleSwift3Context() throws(DemanglingError) -> Node {
        switch try scanner.readScalar() {
        case "E": return Node(kind: .extension, children: [try demangleSwift3Module(), try demangleSwift3Context()])
        case "e":
            let module = try demangleSwift3Module()
            let signature = try demangleSwift3GenericSignature()
            let type = try demangleSwift3Context()
            return Node(kind: .extension, children: [module, type, signature])
        case "S": return try demangleSwift3SubstitutionIndex()
        case "s": return Node(kind: .module, contents: .text(stdlibName), children: [])
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
    
    mutating func demangleSwift3Module() throws(DemanglingError) -> Node {
        switch try scanner.readScalar() {
        case "S": return try demangleSwift3SubstitutionIndex()
        case "s": return Node(kind: .module, contents: .text("Swift"), children: [])
        default:
            try scanner.backtrack()
            let module = try demangleSwift3Identifier(kind: .module)
            nameStack.append(module)
            return module
        }
    }
    
    func swiftStdLibType(_ kind: Node.Kind, named: String) -> Node {
        return Node(kind: kind, children: [Node(kind: .module, contents: .text(stdlibName)), Node(kind: .identifier, contents: .text(named))])
    }
    
    mutating func demangleSwift3SubstitutionIndex() throws(DemanglingError) -> Node {
        switch try scanner.readScalar() {
        case "o": return Node(kind: .module, contents: .text(objcModule))
        case "C": return Node(kind: .module, contents: .text(cModule))
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
    
    mutating func demangleSwift3GenericSignature(isPseudo: Bool = false) throws(DemanglingError) -> Node {
        var children = [Node]()
        var c = try scanner.requirePeek()
        while c != "R" && c != "r" {
            children.append(Node(kind: .dependentGenericParamCount, contents: .index(scanner.conditional(scalar: "z") ? 0 : (try demangleSwift3Index() + 1))))
            c = try scanner.requirePeek()
        }
        if children.isEmpty {
            children.append(Node(kind: .dependentGenericParamCount, contents: .index(1)))
        }
        if !scanner.conditional(scalar: "r") {
            try scanner.match(scalar: "R")
            while !scanner.conditional(scalar: "r") {
                children.append(try demangleSwift3GenericRequirement())
            }
        }
        return Node(kind: .dependentGenericSignature, children: children)
    }
    
    mutating func demangleSwift3GenericRequirement() throws(DemanglingError) -> Node {
        let constrainedType = try demangleSwift3ConstrainedType()
        if scanner.conditional(scalar: "z") {
            return Node(kind: .dependentGenericSameTypeRequirement, children: [constrainedType, try demangleSwift3Type()])
        }
        
        if scanner.conditional(scalar: "l") {
            let name: String
            let kind: Node.Kind
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
            let second = Node(kind: kind, contents: .text(name))
            let reqt = Node(kind: .dependentGenericLayoutRequirement, children: [constrainedType, second])
            if size != UInt64.max {
                reqt.addChild(Node(kind: .number, contents: .index(size)))
                if alignment != UInt64.max {
                    reqt.addChild(Node(kind: .number, contents: .index(alignment)))
                }
            }
            return reqt
        }
        
        let c = try scanner.requirePeek()
        let constraint: Node
        if c == "C" {
            constraint = try demangleSwift3Type()
        } else if c == "S" {
            try scanner.match(scalar: "S")
            let index = try demangleSwift3SubstitutionIndex()
            let typename: Node
            switch index.kind {
            case .protocol: fallthrough
            case .class: typename = index
            case .module: typename = try demangleSwift3ProtocolNameGivenContext(context: index)
            default: throw scanner.unexpectedError()
            }
            constraint = Node(kind: .type, children: [typename])
        } else {
            constraint = try demangleSwift3ProtocolName()
        }
        return Node(kind: .dependentGenericConformanceRequirement, children: [constrainedType, constraint])
    }
    
    mutating func demangleSwift3ConstrainedType() throws(DemanglingError) -> Node {
        if scanner.conditional(scalar: "w") {
            return try demangleSwift3AssociatedTypeSimple()
        } else if scanner.conditional(scalar: "W") {
            return try demangleSwift3AssociatedTypeCompound()
        }
        return try demangleSwift3GenericParamIndex()
    }
    
    mutating func demangleSwift3AssociatedTypeSimple() throws(DemanglingError) -> Node {
        let base = try demangleSwift3GenericParamIndex()
        return try demangleSwift3DependentMemberTypeName(base: Node(kind: .type, children: [base]))
    }
    
    mutating func demangleSwift3AssociatedTypeCompound() throws(DemanglingError) -> Node {
        var base = try demangleSwift3GenericParamIndex()
        while !scanner.conditional(scalar: "_") {
            let type = Node(kind: .type, children: [base])
            base = try demangleSwift3DependentMemberTypeName(base: type)
        }
        return base
    }
    
    mutating func demangleSwift3GenericParamIndex() throws(DemanglingError) -> Node {
        let depth: UInt64
        let index: UInt64
        switch try scanner.readScalar() {
        case "d": (depth, index) = (try demangleSwift3Index() + 1, try demangleSwift3Index())
        case "x": (depth, index) = (0, 0)
        default:
            try scanner.backtrack()
            (depth, index) = (0, try demangleSwift3Index() + 1)
        }
        return Node(kind: .dependentGenericParamType, contents: .text(archetypeName(index, depth)), children: [Node(kind: .index, contents: .index(depth)), Node(kind: .index, contents: .index(index))])
    }
    
    mutating func demangleSwift3DependentMemberTypeName(base: Node) throws(DemanglingError) -> Node {
        let associatedType: Node
        if scanner.conditional(scalar: "S") {
            associatedType = try demangleSwift3SubstitutionIndex()
        } else {
            var prot: Node? = nil
            if scanner.conditional(scalar: "P") {
                prot = try demangleSwift3ProtocolName()
            }
            let identifier = try demangleSwift3Identifier()
            if let p = prot {
                associatedType = Node(kind: .dependentAssociatedTypeRef, children: [identifier, p])
            } else {
                associatedType = Node(kind: .dependentAssociatedTypeRef, children: [identifier])
            }
            nameStack.append(associatedType)
        }
        
        return Node(kind: .dependentMemberType, children: [base, associatedType])
    }
    
    mutating func demangleSwift3DeclName() throws(DemanglingError) -> Node {
        switch try scanner.readScalar() {
        case "L": return Node(kind: .localDeclName, children: [Node(kind: .number, contents: .index(try demangleSwift3Index())), try demangleSwift3Identifier()])
        case "P": return Node(kind: .privateDeclName, children: [try demangleSwift3Identifier(), try demangleSwift3Identifier()])
        default:
            try scanner.backtrack()
            return try demangleSwift3Identifier()
        }
    }
    
    mutating func demangleSwift3Index() throws(DemanglingError) -> UInt64 {
        if scanner.conditional(scalar: "_") {
            return 0
        }
        let value = UInt64(try scanner.readInt()) + 1
        try scanner.match(scalar: "_")
        return value
    }
    
    mutating func demangleSwift3Type() throws(DemanglingError) -> Node {
        let type: Node
        switch try scanner.readScalar() {
        case "B":
            switch try scanner.readScalar() {
            case "b": type = Node(kind: .builtinTypeName, contents: .text("Builtin.BridgeObject"))
            case "B": type = Node(kind: .builtinTypeName, contents: .text("Builtin.UnsafeValueBuffer"))
            case "f":
                let size = try scanner.readInt()
                try scanner.match(scalar: "_")
                type = Node(kind: .builtinTypeName, contents: .text("Builtin.FPIEEE\(size)"))
            case "i":
                let size = try scanner.readInt()
                try scanner.match(scalar: "_")
                type = Node(kind: .builtinTypeName, contents: .text("Builtin.Int\(size)"))
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
                    (name, size) = (c == "i" ? "xInt" : "xFPIEEE", try "\(scanner.readInt())")
                    try scanner.match(scalar: "_")
                default: throw scanner.unexpectedError()
                }
                type = Node(kind: .builtinTypeName, contents: .text("Builtin.Vec\(elements)\(name)\(size)"))
            case "O": type = Node(kind: .builtinTypeName, contents: .text("Builtin.UnknownObject"))
            case "o": type = Node(kind: .builtinTypeName, contents: .text("Builtin.NativeObject"))
            case "t": type = Node(kind: .builtinTypeName, contents: .text("Builtin.SILToken"))
            case "p": type = Node(kind: .builtinTypeName, contents: .text("Builtin.RawPointer"))
            case "w": type = Node(kind: .builtinTypeName, contents: .text("Builtin.Word"))
            default: throw scanner.unexpectedError()
            }
        case "a": type = try demangleSwift3DeclarationName(kind: .typeAlias)
        case "b": type = try demangleSwift3FunctionType(kind: .objCBlock)
        case "c": type = try demangleSwift3FunctionType(kind: .cFunctionPointer)
        case "D": type = Node(kind: .dynamicSelf, children: [try demangleSwift3Type()])
        case "E":
            guard try scanner.readScalars(count: 2) == "RR" else { throw scanner.unexpectedError() }
            type = Node(kind: .errorType, contents: .text(""), children: [])
        case "F": type = try demangleSwift3FunctionType(kind: .functionType)
        case "f": type = try demangleSwift3FunctionType(kind: .uncurriedFunctionType)
        case "G": type = try demangleSwift3BoundGenericArgs(nominalType: demangleSwift3NominalType())
        case "X":
            let c = try scanner.readScalar()
            switch c {
            case "b": type = Node(kind: .silBoxType, children: [try demangleSwift3Type()])
            case "B":
                var signature: Node? = nil
                if scanner.conditional(scalar: "G") {
                    signature = try demangleSwift3GenericSignature(isPseudo: false)
                }
                let layout = Node(kind: .silBoxLayout)
                while !scanner.conditional(scalar: "_") {
                    let kind: Node.Kind
                    switch try scanner.readScalar() {
                    case "m": kind = .silBoxMutableField
                    case "i": kind = .silBoxImmutableField
                    default: throw failure
                    }
                    let type = try demangleType()
                    let field = Node(kind: kind, child: type)
                    layout.addChild(field)
                }
                var genericArgs: Node? = nil
                if signature != nil {
                    let ga = Node(kind: .typeList)
                    while !scanner.conditional(scalar: "_") {
                        let type = try demangleType()
                        ga.addChild(type)
                    }
                    genericArgs = ga
                }
                let boxType = Node(kind: .silBoxTypeWithLayout, child: layout)
                if let s = signature, let ga = genericArgs {
                    boxType.addChild(s)
                    boxType.addChild(ga)
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
                type = Node(kind: c == "P" ? .existentialMetatype : .metatype, children: [Node(kind: .metatypeRepresentation, contents: .text(value)), try demangleSwift3Type()])
            case "P":
                var children = [Node]()
                while !scanner.conditional(scalar: "_") {
                    children.append(try demangleSwift3ProtocolName())
                }
                type = Node(kind: .protocolList, children: [Node(kind: .typeList)])
            case "f": type = try demangleSwift3FunctionType(kind: .thinFunctionType)
            case "o": type = Node(kind: .unowned, children: [try demangleSwift3Type()])
            case "u": type = Node(kind: .unmanaged, children: [try demangleSwift3Type()])
            case "w": type = Node(kind: .weak, children: [try demangleSwift3Type()])
            case "F":
                var children = [Node]()
                children.append(Node(kind: .implConvention, contents: .text(try demangleSwift3ImplConvention(kind: .implConvention))))
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
                    children.append(Node(kind: .implFunctionAttribute, contents: .text(name)))
                }
                if scanner.conditional(scalar: "G") {
                    children.append(try demangleSwift3GenericSignature(isPseudo: false))
                } else if scanner.conditional(scalar: "g") {
                    children.append(try demangleSwift3GenericSignature(isPseudo: true))
                }
                try scanner.match(scalar: "_")
                while !scanner.conditional(scalar: "_") {
                    children.append(try demangleSwift3ImplParameterOrResult(kind: .implParameter))
                }
                while !scanner.conditional(scalar: "_") {
                    children.append(try demangleSwift3ImplParameterOrResult(kind: .implResult))
                }
                type = Node(kind: .implFunctionType, children: children)
            default: throw scanner.unexpectedError()
            }
        case "K": type = try demangleSwift3FunctionType(kind: .autoClosureType)
        case "M": type = Node(kind: .metatype, children: [try demangleSwift3Type()])
        case "P" where scanner.conditional(scalar: "M"): type = Node(kind: .existentialMetatype, children: [try demangleSwift3Type()])
        case "P":
            var children = [Node]()
            while !scanner.conditional(scalar: "_") {
                children.append(try demangleSwift3ProtocolName())
            }
            type = Node(kind: .protocolList, children: [Node(kind: .typeList, children: children)])
        case "Q":
            if scanner.conditional(scalar: "u") {
                type = Node(kind: .opaqueReturnType)
            } else if scanner.conditional(scalar: "U") {
                let index = try demangleIndex()
                type = Node(kind: .opaqueReturnType, child: Node(kind: .opaqueReturnTypeIndex, contents: .index(index)))
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
        case "x": type = Node(kind: .dependentGenericParamType, contents: .text(archetypeName(0, 0)), children: [Node(kind: .index, contents: .index(0)), Node(kind: .index, contents: .index(0))])
        case "w": type = try demangleSwift3AssociatedTypeSimple()
        case "W": type = try demangleSwift3AssociatedTypeCompound()
        case "R": type = Node(kind: .inOut, children: try demangleSwift3Type().children)
        case "S": type = try demangleSwift3SubstitutionIndex()
        case "T": type = try demangleSwift3Tuple(variadic: false)
        case "t": type = try demangleSwift3Tuple(variadic: true)
        case "u": type = Node(kind: .dependentGenericType, children: [try demangleSwift3GenericSignature(), try demangleSwift3Type()])
        case "C": type = try demangleSwift3DeclarationName(kind: .class)
        case "V": type = try demangleSwift3DeclarationName(kind: .structure)
        case "O": type = try demangleSwift3DeclarationName(kind: .enum)
        default: throw scanner.unexpectedError()
        }
        return Node(kind: .type, children: [type])
    }
    
    mutating func demangleSwift3ArchetypeType() throws(DemanglingError) -> Node {
        switch try scanner.readScalar() {
        case "Q":
            let result = Node(kind: .associatedTypeRef, children: [try demangleSwift3ArchetypeType(), try demangleSwift3Identifier()])
            nameStack.append(result)
            return result
        case "S":
            let index = try demangleSwift3SubstitutionIndex()
            let result = Node(kind: .associatedTypeRef, children: [index, try demangleSwift3Identifier()])
            nameStack.append(result)
            return result
        case "s":
            let root = Node(kind: .module, contents: .text(stdlibName))
            let result = Node(kind: .associatedTypeRef, children: [root, try demangleSwift3Identifier()])
            nameStack.append(result)
            return result
        default: throw scanner.unexpectedError()
        }
    }
    
    mutating func demangleSwift3ImplConvention(kind: Node.Kind) throws(DemanglingError) -> String {
        let scalar = try scanner.readScalar()
        switch (scalar, (kind == .implErrorResult ? .implResult : kind)) {
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
    
    mutating func demangleSwift3ImplParameterOrResult(kind: Node.Kind) throws(DemanglingError) -> Node {
        var k: Node.Kind
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
        let conventionNode = Node(kind: .implConvention, contents: .text(convention))
        return Node(kind: k, children: [conventionNode, type])
    }
    
    
    mutating func demangleSwift3Tuple(variadic: Bool) throws(DemanglingError) -> Node {
        var children = [Node]()
        while !scanner.conditional(scalar: "_") {
            var elementChildren = [Node]()
            let peek = try scanner.requirePeek()
            if (peek >= "0" && peek <= "9") || peek == "o" {
                elementChildren.append(try demangleSwift3Identifier(kind: .tupleElementName))
            }
            elementChildren.append(try demangleSwift3Type())
            children.append(Node(kind: .tupleElement, children: elementChildren))
        }
        if variadic, let last = children.popLast() {
            last.insertChild(Node(kind: .variadicMarker), at: 0)
            children.append(last)
        }
        return Node(kind: .tuple, children: children)
    }
    
    mutating func demangleSwift3FunctionType(kind: Node.Kind) throws(DemanglingError) -> Node {
        var children = [Node]()
        if scanner.conditional(scalar: "z") {
            children.append(Node(kind: .throwsAnnotation))
        }
        children.append(Node(kind: .argumentTuple, children: [try demangleSwift3Type()]))
        children.append(Node(kind: .returnType, children: [try demangleSwift3Type()]))
        return Node(kind: kind, children: children)
    }
    
    mutating func demangleSwift3Identifier(kind: Node.Kind? = nil) throws(DemanglingError) -> Node {
        let isPunycode = scanner.conditional(scalar: "X")
        let k: Node.Kind
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
            (isOperator, k) = (false, kind ?? Node.Kind.identifier)
        }
        
        var identifier = try scanner.readScalars(count: Int(scanner.readInt()))
        if isPunycode {
            identifier = try Punycode.decodePunycode(identifier)
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
        
        return Node(kind: k, contents: .text(identifier), children: [])
    }
}

fileprivate func archetypeName(_ index: UInt64, _ depth: UInt64) -> String {
    var result = ""
    var i = index
    repeat {
        result.unicodeScalars.append(UnicodeScalar(("A" as UnicodeScalar).value + UInt32(i % 26))!)
        i /= 26
    } while i > 0
    if depth != 0 {
        result += depth.description
    }
    return result
}

extension String.UnicodeScalarView {
    fileprivate func reduceThrowable<Result, E: Error>(_ initialResult: Result, _ nextPartialResult: (Result, Unicode.Scalar) throws(E) -> Result) throws(E) -> Result {
        do {
            return try reduce(initialResult, nextPartialResult)
        } catch {
            throw error as! E
        }
    }
}
