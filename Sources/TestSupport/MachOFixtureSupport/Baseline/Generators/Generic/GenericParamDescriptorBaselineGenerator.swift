import Foundation
import SwiftSyntax
import SwiftSyntaxBuilder
import MachOFoundation
@testable import MachOSwiftSection

/// Emits `__Baseline__/GenericParamDescriptorBaseline.swift`.
///
/// `GenericParamDescriptor` is a one-byte descriptor packed into the
/// generic-context payload (immediately after the header). Its layout
/// `rawValue` packs `hasKeyArgument` (high bit) plus a `GenericParamKind`
/// in the low 6 bits.
///
/// Fixture choices:
///   - `GenericStructLayoutRequirement.parameters[0]` — kind=type,
///     hasKeyArgument=true (the `A: AnyObject` parameter that's a key
///     argument for runtime type-resolution).
///   - `ParameterPackRequirementTest.parameters[0]` — kind=typePack,
///     hasKeyArgument=true (the `each Element` pack parameter).
package enum GenericParamDescriptorBaselineGenerator {
    package static func generate(
        in machO: some MachOSwiftSectionRepresentableWithCache,
        outputDirectory: URL
    ) throws {
        let layoutDescriptor = try BaselineFixturePicker.struct_GenericStructLayoutRequirement(in: machO)
        let layoutContext = try required(try layoutDescriptor.typeGenericContext(in: machO))
        let layoutParam = try required(layoutContext.parameters.first)

        let packDescriptor = try BaselineFixturePicker.struct_ParameterPackRequirementTest(in: machO)
        let packContext = try required(try packDescriptor.typeGenericContext(in: machO))
        let packParam = try required(packContext.parameters.first)

        let layoutExpr = emitEntryExpr(for: layoutParam)
        let packExpr = emitEntryExpr(for: packParam)

        // Public members declared directly in GenericParamDescriptor.swift.
        // `init(layout:offset:)` is filtered as memberwise-synthesized.
        let registered = [
            "hasKeyArgument",
            "kind",
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

        enum GenericParamDescriptorBaseline {
            static let registeredTestMethodNames: Set<String> = \(literal: registered)

            struct Entry {
                let offset: Int
                let layoutRawValue: UInt8
                let hasKeyArgument: Bool
                let kindRawValue: UInt8
            }

            static let layoutRequirementParam0 = \(raw: layoutExpr)

            static let parameterPackParam0 = \(raw: packExpr)
        }
        """

        let formatted = file.formatted().description + "\n"
        let outputURL = outputDirectory.appendingPathComponent("GenericParamDescriptorBaseline.swift")
        try formatted.write(to: outputURL, atomically: true, encoding: .utf8)
    }

    private static func emitEntryExpr(for param: GenericParamDescriptor) -> String {
        let offset = param.offset
        let rawValue = param.layout.rawValue
        let hasKeyArgument = param.hasKeyArgument
        let kindRawValue = param.kind.rawValue

        let expr: ExprSyntax = """
        Entry(
            offset: \(raw: BaselineEmitter.hex(offset)),
            layoutRawValue: \(raw: BaselineEmitter.hex(rawValue)),
            hasKeyArgument: \(literal: hasKeyArgument),
            kindRawValue: \(raw: BaselineEmitter.hex(kindRawValue))
        )
        """
        return expr.description
    }
}
