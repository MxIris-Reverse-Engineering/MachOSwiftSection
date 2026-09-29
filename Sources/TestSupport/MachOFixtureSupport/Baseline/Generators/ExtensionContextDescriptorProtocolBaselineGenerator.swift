import Foundation
import SwiftSyntax
import SwiftSyntaxBuilder
import MachOFoundation
@testable import MachOSwiftSection

/// Emits `__Baseline__/ExtensionContextDescriptorProtocolBaseline.swift`.
///
/// `extendedContext(in:)` is declared in
/// `Extension/ExtensionContextDescriptor.swift` as a protocol-extension
/// method on `ExtensionContextDescriptorProtocol`. `PublicMemberScanner`
/// attributes it to the extended protocol (see the protocol-extension
/// attribution rule in `BaselineGenerator.swift`), so the Suite/baseline
/// for this method lives here, not on `ExtensionContextDescriptor`.
///
/// The three `extendedContext(in:)` overloads (MachO / InProcess /
/// ReadingContext) collapse to a single MethodKey via PublicMemberScanner's
/// name-only key. The `MangledName` payload is a deep ABI tree we don't
/// embed as a literal; instead we record presence as a flag so the
/// companion Suite (ExtensionContextDescriptorProtocolTests) can verify
/// cross-reader-consistent results.
package enum ExtensionContextDescriptorProtocolBaselineGenerator {
    package static func generate(
        in machO: some MachOSwiftSectionRepresentableWithCache,
        outputDirectory: URL
    ) throws {
        let descriptor = try BaselineFixturePicker.extension_first(in: machO)
        let hasExtendedContext = (try descriptor.extendedContext(in: machO)) != nil
        let entryExpr = emitEntryExpr(hasExtendedContext: hasExtendedContext)

        // Public members declared in protocol extensions on
        // `ExtensionContextDescriptorProtocol`. The three
        // `extendedContext(in:)` overloads collapse to a single MethodKey
        // via PublicMemberScanner's name-only key.
        let registered = [
            "extendedContext",
        ]

        let header = """
        // AUTO-GENERATED — DO NOT EDIT.
        // Regenerate via: Scripts/regen-baselines.sh
        // Source fixture: SymbolTestsCore.framework
        //
        // The MangledName payload returned by `extendedContext(in:)` is a
        // deep ABI tree we don't embed as a literal; the companion Suite
        // (ExtensionContextDescriptorProtocolTests) verifies the methods
        // produce cross-reader-consistent results at runtime.
        """

        let file: SourceFileSyntax = """
        \(raw: header)

        enum ExtensionContextDescriptorProtocolBaseline {
            static let registeredTestMethodNames: Set<String> = \(literal: registered)

            struct Entry {
                let hasExtendedContext: Bool
            }

            static let firstExtension = \(raw: entryExpr)
        }
        """

        let formatted = file.formatted().description + "\n"
        let outputURL = outputDirectory.appendingPathComponent("ExtensionContextDescriptorProtocolBaseline.swift")
        try formatted.write(to: outputURL, atomically: true, encoding: .utf8)
    }

    private static func emitEntryExpr(hasExtendedContext: Bool) -> String {
        let expr: ExprSyntax = """
        Entry(
            hasExtendedContext: \(literal: hasExtendedContext)
        )
        """
        return expr.description
    }
}
