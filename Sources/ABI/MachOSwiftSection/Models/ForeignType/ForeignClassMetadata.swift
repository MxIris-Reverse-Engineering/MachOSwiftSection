import Foundation
import MachOBase

@LocatableLayoutWrapping
public struct ForeignClassMetadata: MetadataProtocol {
    public struct Layout: ForeignClassMetadataLayout {
        public let kind: StoredPointer
        public let descriptor: Pointer<ClassDescriptor>
        public let superclass: ConstMetadataPointer<ForeignClassMetadata>
        public let reserved: StoredPointer
    }
}

// MARK: - ReadingContext Support

extension ForeignClassMetadata {
    public func classDescriptor(in context: some ReadingContext) throws -> ClassDescriptor {
        try layout.descriptor.resolve(in: context)
    }
}

// MARK: - Deprecated Mach-O and pointer forms

extension ForeignClassMetadata {
    @available(*, deprecated, message: "Pass a ReadingContext: classDescriptor(in: machO.context).")
    public func classDescriptor(in machO: some MachOSwiftSectionRepresentableWithCache) throws -> ClassDescriptor {
        try classDescriptor(in: machO.context)
    }

    @available(*, deprecated, message: "Pass a ReadingContext: classDescriptor(in: .inProcess).")
    public func classDescriptor() throws -> ClassDescriptor {
        try classDescriptor(in: InProcessContext.shared)
    }
}
