import Foundation
import SwiftSyntax
import SwiftSyntaxBuilder
import MachOExtensions
import MachOFoundation
@testable import MachOSwiftSection

/// Emits `__Baseline__/TypeContextDescriptorFlagsBaseline.swift`.
///
/// `TypeContextDescriptorFlags` is the kind-specific 16-bit `FlagSet`
/// reachable via `ContextDescriptorFlags.kindSpecificFlags?.typeFlags`. It
/// carries both kind-agnostic flag accessors (`hasImportInfo`,
/// `hasLayoutString`, `noMetadataInitialization`,
/// `hasSingletonMetadataInitialization`,
/// `hasForeignMetadataInitialization`,
/// `hasCanonicalMetadataPrespecializationsOrSingletonMetadataPointer`) and
/// class-specific accessors (`classIsActor`, `classIsDefaultActor`,
/// `classHasVTable`, `classHasOverrideTable`, `classHasResilientSuperclass`,
/// `classHasDefaultOverrideTable`,
/// `classResilientSuperclassReferenceKind`,
/// `classAreImmdiateMembersNegative`).
///
/// Two pickers feed the baseline so each branch is witnessed:
///   - `Structs.StructTest` for the kind-agnostic accessors (and to confirm
///     the class-only flags read as `false` for non-class kinds).
///   - `Classes.ClassTest` for the class-specific accessors (so
///     `classHasVTable` / `classResilientSuperclassReferenceKind` etc. have
///     a real-world value to assert).
package enum TypeContextDescriptorFlagsBaselineGenerator {
    package static func generate(
        in machO: some MachOSwiftSectionRepresentableWithCache,
        outputDirectory: URL
    ) throws {
        let structDescriptor = try BaselineFixturePicker.struct_StructTest(in: machO)
        let structFlags = try required(structDescriptor.layout.flags.kindSpecificFlags?.typeFlags)
        let structEntryExpr = emitEntryExpr(for: structFlags)

        let classDescriptor = try BaselineFixturePicker.class_ClassTest(in: machO)
        let classFlags = try required(classDescriptor.layout.flags.kindSpecificFlags?.typeFlags)
        let classEntryExpr = emitEntryExpr(for: classFlags)

        // Public members declared directly in TypeContextDescriptorFlags.swift.
        let registered = [
            "classAreImmdiateMembersNegative",
            "classHasDefaultOverrideTable",
            "classHasOverrideTable",
            "classHasResilientSuperclass",
            "classHasVTable",
            "classIsActor",
            "classIsDefaultActor",
            "classResilientSuperclassReferenceKind",
            "hasCanonicalMetadataPrespecializationsOrSingletonMetadataPointer",
            "hasForeignMetadataInitialization",
            "hasImportInfo",
            "hasLayoutString",
            "hasSingletonMetadataInitialization",
            "init(rawValue:)",
            "noMetadataInitialization",
            "rawValue",
        ]

        let header = """
        // AUTO-GENERATED — DO NOT EDIT.
        // Regenerate via: Scripts/regen-baselines.sh
        // Source fixture: SymbolTestsCore.framework
        """

        let file: SourceFileSyntax = """
        \(raw: header)

        enum TypeContextDescriptorFlagsBaseline {
            static let registeredTestMethodNames: Set<String> = \(literal: registered)

            struct Entry {
                let rawValue: UInt16
                let noMetadataInitialization: Bool
                let hasSingletonMetadataInitialization: Bool
                let hasForeignMetadataInitialization: Bool
                let hasImportInfo: Bool
                let hasCanonicalMetadataPrespecializationsOrSingletonMetadataPointer: Bool
                let hasLayoutString: Bool
                let classHasDefaultOverrideTable: Bool
                let classIsActor: Bool
                let classIsDefaultActor: Bool
                let classResilientSuperclassReferenceKindRawValue: UInt8
                let classAreImmdiateMembersNegative: Bool
                let classHasResilientSuperclass: Bool
                let classHasOverrideTable: Bool
                let classHasVTable: Bool
            }

            static let structTest = \(raw: structEntryExpr)

            static let classTest = \(raw: classEntryExpr)
        }
        """

        let formatted = file.formatted().description + "\n"
        let outputURL = outputDirectory.appendingPathComponent("TypeContextDescriptorFlagsBaseline.swift")
        try formatted.write(to: outputURL, atomically: true, encoding: .utf8)
    }

    private static func emitEntryExpr(for flags: TypeContextDescriptorFlags) -> String {
        let rawValue = flags.rawValue
        let noMetadataInitialization = flags.noMetadataInitialization
        let hasSingletonMetadataInitialization = flags.hasSingletonMetadataInitialization
        let hasForeignMetadataInitialization = flags.hasForeignMetadataInitialization
        let hasImportInfo = flags.hasImportInfo
        let hasCanonicalMetadataPrespecializationsOrSingletonMetadataPointer = flags.hasCanonicalMetadataPrespecializationsOrSingletonMetadataPointer
        let hasLayoutString = flags.hasLayoutString
        let classHasDefaultOverrideTable = flags.classHasDefaultOverrideTable
        let classIsActor = flags.classIsActor
        let classIsDefaultActor = flags.classIsDefaultActor
        let classResilientSuperclassReferenceKindRawValue = flags.classResilientSuperclassReferenceKind.rawValue
        let classAreImmdiateMembersNegative = flags.classAreImmdiateMembersNegative
        let classHasResilientSuperclass = flags.classHasResilientSuperclass
        let classHasOverrideTable = flags.classHasOverrideTable
        let classHasVTable = flags.classHasVTable

        let expr: ExprSyntax = """
        Entry(
            rawValue: \(raw: BaselineEmitter.hex(rawValue)),
            noMetadataInitialization: \(literal: noMetadataInitialization),
            hasSingletonMetadataInitialization: \(literal: hasSingletonMetadataInitialization),
            hasForeignMetadataInitialization: \(literal: hasForeignMetadataInitialization),
            hasImportInfo: \(literal: hasImportInfo),
            hasCanonicalMetadataPrespecializationsOrSingletonMetadataPointer: \(literal: hasCanonicalMetadataPrespecializationsOrSingletonMetadataPointer),
            hasLayoutString: \(literal: hasLayoutString),
            classHasDefaultOverrideTable: \(literal: classHasDefaultOverrideTable),
            classIsActor: \(literal: classIsActor),
            classIsDefaultActor: \(literal: classIsDefaultActor),
            classResilientSuperclassReferenceKindRawValue: \(raw: BaselineEmitter.hex(classResilientSuperclassReferenceKindRawValue)),
            classAreImmdiateMembersNegative: \(literal: classAreImmdiateMembersNegative),
            classHasResilientSuperclass: \(literal: classHasResilientSuperclass),
            classHasOverrideTable: \(literal: classHasOverrideTable),
            classHasVTable: \(literal: classHasVTable)
        )
        """
        return expr.description
    }
}
