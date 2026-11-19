import Foundation
import SwiftSyntax
import SwiftSyntaxBuilder
import MachOFoundation
@testable import MachOSwiftSection

/// Emits `__Baseline__/ContextDescriptorKindSpecificFlagsBaseline.swift`.
///
/// `ContextDescriptorKindSpecificFlags` is a sum type whose three case-
/// extraction accessors (`protocolFlags`, `typeFlags`, `anonymousFlags`)
/// return optionals. We sample the fixture's `Structs.StructTest` descriptor
/// (a struct kind) so the live value is `.type(...)` — `typeFlags != nil`,
/// the other two `nil`.
///
/// PublicMemberScanner does NOT emit MethodKey entries for the underlying
/// enum cases.
package enum ContextDescriptorKindSpecificFlagsBaselineGenerator {
    package static func generate(
        in machO: some MachOSwiftSectionRepresentableWithCache,
        outputDirectory: URL
    ) throws {
        let descriptor = try BaselineFixturePicker.struct_StructTest(in: machO)
        let flags = try required(descriptor.layout.flags.kindSpecificFlags)
        let entryExpr = emitEntryExpr(for: flags)

        let registered = [
            "anonymousFlags",
            "protocolFlags",
            "typeFlags",
        ]

        let header = """
        // AUTO-GENERATED — DO NOT EDIT.
        // Regenerate via: Scripts/regen-baselines.sh
        // Source fixture: SymbolTestsCore.framework
        """

        let file: SourceFileSyntax = """
        \(raw: header)

        enum ContextDescriptorKindSpecificFlagsBaseline {
            static let registeredTestMethodNames: Set<String> = \(literal: registered)

            struct Entry {
                let hasProtocolFlags: Bool
                let hasTypeFlags: Bool
                let hasAnonymousFlags: Bool
            }

            static let structTest = \(raw: entryExpr)
        }
        """

        let formatted = file.formatted().description + "\n"
        let outputURL = outputDirectory.appendingPathComponent("ContextDescriptorKindSpecificFlagsBaseline.swift")
        try formatted.write(to: outputURL, atomically: true, encoding: .utf8)
    }

    private static func emitEntryExpr(for flags: ContextDescriptorKindSpecificFlags) -> String {
        let hasProtocolFlags = flags.protocolFlags != nil
        let hasTypeFlags = flags.typeFlags != nil
        let hasAnonymousFlags = flags.anonymousFlags != nil

        let expr: ExprSyntax = """
        Entry(
            hasProtocolFlags: \(literal: hasProtocolFlags),
            hasTypeFlags: \(literal: hasTypeFlags),
            hasAnonymousFlags: \(literal: hasAnonymousFlags)
        )
        """
        return expr.description
    }
}
