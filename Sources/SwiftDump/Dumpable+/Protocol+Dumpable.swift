import Foundation
import MachOKit
import MachOSwiftSection
import MachOMacro
import Semantic
import MachOFoundation

extension MachOSwiftSection.`Protocol`: NamedDumpable {
    @MachOImageGenerator
    public func dumpName(using options: DemangleOptions, in machOFile: MachOFile) throws -> SemanticString {
        try MetadataReader.demangleContext(for: .protocol(descriptor), in: machOFile).printSemantic(using: options).replacingTypeNameOrOtherToTypeDeclaration()
    }

    @MachOImageGenerator
    @SemanticStringBuilder
    public func dump(using options: DemangleOptions, in machOFile: MachOFile) throws -> SemanticString {
        Keyword(.protocol)

        Space()

        try dumpName(using: options, in: machOFile)

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
                TypeDeclaration(kind: .other, associatedType)
                if offset.isEnd {
                    BreakLine()
                }
            }
        }

        for (offset, requirement) in requirements.offsetEnumerated() {
            BreakLine()
            Indent(level: 1)
            if let symbol = try MachOSymbol.resolve(from: requirement.offset, in: machOFile) {
                try? MetadataReader.demangleSymbol(for: symbol, in: machOFile).printSemantic(using: options)
            } else {
                InlineComment("[Stripped Symbol]")
            }
            
            if let symbol = try requirement.defaultImplementationSymbol(in: machOFile), let defaultImplementation = try? MetadataReader.demangleSymbol(for: symbol, in: machOFile).printSemantic(using: options) {
                BreakLine()
                Indent(level: 1)
                InlineComment("[Default Implementation]")
                Space()
                defaultImplementation
            }
            
            if offset.isEnd {
                BreakLine()
            }
        }

        Standard("}")
    }
}
