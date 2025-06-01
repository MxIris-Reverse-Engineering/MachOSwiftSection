import Foundation
import MachOKit
import MachOSwiftSection
import MachOSwiftSectionMacro

extension Enum: Dumpable {
    @MachOImageGenerator
    @StringBuilder
    public func dump(using options: SymbolPrintOptions, in machOFile: MachOFile) throws -> String {
        try "enum \(MetadataReader.demangleContext(for: .type(.enum(descriptor)), in: machOFile).print(using: options))"

        if let genericContext {
            try genericContext.dumpGenericParameters(in: machOFile)
            if genericContext.requirements.count > 0 {
                " where "
                try genericContext.dumpGenericRequirements(using: options, in: machOFile)
            }
        }

        " {"
        for (offset, fieldRecord) in try descriptor.fieldDescriptor(in: machOFile).records(in: machOFile).offsetEnumerated() {
            BreakLine()

            Indent(level: 1)

            if fieldRecord.flags.contains(.isIndirectCase) {
                "indirect case "
            } else {
                "case "
            }

            try "\(fieldRecord.fieldName(in: machOFile))"

            let mangledName = try fieldRecord.mangledTypeName(in: machOFile)

            if !mangledName.isEmpty {
                try MetadataReader.demangleType(for: mangledName, in: machOFile).print(using: options).insertBracketIfNeeded
            }

            if offset.isEnd {
                BreakLine()
            }
        }

        "}"
    }
}
