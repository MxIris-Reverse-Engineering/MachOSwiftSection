import Foundation
import Testing
import MachOFoundation
@testable import MachOSwiftSection
@testable import SwiftSectionTestingSupport
import SwiftSectionFixtureSupport

/// Fixture-based Suite for `MultiPayloadEnumDescriptor`.
///
/// `MultiPayloadEnumDescriptor` lives in the `__swift5_mpenum` section and
/// carries variable-length spare-bit metadata for multi-payload enums.
/// The Suite covers:
///   - the `offset` / `layout` ivars (the `init(layout:offset:)` initializer
///     is filtered as memberwise-synthesized)
///   - method overloads that resolve runtime data (`mangledTypeName`,
///     `contents`, `payloadSpareBits`, `payloadSpareBitMaskByteOffset`,
///     `payloadSpareBitMaskByteCount`)
///   - derived bit-twiddling accessors (`contentsSizeInWord`, `flags`,
///     `usesPayloadSpareBits`, the index family, and the
///     `TopLevelDescriptor` extension's `actualSize`)
///
/// All assertions use the multi-payload picker
/// (`Enums.MultiPayloadEnumTests`).
@Suite
@FixtureSuite
final class MultiPayloadEnumDescriptorTests: MachOSwiftSectionFixtureTests, @unchecked Sendable {
    private func loadDescriptors() throws -> (file: MultiPayloadEnumDescriptor, image: MultiPayloadEnumDescriptor) {
        let file = try BaselineFixturePicker.multiPayloadEnumDescriptor_MultiPayloadEnumTest(in: machOFile)
        let image = try BaselineFixturePicker.multiPayloadEnumDescriptor_MultiPayloadEnumTest(in: machOImage)
        return (file: file, image: image)
    }

    // MARK: - Layout / offset

    @Test func offset() async throws {
        let (fileSubject, imageSubject) = try loadDescriptors()
        let result = try acrossAllReaders(fileSubject, imageSubject) { $0.offset }
        #expect(result == MultiPayloadEnumDescriptorBaseline.multiPayloadEnumTest.offset)
    }

    @Test func layout() async throws {
        let (fileSubject, imageSubject) = try loadDescriptors()
        let sizeFlags = try acrossAllReaders(fileSubject, imageSubject) { $0.layout.sizeFlags }
        #expect(sizeFlags == MultiPayloadEnumDescriptorBaseline.multiPayloadEnumTest.layoutSizeFlags)
    }

    // MARK: - Methods (resolved runtime data)

    @Test func mangledTypeName() async throws {
        let (fileSubject, imageSubject) = try loadDescriptors()
        let rawString = try acrossAllContexts(fileSubject, imageSubject) { descriptor, context in
            try descriptor.mangledTypeName(in: context).rawString
        }
        #expect(rawString == MultiPayloadEnumDescriptorBaseline.multiPayloadEnumTest.mangledTypeNameRawString)
    }

    @Test func contents() async throws {
        let (fileSubject, imageSubject) = try loadDescriptors()
        let count = try acrossAllContexts(fileSubject, imageSubject) { descriptor, context in
            try descriptor.contents(in: context).count
        }
        #expect(count == MultiPayloadEnumDescriptorBaseline.multiPayloadEnumTest.contentsCount)
    }

    @Test func payloadSpareBits() async throws {
        let (fileSubject, imageSubject) = try loadDescriptors()
        let count = try acrossAllContexts(fileSubject, imageSubject) { descriptor, context in
            try descriptor.payloadSpareBits(in: context).count
        }
        #expect(count == MultiPayloadEnumDescriptorBaseline.multiPayloadEnumTest.payloadSpareBitsCount)
    }

    @Test func payloadSpareBitMaskByteOffset() async throws {
        let (fileSubject, imageSubject) = try loadDescriptors()
        let result = try acrossAllContexts(fileSubject, imageSubject) { descriptor, context in
            try descriptor.payloadSpareBitMaskByteOffset(in: context)
        }
        #expect(result == MultiPayloadEnumDescriptorBaseline.multiPayloadEnumTest.payloadSpareBitMaskByteOffset)
    }

    @Test func payloadSpareBitMaskByteCount() async throws {
        let (fileSubject, imageSubject) = try loadDescriptors()
        let result = try acrossAllContexts(fileSubject, imageSubject) { descriptor, context in
            try descriptor.payloadSpareBitMaskByteCount(in: context)
        }
        #expect(result == MultiPayloadEnumDescriptorBaseline.multiPayloadEnumTest.payloadSpareBitMaskByteCount)
    }

    // MARK: - Derived bit-twiddling accessors (reader-independent)

    @Test func contentsSizeInWord() async throws {
        let (fileSubject, imageSubject) = try loadDescriptors()
        let result = try acrossAllReaders(fileSubject, imageSubject) { $0.contentsSizeInWord }
        #expect(result == MultiPayloadEnumDescriptorBaseline.multiPayloadEnumTest.contentsSizeInWord)
    }

    @Test func flags() async throws {
        let (fileSubject, imageSubject) = try loadDescriptors()
        let result = try acrossAllReaders(fileSubject, imageSubject) { $0.flags }
        #expect(result == MultiPayloadEnumDescriptorBaseline.multiPayloadEnumTest.flags)
    }

    @Test func usesPayloadSpareBits() async throws {
        let (fileSubject, imageSubject) = try loadDescriptors()
        let result = try acrossAllReaders(fileSubject, imageSubject) { $0.usesPayloadSpareBits }
        #expect(result == MultiPayloadEnumDescriptorBaseline.multiPayloadEnumTest.usesPayloadSpareBits)
    }

    @Test func sizeFlagsIndex() async throws {
        let (fileSubject, imageSubject) = try loadDescriptors()
        let result = try acrossAllReaders(fileSubject, imageSubject) { $0.sizeFlagsIndex }
        #expect(result == MultiPayloadEnumDescriptorBaseline.multiPayloadEnumTest.sizeFlagsIndex)
    }

    @Test func payloadSpareBitMaskByteCountIndex() async throws {
        let (fileSubject, imageSubject) = try loadDescriptors()
        let result = try acrossAllReaders(fileSubject, imageSubject) { $0.payloadSpareBitMaskByteCountIndex }
        #expect(result == MultiPayloadEnumDescriptorBaseline.multiPayloadEnumTest.payloadSpareBitMaskByteCountIndex)
    }

    @Test func payloadSpareBitsIndex() async throws {
        let (fileSubject, imageSubject) = try loadDescriptors()
        let result = try acrossAllReaders(fileSubject, imageSubject) { $0.payloadSpareBitsIndex }
        #expect(result == MultiPayloadEnumDescriptorBaseline.multiPayloadEnumTest.payloadSpareBitsIndex)
    }

    @Test func actualSize() async throws {
        let (fileSubject, imageSubject) = try loadDescriptors()
        let result = try acrossAllReaders(fileSubject, imageSubject) { $0.actualSize }
        #expect(result == MultiPayloadEnumDescriptorBaseline.multiPayloadEnumTest.actualSize)
    }
}
