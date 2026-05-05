import Foundation
import SwiftSyntax
import SwiftSyntaxBuilder
@testable import MachOSwiftSection

/// Emits `__Baseline__/FunctionTypeMetadataBaseline.swift`.
///
/// Phase C2: emits ABI literals derived from in-process resolution of
/// `((Int) -> Void).self`'s `FunctionTypeMetadata`.
///
/// Registered names track the wrapper's directly-declared public surface
/// (`layout`, `offset`); the layout subfields (`kind`, `flags`) are
/// exercised inside the `layout` test body.
package enum FunctionTypeMetadataBaselineGenerator {
    package static func generate(outputDirectory: URL) throws {
        let pointer = InProcessMetadataPicker.stdlibFunctionIntToVoid
        let context = InProcessContext()
        let metadata = try FunctionTypeMetadata.resolve(at: pointer, in: context)
        let kindRaw = metadata.kind.rawValue
        let flagsRaw = metadata.layout.flags.rawValue

        let registered = ["layout", "offset"]

        let header = """
        // AUTO-GENERATED — DO NOT EDIT.
        // Regenerate via: swift package --allow-writing-to-package-directory regen-baselines
        // Source: InProcess `((Int) -> Void).self`; no Mach-O section presence.
        """

        let file: SourceFileSyntax = """
        \(raw: header)

        enum FunctionTypeMetadataBaseline {
            static let registeredTestMethodNames: Set<String> = \(literal: registered)

            struct Entry {
                let kindRawValue: UInt32
                let flagsRawValue: UInt64
            }

            static let stdlibFunctionIntToVoid = Entry(
                kindRawValue: \(raw: BaselineEmitter.hex(kindRaw)),
                flagsRawValue: \(raw: BaselineEmitter.hex(flagsRaw))
            )
        }
        """

        let formatted = file.formatted().description + "\n"
        let outputURL = outputDirectory.appendingPathComponent("FunctionTypeMetadataBaseline.swift")
        try formatted.write(to: outputURL, atomically: true, encoding: .utf8)
    }
}
