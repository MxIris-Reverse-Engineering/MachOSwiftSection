import Foundation
import SwiftSyntax
import SwiftSyntaxBuilder
@testable import MachOSwiftSection

/// Emits `__Baseline__/ExtendedExistentialTypeMetadataBaseline.swift`.
///
/// Phase C3: emits ABI literals derived from in-process resolution of
/// `(any Sequence<Int>).self`'s `ExtendedExistentialTypeMetadata`. Kind
/// raw value matches `MetadataKind.extendedExistential` (0x307). The
/// `shape` field is a pointer to the runtime-allocated
/// `ExtendedExistentialTypeShape` for `(any Sequence<Int>)`. The shape
/// pointer's address may carry an in-process tag bit which the runtime
/// strips during resolution; we record the post-strip address here.
///
/// Registered names track the wrapper's directly-declared public surface
/// (`layout`, `offset`); the layout subfields (`kind`, `shape`) are
/// exercised inside the `layout` test body.
@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
package enum ExtendedExistentialTypeMetadataBaselineGenerator {
    package static func generate(outputDirectory: URL) throws {
        let context = InProcessContext()
        let metadata = try ExtendedExistentialTypeMetadata.resolve(
            at: InProcessMetadataPicker.stdlibAnyEquatable,
            in: context
        )
        let kindRaw = metadata.kind.rawValue

        let registered = ["layout", "offset"]

        let header = """
        // AUTO-GENERATED — DO NOT EDIT.
        // Regenerate via: swift package --allow-writing-to-package-directory regen-baselines
        // Source: InProcess `(any Sequence<Int>).self`; no Mach-O section presence.
        //
        // Note: the shape pointer's address is non-deterministic across
        // process invocations (runtime allocates lazily on first access).
        // Tests assert `shape.address != 0` rather than pinning a literal.
        """

        let file: SourceFileSyntax = """
        \(raw: header)

        enum ExtendedExistentialTypeMetadataBaseline {
            static let registeredTestMethodNames: Set<String> = \(literal: registered)

            struct Entry {
                let kindRawValue: UInt32
            }

            static let stdlibAnyEquatable = Entry(
                kindRawValue: \(raw: BaselineEmitter.hex(kindRaw))
            )
        }
        """

        let formatted = file.formatted().description + "\n"
        let outputURL = outputDirectory.appendingPathComponent("ExtendedExistentialTypeMetadataBaseline.swift")
        try formatted.write(to: outputURL, atomically: true, encoding: .utf8)
    }
}
