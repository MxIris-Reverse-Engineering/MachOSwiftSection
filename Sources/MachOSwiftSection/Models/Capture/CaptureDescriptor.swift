import Foundation
import MachOKit
import MachOBase

/// A record in `__swift5_capture`: the layout of one closure context or box —
/// what it holds, and how the runtime recovers generic metadata from it.
///
/// A Swift closure that captures anything is a heap object whose contents are
/// otherwise opaque: reflection can reach the object but nothing in the
/// object says what its words mean. This descriptor is that missing key. Its
/// heap metadata (``HeapLocalVariableMetadata``) points here, and the
/// descriptor lists one mangled type per captured value, in context order.
///
/// The second list answers a different question. A closure inside a generic
/// function needs its type arguments at runtime, but those are not ordinary
/// captures — they arrive as bindings at the head of the context, or must be
/// projected out of a captured value's own metadata. Each
/// ``MetadataSourceRecord`` pairs a type with the recipe for recovering it;
/// this library reports the recipe verbatim and does not interpret it (see
/// that type's documentation).
///
/// The descriptor is variable-length and the section is a sequence of them,
/// walked by size, exactly like `__swift5_fieldmd`:
///
/// ```
/// numberOfCaptureTypes, numberOfMetadataSources, numberOfBindings   (3 × UInt32)
/// CaptureTypeRecord    × numberOfCaptureTypes                       (4 bytes each)
/// MetadataSourceRecord × numberOfMetadataSources                    (8 bytes each)
/// ```
///
/// Mirrors `swift::reflection::CaptureDescriptor`
/// (`swift/RemoteInspection/Records.h`).
@LocatableLayoutWrapping
public struct CaptureDescriptor: TopLevelDescriptor {
    public struct Layout: LayoutProtocol {
        /// Number of captured values, and hence of trailing
        /// ``CaptureTypeRecord``s.
        public let numberOfCaptureTypes: UInt32
        /// Number of trailing ``MetadataSourceRecord``s.
        public let numberOfMetadataSources: UInt32
        /// Number of generic metadata / witness table words the runtime
        /// writes at the head of the context before the captured values
        /// begin. Nothing trails the descriptor for these — the count is the
        /// whole fact.
        public let numberOfBindings: UInt32
    }
}

extension CaptureDescriptor {
    /// The two trailing counts as `Int`, for the arithmetic below.
    private var captureTypeCount: Int { layout.numberOfCaptureTypes.cast() }
    private var metadataSourceCount: Int { layout.numberOfMetadataSources.cast() }

    /// Total length in bytes of the descriptor including both trailing
    /// arrays, which is how the section walk advances to the next one.
    public var actualSize: Int {
        MemoryLayout<Layout>.size
            + captureTypeCount * MemoryLayout<CaptureTypeRecord.Layout>.size
            + metadataSourceCount * MemoryLayout<MetadataSourceRecord.Layout>.size
    }

    /// Location of the first ``CaptureTypeRecord``, in the same coordinate
    /// space as ``offset``.
    public var captureTypeRecordsOffset: Int {
        offset + MemoryLayout<Layout>.size
    }

    /// Location of the first ``MetadataSourceRecord``, in the same coordinate
    /// space as ``offset``.
    public var metadataSourceRecordsOffset: Int {
        captureTypeRecordsOffset + captureTypeCount * MemoryLayout<CaptureTypeRecord.Layout>.size
    }
}

// MARK: - MachO Reading

extension CaptureDescriptor {
    public func captureTypeRecords<MachO: MachOSwiftSectionRepresentableWithCache>(in machO: MachO) throws -> [CaptureTypeRecord] {
        guard captureTypeCount > 0 else { return [] }
        return try machO.readWrapperElements(offset: captureTypeRecordsOffset, numberOfElements: captureTypeCount)
    }

    public func metadataSourceRecords<MachO: MachOSwiftSectionRepresentableWithCache>(in machO: MachO) throws -> [MetadataSourceRecord] {
        guard metadataSourceCount > 0 else { return [] }
        return try machO.readWrapperElements(offset: metadataSourceRecordsOffset, numberOfElements: metadataSourceCount)
    }
}

extension CaptureDescriptor {
    public func captureTypeRecords() throws -> [CaptureTypeRecord] {
        guard captureTypeCount > 0 else { return [] }
        return try asPointer.readWrapperElements(offset: MemoryLayout<Layout>.size, numberOfElements: captureTypeCount)
    }

    public func metadataSourceRecords() throws -> [MetadataSourceRecord] {
        guard metadataSourceCount > 0 else { return [] }
        let offsetFromStart = MemoryLayout<Layout>.size + captureTypeCount * MemoryLayout<CaptureTypeRecord.Layout>.size
        return try asPointer.readWrapperElements(offset: offsetFromStart, numberOfElements: metadataSourceCount)
    }
}

// MARK: - ReadingContext Support

extension CaptureDescriptor {
    public func captureTypeRecords<Context: ReadingContext>(in context: Context) throws -> [CaptureTypeRecord] {
        guard captureTypeCount > 0 else { return [] }
        return try context.readWrapperElements(at: try context.addressFromOffset(captureTypeRecordsOffset), numberOfElements: captureTypeCount)
    }

    public func metadataSourceRecords<Context: ReadingContext>(in context: Context) throws -> [MetadataSourceRecord] {
        guard metadataSourceCount > 0 else { return [] }
        return try context.readWrapperElements(at: try context.addressFromOffset(metadataSourceRecordsOffset), numberOfElements: metadataSourceCount)
    }
}
