import Foundation
import MachOKit
import MachOReading

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
    
    public func asMetadata(in machO: some MachOSwiftSectionRepresentableWithCache) throws -> Metadata {
        try .resolve(from: offset, in: machO)
    }
    
    public func asMetadata() throws -> Metadata {
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
    public func asFullMetadata(in machO: some MachOSwiftSectionRepresentableWithCache) throws -> FullMetadata<Self> {
        try FullMetadata<Self>.resolve(from: offset - HeaderType.layoutSize, in: machO)
    }

    public func valueWitnesses(in machO: some MachOSwiftSectionRepresentableWithCache) throws -> ValueWitnessTable {
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

// MARK: - ReadingContext Support

extension MetadataProtocol {
    public func asMetadataWrapper(in context: some ReadingContext) throws -> MetadataWrapper {
        try .resolve(at: try context.addressFromOffset(offset), in: context)
    }

    public func asMetadata(in context: some ReadingContext) throws -> Metadata {
        try .resolve(at: try context.addressFromOffset(offset), in: context)
    }
}

extension MetadataProtocol where HeaderType: TypeMetadataHeaderBaseProtocol {
    public func asFullMetadata(in context: some ReadingContext) throws -> FullMetadata<Self> {
        try FullMetadata<Self>.resolve(at: try context.addressFromOffset(offset - HeaderType.layoutSize), in: context)
    }

    public func valueWitnesses(in context: some ReadingContext) throws -> ValueWitnessTable {
        let fullMetadata = try asFullMetadata(in: context)
        return try fullMetadata.layout.header.valueWitnesses.resolve(in: context)
    }
}

extension MetadataProtocol where HeaderType: TypeMetadataHeaderBaseProtocol {
    public func typeLayout(in context: some ReadingContext) throws -> TypeLayout {
        try valueWitnesses(in: context).typeLayout
    }

    public func typeContextDescriptorWrapper(in context: some ReadingContext) throws -> TypeContextDescriptorWrapper? {
        switch kind {
        case .class:
            let cls = try AnyClassMetadataObjCInterop.resolve(at: try context.addressFromOffset(offset), in: context)
            if cls.isPureObjC {
                return nil
            } else {
                return try .class(ClassMetadataObjCInterop.resolve(at: try context.addressFromOffset(offset), in: context).descriptor(in: context)!)
            }
        case .struct,
             .enum,
             .optional:
            return try ValueMetadata.resolve(at: try context.addressFromOffset(offset), in: context).descriptor(in: context).asTypeContextDescriptorWrapper
        case .foreignClass:
            return try .class(ForeignClassMetadata.resolve(at: try context.addressFromOffset(offset), in: context).classDescriptor(in: context))
        case .foreignReferenceType:
            return try .class(ForeignReferenceTypeMetadata.resolve(at: try context.addressFromOffset(offset), in: context).classDescriptor(in: context))
        default:
            return nil
        }
    }
}
