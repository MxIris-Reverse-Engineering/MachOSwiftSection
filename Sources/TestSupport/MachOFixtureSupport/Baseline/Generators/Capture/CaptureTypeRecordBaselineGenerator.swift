import Foundation
import SwiftSyntax
import SwiftSyntaxBuilder
import MachOFoundation
@testable import MachOSwiftSection

/// Emits `__Baseline__/CaptureTypeRecordBaseline.swift`.
///
/// The first captured type of each of the three fixture capture descriptors.
/// The mangled names carry symbolic references, so only their offsets and
/// presence are pinned; the Suite checks the payload resolves consistently
/// across readers.
package enum CaptureTypeRecordBaselineGenerator {
    package static func generate(
        in machO: some MachOSwiftSectionRepresentableWithCache,
        outputDirectory: URL
    ) throws {
        let descriptors = try CaptureFixtureDescriptors(in: machO)

        let registered = ["layout", "mangledTypeName", "offset"]

        let header = """
        // AUTO-GENERATED — DO NOT EDIT.
        // Regenerate via: Scripts/regen-baselines.sh
        // Source fixture: SymbolTestsCore.framework
        //
        // The first capture type record of each fixture capture descriptor.
        // Live MangledName payloads aren't embedded as literals (they carry
        // symbolic references); the Suite verifies they resolve
        // cross-reader-consistently against the presence flag recorded here.
        """

        let entries = try descriptors.all.map { descriptor -> String in
            let record = try descriptor.captureTypeRecords(in: machO)[0]
            let expr: ExprSyntax = """
            Entry(
                offset: \(raw: BaselineEmitter.hex(record.offset)),
                hasMangledTypeName: \(literal: !(try record.mangledTypeName(in: machO).isEmpty))
            )
            """
            return expr.description
        }

        let file: SourceFileSyntax = """
        \(raw: header)

        enum CaptureTypeRecordBaseline {
            static let registeredTestMethodNames: Set<String> = \(literal: registered)

            struct Entry {
                let offset: Int
                let hasMangledTypeName: Bool
            }

            static let firstRecords: [Entry] = [
                \(raw: entries.joined(separator: ",\n    ")),
            ]
        }
        """

        let formatted = file.formatted().description + "\n"
        let outputURL = outputDirectory.appendingPathComponent("CaptureTypeRecordBaseline.swift")
        try formatted.write(to: outputURL, atomically: true, encoding: .utf8)
    }
}
