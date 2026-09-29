import Foundation
import SwiftSyntax
import SwiftSyntaxBuilder
import MachOFoundation
@testable import MachOSwiftSection

/// Emits `__Baseline__/OverrideTableHeaderBaseline.swift`.
///
/// `OverrideTableHeader` is the trailing-object header that announces a
/// class's override table (entries follow). We pick the header from
/// `Classes.SubclassTest` (which overrides several methods inherited from
/// `ClassTest`) and record the `numEntries` scalar.
package enum OverrideTableHeaderBaselineGenerator {
    package static func generate(
        in machO: some MachOSwiftSectionRepresentableWithCache,
        outputDirectory: URL
    ) throws {
        let descriptor = try BaselineFixturePicker.class_SubclassTest(in: machO)
        let classWrapper = try Class(descriptor: descriptor, in: machO)
        let header = try required(classWrapper.overrideTableHeader)

        let entryExpr = emitEntryExpr(for: header)

        // Public members declared directly in OverrideTableHeader.swift.
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

        enum OverrideTableHeaderBaseline {
            static let registeredTestMethodNames: Set<String> = \(literal: registered)

            struct Entry {
                let offset: Int
                let layoutNumEntries: UInt32
            }

            static let subclassTest = \(raw: entryExpr)
        }
        """

        let formatted = file.formatted().description + "\n"
        let outputURL = outputDirectory.appendingPathComponent("OverrideTableHeaderBaseline.swift")
        try formatted.write(to: outputURL, atomically: true, encoding: .utf8)
    }

    private static func emitEntryExpr(for header: OverrideTableHeader) -> String {
        let offset = header.offset
        let numEntries = header.layout.numEntries

        let expr: ExprSyntax = """
        Entry(
            offset: \(raw: BaselineEmitter.hex(offset)),
            layoutNumEntries: \(literal: numEntries)
        )
        """
        return expr.description
    }
}
