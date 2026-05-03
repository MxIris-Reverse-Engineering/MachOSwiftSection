import Foundation
import SwiftSyntax
import SwiftSyntaxBuilder
import MachOExtensions
import MachOFoundation
import MachOKit
@testable import MachOSwiftSection

/// Emits `__Baseline__/TypeMetadataRecordBaseline.swift`.
///
/// `TypeMetadataRecord` mirrors `TargetTypeMetadataRecord` from the Swift
/// runtime — one entry per 4-byte slot in `__swift5_types`/`__swift5_types2`.
/// Public members are `offset`/`layout` plus the derived `typeKind` var
/// and the `contextDescriptor` resolution method (MachO + ReadingContext
/// overloads collapse to a single MethodKey under PublicMemberScanner's
/// name-only key).
///
/// We materialize a representative record by walking
/// `__swift5_types`/`__swift5_types2` and picking the first entry whose
/// resolved descriptor is `Structs.StructTest`. The `typeKind` for that
/// record is `.directTypeDescriptor` and `contextDescriptor(in:)`
/// resolves to a `.type(.struct(...))` `ContextDescriptorWrapper`.
package enum TypeMetadataRecordBaselineGenerator {
    package static func generate(
        in machO: MachOFile,
        outputDirectory: URL
    ) throws {
        let structTest = try BaselineFixturePicker.struct_StructTest(in: machO)
        let record = try findTypeMetadataRecord(targetingDescriptorOffset: structTest.offset, in: machO)

        let entryExpr = try emitEntryExpr(for: record, in: machO)

        let registered = [
            "contextDescriptor",
            "layout",
            "offset",
            "typeKind",
        ]

        let header = """
        // AUTO-GENERATED — DO NOT EDIT.
        // Regenerate via: Scripts/regen-baselines.sh
        // Source fixture: SymbolTestsCore.framework
        """

        let file: SourceFileSyntax = """
        \(raw: header)

        enum TypeMetadataRecordBaseline {
            static let registeredTestMethodNames: Set<String> = \(literal: registered)

            struct Entry {
                let offset: Int
                let layoutRelativeOffset: Int32
                let typeKindRawValue: UInt8
                let contextDescriptorOffset: Int
            }

            static let structTestRecord = \(raw: entryExpr)
        }
        """

        let formatted = file.formatted().description + "\n"
        let outputURL = outputDirectory.appendingPathComponent("TypeMetadataRecordBaseline.swift")
        try formatted.write(to: outputURL, atomically: true, encoding: .utf8)
    }

    /// Walks `__swift5_types` (and `__swift5_types2` if present) and returns
    /// the `TypeMetadataRecord` whose resolved descriptor lives at
    /// `targetOffset`. Used to find the record that points at
    /// `Structs.StructTest`.
    private static func findTypeMetadataRecord(
        targetingDescriptorOffset targetOffset: Int,
        in machO: MachOFile
    ) throws -> TypeMetadataRecord {
        for sectionName in [MachOSwiftSectionName.__swift5_types, .__swift5_types2] {
            let section: any SectionProtocol
            do {
                section = try machO.section(for: sectionName)
            } catch {
                continue
            }
            let sectionOffset = if let cache = machO.cache {
                section.address - cache.mainCacheHeader.sharedRegionStart.cast()
            } else {
                section.offset
            }
            let recordSize = TypeMetadataRecord.layoutSize
            let records: [TypeMetadataRecord] = try machO.readWrapperElements(
                offset: sectionOffset,
                numberOfElements: section.size / recordSize
            )
            for record in records {
                guard let resolved = try? record.contextDescriptor(in: machO) else { continue }
                if resolved.contextDescriptor.offset == targetOffset {
                    return record
                }
            }
        }
        throw RequiredError.requiredNonOptional
    }

    private static func emitEntryExpr(
        for record: TypeMetadataRecord,
        in machO: MachOFile
    ) throws -> String {
        let offset = record.offset
        // `relativeOffset` is a signed 32-bit displacement that can be
        // negative (the descriptor often lives BEFORE the record). Emit it
        // as a decimal literal so the baseline `Int32` field accepts it
        // directly; hex-as-zero-extended-UInt64 wouldn't compile.
        let layoutRelativeOffset = record.layout.nominalTypeDescriptor.relativeOffset
        let typeKindRawValue = record.typeKind.rawValue
        let contextDescriptorOffset = try required(record.contextDescriptor(in: machO)).contextDescriptor.offset

        let expr: ExprSyntax = """
        Entry(
            offset: \(raw: BaselineEmitter.hex(offset)),
            layoutRelativeOffset: \(literal: layoutRelativeOffset),
            typeKindRawValue: \(raw: BaselineEmitter.hex(typeKindRawValue)),
            contextDescriptorOffset: \(raw: BaselineEmitter.hex(contextDescriptorOffset))
        )
        """
        return expr.description
    }
}
