import Foundation
import MachOKit
import MachOSwiftSection
import Semantic
import Utilities
@_spi(Internals) import SwiftInspection
import Demangling

package struct AssociatedTypeDumper<MachO: MachOSwiftSectionRepresentableWithCache>: ConformedDumper {
    package let dumped: AssociatedType

    package let configuration: DumperConfiguration

    package let machO: MachO

    package init(_ dumped: AssociatedType, using configuration: DumperConfiguration, in machO: MachO) {
        self.dumped = dumped
        self.configuration = configuration
        self.machO = machO
    }

    private var demangleResolver: DemangleResolver {
        configuration.demangleResolver
    }

    package var declaration: SemanticString {
        get async throws {
            Keyword(.extension)

            Space()

            let typeName = try await typeName

            typeName

            Standard(":")

            Space()

            try await protocolName
        }
    }

    @SemanticStringBuilder
    package var records: SemanticString {
        get async throws {
            for (offset, record) in dumped.records.offsetEnumerated() {
                BreakLine()

                Indent(level: 1)

                Keyword(.typealias)

                Space()

                try TypeDeclaration(kind: .other, record.name(in: machO))

                Space()

                Standard("=")

                Space()

                try await demangleResolver.resolve(for: MetadataReader.demangleType(for: record.substitutedTypeName(in: machO), in: machO).resolveOpaqueType(in: machO))

                if offset.isEnd {
                    BreakLine()
                }
            }
        }
    }

    /// Emits a deduplicated typealias block collected from every supplied ``AssociatedType``.
    ///
    /// When an extension is materialized from multiple sibling conformances (e.g. `Sequence`
    /// + `Collection` + `BidirectionalCollection`), each conformance contributes its own
    /// `AssociatedType` descriptor whose records overlap. Merging them verbatim produces
    /// duplicate `typealias` lines; this helper dedupes by `(record name, mangled
    /// substituted type)` so each unique entry prints once while preserving the first-seen
    /// ordering.
    @SemanticStringBuilder
    package static func mergedRecords(of associatedTypes: [AssociatedType], using configuration: DumperConfiguration, in machO: MachO) async throws -> SemanticString {
        let orderedRecords = collectUniqueRecords(of: associatedTypes, in: machO)
        let resolver = configuration.demangleResolver
        for (offset, record) in orderedRecords.offsetEnumerated() {
            BreakLine()

            Indent(level: 1)

            Keyword(.typealias)

            Space()

            TypeDeclaration(kind: .other, record.name)

            Space()

            Standard("=")

            Space()

            try await resolver.resolve(for: MetadataReader.demangleType(for: record.mangledTypeName, in: machO).resolveOpaqueType(in: machO))

            if offset.isEnd {
                BreakLine()
            }
        }
    }

    private struct AssociatedTypeRecordDedupKey: Hashable {
        let name: String
        let mangledTypeName: MangledName
    }

    private static func collectUniqueRecords(of associatedTypes: [AssociatedType], in machO: MachO) -> [(name: String, mangledTypeName: MangledName)] {
        var seenKeys: Set<AssociatedTypeRecordDedupKey> = []
        var orderedRecords: [(name: String, mangledTypeName: MangledName)] = []
        for associatedType in associatedTypes {
            for record in associatedType.records {
                let recordName: String
                let mangledTypeName: MangledName
                do {
                    recordName = try record.name(in: machO)
                    mangledTypeName = try record.substitutedTypeName(in: machO)
                } catch {
                    continue
                }
                if seenKeys.insert(AssociatedTypeRecordDedupKey(name: recordName, mangledTypeName: mangledTypeName)).inserted {
                    orderedRecords.append((recordName, mangledTypeName))
                }
            }
        }
        return orderedRecords
    }

    package var body: SemanticString {
        get async throws {
            try await declaration

            Space()

            Standard("{")

            try await records

            Standard("}")
        }
    }

    package var typeName: SemanticString {
        get async throws {
            try await demangleResolver.resolve(for: MetadataReader.demangleType(for: dumped.conformingTypeName, in: machO)).replacingTypeNameOrOtherToTypeDeclaration()
        }
    }

    package var protocolName: SemanticString {
        get async throws {
            try await demangleResolver.resolve(for: MetadataReader.demangleType(for: dumped.protocolTypeName, in: machO))
        }
    }
}

import OrderedCollections

extension Node {
    private final class OpaqueTypeGenericParameterRewriter<MachO: MachOSwiftSectionRepresentableWithCache>: Node.Rewriter {
        let machO: MachO

        let typeList: OrderedDictionary<Int, [Node]>

        init(machO: MachO, typeList: OrderedDictionary<Int, [Node]>) {
            self.machO = machO
            self.typeList = typeList
        }

        override func visit(_ node: Node) -> Node {
            if node.isKind(of: .dependentGenericParamType), let depth: Int = node[safeChild: 0]?.index?.cast(), let index: Int = node[safeChild: 1]?.index?.cast(), let type = typeList[depth, default: []][safe: index], type.isKind(of: .type), let firstChild = node.firstChild {
                return firstChild.copy()
            } else {
                return node
            }
        }
    }

    private final class OpaqueTypeRewriter<MachO: MachOSwiftSectionRepresentableWithCache>: Node.Rewriter {
        let machO: MachO

        init(machO: MachO) {
            self.machO = machO
        }

        override func visit(_ node: Node) -> Node {
            do {
                if node.isKind(of: .opaqueType), let firstChild = node.firstChild, firstChild.isKind(of: .opaqueTypeDescriptorSymbolicReference), let offset: Int = firstChild.index?.cast() {
                    let opaqueTypeDescriptor = try OpaqueTypeDescriptor.resolve(from: offset, in: machO)
                    let opaqueType = try OpaqueType(descriptor: opaqueTypeDescriptor, in: machO)

                    var allTypeList: OrderedDictionary<Int, [Node]> = [:]
                    if let rootTypeListNode = node[safeChild: 2] {
                        for (depth, typeList) in rootTypeListNode.children.enumerated() {
                            for type in typeList {
                                allTypeList[depth, default: []].append(type)
                            }
                        }
                    }
                    if let underlyingTypeArgumentMangledName = opaqueType.underlyingTypeArgumentMangledNames[safe: 0], let underlyingTypeArgumentNode = try? MetadataReader.demangleType(for: underlyingTypeArgumentMangledName, in: machO), underlyingTypeArgumentNode.kind == .type, let firstChild = underlyingTypeArgumentNode.firstChild {
                        return OpaqueTypeGenericParameterRewriter(machO: machO, typeList: allTypeList).rewrite(firstChild.copy())
                    }
                }
            } catch {
                Swift.print(error)
            }
            return node
        }
    }

    fileprivate func resolveOpaqueType(in machO: some MachOSwiftSectionRepresentableWithCache) throws -> Node {
        OpaqueTypeRewriter(machO: machO).rewrite(self)
    }
}
