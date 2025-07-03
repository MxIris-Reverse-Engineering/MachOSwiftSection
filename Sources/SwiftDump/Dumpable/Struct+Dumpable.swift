import Foundation
import MachOKit
import MachOSwiftSection
import MachOMacro
import Semantic
import MachOSymbols
import Utilities
import MachOFoundation

extension Struct: NamedDumpable {
    public func dumpName<MachO: MachORepresentableWithCache & MachOReadable>(using options: DemangleOptions, in machO: MachO) throws -> SemanticString {
        try MetadataReader.demangleContext(for: .type(.struct(descriptor)), in: machO).printSemantic(using: options).replacingTypeNameOrOtherToTypeDeclaration()
    }

    @SemanticStringBuilder
    public func dump<MachO: MachORepresentableWithCache & MachOReadable>(using options: DemangleOptions, in machO: MachO) throws -> SemanticString {
        Keyword(.struct)

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

            let demangledTypeNode = try MetadataReader.demangleType(for: fieldRecord.mangledTypeName(in: machO), in: machO)

            let fieldName = try fieldRecord.fieldName(in: machO)

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
            for (offset, symbol) in try SymbolIndexStore.shared.symbols(of: kind, for: dumpName(using: .interface, in: machO).string, in: machO).offsetEnumerated() {
                if offset.isStart {
                    BreakLine()

                    Indent(level: 1)

                    InlineComment(kind.description)
                }

                BreakLine()

                Indent(level: 1)

                try MetadataReader.demangleSymbol(for: symbol, in: machO)?.printSemantic(using: options)

                if offset.isEnd {
                    BreakLine()
                }
            }
        }

        Standard("}")
    }
}
