import Foundation
import SwiftSyntax
import SwiftSyntaxBuilder
import MachOFoundation
@testable import MachOSwiftSection

/// Emits `__Baseline__/ExtraClassDescriptorFlagsBaseline.swift`.
///
/// `ExtraClassDescriptorFlags` is a tiny `FlagSet` over `UInt32`. The flag
/// is only meaningful when a class has a resilient superclass; for the
/// plain `Classes.ClassTest` picker the raw value is zero. We exercise the
/// `init(rawValue:)` round-trip and the derived `hasObjCResilientClassStub`
/// boolean against a fixed raw value of `0x0` to keep the test deterministic.
package enum ExtraClassDescriptorFlagsBaselineGenerator {
    package static func generate(outputDirectory: URL) throws {
        // Public members declared directly in ExtraClassDescriptorFlags.swift.
        let registered = [
            "hasObjCResilientClassStub",
            "init(rawValue:)",
            "rawValue",
        ]

        let header = """
        // AUTO-GENERATED — DO NOT EDIT.
        // Regenerate via: Scripts/regen-baselines.sh
        // Source fixture: SymbolTestsCore.framework
        //
        // ExtraClassDescriptorFlags is a UInt32 FlagSet with a single bit
        // (`hasObjCResilientClassStub`). For the plain ClassTest picker
        // the raw value is zero; we test the flag derivation by
        // round-tripping a known raw value through `init(rawValue:)`.
        """

        let file: SourceFileSyntax = """
        \(raw: header)

        enum ExtraClassDescriptorFlagsBaseline {
            static let registeredTestMethodNames: Set<String> = \(literal: registered)

            // Construct round-trip values: bit 0 set / unset.
            static let zeroRawValue: UInt32 = 0x0
            static let stubBitRawValue: UInt32 = 0x1
        }
        """

        let formatted = file.formatted().description + "\n"
        let outputURL = outputDirectory.appendingPathComponent("ExtraClassDescriptorFlagsBaseline.swift")
        try formatted.write(to: outputURL, atomically: true, encoding: .utf8)
    }
}
