import Foundation
import SwiftSyntax
import SwiftSyntaxBuilder
import MachOFoundation
@testable import MachOSwiftSection

/// Emits `__Baseline__/GenericPackShapeHeaderBaseline.swift`.
///
/// `GenericPackShapeHeader` is the trailing-object header announcing the
/// pack-shape array on a generic context whose
/// `GenericContextDescriptorFlags.hasTypePacks` bit is set. It records
/// `numPacks` and `numShapeClasses` (both `UInt16`).
///
/// The fixture's `ParameterPackRequirementTest<each Element>` declares one
/// pack parameter, surfacing a single header.
package enum GenericPackShapeHeaderBaselineGenerator {
    package static func generate(
        in machO: some MachOSwiftSectionRepresentableWithCache,
        outputDirectory: URL
    ) throws {
        let descriptor = try BaselineFixturePicker.struct_ParameterPackRequirementTest(in: machO)
        let context = try required(try descriptor.typeGenericContext(in: machO))
        let header = try required(context.typePackHeader)

        let entryExpr = emitEntryExpr(for: header)

        // Public members declared directly in GenericPackShapeHeader.swift.
        // `init(layout:offset:)` is filtered as memberwise-synthesized.
        let registered = [
            "layout",
            "offset",
        ]

        let headerComment = """
        // AUTO-GENERATED — DO NOT EDIT.
        // Regenerate via: Scripts/regen-baselines.sh
        // Source fixture: SymbolTestsCore.framework
        """

        let file: SourceFileSyntax = """
        \(raw: headerComment)

        enum GenericPackShapeHeaderBaseline {
            static let registeredTestMethodNames: Set<String> = \(literal: registered)

            struct Entry {
                let offset: Int
                let layoutNumPacks: UInt16
                let layoutNumShapeClasses: UInt16
            }

            static let parameterPackHeader = \(raw: entryExpr)
        }
        """

        let formatted = file.formatted().description + "\n"
        let outputURL = outputDirectory.appendingPathComponent("GenericPackShapeHeaderBaseline.swift")
        try formatted.write(to: outputURL, atomically: true, encoding: .utf8)
    }

    private static func emitEntryExpr(for header: GenericPackShapeHeader) -> String {
        let offset = header.offset
        let numPacks = header.layout.numPacks
        let numShapeClasses = header.layout.numShapeClasses

        let expr: ExprSyntax = """
        Entry(
            offset: \(raw: BaselineEmitter.hex(offset)),
            layoutNumPacks: \(literal: numPacks),
            layoutNumShapeClasses: \(literal: numShapeClasses)
        )
        """
        return expr.description
    }
}
