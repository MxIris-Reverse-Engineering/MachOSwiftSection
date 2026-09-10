import Foundation
import Testing
import MachOFoundation
@testable import MachOSwiftSection
@testable import MachOTestingSupport
import MachOFixtureSupport

/// Fixture-based Suite for `PropertyDescriptor`.
///
/// A property descriptor sits in no `__swift5_*` section, so the four
/// carriers are picked by `…vpMV` symbol name — one per shape a descriptor
/// can take: the module's shared trivial one, a struct stored property whose
/// offset is inline in the header, a generic struct's stored property whose
/// offset only lives in the metadata, and a resilient class's settable
/// computed property. Every assertion runs across both readers.
@Suite
final class PropertyDescriptorTests: MachOSwiftSectionFixtureTests, FixtureSuite, @unchecked Sendable {
    static let testedTypeName = "PropertyDescriptor"
    static var registeredTestMethodNames: Set<String> {
        PropertyDescriptorBaseline.registeredTestMethodNames
    }

    private struct Shape {
        let label: String
        let file: PropertyDescriptor
        let image: PropertyDescriptor
        let expected: PropertyDescriptorBaseline.Entry
    }

    private func allShapes() throws -> [Shape] {
        let fileDescriptors = try KeyPathFixtureDescriptors(in: machOFile)
        let imageDescriptors = try KeyPathFixtureDescriptors(in: machOImage)
        return [
            Shape(
                label: "trivial",
                file: fileDescriptors.trivial,
                image: imageDescriptors.trivial,
                expected: PropertyDescriptorBaseline.trivial
            ),
            Shape(
                label: "inlineStoredOffset",
                file: fileDescriptors.inlineStoredOffset,
                image: imageDescriptors.inlineStoredOffset,
                expected: PropertyDescriptorBaseline.inlineStoredOffset
            ),
            Shape(
                label: "unresolvedFieldOffset",
                file: fileDescriptors.unresolvedFieldOffset,
                image: imageDescriptors.unresolvedFieldOffset,
                expected: PropertyDescriptorBaseline.unresolvedFieldOffset
            ),
            Shape(
                label: "computedSettable",
                file: fileDescriptors.computedSettable,
                image: imageDescriptors.computedSettable,
                expected: PropertyDescriptorBaseline.computedSettable
            ),
        ]
    }

    @Test func offset() async throws {
        for shape in try allShapes() {
            let result = try acrossAllReaders(
                file: { shape.file.offset },
                image: { shape.image.offset }
            )
            #expect(result == shape.expected.offset, "\(shape.label)")
        }
    }

    @Test func layout() async throws {
        for shape in try allShapes() {
            let result = try acrossAllReaders(
                file: { shape.file.layout.header.rawValue },
                image: { shape.image.layout.header.rawValue }
            )
            #expect(result == shape.expected.headerRawValue, "\(shape.label)")
        }
    }

    @Test func header() async throws {
        for shape in try allShapes() {
            let result = try acrossAllReaders(
                file: { shape.file.header.rawValue },
                image: { shape.image.header.rawValue }
            )
            #expect(result == shape.expected.headerRawValue, "\(shape.label)")
            #expect(shape.file.header == shape.file.layout.header, "\(shape.label)")
        }
    }

    @Test func isTrivial() async throws {
        for shape in try allShapes() {
            let result = try acrossAllReaders(
                file: { shape.file.isTrivial },
                image: { shape.image.isTrivial }
            )
            #expect(result == shape.expected.isTrivial, "\(shape.label)")
        }
        // Exactly one of the four carriers is the shared trivial descriptor;
        // if that stopped being true the picker would be reading the wrong
        // symbols and every other assertion here would be vacuous.
        let trivialCount = try allShapes().filter(\.file.isTrivial).count
        #expect(trivialCount == 1)
    }

    @Test func bodySize() async throws {
        for shape in try allShapes() {
            let result = try acrossAllReaders(
                file: { shape.file.bodySize },
                image: { shape.image.bodySize }
            )
            #expect(result == shape.expected.bodySize, "\(shape.label)")
        }
    }

    @Test func size() async throws {
        for shape in try allShapes() {
            let result = try acrossAllReaders(
                file: { shape.file.size },
                image: { shape.image.size }
            )
            #expect(result == shape.expected.size, "\(shape.label)")
            #expect(result == MemoryLayout<PropertyDescriptor.Layout>.size + shape.expected.bodySize, "\(shape.label)")
        }
    }

    @Test func bodyOffset() async throws {
        for shape in try allShapes() {
            let result = try acrossAllReaders(
                file: { shape.file.bodyOffset },
                image: { shape.image.bodyOffset }
            )
            #expect(result == shape.expected.bodyOffset, "\(shape.label)")
            #expect(result == shape.expected.offset + MemoryLayout<PropertyDescriptor.Layout>.size, "\(shape.label)")
        }
    }

    @Test func inlineStoredFieldOffset() async throws {
        for shape in try allShapes() {
            let result = try acrossAllReaders(
                file: { shape.file.inlineStoredFieldOffset?.rawValue },
                image: { shape.image.inlineStoredFieldOffset?.rawValue }
            )
            #expect(result == shape.expected.inlineStoredFieldOffsetRawValue, "\(shape.label)")
        }
    }

    /// The stored offset, reading the body word where the header only carried
    /// a sentinel. The in-process leg reads through a pointer rather than a
    /// file offset and must agree on the value.
    @Test func storedFieldOffset() async throws {
        for shape in try allShapes() {
            let result = try acrossAllReaders(
                file: { try shape.file.storedFieldOffset(in: machOFile)?.rawValue },
                image: { try shape.image.storedFieldOffset(in: machOImage)?.rawValue },
                inProcess: { try shape.image.asPointerWrapper(in: self.machOImage).storedFieldOffset()?.rawValue }
            )
            #expect(result == shape.expected.storedFieldOffsetRawValue, "\(shape.label)")

            let fromContext = try acrossAllContexts(
                file: { try shape.file.storedFieldOffset(in: fileContext)?.rawValue },
                image: { try shape.image.storedFieldOffset(in: imageContext)?.rawValue }
            )
            #expect(fromContext == shape.expected.storedFieldOffsetRawValue, "\(shape.label)")
        }
    }

    /// The computed body's getter offset is pure relative-pointer arithmetic,
    /// so it is identical across readers and pinned as a literal.
    @Test func computedPropertyBody() async throws {
        for shape in try allShapes() {
            let result = try acrossAllReaders(
                file: { try shape.file.computedPropertyBody(in: machOFile)?.getterOffset },
                image: { try shape.image.computedPropertyBody(in: machOImage)?.getterOffset }
            )
            #expect(result == shape.expected.computedGetterOffset, "\(shape.label)")

            let fromContext = try acrossAllContexts(
                file: { try shape.file.computedPropertyBody(in: fileContext)?.getterOffset },
                image: { try shape.image.computedPropertyBody(in: imageContext)?.getterOffset }
            )
            #expect(fromContext == shape.expected.computedGetterOffset, "\(shape.label)")

            // The in-process leg reads through a pointer, so its offsets are
            // pointers too; only the relative words can be compared directly.
            let inProcessBody = try shape.image.asPointerWrapper(in: machOImage).computedPropertyBody()
            #expect(inProcessBody?.getter.relativeOffset == (try shape.file.computedPropertyBody(in: machOFile))?.getter.relativeOffset, "\(shape.label)")
        }
    }
}
