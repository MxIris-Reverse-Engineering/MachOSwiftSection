import Foundation
import SwiftSyntax
import SwiftSyntaxBuilder
import MachOFoundation
@testable import MachOSwiftSection

/// Emits `__Baseline__/ClassDescriptorBaseline.swift` from the
/// `SymbolTestsCore` fixture via the MachOFile reader.
///
/// `ClassDescriptor` is the largest descriptor type in the Type/Class group:
/// it carries the layout scalar fields plus a long set of derived `var`s
/// (kind-specific flag accessors) and methods (`resilientMetadataBounds`,
/// `superclassTypeMangledName`). Members declared elsewhere — `name(in:)`,
/// `fields(in:)` etc. — live on `TypeContextDescriptorProtocol` and are
/// covered by Task 9, not here.
///
/// Two pickers feed the baseline: the plain `Classes.ClassTest` (no
/// superclass, no resilient stub) and `Classes.SubclassTest` (has a
/// non-nil superclass mangled name).
package enum ClassDescriptorBaselineGenerator {
    package static func generate(
        in machO: some MachOSwiftSectionRepresentableWithCache,
        outputDirectory: URL
    ) throws {
        let classTest = try BaselineFixturePicker.class_ClassTest(in: machO)
        let subclassTest = try BaselineFixturePicker.class_SubclassTest(in: machO)

        let classTestExpr = try emitEntryExpr(for: classTest, in: machO)
        let subclassTestExpr = try emitEntryExpr(for: subclassTest, in: machO)

        // Members directly declared in ClassDescriptor.swift (across the main
        // body and three same-file extensions). Overload pairs (MachO +
        // ReadingContext) collapse to a single MethodKey under the scanner's
        // name-based deduplication.
        let registered = [
            "areImmediateMembersNegative",
            "hasDefaultOverrideTable",
            "hasFieldOffsetVector",
            "hasObjCResilientClassStub",
            "hasOverrideTable",
            "hasResilientSuperclass",
            "hasVTable",
            "immediateMemberSize",
            "isActor",
            "isDefaultActor",
            "layout",
            "nonResilientImmediateMembersOffset",
            "offset",
            "resilientMetadataBounds",
            "resilientSuperclassReferenceKind",
            "superclassTypeMangledName",
        ]

        let header = """
        // AUTO-GENERATED — DO NOT EDIT.
        // Regenerate via: Scripts/regen-baselines.sh
        // Source fixture: SymbolTestsCore.framework
        """

        let file: SourceFileSyntax = """
        \(raw: header)

        enum ClassDescriptorBaseline {
            static let registeredTestMethodNames: Set<String> = \(literal: registered)

            struct Entry {
                let offset: Int
                let layoutNumFields: Int
                let layoutFieldOffsetVectorOffset: Int
                let layoutNumImmediateMembers: Int
                let layoutFlagsRawValue: UInt32
                let hasFieldOffsetVector: Bool
                let hasDefaultOverrideTable: Bool
                let isActor: Bool
                let isDefaultActor: Bool
                let hasVTable: Bool
                let hasOverrideTable: Bool
                let hasResilientSuperclass: Bool
                let areImmediateMembersNegative: Bool
                let hasObjCResilientClassStub: Bool
                let hasSuperclassTypeMangledName: Bool
                let immediateMemberSize: UInt
                let nonResilientImmediateMembersOffset: Int32
            }

            static let classTest = \(raw: classTestExpr)

            static let subclassTest = \(raw: subclassTestExpr)
        }
        """

        let formatted = file.formatted().description + "\n"
        let outputURL = outputDirectory.appendingPathComponent("ClassDescriptorBaseline.swift")
        try formatted.write(to: outputURL, atomically: true, encoding: .utf8)
    }

    private static func emitEntryExpr(
        for descriptor: ClassDescriptor,
        in machO: some MachOSwiftSectionRepresentableWithCache
    ) throws -> String {
        let offset = descriptor.offset
        let numFields = Int(descriptor.layout.numFields)
        let fieldOffsetVectorOffset = Int(descriptor.layout.fieldOffsetVectorOffset)
        let numImmediateMembers = Int(descriptor.layout.numImmediateMembers)
        let flagsRaw = descriptor.layout.flags.rawValue
        let hasFieldOffsetVector = descriptor.hasFieldOffsetVector
        let hasDefaultOverrideTable = descriptor.hasDefaultOverrideTable
        let isActor = descriptor.isActor
        let isDefaultActor = descriptor.isDefaultActor
        let hasVTable = descriptor.hasVTable
        let hasOverrideTable = descriptor.hasOverrideTable
        let hasResilientSuperclass = descriptor.hasResilientSuperclass
        let areImmediateMembersNegative = descriptor.areImmediateMembersNegative
        let hasObjCResilientClassStub = descriptor.hasObjCResilientClassStub
        let hasSuperclassTypeMangledName = (try descriptor.superclassTypeMangledName(in: machO)) != nil
        let immediateMemberSize = UInt(descriptor.immediateMemberSize)
        let nonResilientImmediateMembersOffset = descriptor.nonResilientImmediateMembersOffset

        let expr: ExprSyntax = """
        Entry(
            offset: \(raw: BaselineEmitter.hex(offset)),
            layoutNumFields: \(literal: numFields),
            layoutFieldOffsetVectorOffset: \(literal: fieldOffsetVectorOffset),
            layoutNumImmediateMembers: \(literal: numImmediateMembers),
            layoutFlagsRawValue: \(raw: BaselineEmitter.hex(flagsRaw)),
            hasFieldOffsetVector: \(literal: hasFieldOffsetVector),
            hasDefaultOverrideTable: \(literal: hasDefaultOverrideTable),
            isActor: \(literal: isActor),
            isDefaultActor: \(literal: isDefaultActor),
            hasVTable: \(literal: hasVTable),
            hasOverrideTable: \(literal: hasOverrideTable),
            hasResilientSuperclass: \(literal: hasResilientSuperclass),
            areImmediateMembersNegative: \(literal: areImmediateMembersNegative),
            hasObjCResilientClassStub: \(literal: hasObjCResilientClassStub),
            hasSuperclassTypeMangledName: \(literal: hasSuperclassTypeMangledName),
            immediateMemberSize: \(raw: BaselineEmitter.hex(immediateMemberSize)),
            nonResilientImmediateMembersOffset: \(literal: nonResilientImmediateMembersOffset)
        )
        """
        return expr.description
    }
}
