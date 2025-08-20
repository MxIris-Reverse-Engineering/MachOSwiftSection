import Semantic
import MachOKit
import MachOSwiftSection
import Utilities

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
        for (offset, requirement) in currentRequirements.offsetEnumerated() {
            try requirement.dump(using: options, in: machO)
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
    package func dumpProtocolParameterName<MachO: MachOSwiftSectionRepresentableWithCache>(using options: DemangleOptions, in machO: MachO) throws -> SemanticString {
        let node = try MetadataReader.demangleType(for: paramMangledName(in: machO), in: machO)
        
        for (offset, param) in node.preorder().filter(of: .dependentAssociatedTypeRef).compactMap({ $0.first(of: .identifier)?.contents.name }).offsetEnumerated() {
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
        let node = try MetadataReader.demangleType(for: paramMangledName(in: machO), in: machO)
        node.printSemantic(using: options)
    }

    @SemanticStringBuilder
    package func dumpContent<MachO: MachOSwiftSectionRepresentableWithCache>(using options: DemangleOptions, in machO: MachO) throws -> SemanticString {
        switch try resolvedContent(in: machO) {
        case .type(let mangledName):
            try MetadataReader.demangleType(for: mangledName, in: machO).printSemantic(using: options)
        case .protocol(let resolvableElement):
            switch resolvableElement {
            case .symbol(let unsolvedSymbol):
                try MetadataReader.demangleType(for: unsolvedSymbol, in: machO)?.printSemantic(using: options)
            case .element(let element):
                switch element {
                case .objc(let objc):
                    try TypeName(kind: .protocol, objc.mangledName(in: machO).rawStringValue())
                case .swift(let protocolDescriptor):
                    try MetadataReader.demangleContext(for: .protocol(protocolDescriptor), in: machO).printSemantic(using: options)
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
//            if invertedProtocols.protocols.hasCopyable, invertedProtocols.protocols.hasEscapable {
//
//                "Copyable, Escapable"
//            } else if invertedProtocols.protocols.hasCopyable || invertedProtocols.protocols.hasEscapable {
//                if invertedProtocols.protocols.hasCopyable {
//                    "Copyable"
//                } else {
//                    "~Copyable"
//                }
//                if invertedProtocols.protocols.hasEscapable {
//                    "Escapable"
//                } else {
//                    "~Escapable"
//                }
//            } else {
//                "~Copyable, ~Escapable"
//            }
        }
    }

    @SemanticStringBuilder
    package func dump<MachO: MachOSwiftSectionRepresentableWithCache>(using options: DemangleOptions, in machO: MachO) throws -> SemanticString {
        try dumpParameterName(using: options, in: machO)

        if layout.flags.kind == .sameType {
            Space()
            Standard("==")
            Space()
        } else {
            Standard(":")
            Space()
        }

        try dumpContent(using: options, in: machO)
    }
    
    @SemanticStringBuilder
    package func dumpProtocolRequirement<MachO: MachOSwiftSectionRepresentableWithCache>(using options: DemangleOptions, in machO: MachO) throws -> SemanticString {
        try dumpProtocolParameterName(using: options, in: machO)

        if layout.flags.kind == .sameType {
            Space()
            Standard("==")
            Space()
        } else {
            Standard(":")
            Space()
        }

        try dumpContent(using: options, in: machO)
    }
}

extension OptionSet {
    fileprivate func removing(_ element: Element) -> Self {
        var copy = self
        copy.remove(element)
        return copy
    }
}
