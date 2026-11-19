import Foundation
import MachOKit
import MachOBase

@ResolvableLocatableLayoutWrapper
public struct ForeignReferenceTypeMetadata: MetadataProtocol {
    public struct Layout: ForeignReferenceTypeMetadataLayout {
        public let kind: StoredPointer
        public let descriptor: Pointer<ClassDescriptor>
        public let reserved: StoredPointer
    }
}

// MARK: - ReadingContext Support

extension ForeignReferenceTypeMetadata {
    public func classDescriptor(in context: some ReadingContext) throws -> ClassDescriptor {
        try layout.descriptor.resolve(in: context)
    }
}
