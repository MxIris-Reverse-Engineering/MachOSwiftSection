import Foundation
import MachOKit
import MachOSwiftSection
import MachOMacro
import Semantic

extension Enum: NamedDumpable {
    
    @MachOImageGenerator
    public func dumpName(using options: DemangleOptions, in machOFile: MachOFile) throws -> SemanticString {
        try MetadataReader.demangleContext(for: .type(.enum(descriptor)), in: machOFile).printSemantic(using: options)
    }
    
    @MachOImageGenerator
    @SemanticStringBuilder
    public func dump(using options: DemangleOptions, in machOFile: MachOFile) throws -> SemanticString {
        Keyword(.enum)
        
        Space()
        
        try dumpName(using: options, in: machOFile).replacing(from: .typeName, to: .typeDeclaration)

        if let genericContext {
            try genericContext.dumpGenericParameters(in: machOFile)
            if genericContext.requirements.count > 0 {
                Space()
                Keyword(.where)
                Space()
                try genericContext.dumpGenericRequirements(using: options, in: machOFile)
            }
        }
        Space()
        Standard("{")
        for (offset, fieldRecord) in try descriptor.fieldDescriptor(in: machOFile).records(in: machOFile).offsetEnumerated() {
            BreakLine()

            Indent(level: 1)

            if fieldRecord.flags.contains(.isIndirectCase) {
                Keyword(.indirect)
                Space()
                Keyword(.case)
                Space()
            } else {
                Keyword(.case)
                Space()
            }

            try MemberDeclaration("\(fieldRecord.fieldName(in: machOFile))")

            let mangledName = try fieldRecord.mangledTypeName(in: machOFile)

            if !mangledName.isEmpty {
                let demangledName = try MetadataReader.demangleType(for: mangledName, in: machOFile).printSemantic(using: options)
                let demangledNameString = demangledName.string
                if demangledNameString.hasPrefix("("), demangledNameString.hasSuffix(")") {
                    demangledName
                } else {
                    Standard("(")
                    demangledName
                    Standard(")")
                }
            }

            if offset.isEnd {
                BreakLine()
            }
        }

        Standard("}")
    }
}
