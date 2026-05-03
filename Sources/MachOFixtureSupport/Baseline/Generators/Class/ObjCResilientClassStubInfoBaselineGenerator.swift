import Foundation
import SwiftSyntax
import SwiftSyntaxBuilder

/// Emits `__Baseline__/ObjCResilientClassStubInfoBaseline.swift`.
///
/// `ObjCResilientClassStubInfo` is the trailing-object payload that holds
/// a `RelativeDirectRawPointer` to the resilient class stub. It only
/// appears when a class has `hasObjCResilientClassStub == true`. The
/// `SymbolTestsCore` fixture's classes don't surface a resilient ObjC
/// stub, so the baseline records only the registered member names.
package enum ObjCResilientClassStubInfoBaselineGenerator {
    package static func generate(outputDirectory: URL) throws {
        // Public members declared directly in ObjCResilientClassStubInfo.swift.
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
        // ObjCResilientClassStubInfo is only present when a class has
        // hasObjCResilientClassStub == true; the SymbolTestsCore fixture
        // does not declare such a class, so the Suite documents the
        // missing runtime coverage.
        """

        let file: SourceFileSyntax = """
        \(raw: header)

        enum ObjCResilientClassStubInfoBaseline {
            static let registeredTestMethodNames: Set<String> = \(literal: registered)
        }
        """

        let formatted = file.formatted().description + "\n"
        let outputURL = outputDirectory.appendingPathComponent("ObjCResilientClassStubInfoBaseline.swift")
        try formatted.write(to: outputURL, atomically: true, encoding: .utf8)
    }
}
