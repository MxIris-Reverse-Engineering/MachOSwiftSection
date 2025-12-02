import Foundation
import MachOKit
import MachOFoundation

public struct AssociatedTypeDescriptor: ResolvableLocatableLayoutWrapper {
    public struct Layout: LayoutProtocol {
        public let conformingTypeName: RelativeDirectPointer<MangledName>
        public let protocolTypeName: RelativeDirectPointer<MangledName>
        public let numAssociatedTypes: UInt32
        public let associatedTypeRecordSize: UInt32
    }

    public var layout: Layout
    public let offset: Int

    public init(layout: Layout, offset: Int) {
        self.offset = offset
        self.layout = layout
    }
}

extension AssociatedTypeDescriptor {
    public func conformingTypeName<MachO: MachOSwiftSectionRepresentableWithCache>(in machO: MachO) throws -> MangledName {
        return try layout.conformingTypeName.resolve(from: offset(of: \.conformingTypeName), in: machO)
    }

    public func protocolTypeName<MachO: MachOSwiftSectionRepresentableWithCache>(in machO: MachO) throws -> MangledName {
        return try layout.protocolTypeName.resolve(from: offset(of: \.protocolTypeName), in: machO)
    }

    public func associatedTypeRecords<MachO: MachOSwiftSectionRepresentableWithCache>(in machO: MachO) throws -> [AssociatedTypeRecord] {
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
