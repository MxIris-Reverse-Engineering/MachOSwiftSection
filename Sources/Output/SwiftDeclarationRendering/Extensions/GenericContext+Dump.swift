import Semantic
import MachOKit
import MachOSwiftSection
import Utilities
@_spi(Internals) import Demangling
@_spi(Internals) import SwiftInspection

package func genericParameterName(depth: Int, index: Int) throws -> String {
    var charIndex = index
    var name = ""
    repeat {
        try name.unicodeScalars.append(required(UnicodeScalar(UnicodeScalar("A").value + UInt32(charIndex % 26))))
        charIndex /= 26
    } while charIndex != 0
    if depth != 0 {
        name = "\(name)\(depth)"
    }
    return name
}

package func genericValueName(depth: Int, index: Int) throws -> String {
    var charIndex = index
    var name = ""
    repeat {
        try name.unicodeScalars.append(required(UnicodeScalar(UnicodeScalar("a").value + UInt32(charIndex % 26))))
        charIndex /= 26
    } while charIndex != 0
    if depth != 0 {
        name = "\(name)\(depth)"
    }
    return name
}

extension TargetGenericContext {
    /// - Parameter depthLayout: How this context's parameters split into
    ///   depths (`GenericParameterDepthLayout.make(for:ownedBy:in:)`), which
    ///   decides the depth each printed name carries — the one its fields and
    ///   requirements name it by.
    @SemanticStringBuilder
    package func dumpGenericSignature(resolver: DemangleResolver, depthLayout: GenericParameterDepthLayout, in context: some ReadingContext, isDumpCurrentLevelParams: Bool = true, isDumpCurrentLevelRequirements: Bool = true, @SemanticStringBuilder conformancesBuilder: () async throws -> SemanticString = { "" }) async throws -> SemanticString {
        if (isDumpCurrentLevelParams ? currentParameters : parameters).count > 0 {
            Standard("<")
            try await dumpGenericParameters(depthLayout: depthLayout, in: context, isDumpCurrentLevel: isDumpCurrentLevelParams)
            Standard(">")
        }

        try await conformancesBuilder()

        if (isDumpCurrentLevelRequirements ? uniqueCurrentRequirements(in: context) : requirements).count > 0 {
            Space()
            Keyword(.where)
            Space()
            try await dumpGenericRequirements(resolver: resolver, in: context, isDumpCurrentLevel: isDumpCurrentLevelRequirements)
        }
    }
}

extension TargetGenericContext {
    /// Prints the parameter names, `A, B, A1, …`: the context's own
    /// parameters, or with `isDumpCurrentLevel` off every parameter in scope.
    ///
    /// A name spells its parameter's `(depth, index)`, and only
    /// `depthLayout` knows the depth. The parent chain does not: a type that
    /// declares no parameter is still a generic ancestor, and an extension
    /// ancestor can span several depths — counting ancestors printed
    /// `struct Inner<A2>` over a field the record names `A1`.
    @SemanticStringBuilder
    package func dumpGenericParameters(depthLayout: GenericParameterDepthLayout, in context: some ReadingContext, isDumpCurrentLevel: Bool = true) async throws -> SemanticString {
        // The context's own parameters are the tail of the cumulative list,
        // so the positions below are offsets into `parameters` either way.
        let firstPrintedOffset = isDumpCurrentLevel ? parameters.count - currentParameters.count : 0
        let printedParameters = parameters[firstPrintedOffset...]
        // `values` holds one descriptor per value parameter, in parameter
        // order; the printed ones start after those of the skipped parameters.
        var valueIndex = parameters[..<firstPrintedOffset].filter { $0.kind == .value }.count
        for (offset, parameter) in printedParameters.enumerated() {
            let flatIndex = firstPrintedOffset + offset
            // A layout that does not cover the parameter (an unreadable
            // ancestor) names it by its position among the printed ones.
            let position = depthLayout.position(ofParameterAt: flatIndex) ?? (depth: depthLayout.depthCount, index: offset)

            if parameter.kind == .typePack {
                Keyword(.each)
                Space()
            } else if parameter.kind == .value {
                Keyword(.let)
                Space()
            }

            switch parameter.kind {
            case .type,
                 .typePack:
                try Standard(genericParameterName(depth: position.depth, index: position.index))
            case .value:
                try Standard(genericValueName(depth: position.depth, index: position.index))
                Standard(": ")
                if let value = values[safe: valueIndex] {
                    switch value.type {
                    case .int:
                        TypeName(kind: .other, "Int")
                    }
                }
                valueIndex += 1
            default:
                Standard("")
            }

            if offset < printedParameters.count - 1 {
                Standard(", ")
            }
        }
    }

    @SemanticStringBuilder
    package func dumpGenericRequirements(resolver: DemangleResolver, in context: some ReadingContext, isDumpCurrentLevel: Bool = true) async throws -> SemanticString {
        switch resolver {
        case .options(let demangleOptions):
            try await dumpGenericRequirements(using: demangleOptions, in: context, isDumpCurrentLevel: isDumpCurrentLevel)
        case .builder(let builder):
            try await dumpGenericRequirements(in: context, isDumpCurrentLevel: isDumpCurrentLevel, builder: builder)
        }
    }

    @SemanticStringBuilder
    package func dumpGenericRequirements(using options: DemangleOptions, in context: some ReadingContext, isDumpCurrentLevel: Bool = true) async throws -> SemanticString {
        try await dumpGenericRequirements(in: context, isDumpCurrentLevel: isDumpCurrentLevel) { $0.printSemantic(using: options) }
    }

    @SemanticStringBuilder
    package func dumpGenericRequirements(in context: some ReadingContext, isDumpCurrentLevel: Bool = true, @SemanticStringBuilder builder: (Node) async throws -> SemanticString) async throws -> SemanticString {
        for (offset, requirement) in (isDumpCurrentLevel ? uniqueCurrentRequirements(in: context) : requirements).offsetEnumerated() {
            try await requirement.dump(in: context, builder: builder)
            if !offset.isEnd {
                Standard(",")
                Space()
            }
        }
    }
}

extension Node {
    fileprivate static let firstGenericParamType: Node = .create(kind: .type) {
        Node.create(kind: .dependentGenericParamType) {
            Node.create(kind: .index, index: 0)
            Node.create(kind: .index, index: 0)
        }
    }
}

extension GenericRequirementDescriptor {
    @SemanticStringBuilder
    package func dump(resolver: DemangleResolver, in context: some ReadingContext) async throws -> SemanticString {
        switch resolver {
        case .options(let demangleOptions):
            try await dump(using: demangleOptions, in: context)
        case .builder(let builder):
            try await dump(in: context, builder: builder)
        }
    }

    @SemanticStringBuilder
    package func dump(using options: DemangleOptions, in context: some ReadingContext) async throws -> SemanticString {
        try await dump(in: context) { $0.printSemantic(using: options) }
    }

    @SemanticStringBuilder
    package func dump(in context: some ReadingContext, @SemanticStringBuilder builder: (Node) async throws -> SemanticString) async throws -> SemanticString {
        try await dumpParameterName(in: context, builder: builder)

        if layout.flags.kind == .sameType {
            Space()
            Standard("==")
            Space()
        } else {
            Standard(":")
            Space()
        }

        try await dumpContent(in: context, builder: builder)
    }

    @SemanticStringBuilder
    package func dumpParameterName(using options: DemangleOptions, in context: some ReadingContext) async throws -> SemanticString {
        try await dumpParameterName(in: context) { $0.printSemantic(using: options) }
    }

    @SemanticStringBuilder
    package func dumpParameterName(resolver: DemangleResolver, in context: some ReadingContext) async throws -> SemanticString {
        switch resolver {
        case .options(let demangleOptions):
            try await dumpParameterName(using: demangleOptions, in: context)
        case .builder(let builder):
            try await dumpParameterName(in: context, builder: builder)
        }
    }

    @SemanticStringBuilder
    package func dumpParameterName(in context: some ReadingContext, @SemanticStringBuilder builder: (Node) async throws -> SemanticString) async throws -> SemanticString {
        if layout.flags.contains(.isPackRequirement) {
            Keyword(.repeat)
            Space()
            Keyword(.each)
            Space()
        }

        try await builder(dumpParameterName(in: context))
    }

    package func dumpParameterName(in context: some ReadingContext) async throws -> Node {
        try SymbolicDemangler.demangleType(for: paramMangledName(in: context), in: context)
    }

    @SemanticStringBuilder
    package func dumpContent(resolver: DemangleResolver, in context: some ReadingContext) async throws -> SemanticString {
        switch resolver {
        case .options(let demangleOptions):
            try await dumpContent(using: demangleOptions, in: context)
        case .builder(let builder):
            try await dumpContent(in: context, builder: builder)
        }
    }

    @SemanticStringBuilder
    package func dumpContent(using options: DemangleOptions, in context: some ReadingContext) async throws -> SemanticString {
        try await dumpContent(in: context) { $0.printSemantic(using: options) }
    }

    @SemanticStringBuilder
    package func dumpContent(in context: some ReadingContext, @SemanticStringBuilder builder: (Node) async throws -> SemanticString) async throws -> SemanticString {
        switch try resolvedContent(in: context) {
        case .type(let mangledName):
            try await builder(SymbolicDemangler.demangleType(for: mangledName, in: context))
        case .protocol(let resolvableElement):
            switch resolvableElement {
            case .symbol(let unsolvedSymbol):
                try await SymbolicDemangler.demangleType(for: unsolvedSymbol, in: context).asyncMap { try await builder($0) }
            case .element(let element):
                switch element {
                case .objc(let objc):
                    let objcName = try objc.mangledName(in: context).rawString
                    let node = Node.createTransient(kind: .global, children: [
                        Node.createTransient(kind: .type, children: [
                            Node.createTransient(kind: .protocol, children: [
                                .createTransient(kind: .module, text: objcModule),
                                .createTransient(kind: .identifier, text: objcName),
                            ])
                        ])
                    ])
                    try await builder(node)
                case .swift(let protocolDescriptor):
                    try await builder(SymbolicDemangler.demangleContext(for: .protocol(protocolDescriptor), in: context))
                }
            }
        case .layout(let genericRequirementLayoutKind):
            switch genericRequirementLayoutKind {
            case .class:
                TypeName(kind: .other, "AnyObject")
            }
        case .conformance /* (let protocolConformanceDescriptor) */:
            Error("SwiftDumpConformance")
        case .invertedProtocols(let invertedProtocols):
            try await invertedProtocols.protocols.dumpInvertedProtocolNames(builder: builder)
        }
    }
}

extension GenericRequirementDescriptor {
    @SemanticStringBuilder
    package func dumpProtocolRequirement(resolver: DemangleResolver, in context: some ReadingContext) async throws -> SemanticString {
        switch resolver {
        case .options(let demangleOptions):
            try await dumpProtocolRequirement(using: demangleOptions, in: context)
        case .builder(let builder):
            try await dumpProtocolRequirement(in: context, builder: builder)
        }
    }

    @SemanticStringBuilder
    package func dumpProtocolRequirement(using options: DemangleOptions, in context: some ReadingContext) async throws -> SemanticString {
        try await dumpProtocolRequirement(in: context) { $0.printSemantic(using: options) }
    }

    @SemanticStringBuilder
    package func dumpProtocolRequirement(in context: some ReadingContext, @SemanticStringBuilder builder: (Node) async throws -> SemanticString) async throws -> SemanticString {
        try await dumpProtocolParameterName(in: context, builder: builder)

        if layout.flags.kind == .sameType {
            Space()
            Standard("==")
            Space()
        } else {
            Standard(":")
            Space()
        }

        try await dumpProtocolContent(in: context, builder: builder)
    }

    @SemanticStringBuilder
    package func dumpProtocolParameterName(in context: some ReadingContext, @SemanticStringBuilder builder: (Node) async throws -> SemanticString) async throws -> SemanticString {
        try await dumpProtocolMangledName(paramMangledName(in: context), in: context, builder: builder)
    }

    @SemanticStringBuilder
    private func dumpProtocolMangledName(_ mangledName: MangledName, in context: some ReadingContext, @SemanticStringBuilder builder: (Node) async throws -> SemanticString) async throws -> SemanticString {
        let node = try SymbolicDemangler.demangleType(for: mangledName, in: context)

        let params = node.filter(of: .dependentAssociatedTypeRef).compactMap { $0.first(of: .identifier)?.text }

        if params.isEmpty {
            if node == .firstGenericParamType {
                Keyword(.Self)
            } else {
                try await builder(node)
            }
        } else {
            for (offset, param) in params.offsetEnumerated() {
                if offset.isStart {
                    Keyword(.Self)
                    Standard(".")
                }
                Standard(param)
                if !offset.isEnd {
                    Standard(".")
                }
            }
        }
    }

    @SemanticStringBuilder
    package func dumpProtocolContent(in context: some ReadingContext, @SemanticStringBuilder builder: (Node) async throws -> SemanticString) async throws -> SemanticString {
        switch try resolvedContent(in: context) {
        case .type(let mangledName):
//            try builder(SymbolicDemangler.demangleType(for: mangledName, in: context))
            try await dumpProtocolMangledName(mangledName, in: context, builder: builder)
        case .protocol(let resolvableElement):
            switch resolvableElement {
            case .symbol(let unsolvedSymbol):
                try await SymbolicDemangler.demangleType(for: unsolvedSymbol, in: context).asyncMap { try await builder($0) }
            case .element(let element):
                switch element {
                case .objc(let objc):
                    let objcName = try objc.mangledName(in: context).rawString
                    let node = Node.createTransient(kind: .global, children: [
                        Node.createTransient(kind: .type, children: [
                            Node.createTransient(kind: .protocol, children: [
                                .createTransient(kind: .module, text: objcModule),
                                .createTransient(kind: .identifier, text: objcName),
                            ])
                        ])
                    ])
                    try await builder(node)
                case .swift(let protocolDescriptor):
                    try await builder(SymbolicDemangler.demangleContext(for: .protocol(protocolDescriptor), in: context))
                }
            }
        case .layout(let genericRequirementLayoutKind):
            switch genericRequirementLayoutKind {
            case .class:
                TypeName(kind: .other, "AnyObject")
            }
        case .conformance /* (let protocolConformanceDescriptor) */:
            Standard("SwiftDumpConformance")
        case .invertedProtocols(let invertedProtocols):
            try await invertedProtocols.protocols.dumpInvertedProtocolNames(builder: builder)
        }
    }
}

extension OptionSet {
    fileprivate func removing(_ element: Element) -> Self {
        var copy = self
        copy.remove(element)
        return copy
    }
}

extension InvertibleProtocolSet {
    /// Whether any invertible protocols are present in this set.
    package var hasInvertedProtocols: Bool {
        hasCopyable || hasEscapable
    }

    /// `Swift.Copyable` and `Swift.Escapable` as the type nodes a suppressed
    /// conformance names. They print through the caller's resolver like any
    /// other protocol reference, so they are spelled the way the names around
    /// them are — `Swift::Copyable` under module selectors (evolution proposal
    /// `module-selectors`) — rather than as text fixed here.
    ///
    /// One long-lived instance each: the interface printer memoizes a printed
    /// fragment by node identity, and a node freed after one print would hand
    /// its fragment to whatever is allocated at its address next.
    package static let copyableProtocolTypeNode = invertibleProtocolTypeNode(named: "Copyable")
    package static let escapableProtocolTypeNode = invertibleProtocolTypeNode(named: "Escapable")

    private static func invertibleProtocolTypeNode(named name: String) -> Node {
        Node.create(kind: .type, child: Node.create(kind: .protocol, children: [
            Node.create(kind: .module, text: stdlibName),
            Node.create(kind: .identifier, text: name),
        ]))
    }

    /// Dump the inverted protocol names (e.g., `~Swift.Copyable`, `~Swift.Escapable`),
    /// each protocol spelled by `builder`.
    @SemanticStringBuilder
    package func dumpInvertedProtocolNames(@SemanticStringBuilder builder: (Node) async throws -> SemanticString) async throws -> SemanticString {
        if hasCopyable && hasEscapable {
            Standard("~")
            try await builder(Self.copyableProtocolTypeNode)
            Standard(" & ~")
            try await builder(Self.escapableProtocolTypeNode)
        } else if hasCopyable {
            Standard("~")
            try await builder(Self.copyableProtocolTypeNode)
        } else if hasEscapable {
            Standard("~")
            try await builder(Self.escapableProtocolTypeNode)
        }
    }

    /// Dump the inverted protocol names, each protocol spelled by `resolver`.
    package func dumpInvertedProtocolNames(resolver: DemangleResolver) async throws -> SemanticString {
        try await dumpInvertedProtocolNames { try await resolver.resolve(for: $0) }
    }

    /// Dump the inverted protocols as an inheritance clause with colon prefix (e.g., `: ~Swift.Copyable`).
    @SemanticStringBuilder
    package func dumpInvertedProtocolsInheritance(resolver: DemangleResolver) async throws -> SemanticString {
        if hasInvertedProtocols {
            Standard(":")
            Space()
            try await dumpInvertedProtocolNames(resolver: resolver)
        }
    }
}
