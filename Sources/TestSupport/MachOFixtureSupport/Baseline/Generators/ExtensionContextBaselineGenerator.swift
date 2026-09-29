import Foundation
import SwiftSyntax
import SwiftSyntaxBuilder
import MachOFoundation
@testable import MachOSwiftSection

/// Emits `__Baseline__/ExtensionContextBaseline.swift` from the
/// `SymbolTestsCore` fixture via the MachOFile reader.
///
/// `ExtensionContext` is the high-level wrapper around an
/// `ExtensionContextDescriptor`. Beyond the descriptor itself, it pulls in
/// `genericContext` and `extendedContextMangledName` (both `Optional`).
/// The optional payloads aren't stable Swift literals, so the `Entry`
/// records only presence flags.
package enum ExtensionContextBaselineGenerator {
    package static func generate(
        in machO: some MachOSwiftSectionRepresentableWithCache,
        outputDirectory: URL
    ) throws {
        let descriptor = try BaselineFixturePicker.extension_first(in: machO)
        let context = try ExtensionContext(descriptor: descriptor, in: machO)

        let entryExpr = emitEntryExpr(for: context)

        // Public members declared directly in ExtensionContext.swift.
        // Both `init(descriptor:in:)` overloads (MachO + ReadingContext)
        // collapse to a single MethodKey under PublicMemberScanner's
        // name-based deduplication.
        let registered = [
            "descriptor",
            "extendedContextMangledName",
            "genericContext",
            "init(descriptor:)",
            "init(descriptor:in:)",
        ]

        let header = """
        // AUTO-GENERATED — DO NOT EDIT.
        // Regenerate via: Scripts/regen-baselines.sh
        // Source fixture: SymbolTestsCore.framework
        """

        let file: SourceFileSyntax = """
        \(raw: header)

        enum ExtensionContextBaseline {
            static let registeredTestMethodNames: Set<String> = \(literal: registered)

            struct Entry {
                let descriptorOffset: Int
                let hasGenericContext: Bool
                let hasExtendedContextMangledName: Bool
            }

            static let firstExtension = \(raw: entryExpr)
        }
        """

        let formatted = file.formatted().description + "\n"
        let outputURL = outputDirectory.appendingPathComponent("ExtensionContextBaseline.swift")
        try formatted.write(to: outputURL, atomically: true, encoding: .utf8)
    }

    private static func emitEntryExpr(for instance: ExtensionContext) -> String {
        let descriptorOffset = instance.descriptor.offset
        let hasGenericContext = instance.genericContext != nil
        let hasExtendedContextMangledName = instance.extendedContextMangledName != nil

        let expr: ExprSyntax = """
        Entry(
            descriptorOffset: \(raw: BaselineEmitter.hex(descriptorOffset)),
            hasGenericContext: \(literal: hasGenericContext),
            hasExtendedContextMangledName: \(literal: hasExtendedContextMangledName)
        )
        """
        return expr.description
    }
}
