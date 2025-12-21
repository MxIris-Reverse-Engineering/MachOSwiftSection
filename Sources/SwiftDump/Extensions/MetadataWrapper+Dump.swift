import Foundation
import Semantic
import MachOKit
import MachOSwiftSection
import SwiftInspection

extension MetadataWrapper {
    @SemanticStringBuilder
    package func dumpTypeLayout(using configuration: DumperConfiguration) async throws -> SemanticString {
        if let tupleMetadata = tuple {
            for (index, element) in try tupleMetadata.elements().enumerated() {
                let tupleElementMetadata = try element.type.resolve()
                if let descriptor = try tupleElementMetadata.typeContextDescriptorWrapper()?.asContextDescriptorWrapper {
                    configuration.indentString
                    Comment("Index: " + index.description)
                    BreakLine()
                    configuration.indentString
                    try await Comment("Type: " + configuration.demangleResolver.resolve(for: MetadataReader.demangleContext(for: descriptor)).string)
                    BreakLine()
                    configuration.indentString
                    try Comment("- " + tupleElementMetadata.asFullMetadata().valueWitnesses.resolve().typeLayout.description)
                    BreakLine()
                    configuration.indentString
                    Comment("Total: ")
                    BreakLine()
                }
            }
        }
        configuration.indentString
        try Comment(valueWitnessTable().typeLayout.description)
        BreakLine()
    }
}
