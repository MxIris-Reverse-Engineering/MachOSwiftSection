import Foundation
import Semantic
import MachOKit
import MachOSwiftSection
@_spi(Internals) import SwiftInspection

extension MetadataWrapper {
    /// The type layout comment, or for a tuple the block of its elements'
    /// layouts and its own. Marking comment structure, the whole of it is one
    /// `typeLayout` region, each element a `typeLayoutElement` inside it.
    @SemanticStringBuilder
    package func dumpTypeLayout(using configuration: DumperConfiguration) async throws -> SemanticString {
        try await configuration.commentRegion(.typeLayout) {
            try await typeLayoutLines(using: configuration)
        }
    }

    @SemanticStringBuilder
    private func typeLayoutLines(using configuration: DumperConfiguration) async throws -> SemanticString {
        var isTuple = false
        if let tupleMetadata = tuple {
            configuration.indentString
            configuration.comment(.tupleTypeLayoutHeading, as: nil)
            BreakLine()
            for (_, element) in try tupleMetadata.elements(in: .inProcess).enumerated() {
                let tupleElementMetadata = try element.type.resolve(in: .inProcess)
                if let descriptor = try tupleElementMetadata.typeContextDescriptorWrapper(in: .inProcess)?.asContextDescriptorWrapper {
                    let elementTypeName = try await configuration.demangleResolver.resolve(for: SymbolicDemangler.demangleContext(for: descriptor, in: .inProcess)).string
                    let elementLayout = try tupleElementMetadata.asFullMetadata(in: .inProcess).valueWitnesses.resolve(in: .inProcess).typeLayout
                    configuration.commentRegion(.typeLayoutElement) {
                        configuration.indentString
                        configuration.comment(.tupleElementType(elementTypeName), as: nil)
                        BreakLine()
                        configuration.indentString
                        if let transformer = configuration.typeLayoutTransformer {
                            configuration.templatedComment(transformer(elementLayout), as: nil)
                        } else {
                            configuration.comment(elementLayout.structuredComment(labeled: "Layout"), as: nil)
                        }
                        BreakLine()
                    }
                }
            }
            configuration.indentString
            configuration.comment(.tupleTypeLayoutTotal, as: nil)
            BreakLine()
            isTuple = true
        }
        let typeLayout = try valueWitnessTable(in: .inProcess).typeLayout
        configuration.indentString
        if let transformer = configuration.typeLayoutTransformer {
            configuration.templatedComment(transformer(typeLayout), as: nil)
        } else if isTuple {
            configuration.comment(typeLayout.structuredComment(labeled: "Layout"), as: nil)
        } else {
            configuration.comment(typeLayout.structuredComment(labeled: "Type Layout"), as: nil)
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
