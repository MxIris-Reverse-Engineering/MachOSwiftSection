import Foundation
import MachOKit
import MachOSwiftSection
import Semantic
import Utilities
import Dependencies
import Demangling
@_spi(Internals) import MachOSymbols
@_spi(Internals) import SwiftInspection

package struct StructDumper<MachO: MachOSwiftSectionRepresentableWithCache>: TypedDumper {
    package typealias Dumped = Struct

    package typealias Metadata = StructMetadata

    package let dumped: Struct

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
            Keyword(.struct)

            Space()

            try await name

            // When the dumper is rendering a specialized type (`Foo<Int>`),
            // the bound name printed by `name` already carries the concrete
            // type arguments; emitting the generic-signature clause again
            // would produce `Foo<Int><A: Hashable>`. Skip the clause in
            // that case and only keep the invertible-protocol marker, which
            // is orthogonal to substitution.
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

    private var fieldOffsets: [Int]? {
        guard configuration.printFieldOffset else { return nil }
        guard let metadataContext else { return nil }
        return try? metadataContext.metadata.fieldOffsets(for: dumped.descriptor, in: metadataContext.readingContext).map { $0.cast() }
    }

    package var fields: SemanticString {
        get async throws {
            let fieldOffsets = fieldOffsets
            for (offset, fieldRecord) in try dumped.descriptor.fieldDescriptor(in: machO).records(in: machO).offsetEnumerated() {
                BreakLine()

                let mangledTypeName = try fieldRecord.mangledTypeName(in: machO)

                if let fieldOffsets, let startOffset = fieldOffsets[safe: offset.index] {
                    let endOffset: Int?
                    if let nextFieldOffset = fieldOffsets[safe: offset.index + 1] {
                        endOffset = nextFieldOffset
                    } else if let machOImage = machO.asMachOImage,
                              let metatype = resolveFieldMetatype(for: mangledTypeName, in: machOImage),
                              let metadata = try? Metadata.createInProcess(metatype),
                              let typeLayout = try? metadata.asMetadataWrapper().valueWitnessTable().typeLayout {
                        endOffset = startOffset + Int(typeLayout.size)
                    } else {
                        endOffset = nil
                    }
                    configuration.fieldOffsetComment(startOffset: startOffset, endOffset: endOffset)

                    if configuration.printExpandedFieldOffsets, let machOImage = machO.asMachOImage {
                        expandedFieldOffsets(for: mangledTypeName, baseOffset: startOffset, baseIndentation: configuration.indentation, ancestors: [], in: machOImage)
                    }
                }

                if configuration.printTypeLayout,
                   let machOImage = machO.asMachOImage,
                   let resolvedMetatype = resolveFieldMetatype(for: mangledTypeName, in: machOImage),
                   let resolvedMetadata = try? Metadata.createInProcess(resolvedMetatype) {
                    try await resolvedMetadata.asMetadataWrapper().dumpTypeLayout(using: configuration)
                }

                Indent(level: configuration.indentation)

                let demangledTypeNode = try fieldDemangledTypeNode(for: mangledTypeName)

                let fieldName = try fieldRecord.fieldName(in: machO)

                fieldDeclarationKeywords(for: fieldRecord, typeNode: demangledTypeNode, fieldName: fieldName)

                MemberDeclaration(fieldName.stripLazyPrefix)
                Standard(":")
                Space()
                try await demangleResolver.modify {
                    if case .options(let demangleOptions) = $0 {
                        return .options(demangleOptions.union(.removeReferenceStoragePrefix))
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
            // For a specialized dumper, prefer the bound generic node
            // (e.g. `Foo<Int>`) so the rendered declaration carries the
            // concrete type arguments. `resolveBoundDumpedTypeName` keeps
            // the outer head as a `.declaration` while leaving the type
            // arguments inside `<...>` with regular `.name` styling — the
            // same semantics every other type reference in the dump uses.
            // The interface-form name used for symbol-index lookups stays
            // on the unbound path below.
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
            try await resolver.resolve(for: MetadataReader.demangleContext(for: .type(.struct(dumped.descriptor)), in: machO)).replacingTypeNameOrOtherToTypeDeclaration()
        } else {
            try TypeDeclaration(kind: .struct, dumped.descriptor.name(in: machO))
        }
    }
}

extension TypedDumper {
    
}

extension FieldRecordFlags {
    
}
