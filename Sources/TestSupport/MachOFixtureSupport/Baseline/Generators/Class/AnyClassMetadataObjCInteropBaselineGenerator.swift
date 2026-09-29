import Foundation
import SwiftSyntax
import SwiftSyntaxBuilder

/// Emits `__Baseline__/AnyClassMetadataObjCInteropBaseline.swift`.
///
/// `AnyClassMetadataObjCInterop` is the parallel structure to
/// `AnyClassMetadata` for ObjC-interop classes (carrying the cache /
/// vtable / data words). Live materialisation requires a loaded
/// MachOImage; this baseline records only the registered member names.
package enum AnyClassMetadataObjCInteropBaselineGenerator {
    package static func generate(outputDirectory: URL) throws {
        // Public members declared directly in AnyClassMetadataObjCInterop.swift.
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
        // AnyClassMetadataObjCInterop must be materialised from a loaded
        // MachOImage; live values are not embedded.
        """

        let file: SourceFileSyntax = """
        \(raw: header)

        enum AnyClassMetadataObjCInteropBaseline {
            static let registeredTestMethodNames: Set<String> = \(literal: registered)
        }
        """

        let formatted = file.formatted().description + "\n"
        let outputURL = outputDirectory.appendingPathComponent("AnyClassMetadataObjCInteropBaseline.swift")
        try formatted.write(to: outputURL, atomically: true, encoding: .utf8)
    }
}
