import Foundation
import MachOKit
import MachOSwiftSection
import Semantic
import Utilities
import Dependencies
@_spi(Internals) import MachOSymbols
import SwiftInspection

package struct StructDumper<MachO: MachOSwiftSectionRepresentableWithCache>: TypedDumper {
    package let dumped: Struct

    package let configuration: DumperConfiguration

    package let machO: MachO

    @Dependency(\.symbolIndexStore)
    private var symbolIndexStore

    package init(_ dumped: Struct, using configuration: DumperConfiguration, in machO: MachO) {
        self.dumped = dumped
        self.configuration = configuration
        self.machO = machO
    }

    private var demangleResolver: DemangleResolver {
        configuration.demangleResolver
    }

    package var declaration: SemanticString {
        get async throws {
            Keyword(.struct)

            Space()

            try await name

            if let genericContext = dumped.genericContext {
                try await genericContext.dumpGenericSignature(resolver: demangleResolver, in: machO)
            }
        }
    }

    private var metadata: StructMetadata? {
        guard let metadataAccessorFunction = try? dumped.descriptor.metadataAccessorFunction(in: machO), !dumped.flags.isGeneric else { return nil }
        guard let metadataWrapper = try? metadataAccessorFunction(request: .init()).value.resolve(in: machO) else { return nil }
        return metadataWrapper.struct
    }
    
    private var fieldOffsets: [Int]? {
        guard configuration.emitOffsetComments else { return nil }
        return try? metadata?.fieldOffsets(for: dumped.descriptor, in: machO).map { $0.cast() }
    }

    package var fields: SemanticString {
        get async throws {
            let fieldOffsets = fieldOffsets
            for (offset, fieldRecord) in try dumped.descriptor.fieldDescriptor(in: machO).records(in: machO).offsetEnumerated() {
                BreakLine()

                let mangledTypeName = try fieldRecord.mangledTypeName(in: machO)
                
                if let fieldOffsets, let fieldOffset = fieldOffsets[safe: offset.index] {
                    Indent(level: configuration.indentation)
                    Comment("Field Offset: 0x\(String(fieldOffset, radix: 16))")
                    BreakLine()
                }

                if configuration.printTypeLayout, !dumped.flags.isGeneric, let metatype = try? RuntimeFunctions.getTypeByMangledNameInContext(mangledTypeName, in: machO), let metadata = try? Metadata.createInProcess(metatype) {
                    try await metadata.asMetadataWrapper().dumpTypeLayout(using: configuration)
                }
                
                Indent(level: configuration.indentation)

                let demangledTypeNode = try MetadataReader.demangleType(for: mangledTypeName, in: machO)

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
                try await demangleResolver.modify {
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
            try await resolver.resolve(for: MetadataReader.demangleContext(for: .type(.struct(dumped.descriptor)), in: machO)).replacingTypeNameOrOtherToTypeDeclaration()
        } else {
            try TypeDeclaration(kind: .struct, dumped.descriptor.name(in: machO))
        }
    }
}
