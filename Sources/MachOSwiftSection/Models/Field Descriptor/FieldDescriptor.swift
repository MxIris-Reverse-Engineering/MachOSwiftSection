import Foundation
import MachOKit

public struct FieldDescriptor: LocatableLayoutWrapper, ResolvableElement {
    public struct Layout {
        public let mangledTypeName: RelativeOffset
        public let superclass: RelativeOffset
        public let kind: FieldDescriptorKind
        public let fieldRecordSize: UInt16
        public let numFields: UInt32
    }

    public let offset: Int

    public var layout: Layout

    public init(layout: Layout, offset: Int) {
        self.offset = offset
        self.layout = layout
    }
}

extension FieldDescriptor {
    public func mangledTypeName(in machO: MachOFile) throws -> String? {
        return try machO.readSymbolicMangledName(at: resolvedRelativeOffset(of: \.mangledTypeName))
    }

    public func records(in machO: MachOFile) throws -> [FieldRecord] {
        guard layout.fieldRecordSize != 0 else { return [] }
        let offset = offset + MemoryLayout<FieldDescriptor.Layout>.size
        return try machO.readElements(offset: offset, numberOfElements: layout.numFields.cast())
    }
}
