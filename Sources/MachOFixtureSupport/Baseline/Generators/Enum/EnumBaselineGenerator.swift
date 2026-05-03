import Foundation
import SwiftSyntax
import SwiftSyntaxBuilder
import MachOFoundation
@testable import MachOSwiftSection

/// Emits `__Baseline__/EnumBaseline.swift` from the `SymbolTestsCore`
/// fixture via the MachOFile reader.
///
/// `Enum` is the high-level wrapper around `EnumDescriptor`. Like its
/// `Struct`/`Class` counterparts it carries a number of `Optional` ivars
/// gated on the descriptor's flags. The baseline uses the
/// **presence-flag** pattern (no value embedding) for the optionals
/// because the underlying types (`TypeGenericContext`,
/// `SingletonMetadataPointer`, etc.) are not cheaply Equatable; presence
/// + cardinality catches the structural invariant we care about.
///
/// The `noPayloadEnumTest` picker exercises the simplest path: a plain
/// no-payload enum with no metadata initialization or canonical
/// specializations.
package enum EnumBaselineGenerator {
    package static func generate(
        in machO: some MachOSwiftSectionRepresentableWithCache,
        outputDirectory: URL
    ) throws {
        let noPayloadDescriptor = try BaselineFixturePicker.enum_NoPayloadEnumTest(in: machO)

        let noPayloadEnum = try Enum(descriptor: noPayloadDescriptor, in: machO)

        let noPayloadExpr = emitEntryExpr(for: noPayloadEnum)

        // Public ivars + initializers declared directly in Enum.swift.
        // Two `init(descriptor:in:)` overloads (MachO + Context) collapse to
        // a single MethodKey under PublicMemberScanner's name-based key.
        let registered = [
            "canonicalSpecializedMetadatas",
            "canonicalSpecializedMetadatasCachingOnceToken",
            "canonicalSpecializedMetadatasListCount",
            "descriptor",
            "foreignMetadataInitialization",
            "genericContext",
            "init(descriptor:)",
            "init(descriptor:in:)",
            "invertibleProtocolSet",
            "singletonMetadataInitialization",
            "singletonMetadataPointer",
        ]

        let header = """
        // AUTO-GENERATED — DO NOT EDIT.
        // Regenerate via: Scripts/regen-baselines.sh
        // Source fixture: SymbolTestsCore.framework
        """

        let file: SourceFileSyntax = """
        \(raw: header)

        enum EnumBaseline {
            static let registeredTestMethodNames: Set<String> = \(literal: registered)

            struct Entry {
                let descriptorOffset: Int
                let hasGenericContext: Bool
                let hasForeignMetadataInitialization: Bool
                let hasSingletonMetadataInitialization: Bool
                let canonicalSpecializedMetadatasCount: Int
                let hasCanonicalSpecializedMetadatasListCount: Bool
                let hasCanonicalSpecializedMetadatasCachingOnceToken: Bool
                let hasInvertibleProtocolSet: Bool
                let hasSingletonMetadataPointer: Bool
            }

            static let noPayloadEnumTest = \(raw: noPayloadExpr)
        }
        """

        let formatted = file.formatted().description + "\n"
        let outputURL = outputDirectory.appendingPathComponent("EnumBaseline.swift")
        try formatted.write(to: outputURL, atomically: true, encoding: .utf8)
    }

    private static func emitEntryExpr(for instance: Enum) -> String {
        let descriptorOffset = instance.descriptor.offset
        let hasGenericContext = instance.genericContext != nil
        let hasForeignMetadataInitialization = instance.foreignMetadataInitialization != nil
        let hasSingletonMetadataInitialization = instance.singletonMetadataInitialization != nil
        let canonicalSpecializedMetadatasCount = instance.canonicalSpecializedMetadatas.count
        let hasCanonicalSpecializedMetadatasListCount = instance.canonicalSpecializedMetadatasListCount != nil
        let hasCanonicalSpecializedMetadatasCachingOnceToken = instance.canonicalSpecializedMetadatasCachingOnceToken != nil
        let hasInvertibleProtocolSet = instance.invertibleProtocolSet != nil
        let hasSingletonMetadataPointer = instance.singletonMetadataPointer != nil

        let expr: ExprSyntax = """
        Entry(
            descriptorOffset: \(raw: BaselineEmitter.hex(descriptorOffset)),
            hasGenericContext: \(literal: hasGenericContext),
            hasForeignMetadataInitialization: \(literal: hasForeignMetadataInitialization),
            hasSingletonMetadataInitialization: \(literal: hasSingletonMetadataInitialization),
            canonicalSpecializedMetadatasCount: \(literal: canonicalSpecializedMetadatasCount),
            hasCanonicalSpecializedMetadatasListCount: \(literal: hasCanonicalSpecializedMetadatasListCount),
            hasCanonicalSpecializedMetadatasCachingOnceToken: \(literal: hasCanonicalSpecializedMetadatasCachingOnceToken),
            hasInvertibleProtocolSet: \(literal: hasInvertibleProtocolSet),
            hasSingletonMetadataPointer: \(literal: hasSingletonMetadataPointer)
        )
        """
        return expr.description
    }
}
