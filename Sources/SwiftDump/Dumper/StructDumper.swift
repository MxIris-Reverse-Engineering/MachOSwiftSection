import Foundation
import MachOKit
import MachOSwiftSection
import Semantic
import Utilities
import Dependencies

package struct StructDumper<MachO: MachOSwiftSectionRepresentableWithCache>: TypedDumper {
    private let `struct`: Struct

    private let configuration: DumperConfiguration

    private let machO: MachO
    
    @Dependency(\.symbolIndexStore)
    private var symbolIndexStore
    
    package init(_ dumped: Struct, using configuration: DumperConfiguration, in machO: MachO) {
        self.struct = dumped
        self.configuration = configuration
        self.machO = machO
    }

    private var demangleResolver: DemangleResolver {
        configuration.demangleResolver
    }

    package var declaration: SemanticString {
        get throws {
            Keyword(.struct)

            Space()

            try name

            if let genericContext = `struct`.genericContext {
                if genericContext.currentParameters(in: machO).count > 0 {
                    try genericContext.dumpGenericParameters(in: machO)
                }
                if genericContext.currentRequirements(in: machO).count > 0 {
                    Space()
                    Keyword(.where)
                    Space()
                    try genericContext.dumpGenericRequirements(resolver: demangleResolver, in: machO)
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
                try demangleResolver.modify {
                    if case .options(let demangleOptions) = $0 {
                        return .options(demangleOptions.union(.removeWeakPrefix))
                    } else {
                        return $0
                    }
                }
                .resolve(for: demangledTypeNode)

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
                for (offset, symbol) in symbolIndexStore.memberSymbols(of: kind, for: interfaceNameString, in: machO).offsetEnumerated() {
                    if offset.isStart {
                        BreakLine()

                        Indent(level: 1)

                        InlineComment(kind.description)
                    }

                    BreakLine()

                    Indent(level: 1)

                    try demangleResolver.resolve(for: symbol.demangledNode)

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
            try _name(using: demangleResolver)
        }
    }

    private var interfaceName: SemanticString {
        get throws {
            try _name(using: .options(.interface))
        }
    }

    @SemanticStringBuilder
    private func _name(using resolver: DemangleResolver) throws -> SemanticString {
        if configuration.displayParentName {
            try resolver.resolve(for: MetadataReader.demangleContext(for: .type(.struct(`struct`.descriptor)), in: machO)).replacingTypeNameOrOtherToTypeDeclaration()
        } else {
            try TypeDeclaration(kind: .struct, `struct`.descriptor.name(in: machO))
        }
    }
}
