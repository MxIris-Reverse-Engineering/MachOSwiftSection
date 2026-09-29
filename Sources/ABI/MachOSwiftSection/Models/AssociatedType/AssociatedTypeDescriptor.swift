import Foundation
import MachOKit
import MachOBase

@LocatableLayoutWrapping
public struct AssociatedTypeDescriptor: ResolvableLocatableLayoutWrapper {
    public struct Layout: LayoutProtocol {
        public let conformingTypeName: RelativeDirectPointer<MangledName>
        public let protocolTypeName: RelativeDirectPointer<MangledName>
        public let numAssociatedTypes: UInt32
        public let associatedTypeRecordSize: UInt32
    }
}

extension AssociatedTypeDescriptor {
    public func conformingTypeName(in machO: some MachOSwiftSectionRepresentableWithCache) throws -> MangledName {
        return try layout.conformingTypeName.resolve(from: offset(of: \.conformingTypeName), in: machO)
    }

    public func protocolTypeName(in machO: some MachOSwiftSectionRepresentableWithCache) throws -> MangledName {
        return try layout.protocolTypeName.resolve(from: offset(of: \.protocolTypeName), in: machO)
    }

    public func associatedTypeRecords(in machO: some MachOSwiftSectionRepresentableWithCache) throws -> [AssociatedTypeRecord] {
        return try machO.readWrapperElements(offset: offset + layoutSize, numberOfElements: layout.numAssociatedTypes.cast())
    }
}

extension AssociatedTypeDescriptor {
    public func conformingTypeName() throws -> MangledName {
        return try layout.conformingTypeName.resolve(from: pointer(of: \.conformingTypeName))
    }

    public func protocolTypeName() throws -> MangledName {
        return try layout.protocolTypeName.resolve(from: pointer(of: \.protocolTypeName))
    }

    public func associatedTypeRecords() throws -> [AssociatedTypeRecord] {
        return try asPointer.readWrapperElements(offset: layoutSize, numberOfElements: layout.numAssociatedTypes.cast())
    }
}

extension AssociatedTypeDescriptor: TopLevelDescriptor {
    public var actualSize: Int { layoutSize + (layout.numAssociatedTypes * layout.associatedTypeRecordSize).cast() }
}

// MARK: - ReadingContext Support

extension AssociatedTypeDescriptor {
    public func conformingTypeName(in context: some ReadingContext) throws -> MangledName {
        return try layout.conformingTypeName.resolve(at: try context.addressFromOffset(offset(of: \.conformingTypeName)), in: context)
    }

    public func protocolTypeName(in context: some ReadingContext) throws -> MangledName {
        return try layout.protocolTypeName.resolve(at: try context.addressFromOffset(offset(of: \.protocolTypeName)), in: context)
    }

    public func associatedTypeRecords(in context: some ReadingContext) throws -> [AssociatedTypeRecord] {
        return try context.readWrapperElements(at: try context.addressFromOffset(offset + layoutSize), numberOfElements: layout.numAssociatedTypes.cast())
    }
}
