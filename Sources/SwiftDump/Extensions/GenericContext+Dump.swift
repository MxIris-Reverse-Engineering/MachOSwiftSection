import Semantic
import MachOKit
import MachOSwiftSection
import Utilities
import Demangle

extension TargetGenericContext {
    @SemanticStringBuilder
    package func dumpGenericParameters<MachO: MachOSwiftSectionRepresentableWithCache>(in machO: MachO) throws -> SemanticString {
        Standard("<")
        for (offset, _) in currentParameters.offsetEnumerated() {
            try Standard(genericParameterName(depth: depth, index: offset.index))
            if !offset.isEnd {
                Standard(", ")
            }
        }
        Standard(">")
    }

    @SemanticStringBuilder
    package func dumpGenericRequirements<MachO: MachOSwiftSectionRepresentableWithCache>(using options: DemangleOptions, in machO: MachO) throws -> SemanticString {
        try dumpGenericRequirements(in: machO) { $0.printSemantic(using: options) }
    }
    
    @SemanticStringBuilder
    package func dumpGenericRequirements<MachO: MachOSwiftSectionRepresentableWithCache>(in machO: MachO, @SemanticStringBuilder builder: (Node) throws -> SemanticString) throws -> SemanticString {
        for (offset, requirement) in currentRequirements.offsetEnumerated() {
            try requirement.dump(in: machO, builder: builder)
            if !offset.isEnd {
                Standard(",")
                Space()
            }
        }
    }

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
}

extension GenericRequirementDescriptor {

    @SemanticStringBuilder
    package func dumpProtocolParameterName<MachO: MachOSwiftSectionRepresentableWithCache>(in machO: MachO) throws -> SemanticString {
        let node = try MetadataReader.demangleType(for: paramMangledName(in: machO), in: machO)
        
        for (offset, param) in node.filter(of: .dependentAssociatedTypeRef).compactMap({ $0.first(of: .identifier)?.contents.name }).offsetEnumerated() {
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
    
    @SemanticStringBuilder
    package func dumpParameterName<MachO: MachOSwiftSectionRepresentableWithCache>(using options: DemangleOptions, in machO: MachO) throws -> SemanticString {
        try dumpParameterName(in: machO) { $0.printSemantic(using: options) }
    }
    
    @SemanticStringBuilder
    package func dumpParameterName<MachO: MachOSwiftSectionRepresentableWithCache>(in machO: MachO, @SemanticStringBuilder builder: (Node) throws -> SemanticString) throws -> SemanticString {
        let node = try MetadataReader.demangleType(for: paramMangledName(in: machO), in: machO)
        try builder(node)
    }

    @SemanticStringBuilder
    package func dumpContent<MachO: MachOSwiftSectionRepresentableWithCache>(using options: DemangleOptions, in machO: MachO) throws -> SemanticString {
        try dumpContent(in: machO) { $0.printSemantic(using: options) }
    }
    
    @SemanticStringBuilder
    package func dumpContent<MachO: MachOSwiftSectionRepresentableWithCache>(in machO: MachO, @SemanticStringBuilder builder: (Node) throws -> SemanticString) throws -> SemanticString {
        switch try resolvedContent(in: machO) {
        case .type(let mangledName):
            try builder(MetadataReader.demangleType(for: mangledName, in: machO))
        case .protocol(let resolvableElement):
            switch resolvableElement {
            case .symbol(let unsolvedSymbol):
                try MetadataReader.demangleType(for: unsolvedSymbol, in: machO).map { try builder($0) }
            case .element(let element):
                switch element {
                case .objc(let objc):
                    let objcName = try objc.mangledName(in: machO).rawString
                    let node = Node(kind: .global) {
                        Node(kind: .type) {
                            Node(kind: .protocol) {
                                Node(kind: .module, contents: .name(objcModule))
                                Node(kind: .identifier, contents: .name(objcName))
                            }
                        }
                    }
                    try builder(node)
                case .swift(let protocolDescriptor):
                    try builder(try MetadataReader.demangleContext(for: .protocol(protocolDescriptor), in: machO))
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

    @SemanticStringBuilder
    package func dump<MachO: MachOSwiftSectionRepresentableWithCache>(using options: DemangleOptions, in machO: MachO) throws -> SemanticString {
        try dump(in: machO) { $0.printSemantic(using: options) }
    }
    
    @SemanticStringBuilder
    package func dump<MachO: MachOSwiftSectionRepresentableWithCache>(in machO: MachO, @SemanticStringBuilder builder: (Node) throws -> SemanticString) throws -> SemanticString {
        try dumpParameterName(in: machO, builder: builder)

        if layout.flags.kind == .sameType {
            Space()
            Standard("==")
            Space()
        } else {
            Standard(":")
            Space()
        }

        try dumpContent(in: machO, builder: builder)
    }
    
    
    @SemanticStringBuilder
    package func dumpProtocolRequirement<MachO: MachOSwiftSectionRepresentableWithCache>(using options: DemangleOptions, in machO: MachO) throws -> SemanticString {
        try dumpProtocolRequirement(in: machO) { $0.printSemantic(using: options) }
    }
    
    @SemanticStringBuilder
    package func dumpProtocolRequirement<MachO: MachOSwiftSectionRepresentableWithCache>(in machO: MachO, @SemanticStringBuilder builder: (Node) throws -> SemanticString) throws -> SemanticString {
        try dumpProtocolParameterName(in: machO)

        if layout.flags.kind == .sameType {
            Space()
            Standard("==")
            Space()
        } else {
            Standard(":")
            Space()
        }

        try dumpContent(in: machO, builder: builder)
    }
}

extension OptionSet {
    fileprivate func removing(_ element: Element) -> Self {
        var copy = self
        copy.remove(element)
        return copy
    }
}
