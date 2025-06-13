import Foundation
import MachOKit
import MachOSwiftSection
import MachOMacro
import Semantic

extension AssociatedType: Dumpable {
    @MachOImageGenerator
    @SemanticStringBuilder
    public func dump(using options: DemangleOptions, in machOFile: MachOFile) throws -> SemanticString {
        Keyword(.extension)
        
        Space()
        
        try MetadataReader.demangleSymbol(for: conformingTypeName, in: machOFile).printSemantic(using: options).replacing(from: .typeName, to: .typeDeclaration)
        
        Standard(":")
        
        Space()
        
        try MetadataReader.demangleSymbol(for: protocolTypeName, in: machOFile).printSemantic(using: options)
        
        Space()
        
        Standard("{")
        
        for (offset, record) in records.offsetEnumerated() {
            BreakLine()

            Indent(level: 1)

            Keyword(.typealias)

            Space()

            try TypeDeclaration(record.name(in: machOFile))

            Space()

            Standard("=")

            Space()
            
            try MetadataReader.demangleSymbol(for: record.substitutedTypeName(in: machOFile), in: machOFile).printSemantic(using: options)

            if offset.isEnd {
                BreakLine()
            }
        }

        Standard("}")
    }
}


