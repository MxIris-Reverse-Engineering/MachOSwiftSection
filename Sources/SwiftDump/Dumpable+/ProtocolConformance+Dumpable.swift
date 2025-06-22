import Foundation
import MachOKit
import MachOSwiftSection
import MachOMacro
import MachOFoundation
import Semantic

extension ProtocolConformance: ConformedDumpable {
    @MachOImageGenerator
    @SemanticStringBuilder
    public func dumpTypeName(using options: DemangleOptions, in machOFile: MachOFile) throws -> SemanticString {
        switch typeReference {
        case .directTypeDescriptor(let descriptor):
            try descriptor?.dumpName(using: options, in: machOFile).replacingTypeNameOrOtherToTypeDeclaration()
        case .indirectTypeDescriptor(let descriptor):
            switch descriptor {
            case .symbol(let unsolvedSymbol):
                try MetadataReader.demangleType(for: unsolvedSymbol, in: machOFile).printSemantic(using: options).replacingTypeNameOrOtherToTypeDeclaration()
            case .element(let element):
                try element.dumpName(using: options, in: machOFile).replacingTypeNameOrOtherToTypeDeclaration()
            case nil:
                Standard("")
            }
        case .directObjCClassName(let objcClassName):
            TypeDeclaration(kind: .class, objcClassName.valueOrEmpty)
        case .indirectObjCClass(let objcClass):
            switch objcClass {
            case .symbol(let unsolvedSymbol):
                try MetadataReader.demangleType(for: unsolvedSymbol, in: machOFile).printSemantic(using: options).replacingTypeNameOrOtherToTypeDeclaration()
            case .element(let element):
                try MetadataReader.demangleContext(for: .type(.class(element.descriptor.resolve(in: machOFile))), in: machOFile).printSemantic(using: options).replacingTypeNameOrOtherToTypeDeclaration()
            case nil:
                Standard("")
            }
        }
    }

    @MachOImageGenerator
    @SemanticStringBuilder
    public func dumpProtocolName(using options: DemangleOptions, in machOFile: MachOFile) throws -> SemanticString {
        switch `protocol` {
        case .symbol(let unsolvedSymbol):
            try MetadataReader.demangleType(for: unsolvedSymbol, in: machOFile).printSemantic(using: options)
        case .element(let element):
            try MetadataReader.demangleContext(for: .protocol(element), in: machOFile).printSemantic(using: options)
        case .none:
            Standard("")
        }
    }

    @MachOImageGenerator
    @SemanticStringBuilder
    public func dump(using options: DemangleOptions, in machOFile: MachOFile) throws -> SemanticString {
        Keyword(.extension)

        Space()

        try dumpTypeName(using: options, in: machOFile)

        Standard(":")

        Space()

        try dumpProtocolName(using: options, in: machOFile)

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
                    try? MetadataReader.demangleSymbol(for: symbol, in: machOFile).printSemantic(using: options)
                } else if !resilientWitness.implementation.isNull {
                    FunctionDeclaration(addressString(of: resilientWitness.implementation.resolveDirectOffset(from: resilientWitness.offset(of: \.implementation)), in: machOFile).insertSubFunctionPrefix)
                } else if let implSymbol = try resilientWitness.requirement(in: machOFile)?.mapOptional({ try $0.defaultImplementationSymbol(in: machOFile) }) {
                    switch implSymbol {
                    case .symbol(let symbol):
                        try MetadataReader.demangleSymbol(for: symbol, in: machOFile).printSemantic(using: options)
                    case .element(let symbol):
                        try MetadataReader.demangleSymbol(for: symbol, in: machOFile).printSemantic(using: options)
                    }
                } else {
                    Error("Symbol not found")
                }
            }

            BreakLine()

            Standard("}")
        }
    }
}

extension SemanticString {
    func replacingTypeNameOrOtherToTypeDeclaration() -> SemanticString {
        replacing { 
            switch $0 {
            case .type(let type, .name):
                return .type(type, .declaration)
            case .other:
                return .type(.other, .declaration)
            default:
                return $0
            }
        }
    }
}
