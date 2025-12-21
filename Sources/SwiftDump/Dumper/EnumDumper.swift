import Foundation
import MachOKit
import MachOSwiftSection
import Semantic
import Utilities
import MemberwiseInit
import Demangling
import Dependencies
@_spi(Internals) import MachOSymbols
import SwiftInspection

package struct EnumDumper<MachO: MachOSwiftSectionRepresentableWithCache>: TypedDumper {
    package let dumped: Enum
    
    package let configuration: DumperConfiguration

    package let machO: MachO

    @Dependency(\.symbolIndexStore)
    private var symbolIndexStore

    package init(_ dumped: Enum, using configuration: DumperConfiguration, in machO: MachO) {
        self.dumped = dumped
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

            if let genericContext = dumped.genericContext {
                try await genericContext.dumpGenericSignature(resolver: demangleResolver, in: machO)
            }
        }
    }
    
    private var enumLayout: EnumLayoutCalculator.LayoutResult? {
        get async throws {
            let payloadSize = try dumped.descriptor.payloadSize(in: machO)
            let numberOfPayloadCases = dumped.numberOfPayloadCases
            let numberOfEmptyCases = dumped.numberOfEmptyCases
            if dumped.isMultiPayload {
                let node = try MetadataReader.demangleContext(for: .type(.enum(dumped.descriptor)), in: machO)
                if let multiPayloadEnumDescriptor = MultiPayloadEnumDescriptorCache.shared.multiPayloadEnumDescriptor(for: node, in: machO), multiPayloadEnumDescriptor.usesPayloadSpareBits {
                    let spareBytes = try multiPayloadEnumDescriptor.payloadSpareBits(in: machO)
                    let spareBytesOffset = try multiPayloadEnumDescriptor.payloadSpareBitMaskByteOffset(in: machO)
                    return try EnumLayoutCalculator.calculateMultiPayload( /* enumSize: enumTypeLayout.size.cast(), */ payloadSize: payloadSize.cast(), spareBytes: spareBytes, spareBytesOffset: spareBytesOffset.cast(), numPayloadCases: numberOfPayloadCases.cast(), numEmptyCases: numberOfEmptyCases.cast())
                } else {
                    return EnumLayoutCalculator.calculateTaggedMultiPayload(payloadSize: payloadSize.cast(), numPayloadCases: numberOfPayloadCases.cast(), numEmptyCases: numberOfEmptyCases.cast())
                }

            } else if dumped.isSinglePayload, let typeLayout = try typeLayout {
                return EnumLayoutCalculator.calculateSinglePayload(size: typeLayout.size.cast(), payloadSize: payloadSize.cast(), numEmptyCases: numberOfEmptyCases.cast())
            } else {
                return nil
            }
        }
    }

    package var fields: SemanticString {
        get async throws {
            for (offset, fieldRecord) in try dumped.descriptor.fieldDescriptor(in: machO).records(in: machO).offsetEnumerated() {
                BreakLine()

                let mangledTypeName = try fieldRecord.mangledTypeName(in: machO)

                if !mangledTypeName.isEmpty {
                    if configuration.printTypeLayout, !dumped.flags.isGeneric, let metatype = try? Runtime._getTypeByMangledNameInContext(mangledTypeName, in: machO), let metadata = try? Metadata.createInProcess(metatype) {
                        try await metadata.asMetadataWrapper().dumpTypeLayout(using: configuration)
                    }
                }

                if configuration.printEnumLayout, !dumped.flags.isGeneric {}

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
                    let node = try MetadataReader.demangleType(for: mangledTypeName, in: machO)
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
            try await resolver.resolve(for: MetadataReader.demangleContext(for: .type(.enum(dumped.descriptor)), in: machO)).replacingTypeNameOrOtherToTypeDeclaration()
        } else {
            try TypeDeclaration(kind: .enum, dumped.descriptor.name(in: machO))
        }
    }
}

@_spi(Internals) import MachOCaches
import FoundationToolbox

private final class MultiPayloadEnumDescriptorCache: SharedCache<MultiPayloadEnumDescriptorCache.Entry>, @unchecked Sendable {
    static let shared = MultiPayloadEnumDescriptorCache()

    private override init() {
        super.init()
    }

    final class Entry {
        @Mutex
        var multiPayloadEnumDescriptorByNode: [Node: MultiPayloadEnumDescriptor] = [:]
    }

    override func buildEntry(for machO: some MachORepresentableWithCache) -> Entry? {
        guard let machO = machO as? (any MachOSwiftSectionRepresentableWithCache) else { return nil }
        var multiPayloadEnumDescriptorByNode: [Node: MultiPayloadEnumDescriptor] = [:]

        do {
            for multiPayloadEnumDescriptor in try machO.swift.multiPayloadEnumDescriptors {
                let mangledTypeName = try multiPayloadEnumDescriptor.mangledTypeName(in: machO)

                let node = try MetadataReader.demangleType(for: mangledTypeName, in: machO)

                multiPayloadEnumDescriptorByNode[node] = multiPayloadEnumDescriptor
            }
        } catch {
            print(error)
        }

        let entry = Entry()
        entry.multiPayloadEnumDescriptorByNode = multiPayloadEnumDescriptorByNode
        return entry
    }

    func multiPayloadEnumDescriptor(for node: Node, in machO: some MachOSwiftSectionRepresentableWithCache) -> MultiPayloadEnumDescriptor? {
        let entry = entry(in: machO)
        return entry?.multiPayloadEnumDescriptorByNode[node]
    }
}

private struct EnumLayout {}

extension EnumDescriptor {
    fileprivate func payloadSize(in machO: some MachOSwiftSectionRepresentableWithCache) throws -> Int {
        guard hasPayloadCases else { return .zero }
        let fieldDescriptor = try fieldDescriptor(in: machO)
        let records = try fieldDescriptor.records(in: machO)
        guard !records.isEmpty else { return .zero }
        var payloadSize = 0
        let indirectPayloadSize = MemoryLayout<StoredPointer>.size
        for record in records {
            if record.flags.contains(.isIndirectCase) {
                payloadSize = max(payloadSize, indirectPayloadSize)
                continue
            }
            let mangledTypeName = try record.mangledTypeName(in: machO)
            guard !mangledTypeName.isEmpty else { continue }
            guard let metatype = try Runtime._getTypeByMangledNameInContext(mangledTypeName, genericContext: nil, genericArguments: nil, in: machO) else { continue }

            let metadata = try Metadata.createInProcess(metatype)
            let typeLayout = try metadata.asFullMetadata().valueWitnesses.resolve().typeLayout
            payloadSize = max(payloadSize, typeLayout.size.cast())
        }

        return payloadSize
    }
}
