import Foundation
import MachOKit
import MachOSwiftSection
import MachOMacro
import Semantic
import MachOSymbols
import Utilities
import MachOFoundation

private struct StructDumper<MachO: MachOSwiftSectionRepresentableWithCache & MachOReadable>: NamedDumper {
    let `struct`: Struct

    let options: DemangleOptions

    let machO: MachO

    var body: SemanticString {
        get throws {
            Keyword(.struct)

            Space()

            let name = try self.name

            let interfaceNameString = try interfaceName.string

            name

            if let genericContext = `struct`.genericContext {
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

            for (offset, fieldRecord) in try `struct`.descriptor.fieldDescriptor(in: machO).records(in: machO).offsetEnumerated() {
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
                for (offset, symbol) in SymbolIndexStore.shared.symbols(of: kind, for: interfaceNameString, in: machO).offsetEnumerated() {
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

    var name: SemanticString {
        get throws {
            try _name(using: options)
        }
    }

    private var interfaceName: SemanticString {
        get throws {
            try _name(using: .interface)
        }
    }

    private func _name(using options: DemangleOptions) throws -> SemanticString {
        try MetadataReader.demangleContext(for: .type(.struct(`struct`.descriptor)), in: machO).printSemantic(using: options).replacingTypeNameOrOtherToTypeDeclaration()
    }
}

extension Struct: NamedDumpable {
    public func dumpName<MachO: MachOSwiftSectionRepresentableWithCache & MachOReadable>(using options: DemangleOptions, in machO: MachO) throws -> SemanticString {
        try StructDumper(struct: self, options: options, machO: machO).name
    }

    public func dump<MachO: MachOSwiftSectionRepresentableWithCache & MachOReadable>(using options: DemangleOptions, in machO: MachO) throws -> SemanticString {
        try StructDumper(struct: self, options: options, machO: machO).body
    }
}
