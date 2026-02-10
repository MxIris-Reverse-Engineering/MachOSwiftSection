import Foundation
import Semantic
import MachOKit
import MachOSwiftSection
import SwiftInspection

extension MetadataWrapper {
    @SemanticStringBuilder
    package func dumpTypeLayout(using configuration: DumperConfiguration) async throws -> SemanticString {
        var isTuple = false
        if let tupleMetadata = tuple {
            configuration.indentString
            InlineComment("Type Layout")
            BreakLine()
            for (_, element) in try tupleMetadata.elements().enumerated() {
                let tupleElementMetadata = try element.type.resolve()
                if let descriptor = try tupleElementMetadata.typeContextDescriptorWrapper()?.asContextDescriptorWrapper {
                    configuration.indentString
                    try await Comment("Type: " + configuration.demangleResolver.resolve(for: MetadataReader.demangleContext(for: descriptor)).string)
                    BreakLine()
                    configuration.indentString
                    let elementLayout = try tupleElementMetadata.asFullMetadata().valueWitnesses.resolve().typeLayout
                    if let transformer = configuration.typeLayoutTransformer {
                        transformer(elementLayout)
                    } else {
                        Comment(elementLayout.dumpTupleDescription)
                    }
                    BreakLine()
                }
            }
            configuration.indentString
            Comment("Total: ")
            BreakLine()
            isTuple = true
        }
        let typeLayout = try valueWitnessTable().typeLayout
        configuration.indentString
        if let transformer = configuration.typeLayoutTransformer {
            transformer(typeLayout)
        } else if isTuple {
            Comment(typeLayout.dumpTupleDescription)
        } else {
            Comment(typeLayout.dumpDescription)
        }
        BreakLine()
    }
}

extension TypeLayout {
    fileprivate var dumpDescription: String {
        "Type Layout: (size: \(size), stride: \(stride), alignment: \(flags.alignment), extraInhabitantCount: \(extraInhabitantCount))"
    }
    
    fileprivate var dumpTupleDescription: String {
        "Layout: (size: \(size), stride: \(stride), alignment: \(flags.alignment), extraInhabitantCount: \(extraInhabitantCount))"
    }
    
    fileprivate var dumpDebugDescription: String {
        "\(description.dropLast(1)), isPOD: \(flags.isPOD), isInlineStorage: \(flags.isInlineStorage), isBitwiseTakable: \(flags.isBitwiseTakable), isBitwiseBorrowable: \(flags.isBitwiseBorrowable), isCopyable: \(flags.isCopyable), hasEnumWitnesses: \(flags.hasEnumWitnesses), isIncomplete: \(flags.isIncomplete))"
    }
}
