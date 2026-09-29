import Foundation
import SwiftSyntax
import SwiftSyntaxBuilder
import MachOFoundation
@testable import MachOSwiftSection

/// Emits `__Baseline__/ValueTypeDescriptorWrapperBaseline.swift`.
///
/// `ValueTypeDescriptorWrapper` is the 2-case sum type covering the
/// `enum`/`struct` value-type kinds (no `class` arm). It lives in the same
/// file as `TypeContextDescriptorWrapper` but is a distinct type — the
/// scanner attributes its public members to the `ValueTypeDescriptorWrapper`
/// MethodKey namespace.
///
/// Members include three alternate-projection vars (`contextDescriptor`,
/// `namedContextDescriptor`, `typeContextDescriptor`), the
/// `asTypeContextDescriptorWrapper`/`asContextDescriptorWrapper` projection
/// vars, and the `parent`/`genericContext` instance methods plus the
/// `resolve` static family in the `Resolvable` extension. Each method
/// collapses across MachO + InProcess + ReadingContext overloads under
/// PublicMemberScanner's name-only key.
///
/// Picker: `Structs.StructTest`'s descriptor wrapped in `.struct(...)`.
package enum ValueTypeDescriptorWrapperBaselineGenerator {
    package static func generate(
        in machO: some MachOSwiftSectionRepresentableWithCache,
        outputDirectory: URL
    ) throws {
        let descriptor = try BaselineFixturePicker.struct_StructTest(in: machO)
        let wrapper = ValueTypeDescriptorWrapper.struct(descriptor)
        let entryExpr = try emitEntryExpr(for: wrapper, in: machO)

        // Public members declared directly in TypeContextDescriptorWrapper.swift
        // for the `ValueTypeDescriptorWrapper` enum (body + Resolvable extension).
        let registered = [
            "asContextDescriptorWrapper",
            "asTypeContextDescriptorWrapper",
            "contextDescriptor",
            "genericContext",
            "namedContextDescriptor",
            "parent",
            "resolve",
            "typeContextDescriptor",
        ]

        let header = """
        // AUTO-GENERATED — DO NOT EDIT.
        // Regenerate via: Scripts/regen-baselines.sh
        // Source fixture: SymbolTestsCore.framework
        """

        let file: SourceFileSyntax = """
        \(raw: header)

        enum ValueTypeDescriptorWrapperBaseline {
            static let registeredTestMethodNames: Set<String> = \(literal: registered)

            struct Entry {
                let descriptorOffset: Int
                let hasParent: Bool
                let hasGenericContext: Bool
            }

            static let structTest = \(raw: entryExpr)
        }
        """

        let formatted = file.formatted().description + "\n"
        let outputURL = outputDirectory.appendingPathComponent("ValueTypeDescriptorWrapperBaseline.swift")
        try formatted.write(to: outputURL, atomically: true, encoding: .utf8)
    }

    private static func emitEntryExpr(
        for wrapper: ValueTypeDescriptorWrapper,
        in machO: some MachOSwiftSectionRepresentableWithCache
    ) throws -> String {
        let descriptorOffset = wrapper.contextDescriptor.offset
        let hasParent = (try wrapper.parent(in: machO)) != nil
        let hasGenericContext = (try wrapper.genericContext(in: machO)) != nil

        let expr: ExprSyntax = """
        Entry(
            descriptorOffset: \(raw: BaselineEmitter.hex(descriptorOffset)),
            hasParent: \(literal: hasParent),
            hasGenericContext: \(literal: hasGenericContext)
        )
        """
        return expr.description
    }
}
