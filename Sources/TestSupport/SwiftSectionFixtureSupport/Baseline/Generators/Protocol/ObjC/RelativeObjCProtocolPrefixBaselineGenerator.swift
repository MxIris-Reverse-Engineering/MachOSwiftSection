import Foundation
import SwiftSyntax
import SwiftSyntaxBuilder
@testable import MachOSwiftSection

/// Emits `__Baseline__/RelativeObjCProtocolPrefixBaseline.swift`.
///
/// `RelativeObjCProtocolPrefix` is the relative-pointer variant of the
/// ObjC protocol prefix used in serialized binary contexts. The
/// `SymbolTestsCore` fixture's ObjC reference uses the absolute-pointer
/// `ObjCProtocolPrefix` form, not the relative variant. The baseline
/// therefore registers the public members for the Coverage Invariant
/// test; the Suite documents the absent runtime coverage.
package enum RelativeObjCProtocolPrefixBaselineGenerator {
    package static func generate(outputDirectory: URL) throws {
        // Public members declared directly in RelativeObjCProtocolPrefix.swift.
        // The two `mangledName(in:)` overloads (MachO + ReadingContext) and
        // the standalone `mangledName()` collapse to a single MethodKey
        // under the scanner's name-based deduplication. `init(layout:offset:)`
        // is filtered as memberwise-synthesized.
        let registered = [
            "layout",
            "mangledName",
            "offset",
        ]

        let header = """
        // AUTO-GENERATED — DO NOT EDIT.
        // Regenerate via: Scripts/regen-baselines.sh
        // Source fixture: SymbolTestsCore.framework
        //
        // The SymbolTestsCore fixture does not surface a
        // RelativeObjCProtocolPrefix payload (the absolute-pointer
        // `ObjCProtocolPrefix` is used for the NSObjectProtocol witness).
        // The Suite documents the missing runtime coverage.
        """

        let file: SourceFileSyntax = """
        \(raw: header)

        enum RelativeObjCProtocolPrefixBaseline {
            static let registeredTestMethodNames: Set<String> = \(literal: registered)
        }
        """

        let formatted = file.formatted().description + "\n"
        let outputURL = outputDirectory.appendingPathComponent("RelativeObjCProtocolPrefixBaseline.swift")
        try formatted.write(to: outputURL, atomically: true, encoding: .utf8)
    }
}
