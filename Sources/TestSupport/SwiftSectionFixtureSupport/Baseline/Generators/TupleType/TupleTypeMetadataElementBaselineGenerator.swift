import Foundation
import SwiftSyntax
import SwiftSyntaxBuilder
@testable import MachOSwiftSection

/// Emits `__Baseline__/TupleTypeMetadataElementBaseline.swift`.
///
/// Phase C2: emits ABI literals derived from in-process resolution of the
/// first `Element` of `(Int, String).self`'s `TupleTypeMetadata`.
package enum TupleTypeMetadataElementBaselineGenerator {
    package static func generate(outputDirectory: URL) throws {
        let pointer = InProcessMetadataPicker.stdlibTupleIntString
        let context = InProcessContext()
        let tuple = try TupleTypeMetadata.resolve(at: pointer, in: context)
        let firstElement = try tuple.elements(in: context).first!
        let elementOffset = firstElement.offset

        let registered = ["offset", "type"]

        let header = """
        // AUTO-GENERATED — DO NOT EDIT.
        // Regenerate via: swift package --allow-writing-to-package-directory regen-baselines
        // Source: InProcess first element of `(Int, String)`; no Mach-O section presence.
        """

        let file: SourceFileSyntax = """
        \(raw: header)

        enum TupleTypeMetadataElementBaseline {
            static let registeredTestMethodNames: Set<String> = \(literal: registered)

            struct Entry {
                let offset: UInt64
            }

            static let firstElementOfIntStringTuple = Entry(
                offset: \(raw: BaselineEmitter.hex(elementOffset))
            )
        }
        """

        let formatted = file.formatted().description + "\n"
        let outputURL = outputDirectory.appendingPathComponent("TupleTypeMetadataElementBaseline.swift")
        try formatted.write(to: outputURL, atomically: true, encoding: .utf8)
    }
}
