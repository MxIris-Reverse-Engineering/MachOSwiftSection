import Foundation
import SwiftSyntax
import SwiftSyntaxBuilder
import MachOFoundation
@testable import MachOSwiftSection

/// Emits `__Baseline__/ModuleContextBaseline.swift` from the
/// `SymbolTestsCore` fixture via the MachOFile reader.
///
/// `ModuleContext` is the high-level wrapper around a
/// `ModuleContextDescriptor`. Its only ivars are `descriptor` and `name`.
/// We embed both: `name` as a string literal and `descriptor.offset` as
/// a hex value.
package enum ModuleContextBaselineGenerator {
    package static func generate(
        in machO: some MachOSwiftSectionRepresentableWithCache,
        outputDirectory: URL
    ) throws {
        let descriptor = try BaselineFixturePicker.module_SymbolTestsCore(in: machO)
        let context = try ModuleContext(descriptor: descriptor, in: machO)

        let entryExpr = emitEntryExpr(for: context)

        // Public members declared directly in ModuleContext.swift.
        // Both `init(descriptor:in:)` overloads (MachO + ReadingContext)
        // collapse to a single MethodKey under PublicMemberScanner's
        // name-based deduplication.
        let registered = [
            "descriptor",
            "init(descriptor:)",
            "init(descriptor:in:)",
            "name",
        ]

        let header = """
        // AUTO-GENERATED — DO NOT EDIT.
        // Regenerate via: Scripts/regen-baselines.sh
        // Source fixture: SymbolTestsCore.framework
        """

        let file: SourceFileSyntax = """
        \(raw: header)

        enum ModuleContextBaseline {
            static let registeredTestMethodNames: Set<String> = \(literal: registered)

            struct Entry {
                let descriptorOffset: Int
                let name: String
            }

            static let symbolTestsCore = \(raw: entryExpr)
        }
        """

        let formatted = file.formatted().description + "\n"
        let outputURL = outputDirectory.appendingPathComponent("ModuleContextBaseline.swift")
        try formatted.write(to: outputURL, atomically: true, encoding: .utf8)
    }

    private static func emitEntryExpr(for instance: ModuleContext) -> String {
        let descriptorOffset = instance.descriptor.offset
        let name = instance.name

        let expr: ExprSyntax = """
        Entry(
            descriptorOffset: \(raw: BaselineEmitter.hex(descriptorOffset)),
            name: \(literal: name)
        )
        """
        return expr.description
    }
}
