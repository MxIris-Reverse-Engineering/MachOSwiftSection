import Foundation
import MachOKit
import MachOFoundation
import MachOSwiftSectionMacro

public struct AssociatedTypeDescriptor: ResolvableLocatableLayoutWrapper {
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


@MachOImageAllMembersGenerator
extension AssociatedTypeDescriptor {
    
    public func conformingTypeName(in machOFile: MachOFile) throws -> MangledName {
        return try layout.conformingTypeName.resolve(from: offset(of: \.conformingTypeName), in: machOFile)
    }
    
    //@MachOImageGenerator
    public func protocolTypeName(in machOFile: MachOFile) throws -> MangledName {
        return try layout.protocolTypeName.resolve(from: offset(of: \.protocolTypeName), in: machOFile)
    }
    
    //@MachOImageGenerator
    public func associatedTypeRecords(in machOFile: MachOFile) throws -> [AssociatedTypeRecord] {
        return try machOFile.readElements(offset: offset + layoutSize, numberOfElements: layout.numAssociatedTypes.cast())
    }
    
    public var size: Int {
        layoutSize + (layout.numAssociatedTypes * layout.associatedTypeRecordSize).cast()
    }
}
