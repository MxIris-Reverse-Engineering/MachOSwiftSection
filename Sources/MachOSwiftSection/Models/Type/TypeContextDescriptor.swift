import Foundation
import MachOKit
import MachOFoundation

public struct TypeContextDescriptor: TypeContextDescriptorProtocol {
    public struct Layout: TypeContextDescriptorLayout {
        public let flags: ContextDescriptorFlags
        public let parent: RelativeContextPointer
        public let name: RelativeDirectPointer<String>
        public let accessFunctionPtr: RelativeDirectPointer<MetadataAccessor>
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
    public func enumDescriptor<MachO: MachOSwiftSectionRepresentableWithCache>(in machO: MachO) throws -> EnumDescriptor? {
        guard layout.flags.kind == .enum else { return nil }
        return try machO.readWrapperElement(offset: offset) as EnumDescriptor
    }

    public func structDescriptor<MachO: MachOSwiftSectionRepresentableWithCache>(in machO: MachO) throws -> StructDescriptor? {
        guard layout.flags.kind == .struct else { return nil }
        return try machO.readWrapperElement(offset: offset) as StructDescriptor
    }

    public func classDescriptor<MachO: MachOSwiftSectionRepresentableWithCache>(in machO: MachO) throws -> ClassDescriptor? {
        guard layout.flags.kind == .class else { return nil }
        return try machO.readWrapperElement(offset: offset) as ClassDescriptor
    }

    public func enumDescriptor() throws -> EnumDescriptor? {
        guard layout.flags.kind == .enum else { return nil }
        return try asPointer.readWrapperElement() as EnumDescriptor
    }

    public func structDescriptor() throws -> StructDescriptor? {
        guard layout.flags.kind == .struct else { return nil }
        return try asPointer.readWrapperElement() as StructDescriptor
    }

    public func classDescriptor() throws -> ClassDescriptor? {
        guard layout.flags.kind == .class else { return nil }
        return try asPointer.readWrapperElement() as ClassDescriptor
    }
}
