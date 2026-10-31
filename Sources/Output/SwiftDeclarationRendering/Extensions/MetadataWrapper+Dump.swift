import Foundation
import Semantic
import MachOKit
import MachOSwiftSection
@_spi(Internals) import SwiftInspection

extension MetadataWrapper {
    @SemanticStringBuilder
    package func dumpTypeLayout(using configuration: DumperConfiguration) async throws -> SemanticString {
        var isTuple = false
        if let tupleMetadata = tuple {
            configuration.indentString
            StructuredComment.tupleTypeLayoutHeading
            BreakLine()
            for (_, element) in try tupleMetadata.elements(in: .inProcess).enumerated() {
                let tupleElementMetadata = try element.type.resolve(in: .inProcess)
                if let descriptor = try tupleElementMetadata.typeContextDescriptorWrapper(in: .inProcess)?.asContextDescriptorWrapper {
                    configuration.indentString
                    try await StructuredComment.tupleElementType(configuration.demangleResolver.resolve(for: SymbolicDemangler.demangleContext(for: descriptor, in: .inProcess)).string)
                    BreakLine()
                    configuration.indentString
                    let elementLayout = try tupleElementMetadata.asFullMetadata(in: .inProcess).valueWitnesses.resolve(in: .inProcess).typeLayout
                    if let transformer = configuration.typeLayoutTransformer {
                        transformer(elementLayout)
                    } else {
                        elementLayout.structuredComment(labeled: "Layout")
                    }
                    BreakLine()
                }
            }
            configuration.indentString
            StructuredComment.tupleTypeLayoutTotal
            BreakLine()
            isTuple = true
        }
        let typeLayout = try valueWitnessTable(in: .inProcess).typeLayout
        configuration.indentString
        if let transformer = configuration.typeLayoutTransformer {
            transformer(typeLayout)
        } else if isTuple {
            typeLayout.structuredComment(labeled: "Layout")
        } else {
            typeLayout.structuredComment(labeled: "Type Layout")
        }
        BreakLine()
    }
}

extension TypeLayout {
    /// `// Type Layout: (size: …)`, or under `Layout` in a tuple's block.
    fileprivate func structuredComment(labeled label: String) -> StructuredComment {
        StructuredComment.typeLayout(labeled: label, size: size, stride: stride, alignment: flags.alignment, extraInhabitantCount: extraInhabitantCount)
    }

    fileprivate var dumpDebugDescription: String {
        "\(description.dropLast(1)), isPOD: \(flags.isPOD), isInlineStorage: \(flags.isInlineStorage), isBitwiseTakable: \(flags.isBitwiseTakable), isBitwiseBorrowable: \(flags.isBitwiseBorrowable), isCopyable: \(flags.isCopyable), hasEnumWitnesses: \(flags.hasEnumWitnesses), isIncomplete: \(flags.isIncomplete))"
    }
}
