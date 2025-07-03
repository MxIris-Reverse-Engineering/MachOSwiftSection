import Foundation
import MachOKit
import MachOSwiftSection
import MachOMacro
import Semantic
import Utilities
import MachOFoundation

extension AssociatedType: ConformedDumpable {
    @SemanticStringBuilder
    public func dumpTypeName<MachO: MachORepresentableWithCache & MachOReadable>(using options: DemangleOptions, in machO: MachO) throws -> SemanticString {
        try MetadataReader.demangleSymbol(for: conformingTypeName, in: machO).printSemantic(using: options).replacingTypeNameOrOtherToTypeDeclaration()
    }

    @SemanticStringBuilder
    public func dumpProtocolName<MachO: MachORepresentableWithCache & MachOReadable>(using options: DemangleOptions, in machO: MachO) throws -> SemanticString {
        try MetadataReader.demangleSymbol(for: protocolTypeName, in: machO).printSemantic(using: options)
    }

    @SemanticStringBuilder
    public func dump<MachO: MachORepresentableWithCache & MachOReadable>(using options: DemangleOptions, in machO: MachO) throws -> SemanticString {
        Keyword(.extension)

        Space()

        try dumpTypeName(using: options, in: machO)

        Standard(":")

        Space()

        try dumpProtocolName(using: options, in: machO)

        Space()

        Standard("{")

        for (offset, record) in records.offsetEnumerated() {
            BreakLine()

            Indent(level: 1)

            Keyword(.typealias)

            Space()

            try TypeDeclaration(kind: .other, record.name(in: machO))

            Space()

            Standard("=")

            Space()

            try MetadataReader.demangleSymbol(for: record.substitutedTypeName(in: machO), in: machO).printSemantic(using: options)

            if offset.isEnd {
                BreakLine()
            }
        }

        Standard("}")
    }
}
