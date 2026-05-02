import Foundation
import SwiftSyntax
import SwiftSyntaxBuilder
import MachOFoundation
@testable import MachOSwiftSection

/// Emits `__Baseline__/StructBaseline.swift` from the `SymbolTestsCore`
/// fixture via the MachOFile reader.
///
/// `Struct` is the high-level wrapper around `StructDescriptor`. Beyond the
/// descriptor itself, each ivar is `Optional`/array-shaped depending on
/// flags. The baseline `Entry` only records *presence/absence* of each
/// optional member and the count of canonical specializations; richer payload
/// shapes (e.g. `TypeGenericContext`) are not stable Swift literals worth
/// embedding here, so we let the cross-reader equality assertions guard them
/// at runtime.
package enum StructBaselineGenerator {
    package static func generate(
        in machO: some MachOSwiftSectionRepresentableWithCache,
        outputDirectory: URL
    ) throws {
        let structTestDescriptor = try BaselineFixturePicker.struct_StructTest(in: machO)
        let genericStructDescriptor = try BaselineFixturePicker.struct_GenericStructNonRequirement(in: machO)

        let structTestStruct = try Struct(descriptor: structTestDescriptor, in: machO)
        let genericStructStruct = try Struct(descriptor: genericStructDescriptor, in: machO)

        let structTestExpr = emitEntryExpr(for: structTestStruct)
        let genericStructExpr = emitEntryExpr(for: genericStructStruct)

        // Public members declared directly in Struct.swift, per scanner output.
        // Two `init(descriptor:in:)` overloads (MachO + Context) collapse to one
        // MethodKey under PublicMemberScanner's name-based deduplication.
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
        // Regenerate via: swift run baseline-generator
        // Source fixture: SymbolTestsCore.framework
        """

        let file: SourceFileSyntax = """
        \(raw: header)

        enum StructBaseline {
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

            static let structTest = \(raw: structTestExpr)

            static let genericStructNonRequirement = \(raw: genericStructExpr)
        }
        """

        let formatted = file.formatted().description + "\n"
        let outputURL = outputDirectory.appendingPathComponent("StructBaseline.swift")
        try formatted.write(to: outputURL, atomically: true, encoding: .utf8)
    }

    private static func emitEntryExpr(for instance: Struct) -> String {
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
