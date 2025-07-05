import Foundation
import MachOKit
import MachOSwiftSection
import MachOMacro
import Semantic
import Utilities
import MachOFoundation

private struct AssociatedTypeDumper<MachO: MachOSwiftSectionRepresentableWithCache & MachOReadable>: ConformedDumper {
    let associatedType: AssociatedType
    let options: DemangleOptions
    let machO: MachO

    var body: SemanticString {
        get throws {
            Keyword(.extension)

            Space()

            try typeName

            Standard(":")

            Space()

            try protocolName

            Space()

            Standard("{")

            for (offset, record) in associatedType.records.offsetEnumerated() {
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

    var typeName: SemanticString {
        get throws {
            try MetadataReader.demangleSymbol(for: associatedType.conformingTypeName, in: machO).printSemantic(using: options).replacingTypeNameOrOtherToTypeDeclaration()
        }
    }

    var protocolName: SemanticString {
        get throws {
            try MetadataReader.demangleSymbol(for: associatedType.protocolTypeName, in: machO).printSemantic(using: options)
        }
    }
}

extension AssociatedType: ConformedDumpable {
    public func dumpTypeName<MachO: MachOSwiftSectionRepresentableWithCache & MachOReadable>(using options: DemangleOptions, in machO: MachO) throws -> SemanticString {
        try AssociatedTypeDumper(associatedType: self, options: options, machO: machO).typeName
    }

    public func dumpProtocolName<MachO: MachOSwiftSectionRepresentableWithCache & MachOReadable>(using options: DemangleOptions, in machO: MachO) throws -> SemanticString {
        try AssociatedTypeDumper(associatedType: self, options: options, machO: machO).protocolName
    }

    public func dump<MachO: MachOSwiftSectionRepresentableWithCache & MachOReadable>(using options: DemangleOptions, in machO: MachO) throws -> SemanticString {
        try AssociatedTypeDumper(associatedType: self, options: options, machO: machO).body
    }
}
