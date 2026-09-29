import Foundation
import SwiftSyntax
import SwiftSyntaxBuilder

/// Emits `__Baseline__/ClassFlagsBaseline.swift`.
///
/// `ClassFlags` is a `UInt32` raw enum with five named cases. It does not
/// declare additional public properties or methods. The Suite verifies the
/// raw values stay in lockstep with the ABI; the baseline records the
/// expected raw values per case so any rename/renumber will trip a test.
package enum ClassFlagsBaselineGenerator {
    package static func generate(outputDirectory: URL) throws {
        // Public surface declared in ClassFlags.swift: the enum itself and its
        // raw cases. Cases are tracked here but show up as type members on
        // the enum (PublicMemberScanner emits no per-case keys), so the
        // registered set is intentionally empty for this Suite — the Coverage
        // Invariant test just expects an empty set to mean "no public
        // members other than the cases".
        let registered: [String] = []

        let header = """
        // AUTO-GENERATED — DO NOT EDIT.
        // Regenerate via: Scripts/regen-baselines.sh
        // Source fixture: SymbolTestsCore.framework
        //
        // ClassFlags is a raw UInt32 enum with five named cases. The Suite
        // (ClassFlagsTests) round-trips the raw values to catch any
        // accidental case renumbering / renaming.
        """

        let file: SourceFileSyntax = """
        \(raw: header)

        enum ClassFlagsBaseline {
            static let registeredTestMethodNames: Set<String> = \(literal: registered)

            static let isSwiftPreStableABI: UInt32 = 0x1
            static let usesSwiftRefcounting: UInt32 = 0x2
            static let hasCustomObjCName: UInt32 = 0x4
            static let isStaticSpecialization: UInt32 = 0x8
            static let isCanonicalStaticSpecialization: UInt32 = 0x10
        }
        """

        let formatted = file.formatted().description + "\n"
        let outputURL = outputDirectory.appendingPathComponent("ClassFlagsBaseline.swift")
        try formatted.write(to: outputURL, atomically: true, encoding: .utf8)
    }
}
