import Foundation
import SwiftSyntax
import SwiftSyntaxBuilder
import MachOFoundation
@testable import MachOSwiftSection

/// Emits `__Baseline__/BuiltinTypeBaseline.swift`.
///
/// `BuiltinType` is the high-level wrapper around `BuiltinTypeDescriptor`.
/// It pre-resolves `typeName` from the descriptor at construction. The
/// Suite picks the first descriptor in the `__swift5_builtin` section
/// (matching `BuiltinTypeDescriptorBaseline`'s carrier) and wraps it.
package enum BuiltinTypeBaselineGenerator {
    package static func generate(
        in machO: some MachOSwiftSectionRepresentableWithCache,
        outputDirectory: URL
    ) throws {
        let descriptor = try BaselineFixturePicker.builtinTypeDescriptor_first(in: machO)
        let builtin = try BuiltinType(descriptor: descriptor, in: machO)
        let entryExpr = emitEntryExpr(for: builtin)

        // Public members declared in BuiltinType.swift. The two MachO
        // initializers (`init(descriptor:in:)`) and the InProcess form
        // (`init(descriptor:)`) collapse into two MethodKey entries
        // under the scanner.
        let registered = [
            "descriptor",
            "init(descriptor:)",
            "init(descriptor:in:)",
            "typeName",
        ]

        let header = """
        // AUTO-GENERATED — DO NOT EDIT.
        // Regenerate via: Scripts/regen-baselines.sh
        // Source fixture: SymbolTestsCore.framework
        //
        // BuiltinType wraps the first BuiltinTypeDescriptor of
        // SymbolTestsCore. Live MangledName payload isn't embedded as a
        // literal; the Suite verifies presence via the
        // `hasMangledName` flag and equality of the descriptor offset.
        """

        let file: SourceFileSyntax = """
        \(raw: header)

        enum BuiltinTypeBaseline {
            static let registeredTestMethodNames: Set<String> = \(literal: registered)

            struct Entry {
                let descriptorOffset: Int
                let hasTypeName: Bool
            }

            static let firstBuiltin = \(raw: entryExpr)
        }
        """

        let formatted = file.formatted().description + "\n"
        let outputURL = outputDirectory.appendingPathComponent("BuiltinTypeBaseline.swift")
        try formatted.write(to: outputURL, atomically: true, encoding: .utf8)
    }

    private static func emitEntryExpr(for builtin: BuiltinType) -> String {
        let descriptorOffset = builtin.descriptor.offset
        let hasTypeName = builtin.typeName != nil

        let expr: ExprSyntax = """
        Entry(
            descriptorOffset: \(raw: BaselineEmitter.hex(descriptorOffset)),
            hasTypeName: \(literal: hasTypeName)
        )
        """
        return expr.description
    }
}
