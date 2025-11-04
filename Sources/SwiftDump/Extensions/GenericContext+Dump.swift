import Semantic
import MachOKit
import MachOSwiftSection
import Utilities
import Demangling

private func genericParameterName(depth: Int, index: Int) throws -> String {
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

private func genericValueName(depth: Int, index: Int) throws -> String {
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
    package func dumpGenericSignature<MachO: MachOSwiftSectionRepresentableWithCache>(resolver: DemangleResolver, in machO: MachO, @SemanticStringBuilder conformancesBuilder: () async throws -> SemanticString = { "" }) async throws -> SemanticString {
        if currentParameters.count > 0 {
            Standard("<")
            try await dumpGenericParameters(in: machO)
            Standard(">")
        }

        try await conformancesBuilder()

        if currentRequirements(in: machO).count > 0 {
            Space()
            Keyword(.where)
            Space()
            try await dumpGenericRequirements(resolver: resolver, in: machO)
        }
    }
}

extension TargetGenericContext {
    @SemanticStringBuilder
    package func dumpGenericParameters<MachO: MachOSwiftSectionRepresentableWithCache>(in machO: MachO) async throws -> SemanticString {
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
    }

    @SemanticStringBuilder
    package func dumpGenericRequirements<MachO: MachOSwiftSectionRepresentableWithCache>(resolver: DemangleResolver, in machO: MachO) async throws -> SemanticString {
        switch resolver {
        case .options(let demangleOptions):
            try await dumpGenericRequirements(using: demangleOptions, in: machO)
        case .builder(let builder):
            try await dumpGenericRequirements(in: machO, builder: builder)
        }
    }

    @SemanticStringBuilder
    package func dumpGenericRequirements<MachO: MachOSwiftSectionRepresentableWithCache>(using options: DemangleOptions, in machO: MachO) async throws -> SemanticString {
        try await dumpGenericRequirements(in: machO) { $0.printSemantic(using: options) }
    }

    @SemanticStringBuilder
    package func dumpGenericRequirements<MachO: MachOSwiftSectionRepresentableWithCache>(in machO: MachO, @SemanticStringBuilder builder: (Node) async throws -> SemanticString) async throws -> SemanticString {
        for (offset, requirement) in currentRequirements(in: machO).offsetEnumerated() {
            try await requirement.dump(in: machO, builder: builder)
            if !offset.isEnd {
                Standard(",")
                Space()
            }
        }
    }
}

extension Node {
    fileprivate static let firstGenericParamType = Node(kind: .type) {
        Node(kind: .dependentGenericParamType, text: "A") {
            Node(kind: .index, index: 0)
            Node(kind: .index, index: 0)
        }
    }
}

extension GenericRequirementDescriptor {
    @SemanticStringBuilder
    package func dump<MachO: MachOSwiftSectionRepresentableWithCache>(resolver: DemangleResolver, in machO: MachO) async throws -> SemanticString {
        switch resolver {
        case .options(let demangleOptions):
            try await dump(using: demangleOptions, in: machO)
        case .builder(let builder):
            try await dump(in: machO, builder: builder)
        }
    }

    @SemanticStringBuilder
    package func dump<MachO: MachOSwiftSectionRepresentableWithCache>(using options: DemangleOptions, in machO: MachO) async throws -> SemanticString {
        try await dump(in: machO) { $0.printSemantic(using: options) }
    }

    @SemanticStringBuilder
    package func dump<MachO: MachOSwiftSectionRepresentableWithCache>(in machO: MachO, @SemanticStringBuilder builder: (Node) async throws -> SemanticString) async throws -> SemanticString {
        try await dumpParameterName(in: machO, builder: builder)

        if layout.flags.kind == .sameType {
            Space()
            Standard("==")
            Space()
        } else {
            Standard(":")
            Space()
        }

        try await dumpContent(in: machO, builder: builder)
    }

    @SemanticStringBuilder
    package func dumpParameterName<MachO: MachOSwiftSectionRepresentableWithCache>(using options: DemangleOptions, in machO: MachO) async throws -> SemanticString {
        try await dumpParameterName(in: machO) { $0.printSemantic(using: options) }
    }

    @SemanticStringBuilder
    package func dumpParameterName<MachO: MachOSwiftSectionRepresentableWithCache>(resolver: DemangleResolver, in machO: MachO) async throws -> SemanticString {
        switch resolver {
        case .options(let demangleOptions):
            try await dumpParameterName(using: demangleOptions, in: machO)
        case .builder(let builder):
            try await dumpParameterName(in: machO, builder: builder)
        }
    }

    @SemanticStringBuilder
    package func dumpParameterName<MachO: MachOSwiftSectionRepresentableWithCache>(in machO: MachO, @SemanticStringBuilder builder: (Node) async throws -> SemanticString) async throws -> SemanticString {
        if layout.flags.contains(.isPackRequirement) {
            Keyword(.repeat)
            Space()
            Keyword(.each)
            Space()
        }

        try await builder(dumpParameterName(in: machO))
    }
    
    package func dumpParameterName<MachO: MachOSwiftSectionRepresentableWithCache>(in machO: MachO) async throws -> Node {
        try MetadataReader.demangleType(for: paramMangledName(in: machO), in: machO)
    }

    @SemanticStringBuilder
    package func dumpContent<MachO: MachOSwiftSectionRepresentableWithCache>(resolver: DemangleResolver, in machO: MachO) async throws -> SemanticString {
        switch resolver {
        case .options(let demangleOptions):
            try await dumpContent(using: demangleOptions, in: machO)
        case .builder(let builder):
            try await dumpContent(in: machO, builder: builder)
        }
    }

    @SemanticStringBuilder
    package func dumpContent<MachO: MachOSwiftSectionRepresentableWithCache>(using options: DemangleOptions, in machO: MachO) async throws -> SemanticString {
        try await dumpContent(in: machO) { $0.printSemantic(using: options) }
    }

    @SemanticStringBuilder
    package func dumpContent<MachO: MachOSwiftSectionRepresentableWithCache>(in machO: MachO, @SemanticStringBuilder builder: (Node) async throws -> SemanticString) async throws -> SemanticString {
        switch try resolvedContent(in: machO) {
        case .type(let mangledName):
            try await builder(MetadataReader.demangleType(for: mangledName, in: machO))
        case .protocol(let resolvableElement):
            switch resolvableElement {
            case .symbol(let unsolvedSymbol):
                try await MetadataReader.demangleType(for: unsolvedSymbol, in: machO).asyncMap { try await builder($0) }
            case .element(let element):
                switch element {
                case .objc(let objc):
                    let objcName = try objc.mangledName(in: machO).rawString
                    let node = Node(kind: .global) {
                        Node(kind: .type) {
                            Node(kind: .protocol) {
                                Node(kind: .module, contents: .text(objcModule))
                                Node(kind: .identifier, contents: .text(objcName))
                            }
                        }
                    }
                    try await builder(node)
                case .swift(let protocolDescriptor):
                    try await builder(MetadataReader.demangleContext(for: .protocol(protocolDescriptor), in: machO))
                }
            }
        case .layout(let genericRequirementLayoutKind):
            switch genericRequirementLayoutKind {
            case .class:
                TypeName(kind: .other, "AnyObject")
            }
        case .conformance /* (let protocolConformanceDescriptor) */:
            Standard("SwiftDumpConformance")
        case .invertedProtocols /* (let invertedProtocols) */:
            Standard("SwiftDumpInvertedProtocols")
        }
    }
    
    
}

extension GenericRequirementDescriptor {
    @SemanticStringBuilder
    package func dumpProtocolRequirement<MachO: MachOSwiftSectionRepresentableWithCache>(resolver: DemangleResolver, in machO: MachO) async throws -> SemanticString {
        switch resolver {
        case .options(let demangleOptions):
            try await dumpProtocolRequirement(using: demangleOptions, in: machO)
        case .builder(let builder):
            try await dumpProtocolRequirement(in: machO, builder: builder)
        }
    }

    @SemanticStringBuilder
    package func dumpProtocolRequirement<MachO: MachOSwiftSectionRepresentableWithCache>(using options: DemangleOptions, in machO: MachO) async throws -> SemanticString {
        try await dumpProtocolRequirement(in: machO) { $0.printSemantic(using: options) }
    }

    @SemanticStringBuilder
    package func dumpProtocolRequirement<MachO: MachOSwiftSectionRepresentableWithCache>(in machO: MachO, @SemanticStringBuilder builder: (Node) async throws -> SemanticString) async throws -> SemanticString {
        try await dumpProtocolParameterName(in: machO, builder: builder)

        if layout.flags.kind == .sameType {
            Space()
            Standard("==")
            Space()
        } else {
            Standard(":")
            Space()
        }

        try await dumpProtocolContent(in: machO, builder: builder)
    }

    @SemanticStringBuilder
    package func dumpProtocolParameterName<MachO: MachOSwiftSectionRepresentableWithCache>(in machO: MachO, @SemanticStringBuilder builder: (Node) async throws -> SemanticString) async throws -> SemanticString {
        try await dumpProtocolMangledName(paramMangledName(in: machO), in: machO, builder: builder)
    }
    
    @SemanticStringBuilder
    private func dumpProtocolMangledName<MachO: MachOSwiftSectionRepresentableWithCache>(_ mangledName: MangledName, in machO: MachO, @SemanticStringBuilder builder: (Node) async throws -> SemanticString) async throws -> SemanticString {
        let node = try MetadataReader.demangleType(for: mangledName, in: machO)

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
    package func dumpProtocolContent<MachO: MachOSwiftSectionRepresentableWithCache>(in machO: MachO, @SemanticStringBuilder builder: (Node) async throws -> SemanticString) async throws -> SemanticString {
        switch try resolvedContent(in: machO) {
        case .type(let mangledName):
//            try builder(MetadataReader.demangleType(for: mangledName, in: machO))
            try await dumpProtocolMangledName(mangledName, in: machO, builder: builder)
        case .protocol(let resolvableElement):
            switch resolvableElement {
            case .symbol(let unsolvedSymbol):
                try await MetadataReader.demangleType(for: unsolvedSymbol, in: machO).asyncMap { try await builder($0) }
            case .element(let element):
                switch element {
                case .objc(let objc):
                    let objcName = try objc.mangledName(in: machO).rawString
                    let node = Node(kind: .global) {
                        Node(kind: .type) {
                            Node(kind: .protocol) {
                                Node(kind: .module, contents: .text(objcModule))
                                Node(kind: .identifier, contents: .text(objcName))
                            }
                        }
                    }
                    try await builder(node)
                case .swift(let protocolDescriptor):
                    try await builder(MetadataReader.demangleContext(for: .protocol(protocolDescriptor), in: machO))
                }
            }
        case .layout(let genericRequirementLayoutKind):
            switch genericRequirementLayoutKind {
            case .class:
                TypeName(kind: .other, "AnyObject")
            }
        case .conformance /* (let protocolConformanceDescriptor) */:
            Standard("SwiftDumpConformance")
        case .invertedProtocols /* (let invertedProtocols) */:
            Standard("SwiftDumpInvertedProtocols")
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
