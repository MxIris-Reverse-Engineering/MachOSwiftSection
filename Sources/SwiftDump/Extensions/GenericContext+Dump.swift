import Semantic
import MachOKit
import MachOMacro
import MachOFoundation
import MachOSwiftSection

extension TargetGenericContext {
    @MachOImageGenerator
    @SemanticStringBuilder
    package func dumpGenericParameters(in machOFile: MachOFile) throws -> SemanticString {
        Standard("<")
        for (offset, _) in parameters.offsetEnumerated() {
            Standard(try genericParameterName(depth: 0, index: offset.index))
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
        for (offset, requirement) in requirements.offsetEnumerated() {
            try requirement.dump(using: options, in: machOFile)
            if !offset.isEnd {
                Standard(",")
                Space()
            }
        }
    }
}

extension GenericRequirementDescriptor {
    @MachOImageGenerator
    @SemanticStringBuilder
    package func dump(using options: DemangleOptions, in machOFile: MachOFile) throws -> SemanticString {
        try MetadataReader.demangleType(for: paramManagedName(in: machOFile), in: machOFile).printSemantic(using: options)
        if layout.flags.kind == .sameType {
            Space()
            Standard("==")
            Space()
        } else {
            Standard(":")
            Space()
        }
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
                    TypeName(try objc.mangledName(in: machOFile).rawStringValue())
                case .swift(let protocolDescriptor):
                    try MetadataReader.demangleContext(for: .protocol(protocolDescriptor), in: machOFile).printSemantic(using: options)
                }
            }
        case .layout(let genericRequirementLayoutKind):
            switch genericRequirementLayoutKind {
            case .class:
                TypeName("AnyObject")
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
}

extension OptionSet {
    fileprivate func removing(_ element: Element) -> Self {
        var copy = self
        copy.remove(element)
        return copy
    }
}
