import Foundation
import Testing
import MachOFoundation
@testable import MachOSwiftSection
@testable import MachOTestingSupport

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
final class MultiPayloadEnumDescriptorTests: MachOSwiftSectionFixtureTests, FixtureSuite, @unchecked Sendable {
    static let testedTypeName = "MultiPayloadEnumDescriptor"
    static var registeredTestMethodNames: Set<String> {
        MultiPayloadEnumDescriptorBaseline.registeredTestMethodNames
    }

    private func loadDescriptors() throws -> (file: MultiPayloadEnumDescriptor, image: MultiPayloadEnumDescriptor) {
        let file = try BaselineFixturePicker.multiPayloadEnumDescriptor_MultiPayloadEnumTest(in: machOFile)
        let image = try BaselineFixturePicker.multiPayloadEnumDescriptor_MultiPayloadEnumTest(in: machOImage)
        return (file: file, image: image)
    }

    // MARK: - Layout / offset

    @Test func offset() async throws {
        let (fileSubject, imageSubject) = try loadDescriptors()
        let result = try acrossAllReaders(
            file: { fileSubject.offset },
            image: { imageSubject.offset }
        )
        #expect(result == MultiPayloadEnumDescriptorBaseline.multiPayloadEnumTest.offset)
    }

    @Test func layout() async throws {
        let (fileSubject, imageSubject) = try loadDescriptors()
        let sizeFlags = try acrossAllReaders(
            file: { fileSubject.layout.sizeFlags },
            image: { imageSubject.layout.sizeFlags }
        )
        #expect(sizeFlags == MultiPayloadEnumDescriptorBaseline.multiPayloadEnumTest.layoutSizeFlags)
    }

    // MARK: - Methods (resolved runtime data)

    @Test func mangledTypeName() async throws {
        let (fileSubject, imageSubject) = try loadDescriptors()
        let rawString = try acrossAllReaders(
            file: { try fileSubject.mangledTypeName(in: machOFile).rawString },
            image: { try imageSubject.mangledTypeName(in: machOImage).rawString }
        )
        #expect(rawString == MultiPayloadEnumDescriptorBaseline.multiPayloadEnumTest.mangledTypeNameRawString)

        // ReadingContext-based overload also exercised.
        let fileCtxRaw = try fileSubject.mangledTypeName(in: fileContext).rawString
        let imageCtxRaw = try imageSubject.mangledTypeName(in: imageContext).rawString
        #expect(fileCtxRaw == rawString)
        #expect(imageCtxRaw == rawString)
    }

    @Test func contents() async throws {
        let (fileSubject, imageSubject) = try loadDescriptors()
        let count = try acrossAllReaders(
            file: { try fileSubject.contents(in: machOFile).count },
            image: { try imageSubject.contents(in: machOImage).count }
        )
        #expect(count == MultiPayloadEnumDescriptorBaseline.multiPayloadEnumTest.contentsCount)

        // ReadingContext overloads.
        let fileCtxCount = try fileSubject.contents(in: fileContext).count
        let imageCtxCount = try imageSubject.contents(in: imageContext).count
        #expect(fileCtxCount == count)
        #expect(imageCtxCount == count)
    }

    @Test func payloadSpareBits() async throws {
        let (fileSubject, imageSubject) = try loadDescriptors()
        let count = try acrossAllReaders(
            file: { try fileSubject.payloadSpareBits(in: machOFile).count },
            image: { try imageSubject.payloadSpareBits(in: machOImage).count }
        )
        #expect(count == MultiPayloadEnumDescriptorBaseline.multiPayloadEnumTest.payloadSpareBitsCount)
    }

    @Test func payloadSpareBitMaskByteOffset() async throws {
        let (fileSubject, imageSubject) = try loadDescriptors()
        let result = try acrossAllReaders(
            file: { try fileSubject.payloadSpareBitMaskByteOffset(in: machOFile) },
            image: { try imageSubject.payloadSpareBitMaskByteOffset(in: machOImage) }
        )
        #expect(result == MultiPayloadEnumDescriptorBaseline.multiPayloadEnumTest.payloadSpareBitMaskByteOffset)
    }

    @Test func payloadSpareBitMaskByteCount() async throws {
        let (fileSubject, imageSubject) = try loadDescriptors()
        let result = try acrossAllReaders(
            file: { try fileSubject.payloadSpareBitMaskByteCount(in: machOFile) },
            image: { try imageSubject.payloadSpareBitMaskByteCount(in: machOImage) }
        )
        #expect(result == MultiPayloadEnumDescriptorBaseline.multiPayloadEnumTest.payloadSpareBitMaskByteCount)
    }

    // MARK: - Derived bit-twiddling accessors (reader-independent)

    @Test func contentsSizeInWord() async throws {
        let (fileSubject, imageSubject) = try loadDescriptors()
        let result = try acrossAllReaders(
            file: { fileSubject.contentsSizeInWord },
            image: { imageSubject.contentsSizeInWord }
        )
        #expect(result == MultiPayloadEnumDescriptorBaseline.multiPayloadEnumTest.contentsSizeInWord)
    }

    @Test func flags() async throws {
        let (fileSubject, imageSubject) = try loadDescriptors()
        let result = try acrossAllReaders(
            file: { fileSubject.flags },
            image: { imageSubject.flags }
        )
        #expect(result == MultiPayloadEnumDescriptorBaseline.multiPayloadEnumTest.flags)
    }

    @Test func usesPayloadSpareBits() async throws {
        let (fileSubject, imageSubject) = try loadDescriptors()
        let result = try acrossAllReaders(
            file: { fileSubject.usesPayloadSpareBits },
            image: { imageSubject.usesPayloadSpareBits }
        )
        #expect(result == MultiPayloadEnumDescriptorBaseline.multiPayloadEnumTest.usesPayloadSpareBits)
    }

    @Test func sizeFlagsIndex() async throws {
        let (fileSubject, imageSubject) = try loadDescriptors()
        let result = try acrossAllReaders(
            file: { fileSubject.sizeFlagsIndex },
            image: { imageSubject.sizeFlagsIndex }
        )
        #expect(result == MultiPayloadEnumDescriptorBaseline.multiPayloadEnumTest.sizeFlagsIndex)
    }

    @Test func payloadSpareBitMaskByteCountIndex() async throws {
        let (fileSubject, imageSubject) = try loadDescriptors()
        let result = try acrossAllReaders(
            file: { fileSubject.payloadSpareBitMaskByteCountIndex },
            image: { imageSubject.payloadSpareBitMaskByteCountIndex }
        )
        #expect(result == MultiPayloadEnumDescriptorBaseline.multiPayloadEnumTest.payloadSpareBitMaskByteCountIndex)
    }

    @Test func payloadSpareBitsIndex() async throws {
        let (fileSubject, imageSubject) = try loadDescriptors()
        let result = try acrossAllReaders(
            file: { fileSubject.payloadSpareBitsIndex },
            image: { imageSubject.payloadSpareBitsIndex }
        )
        #expect(result == MultiPayloadEnumDescriptorBaseline.multiPayloadEnumTest.payloadSpareBitsIndex)
    }

    @Test func actualSize() async throws {
        let (fileSubject, imageSubject) = try loadDescriptors()
        let result = try acrossAllReaders(
            file: { fileSubject.actualSize },
            image: { imageSubject.actualSize }
        )
        #expect(result == MultiPayloadEnumDescriptorBaseline.multiPayloadEnumTest.actualSize)
    }
}
