import Foundation
import SwiftSyntax
import SwiftSyntaxBuilder
import MachOFoundation
@testable import MachOSwiftSection

/// Emits `__Baseline__/ExtensionContextDescriptorBaseline.swift` from the
/// `SymbolTestsCore` fixture via the MachOFile reader.
///
/// `ExtensionContextDescriptor` declares only the `offset` and `layout`
/// ivars (`init(layout:offset:)` is filtered as memberwise-synthesized).
/// The protocol-extension `extendedContext(in:)` family of methods returns
/// an `Optional MangledName`; we record presence as a presence flag.
package enum ExtensionContextDescriptorBaselineGenerator {
    package static func generate(
        in machO: some MachOSwiftSectionRepresentableWithCache,
        outputDirectory: URL
    ) throws {
        let descriptor = try BaselineFixturePicker.extension_first(in: machO)
        let entryExpr = try emitEntryExpr(for: descriptor, in: machO)

        // Public members declared directly in ExtensionContextDescriptor.swift.
        // The `extendedContext(in:)` overload group (MachO / InProcess /
        // ReadingContext) collapses to a single MethodKey via
        // PublicMemberScanner's name-only key.
        let registered = [
            "extendedContext",
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

        enum ExtensionContextDescriptorBaseline {
            static let registeredTestMethodNames: Set<String> = \(literal: registered)

            struct Entry {
                let offset: Int
                let layoutFlagsRawValue: UInt32
                let hasExtendedContext: Bool
            }

            static let firstExtension = \(raw: entryExpr)
        }
        """

        let formatted = file.formatted().description + "\n"
        let outputURL = outputDirectory.appendingPathComponent("ExtensionContextDescriptorBaseline.swift")
        try formatted.write(to: outputURL, atomically: true, encoding: .utf8)
    }

    private static func emitEntryExpr(
        for descriptor: ExtensionContextDescriptor,
        in machO: some MachOSwiftSectionRepresentableWithCache
    ) throws -> String {
        let offset = descriptor.offset
        let flagsRaw = descriptor.layout.flags.rawValue
        let hasExtendedContext = (try descriptor.extendedContext(in: machO)) != nil

        let expr: ExprSyntax = """
        Entry(
            offset: \(raw: BaselineEmitter.hex(offset)),
            layoutFlagsRawValue: \(raw: BaselineEmitter.hex(flagsRaw)),
            hasExtendedContext: \(literal: hasExtendedContext)
        )
        """
        return expr.description
    }
}
