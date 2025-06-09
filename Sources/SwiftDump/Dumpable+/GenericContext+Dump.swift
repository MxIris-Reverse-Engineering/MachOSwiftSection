import Foundation
import MachOKit
import MachOSwiftSection
import MachOMacro

extension TargetGenericContext {
    @MachOImageGenerator
    @StringBuilder
    package func dumpGenericParameters(in machOFile: MachOFile) throws -> String {
        "<"
        for (offset, _) in parameters.offsetEnumerated() {
            try genericParameterName(depth: 0, index: offset.index)
            if !offset.isEnd {
                ", "
            }
        }
        ">"
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
    @StringBuilder
    package func dumpGenericRequirements(using options: DemangleOptions, in machOFile: MachOFile) throws -> String {
        for (offset, requirement) in requirements.offsetEnumerated() {
            try requirement.dump(using: options, in: machOFile)
            if !offset.isEnd {
                ", "
            }
        }
    }
}

extension GenericRequirementDescriptor {
    @MachOImageGenerator
    @StringBuilder
    package func dump(using options: DemangleOptions, in machOFile: MachOFile) throws -> String {
        try MetadataReader.demangleType(for: paramManagedName(in: machOFile), in: machOFile).print(using: options)
        if layout.flags.kind == .sameType {
            " == "
        } else {
            ": "
        }
        switch try resolvedContent(in: machOFile) {
        case .type(let mangledName):
            try MetadataReader.demangleType(for: mangledName, in: machOFile).print(using: options)
        case .protocol(let resolvableElement):
            switch resolvableElement {
            case .symbol(let unsolvedSymbol):
                try MetadataReader.demangleType(for: unsolvedSymbol, in: machOFile).print(using: options)
            case .element(let element):
                switch element {
                case .objc(let objc):
                    try objc.mangledName(in: machOFile).rawStringValue()
                case .swift(let protocolDescriptor):
                    try MetadataReader.demangleContext(for: .protocol(protocolDescriptor), in: machOFile).print(using: options)
                }
            }
        case .layout(let genericRequirementLayoutKind):
            switch genericRequirementLayoutKind {
            case .class:
                "AnyObject"
            }
        case .conformance /* (let protocolConformanceDescriptor) */:
            ""
        case .invertedProtocols(let invertedProtocols):
            if invertedProtocols.protocols.hasCopyable, invertedProtocols.protocols.hasEscapable {
                "Copyable, Escapable"
            } else if invertedProtocols.protocols.hasCopyable || invertedProtocols.protocols.hasEscapable {
                if invertedProtocols.protocols.hasCopyable {
                    "Copyable"
                } else {
                    "~Copyable"
                }
                if invertedProtocols.protocols.hasEscapable {
                    "Escapable"
                } else {
                    "~Escapable"
                }
            } else {
                "~Copyable, ~Escapable"
            }
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
