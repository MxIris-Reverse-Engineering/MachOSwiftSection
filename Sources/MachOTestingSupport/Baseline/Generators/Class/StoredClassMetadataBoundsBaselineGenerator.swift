import Foundation
import SwiftSyntax
import SwiftSyntaxBuilder

/// Emits `__Baseline__/StoredClassMetadataBoundsBaseline.swift`.
///
/// `StoredClassMetadataBounds` is a small wrapper carrying the bounds for
/// a class that has a resilient superclass — it's pointed at by
/// `ClassDescriptor.metadataNegativeSizeInWordsOrResilientMetadataBounds`.
/// The fixture's resilient-superclass class exercises the lookup. The
/// baseline records only the registered member names.
package enum StoredClassMetadataBoundsBaselineGenerator {
    package static func generate(outputDirectory: URL) throws {
        // Public members declared directly in StoredClassMetadataBounds.swift.
        // `init(layout:offset:)` is filtered as memberwise-synthesized.
        let registered = [
            "layout",
            "offset",
        ]

        let header = """
        // AUTO-GENERATED — DO NOT EDIT.
        // Regenerate via: Scripts/regen-baselines.sh
        // Source fixture: SymbolTestsCore.framework
        //
        // StoredClassMetadataBounds is reachable via
        // ClassDescriptor.resilientMetadataBounds(...). The Suite picks a
        // resilient-superclass class and asserts cross-reader agreement
        // on the resolved bounds offset.
        """

        let file: SourceFileSyntax = """
        \(raw: header)

        enum StoredClassMetadataBoundsBaseline {
            static let registeredTestMethodNames: Set<String> = \(literal: registered)
        }
        """

        let formatted = file.formatted().description + "\n"
        let outputURL = outputDirectory.appendingPathComponent("StoredClassMetadataBoundsBaseline.swift")
        try formatted.write(to: outputURL, atomically: true, encoding: .utf8)
    }
}
