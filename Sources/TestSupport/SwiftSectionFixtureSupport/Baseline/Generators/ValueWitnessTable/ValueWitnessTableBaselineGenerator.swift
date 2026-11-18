import Foundation
import SwiftSyntax
import SwiftSyntaxBuilder

/// Emits `__Baseline__/ValueWitnessTableBaseline.swift`.
///
/// `ValueWitnessTable` is the runtime-allocated table of value-witness
/// function pointers (initializeBufferWithCopyOfBuffer / destroy /
/// assignWithCopy / etc.) plus the type-layout metadata (size /
/// stride / flags / extraInhabitants). It's reachable only via
/// `MetadataProtocol.valueWitnesses(in:)` from a loaded MachOImage —
/// the function pointers live in the runtime image. The Suite
/// materialises the value-witness table for `Structs.StructTest` and
/// asserts cross-reader equality on the structural fields (size /
/// stride / flags raw / numExtraInhabitants); the function pointers
/// themselves vary per process and aren't compared literally.
///
/// `init(layout:offset:)` is filtered as memberwise-synthesized.
package enum ValueWitnessTableBaselineGenerator {
    package static func generate(outputDirectory: URL) throws {
        let registered = [
            "layout",
            "offset",
            "typeLayout",
        ]

        let header = """
        // AUTO-GENERATED — DO NOT EDIT.
        // Regenerate via: Scripts/regen-baselines.sh
        // Source fixture: SymbolTestsCore.framework
        //
        // ValueWitnessTable is reachable solely through
        // `MetadataProtocol.valueWitnesses(in:)` from a loaded
        // MachOImage — the function pointers live in the runtime image.
        // The Suite materialises the table for Structs.StructTest and
        // asserts cross-reader equality on the size / stride / flags /
        // numExtraInhabitants ivars; per-process function pointers are
        // not compared literally.
        //
        // `init(layout:offset:)` is filtered as memberwise-synthesized.
        """

        let file: SourceFileSyntax = """
        \(raw: header)

        enum ValueWitnessTableBaseline {
            static let registeredTestMethodNames: Set<String> = \(literal: registered)
        }
        """

        let formatted = file.formatted().description + "\n"
        let outputURL = outputDirectory.appendingPathComponent("ValueWitnessTableBaseline.swift")
        try formatted.write(to: outputURL, atomically: true, encoding: .utf8)
    }
}
