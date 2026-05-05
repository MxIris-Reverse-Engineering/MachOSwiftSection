import Foundation
import SwiftSyntax
import SwiftSyntaxBuilder
import MachOFoundation
@testable import MachOSwiftSection

/// Emits `__Baseline__/GenericValueDescriptorBaseline.swift`.
///
/// `GenericValueDescriptor` is the per-value record carried in the
/// trailing `values` array of a generic context whose
/// `GenericContextDescriptorFlags.hasValues` bit is set. Each descriptor
/// records the value `type` (currently only `GenericValueType.int`).
///
/// Phase B7 introduced `GenericValueParameters.swift` so that
/// `GenericValueFixtures.FixedSizeArray<let N: Int, T>` surfaces a
/// single `GenericValueDescriptor` on its generic context.
package enum GenericValueDescriptorBaselineGenerator {
    package static func generate(
        in machO: some MachOSwiftSectionRepresentableWithCache,
        outputDirectory: URL
    ) throws {
        let descriptor = try BaselineFixturePicker.struct_FixedSizeArray(in: machO)
        let context = try required(try descriptor.typeGenericContext(in: machO))
        let value = try required(context.values.first)

        let entryExpr = emitEntryExpr(for: value)

        // Public members declared directly in GenericValueDescriptor.swift.
        // `init(layout:offset:)` is filtered as memberwise-synthesized.
        let registered = [
            "layout",
            "offset",
            "type",
        ]

        let header = """
        // AUTO-GENERATED — DO NOT EDIT.
        // Regenerate via: Scripts/regen-baselines.sh
        // Source fixture: SymbolTestsCore.framework
        """

        let file: SourceFileSyntax = """
        \(raw: header)

        enum GenericValueDescriptorBaseline {
            static let registeredTestMethodNames: Set<String> = \(literal: registered)

            struct Entry {
                let offset: Int
                let layoutType: UInt32
                let typeRawValue: UInt32
            }

            static let fixedSizeArrayFirstValue = \(raw: entryExpr)
        }
        """

        let formatted = file.formatted().description + "\n"
        let outputURL = outputDirectory.appendingPathComponent("GenericValueDescriptorBaseline.swift")
        try formatted.write(to: outputURL, atomically: true, encoding: .utf8)
    }

    private static func emitEntryExpr(for value: GenericValueDescriptor) -> String {
        let offset = value.offset
        let layoutType = value.layout.type
        let typeRawValue = value.type.rawValue

        let expr: ExprSyntax = """
        Entry(
            offset: \(raw: BaselineEmitter.hex(offset)),
            layoutType: \(literal: layoutType),
            typeRawValue: \(literal: typeRawValue)
        )
        """
        return expr.description
    }
}
