import Foundation
import SwiftSyntax
import SwiftSyntaxBuilder

/// Emits `__Baseline__/MetadataResponseBaseline.swift`.
///
/// `MetadataResponse` is the (`Pointer<MetadataWrapper>`, `MetadataState`)
/// tuple returned by `MetadataAccessorFunction.callAsFunction(...)`. Live
/// instances are reachable only through MachOImage's accessor invocation.
/// The Suite (`MetadataResponseTests`) materialises a response by invoking
/// `Structs.StructTest`'s accessor on the loaded MachOImage and asserts:
///   - `value.resolve(in: machOImage)` returns a non-nil
///     `MetadataWrapper.struct(_:)`.
///   - `state` decodes a known state (`.complete` for blocking
///     `MetadataRequest()` calls).
///
/// `init(value:state:)` is internal-scoped on the source side; the only
/// public members the scanner sees are `value` and `state`.
package enum MetadataResponseBaselineGenerator {
    package static func generate(outputDirectory: URL) throws {
        let registered = [
            "state",
            "value",
        ]

        let header = """
        // AUTO-GENERATED — DO NOT EDIT.
        // Regenerate via: Scripts/regen-baselines.sh
        // Source fixture: SymbolTestsCore.framework
        //
        // MetadataResponse is materialised solely through MachOImage's
        // accessor invocation; the Suite verifies the public projections at
        // runtime against this name-only baseline.
        """

        let file: SourceFileSyntax = """
        \(raw: header)

        enum MetadataResponseBaseline {
            static let registeredTestMethodNames: Set<String> = \(literal: registered)
        }
        """

        let formatted = file.formatted().description + "\n"
        let outputURL = outputDirectory.appendingPathComponent("MetadataResponseBaseline.swift")
        try formatted.write(to: outputURL, atomically: true, encoding: .utf8)
    }
}
