import Foundation
import MachOKit
import MachOSwiftSection
import MachOMacro
import Semantic

extension Struct: Dumpable {
    @MachOImageGenerator
    @SemanticStringBuilder
    public func dump(using options: DemangleOptions, in machOFile: MachOFile) throws -> SemanticString {
        Keyword(.struct)
        Space()
        try MetadataReader.demangleContext(for: .type(.struct(descriptor)), in: machOFile).printSemantic(using: options)

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

            let demangledTypeName = try MetadataReader.demangleType(for: fieldRecord.mangledTypeName(in: machOFile), in: machOFile).printSemantic(using: options)
            let demangledTypeNameString = demangledTypeName.string
            
            let fieldName = try fieldRecord.fieldName(in: machOFile)
            
            if fieldRecord.flags.contains(.isVariadic) {
                if demangledTypeNameString.hasWeakPrefix {
                    Keyword(.weak)
                    Space()
                    Keyword(.var)
                    Space()
                } else if fieldName.hasLazyPrefix {
                    Keyword(.lazy)
                    Space()
                    Keyword(.var)
                    Space()
                } else {
                    Keyword(.var)
                    Space()
                }
            } else {
                Keyword(.let)
                Space()
            }

            MemberDeclaration(fieldName.stripLazyPrefix)
            Standard(":")
            Space()
            TypeName(demangledTypeNameString.stripWeakPrefix)

            if offset.isEnd {
                BreakLine()
            }
        }

        Standard("}")
    }
}
