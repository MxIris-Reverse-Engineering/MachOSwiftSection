import Foundation
import SwiftSyntax
import SwiftSyntaxBuilder

/// Emits `__Baseline__/ClassFlagsBaseline.swift`.
///
/// `ClassFlags` is a `UInt32` option set built by `@FlagSet` from its nested
/// `Flag` enumeration of five cases. It declares no other public properties
/// or methods. The Suite verifies the raw values stay in lockstep with the
/// ABI; the baseline records the expected raw value per flag so any
/// rename/renumber will trip a test.
package enum ClassFlagsBaselineGenerator {
    package static func generate(outputDirectory: URL) throws {
        // Public surface declared in ClassFlags.swift: the structure and its
        // nested `Flag` cases. `@FlagSet` generates `rawValue`, the
        // initializers and one static per case, none of which the
        // source-scanning PublicMemberScanner sees, and it emits no per-case
        // keys — so the registered set is intentionally empty for this Suite.
        let registered: [String] = []

        let header = """
        // AUTO-GENERATED — DO NOT EDIT.
        // Regenerate via: Scripts/regen-baselines.sh
        // Source fixture: SymbolTestsCore.framework
        //
        // ClassFlags is a UInt32 option set with five flags, built by
        // @FlagSet. The Suite (ClassFlagsTests) round-trips the raw values to
        // catch any accidental flag renumbering / renaming.
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
