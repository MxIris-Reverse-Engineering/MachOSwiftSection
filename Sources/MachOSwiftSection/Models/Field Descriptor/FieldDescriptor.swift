import Foundation
import MachOKit

public struct FieldDescriptor: LocatableLayoutWrapper, ResolvableElement {
    public struct Layout {
        public let mangledTypeName: RelativeDirectPointer<MangledName>
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
    public func mangledTypeName(in machOFile: MachOFile) throws -> MangledName {
        return try layout.mangledTypeName.resolve(from: fileOffset(of: \.mangledTypeName), in: machOFile)
    }

    public func records(in machOFile: MachOFile) throws -> [FieldRecord] {
        guard layout.fieldRecordSize != 0 else { return [] }
        let offset = offset + MemoryLayout<FieldDescriptor.Layout>.size
        return try machOFile.readElements(offset: offset, numberOfElements: layout.numFields.cast())
    }
}
