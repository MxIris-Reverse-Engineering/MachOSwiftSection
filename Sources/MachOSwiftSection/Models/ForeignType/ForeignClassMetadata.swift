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

extension ForeignClassMetadata {
    public func classDescriptor(in machO: some MachOSwiftSectionRepresentableWithCache) throws -> ClassDescriptor {
        try layout.descriptor.resolve(in: machO)
    }

    public func classDescriptor() throws -> ClassDescriptor {
        try layout.descriptor.resolve()
    }
}

// MARK: - ReadingContext Support

extension ForeignClassMetadata {
    public func classDescriptor<Context: ReadingContext>(in context: Context) throws -> ClassDescriptor {
        try layout.descriptor.resolve(in: context)
    }
}
