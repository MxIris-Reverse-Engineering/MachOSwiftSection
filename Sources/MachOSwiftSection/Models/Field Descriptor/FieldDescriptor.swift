import Foundation
import MachOKit

public struct FieldDescriptor: LayoutWrapperWithOffset {
    public struct Layout {
        public let mangledTypeName: RelativeOffset
        public let superclass: RelativeOffset
        public let kind: FieldDescriptorKind
        public let fieldRecordSize: UInt16
        public let numFields: UInt32
    }

    public let offset: Int

    public var layout: Layout

    public init(offset: Int, layout: Layout) {
        self.offset = offset
        self.layout = layout
    }
}

extension FieldDescriptor {
    
    public func mangledTypeName(in machO: MachOFile) throws -> String? {
        return try machO.makeSymbolicMangledNameStringRef(address(of: \.mangledTypeName))
    }

    public func records(in machO: MachOFile) throws -> [FieldRecord] {
        guard layout.fieldRecordSize != 0 else { return [] }
        let offset = offset + MemoryLayout<FieldDescriptor.Layout>.size
        let size = MemoryLayout<FieldRecord.Layout>.size
        let headerStartOffset = machO.headerStartOffset
        let sequence: DataSequence<FieldRecord.Layout> = try machO.fileHandle.readDataSequence(offset: numericCast(offset + headerStartOffset), numberOfElements: .init(layout.numFields))
        return sequence.enumerated().map { .init(offset: offset + size * $0, layout: $1) }
    }
}
