import Foundation
import SwiftSyntax
import SwiftSyntaxBuilder
import MachOFoundation
@testable import MachOSwiftSection

/// Emits `__Baseline__/GenericContextDescriptorHeaderBaseline.swift`.
///
/// `GenericContextDescriptorHeader` is the base 8-byte header carried at the
/// start of every `GenericContext` payload (4 × `UInt16`: `numParams`,
/// `numRequirements`, `numKeyArguments`, `flags`). The `TypeGenericContext`
/// variant subclasses this layout with two additional `RelativeOffset`
/// pointers and is exercised separately by the
/// `TypeGenericContextDescriptorHeader` Suite.
///
/// We pick the header from the first extension descriptor with a generic
/// context — extensions on generic types (e.g.
/// `extension Extensions.ExtensionBaseStruct where Element: Equatable`)
/// surface a `GenericContext` whose `Header` is the plain
/// `GenericContextDescriptorHeader`.
package enum GenericContextDescriptorHeaderBaselineGenerator {
    package static func generate(
        in machO: some MachOSwiftSectionRepresentableWithCache,
        outputDirectory: URL
    ) throws {
        let header = try pickHeader(in: machO)
        let entryExpr = emitEntryExpr(for: header)

        // Public members declared directly in GenericContextDescriptorHeader.swift.
        // `init(layout:offset:)` is filtered as memberwise-synthesized.
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

        enum GenericContextDescriptorHeaderBaseline {
            static let registeredTestMethodNames: Set<String> = \(literal: registered)

            struct Entry {
                let offset: Int
                let layoutNumParams: UInt16
                let layoutNumRequirements: UInt16
                let layoutNumKeyArguments: UInt16
                let layoutFlagsRawValue: UInt16
            }

            static let firstExtensionGenericHeader = \(raw: entryExpr)
        }
        """

        let formatted = file.formatted().description + "\n"
        let outputURL = outputDirectory.appendingPathComponent("GenericContextDescriptorHeaderBaseline.swift")
        try formatted.write(to: outputURL, atomically: true, encoding: .utf8)
    }

    /// Picks a `GenericContextDescriptorHeader` from the first generic
    /// extension context in the fixture. Walks the parent chain of every
    /// type descriptor until an `ExtensionContextDescriptor` whose
    /// `isGeneric` flag is set is found, then materializes its
    /// `GenericContext` and returns the header. Falls back to
    /// `RequiredError` if the fixture has no generic extension at all.
    package static func pickHeader(
        in machO: some MachOSwiftSectionRepresentableWithCache
    ) throws -> GenericContextDescriptorHeader {
        for typeDescriptor in try machO.swift.contextDescriptors {
            var current: SymbolOrElement<ContextDescriptorWrapper>? = try typeDescriptor.parent(in: machO)
            while let cursor = current {
                if let resolved = cursor.resolved {
                    if let ext = resolved.extensionContextDescriptor,
                       ext.flags.isGeneric,
                       let context = try ext.genericContext(in: machO) {
                        return context.header
                    }
                    current = try resolved.parent(in: machO)
                } else {
                    current = nil
                }
            }
        }
        throw RequiredError.requiredNonOptional
    }

    private static func emitEntryExpr(for header: GenericContextDescriptorHeader) -> String {
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
