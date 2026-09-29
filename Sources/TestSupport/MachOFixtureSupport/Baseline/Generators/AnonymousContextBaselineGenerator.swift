import Foundation
import SwiftSyntax
import SwiftSyntaxBuilder
import MachOFoundation
@testable import MachOSwiftSection

/// Emits `__Baseline__/AnonymousContextBaseline.swift` from the
/// `SymbolTestsCore` fixture via the MachOFile reader.
///
/// `AnonymousContext` wraps an `AnonymousContextDescriptor` and pulls in the
/// optional `genericContext` and `mangledName` ivars. We use the
/// presence-flag pattern (no value embedding) for the optionals because
/// `MangledName`/`GenericContext` are deep ABI structures that are hostile
/// to literal embedding; cross-reader equality assertions in the companion
/// Suite cover correctness at runtime.
package enum AnonymousContextBaselineGenerator {
    package static func generate(
        in machO: some MachOSwiftSectionRepresentableWithCache,
        outputDirectory: URL
    ) throws {
        let descriptor = try BaselineFixturePicker.anonymous_first(in: machO)
        let context = try AnonymousContext(descriptor: descriptor, in: machO)

        let entryExpr = emitEntryExpr(for: context)

        // Public members declared directly in AnonymousContext.swift.
        // Both `init(descriptor:in:)` overloads (MachO + ReadingContext)
        // collapse to one MethodKey under PublicMemberScanner's name-based
        // deduplication.
        let registered = [
            "descriptor",
            "genericContext",
            "init(descriptor:)",
            "init(descriptor:in:)",
            "mangledName",
        ]

        let header = """
        // AUTO-GENERATED — DO NOT EDIT.
        // Regenerate via: Scripts/regen-baselines.sh
        // Source fixture: SymbolTestsCore.framework
        """

        let file: SourceFileSyntax = """
        \(raw: header)

        enum AnonymousContextBaseline {
            static let registeredTestMethodNames: Set<String> = \(literal: registered)

            struct Entry {
                let descriptorOffset: Int
                let hasGenericContext: Bool
                let hasMangledName: Bool
            }

            static let firstAnonymous = \(raw: entryExpr)
        }
        """

        let formatted = file.formatted().description + "\n"
        let outputURL = outputDirectory.appendingPathComponent("AnonymousContextBaseline.swift")
        try formatted.write(to: outputURL, atomically: true, encoding: .utf8)
    }

    private static func emitEntryExpr(for instance: AnonymousContext) -> String {
        let descriptorOffset = instance.descriptor.offset
        let hasGenericContext = instance.genericContext != nil
        let hasMangledName = instance.mangledName != nil

        let expr: ExprSyntax = """
        Entry(
            descriptorOffset: \(raw: BaselineEmitter.hex(descriptorOffset)),
            hasGenericContext: \(literal: hasGenericContext),
            hasMangledName: \(literal: hasMangledName)
        )
        """
        return expr.description
    }
}
