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
/// The protocol-extension `extendedContext(in:)` family of methods is
/// attributed to `ExtensionContextDescriptorProtocol` by
/// `PublicMemberScanner` (see the protocol-extension attribution rule in
/// `BaselineGenerator.swift`); its baseline/Suite live separately.
package enum ExtensionContextDescriptorBaselineGenerator {
    package static func generate(
        in machO: some MachOSwiftSectionRepresentableWithCache,
        outputDirectory: URL
    ) throws {
        let descriptor = try BaselineFixturePicker.extension_first(in: machO)
        let entryExpr = emitEntryExpr(for: descriptor)

        // Public members declared directly in ExtensionContextDescriptor.swift.
        let registered = [
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
            }

            static let firstExtension = \(raw: entryExpr)
        }
        """

        let formatted = file.formatted().description + "\n"
        let outputURL = outputDirectory.appendingPathComponent("ExtensionContextDescriptorBaseline.swift")
        try formatted.write(to: outputURL, atomically: true, encoding: .utf8)
    }

    private static func emitEntryExpr(
        for descriptor: ExtensionContextDescriptor
    ) -> String {
        let offset = descriptor.offset
        let flagsRaw = descriptor.layout.flags.rawValue

        let expr: ExprSyntax = """
        Entry(
            offset: \(raw: BaselineEmitter.hex(offset)),
            layoutFlagsRawValue: \(raw: BaselineEmitter.hex(flagsRaw))
        )
        """
        return expr.description
    }
}
