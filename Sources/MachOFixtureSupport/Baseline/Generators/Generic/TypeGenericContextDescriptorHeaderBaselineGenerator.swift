import Foundation
import SwiftSyntax
import SwiftSyntaxBuilder
import MachOFoundation
@testable import MachOSwiftSection

/// Emits `__Baseline__/TypeGenericContextDescriptorHeaderBaseline.swift`.
///
/// `TypeGenericContextDescriptorHeader` extends the plain
/// `GenericContextDescriptorHeader` layout with two additional pointers
/// (`instantiationCache` and `defaultInstantiationPattern`) — the
/// runtime-side metadata-instantiation hooks. We pick the header from the
/// generic struct `GenericFieldLayout.GenericStructLayoutRequirement<A: AnyObject>`
/// whose `typeGenericContext` exists and whose generic context exercises a
/// non-trivial layout requirement.
package enum TypeGenericContextDescriptorHeaderBaselineGenerator {
    package static func generate(
        in machO: some MachOSwiftSectionRepresentableWithCache,
        outputDirectory: URL
    ) throws {
        let descriptor = try BaselineFixturePicker.struct_GenericStructLayoutRequirement(in: machO)
        let typeContext = try required(try descriptor.typeGenericContext(in: machO))
        let header = typeContext.header

        let entryExpr = emitEntryExpr(for: header)

        // Public members declared directly in
        // TypeGenericContextDescriptorHeader.swift. `init(layout:offset:)` is
        // filtered as memberwise-synthesized.
        let registered = [
            "layout",
            "offset",
        ]

        let headerComment = """
        // AUTO-GENERATED — DO NOT EDIT.
        // Regenerate via: Scripts/regen-baselines.sh
        // Source fixture: SymbolTestsCore.framework
        """

        let file: SourceFileSyntax = """
        \(raw: headerComment)

        enum TypeGenericContextDescriptorHeaderBaseline {
            static let registeredTestMethodNames: Set<String> = \(literal: registered)

            struct Entry {
                let offset: Int
                let layoutNumParams: UInt16
                let layoutNumRequirements: UInt16
                let layoutNumKeyArguments: UInt16
                let layoutFlagsRawValue: UInt16
            }

            static let genericStructLayoutRequirement = \(raw: entryExpr)
        }
        """

        let formatted = file.formatted().description + "\n"
        let outputURL = outputDirectory.appendingPathComponent("TypeGenericContextDescriptorHeaderBaseline.swift")
        try formatted.write(to: outputURL, atomically: true, encoding: .utf8)
    }

    private static func emitEntryExpr(for header: TypeGenericContextDescriptorHeader) -> String {
        let offset = header.offset
        let numParams = header.layout.numParams
        let numRequirements = header.layout.numRequirements
        let numKeyArguments = header.layout.numKeyArguments
        let flagsRawValue = header.layout.flags.rawValue

        let expr: ExprSyntax = """
        Entry(
            offset: \(raw: BaselineEmitter.hex(offset)),
            layoutNumParams: \(literal: numParams),
            layoutNumRequirements: \(literal: numRequirements),
            layoutNumKeyArguments: \(literal: numKeyArguments),
            layoutFlagsRawValue: \(raw: BaselineEmitter.hex(flagsRawValue))
        )
        """
        return expr.description
    }
}
