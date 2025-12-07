import Foundation
import MachOFoundation

public struct ForeignReferenceTypeMetadata: MetadataProtocol {
    public struct Layout: ForeignReferenceTypeMetadataLayout {
        public let kind: StoredPointer
        public let descriptor: Pointer<ClassDescriptor>
        public let reserved: StoredPointer
    }

    public var layout: Layout

    public let offset: Int

    public init(layout: Layout, offset: Int) {
        self.layout = layout
        self.offset = offset
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
