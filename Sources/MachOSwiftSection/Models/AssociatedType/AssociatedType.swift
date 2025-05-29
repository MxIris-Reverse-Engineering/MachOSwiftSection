import Foundation
import MachOKit
import MachOSwiftSectionMacro

public struct AssociatedType {
    public let descriptor: AssociatedTypeDescriptor

    public let conformingTypeName: MangledName

    public let protocolTypeName: MangledName

    public let records: [AssociatedTypeRecord]

    @MachOImageGenerator
    public init(descriptor: AssociatedTypeDescriptor, in machOFile: MachOFile) throws {
        self.descriptor = descriptor
        self.conformingTypeName = try descriptor.conformingTypeName(in: machOFile)
        self.protocolTypeName = try descriptor.protocolTypeName(in: machOFile)
        self.records = try descriptor.associatedTypeRecords(in: machOFile)
    }
}

extension AssociatedType: Dumpable {
    @MachOImageGenerator
    @StringBuilder
    public func dump(using options: SymbolPrintOptions, in machOFile: MachOFile) throws -> String {
        try "extension \(MetadataReader.demangleSymbol(for: conformingTypeName, in: machOFile, using: options)): \(MetadataReader.demangleSymbol(for: protocolTypeName, in: machOFile, using: options)) {"
        for (offset, record) in records.offsetEnumerated() {
            BreakLine()

            Indent(level: 1)

            try "typealias \(record.name(in: machOFile)) = \(MetadataReader.demangleSymbol(for: record.substitutedTypeName(in: machOFile), in: machOFile, using: options))"

            if offset.isEnd {
                BreakLine()
            }
        }

        "}"
    }
}
