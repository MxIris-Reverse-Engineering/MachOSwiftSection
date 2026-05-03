import Foundation
import SwiftSyntax
import SwiftSyntaxBuilder
import MachOFoundation
@testable import MachOSwiftSection

/// Emits `__Baseline__/GenericContextBaseline.swift`.
///
/// `GenericContext` (the typealias `TargetGenericContext<GenericContextDescriptorHeader>`)
/// and `TypeGenericContext` (the typealias
/// `TargetGenericContext<TypeGenericContextDescriptorHeader>`) are both
/// instantiations of the generic `TargetGenericContext` struct. The
/// PublicMemberScanner emits MethodKey entries under the typeName
/// `TargetGenericContext` (the actual struct declaration name), so this
/// Suite's `testedTypeName` is `TargetGenericContext`.
///
/// Fixture choice: we sample several generic structs that exercise the
/// principal branches of the parser:
///   - `GenericStructNonRequirement<A>` — params only, no requirements
///   - `GenericStructLayoutRequirement<A: AnyObject>` — layout requirement
///   - `GenericStructSwiftProtocolRequirement<A: Equatable>` — protocol
///     requirement (Swift)
///   - `ParameterPackRequirementTest<each Element>` — typePackHeader/typePacks
///   - `InvertibleProtocolRequirementTest<Element: ~Copyable>: ~Copyable` —
///     conditionalInvertibleProtocolSet
///
/// We record presence/cardinality (counts; presence flags for optional
/// payloads) rather than full structural equality — the underlying types
/// (`GenericRequirementDescriptor`, `GenericPackShapeDescriptor`, etc.) are
/// not cheap to deep-compare and the meaningful invariant is "the field is
/// present and has the expected count when expected, absent otherwise".
package enum GenericContextBaselineGenerator {
    package static func generate(
        in machO: some MachOSwiftSectionRepresentableWithCache,
        outputDirectory: URL
    ) throws {
        let nonRequirementContext = try requireTypeGenericContext(
            for: try BaselineFixturePicker.struct_GenericStructNonRequirement(in: machO),
            in: machO
        )
        let layoutContext = try requireTypeGenericContext(
            for: try BaselineFixturePicker.struct_GenericStructLayoutRequirement(in: machO),
            in: machO
        )
        let protocolContext = try requireTypeGenericContext(
            for: try BaselineFixturePicker.struct_GenericStructSwiftProtocolRequirement(in: machO),
            in: machO
        )
        let packContext = try requireTypeGenericContext(
            for: try BaselineFixturePicker.struct_ParameterPackRequirementTest(in: machO),
            in: machO
        )
        let invertibleContext = try requireTypeGenericContext(
            for: try BaselineFixturePicker.struct_InvertibleProtocolRequirementTest(in: machO),
            in: machO
        )

        let nonRequirementExpr = emitEntryExpr(for: nonRequirementContext)
        let layoutExpr = emitEntryExpr(for: layoutContext)
        let protocolExpr = emitEntryExpr(for: protocolContext)
        let packExpr = emitEntryExpr(for: packContext)
        let invertibleExpr = emitEntryExpr(for: invertibleContext)

        // Public members declared directly in GenericContext.swift on
        // `TargetGenericContext`. The three `init(contextDescriptor:in:)`
        // overloads (MachO + InProcess + ReadingContext) collapse to one
        // MethodKey under PublicMemberScanner's name-based deduplication;
        // `init(contextDescriptor:)` is the InProcess variant.
        let registered = [
            "allParameters",
            "allRequirements",
            "allTypePacks",
            "allValues",
            "asGenericContext",
            "conditionalInvertibleProtocolSet",
            "conditionalInvertibleProtocolsRequirements",
            "conditionalInvertibleProtocolsRequirementsCount",
            "currentParameters",
            "currentRequirements",
            "currentTypePacks",
            "currentValues",
            "depth",
            "header",
            "init(contextDescriptor:)",
            "init(contextDescriptor:in:)",
            "offset",
            "parameters",
            "parentParameters",
            "parentRequirements",
            "parentTypePacks",
            "parentValues",
            "requirements",
            "size",
            "typePackHeader",
            "typePacks",
            "uniqueCurrentRequirements",
            "uniqueCurrentRequirementsInProcess",
            "valueHeader",
            "values",
        ]

        let header = """
        // AUTO-GENERATED — DO NOT EDIT.
        // Regenerate via: Scripts/regen-baselines.sh
        // Source fixture: SymbolTestsCore.framework
        """

        let file: SourceFileSyntax = """
        \(raw: header)

        enum GenericContextBaseline {
            static let registeredTestMethodNames: Set<String> = \(literal: registered)

            struct Entry {
                let offset: Int
                let size: Int
                let depth: Int
                let parametersCount: Int
                let requirementsCount: Int
                let hasTypePackHeader: Bool
                let typePacksCount: Int
                let hasValueHeader: Bool
                let valuesCount: Int
                let parentParametersCount: Int
                let parentRequirementsCount: Int
                let parentTypePacksCount: Int
                let parentValuesCount: Int
                let hasConditionalInvertibleProtocolSet: Bool
                let hasConditionalInvertibleProtocolsRequirementsCount: Bool
                let conditionalInvertibleProtocolsRequirementsCount: Int
                let currentParametersCount: Int
                let currentRequirementsCount: Int
                let currentTypePacksCount: Int
                let currentValuesCount: Int
                let allParametersCount: Int
                let allRequirementsCount: Int
                let allTypePacksCount: Int
                let allValuesCount: Int
            }

            static let nonRequirement = \(raw: nonRequirementExpr)

            static let layoutRequirement = \(raw: layoutExpr)

            static let protocolRequirement = \(raw: protocolExpr)

            static let parameterPack = \(raw: packExpr)

            static let invertibleProtocol = \(raw: invertibleExpr)
        }
        """

        let formatted = file.formatted().description + "\n"
        let outputURL = outputDirectory.appendingPathComponent("GenericContextBaseline.swift")
        try formatted.write(to: outputURL, atomically: true, encoding: .utf8)
    }

    private static func requireTypeGenericContext(
        for descriptor: StructDescriptor,
        in machO: some MachOSwiftSectionRepresentableWithCache
    ) throws -> TypeGenericContext {
        try required(try descriptor.typeGenericContext(in: machO))
    }

    private static func emitEntryExpr<H: GenericContextDescriptorHeaderProtocol>(
        for context: TargetGenericContext<H>
    ) -> String {
        let offset = context.offset
        let size = context.size
        let depth = context.depth
        let parametersCount = context.parameters.count
        let requirementsCount = context.requirements.count
        let hasTypePackHeader = context.typePackHeader != nil
        let typePacksCount = context.typePacks.count
        let hasValueHeader = context.valueHeader != nil
        let valuesCount = context.values.count
        let parentParametersCount = context.parentParameters.count
        let parentRequirementsCount = context.parentRequirements.count
        let parentTypePacksCount = context.parentTypePacks.count
        let parentValuesCount = context.parentValues.count
        let hasSet = context.conditionalInvertibleProtocolSet != nil
        let hasCount = context.conditionalInvertibleProtocolsRequirementsCount != nil
        let conditionalReqsCount = context.conditionalInvertibleProtocolsRequirements.count
        let currentParametersCount = context.currentParameters.count
        let currentRequirementsCount = context.currentRequirements.count
        let currentTypePacksCount = context.currentTypePacks.count
        let currentValuesCount = context.currentValues.count
        let allParametersCount = context.allParameters.count
        let allRequirementsCount = context.allRequirements.count
        let allTypePacksCount = context.allTypePacks.count
        let allValuesCount = context.allValues.count

        let expr: ExprSyntax = """
        Entry(
            offset: \(raw: BaselineEmitter.hex(offset)),
            size: \(literal: size),
            depth: \(literal: depth),
            parametersCount: \(literal: parametersCount),
            requirementsCount: \(literal: requirementsCount),
            hasTypePackHeader: \(literal: hasTypePackHeader),
            typePacksCount: \(literal: typePacksCount),
            hasValueHeader: \(literal: hasValueHeader),
            valuesCount: \(literal: valuesCount),
            parentParametersCount: \(literal: parentParametersCount),
            parentRequirementsCount: \(literal: parentRequirementsCount),
            parentTypePacksCount: \(literal: parentTypePacksCount),
            parentValuesCount: \(literal: parentValuesCount),
            hasConditionalInvertibleProtocolSet: \(literal: hasSet),
            hasConditionalInvertibleProtocolsRequirementsCount: \(literal: hasCount),
            conditionalInvertibleProtocolsRequirementsCount: \(literal: conditionalReqsCount),
            currentParametersCount: \(literal: currentParametersCount),
            currentRequirementsCount: \(literal: currentRequirementsCount),
            currentTypePacksCount: \(literal: currentTypePacksCount),
            currentValuesCount: \(literal: currentValuesCount),
            allParametersCount: \(literal: allParametersCount),
            allRequirementsCount: \(literal: allRequirementsCount),
            allTypePacksCount: \(literal: allTypePacksCount),
            allValuesCount: \(literal: allValuesCount)
        )
        """
        return expr.description
    }
}
