import Foundation
import MachOKit

public struct FieldRecord: LayoutWrapperWithOffset {
    public struct Layout {
        public let flags: UInt32
        public let mangledTypeName: Int32
        public let fieldName: Int32
    }

    public let offset: Int

    public var layout: Layout

    public init(offset: Int, layout: Layout) {
        self.offset = offset
        self.layout = layout
    }
    
    public func offset<T>(of keyPath: KeyPath<Layout, T>) -> Int {
        return offset + layoutOffset(of: keyPath)
    }
}

extension FieldRecord {
    public var flags: FieldRecordFlags {
        return FieldRecordFlags(rawValue: layout.flags)
    }

    public func mangledTypeName(in machO: MachOFile) throws -> String {
        let offset = offset(of: \.mangledTypeName) + Int(layout.mangledTypeName)
        return try machO.makeSymbolicMangledNameStringRef(numericCast(offset))
    }

    public func fieldName(in machO: MachOFile) throws -> String? {
        let offset = offset(of: \.fieldName) + Int(layout.fieldName)
        return machO.fileHandle.readString(offset: numericCast(offset + machO.headerStartOffset))
    }
}





