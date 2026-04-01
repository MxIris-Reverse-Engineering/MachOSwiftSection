import Foundation
import MachOKit
import MachOSwiftSection
import Semantic
import Utilities
import Dependencies
import Demangling
@_spi(Internals) import MachOSymbols
import SwiftInspection

package struct StructDumper<MachO: MachOSwiftSectionRepresentableWithCache>: TypedDumper {
    package typealias Dumped = Struct
    
    package typealias Metadata = StructMetadata
    
    package let dumped: Struct

    package let metadata: StructMetadata?

    package let configuration: DumperConfiguration

    package let machO: MachO

    @Dependency(\.symbolIndexStore)
    private var symbolIndexStore

    package init(_ dumped: Dumped, using configuration: DumperConfiguration, in machO: MachO) {
        self.init(dumped, metadata: nil, using: configuration, in: machO)
    }

    package init(_ dumped: Dumped, metadata: Metadata?, using configuration: DumperConfiguration, in machO: MachO) {
        self.dumped = dumped
        self.metadata = metadata
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

    private var fieldOffsets: [Int]? {
        guard configuration.printFieldOffset else { return nil }
        return try? metadata?.fieldOffsets(for: dumped.descriptor, in: machO).map { $0.cast() }
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
                    } else if !dumped.flags.isGeneric,
                              let machOImage = machO.asMachOImage,
                              let metatype = try? RuntimeFunctions.getTypeByMangledNameInContext(mangledTypeName, in: machOImage),
                              let metadata = try? Metadata.createInProcess(metatype),
                              let typeLayout = try? metadata.asMetadataWrapper().valueWitnessTable().typeLayout {
                        endOffset = startOffset + Int(typeLayout.size)
                    } else {
                        endOffset = nil
                    }
                    configuration.fieldOffsetComment(startOffset: startOffset, endOffset: endOffset)

                    if configuration.printExpandedFieldOffsets {
                        expandedFieldOffsets(for: mangledTypeName, baseOffset: startOffset, indentation: configuration.indentation + 1)
                    }
                }

                if configuration.printTypeLayout, !dumped.flags.isGeneric, let machO = machO.asMachOImage, let metatype = try? RuntimeFunctions.getTypeByMangledNameInContext(mangledTypeName, in: machO), let metadata = try? Metadata.createInProcess(metatype) {
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

    // MARK: - Expanded Field Offsets

    @SemanticStringBuilder
    private func expandedFieldOffsets(for mangledTypeName: MangledName, baseOffset: Int, indentation: Int) -> SemanticString {
        if let machOImage = machO.asMachOImage,
           let structDescriptor = resolveStructDescriptor(for: mangledTypeName),
           let metatype = try? RuntimeFunctions.getTypeByMangledNameInContext(mangledTypeName, in: machOImage),
           let nestedMetadata = try? StructMetadata.createInProcess(metatype),
           let nestedFieldOffsets = try? nestedMetadata.fieldOffsets(for: structDescriptor),
           let nestedFieldRecords = try? structDescriptor.fieldDescriptor(in: machO).records(in: machO) {
            for (nestedFieldRecord, nestedRelativeOffset) in zip(nestedFieldRecords, nestedFieldOffsets) {
                if let fieldName = try? nestedFieldRecord.fieldName(in: machO) {
                    let absoluteOffset = baseOffset + Int(nestedRelativeOffset)
                    configuration.expandedFieldOffsetComment(fieldName: fieldName, offset: absoluteOffset, indentation: indentation)

                    if let nestedMangledTypeName = try? nestedFieldRecord.mangledTypeName(in: machO) {
                        expandedFieldOffsets(for: nestedMangledTypeName, baseOffset: absoluteOffset, indentation: indentation + 1)
                    }
                }
            }
        }
    }

    private func resolveStructDescriptor(for mangledTypeName: MangledName) -> StructDescriptor? {
        guard let lookup = mangledTypeName.lookupElements.first,
              case .relative(let relativeReference) = lookup.reference,
              let (kind, directness) = SymbolicReference.symbolicReference(for: relativeReference.kind),
              kind == .context, directness == .direct else { return nil }
        guard let contextWrapper = try? RelativeDirectPointer<ContextDescriptorWrapper>(relativeOffset: relativeReference.relativeOffset).resolve(from: lookup.offset, in: machO),
              case .type(.struct(let structDescriptor)) = contextWrapper else { return nil }
        return structDescriptor
    }
}
