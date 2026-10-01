import Foundation
import MachOKit
import MachOBase

public protocol FinalClassMetadataProtocol: HeapMetadataProtocol {}

// MARK: - ReadingContext Support

extension FinalClassMetadataProtocol where Layout: FinalClassMetadataLayout {
    public func fieldOffsets(for descriptor: ClassDescriptor? = nil, in context: some ReadingContext) throws -> [StoredPointer] {
        guard let descriptor = try descriptor ?? layout.descriptor.resolve(in: context) else { return [] }
        guard descriptor.fieldOffsetVectorOffset != .zero else { return [] }
        let fieldOffsetsOffset = offset.offseting(of: StoredPointer.self, numbersOfElements: descriptor.fieldOffsetVectorOffset.cast())
        return try context.readElements(at: try context.addressFromOffset(fieldOffsetsOffset), numberOfElements: descriptor.numFields.cast())
    }

    public func descriptor(in context: some ReadingContext) throws -> ClassDescriptor? {
        try layout.descriptor.resolve(in: context)
    }
}

// MARK: - Deprecated Mach-O and pointer forms

extension FinalClassMetadataProtocol where Layout: FinalClassMetadataLayout {
    @available(*, deprecated, message: "Pass a ReadingContext: fieldOffsets(in: machO.context).")
    public func fieldOffsets(for descriptor: ClassDescriptor? = nil, in machO: some MachOSwiftSectionRepresentableWithCache) throws -> [StoredPointer] {
        try fieldOffsets(for: descriptor, in: machO.context)
    }

    @available(*, deprecated, message: "Pass a ReadingContext: descriptor(in: machO.context).")
    public func descriptor(in machO: some MachOSwiftSectionRepresentableWithCache) throws -> ClassDescriptor? {
        try descriptor(in: machO.context)
    }

    @available(*, deprecated, message: "Pass a ReadingContext: fieldOffsets(in: .inProcess).")
    public func fieldOffsets(for descriptor: ClassDescriptor? = nil) throws -> [StoredPointer] {
        try fieldOffsets(for: descriptor, in: InProcessContext.shared)
    }

    @available(*, deprecated, message: "Pass a ReadingContext: descriptor(in: .inProcess).")
    public func descriptor() throws -> ClassDescriptor? {
        try descriptor(in: InProcessContext.shared)
    }
}
