import Foundation
import Testing
import MachOFoundation
import MachOKit
@testable import MachOSwiftSection
@testable import MachOTestingSupport
import MachOFixtureSupport

/// Fixture-based Suite for `TypeMetadataRecord`.
///
/// `TypeMetadataRecord` mirrors `TargetTypeMetadataRecord` from the Swift
/// runtime — one entry per 4-byte slot in `__swift5_types`/`__swift5_types2`.
/// We materialize a representative record by walking the section and
/// finding the entry that resolves to `Structs.StructTest`.
@Suite
final class TypeMetadataRecordTests: MachOSwiftSectionFixtureTests, FixtureSuite, @unchecked Sendable {
    static let testedTypeName = "TypeMetadataRecord"
    static var registeredTestMethodNames: Set<String> {
        TypeMetadataRecordBaseline.registeredTestMethodNames
    }

    /// Walks `__swift5_types`/`__swift5_types2` and returns the
    /// `TypeMetadataRecord` whose resolved descriptor lives at
    /// `targetOffset`. Two specializations follow because the `section(for:)`
    /// extension lives on the concrete `MachOFile`/`MachOImage` types
    /// rather than on a shared protocol.
    private func findTypeMetadataRecord(
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

    private func findTypeMetadataRecord(
        targetingDescriptorOffset targetOffset: Int,
        in machO: MachOImage
    ) throws -> TypeMetadataRecord {
        for sectionName in [MachOSwiftSectionName.__swift5_types, .__swift5_types2] {
            let section: any SectionProtocol
            do {
                section = try machO.section(for: sectionName)
            } catch {
                continue
            }
            let vmaddrSlide = try required(machO.vmaddrSlide)
            let start = try required(UnsafeRawPointer(bitPattern: section.address + vmaddrSlide))
            let sectionOffset = machO.ptr.distance(to: start)
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

    private func loadStructTestRecords() throws -> (file: TypeMetadataRecord, image: TypeMetadataRecord) {
        let fileTarget = try BaselineFixturePicker.struct_StructTest(in: machOFile).offset
        let imageTarget = try BaselineFixturePicker.struct_StructTest(in: machOImage).offset
        let file = try findTypeMetadataRecord(targetingDescriptorOffset: fileTarget, in: machOFile)
        let image = try findTypeMetadataRecord(targetingDescriptorOffset: imageTarget, in: machOImage)
        return (file: file, image: image)
    }

    @Test func offset() async throws {
        let (fileRecord, imageRecord) = try loadStructTestRecords()
        let result = try acrossAllReaders(
            file: { fileRecord.offset },
            image: { imageRecord.offset }
        )
        #expect(result == TypeMetadataRecordBaseline.structTestRecord.offset)
    }

    @Test func layout() async throws {
        let (fileRecord, imageRecord) = try loadStructTestRecords()
        // The `relativeOffset` field is stable across readers (it's a raw
        // value stored in the record).
        let result = try acrossAllReaders(
            file: { fileRecord.layout.nominalTypeDescriptor.relativeOffset },
            image: { imageRecord.layout.nominalTypeDescriptor.relativeOffset }
        )
        #expect(result == TypeMetadataRecordBaseline.structTestRecord.layoutRelativeOffset)
    }

    @Test func typeKind() async throws {
        let (fileRecord, imageRecord) = try loadStructTestRecords()
        let result = try acrossAllReaders(
            file: { fileRecord.typeKind.rawValue },
            image: { imageRecord.typeKind.rawValue }
        )
        #expect(result == TypeMetadataRecordBaseline.structTestRecord.typeKindRawValue)
    }

    @Test func contextDescriptor() async throws {
        let (fileRecord, imageRecord) = try loadStructTestRecords()
        // `contextDescriptor(in:)` resolves to the wrapped descriptor; cross-
        // reader equality on the resolved descriptor's offset.
        let result = try acrossAllReaders(
            file: { try required(fileRecord.contextDescriptor(in: machOFile)).contextDescriptor.offset },
            image: { try required(imageRecord.contextDescriptor(in: machOImage)).contextDescriptor.offset }
        )
        #expect(result == TypeMetadataRecordBaseline.structTestRecord.contextDescriptorOffset)

        // ReadingContext-based overload also exercised.
        let imageCtxOffset = try required(imageRecord.contextDescriptor(in: imageContext)).contextDescriptor.offset
        #expect(imageCtxOffset == TypeMetadataRecordBaseline.structTestRecord.contextDescriptorOffset)
    }
}
