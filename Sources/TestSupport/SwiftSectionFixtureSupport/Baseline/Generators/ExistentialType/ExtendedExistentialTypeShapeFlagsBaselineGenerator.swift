import Foundation
import SwiftSyntax
import SwiftSyntaxBuilder
@testable import MachOSwiftSection

/// Emits `__Baseline__/ExtendedExistentialTypeShapeFlagsBaseline.swift`.
///
/// Phase C3: emits ABI literals derived from in-process resolution of the
/// shape flags of `(any Sequence<Int>).self`. Currently `OptionSet`
/// boilerplate (`init(rawValue:)` and `rawValue`); the test round-trips
/// through both. The raw value reflects the special-kind /
/// has-generalization-signature / has-type-expression /
/// has-suggested-witnesses / has-implicit-generic-params bits set by
/// the runtime for `(any Sequence<Int>)`.
@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
package enum ExtendedExistentialTypeShapeFlagsBaselineGenerator {
    package static func generate(outputDirectory: URL) throws {
        let context = InProcessContext()
        let metadata = try ExtendedExistentialTypeMetadata.resolve(
            at: InProcessMetadataPicker.stdlibAnyEquatable,
            in: context
        )
        let shape = try metadata.layout.shape.resolve(in: context)
        let rawValue = shape.layout.flags.rawValue

        let registered = [
            "init(rawValue:)",
            "rawValue",
        ]

        let header = """
        // AUTO-GENERATED — DO NOT EDIT.
        // Regenerate via: swift package --allow-writing-to-package-directory regen-baselines
        // Source: InProcess shape of `(any Sequence<Int>).self`; no Mach-O section presence.
        """

        let file: SourceFileSyntax = """
        \(raw: header)

        enum ExtendedExistentialTypeShapeFlagsBaseline {
            static let registeredTestMethodNames: Set<String> = \(literal: registered)

            struct Entry {
                let rawValue: UInt32
            }

            static let equatableShape = Entry(
                rawValue: \(raw: BaselineEmitter.hex(rawValue))
            )
        }
        """

        let formatted = file.formatted().description + "\n"
        let outputURL = outputDirectory.appendingPathComponent("ExtendedExistentialTypeShapeFlagsBaseline.swift")
        try formatted.write(to: outputURL, atomically: true, encoding: .utf8)
    }
}
