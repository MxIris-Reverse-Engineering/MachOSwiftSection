import Foundation
import MachOKit
import MachOBase

@ResolvableLocatableLayoutWrapper
public struct TypeContextDescriptor: TypeContextDescriptorProtocol {
    public struct Layout: TypeContextDescriptorLayout {
        public let flags: ContextDescriptorFlags
        public let parent: RelativeContextPointer
        public let name: RelativeDirectPointer<String>
        public let accessFunctionPtr: RelativeDirectPointer<MetadataAccessorFunction>
        public let fieldDescriptor: RelativeDirectPointer<FieldDescriptor>
    }
}

// MARK: - ReadingContext Support

extension TypeContextDescriptor {
    public func enumDescriptor(in context: some ReadingContext) throws -> EnumDescriptor? {
        guard layout.flags.kind == .enum else { return nil }
        return try context.readWrapperElement(at: try context.addressFromOffset(offset)) as EnumDescriptor
    }

    public func structDescriptor(in context: some ReadingContext) throws -> StructDescriptor? {
        guard layout.flags.kind == .struct else { return nil }
        return try context.readWrapperElement(at: try context.addressFromOffset(offset)) as StructDescriptor
    }

    public func classDescriptor(in context: some ReadingContext) throws -> ClassDescriptor? {
        guard layout.flags.kind == .class else { return nil }
        return try context.readWrapperElement(at: try context.addressFromOffset(offset)) as ClassDescriptor
    }
}
