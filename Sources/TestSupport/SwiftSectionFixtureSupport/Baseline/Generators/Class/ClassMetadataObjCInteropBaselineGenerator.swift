import Foundation
import SwiftSyntax
import SwiftSyntaxBuilder

/// Emits `__Baseline__/ClassMetadataObjCInteropBaseline.swift`.
///
/// `ClassMetadataObjCInterop` is the parallel of `ClassMetadata` for
/// ObjC-interop classes. Same rule: only materialised at runtime via the
/// MachOImage metadata accessor, so this baseline records only the
/// registered member names.
package enum ClassMetadataObjCInteropBaselineGenerator {
    package static func generate(outputDirectory: URL) throws {
        // Public members declared directly in ClassMetadataObjCInterop.swift.
        // `init(layout:offset:)` is filtered as memberwise-synthesized.
        let registered = [
            "descriptorOffset",
            "layout",
            "offset",
        ]

        let header = """
        // AUTO-GENERATED — DO NOT EDIT.
        // Regenerate via: Scripts/regen-baselines.sh
        // Source fixture: SymbolTestsCore.framework
        //
        // ClassMetadataObjCInterop can only be materialised via MachOImage's
        // metadata accessor at runtime; live pointer values are not embedded.
        """

        let file: SourceFileSyntax = """
        \(raw: header)

        enum ClassMetadataObjCInteropBaseline {
            static let registeredTestMethodNames: Set<String> = \(literal: registered)
        }
        """

        let formatted = file.formatted().description + "\n"
        let outputURL = outputDirectory.appendingPathComponent("ClassMetadataObjCInteropBaseline.swift")
        try formatted.write(to: outputURL, atomically: true, encoding: .utf8)
    }
}
