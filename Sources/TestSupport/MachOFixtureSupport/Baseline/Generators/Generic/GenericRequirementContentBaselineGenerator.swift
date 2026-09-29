import Foundation
import SwiftSyntax
import SwiftSyntaxBuilder
@testable import MachOSwiftSection

/// Emits `__Baseline__/GenericRequirementContentBaseline.swift`.
///
/// `GenericRequirementContent` and `ResolvedGenericRequirementContent` are
/// `@CaseCheckable(.public)` / `@AssociatedValue(.public)` enums; the macro-
/// generated case-presence helpers and associated-value extractors are not
/// visited by `PublicMemberScanner` (it only inspects source-level decls,
/// not macro expansions). The only public member declared in source — and
/// therefore the only one this Suite has to cover — is the nested
/// `GenericRequirementContent.InvertedProtocols` struct's two stored
/// properties (`genericParamIndex`, `protocols`).
///
/// The `InvertedProtocols` payload is materialized by the parser via an
/// in-memory load of `RelativeOffset.layout.content` for the
/// `invertedProtocols` requirement kind. The fixture's
/// `InvertibleProtocolRequirementTest<Element: ~Copyable>: ~Copyable`
/// generic struct emits exactly one such requirement, so we use it as the
/// live carrier.
package enum GenericRequirementContentBaselineGenerator {
    package static func generate(
        in machO: some MachOSwiftSectionRepresentableWithCache,
        outputDirectory: URL
    ) throws {
        let descriptor = try BaselineFixturePicker.struct_InvertibleProtocolRequirementTest(in: machO)
        let context = try required(try descriptor.typeGenericContext(in: machO))
        // Look at the conditional invertible protocols requirements first;
        // fall back to scanning the regular requirements for the
        // invertedProtocols kind.
        let invertedProtocols = try requireInvertedProtocols(in: context)

        let entryExpr = emitEntryExpr(for: invertedProtocols)

        // Public members declared directly on
        // GenericRequirementContent.InvertedProtocols. The two case-iterating
        // helpers macro-injected onto the parent enums are out of scope.
        let registered = [
            "genericParamIndex",
            "protocols",
        ]

        let header = """
        // AUTO-GENERATED — DO NOT EDIT.
        // Regenerate via: Scripts/regen-baselines.sh
        // Source fixture: SymbolTestsCore.framework
        //
        // Only GenericRequirementContent.InvertedProtocols has visible public
        // surface (case-iterating helpers on the parent enums are emitted
        // by macros and not visited by PublicMemberScanner).
        """

        let file: SourceFileSyntax = """
        \(raw: header)

        enum GenericRequirementContentBaseline {
            static let registeredTestMethodNames: Set<String> = \(literal: registered)

            struct Entry {
                let genericParamIndex: UInt16
                let protocolsRawValue: UInt16
            }

            static let invertibleProtocolRequirement = \(raw: entryExpr)
        }
        """

        let formatted = file.formatted().description + "\n"
        let outputURL = outputDirectory.appendingPathComponent("GenericRequirementContentBaseline.swift")
        try formatted.write(to: outputURL, atomically: true, encoding: .utf8)
    }

    private static func requireInvertedProtocols(
        in context: TypeGenericContext
    ) throws -> GenericRequirementContent.InvertedProtocols {
        // Walk both the conditional set and the regular requirements to find
        // an `.invertedProtocols` discriminant.
        let candidates =
            context.conditionalInvertibleProtocolsRequirements
            + context.requirements
        for requirement in candidates {
            if case .invertedProtocols(let payload) = requirement.content {
                return payload
            }
        }
        throw RequiredError.requiredNonOptional
    }

    private static func emitEntryExpr(for value: GenericRequirementContent.InvertedProtocols) -> String {
        let genericParamIndex = value.genericParamIndex
        let protocolsRawValue = value.protocols.rawValue

        let expr: ExprSyntax = """
        Entry(
            genericParamIndex: \(literal: genericParamIndex),
            protocolsRawValue: \(raw: BaselineEmitter.hex(protocolsRawValue))
        )
        """
        return expr.description
    }
}
