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

// MARK: - Deprecated Mach-O and pointer forms

extension AssociatedTypeDescriptor {
    @available(*, deprecated, message: "Pass a ReadingContext: conformingTypeName(in: machO.context).")
    public func conformingTypeName(in machO: some MachOSwiftSectionRepresentableWithCache) throws -> MangledName {
        try conformingTypeName(in: machO.context)
    }

    @available(*, deprecated, message: "Pass a ReadingContext: protocolTypeName(in: machO.context).")
    public func protocolTypeName(in machO: some MachOSwiftSectionRepresentableWithCache) throws -> MangledName {
        try protocolTypeName(in: machO.context)
    }

    @available(*, deprecated, message: "Pass a ReadingContext: associatedTypeRecords(in: machO.context).")
    public func associatedTypeRecords(in machO: some MachOSwiftSectionRepresentableWithCache) throws -> [AssociatedTypeRecord] {
        try associatedTypeRecords(in: machO.context)
    }

    @available(*, deprecated, message: "Pass a ReadingContext: conformingTypeName(in: .inProcess).")
    public func conformingTypeName() throws -> MangledName {
        try conformingTypeName(in: InProcessContext.shared)
    }

    @available(*, deprecated, message: "Pass a ReadingContext: protocolTypeName(in: .inProcess).")
    public func protocolTypeName() throws -> MangledName {
        try protocolTypeName(in: InProcessContext.shared)
    }

    @available(*, deprecated, message: "Pass a ReadingContext: associatedTypeRecords(in: .inProcess).")
    public func associatedTypeRecords() throws -> [AssociatedTypeRecord] {
        try associatedTypeRecords(in: InProcessContext.shared)
    }
}
