import Foundation
import MachOKit
import MachOSwiftSection
import MachOMacro
import Semantic

extension MachOSwiftSection.`Protocol`: NamedDumpable {
    
    @MachOImageGenerator
    public func dumpName(using options: DemangleOptions, in machOFile: MachOFile) throws -> SemanticString {
        try MetadataReader.demangleContext(for: .protocol(descriptor), in: machOFile).printSemantic(using: options)
    }
    
    @MachOImageGenerator
    @SemanticStringBuilder
    public func dump(using options: DemangleOptions, in machOFile: MachOFile) throws -> SemanticString {
        Keyword(.protocol)
        Space()
        try dumpName(using: options, in: machOFile) .replacing(from: .typeName, to: .typeDeclaration)

        if numberOfRequirementsInSignature > 0 {
            Space()
            Keyword(.where)
            Space()

            for (offset, requirement) in requirementInSignatures.offsetEnumerated() {
                try requirement.dump(using: options, in: machOFile)
                if !offset.isEnd {
                    Standard(",")
                    Space()
                }
            }
        }
        Space()
        Standard("{")

        let associatedTypes = try descriptor.associatedTypes(in: machOFile)

        if !associatedTypes.isEmpty {
            for (offset, associatedType) in associatedTypes.offsetEnumerated() {
                BreakLine()
                Indent(level: 1)
                Keyword(.associatedtype)
                Space()
                TypeDeclaration(associatedType)
                if offset.isEnd {
                    BreakLine()
                }
            }
        }

        for (offset, requirement) in requirements.offsetEnumerated() {
            BreakLine()
            Indent(level: 1)
            if let symbol = try requirement.defaultImplementationSymbol(in: machOFile) {
                InlineComment("[Default Implementation]")
                try MetadataReader.demangleSymbol(for: symbol, in: machOFile).printSemantic(using: options)
            } else {
                InlineComment("[Stripped Symbol]")
            }
            if offset.isEnd {
                BreakLine()
            }
        }

        Standard("}")
    }
}
