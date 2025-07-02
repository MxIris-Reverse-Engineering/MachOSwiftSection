struct Demangler<C>: Sendable where C: Collection, C.Iterator.Element == UnicodeScalar, C: Sendable, C.Index: Sendable {
    private var scanner: ScalarScanner<C>
    private var nameStack: [Node] = []
    private var substitutions: [Node] = []
    private var words: [String] = []
    private var symbolicReferences: [Int32] = []
    private var isOldFunctionTypeMangling: Bool = false
    private var flavor: ManglingFlavor = .default
    private var symbolicReferenceIndex: Int = 0

    var symbolicReferenceResolver: SymbolicReferenceResolver? = nil

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
    private func require<T>(_ optional: T?) throws -> T {
        if let v = optional {
            return v
        } else {
            throw failure
        }
    }

    private func require(_ value: Bool) throws {
        if !value {
            throw failure
        }
    }

    private var failure: Error {
        return scanner.unexpectedError()
    }

    private mutating func readManglingPrefix() throws {
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

    private mutating func popTopLevelInto(_ parent: inout Node) throws {
        while var funcAttr = pop(where: { $0.isFunctionAttr }) {
            switch funcAttr.kind {
            case .partialApplyForwarder,
                 .partialApplyObjCForwarder:
                try popTopLevelInto(&funcAttr)
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

    package mutating func demangleSymbol() throws -> Node {
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
        var topLevel = Node(kind: .global)
        try popTopLevelInto(&topLevel)
        if let suffix {
            topLevel.addChild(suffix)
        }
        try require(topLevel.children.count != 0)
        return topLevel
    }

    package mutating func demangleType() throws -> Node {
        reset()

        try parseAndPushNames()
        if let result = pop() {
            return result
        }

        return Node(kind: .suffix, contents: .name(String(String.UnicodeScalarView(scanner.scalars))), children: [])
    }

    private mutating func parseAndPushNames() throws {
        while !scanner.isAtEnd {
            try nameStack.append(demangleOperator())
        }
    }

    private mutating func demangleSymbolicReference(rawValue: UInt8) throws -> Node {
        guard let (kind, directness) = SymbolicReference.symbolicReference(for: rawValue) else {
            throw SwiftSymbolParseError.requiredNonOptional
        }
        guard let symbolicReferenceResolver, let symbol = symbolicReferenceResolver(kind, directness, symbolicReferenceIndex) else {
            throw SwiftSymbolParseError.requiredNonOptional
        }
        symbolicReferenceIndex += 1
        if (kind == .context || kind == .objectiveCProtocol) && (symbol.kind != .opaqueTypeDescriptorSymbolicReference && symbol.kind != .opaqueReturnTypeOf) {
            substitutions.append(symbol)
        }
        return symbol
    }

    private mutating func demangleTypeAnnotation() throws -> Node {
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
        default: throw failure
        }
    }

    private mutating func demangleOperator() throws -> Node {
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
        case "s": return Node(kind: .module, contents: .name(stdlibName))
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
            return Node(kind: .suffix, contents: .name(scanner.remainder()))
        case "$": return try demangleIntegerType()
        default:
            try scanner.backtrack()
            return try demangleIdentifier()
        }
    }

    private mutating func demangleNatural() throws -> UInt64? {
        return try scanner.conditionalInt()
    }

    private mutating func demangleIndex() throws -> UInt64 {
        if scanner.conditional(scalar: "_") {
            return 0
        }
        let value = try require(demangleNatural())
        try scanner.match(scalar: "_")
        return value + 1
    }

    private mutating func demangleIndexAsName() throws -> Node {
        return try Node(kind: .number, contents: .index(demangleIndex()))
    }

    private mutating func demangleMultiSubstitutions() throws -> Node {
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

    private mutating func pushMultiSubstitutions(repeatCount: Int, index: Int) throws -> Node {
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

    private mutating func popFunctionType(kind: Node.Kind, hasClangType: Bool = false) throws -> Node {
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

    private mutating func popFunctionParams(kind: Node.Kind) throws -> Node {
        let paramsType: Node
        if pop(kind: .emptyList) != nil {
            return Node(kind: kind, child: Node(kind: .type, child: Node(kind: .tuple)))
        } else {
            paramsType = try require(pop(kind: .type))
        }

        if kind == .argumentTuple {
            let params = try require(paramsType.children.first)
            let numParams = params.kind == .tuple ? params.children.count : 1
            return Node(kind: kind, contents: .index(UInt64(numParams)), children: [paramsType])
        } else {
            return Node(kind: kind, children: [paramsType])
        }
    }

    private mutating func getLabel(params: Node, idx: Int) throws -> Node {
        if isOldFunctionTypeMangling {
            let param = try require(params.children.at(idx))
            if let label = param.children.enumerated().first(where: { $0.element.kind == .tupleElementName }) {
                param.removeChild(at: label.offset)
                return Node(kind: .identifier, contents: .name(label.element.text ?? ""))
            }
            return Node(kind: .firstElementMarker)
        }
        return try require(pop())
    }

    private mutating func popFunctionParamLabels(type: Node) throws -> Node? {
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

    private mutating func popTuple() throws -> Node {
        let root = Node(kind: .tuple)
        if pop(kind: .emptyList) == nil {
            var firstElem = false
            repeat {
                firstElem = pop(kind: .firstElementMarker) != nil
                let tupleElement = Node(kind: .tupleElement)
                if let variadicMarker = pop(kind: .variadicMarker) {
                    tupleElement.addChild(variadicMarker)
                }
                if let ident = pop(kind: .identifier), case let .name(text) = ident.contents {
                    tupleElement.addChild(Node(kind: .tupleElementName, contents: .name(text)))
                }
                try tupleElement.addChild(require(pop(kind: .type)))
                root.addChild(tupleElement)
            } while !firstElem
            root.reverseChildren()
        }
        return Node(kind: .type, child: root)
    }

    private mutating func popPack(kind: Node.Kind = .pack) throws -> Node {
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

    private mutating func popSilPack() throws -> Node {
        switch try scanner.readScalar() {
        case "d": return try popPack(kind: .silPackDirect)
        case "i": return try popPack(kind: .silPackIndirect)
        default: throw failure
        }
    }

    private mutating func popTypeList() throws -> Node {
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

    private mutating func popProtocol() throws -> Node {
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

    private mutating func popAnyProtocolConformanceList() throws -> Node {
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

    private mutating func demangleRetroactiveProtocolConformanceRef() throws -> Node {
        let module = try require(popModule())
        let proto = try require(popProtocol())
        return Node(kind: .protocolConformanceRefInOtherModule, children: [proto, module])
    }

    private mutating func demangleConcreteProtocolConformance() throws -> Node {
        let conditionalConformanceList = try require(popAnyProtocolConformanceList())
        let conformanceRef = try pop(kind: .protocolConformanceRefInTypeModule) ?? pop(kind: .protocolConformanceRefInProtocolModule) ?? demangleRetroactiveProtocolConformanceRef()
        return try Node(kind: .concreteProtocolConformance, children: [require(pop(kind: .type)), conformanceRef, conditionalConformanceList])
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

    private mutating func demangleDependentProtocolConformanceRoot() throws -> Node {
        let index = try demangleDependentConformanceIndex()
        let prot = try popProtocol()
        return try Node(kind: .dependentProtocolConformanceRoot, children: [require(pop(kind: .type)), prot, index])
    }

    private mutating func demangleDependentProtocolConformanceInherited() throws -> Node {
        let index = try demangleDependentConformanceIndex()
        let prot = try popProtocol()
        let nested = try require(popDependentProtocolConformance())
        return Node(kind: .dependentProtocolConformanceInherited, children: [nested, prot, index])
    }

    private mutating func popDependentAssociatedConformance() throws -> Node {
        let prot = try popProtocol()
        let dependentType = try require(pop(kind: .type))
        return Node(kind: .dependentAssociatedConformance, children: [dependentType, prot])
    }

    private mutating func demangleDependentProtocolConformanceAssociated() throws -> Node {
        let index = try demangleDependentConformanceIndex()
        let assoc = try popDependentAssociatedConformance()
        let nested = try require(popDependentProtocolConformance())
        return Node(kind: .dependentProtocolConformanceAssociated, children: [nested, assoc, index])
    }

    private mutating func demangleDependentConformanceIndex() throws -> Node {
        let index = try demangleIndex()
        if index == 1 {
            return Node(kind: .unknownIndex)
        }
        return Node(kind: .index, contents: .index(index - 2))
    }

    private mutating func popModule() -> Node? {
        if let ident = pop(kind: .identifier) {
            return ident.changeKind(.module)
        } else {
            return pop(kind: .module)
        }
    }

    private mutating func popContext() throws -> Node {
        if let mod = popModule() {
            return mod
        } else if let type = pop(kind: .type) {
            let child = try require(type.children.first)
            try require(child.kind.isContext)
            return child
        }
        return try require(pop { $0.isContext })
    }

    private mutating func popTypeAndGetChild() throws -> Node {
        return try require(pop(kind: .type)?.children.first)
    }

    private mutating func popTypeAndGetAnyGeneric() throws -> Node {
        let child = try popTypeAndGetChild()
        try require(child.kind.isAnyGeneric)
        return child
    }

    private mutating func popAssociatedTypeName() throws -> Node {
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

    private mutating func popAssociatedTypePath() throws -> Node {
        var firstElem = false
        var assocTypePath = [Node]()
        repeat {
            firstElem = pop(kind: .firstElementMarker) != nil
            try assocTypePath.append(require(popAssociatedTypeName()))
        } while !firstElem
        return Node(kind: .assocTypePath, children: assocTypePath.reversed())
    }

    private mutating func popProtocolConformance() throws -> Node {
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

    private mutating func getDependentGenericParamType(depth: Int, index: Int) throws -> Node {
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

        return Node(kind: .dependentGenericParamType, contents: .name(name), children: [
            Node(kind: .index, contents: .index(UInt64(depth))),
            Node(kind: .index, contents: .index(UInt64(index))),
        ])
    }

    private mutating func demangleStandardSubstitution() throws -> Node {
        switch try scanner.readScalar() {
        case "o": return Node(kind: .module, contents: .name(objcModule))
        case "C": return Node(kind: .module, contents: .name(cModule))
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

    private mutating func demangleIdentifier() throws -> Node {
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
        let result = Node(kind: .identifier, contents: .name(identifier))
        substitutions.append(result)
        return result
    }

    private mutating func demangleOperatorIdentifier() throws -> Node {
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
        case "i": return Node(kind: .infixOperator, contents: .name(str))
        case "p": return Node(kind: .prefixOperator, contents: .name(str))
        case "P": return Node(kind: .postfixOperator, contents: .name(str))
        default: throw failure
        }
    }

    private mutating func demangleLocalIdentifier() throws -> Node {
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
            return try Node(kind: .relatedEntityDeclName, contents: .name(String(c)), children: [require(pop())])
        default:
            try scanner.backtrack()
            let discriminator = try demangleIndexAsName()
            let name = try require(pop(where: { $0.isDeclName }))
            return Node(kind: .localDeclName, children: [discriminator, name])
        }
    }

    private mutating func demangleBuiltinType() throws -> Node {
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
            return Node(kind: .builtinFixedArray, children: [size, element])
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

    private mutating func demangleAnyGenericType(kind: Node.Kind) throws -> Node {
        let name = try require(pop(where: { $0.isDeclName }))
        let ctx = try popContext()
        let type = Node(typeWithChildKind: kind, childChildren: [ctx, name])
        substitutions.append(type)
        return type
    }

    private mutating func demangleExtensionContext() throws -> Node {
        let genSig = pop(kind: .dependentGenericSignature)
        let module = try require(popModule())
        let type = try popTypeAndGetAnyGeneric()
        if let g = genSig {
            return Node(kind: .extension, children: [module, type, g])
        } else {
            return Node(kind: .extension, children: [module, type])
        }
    }

    private enum ManglingFlavor {
        case `default`
        case embedded
    }

    private func getParentId(parent: Node, flavor: ManglingFlavor) -> String {
        return "{ParentId}"
    }

    private mutating func setParentForOpaqueReturnTypeNodes(visited: Node, parentId: String) {
        if visited.kind == .opaqueReturnType {
            if visited.children.last?.kind == .opaqueReturnTypeParent {
                return
            }
            visited.addChild(Node(kind: .opaqueReturnTypeParent, contents: .name(parentId)))
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

    private mutating func demanglePlainFunction() throws -> Node {
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

    private mutating func demangleRetroactiveConformance() throws -> Node {
        let index = try demangleIndexAsName()
        let conformance = try require(popAnyProtocolConformance())
        return Node(kind: .retroactiveConformance, children: [index, conformance])
    }

    private mutating func demangleBoundGenericType() throws -> Node {
        let (array, retroactiveConformances) = try demangleBoundGenerics()
        let nominal = try popTypeAndGetAnyGeneric()
        var children = try [demangleBoundGenericArgs(nominal: nominal, array: array, index: 0)]
        if !retroactiveConformances.isEmpty {
            children.append(Node(kind: .typeList, children: retroactiveConformances.reversed()))
        }
        let type = Node(kind: .type, children: children)
        substitutions.append(type)
        return type
    }

    private mutating func popRetroactiveConformances() throws -> Node? {
        var retroactiveConformances: [Node] = []
        while let conformance = pop(kind: .retroactiveConformance) {
            retroactiveConformances.append(conformance)
        }
        retroactiveConformances = retroactiveConformances.reversed()
        return retroactiveConformances.isEmpty ? nil : Node(kind: .typeList, children: retroactiveConformances)
    }

    private mutating func demangleBoundGenerics() throws -> (typeLists: [Node], conformances: [Node]) {
        let retroactiveConformances = try popRetroactiveConformances()

        var array = [Node]()
        while true {
            var children = [Node]()
            while let t = pop(kind: .type) {
                children.append(t)
            }
            array.append(Node(kind: .typeList, children: children.reversed()))

            if pop(kind: .emptyList) != nil {
                break
            } else {
                _ = try require(pop(kind: .firstElementMarker))
            }
        }

        return (array, retroactiveConformances?.children ?? [])
    }

    private mutating func demangleBoundGenericArgs(nominal: Node, array: [Node], index: Int) throws -> Node {
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

    private mutating func demangleImplParamConvention(kind: Node.Kind) throws -> Node? {
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
        return Node(kind: kind, child: Node(kind: .implConvention, contents: .name(attr)))
    }

    private mutating func demangleImplResultConvention(kind: Node.Kind) throws -> Node? {
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
        return Node(kind: kind, child: Node(kind: .implConvention, contents: .name(attr)))
    }

    private mutating func demangleImplParameterSending() -> Node? {
        guard scanner.conditional(scalar: "T") else {
            return nil
        }
        return Node(kind: .implParameterSending, contents: .name("sending"))
    }

    private mutating func demangleImplResultDifferentiability() -> Node {
        return Node(kind: .implParameterResultDifferentiability, contents: .name(scanner.conditional(scalar: "w") ? "@noDerivative" : ""))
    }

    private mutating func demangleClangType() throws -> Node {
        let numChars = try require(demangleNatural())
        let text = try scanner.readScalars(count: Int(numChars))
        return Node(kind: .clangType, contents: .name(text))
    }

    private mutating func demangleImplFunctionType() throws -> Node {
        var typeChildren = [Node]()
        if scanner.conditional(scalar: "s") {
            let (substitutions, conformances) = try demangleBoundGenerics()
            let sig = try require(pop(kind: .dependentGenericSignature))
            let subsNode = try Node(kind: .implPatternSubstitutions, children: [sig, require(substitutions.first)] + conformances)
            typeChildren.append(subsNode)
        }

        if scanner.conditional(scalar: "I") {
            let (substitutions, conformances) = try demangleBoundGenerics()
            let subsNode = try Node(kind: .implInvocationSubstitutions, children: [require(substitutions.first)] + conformances)
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
        typeChildren.append(Node(kind: .implConvention, contents: .name(cAttr)))

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
            let node = Node(kind: .implFunctionConvention, child: Node(kind: .implFunctionConventionName, contents: .name(fConv)))
            if hasClangType {
                try node.addChild(demangleClangType())
            }
            typeChildren.append(node)
        }

        if scanner.conditional(scalar: "A") {
            typeChildren.append(Node(kind: .implCoroutineKind, contents: .name("yield_once")))
        } else if scanner.conditional(scalar: "I") {
            typeChildren.append(Node(kind: .implCoroutineKind, contents: .name("yield_once_2")))
        } else if scanner.conditional(scalar: "G") {
            typeChildren.append(Node(kind: .implCoroutineKind, contents: .name("yield_many")))
        }

        if scanner.conditional(scalar: "h") {
            typeChildren.append(Node(kind: .implFunctionAttribute, contents: .name("@Sendable")))
        }

        if scanner.conditional(scalar: "H") {
            typeChildren.append(Node(kind: .implFunctionAttribute, contents: .name("@async")))
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
            if let diff = demangleImplParameterSending() {
                param.addChild(diff)
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

    private mutating func demangleMetatype() throws -> Node {
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

    private mutating func demanglePrivateContextDescriptor() throws -> Node {
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

    private mutating func demangleArchetype() throws -> Node {
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
                    Node(kind: .typeList, children: boundGenericArgs + retroactiveConformances),
                ]
            )
            let opaqueType = Node(kind: .type, child: opaque)
            substitutions.append(opaqueType)
            return opaqueType
        case "r":
            return Node(typeWithChildKind: .opaqueReturnType, childChildren: [])
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

    private mutating func demangleAssociatedTypeSimple(index: Node?) throws -> Node {
        let atName = try popAssociatedTypeName()
        let gpi = try index.map { Node(kind: .type, child: $0) } ?? require(pop(kind: .type))
        return Node(typeWithChildKind: .dependentMemberType, childChildren: [gpi, atName])
    }

    private mutating func demangleAssociatedTypeCompound(index: Node?) throws -> Node {
        var assocTypeNames = [Node]()
        var firstElem = false
        repeat {
            firstElem = pop(kind: .firstElementMarker) != nil
            try assocTypeNames.append(popAssociatedTypeName())
        } while !firstElem

        var base = try index.map { Node(kind: .type, child: $0) } ?? require(pop(kind: .type))
        while let assocType = assocTypeNames.popLast() {
            base = Node(kind: .type, child: Node(kind: .dependentMemberType, children: [Node(kind: .type, child: base), assocType]))
        }
        return base
    }

    private mutating func demangleGenericParamIndex() throws -> Node {
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

    private mutating func demangleThunkOrSpecialization() throws -> Node {
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
            for t in types {
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
        case "e": return try Node(kind: .outlinedBridgedMethod, contents: .name(demangleBridgedMethodParams()))
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
            case "S": return Node(kind: .hasSymbolQuery)
            default: throw failure
            }
        default: throw failure
        }
    }

    private mutating func demangleAutoDiffFunctionOrSimpleThunk(kind: Node.Kind) throws -> Node {
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

    private mutating func demangleAutoDiffFunctionKind() throws -> Node {
        let kind = try scanner.readScalar()
        guard let autoDiffFunctionKind = AutoDiffFunctionKind(UInt64(kind.value)) else {
            throw failure
        }
        return Node(kind: .autoDiffFunctionKind, contents: .index(UInt64(autoDiffFunctionKind.rawValue.value)))
    }

    private mutating func demangleAutoDiffSubsetParametersThunk() throws -> Node {
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

    private mutating func demangleAutoDiffSelfReorderingReabstractionThunk() throws -> Node {
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

    private mutating func demangleDifferentiabilityWitness() throws -> Node {
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

    private mutating func demangleIndexSubset() throws -> Node {
        var str = ""
        while let c = scanner.conditional(where: { $0 == "S" || $0 == "U" }) {
            str.unicodeScalars.append(c)
        }
        try require(!str.isEmpty)
        return Node(kind: .indexSubset, contents: .name(str))
    }

    private mutating func demangleDifferentiableFunctionType() throws -> Node {
        let kind: Differentiability = switch try scanner.readScalar() {
        case "f": .forward
        case "r": .reverse
        case "d": .normal
        case "l": .linear
        default: throw failure
        }
        return Node(kind: .differentiableFunctionType, contents: .index(UInt64(kind.rawValue.value)))
    }

    private mutating func demangleBridgedMethodParams() throws -> String {
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

    private mutating func demangleGenericSpecialization(kind: Node.Kind, droppedArguments: Node? = nil) throws -> Node {
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

    private mutating func demangleGenericSpecializationWithDroppedArguments() throws -> Node {
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

    private mutating func demangleFunctionSpecialization() throws -> Node {
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
            guard kindName.kind == .functionSignatureSpecializationParamKind, case let .index(i) = kindName.contents else { throw failure }
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
                param.insertChild(Node(kind: .functionSignatureSpecializationParamPayload, contents: .name(text)), at: fixedChildrenEndIndex)
                spec.setChild(param, at: paramIndexPair.offset)
            default: break
            }
        }
        return spec
    }

    private mutating func demangleFuncSpecParam(kind: Node.Kind) throws -> Node {
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
                param.addChild(Node(kind: .functionSignatureSpecializationParamPayload, contents: .name(encoding)))
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

    private mutating func addFuncSpecParamNumber(param: inout Node, kind: FunctionSigSpecializationParamKind) throws {
        param.addChild(Node(kind: .functionSignatureSpecializationParamKind, contents: .index(kind.rawValue)))
        let str = scanner.readWhile { $0.isDigit }
        try require(!str.isEmpty)
        param.addChild(Node(kind: .functionSignatureSpecializationParamPayload, contents: .name(str)))
    }

    private mutating func demangleSpecAttributes(kind: Node.Kind, demangleUniqueId: Bool = false) throws -> Node {
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

    private mutating func demangleWitness() throws -> Node {
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

    private mutating func popAssocTypePath() throws -> Node {
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

    private mutating func demangleSpecialType() throws -> Node {
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
            case "D": return Node(kind: .type, child: Node(kind: .sugaredDictionary))
            case "p": return Node(kind: .type, child: Node(kind: .sugaredParen))
            default: throw failure
            }
        default: throw failure
        }
    }

    private mutating func demangleSymbolicExtendedExistentialType() throws -> Node {
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

    private mutating func demangleExtendedExistentialShape(nodeKind: UnicodeScalar) throws -> Node {
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

    private mutating func demangleMetatypeRepresentation() throws -> Node {
        let value: String
        switch try scanner.readScalar() {
        case "t": value = "@thin"
        case "T": value = "@thick"
        case "o": value = "@objc_metatype"
        default: throw failure
        }
        return Node(kind: .metatypeRepresentation, contents: .name(value))
    }

    private mutating func demangleAccessor(child: Node) throws -> Node {
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

    private mutating func demangleFunctionEntity() throws -> Node {
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

    private mutating func demangleEntity(kind: Node.Kind) throws -> Node {
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

    private mutating func demangleVariable() throws -> Node {
        return try demangleAccessor(child: demangleEntity(kind: .variable))
    }

    private mutating func demangleSubscript() throws -> Node {
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

    private mutating func demangleProtocolList() throws -> Node {
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

    private mutating func demangleProtocolListType() throws -> Node {
        return try Node(kind: .type, child: demangleProtocolList())
    }

    private mutating func demangleConstrainedExistentialRequirementList() throws -> Node {
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

    private mutating func demangleGenericSignature(hasParamCounts: Bool) throws -> Node {
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

    private mutating func demangleGenericRequirement() throws -> Node {
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
            let name = Node(kind: .identifier, contents: .name(String(String.UnicodeScalarView([c]))))
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

    private mutating func demangleGenericType() throws -> Node {
        let genSig = try require(pop(kind: .dependentGenericSignature))
        let type = try require(pop(kind: .type))
        return Node(typeWithChildKind: .dependentGenericType, childChildren: [genSig, type])
    }

    private mutating func demangleValueWitness() throws -> Node {
        let code = try scanner.readScalars(count: 2)
        let kind = try require(ValueWitnessKind(code: code))
        return try Node(kind: .valueWitness, contents: .index(kind.rawValue), children: [require(pop(kind: .type))])
    }
}

extension Demangler {
    private mutating func demangleMacroExpansion() throws -> Node {
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
        if isAttached {
            result = try Node(kind: kind, children: [context, require(attachedName), macroName, discriminator])
        } else {
            result = Node(kind: kind, children: [context, macroName, discriminator])
        }
        if let privateDiscriminator {
            result.addChild(privateDiscriminator)
        }
        return result
    }

    private mutating func demangleIntegerType() throws -> Node {
        if scanner.conditional(scalar: "n") {
            return try Node(kind: .type, children: [Node(kind: .negativeInteger, contents: .index(demangleIndex()))])
        } else {
            return try Node(kind: .type, children: [Node(kind: .integer, contents: .index(demangleIndex()))])
        }
    }

    private mutating func demangleObjCTypeName() throws -> Node {
        let type = Node(kind: .type)
        if scanner.conditional(scalar: "C") {
            let module: Node
            if scanner.conditional(scalar: "s") {
                module = Node(kind: .module, contents: .name(stdlibName))
            } else {
                module = try demangleIdentifier().changeKind(.module)
            }
            try type.addChild(Node(kind: .class, children: [module, demangleIdentifier()]))
        } else if scanner.conditional(scalar: "P") {
            let module: Node
            if scanner.conditional(scalar: "s") {
                module = Node(kind: .module, contents: .name(stdlibName))
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
