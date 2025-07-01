import Semantic
import MachOKit
import MachOMacro
import MachOFoundation
import MachOSwiftSection
import Utilities

extension TargetGenericContext {
    @MachOImageGenerator
    @SemanticStringBuilder
    package func dumpGenericParameters(in machOFile: MachOFile) throws -> SemanticString {
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

    @MachOImageGenerator
    @SemanticStringBuilder
    package func dumpGenericRequirements(using options: DemangleOptions, in machOFile: MachOFile) throws -> SemanticString {
        for (offset, requirement) in currentRequirements.offsetEnumerated() {
            try requirement.dump(using: options, in: machOFile)
            if !offset.isEnd {
                Standard(",")
                Space()
            }
        }
    }
}

@MachOImageAllMembersGenerator
extension GenericRequirementDescriptor {
    
    package func dumpInheritedProtocol(using options: DemangleOptions, in machOFile: MachOFile) throws -> SemanticString? {
        if try paramManagedName(in: machOFile).rawStringValue() == "A" {
            return try dumpParameterName(using: options, in: machOFile)
        } else {
            return nil
        }
    }
    
    
    @SemanticStringBuilder
    package func dumpParameterName(using options: DemangleOptions, in machOFile: MachOFile) throws -> SemanticString {
        let node = try MetadataReader.demangleType(for: paramManagedName(in: machOFile), in: machOFile)
        node.printSemantic(using: options)
    }
    
    @SemanticStringBuilder
    package func dumpContent(using options: DemangleOptions, in machOFile: MachOFile) throws -> SemanticString {
        switch try resolvedContent(in: machOFile) {
        case .type(let mangledName):
            try MetadataReader.demangleType(for: mangledName, in: machOFile).printSemantic(using: options)
        case .protocol(let resolvableElement):
            switch resolvableElement {
            case .symbol(let unsolvedSymbol):
                try MetadataReader.demangleType(for: unsolvedSymbol, in: machOFile).printSemantic(using: options)
            case .element(let element):
                switch element {
                case .objc(let objc):
                    TypeName(kind: .protocol, try objc.mangledName(in: machOFile).rawStringValue())
                case .swift(let protocolDescriptor):
                    try MetadataReader.demangleContext(for: .protocol(protocolDescriptor), in: machOFile).printSemantic(using: options)
                }
            }
        case .layout(let genericRequirementLayoutKind):
            switch genericRequirementLayoutKind {
            case .class:
                TypeName(kind: .other, "AnyObject")
            }
        case .conformance /* (let protocolConformanceDescriptor) */:
            Standard("")
        case .invertedProtocols/* (let invertedProtocols) */:
            Standard("")
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
    package func dump(using options: DemangleOptions, in machOFile: MachOFile) throws -> SemanticString {
        try dumpParameterName(using: options, in: machOFile)
        
        if layout.flags.kind == .sameType {
            Space()
            Standard("==")
            Space()
        } else {
            Standard(":")
            Space()
        }
        
        try dumpContent(using: options, in: machOFile)
    }
}

extension OptionSet {
    fileprivate func removing(_ element: Element) -> Self {
        var copy = self
        copy.remove(element)
        return copy
    }
}
