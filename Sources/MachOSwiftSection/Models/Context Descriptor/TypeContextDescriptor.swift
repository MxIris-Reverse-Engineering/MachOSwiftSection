import Foundation
@_spi(Support) import MachOKit

public struct TypeContextDescriptor: TypeContextDescriptorProtocol {
    public struct Layout: TypeContextDescriptorLayoutProtocol {
        public let context: ContextDescriptor.Layout
        public let name: RelativeDirectPointer
        public let accessFunctionPtr: RelativeDirectPointer
        public let fieldDescriptor: RelativeDirectPointer
    }

    public let offset: Int

    public var layout: Layout

    public init(offset: Int, layout: Layout) {
        self.offset = offset
        self.layout = layout
    }
}

extension TypeContextDescriptor {
    public func name(in machO: MachOFile) -> String? {
        let offset = offset(of: \.name) + Int(layout.name)
        return machO.fileHandle.readString(offset: numericCast(offset + machO.headerStartOffset))
    }

    public func parent(in machO: MachOFile) -> TypeContextDescriptor? {
        guard layout.context.parent != 0 else { return nil }
        return machO.swift._readTypeContextDescriptor(from: numericCast(offset(of: \.context.parent) + Int(layout.context.parent)), in: machO)
    }

    public func fieldDescriptor(in machO: MachOFile) -> FieldDescriptor {
        let offset = offset(of: \.fieldDescriptor) + Int(layout.fieldDescriptor)
        let layout: FieldDescriptor.Layout = machO.fileHandle.read(offset: numericCast(offset + machO.headerStartOffset))
        return FieldDescriptor(offset: offset, layout: layout)
    }
}
