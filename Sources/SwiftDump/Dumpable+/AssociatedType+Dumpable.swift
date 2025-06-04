import Foundation
import MachOKit
import MachOSwiftSection
import MachOMacro

extension AssociatedType: Dumpable {
    @MachOImageGenerator
    @StringBuilder
    public func dump(using options: DemangleOptions, in machOFile: MachOFile) throws -> String {
        try "extension \(MetadataReader.demangleSymbol(for: conformingTypeName, in: machOFile).print(using: options)): \(MetadataReader.demangleSymbol(for: protocolTypeName, in: machOFile).print(using: options)) {"
        for (offset, record) in records.offsetEnumerated() {
            BreakLine()

            Indent(level: 1)

            try "typealias \(record.name(in: machOFile)) = \(MetadataReader.demangleSymbol(for: record.substitutedTypeName(in: machOFile), in: machOFile).print(using: options))"

            if offset.isEnd {
                BreakLine()
            }
        }

        "}"
    }
}
