import Foundation
import SwiftSyntax
import SwiftSyntaxBuilder
import MachOFoundation
@testable import MachOSwiftSection

/// Emits `__Baseline__/TypeContextDescriptorProtocolBaseline.swift`.
///
/// Per the protocol-extension attribution rule (see `BaselineGenerator.swift`),
/// `metadataAccessorFunction`, `fieldDescriptor`, `genericContext`,
/// `typeGenericContext` and the 7 derived booleans
/// (`hasSingletonMetadataInitialization`, `hasForeignMetadataInitialization`,
/// `hasImportInfo`,
/// `hasCanonicalMetadataPrespecializationsOrSingletonMetadataPointer`,
/// `hasLayoutString`, `hasCanonicalMetadataPrespecializations`,
/// `hasSingletonMetadataPointer`) live in
/// `extension TypeContextDescriptorProtocol { ... }` and attribute to the
/// protocol, not to concrete descriptors like `StructDescriptor`/
/// `EnumDescriptor`/`ClassDescriptor`.
///
/// Picker: `Structs.StructTest`. The booleans all read `false` for this
/// non-generic, no-import struct; `metadataAccessorFunction` returns `nil`
/// when the picker is read out of `MachOFile` (the accessor is only
/// reachable from a loaded `MachOImage`); `fieldDescriptor` resolves to a
/// non-trivial `FieldDescriptor` we record by presence; `genericContext`
/// returns `nil` (struct is non-generic).
package enum TypeContextDescriptorProtocolBaselineGenerator {
    package static func generate(
        in machO: some MachOSwiftSectionRepresentableWithCache,
        outputDirectory: URL
    ) throws {
        let descriptor = try BaselineFixturePicker.struct_StructTest(in: machO)

        let entryExpr = try emitEntryExpr(for: descriptor, in: machO)

        // Public members declared in `extension TypeContextDescriptorProtocol { ... }`
        // (across the body, an in-process variant, and a ReadingContext variant).
        // Overload pairs collapse to single MethodKey entries under
        // PublicMemberScanner's name-only key.
        let registered = [
            "fieldDescriptor",
            "genericContext",
            "hasCanonicalMetadataPrespecializations",
            "hasCanonicalMetadataPrespecializationsOrSingletonMetadataPointer",
            "hasForeignMetadataInitialization",
            "hasImportInfo",
            "hasLayoutString",
            "hasSingletonMetadataInitialization",
            "hasSingletonMetadataPointer",
            "metadataAccessorFunction",
            "typeGenericContext",
        ]

        let header = """
        // AUTO-GENERATED — DO NOT EDIT.
        // Regenerate via: Scripts/regen-baselines.sh
        // Source fixture: SymbolTestsCore.framework
        //
        // Live FieldDescriptor / GenericContext / MetadataAccessorFunction
        // payloads aren't embedded as literals; the companion Suite
        // (TypeContextDescriptorProtocolTests) verifies the methods produce
        // cross-reader-consistent results at runtime against the presence
        // flags recorded here.
        """

        let file: SourceFileSyntax = """
        \(raw: header)

        enum TypeContextDescriptorProtocolBaseline {
            static let registeredTestMethodNames: Set<String> = \(literal: registered)

            struct Entry {
                let hasFieldDescriptor: Bool
                let hasGenericContext: Bool
                let hasTypeGenericContext: Bool
                let hasSingletonMetadataInitialization: Bool
                let hasForeignMetadataInitialization: Bool
                let hasImportInfo: Bool
                let hasCanonicalMetadataPrespecializationsOrSingletonMetadataPointer: Bool
                let hasLayoutString: Bool
                let hasCanonicalMetadataPrespecializations: Bool
                let hasSingletonMetadataPointer: Bool
            }

            static let structTest = \(raw: entryExpr)
        }
        """

        let formatted = file.formatted().description + "\n"
        let outputURL = outputDirectory.appendingPathComponent("TypeContextDescriptorProtocolBaseline.swift")
        try formatted.write(to: outputURL, atomically: true, encoding: .utf8)
    }

    private static func emitEntryExpr(
        for descriptor: StructDescriptor,
        in machO: some MachOSwiftSectionRepresentableWithCache
    ) throws -> String {
        let hasFieldDescriptor = (try? descriptor.fieldDescriptor(in: machO)) != nil
        let hasGenericContext = (try descriptor.genericContext(in: machO)) != nil
        let hasTypeGenericContext = (try descriptor.typeGenericContext(in: machO)) != nil
        let hasSingletonMetadataInitialization = descriptor.hasSingletonMetadataInitialization
        let hasForeignMetadataInitialization = descriptor.hasForeignMetadataInitialization
        let hasImportInfo = descriptor.hasImportInfo
        let hasCanonicalMetadataPrespecializationsOrSingletonMetadataPointer = descriptor.hasCanonicalMetadataPrespecializationsOrSingletonMetadataPointer
        let hasLayoutString = descriptor.hasLayoutString
        let hasCanonicalMetadataPrespecializations = descriptor.hasCanonicalMetadataPrespecializations
        let hasSingletonMetadataPointer = descriptor.hasSingletonMetadataPointer

        let expr: ExprSyntax = """
        Entry(
            hasFieldDescriptor: \(literal: hasFieldDescriptor),
            hasGenericContext: \(literal: hasGenericContext),
            hasTypeGenericContext: \(literal: hasTypeGenericContext),
            hasSingletonMetadataInitialization: \(literal: hasSingletonMetadataInitialization),
            hasForeignMetadataInitialization: \(literal: hasForeignMetadataInitialization),
            hasImportInfo: \(literal: hasImportInfo),
            hasCanonicalMetadataPrespecializationsOrSingletonMetadataPointer: \(literal: hasCanonicalMetadataPrespecializationsOrSingletonMetadataPointer),
            hasLayoutString: \(literal: hasLayoutString),
            hasCanonicalMetadataPrespecializations: \(literal: hasCanonicalMetadataPrespecializations),
            hasSingletonMetadataPointer: \(literal: hasSingletonMetadataPointer)
        )
        """
        return expr.description
    }
}
