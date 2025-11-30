import Foundation
import MachOKit
import MachOSwiftSection
import Semantic
import Utilities
import MemberwiseInit
import Demangling
import Dependencies
@_spi(Internals) import MachOSymbols

package struct EnumDumper<MachO: MachOSwiftSectionRepresentableWithCache>: TypedDumper {
    private let `enum`: Enum

    private let configuration: DumperConfiguration

    private let machO: MachO

    @Dependency(\.symbolIndexStore)
    private var symbolIndexStore

    package init(_ dumped: Enum, using configuration: DumperConfiguration, in machO: MachO) {
        self.enum = dumped
        self.configuration = configuration
        self.machO = machO
    }

    private var demangleResolver: DemangleResolver {
        configuration.demangleResolver
    }

    package var declaration: SemanticString {
        get async throws {
            Keyword(.enum)

            Space()

            try await name

            if let genericContext = `enum`.genericContext {
                try await genericContext.dumpGenericSignature(resolver: demangleResolver, in: machO)
            }
        }
    }

    package var fields: SemanticString {
        get async throws {
            for (offset, fieldRecord) in try `enum`.descriptor.fieldDescriptor(in: machO).records(in: machO).offsetEnumerated() {
                BreakLine()

                Indent(level: configuration.indentation)

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
                    let node = try MetadataReader.demangleType(for: mangledName, in: machO)
                    let demangledName = try await demangleResolver.resolve(for: node)
                    if node.firstChild?.isKind(of: .tuple) ?? false {
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
        }
    }

    package var body: SemanticString {
        get async throws {
            try await declaration

            Space()

            Standard("{")

            try await fields

            let interfaceNameString = try await interfaceName.string

            for kind in SymbolIndexStore.MemberKind.allCases {
                for (offset, symbol) in symbolIndexStore.memberSymbols(of: kind, for: interfaceNameString, in: machO).offsetEnumerated() {
                    if offset.isStart {
                        BreakLine()

                        Indent(level: 1)

                        InlineComment(kind.description)
                    }

                    BreakLine()

                    Indent(level: 1)

                    try await demangleResolver.resolve(for: symbol.demangledNode)

                    if offset.isEnd {
                        BreakLine()
                    }
                }
            }

            Standard("}")
        }
    }

    package var name: SemanticString {
        get async throws {
            try await _name(using: demangleResolver)
        }
    }

    private var interfaceName: SemanticString {
        get async throws {
            try await _name(using: .options(.interface))
        }
    }

    @SemanticStringBuilder
    private func _name(using resolver: DemangleResolver) async throws -> SemanticString {
        if configuration.displayParentName {
            try await resolver.resolve(for: MetadataReader.demangleContext(for: .type(.enum(`enum`.descriptor)), in: machO)).replacingTypeNameOrOtherToTypeDeclaration()
        } else {
            try TypeDeclaration(kind: .enum, `enum`.descriptor.name(in: machO))
        }
    }
}
