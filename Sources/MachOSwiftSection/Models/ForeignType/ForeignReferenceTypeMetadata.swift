import Foundation
import MachOBase

@LocatableLayoutWrapping
public struct ForeignReferenceTypeMetadata: MetadataProtocol {
    public struct Layout: ForeignReferenceTypeMetadataLayout {
        public let kind: StoredPointer
        public let descriptor: Pointer<ClassDescriptor>
        public let reserved: StoredPointer
    }
}

extension ForeignReferenceTypeMetadata {
    public func classDescriptor(in machO: some MachOSwiftSectionRepresentableWithCache) throws -> ClassDescriptor {
        try layout.descriptor.resolve(in: machO)
    }

    public func classDescriptor() throws -> ClassDescriptor {
        try layout.descriptor.resolve()
    }
}

// MARK: - ReadingContext Support

extension ForeignReferenceTypeMetadata {
    public func classDescriptor<Context: ReadingContext>(in context: Context) throws -> ClassDescriptor {
        try layout.descriptor.resolve(in: context)
    }
}
