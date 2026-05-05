import Foundation
import SwiftSyntax
import SwiftSyntaxBuilder

/// Emits `__Baseline__/StoredClassMetadataBoundsBaseline.swift`.
///
/// Phase B2: `StoredClassMetadataBounds` is exercised as a real
/// InProcess wrapper. The Suite dlsym's the nominal type descriptor of
/// `ResilientClassFixtures.ResilientChild`, materialises the
/// `ClassDescriptor`, then chases the resilient-metadata-bounds
/// pointer via the InProcess `ReadingContext`. The bounds are
/// runtime-allocated, so their address (`offset`) is ASLR-randomized
/// and the `negativeSizeInWords` / `positiveSizeInWords` shape reflects
/// the resilient root's metadata, which can drift across toolchain
/// versions. The Suite asserts invariants (non-zero offset, sane word
/// counts) rather than pinning literals.
///
/// `init(layout:offset:)` is filtered as memberwise-synthesized.
package enum StoredClassMetadataBoundsBaselineGenerator {
    package static func generate(outputDirectory: URL) throws {
        let registered = [
            "layout",
            "offset",
        ]

        let header = """
        // AUTO-GENERATED — DO NOT EDIT.
        // Regenerate via: swift package --allow-writing-to-package-directory regen-baselines
        // Source fixture: SymbolTestsCore.framework
        //
        // StoredClassMetadataBounds is reachable via
        // ClassDescriptor.resilientMetadataBounds(in:context:). Phase B2
        // converted the Suite to an InProcess-only real test against
        // `ResilientClassFixtures.ResilientChild` (parent
        // `SymbolTestsHelper.ResilientBase`, cross-module). The bounds
        // are runtime-allocated so no ABI literal is pinned — the Suite
        // asserts invariants on the resolved record instead.
        //
        // `init(layout:offset:)` is filtered as memberwise-synthesized.
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
