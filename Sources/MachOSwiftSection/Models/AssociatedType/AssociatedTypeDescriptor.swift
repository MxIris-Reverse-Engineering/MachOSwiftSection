import Foundation
import MachOKit

public struct AssociatedTypeDescriptor: LocatableLayoutWrapper {
    public struct Layout {
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
    
    public func conformingTypeName(in machOFile: MachOFile) throws -> MangledName {
        return try layout.conformingTypeName.resolve(from: fileOffset(of: \.conformingTypeName), in: machOFile)
    }
    
    public func protocolTypeName(in machOFile: MachOFile) throws -> MangledName {
        return try layout.protocolTypeName.resolve(from: fileOffset(of: \.protocolTypeName), in: machOFile)
    }
    
    public func associatedTypeRecords(in machOFile: MachOFile) throws -> [AssociatedTypeRecord] {
        return try machOFile.readElements(offset: offset + layoutSize, numberOfElements: layout.numAssociatedTypes.cast())
    }
    
    public var size: Int {
        layoutSize + (layout.numAssociatedTypes * layout.associatedTypeRecordSize).cast()
    }
}
