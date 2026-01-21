import Foundation
import MachOKit
import MachOExtensions
import MachOReading
import DyldPrivate

public protocol MetadataProtocol<HeaderType>: ResolvableLocatableLayoutWrapper where Layout: MetadataLayout {
    associatedtype HeaderType: ResolvableLocatableLayoutWrapper = TypeMetadataHeader
}

extension MetadataProtocol {
    public static func createInMachO(_ type: Any.Type) throws -> (machO: MachOImage, metadata: Self)? {
        let ptr = unsafeBitCast(type, to: UnsafeRawPointer.self)
        guard let machO = MachOImage.image(for: ptr) else { return nil }
        let layout: Layout = unsafeBitCast(type, to: UnsafePointer<Layout>.self).pointee
        return (machO, self.init(layout: layout, offset: ptr.bitPattern.int - machO.ptr.bitPattern.int))
    }

    public static func createInProcess(_ type: Any.Type) throws -> Self {
        let ptr = unsafeBitCast(type, to: UnsafeRawPointer.self)
        return try ptr.readWrapperElement()
    }
}

extension MetadataProtocol {
    public func asMetadataWrapper(in machO: some MachOSwiftSectionRepresentableWithCache) throws -> MetadataWrapper {
        try .resolve(from: offset, in: machO)
    }

    public func asMetadataWrapper() throws -> MetadataWrapper {
        try .resolve(from: .init(bitPattern: offset))
    }
}

extension MetadataProtocol {
    public var kind: MetadataKind {
        .enumeratedMetadataKind(layout.kind)
    }
}

extension MetadataProtocol {
    public func asMetatype<T>() throws -> T.Type {
        let ptr = try asPointer
        return unsafeBitCast(ptr, to: T.Type.self)
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

extension MetadataProtocol where HeaderType: TypeMetadataHeaderBaseProtocol {
    public var isAnyExistentialType: Bool {
        switch kind {
        case .existentialMetatype,
             .existential:
            return true
        default:
            return false
        }
    }

    public func typeLayout(in machO: some MachOSwiftSectionRepresentableWithCache) throws -> TypeLayout {
        try valueWitnesses(in: machO).typeLayout
    }

    public func typeLayout() throws -> TypeLayout {
        try valueWitnesses().typeLayout
    }

    public func typeContextDescriptorWrapper() throws -> TypeContextDescriptorWrapper? {
        let ptr = try asPointer
        switch kind {
        case .class:
            let cls = try AnyClassMetadataObjCInterop.resolve(from: ptr)
            if cls.isPureObjC {
                return nil
            } else {
                return try .class(ClassMetadataObjCInterop.resolve(from: ptr).descriptor()!)
            }
        case .struct,
             .enum,
             .optional:
            return try ValueMetadata.resolve(from: ptr).descriptor().asTypeContextDescriptorWrapper
        case .foreignClass:
            return try .class(ForeignClassMetadata.resolve(from: ptr).classDescriptor())
        case .foreignReferenceType:
            return try .class(ForeignReferenceTypeMetadata.resolve(from: ptr).classDescriptor())
        default:
            return nil
        }
    }
    
    public func typeContextDescriptorWrapper(in machO: some MachOSwiftSectionRepresentableWithCache) throws -> TypeContextDescriptorWrapper? {
        switch kind {
        case .class:
            let cls = try AnyClassMetadataObjCInterop.resolve(from: offset, in: machO)
            if cls.isPureObjC {
                return nil
            } else {
                return try .class(ClassMetadataObjCInterop.resolve(from: offset, in: machO).descriptor(in: machO)!)
            }
        case .struct,
             .enum,
             .optional:
            return try ValueMetadata.resolve(from: offset, in: machO).descriptor(in: machO).asTypeContextDescriptorWrapper
        case .foreignClass:
            return try .class(ForeignClassMetadata.resolve(from: offset, in: machO).classDescriptor(in: machO))
        case .foreignReferenceType:
            return try .class(ForeignReferenceTypeMetadata.resolve(from: offset, in: machO).classDescriptor(in: machO))
        default:
            return nil
        }
    }
}
