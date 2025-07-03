import Foundation
import MachOKit
import MachOFoundation
import MachOSwiftSection
import MachOMacro
import Semantic
import MachOSymbols
import Utilities

extension Enum: NamedDumpable {
    public func dumpName<MachO: MachORepresentableWithCache & MachOReadable>(using options: DemangleOptions, in machO: MachO) throws -> SemanticString {
        try MetadataReader.demangleContext(for: .type(.enum(descriptor)), in: machO).printSemantic(using: options).replacingTypeNameOrOtherToTypeDeclaration()
    }

    @SemanticStringBuilder
    public func dump<MachO: MachORepresentableWithCache & MachOReadable>(using options: DemangleOptions, in machO: MachO) throws -> SemanticString {
        Keyword(.enum)

        Space()

        try dumpName(using: options, in: machO)

        if let genericContext {
            if genericContext.currentParameters.count > 0 {
                try genericContext.dumpGenericParameters(in: machO)
            }
            if genericContext.currentRequirements.count > 0 {
                Space()
                Keyword(.where)
                Space()
                try genericContext.dumpGenericRequirements(using: options, in: machO)
            }
        }
        Space()
        Standard("{")
        for (offset, fieldRecord) in try descriptor.fieldDescriptor(in: machO).records(in: machO).offsetEnumerated() {
            BreakLine()

            Indent(level: 1)

            if fieldRecord.flags.contains(.isIndirectCase) {
                Keyword(.indirect)
                Space()
                Keyword(.case)
                Space()
            } else {
                Keyword(.case)
                Space()
            }

            try MemberDeclaration("\(fieldRecord.fieldName(in: machO))")

            let mangledName = try fieldRecord.mangledTypeName(in: machO)

            if !mangledName.isEmpty {
                let demangledName = try MetadataReader.demangleType(for: mangledName, in: machO).printSemantic(using: options)
                let demangledNameString = demangledName.string
                if demangledNameString.hasPrefix("("), demangledNameString.hasSuffix(")") {
                    demangledName
                } else {
                    Standard("(")
                    demangledName
                    Standard(")")
                }
            }

            if offset.isEnd {
                BreakLine()
            }
        }

        for kind in SymbolIndexStore.IndexKind.allCases {
            for (offset, function) in try SymbolIndexStore.shared.symbols(of: kind, for: dumpName(using: .interface, in: machO).string, in: machO).offsetEnumerated() {
                if offset.isStart {
                    BreakLine()

                    Indent(level: 1)

                    InlineComment(kind.description)
                }

                BreakLine()

                Indent(level: 1)

                try MetadataReader.demangleSymbol(for: function, in: machO)?.printSemantic(using: options)

                if offset.isEnd {
                    BreakLine()
                }
            }
        }

        Standard("}")
    }
}
