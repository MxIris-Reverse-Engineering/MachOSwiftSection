import Foundation
import SwiftSyntax
import SwiftSyntaxBuilder
import MachOFoundation
@testable import MachOSwiftSection

/// Emits `__Baseline__/GenericValueHeaderBaseline.swift`.
///
/// `GenericValueHeader` is the trailing-object header announcing the
/// integer-value-parameter array on a generic context whose
/// `GenericContextDescriptorFlags.hasValues` bit is set. It records
/// `numValues` (UInt32).
///
/// Phase B7 introduced `GenericValueParameters.swift` so that
/// `GenericValueFixtures.FixedSizeArray<let N: Int, T>` surfaces a
/// single `GenericValueHeader` on its generic context.
package enum GenericValueHeaderBaselineGenerator {
    package static func generate(
        in machO: some MachOSwiftSectionRepresentableWithCache,
        outputDirectory: URL
    ) throws {
        let descriptor = try BaselineFixturePicker.struct_FixedSizeArray(in: machO)
        let context = try required(try descriptor.typeGenericContext(in: machO))
        let header = try required(context.valueHeader)

        let entryExpr = emitEntryExpr(for: header)

        // Public members declared directly in GenericValueHeader.swift.
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

        enum GenericValueHeaderBaseline {
            static let registeredTestMethodNames: Set<String> = \(literal: registered)

            struct Entry {
                let offset: Int
                let layoutNumValues: UInt32
            }

            static let fixedSizeArrayHeader = \(raw: entryExpr)
        }
        """

        let formatted = file.formatted().description + "\n"
        let outputURL = outputDirectory.appendingPathComponent("GenericValueHeaderBaseline.swift")
        try formatted.write(to: outputURL, atomically: true, encoding: .utf8)
    }

    private static func emitEntryExpr(for header: GenericValueHeader) -> String {
        let offset = header.offset
        let numValues = header.layout.numValues

        let expr: ExprSyntax = """
        Entry(
            offset: \(raw: BaselineEmitter.hex(offset)),
            layoutNumValues: \(literal: numValues)
        )
        """
        return expr.description
    }
}
