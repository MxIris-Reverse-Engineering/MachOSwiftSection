import Foundation
import SwiftSyntax
import SwiftSyntaxBuilder
import MachOFoundation
@testable import MachOSwiftSection

/// Emits `__Baseline__/AnonymousContextDescriptorFlagsBaseline.swift`.
///
/// `AnonymousContextDescriptorFlags` is a small `FlagSet` value type whose
/// `rawValue` (`UInt16`) lives in the descriptor's `layout.flags`
/// kind-specific bit-range. We extract it by interrogating the fixture's
/// first anonymous descriptor and embed the raw value plus the derived
/// `hasMangledName` boolean.
package enum AnonymousContextDescriptorFlagsBaselineGenerator {
    package static func generate(
        in machO: some MachOSwiftSectionRepresentableWithCache,
        outputDirectory: URL
    ) throws {
        let descriptor = try BaselineFixturePicker.anonymous_first(in: machO)
        let flags = try required(descriptor.layout.flags.kindSpecificFlags?.anonymousFlags)

        let entryExpr = emitEntryExpr(for: flags)

        // Public members declared directly in AnonymousContextDescriptorFlags.swift.
        let registered = [
            "hasMangledName",
            "init(rawValue:)",
            "rawValue",
        ]

        let header = """
        // AUTO-GENERATED — DO NOT EDIT.
        // Regenerate via: Scripts/regen-baselines.sh
        // Source fixture: SymbolTestsCore.framework
        """

        let file: SourceFileSyntax = """
        \(raw: header)

        enum AnonymousContextDescriptorFlagsBaseline {
            static let registeredTestMethodNames: Set<String> = \(literal: registered)

            struct Entry {
                let rawValue: UInt16
                let hasMangledName: Bool
            }

            static let firstAnonymous = \(raw: entryExpr)
        }
        """

        let formatted = file.formatted().description + "\n"
        let outputURL = outputDirectory.appendingPathComponent("AnonymousContextDescriptorFlagsBaseline.swift")
        try formatted.write(to: outputURL, atomically: true, encoding: .utf8)
    }

    private static func emitEntryExpr(for flags: AnonymousContextDescriptorFlags) -> String {
        let rawValue = flags.rawValue
        let hasMangledName = flags.hasMangledName

        let expr: ExprSyntax = """
        Entry(
            rawValue: \(raw: BaselineEmitter.hex(rawValue)),
            hasMangledName: \(literal: hasMangledName)
        )
        """
        return expr.description
    }
}
