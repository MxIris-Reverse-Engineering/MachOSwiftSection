import Foundation
import SwiftSyntax
import SwiftSyntaxBuilder

/// Emits `__Baseline__/ClassMetadataBoundsProtocolBaseline.swift`.
///
/// The protocol declares one instance method (`adjustForSubclass`) and
/// two static factory methods (`forAddressPointAndSize`,
/// `forSwiftRootClass`). The Suite exercises them by constructing a
/// known starting bounds value, applying a subclass adjustment, and
/// asserting the post-adjustment scalars.
package enum ClassMetadataBoundsProtocolBaselineGenerator {
    package static func generate(outputDirectory: URL) throws {
        // Public members declared directly in ClassMetadataBoundsProtocol.swift.
        let registered = [
            "adjustForSubclass",
            "forAddressPointAndSize",
            "forSwiftRootClass",
        ]

        let header = """
        // AUTO-GENERATED — DO NOT EDIT.
        // Regenerate via: Scripts/regen-baselines.sh
        // Source fixture: SymbolTestsCore.framework
        //
        // ClassMetadataBoundsProtocol's methods are pure value-type
        // computations; the Suite exercises them with constructed inputs.
        """

        let file: SourceFileSyntax = """
        \(raw: header)

        enum ClassMetadataBoundsProtocolBaseline {
            static let registeredTestMethodNames: Set<String> = \(literal: registered)
        }
        """

        let formatted = file.formatted().description + "\n"
        let outputURL = outputDirectory.appendingPathComponent("ClassMetadataBoundsProtocolBaseline.swift")
        try formatted.write(to: outputURL, atomically: true, encoding: .utf8)
    }
}
