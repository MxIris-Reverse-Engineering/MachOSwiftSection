import Foundation
import SwiftSyntax
import SwiftSyntaxBuilder
@testable import MachOSwiftSection

/// Emits `__Baseline__/ExistentialMetatypeMetadataBaseline.swift`.
///
/// Phase C3: emits ABI literals derived from in-process resolution of
/// `Any.Type.self`'s `ExistentialMetatypeMetadata`. The kind raw value
/// matches `MetadataKind.existentialMetatype` (0x306); `instanceType`
/// points to `Any.self`'s metadata; `flags` mirrors `Any.self`'s
/// existential flags into the metatype layout.
///
/// Registered names track the wrapper's directly-declared public surface
/// (`layout`, `offset`); the layout subfields (`kind`, `instanceType`,
/// `flags`) are exercised inside the `layout` test body.
package enum ExistentialMetatypeMetadataBaselineGenerator {
    package static func generate(outputDirectory: URL) throws {
        let context = InProcessContext()
        let metadata = try ExistentialMetatypeMetadata.resolve(
            at: InProcessMetadataPicker.stdlibAnyMetatype,
            in: context
        )
        let kindRaw = metadata.kind.rawValue
        let flagsRaw = metadata.layout.flags.rawValue

        let registered = ["layout", "offset"]

        let header = """
        // AUTO-GENERATED — DO NOT EDIT.
        // Regenerate via: swift package --allow-writing-to-package-directory regen-baselines
        // Source: InProcess `Any.Type.self`; no Mach-O section presence.
        """

        let file: SourceFileSyntax = """
        \(raw: header)

        enum ExistentialMetatypeMetadataBaseline {
            static let registeredTestMethodNames: Set<String> = \(literal: registered)

            struct Entry {
                let kindRawValue: UInt32
                let flagsRawValue: UInt32
            }

            static let stdlibAnyMetatype = Entry(
                kindRawValue: \(raw: BaselineEmitter.hex(kindRaw)),
                flagsRawValue: \(raw: BaselineEmitter.hex(flagsRaw))
            )
        }
        """

        let formatted = file.formatted().description + "\n"
        let outputURL = outputDirectory.appendingPathComponent("ExistentialMetatypeMetadataBaseline.swift")
        try formatted.write(to: outputURL, atomically: true, encoding: .utf8)
    }
}
