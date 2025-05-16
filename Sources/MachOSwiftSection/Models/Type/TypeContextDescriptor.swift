import Foundation
import MachOKit

public struct TypeContextDescriptor: TypeContextDescriptorProtocol {
    public struct Layout: TypeContextDescriptorLayout {
        public let flags: ContextDescriptorFlags
        public let parent: RelativeIndirectablePointer<ContextDescriptorWrapper?, SignedPointer<ContextDescriptorWrapper?>>
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
    public func enumDescriptor(in machOFile: MachOFile) throws -> EnumDescriptor? {
        guard layout.flags.kind == .enum else { return nil }
        let layout: EnumDescriptor.Layout = try machOFile.readElement(offset: offset)
        return EnumDescriptor(layout: layout, offset: offset)
    }
}
