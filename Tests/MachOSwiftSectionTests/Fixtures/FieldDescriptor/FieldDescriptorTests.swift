import Foundation
import Testing
import MachOKit
import MachOFoundation
@testable import MachOSwiftSection
@testable import SwiftSectionTestingSupport
import SwiftSectionFixtureSupport

/// Fixture-based Suite for `FieldDescriptor`.
///
/// Each `@Test` exercises one ivar / derived var / reader method declared
/// in `FieldDescriptor.swift`. The cross-reader assertions use
/// counts/presence flags rather than full structural equality — `MangledName`
/// payloads parse to deep ABI trees that we don't deep-compare; presence
/// + cardinality is the meaningful invariant.
///
/// Fixture variants:
///   - `genericStructNonRequirement` — three records (`field1`, `field2`,
///     `field3`)
///   - `structTest` — zero records (StructTest declares only a computed
///     property, no stored fields)
@Suite
@FixtureSuite
final class FieldDescriptorTests: MachOSwiftSectionFixtureTests, @unchecked Sendable {
    // MARK: - Helpers

    private func loadGenericStructFieldDescriptors() throws -> (file: FieldDescriptor, image: FieldDescriptor) {
        let fileDescriptor = try BaselineFixturePicker.struct_GenericStructNonRequirement(in: machOFile)
        let imageDescriptor = try BaselineFixturePicker.struct_GenericStructNonRequirement(in: machOImage)
        let file = try required(try fileDescriptor.fieldDescriptor(in: fileContext))
        let image = try required(try imageDescriptor.fieldDescriptor(in: imageContext))
        return (file: file, image: image)
    }

    private func loadStructTestFieldDescriptors() throws -> (file: FieldDescriptor, image: FieldDescriptor) {
        let fileDescriptor = try BaselineFixturePicker.struct_StructTest(in: machOFile)
        let imageDescriptor = try BaselineFixturePicker.struct_StructTest(in: machOImage)
        let file = try required(try fileDescriptor.fieldDescriptor(in: fileContext))
        let image = try required(try imageDescriptor.fieldDescriptor(in: imageContext))
        return (file: file, image: image)
    }

    // MARK: - Ivars

    @Test func offset() async throws {
        let descriptors = try loadGenericStructFieldDescriptors()
        let result = try acrossAllReaders(descriptors.file, descriptors.image) { $0.offset }
        #expect(result == FieldDescriptorBaseline.genericStructNonRequirement.offset)
    }

    @Test func layout() async throws {
        // Cross-reader equality on the per-field layout values
        // (numFields and fieldRecordSize, kind via raw value).
        let descriptors = try loadGenericStructFieldDescriptors()
        let numFields = try acrossAllReaders(descriptors.file, descriptors.image) { Int($0.layout.numFields) }
        #expect(numFields == FieldDescriptorBaseline.genericStructNonRequirement.layoutNumFields)

        let fieldRecordSize = try acrossAllReaders(descriptors.file, descriptors.image) { Int($0.layout.fieldRecordSize) }
        #expect(fieldRecordSize == FieldDescriptorBaseline.genericStructNonRequirement.layoutFieldRecordSize)

        let kindRaw = try acrossAllReaders(descriptors.file, descriptors.image) { $0.layout.kind }
        #expect(kindRaw == FieldDescriptorBaseline.genericStructNonRequirement.kindRawValue)
    }

    // MARK: - Derived var

    /// The section is walked by size, so a wrong `actualSize` would desync
    /// every later descriptor rather than fail locally. The walk over the
    /// whole section is the real assertion here.
    @Test func actualSize() async throws {
        let genericDescriptors = try loadGenericStructFieldDescriptors()
        let genericSize = try acrossAllReaders(genericDescriptors.file, genericDescriptors.image) { $0.actualSize }
        #expect(genericSize == FieldDescriptorBaseline.genericStructNonRequirement.actualSize)

        let structTestDescriptors = try loadStructTestFieldDescriptors()
        let structTestSize = try acrossAllReaders(structTestDescriptors.file, structTestDescriptors.image) { $0.actualSize }
        #expect(structTestSize == FieldDescriptorBaseline.structTest.actualSize)
        #expect(structTestSize == MemoryLayout<FieldDescriptor.Layout>.size)

        let descriptors = try BaselineFixturePicker.fieldDescriptors(in: machOFile)
        #expect(descriptors.count == FieldDescriptorBaseline.descriptorCount)
        for (earlier, later) in zip(descriptors, descriptors.dropFirst()) {
            #expect(later.offset - earlier.offset == earlier.actualSize)
        }
        // The descriptors a type points at are among the ones the walk finds.
        #expect(descriptors.contains { $0.offset == genericDescriptors.file.offset })
        #expect(descriptors.contains { $0.offset == structTestDescriptors.file.offset })
        #expect(try BaselineFixturePicker.fieldDescriptors(in: machOImage).count == descriptors.count)
    }

    @Test func kind() async throws {
        let descriptors = try loadGenericStructFieldDescriptors()
        let result = try acrossAllReaders(descriptors.file, descriptors.image) { $0.kind.rawValue }
        #expect(result == FieldDescriptorBaseline.genericStructNonRequirement.kindRawValue)
    }

    // MARK: - Reader methods

    @Test func mangledTypeName() async throws {
        let descriptors = try loadGenericStructFieldDescriptors()
        let presence = try acrossAllContexts(descriptors.file, descriptors.image) { descriptor, context in
            (try? descriptor.mangledTypeName(in: context)) != nil
        }
        #expect(presence == FieldDescriptorBaseline.genericStructNonRequirement.hasMangledTypeName)
    }

    @Test func records() async throws {
        // Fixture with non-empty records: GenericStructNonRequirement (3 fields).
        let genericDescriptors = try loadGenericStructFieldDescriptors()
        let genericCount = try acrossAllContexts(genericDescriptors.file, genericDescriptors.image) { descriptor, context in
            try descriptor.records(in: context).count
        }
        #expect(genericCount == FieldDescriptorBaseline.genericStructNonRequirement.recordsCount)

        // Fixture with empty records: StructTest (0 fields, only a computed body).
        let structTestDescriptors = try loadStructTestFieldDescriptors()
        let structTestCount = try acrossAllContexts(structTestDescriptors.file, structTestDescriptors.image) { descriptor, context in
            try descriptor.records(in: context).count
        }
        #expect(structTestCount == FieldDescriptorBaseline.structTest.recordsCount)
    }
}
