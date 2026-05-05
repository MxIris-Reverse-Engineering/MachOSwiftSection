import Foundation
import SwiftSyntax
import SwiftSyntaxBuilder
@testable import MachOSwiftSection

/// Emits `__Baseline__/TupleTypeMetadataBaseline.swift`.
///
/// Phase C2: emits ABI literals derived from in-process resolution of
/// `(Int, String).self`'s `TupleTypeMetadata`.
///
/// Registered names track the wrapper's directly-declared public surface
/// (`layout`, `offset`, `elements`); the layout subfields (`kind`,
/// `numberOfElements`, `labels`) are exercised inside the `layout` test
/// body.
package enum TupleTypeMetadataBaselineGenerator {
    package static func generate(outputDirectory: URL) throws {
        let pointer = InProcessMetadataPicker.stdlibTupleIntString
        let context = InProcessContext()
        let metadata = try TupleTypeMetadata.resolve(at: pointer, in: context)
        let kindRaw = metadata.kind.rawValue
        let count = metadata.layout.numberOfElements
        let labelsAddress = metadata.layout.labels.address

        let registered = ["elements", "layout", "offset"]

        let header = """
        // AUTO-GENERATED — DO NOT EDIT.
        // Regenerate via: swift package --allow-writing-to-package-directory regen-baselines
        // Source: InProcess (stdlib `(Int, String).self`); no Mach-O section presence.
        """

        let file: SourceFileSyntax = """
        \(raw: header)

        enum TupleTypeMetadataBaseline {
            static let registeredTestMethodNames: Set<String> = \(literal: registered)

            struct Entry {
                let kindRawValue: UInt32
                let numberOfElements: UInt64
                let labelsAddress: UInt64
            }

            static let stdlibTupleIntString = Entry(
                kindRawValue: \(raw: BaselineEmitter.hex(kindRaw)),
                numberOfElements: \(raw: BaselineEmitter.hex(count)),
                labelsAddress: \(raw: BaselineEmitter.hex(labelsAddress))
            )
        }
        """

        let formatted = file.formatted().description + "\n"
        let outputURL = outputDirectory.appendingPathComponent("TupleTypeMetadataBaseline.swift")
        try formatted.write(to: outputURL, atomically: true, encoding: .utf8)
    }
}
