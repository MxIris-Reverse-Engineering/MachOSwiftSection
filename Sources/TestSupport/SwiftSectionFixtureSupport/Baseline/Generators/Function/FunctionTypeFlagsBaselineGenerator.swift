import Foundation
import SwiftSyntax
import SwiftSyntaxBuilder
@testable import MachOSwiftSection

/// Emits `__Baseline__/FunctionTypeFlagsBaseline.swift`.
///
/// Phase C2: emits the runtime-anchored `numberOfParameters` literal
/// derived from in-process resolution of `((Int) -> Void).self`'s
/// `FunctionTypeMetadata.layout.flags`. Other `FunctionTypeFlags`
/// accessors (`rawValue`, `convention`, `isThrowing`, etc.) are pure
/// raw-value bit decoders and remain tracked via the sentinel
/// allowlist (`pureDataUtilityEntries`).
package enum FunctionTypeFlagsBaselineGenerator {
    package static func generate(outputDirectory: URL) throws {
        let pointer = InProcessMetadataPicker.stdlibFunctionIntToVoid
        let context = InProcessContext()
        let metadata = try FunctionTypeMetadata.resolve(at: pointer, in: context)
        let numberOfParameters = metadata.layout.flags.numberOfParameters

        let registered = ["numberOfParameters"]

        let header = """
        // AUTO-GENERATED — DO NOT EDIT.
        // Regenerate via: swift package --allow-writing-to-package-directory regen-baselines
        // Source: InProcess `((Int) -> Void).self` flags slice.
        """

        let file: SourceFileSyntax = """
        \(raw: header)

        enum FunctionTypeFlagsBaseline {
            static let registeredTestMethodNames: Set<String> = \(literal: registered)

            struct Entry {
                let numberOfParameters: UInt64
            }

            static let stdlibFunctionIntToVoid = Entry(
                numberOfParameters: \(raw: BaselineEmitter.hex(numberOfParameters))
            )
        }
        """

        let formatted = file.formatted().description + "\n"
        let outputURL = outputDirectory.appendingPathComponent("FunctionTypeFlagsBaseline.swift")
        try formatted.write(to: outputURL, atomically: true, encoding: .utf8)
    }
}
