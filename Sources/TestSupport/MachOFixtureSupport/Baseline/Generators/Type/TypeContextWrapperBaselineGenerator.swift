import Foundation
import SwiftSyntax
import SwiftSyntaxBuilder
import MachOFoundation
@testable import MachOSwiftSection

/// Emits `__Baseline__/TypeContextWrapperBaseline.swift`.
///
/// `TypeContextWrapper` is the high-level sum type covering the
/// `enum`/`struct`/`class` type contexts (analogous to
/// `TypeContextDescriptorWrapper` but at the `*Context` level — wrapping
/// the high-level `Enum`/`Struct`/`Class` types, not their descriptors).
///
/// Members include the alternate-projection vars
/// (`contextDescriptorWrapper`, `typeContextDescriptorWrapper`), the
/// `asPointerWrapper(in:)` instance func, and the static
/// `forTypeContextDescriptorWrapper` family (3 overloads collapse to one
/// MethodKey under PublicMemberScanner's name-only key).
///
/// Picker: route `Structs.StructTest`'s descriptor through
/// `TypeContextWrapper.forTypeContextDescriptorWrapper` to produce a
/// `.struct(...)` wrapper.
package enum TypeContextWrapperBaselineGenerator {
    package static func generate(
        in machO: some MachOSwiftSectionRepresentableWithCache,
        outputDirectory: URL
    ) throws {
        let descriptor = try BaselineFixturePicker.struct_StructTest(in: machO)
        let descriptorWrapper = TypeContextDescriptorWrapper.struct(descriptor)
        let wrapper = try TypeContextWrapper.forTypeContextDescriptorWrapper(descriptorWrapper, in: machO)
        let entryExpr = emitEntryExpr(for: wrapper)

        let registered = [
            "asPointerWrapper",
            "contextDescriptorWrapper",
            "forTypeContextDescriptorWrapper",
            "typeContextDescriptorWrapper",
        ]

        let header = """
        // AUTO-GENERATED — DO NOT EDIT.
        // Regenerate via: Scripts/regen-baselines.sh
        // Source fixture: SymbolTestsCore.framework
        """

        let file: SourceFileSyntax = """
        \(raw: header)

        enum TypeContextWrapperBaseline {
            static let registeredTestMethodNames: Set<String> = \(literal: registered)

            struct Entry {
                let descriptorOffset: Int
                let isStruct: Bool
            }

            static let structTest = \(raw: entryExpr)
        }
        """

        let formatted = file.formatted().description + "\n"
        let outputURL = outputDirectory.appendingPathComponent("TypeContextWrapperBaseline.swift")
        try formatted.write(to: outputURL, atomically: true, encoding: .utf8)
    }

    private static func emitEntryExpr(for wrapper: TypeContextWrapper) -> String {
        let descriptorOffset = wrapper.typeContextDescriptorWrapper.contextDescriptor.offset
        let isStruct = wrapper.isStruct

        let expr: ExprSyntax = """
        Entry(
            descriptorOffset: \(raw: BaselineEmitter.hex(descriptorOffset)),
            isStruct: \(literal: isStruct)
        )
        """
        return expr.description
    }
}
