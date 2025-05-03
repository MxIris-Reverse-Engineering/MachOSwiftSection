import Foundation
@_spi(Support) import MachOKit

public struct TypeContextDescriptor: TypeContextDescriptorProtocol {
    public struct Layout: TypeContextDescriptorLayout {
        public let flags: ContextDescriptorFlags
        public let parent: RelativeOffset
        public let name: RelativeDirectPointer<String>
        public let accessFunctionPtr: RelativeOffset
        public let fieldDescriptor: RelativeDirectPointer<FieldDescriptor>
    }

    public let offset: Int

    public var layout: Layout

    public init(offset: Int, layout: Layout) {
        self.offset = offset
        self.layout = layout
    }
}

extension TypeContextDescriptor {
    public func enumDescriptor(in machO: MachOFile) -> EnumDescriptor? {
        guard layout.flags.kind == .enum else { return nil }
        let layout: EnumDescriptor.Layout = machO.fileHandle.read(offset: numericCast(offset + machO.headerStartOffset))
        return EnumDescriptor(offset: offset, layout: layout)
    }
}
