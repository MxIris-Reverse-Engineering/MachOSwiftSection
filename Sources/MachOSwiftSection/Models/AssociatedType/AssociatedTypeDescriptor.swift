import Foundation
import MachOKit
import MachOFoundation
import MachOMacro

public struct AssociatedTypeDescriptor: ResolvableLocatableLayoutWrapper {
    public struct Layout: Sendable {
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
    public func conformingTypeName<MachO: MachORepresentableWithCache & MachOReadable>(in machOFile: MachO) throws -> MangledName {
        return try layout.conformingTypeName.resolve(from: offset(of: \.conformingTypeName), in: machOFile)
    }

    public func protocolTypeName<MachO: MachORepresentableWithCache & MachOReadable>(in machOFile: MachO) throws -> MangledName {
        return try layout.protocolTypeName.resolve(from: offset(of: \.protocolTypeName), in: machOFile)
    }

    public func associatedTypeRecords<MachO: MachORepresentableWithCache & MachOReadable>(in machOFile: MachO) throws -> [AssociatedTypeRecord] {
        return try machOFile.readWrapperElements(offset: offset + layoutSize, numberOfElements: layout.numAssociatedTypes.cast())
    }
}

extension AssociatedTypeDescriptor: TopLevelDescriptor {
    public var actualSize: Int { layoutSize + (layout.numAssociatedTypes * layout.associatedTypeRecordSize).cast() }
}
