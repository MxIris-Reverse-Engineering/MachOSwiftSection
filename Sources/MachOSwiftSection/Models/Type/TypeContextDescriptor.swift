import Foundation
import MachOKit

public struct TypeContextDescriptor: TypeContextDescriptorProtocol {
    public struct Layout: TypeContextDescriptorLayout {
        public let flags: ContextDescriptorFlags
        public let parent: RelativeDirectPointer<ContextDescriptor>
        public let name: RelativeDirectPointer<String>
        public let accessFunctionPtr: RelativeOffset
        public let fieldDescriptor: RelativeDirectPointer<FieldDescriptor>
    }

    public let offset: Int

    public var layout: Layout

    public init(layout: Layout, offset: Int) {
        self.offset = offset
        self.layout = layout
    }
}

extension TypeContextDescriptor {
    public func enumDescriptor(in machO: MachOFile) throws -> EnumDescriptor? {
        guard layout.flags.kind == .enum else { return nil }
        let layout: EnumDescriptor.Layout = try machO.fileHandle.read(offset: numericCast(offset + machO.headerStartOffset))
        return EnumDescriptor(layout: layout, offset: offset)
    }
}
