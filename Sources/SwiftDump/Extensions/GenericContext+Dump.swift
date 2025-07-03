import Semantic
import MachOKit
import MachOMacro
import MachOFoundation
import MachOSwiftSection
import Utilities

extension TargetGenericContext {
    @SemanticStringBuilder
    package func dumpGenericParameters<MachO: MachOSwiftSectionRepresentableWithCache & MachOReadable>(in machO: MachO) throws -> SemanticString {
        Standard("<")
        for (offset, _) in currentParameters.offsetEnumerated() {
            Standard(try genericParameterName(depth: depth, index: offset.index))
            if !offset.isEnd {
                Standard(", ")
            }
        }
        Standard(">")
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

    @SemanticStringBuilder
    package func dumpGenericRequirements<MachO: MachOSwiftSectionRepresentableWithCache & MachOReadable>(using options: DemangleOptions, in machO: MachO) throws -> SemanticString {
        for (offset, requirement) in currentRequirements.offsetEnumerated() {
            try requirement.dump(using: options, in: machO)
            if !offset.isEnd {
                Standard(",")
                Space()
            }
        }
    }
}

extension GenericRequirementDescriptor {
    
    package func dumpInheritedProtocol<MachO: MachOSwiftSectionRepresentableWithCache & MachOReadable>(using options: DemangleOptions, in machO: MachO) throws -> SemanticString? {
        if try paramManagedName(in: machO).rawStringValue() == "A" {
            return try dumpParameterName(using: options, in: machO)
        } else {
            return nil
        }
    }
    
    
    @SemanticStringBuilder
    package func dumpParameterName<MachO: MachOSwiftSectionRepresentableWithCache & MachOReadable>(using options: DemangleOptions, in machO: MachO) throws -> SemanticString {
        let node = try MetadataReader.demangleType(for: paramManagedName(in: machO), in: machO)
        node.printSemantic(using: options)
    }
    
    @SemanticStringBuilder
    package func dumpContent<MachO: MachOSwiftSectionRepresentableWithCache & MachOReadable>(using options: DemangleOptions, in machO: MachO) throws -> SemanticString {
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
                    TypeName(kind: .protocol, try objc.mangledName(in: machO).rawStringValue())
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
        case .invertedProtocols/* (let invertedProtocols) */:
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
    package func dump<MachO: MachOSwiftSectionRepresentableWithCache & MachOReadable>(using options: DemangleOptions, in machO: MachO) throws -> SemanticString {
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
}

extension OptionSet {
    fileprivate func removing(_ element: Element) -> Self {
        var copy = self
        copy.remove(element)
        return copy
    }
}
