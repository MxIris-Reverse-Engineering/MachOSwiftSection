import Foundation
import SwiftSyntax
import SwiftSyntaxBuilder
import MachOFoundation
@testable import MachOSwiftSection

/// Emits `__Baseline__/MetadataSourceRecordBaseline.swift`.
///
/// Every metadata source record of the fixture's two-source capture
/// descriptor. Both fields are pinned: the type name side is a bare generic
/// parameter and the source side is the recipe, and both happen to be plain
/// ASCII here — which is exactly what makes them worth showing.
package enum MetadataSourceRecordBaselineGenerator {
    package static func generate(
        in machO: some MachOSwiftSectionRepresentableWithCache,
        outputDirectory: URL
    ) throws {
        let descriptor = try CaptureFixtureDescriptors(in: machO).withMultipleMetadataSources

        let registered = ["layout", "mangledMetadataSource", "mangledTypeName", "offset"]

        let header = """
        // AUTO-GENERATED — DO NOT EDIT.
        // Regenerate via: Scripts/regen-baselines.sh
        // Source fixture: SymbolTestsCore.framework
        //
        // Every metadata source record of the fixture's two-source capture
        // descriptor: which type each entry supplies metadata for, and the
        // unparsed recipe for recovering it.
        """

        let entries = try descriptor.metadataSourceRecords(in: machO).map { record -> String in
            let expr: ExprSyntax = """
            Entry(
                offset: \(raw: BaselineEmitter.hex(record.offset)),
                mangledTypeName: \(literal: try record.mangledTypeName(in: machO).rawString),
                mangledMetadataSource: \(literal: try record.mangledMetadataSource(in: machO).rawString)
            )
            """
            return expr.description
        }

        let file: SourceFileSyntax = """
        \(raw: header)

        enum MetadataSourceRecordBaseline {
            static let registeredTestMethodNames: Set<String> = \(literal: registered)

            struct Entry {
                let offset: Int
                let mangledTypeName: String
                let mangledMetadataSource: String
            }

            static let records: [Entry] = [
                \(raw: entries.joined(separator: ",\n    ")),
            ]
        }
        """

        let formatted = file.formatted().description + "\n"
        let outputURL = outputDirectory.appendingPathComponent("MetadataSourceRecordBaseline.swift")
        try formatted.write(to: outputURL, atomically: true, encoding: .utf8)
    }
}
