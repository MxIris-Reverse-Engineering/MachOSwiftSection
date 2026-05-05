import Foundation
import SwiftSyntax
import SwiftSyntaxBuilder
@testable import MachOSwiftSection

/// Emits `__Baseline__/MetatypeMetadataBaseline.swift`.
///
/// Phase C2: emits ABI literals derived from in-process resolution of
/// `type(of: Int.self)`'s `MetatypeMetadata`. The kind raw value matches
/// `MetadataKind.metatype` (0x304); `instanceType` points to `Int.self`'s
/// metadata (a struct kind 0x200).
///
/// Registered names track the wrapper's directly-declared public
/// surface (`layout`, `offset`); the layout subfields (`kind`,
/// `instanceType`) are exercised inside the `layout` test body.
package enum MetatypeMetadataBaselineGenerator {
    package static func generate(outputDirectory: URL) throws {
        let pointer = InProcessMetadataPicker.stdlibIntMetatype
        let context = InProcessContext()
        let metatype = try MetatypeMetadata.resolve(at: pointer, in: context)
        let kindRaw = metatype.kind.rawValue

        let registered = ["layout", "offset"]

        let header = """
        // AUTO-GENERATED — DO NOT EDIT.
        // Regenerate via: swift package --allow-writing-to-package-directory regen-baselines
        // Source: InProcess (stdlib `type(of: Int.self)`); no Mach-O section presence.
        """

        let file: SourceFileSyntax = """
        \(raw: header)

        enum MetatypeMetadataBaseline {
            static let registeredTestMethodNames: Set<String> = \(literal: registered)

            struct Entry {
                let kindRawValue: UInt32
            }

            static let stdlibIntMetatype = Entry(
                kindRawValue: \(raw: BaselineEmitter.hex(kindRaw))
            )
        }
        """

        let formatted = file.formatted().description + "\n"
        let outputURL = outputDirectory.appendingPathComponent("MetatypeMetadataBaseline.swift")
        try formatted.write(to: outputURL, atomically: true, encoding: .utf8)
    }
}
