import Foundation
import MachOKit
import MachOFoundation
import MachOSwiftSectionMacro

public struct FieldDescriptor: ResolvableLocatableLayoutWrapper {
    public struct Layout {
        public let mangledTypeName: RelativeDirectPointer<MangledName>
        public let superclass: RelativeOffset
        public let kind: UInt16
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

@MachOImageAllMembersGenerator
extension FieldDescriptor {
    
    public var kind: FieldDescriptorKind { .init(rawValue: layout.kind)! }
    
    public func mangledTypeName(in machOFile: MachOFile) throws -> MangledName {
        return try layout.mangledTypeName.resolve(from: offset(of: \.mangledTypeName), in: machOFile)
    }

    public func records(in machOFile: MachOFile) throws -> [FieldRecord] {
        guard layout.fieldRecordSize != 0 else { return [] }
        let offset = offset + MemoryLayout<FieldDescriptor.Layout>.size
        return try machOFile.readElements(offset: offset, numberOfElements: layout.numFields.cast())
    }
}
