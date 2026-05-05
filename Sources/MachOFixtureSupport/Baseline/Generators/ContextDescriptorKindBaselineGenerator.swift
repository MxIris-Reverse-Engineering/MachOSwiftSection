import Foundation
import SwiftSyntax
import SwiftSyntaxBuilder
import MachOFoundation
@testable import MachOSwiftSection

/// Emits `__Baseline__/ContextDescriptorKindBaseline.swift`.
///
/// `ContextDescriptorKind` is a `UInt8`-backed enum. PublicMemberScanner does
/// NOT emit MethodKey entries for enum cases (only for `func`/`var`/`init`/
/// `subscript`), so the Suite covers `description` and `mangledType`.
///
/// We extract a representative `ContextDescriptorKind` value from the
/// fixture's `Structs.StructTest` descriptor (`.struct`).
package enum ContextDescriptorKindBaselineGenerator {
    package static func generate(
        in machO: some MachOSwiftSectionRepresentableWithCache,
        outputDirectory: URL
    ) throws {
        let descriptor = try BaselineFixturePicker.struct_StructTest(in: machO)
        let kind = descriptor.layout.flags.kind
        let entryExpr = emitEntryExpr(for: kind)

        let registered = [
            "description",
            "mangledType",
        ]

        let header = """
        // AUTO-GENERATED — DO NOT EDIT.
        // Regenerate via: Scripts/regen-baselines.sh
        // Source fixture: SymbolTestsCore.framework
        """

        let file: SourceFileSyntax = """
        \(raw: header)

        enum ContextDescriptorKindBaseline {
            static let registeredTestMethodNames: Set<String> = \(literal: registered)

            struct Entry {
                let rawValue: UInt8
                let description: String
                let mangledType: String
            }

            static let structTest = \(raw: entryExpr)
        }
        """

        let formatted = file.formatted().description + "\n"
        let outputURL = outputDirectory.appendingPathComponent("ContextDescriptorKindBaseline.swift")
        try formatted.write(to: outputURL, atomically: true, encoding: .utf8)
    }

    private static func emitEntryExpr(for kind: ContextDescriptorKind) -> String {
        let rawValue = kind.rawValue
        let description = kind.description
        let mangledType = kind.mangledType

        let expr: ExprSyntax = """
        Entry(
            rawValue: \(raw: BaselineEmitter.hex(rawValue)),
            description: \(literal: description),
            mangledType: \(literal: mangledType)
        )
        """
        return expr.description
    }
}
