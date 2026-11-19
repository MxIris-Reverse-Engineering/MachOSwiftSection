import Foundation
import SwiftSyntax
import SwiftSyntaxBuilder

/// Emits `__Baseline__/MethodDescriptorKindBaseline.swift`.
///
/// `MethodDescriptorKind` is a `UInt8`-raw enum with six cases (`method`,
/// `init`, `getter`, `setter`, `modifyCoroutine`, `readCoroutine`). The
/// `description` accessor returns a fixed-width display string per case.
/// We pin the raw values and description strings here so accidental
/// renumbering or display tweaks fail a Suite test.
package enum MethodDescriptorKindBaselineGenerator {
    package static func generate(outputDirectory: URL) throws {
        // Public members declared directly in MethodDescriptorKind.swift:
        // only `description`. Cases are tracked statically below.
        let registered = [
            "description",
        ]

        let header = """
        // AUTO-GENERATED — DO NOT EDIT.
        // Regenerate via: Scripts/regen-baselines.sh
        // Source fixture: SymbolTestsCore.framework
        """

        let file: SourceFileSyntax = """
        \(raw: header)

        enum MethodDescriptorKindBaseline {
            static let registeredTestMethodNames: Set<String> = \(literal: registered)

            struct Entry {
                let rawValue: UInt8
                let description: String
            }

            static let method = Entry(rawValue: 0x0, description: "Method")
            static let `init` = Entry(rawValue: 0x1, description: " Init ")
            static let getter = Entry(rawValue: 0x2, description: "Getter")
            static let setter = Entry(rawValue: 0x3, description: "Setter")
            static let modifyCoroutine = Entry(rawValue: 0x4, description: "Modify")
            static let readCoroutine = Entry(rawValue: 0x5, description: " Read ")
        }
        """

        let formatted = file.formatted().description + "\n"
        let outputURL = outputDirectory.appendingPathComponent("MethodDescriptorKindBaseline.swift")
        try formatted.write(to: outputURL, atomically: true, encoding: .utf8)
    }
}
