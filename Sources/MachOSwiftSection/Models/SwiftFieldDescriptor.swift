import Foundation
@_spi(Support) import MachOKit

public struct SwiftFieldDescriptor: LayoutWrapper {
    public struct Layout {
        public let mangledTypeName: Int32
        public let superclass: Int32
        public let kind: UInt16
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

extension SwiftFieldDescriptor {
    
    public func mangledTypeName(in machO: MachOFile) -> String? {
        let address = Int(layout.mangledTypeName) + offset + machO.headerStartOffset
        return machO.fileHandle.readString(offset: numericCast(address))
    }
    
    public var kind: SwiftFieldDescriptorKind {
        return SwiftFieldDescriptorKind(rawValue: layout.kind) ?? .unknown
    }

    public func records(in machO: MachOFile) -> [SwiftFieldRecord] {
        guard layout.fieldRecordSize != 0 else { return [] }
        let offset = offset + MemoryLayout<SwiftFieldDescriptor.Layout>.size
        let size = MemoryLayout<SwiftFieldRecord.Layout>.size
        let headerStartOffset = machO.headerStartOffset
        let sequence: DataSequence<SwiftFieldRecord.Layout> = machO.fileHandle.readDataSequence(offset: numericCast(offset + headerStartOffset), numberOfElements: .init(layout.numFields))
        return sequence.enumerated().map { .init(offset: offset + size * $0, layout: $1) }
    }
}
