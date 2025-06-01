import Foundation
import MachOKit
import MachOSwiftSection
import MachOMacro

extension Struct: Dumpable {
    @MachOImageGenerator
    @StringBuilder
    public func dump(using options: SymbolPrintOptions, in machOFile: MachOFile) throws -> String {
        try "struct \(MetadataReader.demangleContext(for: .type(.struct(descriptor)), in: machOFile).print(using: options))"

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

            let demangledTypeName = try MetadataReader.demangleType(for: fieldRecord.mangledTypeName(in: machOFile), in: machOFile).print(using: options)
            
            let fieldName = try fieldRecord.fieldName(in: machOFile)
            
            if fieldRecord.flags.contains(.isVariadic) {
                if demangledTypeName.hasWeakPrefix {
                    "weak var "
                } else if fieldName.hasLazyPrefix {
                    "lazy var "
                } else {
                    "var "
                }
            } else {
                "let "
            }

            "\(fieldName.stripLazyPrefix): \(demangledTypeName.stripWeakPrefix)"

            if offset.isEnd {
                BreakLine()
            }
        }

        "}"
    }
}
