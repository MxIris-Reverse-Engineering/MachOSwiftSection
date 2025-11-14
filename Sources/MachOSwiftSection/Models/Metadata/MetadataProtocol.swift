import Foundation
import MachOKit
import MachOExtensions
import MachOReading
import MachOUtilitiesC

public protocol MetadataProtocol: ResolvableLocatableLayoutWrapper where Layout: MetadataLayout {
    associatedtype HeaderType: ResolvableLocatableLayoutWrapper = TypeMetadataHeader
}

extension MetadataProtocol {
    public static func create(_ type: Any.Type) -> (machO: MachOImage, metadata: Self)? {
        let ptr = unsafeBitCast(type, to: UnsafeRawPointer.self)

        guard let machHeader = dyld_image_header_containing_address(ptr) else { return nil }
        
        let machO = MachOImage(ptr: machHeader)

        let layout: Layout = unsafeBitCast(type, to: UnsafePointer<Layout>.self).pointee

        return (machO, self.init(layout: layout, offset: ptr.int - machO.ptr.int))
    }
}

extension MetadataProtocol {
    public var kind: MetadataKind {
        .enumeratedMetadataKind(layout.kind)
    }

    public func asFullMetadata<MachO: MachOSwiftSectionRepresentableWithCache>(in machO: MachO) throws -> FullMetadata<Self> {
        try FullMetadata<Self>.resolve(from: offset - HeaderType.layoutSize, in: machO)
    }
}

extension MetadataProtocol where HeaderType: TypeMetadataHeaderBaseProtocol {
    public func valueWitnesses<MachO: MachOSwiftSectionRepresentableWithCache>(in machO: MachO) throws -> ValueWitnessTable {
        let fullMetadata = try asFullMetadata(in: machO)
        return try fullMetadata.layout.header.valueWitnesses.resolve(in: machO)
    }
}
