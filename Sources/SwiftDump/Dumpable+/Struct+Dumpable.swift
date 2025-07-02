import Foundation
import MachOKit
import MachOSwiftSection
import MachOMacro
import Semantic
import MachOSymbols
import Utilities

extension Struct: NamedDumpable {
    @MachOImageGenerator
    public func dumpName(using options: DemangleOptions, in machOFile: MachOFile) throws -> SemanticString {
        try MetadataReader.demangleContext(for: .type(.struct(descriptor)), in: machOFile).printSemantic(using: options).replacingTypeNameOrOtherToTypeDeclaration()
    }

    @MachOImageGenerator
    @SemanticStringBuilder
    public func dump(using options: DemangleOptions, in machOFile: MachOFile) throws -> SemanticString {
        Keyword(.struct)

        Space()

        try dumpName(using: options, in: machOFile)

        if let genericContext {
            if genericContext.currentParameters.count > 0 {
                try genericContext.dumpGenericParameters(in: machOFile)
            }
            if genericContext.currentRequirements.count > 0 {
                Space()
                Keyword(.where)
                Space()
                try genericContext.dumpGenericRequirements(using: options, in: machOFile)
            }
        }

        Space()

        Standard("{")

        for (offset, fieldRecord) in try descriptor.fieldDescriptor(in: machOFile).records(in: machOFile).offsetEnumerated() {
            BreakLine()

            Indent(level: 1)

            let demangledTypeNode = try MetadataReader.demangleType(for: fieldRecord.mangledTypeName(in: machOFile), in: machOFile)

            let fieldName = try fieldRecord.fieldName(in: machOFile)

            if fieldRecord.flags.contains(.isVariadic) {
                if demangledTypeNode.hasWeakNode {
                    Keyword(.weak)
                    Space()
                    Keyword(.var)
                    Space()
                } else if fieldName.hasLazyPrefix {
                    Keyword(.lazy)
                    Space()
                    Keyword(.var)
                    Space()
                } else {
                    Keyword(.var)
                    Space()
                }
            } else {
                Keyword(.let)
                Space()
            }

            MemberDeclaration(fieldName.stripLazyPrefix)
            Standard(":")
            Space()
            demangledTypeNode.printSemantic(using: options.union(.removeWeakPrefix))

            if offset.isEnd {
                BreakLine()
            }
        }

        for kind in SymbolIndexStore.IndexKind.allCases {
            for (offset, symbol) in try SymbolIndexStore.shared.symbols(of: kind, for: dumpName(using: .interface, in: machOFile).string, in: machOFile).offsetEnumerated() {
                if offset.isStart {
                    BreakLine()

                    Indent(level: 1)

                    InlineComment(kind.description)
                }

                BreakLine()

                Indent(level: 1)

                try MetadataReader.demangleSymbol(for: symbol, in: machOFile)?.printSemantic(using: options)

                if offset.isEnd {
                    BreakLine()
                }
            }
        }

        Standard("}")
    }
}
