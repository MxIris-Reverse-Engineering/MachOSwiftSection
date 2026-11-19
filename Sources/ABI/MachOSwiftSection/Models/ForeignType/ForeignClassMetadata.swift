import Foundation
import MachOKit
import MachOBase

@ResolvableLocatableLayoutWrapper
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
