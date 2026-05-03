import Foundation
import SwiftSyntax
import SwiftSyntaxBuilder
import MachOFoundation
@testable import MachOSwiftSection

/// Emits `__Baseline__/TypeContextDescriptorWrapperBaseline.swift`.
///
/// `TypeContextDescriptorWrapper` is the 3-case sum type covering the
/// `enum`/`struct`/`class` type-descriptor kinds. Members include three
/// alternate-projection vars (`contextDescriptor`, `namedContextDescriptor`,
/// `typeContextDescriptor`), the `asContextDescriptorWrapper` var, the
/// `asPointerWrapper(in:)` func, and the `parent`/`genericContext`/
/// `typeGenericContext` instance methods (each with MachO + InProcess +
/// ReadingContext overloads that collapse to one MethodKey under
/// PublicMemberScanner's name-only key). The static `resolve` family in
/// `extension TypeContextDescriptorWrapper: Resolvable { ... }` collapses
/// likewise.
///
/// Picker: `Structs.StructTest`'s descriptor wrapped in `.struct(...)`.
package enum TypeContextDescriptorWrapperBaselineGenerator {
    package static func generate(
        in machO: some MachOSwiftSectionRepresentableWithCache,
        outputDirectory: URL
    ) throws {
        let descriptor = try BaselineFixturePicker.struct_StructTest(in: machO)
        let wrapper = TypeContextDescriptorWrapper.struct(descriptor)
        let entryExpr = try emitEntryExpr(for: wrapper, in: machO)

        // Public members declared directly in TypeContextDescriptorWrapper.swift
        // (the `TypeContextDescriptorWrapper` enum body and its `Resolvable`
        // extension). The `ValueTypeDescriptorWrapper` enum declared in the
        // same file is covered by its own baseline / Suite.
        let registered = [
            "asContextDescriptorWrapper",
            "asPointerWrapper",
            "contextDescriptor",
            "genericContext",
            "namedContextDescriptor",
            "parent",
            "resolve",
            "typeContextDescriptor",
            "typeGenericContext",
        ]

        let header = """
        // AUTO-GENERATED — DO NOT EDIT.
        // Regenerate via: Scripts/regen-baselines.sh
        // Source fixture: SymbolTestsCore.framework
        """

        let file: SourceFileSyntax = """
        \(raw: header)

        enum TypeContextDescriptorWrapperBaseline {
            static let registeredTestMethodNames: Set<String> = \(literal: registered)

            struct Entry {
                let descriptorOffset: Int
                let hasParent: Bool
                let hasGenericContext: Bool
                let hasTypeGenericContext: Bool
            }

            static let structTest = \(raw: entryExpr)
        }
        """

        let formatted = file.formatted().description + "\n"
        let outputURL = outputDirectory.appendingPathComponent("TypeContextDescriptorWrapperBaseline.swift")
        try formatted.write(to: outputURL, atomically: true, encoding: .utf8)
    }

    private static func emitEntryExpr(
        for wrapper: TypeContextDescriptorWrapper,
        in machO: some MachOSwiftSectionRepresentableWithCache
    ) throws -> String {
        let descriptorOffset = wrapper.contextDescriptor.offset
        let hasParent = (try wrapper.parent(in: machO)) != nil
        let hasGenericContext = (try wrapper.genericContext(in: machO)) != nil
        let hasTypeGenericContext = (try wrapper.typeGenericContext(in: machO)) != nil

        let expr: ExprSyntax = """
        Entry(
            descriptorOffset: \(raw: BaselineEmitter.hex(descriptorOffset)),
            hasParent: \(literal: hasParent),
            hasGenericContext: \(literal: hasGenericContext),
            hasTypeGenericContext: \(literal: hasTypeGenericContext)
        )
        """
        return expr.description
    }
}
