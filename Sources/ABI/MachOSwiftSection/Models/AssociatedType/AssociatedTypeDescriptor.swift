import Foundation
import MachOKit
import MachOBase

@ResolvableLocatableLayoutWrapper
public struct AssociatedTypeDescriptor {
    public struct Layout: LayoutProtocol {
        public let conformingTypeName: RelativeDirectPointer<MangledName>
        public let protocolTypeName: RelativeDirectPointer<MangledName>
        public let numAssociatedTypes: UInt32
        public let associatedTypeRecordSize: UInt32
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
