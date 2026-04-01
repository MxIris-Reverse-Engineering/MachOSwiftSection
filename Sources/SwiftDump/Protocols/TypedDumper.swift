import Semantic
import MachOSwiftSection
import MachOKit
import SwiftInspection

package protocol TypedDumper: NamedDumper where Dumped: TopLevelType, Dumped.Descriptor: TypeContextDescriptorProtocol {
    associatedtype Metadata: MetadataProtocol
    @SemanticStringBuilder var fields: SemanticString { get async throws }

    init(_ dumped: Dumped, metadata: Metadata?, using configuration: DumperConfiguration, in machO: MachO)
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
           let nestedMetadata = try? StructMetadata.createInProcess(metatype),
           let descriptor = try? nestedMetadata.descriptor().struct,
           let nestedFieldOffsets = try? nestedMetadata.fieldOffsets(for: descriptor),
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
