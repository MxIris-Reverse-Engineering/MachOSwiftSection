import Foundation
import SwiftSyntax
import SwiftSyntaxBuilder

/// Emits `__Baseline__/MetadataAccessorFunctionBaseline.swift`.
///
/// `MetadataAccessorFunction` wraps a raw function pointer to a Swift
/// runtime metadata accessor. The pointer can only be obtained from a
/// loaded MachOImage (the function lives in the image's text segment), so
/// the structural payload is reachable solely through MachOImage. We emit
/// only the registered method name; the Suite (`MetadataAccessorFunctionTests`)
/// invokes `callAsFunction(request:)` against `Structs.StructTest`'s accessor
/// and asserts the returned `MetadataResponse` resolves to a non-nil
/// `StructMetadata`.
///
/// `init(ptr:)` is `package`-scoped and not visited by the public scanner;
/// the six `callAsFunction` overloads collapse to a single `MethodKey`
/// under PublicMemberScanner's name-only keying.
package enum MetadataAccessorFunctionBaselineGenerator {
    package static func generate(outputDirectory: URL) throws {
        let registered = [
            "callAsFunction",
        ]

        let header = """
        // AUTO-GENERATED — DO NOT EDIT.
        // Regenerate via: Scripts/regen-baselines.sh
        // Source fixture: SymbolTestsCore.framework
        //
        // MetadataAccessorFunction is materialised solely through MachOImage
        // (the underlying pointer is the runtime function's text address).
        // No literal payload is embedded; the Suite invokes the accessor at
        // runtime and asserts a non-nil StructMetadata response.
        """

        let file: SourceFileSyntax = """
        \(raw: header)

        enum MetadataAccessorFunctionBaseline {
            static let registeredTestMethodNames: Set<String> = \(literal: registered)
        }
        """

        let formatted = file.formatted().description + "\n"
        let outputURL = outputDirectory.appendingPathComponent("MetadataAccessorFunctionBaseline.swift")
        try formatted.write(to: outputURL, atomically: true, encoding: .utf8)
    }
}
