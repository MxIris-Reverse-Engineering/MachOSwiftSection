import Foundation
import SwiftSyntax
import SwiftSyntaxBuilder
import MachOFoundation
@testable import MachOSwiftSection

// Pattern note: this generator and its corresponding Suite use **presence flags**
// (`hasGenericContext: Bool`, etc.) for heavy optional ivars rather than full
// structural equality. Rationale: the underlying types (TypeGenericContext,
// SingletonMetadataPointer, ...) are non-Equatable and would require deep,
// brittle equality assertions. Presence + cardinality catches the structural
// invariant we care about — that the descriptor's optional fields appear when
// expected and not when not.
//
// Limitation: a regression that produces a *wrong-shaped* generic context (with
// the optional field set but its contents corrupted) is not caught by these
// tests. Where deeper structural assertions matter, Tasks 12 (Generic/) and 14
// (Metadata/) will add type-specific tests.

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
        // Regenerate via: Scripts/regen-baselines.sh
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
