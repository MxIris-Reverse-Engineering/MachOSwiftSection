import Foundation
import MachOKit
import MachOExtensions
import MachOReading
import DyldPrivate

public protocol MetadataProtocol: ResolvableLocatableLayoutWrapper where Layout: MetadataLayout {
    associatedtype HeaderType: ResolvableLocatableLayoutWrapper = TypeMetadataHeader
}

extension MetadataProtocol {
    public static func createInMachO(_ type: Any.Type) throws -> (machO: MachOImage, metadata: Self)? {
        let ptr = unsafeBitCast(type, to: UnsafeRawPointer.self)
        guard let machHeader = dyld_image_header_containing_address(ptr) else { return nil }
        let machO = MachOImage(ptr: machHeader)
        let layout: Layout = unsafeBitCast(type, to: UnsafePointer<Layout>.self).pointee
        return (machO, self.init(layout: layout, offset: ptr.int - machO.ptr.int))
    }

    public static func createInProcess(_ type: Any.Type) throws -> Self {
        let ptr = unsafeBitCast(type, to: UnsafeRawPointer.self)
        return try ptr.readWrapperElement()
    }
}

extension MetadataProtocol {
    public var kind: MetadataKind {
        .enumeratedMetadataKind(layout.kind)
    }
}

extension MetadataProtocol where HeaderType: TypeMetadataHeaderBaseProtocol {
    public func asFullMetadata<MachO: MachOSwiftSectionRepresentableWithCache>(in machO: MachO) throws -> FullMetadata<Self> {
        try FullMetadata<Self>.resolve(from: offset - HeaderType.layoutSize, in: machO)
    }

    public func valueWitnesses<MachO: MachOSwiftSectionRepresentableWithCache>(in machO: MachO) throws -> ValueWitnessTable {
        let fullMetadata = try asFullMetadata(in: machO)
        return try fullMetadata.layout.header.valueWitnesses.resolve(in: machO)
    }
}

extension MetadataProtocol where HeaderType: TypeMetadataHeaderBaseProtocol {
    public func asFullMetadata() throws -> FullMetadata<Self> {
        try FullMetadata<Self>.resolve(from: asPointer - HeaderType.layoutSize)
    }

    public func valueWitnesses() throws -> ValueWitnessTable {
        let fullMetadata = try asFullMetadata()
        return try fullMetadata.layout.header.valueWitnesses.resolve()
    }
}
