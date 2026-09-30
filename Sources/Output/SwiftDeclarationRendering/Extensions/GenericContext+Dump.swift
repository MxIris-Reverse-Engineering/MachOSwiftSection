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
    @SemanticStringBuilder
    package func dumpGenericSignature(resolver: DemangleResolver, in context: some ReadingContext, isDumpCurrentLevelParams: Bool = true, isDumpCurrentLevelRequirements: Bool = true, @SemanticStringBuilder conformancesBuilder: () async throws -> SemanticString = { "" }) async throws -> SemanticString {
        if (isDumpCurrentLevelParams ? currentParameters : parameters).count > 0 {
            Standard("<")
            try await dumpGenericParameters(in: context, isDumpCurrentLevel: isDumpCurrentLevelParams)
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
    @SemanticStringBuilder
    package func dumpGenericParameters(in context: some ReadingContext, isDumpCurrentLevel: Bool = true) async throws -> SemanticString {
        if isDumpCurrentLevel {
            var currentValueIndex = 0
            for (offset, parameter) in currentParameters.offsetEnumerated() {
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
                    try Standard(genericParameterName(depth: depth, index: offset.index))
                case .value:
                    try Standard(genericValueName(depth: depth, index: offset.index))
                    Standard(": ")
                    switch currentValues[currentValueIndex].type {
                    case .int:
                        TypeName(kind: .other, "Int")
                    }
                    currentValueIndex += 1
                default:
                    Standard("")
                }

                if !offset.isEnd {
                    Standard(", ")
                }
            }
        } else {
            // `parameters` is cumulative — every nested generic context stores
            // the full canonical parameter list. Naively iterating
            // `allParameters` would re-emit each inherited level, producing
            // duplicates at depth ≥ 2 (e.g. `<A, A1, B1, A2>` with `A`
            // duplicated). Walk per-level "newly introduced" slices instead,
            // mirroring the depth-aware visit order Swift's
            // `forEachParam` produces.
            let perLevelCounts = Self.dumpPerLevelNewParameterCounts(
                parentParameters: parentParameters,
                currentCount: currentParameters.count
            )
            let perLevelValueCounts = Self.dumpPerLevelNewValueCounts(
                parentValues: parentValues,
                currentCount: currentValues.count
            )
            var paramOffset = 0
            var valueOffset = 0
            var totalEmitted = 0
            let totalParameters = parameters.count
            for (depthIndex, newCount) in perLevelCounts.enumerated() {
                let valuesAtThisLevel = perLevelValueCounts[safe: depthIndex] ?? 0
                var currentValueIndexInLevel = 0
                for indexInLevel in 0..<newCount {
                    let parameter = parameters[paramOffset + indexInLevel]

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
                        try Standard(genericParameterName(depth: depthIndex, index: indexInLevel))
                    case .value:
                        try Standard(genericValueName(depth: depthIndex, index: indexInLevel))
                        Standard(": ")
                        if valueOffset + currentValueIndexInLevel < values.count {
                            switch values[valueOffset + currentValueIndexInLevel].type {
                            case .int:
                                TypeName(kind: .other, "Int")
                            }
                        }
                        currentValueIndexInLevel += 1
                    default:
                        Standard("")
                    }

                    totalEmitted += 1
                    if totalEmitted < totalParameters {
                        Standard(", ")
                    }
                }
                paramOffset += newCount
                valueOffset += valuesAtThisLevel
            }
        }
    }

    /// Per-level "newly introduced" parameter counts derived from the
    /// cumulative `parentParameters` slices plus the current level's new
    /// count. Mirrors `GenericSpecializer.perLevelNewParameterCounts`.
    fileprivate static func dumpPerLevelNewParameterCounts(
        parentParameters: [[GenericParamDescriptor]],
        currentCount: Int
    ) -> [Int] {
        var counts: [Int] = []
        var previous = 0
        for parentCumulative in parentParameters {
            counts.append(parentCumulative.count - previous)
            previous = parentCumulative.count
        }
        counts.append(currentCount)
        return counts
    }

    /// Same idea for value generics.
    fileprivate static func dumpPerLevelNewValueCounts(
        parentValues: [[GenericValueDescriptor]],
        currentCount: Int
    ) -> [Int] {
        var counts: [Int] = []
        var previous = 0
        for parentCumulative in parentValues {
            counts.append(parentCumulative.count - previous)
            previous = parentCumulative.count
        }
        counts.append(currentCount)
        return counts
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
            invertedProtocols.protocols.dumpInvertedProtocolNames
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
            invertedProtocols.protocols.dumpInvertedProtocolNames
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

    /// Dump the inverted protocol names (e.g., `~Swift.Copyable`, `~Swift.Escapable`).
    @SemanticStringBuilder
    package var dumpInvertedProtocolNames: SemanticString {
        if hasCopyable && hasEscapable {
            Standard("~")
            TypeName(kind: .other, "Swift.Copyable")
            Standard(" & ~")
            TypeName(kind: .other, "Swift.Escapable")
        } else if hasCopyable {
            Standard("~")
            TypeName(kind: .other, "Swift.Copyable")
        } else if hasEscapable {
            Standard("~")
            TypeName(kind: .other, "Swift.Escapable")
        }
    }

    /// Dump the inverted protocols as an inheritance clause with colon prefix (e.g., `: ~Swift.Copyable`).
    @SemanticStringBuilder
    package var dumpInvertedProtocolsInheritance: SemanticString {
        if hasInvertedProtocols {
            Standard(":")
            Space()
            dumpInvertedProtocolNames
        }
    }
}
