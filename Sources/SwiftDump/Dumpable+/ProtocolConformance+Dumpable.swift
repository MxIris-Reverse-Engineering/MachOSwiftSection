import Foundation
import MachOKit
import MachOSwiftSection
import MachOMacro
import Semantic

extension ProtocolConformance: Dumpable {
    @MachOImageGenerator
    @SemanticStringBuilder
    public func dump(using options: DemangleOptions, in machOFile: MachOFile) throws -> SemanticString {
        Keyword(.extension)
        Space()
        switch typeReference {
        case .directTypeDescriptor(let descriptor):
            try TypeDeclaration(descriptor.flatMap { try $0.dumpName(using: options, in: machOFile) }.valueOrEmpty)
        case .indirectTypeDescriptor(let descriptor):
            switch descriptor {
            case .symbol(let unsolvedSymbol):
                try MetadataReader.demangleType(for: unsolvedSymbol, in: machOFile).printSemantic(using: options)
            case .element(let element):
                try TypeDeclaration(element.dumpName(using: options, in: machOFile))
            case nil:
                Standard("")
            }
        case .directObjCClassName(let objcClassName):
            TypeDeclaration(objcClassName.valueOrEmpty)
        case .indirectObjCClass(let objcClass):
            switch objcClass {
            case .symbol(let unsolvedSymbol):
                try MetadataReader.demangleType(for: unsolvedSymbol, in: machOFile).printSemantic(using: options)
            case .element(let element):
                try MetadataReader.demangleContext(for: .type(.class(element.descriptor.resolve(in: machOFile))), in: machOFile).printSemantic(using: options)
            case nil:
                Standard("")
            }
        }
        Standard(":")
        Space()
        switch `protocol` {
        case .symbol(let unsolvedSymbol):
            try MetadataReader.demangleType(for: unsolvedSymbol, in: machOFile).printSemantic(using: options)
        case .element(let element):
            try MetadataReader.demangleContext(for: .protocol(element), in: machOFile).printSemantic(using: options)
        case .none:
            Standard("")
        }

        if !conditionalRequirements.isEmpty {
            Space()
            Keyword(.where)
            Space()
        }

        for conditionalRequirement in conditionalRequirements {
            try conditionalRequirement.dump(using: options, in: machOFile)
        }

        if resilientWitnesses.isEmpty {
            Space()
            Standard("{}")
        } else {
            Space()
            Standard("{")

            for resilientWitness in resilientWitnesses {
                BreakLine()

                Indent(level: 1)

                if let symbol = try resilientWitness.implementationSymbol(in: machOFile) {
                    try MetadataReader.demangleSymbol(for: symbol, in: machOFile).printSemantic(using: options)
                } else if let implSymbol = try resilientWitness.requirement(in: machOFile)?.mapOptional({ try $0.defaultImplementationSymbol(in: machOFile) }) {
                    switch implSymbol {
                    case .symbol(let symbol):
                        try MetadataReader.demangleSymbol(for: symbol, in: machOFile).printSemantic(using: options)
                    case .element(let symbol):
                        try MetadataReader.demangleSymbol(for: symbol, in: machOFile).printSemantic(using: options)
                    }
                } else {
                    InlineComment("Symbol not found")
                }
            }

            BreakLine()

            Standard("}")
        }
    }
}
