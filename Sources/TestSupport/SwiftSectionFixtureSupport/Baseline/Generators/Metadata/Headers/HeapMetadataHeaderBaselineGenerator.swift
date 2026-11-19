import Foundation
import SwiftSyntax
import SwiftSyntaxBuilder

/// Emits `__Baseline__/HeapMetadataHeaderBaseline.swift`.
///
/// `HeapMetadataHeader` is the prefix preceding heap metadata records (the
/// `(layoutString, destroy, valueWitnesses)` triple); the `valueWitnesses`
/// pointer is reachable through `MetadataProtocol.asFullMetadata` for any
/// heap-class metadata. Live header instances are reachable only through
/// MachOImage's accessor invocation, so we emit only the registered member
/// names; the Suite verifies cross-reader equality at runtime.
///
/// `init(layout:offset:)` is filtered as memberwise-synthesized.
package enum HeapMetadataHeaderBaselineGenerator {
    package static func generate(outputDirectory: URL) throws {
        let registered = [
            "layout",
            "offset",
        ]

        let header = """
        // AUTO-GENERATED — DO NOT EDIT.
        // Regenerate via: Scripts/regen-baselines.sh
        // Source fixture: SymbolTestsCore.framework
        //
        // HeapMetadataHeader is materialised from MachOImage's accessor
        // (via FullMetadata header projection); live pointer values are
        // not embedded here.
        """

        let file: SourceFileSyntax = """
        \(raw: header)

        enum HeapMetadataHeaderBaseline {
            static let registeredTestMethodNames: Set<String> = \(literal: registered)
        }
        """

        let formatted = file.formatted().description + "\n"
        let outputURL = outputDirectory.appendingPathComponent("HeapMetadataHeaderBaseline.swift")
        try formatted.write(to: outputURL, atomically: true, encoding: .utf8)
    }
}
