import Foundation
import MachOFoundation

public struct ForeignClassMetadata: MetadataProtocol {
    public struct Layout: ForeignClassMetadataLayout {
        public let kind: StoredPointer
        public let descriptor: Pointer<ClassDescriptor>
        public let superclass: ConstMetadataPointer<ForeignClassMetadata>
        public let reserved: StoredPointer
    }

    public var layout: Layout

    public let offset: Int

    public init(layout: Layout, offset: Int) {
        self.layout = layout
        self.offset = offset
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
