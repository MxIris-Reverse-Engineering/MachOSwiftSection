import Foundation
import SwiftSyntax
import SwiftSyntaxBuilder
import MachOFoundation
@testable import MachOSwiftSection

/// Emits `__Baseline__/ContextProtocolBaseline.swift`.
///
/// Per the protocol-extension attribution rule (see `BaselineGenerator.swift`),
/// the `parent()` family of overloads declared in
/// `extension ContextProtocol { ... }` belongs to this Suite, not to the
/// concrete `Struct`/`Enum`/`Class` Suites that conform.
///
/// We materialize a representative `Struct` context off the `Structs.StructTest`
/// descriptor — a concrete (non-module) context whose `parent` chain
/// terminates at the `SymbolTestsCore` module.
package enum ContextProtocolBaselineGenerator {
    package static func generate(
        in machO: some MachOSwiftSectionRepresentableWithCache,
        outputDirectory: URL
    ) throws {
        let descriptor = try BaselineFixturePicker.struct_StructTest(in: machO)
        let context = try Struct(descriptor: descriptor, in: machO)
        let hasParent = (try context.parent(in: machO)) != nil

        let entryExpr = emitEntryExpr(hasParent: hasParent)

        let registered = ["parent"]

        let header = """
        // AUTO-GENERATED — DO NOT EDIT.
        // Regenerate via: Scripts/regen-baselines.sh
        // Source fixture: SymbolTestsCore.framework
        //
        // The `parent` accessor returns a `SymbolOrElement<ContextWrapper>?`
        // we don't embed as a literal; the companion Suite verifies the
        // method produces cross-reader-consistent results at runtime against
        // the presence flag recorded here.
        """

        let file: SourceFileSyntax = """
        \(raw: header)

        enum ContextProtocolBaseline {
            static let registeredTestMethodNames: Set<String> = \(literal: registered)

            struct Entry {
                let hasParent: Bool
            }

            static let structTest = \(raw: entryExpr)
        }
        """

        let formatted = file.formatted().description + "\n"
        let outputURL = outputDirectory.appendingPathComponent("ContextProtocolBaseline.swift")
        try formatted.write(to: outputURL, atomically: true, encoding: .utf8)
    }

    private static func emitEntryExpr(hasParent: Bool) -> String {
        let expr: ExprSyntax = """
        Entry(
            hasParent: \(literal: hasParent)
        )
        """
        return expr.description
    }
}
