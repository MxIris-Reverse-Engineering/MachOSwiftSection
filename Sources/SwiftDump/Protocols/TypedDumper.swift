import Semantic
import MachOSwiftSection
import MachOKit
import Demangling
@_spi(Internals) import SwiftInspection

package protocol TypedDumper: NamedDumper where Dumped: TopLevelType, Dumped.Descriptor: TypeContextDescriptorProtocol {
    associatedtype Metadata: MetadataProtocol
    @SemanticStringBuilder var fields: SemanticString { get async throws }

    init(_ dumped: Dumped, metadata: Metadata?, using configuration: DumperConfiguration, in machO: MachO)
}

extension TypedDumper {
    /// Emits `var` or `let` based on the field record's mutability flag.
    @SemanticStringBuilder
    package func fieldMutabilityKeyword(for fieldRecord: FieldRecord) -> SemanticString {
        if fieldRecord.flags.contains(.isVariadic) {
            Keyword(.var)
        } else {
            Keyword(.let)
        }
    }

    /// Emits the full storage-modifier + mutability-keyword prefix for a stored field,
    /// including the trailing space, ready for the field name to follow.
    ///
    /// Handles `weak`, `unowned`, `unowned(unsafe)`, and `lazy`, then delegates to
    /// `fieldMutabilityKeyword(for:)` for the `var`/`let` decision. Swift 5.9+
    /// permits `weak let` / `unowned let`, so the storage modifier composes with
    /// either mutability keyword. `lazy` is the single exception and always pairs
    /// with `var`.
    @SemanticStringBuilder
    package func fieldDeclarationKeywords(
        for fieldRecord: FieldRecord,
        typeNode: Node,
        fieldName: String
    ) -> SemanticString {
        if typeNode.hasWeakNode {
            Keyword(.weak)
            Space()
            fieldMutabilityKeyword(for: fieldRecord)
            Space()
        } else if typeNode.hasUnmanagedNode {
            Keyword(.unowned)
            Standard("(")
            Keyword(.unsafe)
            Standard(")")
            Space()
            fieldMutabilityKeyword(for: fieldRecord)
            Space()
        } else if typeNode.hasUnownedNode {
            Keyword(.unowned)
            Space()
            fieldMutabilityKeyword(for: fieldRecord)
            Space()
        } else if fieldName.hasLazyPrefix {
            Keyword(.lazy)
            Space()
            Keyword(.var)
            Space()
        } else {
            fieldMutabilityKeyword(for: fieldRecord)
            Space()
        }
    }
}

extension TypedDumper {
    package var typeLayout: TypeLayout? {
        get throws {
            try dumped.descriptor.metadataAccessorFunction(in: machO)?(request: .init()).value.resolve(in: machO).valueWitnessTable(in: machO).typeLayout
        }
    }
}

extension TypedDumper {
    @SemanticStringBuilder
    func expandedFieldOffsets(for mangledTypeName: MangledName, baseOffset: Int, baseIndentation: Int, ancestors: [Bool], in machO: MachOImage?) -> SemanticString {
        let metatype: Any.Type?
        if let machO {
            metatype = try? RuntimeFunctions.getTypeByMangledNameInContext(mangledTypeName, in: machO)
        } else {
            metatype = try? RuntimeFunctions.getTypeByMangledNameInContext(mangledTypeName)
        }
        if let metatype,
           let metadata = try? Metadata.createInProcess(metatype).asMetadataWrapper().struct,
           let descriptor = try? metadata.descriptor().struct, !descriptor.isGeneric,
           let nestedFieldOffsets = try? metadata.fieldOffsets(for: descriptor),
           let nestedFieldRecords = try? descriptor.fieldDescriptor().records() {
            let fieldEntries = Array(zip(nestedFieldRecords, nestedFieldOffsets))
            for (fieldIndex, (nestedFieldRecord, nestedRelativeOffset)) in fieldEntries.enumerated() {
                if let fieldName = try? nestedFieldRecord.fieldName() {
                    let absoluteOffset = baseOffset + Int(nestedRelativeOffset)
                    let isLastField = fieldIndex == fieldEntries.count - 1
                    let nestedMangledTypeName = try? nestedFieldRecord.mangledTypeName()
                    let typeName = nestedMangledTypeName.flatMap { try? MetadataReader.demangleType(for: $0).printSemantic(using: .default).string } ?? ""
                    configuration.expandedFieldOffsetComment(fieldName: fieldName, typeName: typeName, offset: absoluteOffset, baseIndentation: baseIndentation, ancestors: ancestors, isLast: isLastField)

                    if let nestedMangledTypeName {
                        expandedFieldOffsets(for: nestedMangledTypeName, baseOffset: absoluteOffset, baseIndentation: baseIndentation, ancestors: ancestors + [isLastField], in: nil)
                    }
                }
            }
        }
    }
}
