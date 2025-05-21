import Foundation
import MachOKit

public struct TypeContextDescriptor: TypeContextDescriptorProtocol {
    public struct Layout: TypeContextDescriptorLayout {
        public let flags: ContextDescriptorFlags
        public let parent: RelativeContextPointer<ContextDescriptorWrapper?>
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
        return try machOFile.readElement(offset: offset) as EnumDescriptor
    }

    public func structDescriptor(in machOFile: MachOFile) throws -> StructDescriptor? {
        guard layout.flags.kind == .struct else { return nil }
        return try machOFile.readElement(offset: offset) as StructDescriptor
    }

    public func classDescriptor(in machOFile: MachOFile) throws -> ClassDescriptor? {
        guard layout.flags.kind == .class else { return nil }
        return try machOFile.readElement(offset: offset) as ClassDescriptor
    }
}
