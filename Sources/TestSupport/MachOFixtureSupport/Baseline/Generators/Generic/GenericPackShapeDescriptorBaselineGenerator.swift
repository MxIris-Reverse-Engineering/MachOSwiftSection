import Foundation
import SwiftSyntax
import SwiftSyntaxBuilder
import MachOFoundation
@testable import MachOSwiftSection

/// Emits `__Baseline__/GenericPackShapeDescriptorBaseline.swift`.
///
/// `GenericPackShapeDescriptor` is the per-pack record carried in the
/// trailing `typePacks` array of a generic context whose
/// `GenericContextDescriptorFlags.hasTypePacks` bit is set. Each descriptor
/// records the pack `kind` (metadata or witnessTable), `index`, and
/// `shapeClass` plus an `unused` filler.
///
/// The fixture's `ParameterPackRequirementTest<each Element>` declares one
/// pack parameter, which surfaces a single pack-shape descriptor.
package enum GenericPackShapeDescriptorBaselineGenerator {
    package static func generate(
        in machO: some MachOSwiftSectionRepresentableWithCache,
        outputDirectory: URL
    ) throws {
        let descriptor = try BaselineFixturePicker.struct_ParameterPackRequirementTest(in: machO)
        let context = try required(try descriptor.typeGenericContext(in: machO))
        let pack = try required(context.typePacks.first)

        let entryExpr = emitEntryExpr(for: pack)

        // Public members declared directly in GenericPackShapeDescriptor.swift.
        // `init(layout:offset:)` is filtered as memberwise-synthesized.
        let registered = [
            "kind",
            "layout",
            "offset",
        ]

        let header = """
        // AUTO-GENERATED — DO NOT EDIT.
        // Regenerate via: Scripts/regen-baselines.sh
        // Source fixture: SymbolTestsCore.framework
        """

        let file: SourceFileSyntax = """
        \(raw: header)

        enum GenericPackShapeDescriptorBaseline {
            static let registeredTestMethodNames: Set<String> = \(literal: registered)

            struct Entry {
                let offset: Int
                let layoutKind: UInt16
                let layoutIndex: UInt16
                let layoutShapeClass: UInt16
                let layoutUnused: UInt16
                let kindRawValue: UInt16
            }

            static let parameterPackFirstShape = \(raw: entryExpr)
        }
        """

        let formatted = file.formatted().description + "\n"
        let outputURL = outputDirectory.appendingPathComponent("GenericPackShapeDescriptorBaseline.swift")
        try formatted.write(to: outputURL, atomically: true, encoding: .utf8)
    }

    private static func emitEntryExpr(for pack: GenericPackShapeDescriptor) -> String {
        let offset = pack.offset
        let layoutKind = pack.layout.kind
        let layoutIndex = pack.layout.index
        let layoutShapeClass = pack.layout.shapeClass
        let layoutUnused = pack.layout.unused
        let kindRawValue = pack.kind.rawValue

        let expr: ExprSyntax = """
        Entry(
            offset: \(raw: BaselineEmitter.hex(offset)),
            layoutKind: \(literal: layoutKind),
            layoutIndex: \(literal: layoutIndex),
            layoutShapeClass: \(literal: layoutShapeClass),
            layoutUnused: \(literal: layoutUnused),
            kindRawValue: \(literal: kindRawValue)
        )
        """
        return expr.description
    }
}
