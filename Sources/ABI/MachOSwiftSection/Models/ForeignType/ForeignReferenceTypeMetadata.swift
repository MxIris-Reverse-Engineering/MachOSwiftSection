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

// MARK: - ReadingContext Support

extension ForeignReferenceTypeMetadata {
    public func classDescriptor(in context: some ReadingContext) throws -> ClassDescriptor {
        try layout.descriptor.resolve(in: context)
    }
}

// MARK: - Deprecated Mach-O and pointer forms

extension ForeignReferenceTypeMetadata {
    @available(*, deprecated, message: "Pass a ReadingContext: classDescriptor(in: machO.context).")
    public func classDescriptor(in machO: some MachOSwiftSectionRepresentableWithCache) throws -> ClassDescriptor {
        try classDescriptor(in: machO.context)
    }

    @available(*, deprecated, message: "Pass a ReadingContext: classDescriptor(in: .inProcess).")
    public func classDescriptor() throws -> ClassDescriptor {
        try classDescriptor(in: InProcessContext.shared)
    }
}
