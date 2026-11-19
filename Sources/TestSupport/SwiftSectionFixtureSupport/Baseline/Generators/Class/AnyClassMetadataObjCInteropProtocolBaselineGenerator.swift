import Foundation
import SwiftSyntax
import SwiftSyntaxBuilder

/// Emits `__Baseline__/AnyClassMetadataObjCInteropProtocolBaseline.swift`.
///
/// The protocol's accessors (`asFinalClassMetadata`, `superclass`,
/// `isPureObjC`, `isTypeMetadata`) require a live class metadata
/// instance reachable only from a loaded MachOImage. The baseline
/// records only the registered member names; the Suite asserts
/// cross-reader agreement at runtime.
package enum AnyClassMetadataObjCInteropProtocolBaselineGenerator {
    package static func generate(outputDirectory: URL) throws {
        // Public members declared directly across the
        // AnyClassMetadataObjCInteropProtocol extension blocks. Overload
        // pairs collapse via PublicMemberScanner's name-based key.
        let registered = [
            "asFinalClassMetadata",
            "isPureObjC",
            "isTypeMetadata",
            "superclass",
        ]

        let header = """
        // AUTO-GENERATED — DO NOT EDIT.
        // Regenerate via: Scripts/regen-baselines.sh
        // Source fixture: SymbolTestsCore.framework
        //
        // Live AnyClassMetadataObjCInterop cannot be embedded as a literal;
        // the Suite verifies the methods produce cross-reader-consistent
        // results at runtime.
        """

        let file: SourceFileSyntax = """
        \(raw: header)

        enum AnyClassMetadataObjCInteropProtocolBaseline {
            static let registeredTestMethodNames: Set<String> = \(literal: registered)
        }
        """

        let formatted = file.formatted().description + "\n"
        let outputURL = outputDirectory.appendingPathComponent("AnyClassMetadataObjCInteropProtocolBaseline.swift")
        try formatted.write(to: outputURL, atomically: true, encoding: .utf8)
    }
}
