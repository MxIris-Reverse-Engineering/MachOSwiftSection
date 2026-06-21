import Foundation
import MachOKit
import MachOSwiftSection
import Semantic
import Utilities
import MemberwiseInit
import Demangling
import Dependencies
@_spi(Internals) import MachOSymbols
@_spi(Internals) import SwiftInspection
import SwiftDeclarationRendering

package struct EnumDumper<MachO: MachOSwiftSectionRepresentableWithCache>: TypedDumper {
    package typealias Dumped = Enum

    package typealias Metadata = EnumMetadata

    package let dumped: Enum

    package let metadataContext: DumperMetadataContext<Metadata>?

    package let configuration: DumperConfiguration

    package let machO: MachO

    @Dependency(\.symbolIndexStore)
    private var symbolIndexStore

    package init(_ dumped: Dumped, using configuration: DumperConfiguration, in machO: MachO) {
        self.init(dumped, metadataContext: nil, using: configuration, in: machO)
    }

    package init(_ dumped: Dumped, metadataContext: DumperMetadataContext<Metadata>?, using configuration: DumperConfiguration, in machO: MachO) {
        self.dumped = dumped
        self.metadataContext = metadataContext
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

            // Skip the generic-signature clause when `name` already
            // rendered the bound generic form (see StructDumper for the
            // matching reasoning).
            let isBound = boundDumpedMetatype() != nil
            if !isBound, let genericContext = dumped.genericContext {
                try await genericContext.dumpGenericSignature(resolver: demangleResolver, in: machO) {
                    if let invertibleProtocolSet = dumped.invertibleProtocolSet, invertibleProtocolSet.hasInvertedProtocols {
                        invertibleProtocolSet.dumpInvertedProtocolsInheritance
                    }
                }
            } else if let invertibleProtocolSet = dumped.invertibleProtocolSet, invertibleProtocolSet.hasInvertedProtocols {
                invertibleProtocolSet.dumpInvertedProtocolsInheritance
            }
        }
    }

    package var fields: SemanticString {
        get async throws {
            // Enum layout strategy / spare-bit / per-case type-layout comments are
            // rendered by the shared `FieldLayoutRenderer` in
            // `SwiftDeclarationRendering` (single source with `SwiftPrinting`).
            // Unlike struct/class field offsets, the enum layout always resolves
            // the enum's own metadata through its accessor, so the renderer keeps
            // its default `autoResolveAccessorMetadata` behaviour.
            let fieldLayoutRenderer = FieldLayoutRenderer(
                type: .enum(dumped),
                metadata: try? metadataContext?.metadata.asMetadataWrapper(in: machO),
                machO: machO,
                configuration: configuration
            )
            let enumLayout = await fieldLayoutRenderer.enumLayout

            await fieldLayoutRenderer.enumPrefixComments(enumLayout: enumLayout)

            for (offset, fieldRecord) in try dumped.descriptor.fieldDescriptor(in: machO).records(in: machO).offsetEnumerated() {
                BreakLine()

                let mangledTypeName = try fieldRecord.mangledTypeName(in: machO)

                await fieldLayoutRenderer.enumCaseComments(forCaseAtIndex: offset.index, mangledTypeName: mangledTypeName, enumLayout: enumLayout)

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

                if !mangledTypeName.isEmpty {
                    let node = try fieldDemangledTypeNode(for: mangledTypeName)
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

                    if configuration.printMemberAddress {
                        configuration.memberAddressComment(offset: symbol.offset, addressString: machO.addressString(forOffset: symbol.offset))
                    }

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
            if let boundNode = boundDumpedTypeNode() {
                try await resolveBoundDumpedTypeName(boundNode)
            } else {
                try await _name(using: demangleResolver)
            }
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
            try await resolver.resolve(for: MetadataReader.demangleContext(for: .type(.enum(dumped.descriptor)), in: machO)).replacingTypeNameOrOtherToTypeDeclaration()
        } else {
            try TypeDeclaration(kind: .enum, dumped.descriptor.name(in: machO))
        }
    }
}
