import Foundation
import MachOKit

public struct FieldRecord: LocatableLayoutWrapper {
    public struct Layout {
        public let flags: FieldRecordFlags
        public let mangledTypeName: RelativeDirectPointer<MangledName>
        public let fieldName: RelativeDirectPointer<String>
    }

    public let offset: Int

    public var layout: Layout

    public init(layout: Layout, offset: Int) {
        self.offset = offset
        self.layout = layout
    }

    public func offset<T>(of keyPath: KeyPath<Layout, T>) -> Int {
        return offset + layoutOffset(of: keyPath)
    }
}

extension FieldRecord {
    public func mangledTypeName(in machO: MachOFile) throws -> MangledName {
        return try layout.mangledTypeName.resolve(from: offset(of: \.mangledTypeName), in: machO)
    }

    public func fieldName(in machO: MachOFile) throws -> String {
        return try layout.fieldName.resolve(from: offset(of: \.fieldName), in: machO)
    }
}
