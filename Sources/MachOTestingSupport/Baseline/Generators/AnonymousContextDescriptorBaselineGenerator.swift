import Foundation
import SwiftSyntax
import SwiftSyntaxBuilder
import MachOFoundation
@testable import MachOSwiftSection

/// Emits `__Baseline__/AnonymousContextDescriptorBaseline.swift` from the
/// `SymbolTestsCore` fixture via the MachOFile reader.
///
/// `AnonymousContextDescriptor` declares only the `offset` and `layout`
/// ivars (the `init(layout:offset:)` is filtered as a memberwise
/// synthesized initializer). The `Layout` is `flags + parent`; the
/// `flags.rawValue` (a `UInt32`) is a stable scalar we can embed.
package enum AnonymousContextDescriptorBaselineGenerator {
    package static func generate(
        in machO: some MachOSwiftSectionRepresentableWithCache,
        outputDirectory: URL
    ) throws {
        let descriptor = try BaselineFixturePicker.anonymous_first(in: machO)
        let entryExpr = emitEntryExpr(for: descriptor)

        let registered = ["layout", "offset"]

        let header = """
        // AUTO-GENERATED — DO NOT EDIT.
        // Regenerate via: Scripts/regen-baselines.sh
        // Source fixture: SymbolTestsCore.framework
        """

        let file: SourceFileSyntax = """
        \(raw: header)

        enum AnonymousContextDescriptorBaseline {
            static let registeredTestMethodNames: Set<String> = \(literal: registered)

            struct Entry {
                let offset: Int
                let layoutFlagsRawValue: UInt32
            }

            static let firstAnonymous = \(raw: entryExpr)
        }
        """

        let formatted = file.formatted().description + "\n"
        let outputURL = outputDirectory.appendingPathComponent("AnonymousContextDescriptorBaseline.swift")
        try formatted.write(to: outputURL, atomically: true, encoding: .utf8)
    }

    private static func emitEntryExpr(for descriptor: AnonymousContextDescriptor) -> String {
        let offset = descriptor.offset
        let flagsRaw = descriptor.layout.flags.rawValue

        let expr: ExprSyntax = """
        Entry(
            offset: \(raw: BaselineEmitter.hex(offset)),
            layoutFlagsRawValue: \(raw: BaselineEmitter.hex(flagsRaw))
        )
        """
        return expr.description
    }
}
