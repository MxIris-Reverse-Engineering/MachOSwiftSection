import Foundation
import SwiftSyntax
import SwiftSyntaxBuilder

/// Emits `__Baseline__/ObjCClassWrapperMetadataBaseline.swift`.
///
/// `ObjCClassWrapperMetadata` is a small wrapper carrying the kind and a
/// `ConstMetadataPointer<ClassMetadataObjCInterop>`. It's only reachable
/// at runtime from a loaded MachOImage (Swift refers to ObjC classes via
/// this wrapper). The baseline records only the registered member names.
package enum ObjCClassWrapperMetadataBaselineGenerator {
    package static func generate(outputDirectory: URL) throws {
        // Public members declared directly in ObjCClassWrapperMetadata.swift.
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
        // ObjCClassWrapperMetadata is reachable from a loaded MachOImage;
        // live values are not embedded as literals.
        """

        let file: SourceFileSyntax = """
        \(raw: header)

        enum ObjCClassWrapperMetadataBaseline {
            static let registeredTestMethodNames: Set<String> = \(literal: registered)
        }
        """

        let formatted = file.formatted().description + "\n"
        let outputURL = outputDirectory.appendingPathComponent("ObjCClassWrapperMetadataBaseline.swift")
        try formatted.write(to: outputURL, atomically: true, encoding: .utf8)
    }
}
