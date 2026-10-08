import Foundation
import SwiftSyntax
import SwiftSyntaxBuilder
@testable import MachOSwiftSection

/// Emits `__Baseline__/ProtocolRequirementKindBaseline.swift`.
///
/// `ProtocolRequirementKind` is a closed `UInt8` enum tagging each
/// `ProtocolRequirement.flags.kind` value. The only public method
/// declared in source is the `CustomStringConvertible.description`
/// computed property; the cases themselves are out of scope for
/// PublicMemberScanner (it does not visit `EnumCaseDeclSyntax`).
///
/// The baseline records the description string for every case so the
/// Suite can iterate them deterministically.
package enum ProtocolRequirementKindBaselineGenerator {
    package static func generate(outputDirectory: URL) throws {
        let baseProtocol = ProtocolRequirementKind.baseProtocol.description
        let method = ProtocolRequirementKind.method.description
        let initRequirement = ProtocolRequirementKind.`init`.description
        let getter = ProtocolRequirementKind.getter.description
        let setter = ProtocolRequirementKind.setter.description
        let readCoroutine = ProtocolRequirementKind.readCoroutine.description
        let modifyCoroutine = ProtocolRequirementKind.modifyCoroutine.description
        let associatedTypeAccessFunction = ProtocolRequirementKind.associatedTypeAccessFunction.description
        let associatedConformanceAccessFunction = ProtocolRequirementKind.associatedConformanceAccessFunction.description

        // Public members declared directly in ProtocolRequirementKind.swift.
        // Only `description` (in the CustomStringConvertible extension) is a
        // member declaration — case declarations are not visited.
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

        enum ProtocolRequirementKindBaseline {
            static let registeredTestMethodNames: Set<String> = \(literal: registered)

            static let baseProtocolDescription = \(literal: baseProtocol)
            static let methodDescription = \(literal: method)
            static let initDescription = \(literal: initRequirement)
            static let getterDescription = \(literal: getter)
            static let setterDescription = \(literal: setter)
            static let readCoroutineDescription = \(literal: readCoroutine)
            static let modifyCoroutineDescription = \(literal: modifyCoroutine)
            static let associatedTypeAccessFunctionDescription = \(literal: associatedTypeAccessFunction)
            static let associatedConformanceAccessFunctionDescription = \(literal: associatedConformanceAccessFunction)
        }
        """

        let formatted = file.formatted().description + "\n"
        let outputURL = outputDirectory.appendingPathComponent("ProtocolRequirementKindBaseline.swift")
        try formatted.write(to: outputURL, atomically: true, encoding: .utf8)
    }
}
