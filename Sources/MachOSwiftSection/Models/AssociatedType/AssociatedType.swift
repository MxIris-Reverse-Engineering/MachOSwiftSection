import Foundation
import MachOKit
import MachOSwiftSectionMacro

public struct AssociatedType {
    public let descriptor: AssociatedTypeDescriptor

    public let conformingTypeName: MangledName

    public let protocolTypeName: MangledName

    public let records: [AssociatedTypeRecord]

    private var _cacheDescription: String = ""
    
    @MachOImageGenerator
    public init(descriptor: AssociatedTypeDescriptor, in machOFile: MachOFile) throws {
        self.descriptor = descriptor
        self.conformingTypeName = try descriptor.conformingTypeName(in: machOFile)
        self.protocolTypeName = try descriptor.protocolTypeName(in: machOFile)
        self.records = try descriptor.associatedTypeRecords(in: machOFile)
        
        do {
            _cacheDescription = try buildDescription(in: machOFile)
        } catch  {
            _cacheDescription = "Error \(error)"
        }
    }

    @MachOImageGenerator
    @StringBuilder
    private func buildDescription(in machOFile: MachOFile) throws -> String {
        try "extension \(MetadataReader.demangleSymbol(for: conformingTypeName, in: machOFile)): \(MetadataReader.demangleSymbol(for: protocolTypeName, in: machOFile)) {"
        for (offset, record) in records.offsetEnumerated() {
            BreakLine()

            Indent(level: 1)

            try "typealias \(record.name(in: machOFile)) = \(MetadataReader.demangleSymbol(for: record.substitutedTypeName(in: machOFile), in: machOFile))"

            if offset.isEnd {
                BreakLine()
            }
        }

        "}"
    }
}

extension AssociatedType: CustomStringConvertible {
    public var description: String {
        _cacheDescription
    }
}
