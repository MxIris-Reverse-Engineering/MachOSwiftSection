import Foundation
import MachOKit
import MachOSwiftSection
import Semantic
import Utilities

package struct StructDumper<MachO: MachOSwiftSectionRepresentableWithCache>: TypedDumper {
    private let `struct`: Struct

    private let configuration: DumperConfiguration

    private let machO: MachO

    package init(_ dumped: Struct, using configuration: DumperConfiguration, in machO: MachO) {
        self.struct = dumped
        self.configuration = configuration
        self.machO = machO
    }

    private var options: DemangleOptions {
        configuration.demangleOptions
    }
    
    package var declaration: SemanticString {
        get throws {
            Keyword(.struct)
            
            Space()
            
            try name
            
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
        }
    }
    
    package var fields: SemanticString {
        get throws {
            for (offset, fieldRecord) in try `struct`.descriptor.fieldDescriptor(in: machO).records(in: machO).offsetEnumerated() {
                BreakLine()

                Indent(level: configuration.indentation)

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
        }
    }

    package var body: SemanticString {
        get throws {
            try declaration

            Space()

            Standard("{")

            try fields

            let interfaceNameString = try interfaceName.string

            for kind in SymbolIndexStore.MemberKind.allCases {
                for (offset, symbol) in SymbolIndexStore.shared.memberSymbols(of: kind, for: interfaceNameString, in: machO).offsetEnumerated() {
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

    package var name: SemanticString {
        get throws {
            try _name(using: options)
        }
    }

    private var interfaceName: SemanticString {
        get throws {
            try _name(using: .interface)
        }
    }

    @SemanticStringBuilder
    private func _name(using options: DemangleOptions) throws -> SemanticString {
        if configuration.displayParentName {
        try MetadataReader.demangleContext(for: .type(.struct(`struct`.descriptor)), in: machO).printSemantic(using: options).replacingTypeNameOrOtherToTypeDeclaration()
        } else {
            try TypeDeclaration(kind: .struct, `struct`.descriptor.name(in: machO))
        }
    }
}
