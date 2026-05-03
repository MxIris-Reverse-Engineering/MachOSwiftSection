import Foundation
import Testing
import MachOFoundation
import MachOKit
@testable import MachOSwiftSection
@testable import MachOTestingSupport
import MachOFixtureSupport

/// Fixture-based Suite for `TypeReference`.
///
/// `TypeReference` is the 4-case sum type covering the runtime's
/// `TypeReferenceKind` arms. Public members are `forKind(_:at:)` (the
/// static constructor that picks the right arm based on the kind byte)
/// and the `resolve` instance methods (MachO + InProcess + ReadingContext
/// overloads collapse to one MethodKey under PublicMemberScanner's
/// name-only key). The `ResolvedTypeReference` enum declared in the same
/// file has only cases — no methods/vars — so it doesn't need its own Suite.
///
/// Fixture: walk `__swift5_types`/`__swift5_types2`, find the record
/// pointing at `Structs.StructTest`, and use its relative offset and
/// `typeKind` byte to materialize a `TypeReference.directTypeDescriptor(...)`
/// via `forKind(.directTypeDescriptor, at: …)`.
@Suite
final class TypeReferenceTests: MachOSwiftSectionFixtureTests, FixtureSuite, @unchecked Sendable {
    static let testedTypeName = "TypeReference"
    static var registeredTestMethodNames: Set<String> {
        TypeReferenceBaseline.registeredTestMethodNames
    }

    /// Find the `TypeMetadataRecord` for `Structs.StructTest` and project
    /// its (record-field-offset, relative-offset, kind) tuple — the
    /// inputs to `TypeReference.forKind(_:at:)`. Two specializations
    /// follow because the `section(for:)` extension lives on the concrete
    /// `MachOFile`/`MachOImage` types rather than on a shared protocol.
    private func loadStructTestReferenceData(
        in machO: MachOFile
    ) throws -> (recordFieldOffset: Int, relativeOffset: Int32, kind: TypeReferenceKind) {
        let target = try BaselineFixturePicker.struct_StructTest(in: machO).offset
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
                if resolved.contextDescriptor.offset == target {
                    let fieldOffset = record.offset(of: \.nominalTypeDescriptor)
                    let relativeOffset = record.layout.nominalTypeDescriptor.relativeOffset
                    return (fieldOffset, relativeOffset, record.typeKind)
                }
            }
        }
        throw RequiredError.requiredNonOptional
    }

    private func loadStructTestReferenceData(
        in machO: MachOImage
    ) throws -> (recordFieldOffset: Int, relativeOffset: Int32, kind: TypeReferenceKind) {
        let target = try BaselineFixturePicker.struct_StructTest(in: machO).offset
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
                if resolved.contextDescriptor.offset == target {
                    let fieldOffset = record.offset(of: \.nominalTypeDescriptor)
                    let relativeOffset = record.layout.nominalTypeDescriptor.relativeOffset
                    return (fieldOffset, relativeOffset, record.typeKind)
                }
            }
        }
        throw RequiredError.requiredNonOptional
    }

    @Test func forKind() async throws {
        let fileData = try loadStructTestReferenceData(in: machOFile)
        let imageData = try loadStructTestReferenceData(in: machOImage)

        // Construct via `forKind(_:at:)` — confirms the static factory
        // picks the right arm for `.directTypeDescriptor`.
        let fileRef = TypeReference.forKind(fileData.kind, at: fileData.relativeOffset)
        let imageRef = TypeReference.forKind(imageData.kind, at: imageData.relativeOffset)

        if case .directTypeDescriptor = fileRef {} else { Issue.record("expected .directTypeDescriptor arm") }
        if case .directTypeDescriptor = imageRef {} else { Issue.record("expected .directTypeDescriptor arm") }

        #expect(fileData.kind.rawValue == TypeReferenceBaseline.structTestRecord.kindRawValue)
        #expect(imageData.kind.rawValue == TypeReferenceBaseline.structTestRecord.kindRawValue)
        #expect(fileData.relativeOffset == TypeReferenceBaseline.structTestRecord.relativeOffset)
        #expect(imageData.relativeOffset == TypeReferenceBaseline.structTestRecord.relativeOffset)
    }

    @Test func resolve() async throws {
        let fileData = try loadStructTestReferenceData(in: machOFile)
        let imageData = try loadStructTestReferenceData(in: machOImage)

        let fileRef = TypeReference.forKind(fileData.kind, at: fileData.relativeOffset)
        let imageRef = TypeReference.forKind(imageData.kind, at: imageData.relativeOffset)

        let fileResolved = try fileRef.resolve(at: fileData.recordFieldOffset, in: machOFile)
        let imageResolved = try imageRef.resolve(at: imageData.recordFieldOffset, in: machOImage)

        // The resolved `directTypeDescriptor` arm should round-trip to the
        // same descriptor we picked from the section.
        if case .directTypeDescriptor(let wrapper) = fileResolved {
            #expect(wrapper?.contextDescriptor.offset == TypeReferenceBaseline.structTestRecord.resolvedDescriptorOffset)
        } else {
            Issue.record("expected resolved .directTypeDescriptor")
        }
        if case .directTypeDescriptor(let wrapper) = imageResolved {
            #expect(wrapper?.contextDescriptor.offset == TypeReferenceBaseline.structTestRecord.resolvedDescriptorOffset)
        } else {
            Issue.record("expected resolved .directTypeDescriptor")
        }

        // ReadingContext-based overload also exercised.
        let imageCtxResolved = try imageRef.resolve(at: imageData.recordFieldOffset, in: imageContext)
        if case .directTypeDescriptor(let wrapper) = imageCtxResolved {
            #expect(wrapper?.contextDescriptor.offset == TypeReferenceBaseline.structTestRecord.resolvedDescriptorOffset)
        } else {
            Issue.record("expected resolved .directTypeDescriptor")
        }
    }
}
