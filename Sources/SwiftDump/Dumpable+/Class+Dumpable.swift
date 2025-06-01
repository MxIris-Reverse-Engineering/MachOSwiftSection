import Foundation
import MachOKit
import MachOSwiftSection
import MachOSwiftSectionMacro

extension Class: Dumpable {
    @MachOImageGenerator
    @StringBuilder
    public func dump(using options: SymbolPrintOptions, in machOFile: MachOFile) throws -> String {
        try "class \(MetadataReader.demangleContext(for: .type(.class(descriptor)), in: machOFile).print(using: options))"

        if let genericContext {
            try genericContext.dumpGenericParameters(in: machOFile)
        }

        if let superclassMangledName = try descriptor.superclassTypeMangledName(in: machOFile) {
            try ": \(MetadataReader.demangleType(for: superclassMangledName, in: machOFile).print(using: options))"
        } else if let resilientSuperclass, let kind = descriptor.resilientSuperclassReferenceKind, let superclass = try resilientSuperclass.dumpSuperclass(using: options, for: kind, in: machOFile) {
            ": \(superclass)"
        }

        if let genericContext, genericContext.requirements.count > 0 {
            " where "
            try genericContext.dumpGenericRequirements(using: options, in: machOFile)
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

        for (offset, descriptor) in methodDescriptors.offsetEnumerated() {
            BreakLine()

            Indent(level: 1)

            "[\(descriptor.flags.kind)] "

            if !descriptor.flags.isInstance, descriptor.flags.kind != .`init` {
                "static "
            }

            if descriptor.flags.isDynamic {
                "dynamic "
            }

            if descriptor.flags.kind == .method {
                "func "
            }

            if let symbol = try? descriptor.implementationSymbol(in: machOFile) {
                (try? MetadataReader.demangleSymbol(for: symbol, in: machOFile).print(using: options)) ?? "Demangle Error"
            } else if !descriptor.implementation.isNull {
                "\(descriptor.implementation.resolveDirectOffset(from: descriptor.offset(of: \.implementation)))"
            } else {
                "Symbol not found"
            }

            if offset.isEnd {
                BreakLine()
            }
        }

        for (offset, descriptor) in methodOverrideDescriptors.offsetEnumerated() {
            BreakLine()

            Indent(level: 1)

            "override "

//            if !descriptor.method.res, descriptor.flags.kind != .`init` {
//                "class "
//            }
//
//            if descriptor.flags.isDynamic {
//                "dynamic "
//            }
//
//            if descriptor.flags.kind == .method {
//                "func "
//            }

            if let symbol = try? descriptor.implementationSymbol(in: machOFile) {
                (try? MetadataReader.demangleSymbol(for: symbol, in: machOFile).print(using: options)) ?? "Error"
            } else {
                "Symbol not found"
            }

            if offset.isEnd {
                BreakLine()
            }
        }

        for (offset, descriptor) in methodDefaultOverrideDescriptors.offsetEnumerated() {
            BreakLine()

            Indent(level: 1)

            "default override "

            if let symbol = try? descriptor.implementationSymbol(in: machOFile) {
                (try? MetadataReader.demangleSymbol(for: symbol, in: machOFile).print(using: options)) ?? "Error"
            } else {
                "Symbol not found"
            }

            if offset.isEnd {
                BreakLine()
            }
        }

        "}"
    }
}
