import Foundation
import SwiftSyntax
import SwiftSyntaxBuilder
import MachOExtensions
import MachOFoundation
import MachOKit
@testable import MachOSwiftSection

/// Emits `__Baseline__/TypeReferenceBaseline.swift`.
///
/// `TypeReference` is the 4-case sum type covering the runtime's
/// `TypeReferenceKind` (`directTypeDescriptor`/`indirectTypeDescriptor`/
/// `directObjCClassName`/`indirectObjCClass`). Public members are
/// `forKind(_:at:)` (the static constructor that picks the right arm
/// based on the kind byte) and the `resolve` instance methods (MachO +
/// InProcess + ReadingContext overloads collapse to one MethodKey under
/// PublicMemberScanner's name-only key). The `ResolvedTypeReference`
/// enum declared in the same file has only cases, no methods/vars, so
/// it doesn't need its own baseline.
///
/// Fixture: walk `__swift5_types`/`__swift5_types2`, find the record
/// pointing at `Structs.StructTest`, and use its relative offset and
/// `typeKind` to materialize a `TypeReference.directTypeDescriptor(...)`.
/// `forKind(.directTypeDescriptor, at: …)` reproduces the same value.
package enum TypeReferenceBaselineGenerator {
    package static func generate(
        in machO: MachOFile,
        outputDirectory: URL
    ) throws {
        let structTest = try BaselineFixturePicker.struct_StructTest(in: machO)
        let record = try findTypeMetadataRecord(targetingDescriptorOffset: structTest.offset, in: machO)

        // The record's `nominalTypeDescriptor` field offset is the absolute
        // file offset of the field — `record.offset(of:)` already includes
        // `record.offset`. We resolve relative pointers against this address.
        let recordFieldOffset = record.offset(of: \.nominalTypeDescriptor)
        let relativeOffset = record.layout.nominalTypeDescriptor.relativeOffset

        let entryExpr = emitEntryExpr(
            recordFieldOffset: recordFieldOffset,
            relativeOffset: relativeOffset,
            kindRawValue: record.typeKind.rawValue,
            descriptorOffset: structTest.offset
        )

        let registered = [
            "forKind",
            "resolve",
        ]

        let header = """
        // AUTO-GENERATED — DO NOT EDIT.
        // Regenerate via: Scripts/regen-baselines.sh
        // Source fixture: SymbolTestsCore.framework
        """

        let file: SourceFileSyntax = """
        \(raw: header)

        enum TypeReferenceBaseline {
            static let registeredTestMethodNames: Set<String> = \(literal: registered)

            struct Entry {
                let recordFieldOffset: Int
                let relativeOffset: Int32
                let kindRawValue: UInt8
                let resolvedDescriptorOffset: Int
            }

            static let structTestRecord = \(raw: entryExpr)
        }
        """

        let formatted = file.formatted().description + "\n"
        let outputURL = outputDirectory.appendingPathComponent("TypeReferenceBaseline.swift")
        try formatted.write(to: outputURL, atomically: true, encoding: .utf8)
    }

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
        recordFieldOffset: Int,
        relativeOffset: Int32,
        kindRawValue: UInt8,
        descriptorOffset: Int
    ) -> String {
        // `relativeOffset` is a signed 32-bit displacement that can be
        // negative (the descriptor often lives BEFORE the record). Emit
        // as a decimal literal so the baseline's `Int32` field accepts
        // it directly.
        let expr: ExprSyntax = """
        Entry(
            recordFieldOffset: \(raw: BaselineEmitter.hex(recordFieldOffset)),
            relativeOffset: \(literal: relativeOffset),
            kindRawValue: \(raw: BaselineEmitter.hex(kindRawValue)),
            resolvedDescriptorOffset: \(raw: BaselineEmitter.hex(descriptorOffset))
        )
        """
        return expr.description
    }
}
