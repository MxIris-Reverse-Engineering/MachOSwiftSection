import Foundation
import MachOKit
import MachOSwiftSection
import MachOSwiftSectionMacro

extension MachOSwiftSection.`Protocol`: Dumpable {
    @MachOImageGenerator
    @StringBuilder
    public func dump(using options: SymbolPrintOptions, in machOFile: MachOFile) throws -> String {
        try "protocol \(MetadataReader.demangleContext(for: .protocol(descriptor), in: machOFile).print(using: options))"

        if numberOfRequirementsInSignature > 0 {
            " where "

            for (offset, requirement) in requirementInSignatures.offsetEnumerated() {
                try requirement.dump(using: options, in: machOFile)
                if !offset.isEnd {
                    ", "
                }
            }
        }

        " {"

        let associatedTypes = try descriptor.associatedTypes(in: machOFile)

        if !associatedTypes.isEmpty {
            for (offset, associatedType) in associatedTypes.offsetEnumerated() {
                BreakLine()
                Indent(level: 1)
                "associatedtype \(associatedType)"
                if offset.isEnd {
                    BreakLine()
                }
            }
        }

        for (offset, requirement) in requirements.offsetEnumerated() {
            BreakLine()
            Indent(level: 1)
            if let symbol = try requirement.defaultImplementationSymbol(in: machOFile) {
                "[Default Implementation] "
                try MetadataReader.demangleSymbol(for: symbol, in: machOFile).print(using: options)
            } else {
                "[Stripped Symbol]"
            }
            if offset.isEnd {
                BreakLine()
            }
        }

        "}"
    }
}
