import Foundation
import MachOKit
import MachOSwiftSection
import MachOMacro

extension ProtocolConformance: Dumpable {
    @MachOImageGenerator
    @StringBuilder
    public func dump(using options: DemangleOptions, in machOFile: MachOFile) throws -> String {
        "extension "
        switch typeReference {
        case .directTypeDescriptor(let descriptor):
            try descriptor.flatMap { try $0.dumpName(using: options, in: machOFile) }.valueOrEmpty
        case .indirectTypeDescriptor(let descriptor):
            switch descriptor {
            case .symbol(let unsolvedSymbol):
                try MetadataReader.demangleType(for: unsolvedSymbol, in: machOFile).print(using: options)
            case .element(let element):
                try element.dumpName(using: options, in: machOFile)
            case nil:
                ""
            }
        case .directObjCClassName(let objcClassName):
            objcClassName.valueOrEmpty
        case .indirectObjCClass(let objcClass):
            switch objcClass {
            case .symbol(let unsolvedSymbol):
                try MetadataReader.demangleType(for: unsolvedSymbol, in: machOFile).print(using: options)
            case .element(let element):
                try MetadataReader.demangleContext(for: .type(.class(element.descriptor.resolve(in: machOFile))), in: machOFile).print(using: options)
            case nil:
                ""
            }
        }
        ": "
        switch `protocol` {
        case .symbol(let unsolvedSymbol):
            try MetadataReader.demangleType(for: unsolvedSymbol, in: machOFile).print(using: options)
        case .element(let element):
            try MetadataReader.demangleContext(for: .protocol(element), in: machOFile).print(using: options)
        case .none:
            ""
        }

        if !conditionalRequirements.isEmpty {
            " where "
        }

        for conditionalRequirement in conditionalRequirements {
            try conditionalRequirement.dump(using: options, in: machOFile)
        }

        if resilientWitnesses.isEmpty {
            " {}"
        } else {
            " {"

            for resilientWitness in resilientWitnesses {
                BreakLine()
                
                Indent(level: 1)
                
                if let symbol = try resilientWitness.implementationSymbol(in: machOFile) {
                    try MetadataReader.demangleSymbol(for: symbol, in: machOFile).print(using: options)
                } else if let implSymbol = try resilientWitness.requirement(in: machOFile)?.mapOptional({ try $0.defaultImplementationSymbol(in: machOFile) }) {
                    switch implSymbol {
                    case .symbol(let symbol):
                        try MetadataReader.demangleSymbol(for: symbol, in: machOFile).print(using: options)
                    case .element(let symbol):
                        try MetadataReader.demangleSymbol(for: symbol, in: machOFile).print(using: options)
                    }
                } else {
                    "Symbol not found"
                }
            }

            BreakLine()
            
            "}"
        }
    }
}
