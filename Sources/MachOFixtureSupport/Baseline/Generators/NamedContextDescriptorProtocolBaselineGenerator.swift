import Foundation
import SwiftSyntax
import SwiftSyntaxBuilder
import MachOFoundation
@testable import MachOSwiftSection

/// Emits `__Baseline__/NamedContextDescriptorProtocolBaseline.swift`.
///
/// Per the protocol-extension attribution rule (see `BaselineGenerator.swift`),
/// `name(in:)` and `mangledName(in:)` are declared in
/// `extension NamedContextDescriptorProtocol { ... }` and attribute to the
/// protocol, not to concrete descriptor types like `StructDescriptor`.
///
/// Picker: `Structs.StructTest` — its `name(in:)` is the stable string
/// `"StructTest"` we embed verbatim.
package enum NamedContextDescriptorProtocolBaselineGenerator {
    package static func generate(
        in machO: some MachOSwiftSectionRepresentableWithCache,
        outputDirectory: URL
    ) throws {
        let descriptor = try BaselineFixturePicker.struct_StructTest(in: machO)
        let name = try descriptor.name(in: machO)
        let hasMangledName = (try? descriptor.mangledName(in: machO)) != nil

        let entryExpr = emitEntryExpr(name: name, hasMangledName: hasMangledName)

        let registered = [
            "mangledName",
            "name",
        ]

        let header = """
        // AUTO-GENERATED — DO NOT EDIT.
        // Regenerate via: Scripts/regen-baselines.sh
        // Source fixture: SymbolTestsCore.framework
        //
        // The MangledName payload is a deep ABI tree we don't embed as a
        // literal; the companion Suite (NamedContextDescriptorProtocolTests)
        // verifies the methods produce cross-reader-consistent results at
        // runtime against the presence flag recorded here.
        """

        let file: SourceFileSyntax = """
        \(raw: header)

        enum NamedContextDescriptorProtocolBaseline {
            static let registeredTestMethodNames: Set<String> = \(literal: registered)

            struct Entry {
                let name: String
                let hasMangledName: Bool
            }

            static let structTest = \(raw: entryExpr)
        }
        """

        let formatted = file.formatted().description + "\n"
        let outputURL = outputDirectory.appendingPathComponent("NamedContextDescriptorProtocolBaseline.swift")
        try formatted.write(to: outputURL, atomically: true, encoding: .utf8)
    }

    private static func emitEntryExpr(name: String, hasMangledName: Bool) -> String {
        let expr: ExprSyntax = """
        Entry(
            name: \(literal: name),
            hasMangledName: \(literal: hasMangledName)
        )
        """
        return expr.description
    }
}
