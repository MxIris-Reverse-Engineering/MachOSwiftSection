import Foundation
import SwiftSyntax
import SwiftSyntaxBuilder
import MachOFoundation
@testable import MachOSwiftSection

/// Emits `__Baseline__/ContextWrapperBaseline.swift`.
///
/// `ContextWrapper` is the high-level sum type covering all context wrappers
/// (analogous to `ContextDescriptorWrapper` but at the `*Context` level).
/// Members include `context` (the unified projection), the static
/// `forContextDescriptorWrapper(_:in:)` constructor family, and `parent(in:)`.
///
/// Picker: we route `Structs.StructTest`'s descriptor through
/// `ContextWrapper.forContextDescriptorWrapper` to produce a `.type(.struct(...))`
/// wrapper. The `forContextDescriptorWrapper` overloads (MachO + InProcess +
/// ReadingContext) collapse to one MethodKey under PublicMemberScanner's
/// name-only key.
package enum ContextWrapperBaselineGenerator {
    package static func generate(
        in machO: some MachOSwiftSectionRepresentableWithCache,
        outputDirectory: URL
    ) throws {
        let descriptor = try BaselineFixturePicker.struct_StructTest(in: machO)
        let descriptorWrapper = ContextDescriptorWrapper.type(.struct(descriptor))
        let wrapper = try ContextWrapper.forContextDescriptorWrapper(descriptorWrapper, in: machO)
        let entryExpr = try emitEntryExpr(for: wrapper, in: machO)

        let registered = [
            "context",
            "forContextDescriptorWrapper",
            "parent",
        ]

        let header = """
        // AUTO-GENERATED — DO NOT EDIT.
        // Regenerate via: Scripts/regen-baselines.sh
        // Source fixture: SymbolTestsCore.framework
        """

        let file: SourceFileSyntax = """
        \(raw: header)

        enum ContextWrapperBaseline {
            static let registeredTestMethodNames: Set<String> = \(literal: registered)

            struct Entry {
                let descriptorOffset: Int
                let hasParent: Bool
            }

            static let structTest = \(raw: entryExpr)
        }
        """

        let formatted = file.formatted().description + "\n"
        let outputURL = outputDirectory.appendingPathComponent("ContextWrapperBaseline.swift")
        try formatted.write(to: outputURL, atomically: true, encoding: .utf8)
    }

    private static func emitEntryExpr(
        for wrapper: ContextWrapper,
        in machO: some MachOSwiftSectionRepresentableWithCache
    ) throws -> String {
        let descriptorOffset = wrapper.context.descriptor.offset
        let hasParent = (try wrapper.parent(in: machO)) != nil

        let expr: ExprSyntax = """
        Entry(
            descriptorOffset: \(raw: BaselineEmitter.hex(descriptorOffset)),
            hasParent: \(literal: hasParent)
        )
        """
        return expr.description
    }
}
