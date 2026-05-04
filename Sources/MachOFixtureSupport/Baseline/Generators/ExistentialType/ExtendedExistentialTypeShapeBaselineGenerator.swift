import Foundation
import SwiftSyntax
import SwiftSyntaxBuilder
@testable import MachOSwiftSection

/// Emits `__Baseline__/ExtendedExistentialTypeShapeBaseline.swift`.
///
/// Phase C3: emits ABI literals derived from in-process resolution of
/// the shape pointer of `(any Sequence<Int>).self`'s
/// `ExtendedExistentialTypeMetadata`. The shape's `flags` raw value
/// encodes the special-kind / has-generalization / has-type-expression /
/// has-suggested-witnesses / has-implicit-generic-params bits. Its
/// `requirementSignatureHeader` carries `numParams`/`numRequirements` for
/// the parameterized protocol (Sequence has primary associated type
/// Element, which contributes one parameter and a same-type requirement
/// fixing it to `Int`).
///
/// Registered names track the wrapper's directly-declared public surface
/// (`existentialType`, `layout`, `offset`); the layout subfields (`flags`,
/// `requirementSignatureHeader`) are exercised inside the `layout` test
/// body. The shape's runtime address is non-deterministic so `offset` is
/// asserted only as non-zero.
@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
package enum ExtendedExistentialTypeShapeBaselineGenerator {
    package static func generate(outputDirectory: URL) throws {
        let context = InProcessContext()
        let metadata = try ExtendedExistentialTypeMetadata.resolve(
            at: InProcessMetadataPicker.stdlibAnyEquatable,
            in: context
        )
        let shape = try metadata.layout.shape.resolve(in: context)
        let flagsRaw = shape.layout.flags.rawValue
        let numParams = shape.layout.requirementSignatureHeader.numParams

        let registered = [
            "existentialType",
            "layout",
            "offset",
        ]

        let header = """
        // AUTO-GENERATED — DO NOT EDIT.
        // Regenerate via: swift package --allow-writing-to-package-directory regen-baselines
        // Source: InProcess shape of `(any Sequence<Int>).self`; no Mach-O section presence.
        """

        let file: SourceFileSyntax = """
        \(raw: header)

        enum ExtendedExistentialTypeShapeBaseline {
            static let registeredTestMethodNames: Set<String> = \(literal: registered)

            struct Entry {
                let flagsRawValue: UInt32
                let requirementSignatureNumParams: UInt16
            }

            static let equatableShape = Entry(
                flagsRawValue: \(raw: BaselineEmitter.hex(flagsRaw)),
                requirementSignatureNumParams: \(raw: BaselineEmitter.hex(numParams))
            )
        }
        """

        let formatted = file.formatted().description + "\n"
        let outputURL = outputDirectory.appendingPathComponent("ExtendedExistentialTypeShapeBaseline.swift")
        try formatted.write(to: outputURL, atomically: true, encoding: .utf8)
    }
}
