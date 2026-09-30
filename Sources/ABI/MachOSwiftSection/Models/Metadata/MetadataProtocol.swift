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
    public var isAnyExistentialType: Bool {
        switch kind {
        case .existentialMetatype,
             .existential:
            return true
        default:
            return false
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
        // The metadata's own address first: in process that conversion is
        // what rejects a null metadata, and the header sits in front of it.
        let metadataAddress = try context.addressFromOffset(offset)
        return try FullMetadata<Self>.resolve(at: context.advanceAddress(metadataAddress, by: -HeaderType.layoutSize), in: context)
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
        // Converted before the switch, so a null metadata throws in process
        // whatever its kind.
        let address = try context.addressFromOffset(offset)
        switch kind {
        case .class:
            let cls = try AnyClassMetadataObjCInterop.resolve(at: address, in: context)
            if cls.isPureObjC {
                return nil
            } else {
                return try .class(ClassMetadataObjCInterop.resolve(at: address, in: context).descriptor(in: context)!)
            }
        case .struct,
             .enum,
             .optional:
            return try ValueMetadata.resolve(at: address, in: context).descriptor(in: context).asTypeContextDescriptorWrapper
        case .foreignClass:
            return try .class(ForeignClassMetadata.resolve(at: address, in: context).classDescriptor(in: context))
        case .foreignReferenceType:
            return try .class(ForeignReferenceTypeMetadata.resolve(at: address, in: context).classDescriptor(in: context))
        default:
            return nil
        }
    }
}

// MARK: - Deprecated Mach-O and pointer forms

extension MetadataProtocol {
    @available(*, deprecated, message: "Pass a ReadingContext: asMetadataWrapper(in: machO.context).")
    public func asMetadataWrapper(in machO: some MachOSwiftSectionRepresentableWithCache) throws -> MetadataWrapper {
        try asMetadataWrapper(in: machO.context)
    }

    @available(*, deprecated, message: "Pass a ReadingContext: asMetadataWrapper(in: .inProcess).")
    public func asMetadataWrapper() throws -> MetadataWrapper {
        try asMetadataWrapper(in: InProcessContext.shared)
    }

    @available(*, deprecated, message: "Pass a ReadingContext: asMetadata(in: machO.context).")
    public func asMetadata(in machO: some MachOSwiftSectionRepresentableWithCache) throws -> Metadata {
        try asMetadata(in: machO.context)
    }

    @available(*, deprecated, message: "Pass a ReadingContext: asMetadata(in: .inProcess).")
    public func asMetadata() throws -> Metadata {
        try asMetadata(in: InProcessContext.shared)
    }
}

extension MetadataProtocol where HeaderType: TypeMetadataHeaderBaseProtocol {
    @available(*, deprecated, message: "Pass a ReadingContext: asFullMetadata(in: machO.context).")
    public func asFullMetadata(in machO: some MachOSwiftSectionRepresentableWithCache) throws -> FullMetadata<Self> {
        try asFullMetadata(in: machO.context)
    }

    @available(*, deprecated, message: "Pass a ReadingContext: valueWitnesses(in: machO.context).")
    public func valueWitnesses(in machO: some MachOSwiftSectionRepresentableWithCache) throws -> ValueWitnessTable {
        try valueWitnesses(in: machO.context)
    }

    @available(*, deprecated, message: "Pass a ReadingContext: asFullMetadata(in: .inProcess).")
    public func asFullMetadata() throws -> FullMetadata<Self> {
        try asFullMetadata(in: InProcessContext.shared)
    }

    @available(*, deprecated, message: "Pass a ReadingContext: valueWitnesses(in: .inProcess).")
    public func valueWitnesses() throws -> ValueWitnessTable {
        try valueWitnesses(in: InProcessContext.shared)
    }

    @available(*, deprecated, message: "Pass a ReadingContext: typeLayout(in: machO.context).")
    public func typeLayout(in machO: some MachOSwiftSectionRepresentableWithCache) throws -> TypeLayout {
        try typeLayout(in: machO.context)
    }

    @available(*, deprecated, message: "Pass a ReadingContext: typeLayout(in: .inProcess).")
    public func typeLayout() throws -> TypeLayout {
        try typeLayout(in: InProcessContext.shared)
    }

    @available(*, deprecated, message: "Pass a ReadingContext: typeContextDescriptorWrapper(in: .inProcess).")
    public func typeContextDescriptorWrapper() throws -> TypeContextDescriptorWrapper? {
        try typeContextDescriptorWrapper(in: InProcessContext.shared)
    }

    @available(*, deprecated, message: "Pass a ReadingContext: typeContextDescriptorWrapper(in: machO.context).")
    public func typeContextDescriptorWrapper(in machO: some MachOSwiftSectionRepresentableWithCache) throws -> TypeContextDescriptorWrapper? {
        try typeContextDescriptorWrapper(in: machO.context)
    }
}
