import Foundation
import MachOKit
import MachOSwiftSection
import MachOMacro
import Semantic

extension AssociatedType: ConformedDumpable {
    @MachOImageGenerator
    @SemanticStringBuilder
    public func dumpTypeName(using options: DemangleOptions, in machOFile: MachOFile) throws -> SemanticString {
        try MetadataReader.demangleSymbol(for: conformingTypeName, in: machOFile).printSemantic(using: options).replacingTypeNameOrOtherToTypeDeclaration()
    }

    @MachOImageGenerator
    @SemanticStringBuilder
    public func dumpProtocolName(using options: DemangleOptions, in machOFile: MachOFile) throws -> SemanticString {
        try MetadataReader.demangleSymbol(for: protocolTypeName, in: machOFile).printSemantic(using: options)
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

        Space()

        Standard("{")

        for (offset, record) in records.offsetEnumerated() {
            BreakLine()

            Indent(level: 1)

            Keyword(.typealias)

            Space()

            try TypeDeclaration(kind: .other, record.name(in: machOFile))

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
